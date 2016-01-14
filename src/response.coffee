{Response} = require 'hubot'

class HipChatResponse extends Response

	sendFile: (file_info) ->
		@robot.adapter.sendFile(@envelope, file_info)

	sendHtml: (strings...) ->
		@robot.adapter.sendHtml(@envelope, strings...)

module.exports = HipChatResponse