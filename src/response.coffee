{Response} = require 'hubot'

class HipchatResponse extends Response

	sendFile: (file_info) ->
		@robot.adapter.sendFile(@envelope, file_info)

	sendHtml: (strings...) ->
		@robot.adapter.sendHtml(@envelope, strings...)

module.exports = HipchatResponse