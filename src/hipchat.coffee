Robot   = require('hubot').robot()
Adapter = require('hubot').adapter()

HTTPS   = require 'https'
Wobot   = require('wobot').Bot

class HipChat extends Adapter
  send: (user, strings...) ->
    for str in strings
      @bot.message user.reply_to, str

  reply: (user, strings...) ->
    for str in strings
      @send user, "@\"#{user.name}\" #{str}"

  run: ->
    self = @
    @options =
      jid:      process.env.HUBOT_HIPCHAT_JID
      password: process.env.HUBOT_HIPCHAT_PASSWORD
      token:    process.env.HUBOT_HIPCHAT_TOKEN or null
      name:     process.env.HUBOT_HIPCHAT_NAME or "#{self.name} Bot"
      rooms:    process.env.HUBOT_HIPCHAT_ROOMS or "@All"
      debug:    process.env.HUBOT_HIPCHAT_DEBUG or false
      host:     process.env.HUBOT_HIPCHAT_HOST or null

    console.log "Options:", @options
    bot = new Wobot(jid: @options.jid, name: @options.name, password: @options.password, debug: @options.debug == 'true', host: @options.host)
    mention = new RegExp("@#{@options.name.split(' ')[0]}\\b", "i")
    console.log mention
    console.log "Bot:", bot

    bot.onConnect =>
      console.log "Connected to HipChat"

      # Join requested rooms
      if @options.rooms is "@All"
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
      author = (self.userForName from) or {}
      author.name = from unless author.name
      author.reply_to = channel
      author.room = self.roomNameFromJid(channel)
      hubot_msg = message.replace(mention, "#{self.robot.name}: ")
      self.receive new Robot.TextMessage(author, hubot_msg)

    bot.onPrivateMessage (from, message) ->
      author = self.userForId(self.userIdFromJid(from))
      author.reply_to = from
      author.room = self.roomNameFromJid(from)
      self.receive new Robot.TextMessage(author, "#{self.robot.name}: #{message}")

    # Join rooms automatically when invited
    bot.onInvite (room_jid, from_jid, message) =>
      console.log "Got invite to #{room_jid} from #{from_jid} - joining"
      bot.join room_jid

    bot.connect()

    @bot = bot

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

  userIdFromJid: (jid) ->
    try
      return jid.match(/^\d+_(\d+)@/)[1]
    catch e
      console.log "Bad user JID: #{jid}"
      return null

  roomNameFromJid: (jid) ->
    try
      return jid.match(/^\d+_([\w_\.]+)@/)[1]
    catch e
      console.log "Bad room JID: #{jid}"
      return null

exports.use = (robot) ->
  new HipChat robot
