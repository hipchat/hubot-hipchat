# Modified from [Wobot](https://github.com/cjoudrey/wobot).
#
# Copyright (C) 2011 by Christian Joudrey
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

{EventEmitter} = require "events"
fs = require "fs"
util = require "./util"
{bind, isString, isRegExp} = require "underscore"
# The xmpp module emits warnings about node-stringprep that are unfixable on
# node 0.10+, so require it through our helper that suppresses console messages;
# it's complaint doesn't seem to effect the functionality of xmpp that we need
# anyway...
xmpp = util.require "node-xmpp", "quiet"

# Parse and cache the node package.json file when this module is loaded
pkg = do ->
  data = fs.readFileSync __dirname + "/../package.json", "utf8"
  JSON.parse(data)

# ##Public Connector API
module.exports = class Connector extends EventEmitter

  # This is the `Connector` constructor.
  #
  # `options` object:
  #
  #   - `jid`: Connector's Jabber ID
  #   - `password`: Connector's HipChat password
  #   - `host`: Force host to make XMPP connection to. Will look up DNS SRV
  #        record on JID's host otherwise.
  #   - `caps_ver`: Name and version of connector. Override if Connector is being used
  #        to power another connector framework (e.g. Hubot).
  #   - `logger`: A logger instance.
  constructor: (options={}) ->
    @once "connect", (->) # listener bug in Node 0.4.2
    @setMaxListeners 0

    @jabber = null
    @keepalive = null
    @name = null
    @plugins = {}
    @iq_count = 1 # current IQ id to use
    @logger = options.logger

    # add a JID resource if none was provided
    jid = new xmpp.JID options.jid
    jid.resource = "hubot-hipchat" if not jid.resource

    @jid = jid.toString()
    @password = options.password
    @host = options.host
    @caps_ver = options.caps_ver or "hubot-hipchat:#{pkg.version}"

    # Multi-User-Conference (rooms) service host. Use when directing stanzas
    # to the MUC service.
    @mucHost = "conf.#{if @host then @host else 'hipchat.com'}"

    @onError @disconnect

  # Connects the connector to HipChat and sets the XMPP event listeners.
  connect: ->
    @jabber = new xmpp.Client
      jid: @jid,
      password: @password,
      host: @host

    @jabber.on "error", bind(onStreamError, @)
    @jabber.on "online", bind(onOnline, @)
    @jabber.on "stanza", bind(onStanza, @)

    # debug network traffic
    do =>
      @jabber.on "data", (buffer) =>
        @logger.debug "  IN > %s", buffer.toString()
      _send = @jabber.send
      @jabber.send = (stanza) =>
        @logger.debug " OUT > %s", stanza
        _send.call @jabber, stanza

  # Disconnect the connector from HipChat, remove the anti-idle and emit the
  # `disconnect` event.
  disconnect: =>
    if @keepalive
      clearInterval @keepalive
      delete @keepalive
    @jabber.end()
    @emit "disconnect"

  # Fetches our profile info
  #
  # - `callback`: Function to be triggered: `function (err, data, stanza)`
  #   - `err`: Error condition (string) if any
  #   - `data`: Object containing fields returned (fn, title, photo, etc)
  #   - `stanza`: Full response stanza, an `xmpp.Element`
  getProfile: (callback) ->
    stanza = new xmpp.Element("iq", type: "get")
      .c("vCard", xmlns: "vcard-temp")
    @sendIq stanza, (err, res) ->
      data = {}
      if not err
        for field in res.getChild("vCard").children
          data[field.name.toLowerCase()] = field.getText()
      callback err, data, res

  # Fetches the rooms available to the connector user. This is equivalent to what
  # would show up in the HipChat lobby.
  #
  # - `callback`: Function to be triggered: `function (err, items, stanza)`
  #   - `err`: Error condition (string) if any
  #   - `rooms`: Array of objects containing room data
  #   - `stanza`: Full response stanza, an `xmpp.Element`
  getRooms: (callback) ->
    iq = new xmpp.Element("iq", to: this.mucHost, type: "get")
      .c("query", xmlns: "http://jabber.org/protocol/disco#items");
    @sendIq iq, (err, stanza) ->
      rooms = if err then [] else
        # Parse response into objects
        stanza.getChild("query").getChildren("item").map (el) ->
          x = el.getChild "x", "http://hipchat.com/protocol/muc#room"
          # A room
          jid: el.attrs.jid
          name: el.attrs.name
          id: getInt(x, "id")
          topic: getText(x, "topic")
          privacy: getText(x, "privacy")
          owner: getText(x, "owner")
          num_participants: getInt(x, "num_participants")
          guest_url: getText(x, "guest_url")
          is_archived: !!getChild(x, "is_archived")
      callback err, (rooms or []), stanza

  # Fetches the roster (buddy list)
  #
  # - `callback`: Function to be triggered: `function (err, items, stanza)`
  #   - `err`: Error condition (string) if any
  #   - `items`: Array of objects containing user data
  #   - `stanza`: Full response stanza, an `xmpp.Element`
  getRoster: (callback) ->
    iq = new xmpp.Element("iq", type: "get")
      .c("query", xmlns: "jabber:iq:roster")
    @sendIq iq, (err, stanza) ->
      items = if err then [] else
        # Parse response into objects
        stanza.getChild("query").getChildren("item").map (el) ->
          jid: el.attrs.jid
          name: el.attrs.name
          # Name used to @mention this user
          mention_name: el.attrs.mention_name
      callback err, (items or []), stanza

  # Updates the connector's availability and status.
  #
  #  - `availability`: Jabber availability codes
  #     - `away`
  #     - `chat` (Free for chat)
  #     - `dnd` (Do not disturb)
  #  - `status`: Status message to display
  setAvailability: (availability, status) ->
    packet = new xmpp.Element "presence", type: "available"
    packet.c("show").t(availability)
    packet.c("status").t(status) if (status)

    # Providing capabilities info (XEP-0115) in presence tells HipChat
    # what type of client is connecting. The rest of the spec is not actually
    # used at this time.
    packet.c "c",
      xmlns: "http://jabber.org/protocol/caps"
      node: "http://hipchat.com/client/bot" # tell HipChat we're a bot
      ver: @caps_ver

    @jabber.send packet

  # Join the specified room.
  #
  # - `roomJid`: Target room, in the form of `????_????@conf.hipchat.com`
  # - `historyStanzas`: Max number of history entries to request
  join: (roomJid, historyStanzas) ->
    historyStanzas = 0 if not historyStanzas
    packet = new xmpp.Element "presence", to: "#{roomJid}/#{@name}"
    packet.c "x", xmlns: "http://jabber.org/protocol/muc"
    packet.c "history",
      xmlns: "http://jabber.org/protocol/muc"
      maxstanzas: String(historyStanzas)
    @jabber.send packet

  # Part the specified room.
  #
  # - `roomJid`: Target room, in the form of `????_????@conf.hipchat.com`
  part: (roomJid) ->
    packet = new xmpp.Element 'presence',
      type: 'unavailable'
      to: "#{roomJid}/#{@name}"
    packet.c 'x', xmlns: 'http://jabber.org/protocol/muc'
    packet.c('status').t('hc-leave')
    @jabber.send packet

  # Send a message to a room or a user.
  #
  # - `targetJid`: Target
  #    - Message to a room: `????_????@conf.hipchat.com`
  #    - Private message to a user: `????_????@chat.hipchat.com`
  # - `message`: Message to be sent to the room
  message: (targetJid, message) ->
    parsedJid = new xmpp.JID targetJid

    if parsedJid.domain is @mucHost
      packet = new xmpp.Element "message",
        to: "#{targetJid}/#{@name}"
        type: "groupchat"
    else
      packet = new xmpp.Element "message",
        to: targetJid
        type: "chat"
        from: @jid
      packet.c "inactive", xmlns: "http://jabber/protocol/chatstates"

    packet.c("body").t(message)
    @jabber.send packet

  # Sends an IQ stanza and stores a callback to be called when its response
  # is received.
  #
  # - `stanza`: `xmpp.Element` to send
  # - `callback`: Function to be triggered: `function (err, stanza)`
  #   - `err`: Error condition (string) if any
  #   - `stanza`: Full response stanza, an `xmpp.Element`
  sendIq: (stanza, callback) ->
    stanza = stanza.root() # work with base element
    id = @iq_count++
    stanza.attrs.id = id;
    @once "iq:#{id}", callback
    @jabber.send stanza

  loadPlugin: (identifier, plugin, options) ->
    if typeof plugin isnt "object"
      throw new Error "Plugin argument must be an object"
    if typeof plugin.load isnt "function"
      throw new Error "Plugin object must have a load function"
    @plugins[identifier] = plugin
    plugin.load @, options
    true

  # ##Events API

  # Emitted whenever the connector connects to the server.
  #
  # - `callback`: Function to be triggered: `function ()`
  onConnect: (callback) -> @on "connect", callback

  # Emitted whenever the connector disconnects from the server.
  #
  # - `callback`: Function to be triggered: `function ()`
  onDisconnect: (callback) -> @on "disconnect", callback

  # Emitted whenever the connector is invited to a room.
  #
  # `onInvite(callback)`
  #
  # - `callback`: Function to be triggered:
  #               `function (roomJid, fromJid, reason, matches)`
  #   - `roomJid`: JID of the room being invited to.
  #   - `fromJid`: JID of the person who sent the invite.
  #   - `reason`: Reason for invite (text)
  onInvite: (callback) -> @on "invite", callback

  # Makes an onMessage impl for the named message event
  onMessageFor = (name) ->
    (condition, callback) ->
      if not callback
        callback = condition
        condition = null
      @on name, ->
        message = arguments[arguments.length - 1]
        if not condition or message is condition
          callback.apply @, arguments
        else if isRegExp condition
          match = message.match condition
          return if not match
          args = [].slice.call arguments
          args.push match
          callback.apply @, args

  # Emitted whenever a message is sent to a channel the connector is in.
  #
  # `onMessage(condition, callback)`
  #
  # `onMessage(callback)`
  #
  # - `condition`: String or RegExp the message must match.
  # - `callback`: Function to be triggered: `function (roomJid, from, message, matches)`
  #   - `roomJid`: Jabber Id of the room in which the message occured.
  #   - `from`: The name of the person who said the message.
  #   - `message`: The message
  #   - `matches`: The matches returned by the condition when it is a RegExp
  onMessage: onMessageFor "message"

  # Emitted whenever a message is sent privately to the connector.
  #
  # `onPrivateMessage(condition, callback)`
  #
  # `onPrivateMessage(callback)`
  #
  # - `condition`: String or RegExp the message must match.
  # - `callback`: Function to be triggered: `function (fromJid, message)`
  onPrivateMessage: onMessageFor "privateMessage"

  # Emitted whenever the connector pings the server (roughly every 30 seconds).
  #
  # - `callback`: Function to be triggered: `function ()`
  onPing: (callback) -> @on "ping", callback

  # Emitted whenever an XMPP stream error occurs. The `disconnect` event will
  # always be emitted afterwards.
  #
  # Conditions are defined in the XMPP spec:
  #   http://xmpp.org/rfcs/rfc6120.html#streams-error-conditions
  #
  # - `callback`: Function to be triggered: `function(condition, text, stanza)`
  #   - `condition`: XMPP stream error condition (string)
  #   - `text`: Human-readable error message (string)
  #   - `stanza`: The raw `xmpp.Element` error stanza
  onError: (callback) -> @on "error", callback

# ##Private functions

# Whenever an XMPP stream error occurs, this function is responsible for
# triggering the `error` event with the details and disconnecting the connector
# from the server.
#
# Stream errors (http://xmpp.org/rfcs/rfc6120.html#streams-error) look like:
# <stream:error>
#   <system-shutdown xmlns='urn:ietf:params:xml:ns:xmpp-streams'/>
# </stream:error>
onStreamError = (err) ->
  if err instanceof xmpp.Element
    condition = err.children[0].name
    text = err.getChildText "text"
    if not text
      text = "No error text sent by HipChat, see
        http://xmpp.org/rfcs/rfc6120.html#streams-error-conditions
        for error condition descriptions."
    @emit "error", condition, text, err
  else
    @emit "error", null, null, err

# Whenever an XMPP connection is made, this function is responsible for
# triggering the `connect` event and starting the 30s anti-idle. It will
# also set the availability of the connector to `chat`.
onOnline = ->
  @setAvailability "chat"

  ping = =>
    @jabber.send " "
    @emit "ping"

  @keepalive = setInterval ping, 30000

  # Load our profile to get name
  @getProfile (err, data) =>
    if err
      # This isn't technically a stream error which is what the `error`
      # event usually represents, but we want to treat a profile fetch
      # error as a fatal error and disconnect the connector.
      @emit "error", null, "Unable to get profile info: #{err}", null
    else
      # Now that we have our name we can let rooms be joined
      @name = data.fn;
      # This is the name used to @mention us
      @mention_name = data.nickname
      @emit "connect"

# This function is responsible for handling incoming XMPP messages. The
# `data` event will be triggered with the message for custom XMPP
# handling.
#
# The connector will parse the message and trigger the `message`
# event when it is a group chat message or the `privateMessage` event when
# it is a private message.
onStanza = (stanza) ->
  @emit "data", stanza
  if stanza.is "message"
    if stanza.attrs.type is "groupchat"
      body = stanza.getChildText "body"
      return if not body
      # Ignore chat history
      return if stanza.getChild "delay"
      fromJid = new xmpp.JID stanza.attrs.from
      fromChannel = fromJid.bare().toString()
      fromNick = fromJid.resource
      # Ignore our own messages
      return if fromNick is @name
      @emit "message", fromChannel, fromNick, body
    else if stanza.attrs.type is "chat"
      # Message without body is probably a typing notification
      body = stanza.getChildText "body"
      return if not body
      fromJid = new xmpp.JID stanza.attrs.from
      @emit "privateMessage", fromJid.bare().toString(), body
    else if not stanza.attrs.type
      # @todo It'd be great if we could have some sort of xpath-based listener
      # so we could just watch for '/message/x/invite' stanzas instead of
      # doing all this manual getChild nonsense
      x = stanza.getChild "x", "http://jabber.org/protocol/muc#user"
      return if not x
      invite = x.getChild "invite"
      return if not invite
      reason = invite.getChildText "reason"
      inviteRoom = new xmpp.JID stanza.attrs.from
      inviteSender = new xmpp.JID invite.attrs.from
      @emit "invite", inviteRoom.bare(), inviteSender.bare(), reason
  else if stanza.is "iq"
    # Handle a response to an IQ request
    event_id = "iq:#{stanza.attrs.id}"
    if stanza.attrs.type is "result"
      @emit event_id, null, stanza
    else
      # IQ error response
      # ex: http://xmpp.org/rfcs/rfc6121.html#roster-syntax-actions-result
      condition = "unknown"
      error_elem = stanza.getChild "error"
      condition = error_elem.children[0].name if error_elem
      @emit event_id, condition, stanza

# DOM helpers

getChild = (el, name) ->
  el.getChild name

getText = (el, name) ->
  getChild(el, name).getText()

getInt = (el, name) ->
  parseInt getText(el, name), 10
