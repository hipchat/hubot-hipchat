{Adapter, TextMessage} = require "../../hubot"
HTTPS = require "https"
{inspect} = require "util"
Connector = require "./connector"

class HipChat extends Adapter

  constructor: (robot) ->
    super robot
    @logger = robot.logger

  send: (envelope, strings...) ->
    user = null
    room = null
    target_jid = null

    # as of hubot 2.4.2, the first param to send() is an object with 'user'
    # and 'room' data inside. detect the old style here.
    if envelope.reply_to
      user = envelope
    else
      # expand envelope
      {user, room} = envelope

    if user
      # most common case - we're replying to a user in a room or 1-1
      if user.reply_to
        target_jid = user.reply_to
      # allows user objects to be passed in
      else if user.jid
        target_jid = user.jid
      # allows user to be a jid string
      else if user.search /@/ isnt -1
        target_jid = user
    else if room
      # this will happen if someone uses robot.messageRoom(jid, ...)
      target_jid = room

    if not target_jid
      return @logger.error "ERROR: Not sure who to send to. envelope=", envelope

    for str in strings
      @connector.message target_jid, str

  reply: (envelope, strings...) ->
    user = if envelope.user then envelope.user else envelope
    for str in strings
      @send envelope, "@#{user.mention_name} #{str}"

  run: ->
    @options =
      jid:        process.env.HUBOT_HIPCHAT_JID
      password:   process.env.HUBOT_HIPCHAT_PASSWORD
      token:      process.env.HUBOT_HIPCHAT_TOKEN or null
      rooms:      process.env.HUBOT_HIPCHAT_ROOMS or "All"
      host:       process.env.HUBOT_HIPCHAT_HOST or null
      autojoin:   process.env.HUBOT_HIPCHAT_JOIN_ROOMS_ON_INVITE isnt "false"
    @logger.debug "HipChat adapter options: #{JSON.stringify @options}"

    # create Connector object
    connector = new Connector
      jid: @options.jid
      password: @options.password
      host: @options.host
      logger: @logger
    host = if @options.host then @options.host else "hipchat.com"
    @logger.info "Connecting HipChat adapter..."

    connector.onConnect =>
      @logger.info "Connected to #{host} as @#{connector.mention_name}"

      # Provide our name to Hubot
      @robot.name = connector.mention_name

      # Tell Hubot we're connected so it can load scripts
      @emit "connected"

      # Join requested rooms
      if @options.rooms is "All" or @options.rooms is "@All"
        connector.getRooms (err, rooms, stanza) =>
          if rooms
            for room in rooms
              @logger.info "Joining #{room.jid}"
              connector.join room.jid
          else
            @logger.error "Can't list rooms: #{err}"
      else
        for room_jid in @options.rooms.split ","
          @logger.info "Joining #{room_jid}"
          connector.join room_jid

      # Fetch user info
      connector.getRoster (err, users, stanza) =>
        if users
          for user in users
            @robot.brain.userForId @userIdFromJid(user.jid), user
        else
          @logger.error "Can't list users: #{err}"

    connector.onDisconnect =>
      @logger.info "Disconnected from #{host} as @#{connector.mention_name}"

    connector.onError =>
      @logger.error [].slice.call(arguments).map(inspect).join(", ")

    connector.onMessage (channel, from, message) =>
      author = {}
      author.name = from
      author.reply_to = channel
      author.room = @roomNameFromJid(channel)

      # add extra details if this message is from a known user
      author_data = @robot.brain.userForName(from)
      if author_data
        author.name = author_data.name
        author.mention_name = author_data.mention_name
        author.jid = author_data.jid

      # reformat leading @mention name to be like "name: message" which is
      # what hubot expects
      regex = new RegExp("^@#{connector.mention_name}\\b", "i")
      hubot_msg = message.replace(regex, "#{connector.mention_name}: ")

      @receive new TextMessage(author, hubot_msg)

    connector.onPrivateMessage (from, message) =>
      author = {}
      author.reply_to = from

      # add extra details if this message is from a known user
      author_data = @robot.brain.userForId(@userIdFromJid(from))
      if author_data
        author.name = author_data.name
        author.mention_name = author_data.mention_name
        author.jid = author_data.jid

      # remove leading @mention name if present and format the message like
      # "name: message" which is what hubot expects
      regex = new RegExp("^@#{connector.mention_name}\\b", "i")
      message = message.replace(regex, "")
      hubot_msg = "#{connector.mention_name}: #{message}"

      @receive new TextMessage(author, hubot_msg)

    # Join rooms automatically when invited
    connector.onInvite (room_jid, from_jid, message) =>
      action = if @options.autojoin then "joining" else "ignoring"
      @logger.info "Got invite to #{room_jid} from #{from_jid} - #{action}"
      connector.join room_jid if @options.autojoin

    connector.connect()

    @connector = connector

  userIdFromJid: (jid) ->
    try
      jid.match(/^\d+_(\d+)@chat\./)[1]
    catch e
      @logger.error "Bad user JID: #{jid}"

  roomNameFromJid: (jid) ->
    try
      jid.match(/^\d+_(.+)@conf\./)[1]
    catch e
      @logger.error "Bad room JID: #{jid}"

  # Convenience HTTP Methods for posting on behalf of the token'd user
  get: (path, callback) ->
    @request "GET", path, null, callback

  post: (path, body, callback) ->
    @request "POST", path, body, callback

  request: (method, path, body, callback) ->
    @logger.debug "Request:", method, path, body
    host = @options.host or "api.hipchat.com"
    headers = "Host": host

    unless @options.token
      return callback "No API token provided to Hubot", null

    options =
      agent  : false
      host   : host
      port   : 443
      path   : path += "?auth_token=#{@options.token}"
      method : method
      headers: headers

    if method is "POST"
      headers["Content-Type"] = "application/x-www-form-urlencoded"
      options.headers["Content-Length"] = body.length

    request = HTTPS.request options, (response) =>
      data = ""
      response.on "data", (chunk) ->
        data += chunk
      response.on "end", =>
        if response.statusCode >= 400
          @logger.error "HipChat API error: #{response.statusCode}"
        try
          callback null, JSON.parse(data)
        catch err
          callback null, data or { }
      response.on "error", (err) ->
        callback err, null

    if method is "POST"
      request.end(body, "binary")
    else
      request.end()

    request.on "error", (err) =>
      @logger.error err
      @logger.error err.stack if err.stack
      callback err

exports.use = (robot) ->
  new HipChat robot
