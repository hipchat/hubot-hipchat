{Adapter, TextMessage, EnterMessage, LeaveMessage, TopicMessage, User} = require "hubot"
HTTPS = require "https"
{inspect} = require "util"
Connector = require "./connector"
promise = require "./promises"

class HipChat extends Adapter

  constructor: (robot) ->
    super robot
    @logger = robot.logger
    reconnectTimer = null

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

  waitAndReconnect: ->
    if !@reconnectTimer
      delay = Math.round(Math.random() * (20 - 5) + 5)
      @logger.info "Waiting #{delay}s and then retrying..."
      @reconnectTimer = setTimeout () =>
         @logger.info "Attempting to reconnect..."
         delete @reconnectTimer
         @connector.connect()
      , delay * 1000

  run: ->
    @options =
      jid: process.env.HUBOT_HIPCHAT_JID
      password: process.env.HUBOT_HIPCHAT_PASSWORD
      token: process.env.HUBOT_HIPCHAT_TOKEN or null
      rooms: process.env.HUBOT_HIPCHAT_ROOMS or "All"
      rooms_blacklist: process.env.HUBOT_HIPCHAT_ROOMS_BLACKLIST or ""
      rooms_join_public: process.env.HUBOT_HIPCHAT_JOIN_PUBLIC_ROOMS isnt "false"
      host: process.env.HUBOT_HIPCHAT_HOST or null
      bosh: { url: process.env.HUBOT_HIPCHAT_BOSH_URL or null }
      autojoin: process.env.HUBOT_HIPCHAT_JOIN_ROOMS_ON_INVITE isnt "false"
      xmppDomain: process.env.HUBOT_HIPCHAT_XMPP_DOMAIN or null
      reconnect: process.env.HUBOT_HIPCHAT_RECONNECT isnt "false"

    @logger.debug "HipChat adapter options: #{JSON.stringify @options}"

    # create Connector object
    connector = new Connector
      jid: @options.jid
      password: @options.password
      host: @options.host
      logger: @logger
      xmppDomain: @options.xmppDomain
    host = if @options.host then @options.host else "hipchat.com"
    @logger.info "Connecting HipChat adapter..."

    init = promise()

    connector.onTopic (channel, from, message) =>
      @logger.info "Topic change: " + message
      author = getAuthor: => @robot.brain.userForName(from) or new User(from)
      author.room = @roomNameFromJid(channel)
      @receive new TopicMessage(author, message, 'id')


    connector.onDisconnect =>
      @logger.info "Disconnected from #{host}"

      if @options.reconnect
        @waitAndReconnect()

    connector.onError =>
      @logger.error [].slice.call(arguments).map(inspect).join(", ")

      if @options.reconnect
        @waitAndReconnect()

    firstTime = true
    connector.onConnect =>
      @logger.info "Connected to #{host} as @#{connector.mention_name}"

      # Provide our name to Hubot
      @robot.name = connector.mention_name

      # Tell Hubot we're connected so it can load scripts
      if firstTime
        @emit "connected"
        @logger.debug "Sending connected event"

      saveUsers = (users) =>
        # Save users to brain
        for user in users
          user.id = @userIdFromJid user.jid
          # userForId will not merge to an existing user
          if user.id of @robot.brain.data.users
            oldUser = @robot.brain.data.users[user.id]
            for key, value of oldUser
              unless key of user
                user[key] = value
            delete @robot.brain.data.users[user.id]
          @robot.brain.userForId user.id, user

      joinRoom = (jid) =>
        if jid and typeof jid is "object"
          jid = "#{jid.local}@#{jid.domain}"

        if jid in @options.rooms_blacklist.split(",")
          @logger.info "Not joining #{jid} because it is blacklisted"
          return

        @logger.info "Joining #{jid}"
        connector.join jid

      # Fetch user info
      connector.getRoster (err, users, stanza) =>
        return init.reject err if err
        init.resolve users

      init
        .done (users) =>
          saveUsers(users)
          # Join requested rooms
          if @options.rooms is "All" or @options.rooms is "@All"
            connector.getRooms (err, rooms, stanza) =>
              if rooms
                for room in rooms
                  if !@options.rooms_join_public && room.guest_url != ''
                    @logger.info "Not joining #{room.jid} because it is a public room"
                  else
                    joinRoom(room.jid)
              else
                @logger.error "Can't list rooms: #{errmsg err}"
          # Join all rooms
          else
            for room_jid in @options.rooms.split ","
              joinRoom(room_jid)
        .fail (err) =>
          @logger.error "Can't list users: #{errmsg err}" if err

      connector.onRosterChange (users) =>
        saveUsers(users)

      handleMessage = (opts) =>
        # buffer message events until the roster fetch completes
        # to ensure user data is properly loaded
        init.done =>
          {getAuthor, message, reply_to, room} = opts
          author = Object.create(getAuthor()) or {}
          author.reply_to = reply_to
          author.room = room
          @receive new TextMessage(author, message)

      if firstTime
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
          regex = new RegExp "^@?#{mention_name}\\b", "i"
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
      if firstTime
        connector.onEnter (user_jid, room_jid, currentName) =>
          changePresence EnterMessage, user_jid, room_jid, currentName

        connector.onLeave (user_jid, room_jid) ->
          changePresence LeaveMessage, user_jid, room_jid

        connector.onInvite (room_jid, from_jid, message) =>
          action = if @options.autojoin then "joining" else "ignoring"
          @logger.info "Got invite to #{room_jid} from #{from_jid} - #{action}"
          joinRoom(room_jid) if @options.autojoin

      firstTime = false
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
