{Adapter, TextMessage, EnterMessage, LeaveMessage, User} = require "../../hubot"
HTTPS = require "https"
{inspect} = require "util"
Connector = require "./connector"
promise = require "./promises"

class HipChat extends Adapter

  constructor: (robot) ->
    super robot
    @logger = robot.logger

  emote: (envelope, strings...) ->
    @send envelope, strings.map((str) -> "/me #{str}")...

  send: (envelope, strings...) ->
    {user, room} = envelope
    user = envelope if not user # pre-2.4.2 style

    target_jid =
      # most common case - we're replying to a user in a room or 1-1
      user?.reply_to or
      # allows user objects to be passed in
      user?.jid or
      if user?.search?(/@/) >= 0
        user # allows user to be a jid string
      else
        room # this will happen if someone uses robot.messageRoom(jid, ...)

    if not target_jid
      return @logger.error "ERROR: Not sure who to send to: envelope=#{inspect envelope}"

    for str in strings
      @connector.message target_jid, str

  topic: (envelope, message) ->
    {user, room} = envelope
    user = envelope if not user # pre-2.4.2 style

    target_jid =
      # most common case - we're replying to a user in a room or 1-1
      user?.reply_to or
      # allows user objects to be passed in
      user?.jid or
      if user?.search?(/@/) >= 0
        user # allows user to be a jid string
      else
        room # this will happen if someone uses robot.messageRoom(jid, ...)

    if not target_jid
      return @logger.error "ERROR: Not sure who to send to: envelope=#{inspect envelope}"

    @connector.topic target_jid, message

  reply: (envelope, strings...) ->
    user = if envelope.user then envelope.user else envelope
    @send envelope, "@#{user.mention_name} #{str}" for str in strings

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

    init = promise()

    connector.onConnect =>
      @logger.info "Connected to #{host} as @#{connector.mention_name}"

      # Provide our name to Hubot
      @robot.name = connector.mention_name

      # Tell Hubot we're connected so it can load scripts
      @emit "connected"

      # Fetch user info
      connector.getRoster (err, users, stanza) =>
        return init.reject err if err
        init.resolve users

      init
        .done (users) =>
          # Save users to brain
          for user in users
            user.id = @userIdFromJid user.jid
            @robot.brain.userForId user.id, user
          # Join requested rooms
          if @options.rooms is "All" or @options.rooms is "@All"
            connector.getRooms (err, rooms, stanza) =>
              if rooms
                for room in rooms
                  @logger.info "Joining #{room.jid}"
                  connector.join room.jid
              else
                @logger.error "Can't list rooms: #{errmsg err}"
          # Join all rooms
          else
            for room_jid in @options.rooms.split ","
              @logger.info "Joining #{room_jid}"
              connector.join room_jid
        .fail (err) =>
          @logger.error "Can't list users: #{errmsg err}" if err

      handleMessage = (opts) =>
        # buffer message events until the roster fetch completes
        # to ensure user data is properly loaded
        init.done =>
          {getAuthor, message, reply_to, room} = opts
          author = getAuthor() or {}
          author.reply_to = reply_to
          author.room = room
          @receive new TextMessage(author, message)

      connector.onMessage (channel, from, message) =>
        # reformat leading @mention name to be like "name: message" which is
        # what hubot expects
        mention_name = connector.mention_name
        regex = new RegExp "^@#{mention_name}\\b", "i"
        message = message.replace regex, "#{mention_name}: "
        handleMessage
          getAuthor: => @robot.brain.userForName(from) or new User(from)
          message: message
          reply_to: channel
          room: @roomNameFromJid(channel)

      connector.onPrivateMessage (from, message) =>
        # remove leading @mention name if present and format the message like
        # "name: message" which is what hubot expects
        mention_name = connector.mention_name
        regex = new RegExp "^@#{mention_name}\\b", "i"
        message = "#{mention_name}: #{message.replace regex, ""}"
        handleMessage
          getAuthor: => @robot.brain.userForId(@userIdFromJid from)
          message: message
          reply_to: from

      changePresence = (PresenceMessage, user_jid, room_jid, currentName) =>
        # buffer presence events until the roster fetch completes
        # to ensure user data is properly loaded
        init.done =>
          user = @robot.brain.userForId(@userIdFromJid(user_jid)) or {}
          if user
            user.room = room_jid
            # If an updated name was sent as part of a presence, update it now
            user.name = currentName if currentName.length
            @receive new PresenceMessage(user)

      connector.onEnter (user_jid, room_jid, currentName) =>
        changePresence EnterMessage, user_jid, room_jid, currentName

      connector.onLeave (user_jid, room_jid) ->
        changePresence LeaveMessage, user_jid, room_jid

      connector.onDisconnect =>
        @logger.info "Disconnected from #{host}"

      connector.onError =>
        @logger.error [].slice.call(arguments).map(inspect).join(", ")

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

errmsg = (err) ->
  err + (if err.stack then '\n' + err.stack else '')

exports.use = (robot) ->
  new HipChat robot
