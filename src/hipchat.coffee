Robot   = require('hubot').Robot
Adapter = require('hubot').Adapter
TextMessage = require('hubot').TextMessage
HTTPS = require 'https'
Wobot = require('wobot').Bot

class HipChat extends Adapter
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
      user = envelope.user
      room = envelope.room

    if user
      # most common case - we're replying to a user in a room or 1-1
      if user.reply_to
        target_jid = user.reply_to
      # allows user objects to be passed in
      else if user.jid
        target_jid = user.jid
      # allows user to be a jid string
      else if user.search /@/ != -1
        target_jid = user
    else if room
      # this will happen if someone uses robot.messageRoom(jid, ...)
      target_jid = room

    if not target_jid
      console.log "ERROR: Not sure who to send to. envelope=", envelope
      return

    for str in strings
      @bot.message target_jid, str

  reply: (envelope, strings...) ->
    user = if envelope.user then envelope.user else envelope
    for str in strings
      @send envelope, "@#{user.mention_name} #{str}"

  run: ->
    self = @
    @options =
      jid:      process.env.HUBOT_HIPCHAT_JID
      password: process.env.HUBOT_HIPCHAT_PASSWORD
      token:    process.env.HUBOT_HIPCHAT_TOKEN or null
      rooms:    process.env.HUBOT_HIPCHAT_ROOMS or "All"
      debug:    process.env.HUBOT_HIPCHAT_DEBUG or false
      host:     process.env.HUBOT_HIPCHAT_HOST or null
    console.log "HipChat adapter options:", @options

    # create Wobot bot object
    bot = new Wobot(
      jid: @options.jid,
      password: @options.password,
      debug: @options.debug == 'true',
      host: @options.host
    )
    console.log "Wobot object:", bot

    bot.onConnect =>
      console.log "Connected to HipChat as @#{bot.mention_name}!"

      # Provide our name to Hubot
      self.robot.name = bot.mention_name

      # Tell Hubot we're connected so it can load scripts
      self.emit "connected"

      # Join requested rooms
      if @options.rooms is "All" or @options.rooms is '@All'
        bot.getRooms (err, rooms, stanza) ->
          if rooms
            for room in rooms
              console.log "Joining #{room.jid}"
              bot.join room.jid
          else
            console.log "Can't list rooms: #{err}"
      else
        for room_jid in @options.rooms.split(',')
          console.log "Joining #{room_jid}"
          bot.join room_jid

      # Fetch user info
      bot.getRoster (err, users, stanza) ->
        if users
          for user in users
            self.userForId self.userIdFromJid(user.jid), user
        else
          console.log "Can't list users: #{err}"

    bot.onError (message) ->
      # If HipChat sends an error, we get the error message from XMPP.
      # Otherwise, we get an Error object from the Node connection.
      if message.message
        console.log "Error talking to HipChat:", message.message
      else
        console.log "Received error from HipChat:", message

    bot.onMessage (channel, from, message) ->
      author = {}
      author.name = from
      author.reply_to = channel
      author.room = self.roomNameFromJid(channel)

      # add extra details if this message is from a known user
      author_data = self.userForName(from)
      if author_data
        author.name = author_data.name
        author.mention_name = author_data.mention_name
        author.jid = author_data.jid

      # reformat leading @mention name to be like "name: message" which is
      # what hubot expects
      regex = new RegExp("^@#{bot.mention_name}\\b", "i")
      hubot_msg = message.replace(regex, "#{bot.mention_name}: ")

      self.receive new TextMessage(author, hubot_msg)

    bot.onPrivateMessage (from, message) ->
      author = {}
      author.reply_to = from

      # add extra details if this message is from a known user
      author_data = self.userForId(self.userIdFromJid(from))
      if author_data
        author.name = author_data.name
        author.mention_name = author_data.mention_name
        author.jid = author_data.jid

      # remove leading @mention name if present and format the message like
      # "name: message" which is what hubot expects
      regex = new RegExp("^@#{bot.mention_name}\\b", "i")
      message = message.replace(regex, "")
      hubot_msg = "#{bot.mention_name}: #{message}"

      self.receive new TextMessage(author, hubot_msg)

    # Join rooms automatically when invited
    bot.onInvite (room_jid, from_jid, message) =>
      console.log "Got invite to #{room_jid} from #{from_jid} - joining"
      bot.join room_jid

    bot.connect()

    @bot = bot

  userIdFromJid: (jid) ->
    try
      return jid.match(/^\d+_(\d+)@chat\./)[1]
    catch e
      console.log "Bad user JID: #{jid}"
      return null

  roomNameFromJid: (jid) ->
    try
      return jid.match(/^\d+_(.+)@conf\./)[1]
    catch e
      console.log "Bad room JID: #{jid}"
      return null

  # Convenience HTTP Methods for posting on behalf of the token"d user
  get: (path, callback) ->
    @request "GET", path, null, callback

  post: (path, body, callback) ->
    @request "POST", path, body, callback

  request: (method, path, body, callback) ->
    console.log method, path, body
    host = @options.host or "api.hipchat.com"
    headers = "Host": host

    unless @options.token
      callback "No API token provided to Hubot", null
      return

    options =
      "agent"  : false
      "host"   : host
      "port"   : 443
      "path"   : path
      "method" : method
      "headers": headers

    if method is "POST"
      body.auth_token = @options.token
      body = JSON.stringify(body)
      headers["Content-Type"] = "application/json"

      body = new Buffer(body)
      options.headers["Content-Length"] = body.length
    else
      options.path += "?auth_token=#{@options.token}"

    request = HTTPS.request options, (response) ->
      data = ""
      response.on "data", (chunk) ->
        data += chunk
      response.on "end", ->
        if response.statusCode >= 400
          console.log "HipChat API error: #{response.statusCode}"

        try
          callback null, JSON.parse(data)
        catch err
          callback null, data or { }
      response.on "error", (err) ->
        callback err, null

    if method is "POST"
      request.end(body, 'binary')
    else
      request.end()

    request.on "error", (err) ->
      console.log err
      console.log err.stack
      callback err

exports.use = (robot) ->
  new HipChat robot
