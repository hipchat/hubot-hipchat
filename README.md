# hubot-hipchat

## Quickstart: Hubot for HipChat on Heroku

### The Easy Way

Try deploying the "[Triatomic](https://github.com/hipchat/triatomic)" starter HipChat Hubot project to Heroku. Once you have it running, simply clone it and customize its scripts as you please.

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy?template=https://github.com/hipchat/triatomic)

### The "I do it myself!" Way

This is a HipChat-specific version of the more general [instructions in the Hubot wiki](https://github.com/github/hubot/wiki/Deploying-Hubot-onto-Heroku). Some of this guide is derived from Hubot's [general set up instructions](https://hubot.github.com/docs). You may wish to see that guide for more information about the general use and configuration of Hubot, in addition to details for deploying it to environments other than Heroku.

1. From your existing HipChat account add your bot as a [new user](http://help.hipchat.com/knowledgebase/articles/64413-how-do-i-add-invite-new-users-). Stay signed in to the account - we'll need to access its account settings later.

1. If you are using Linux, make sure libexpat is installed:

        % apt-get install libexpat1-dev

1. You will need [node.js](https://nodejs.org). Joyent has an [excellent blog post on how to get those installed](https://www.joyent.com/blog/installing-node-and-npm), so we'll omit those details here.  You'll want node.js 0.12.x or later.

1. Once node and npm are ready, we can install the hubot generator:

        %  npm install -g yo generator-hubot

1. This will give us the hubot yeoman generator. Now we can make a new directory, and generate a new instance of hubot in it, using this Hubot HipChat adapter. For example, if we wanted to make a bot called myhubot:

        % mkdir myhubot
        % cd myhubot
        % yo hubot --adapter hipchat

1. At this point, you'll be asked a few questions about the bot you are creating. When you finish answering, yeoman will download and install the necessary dependencies. (If the generator hangs, a workaround is to re-run without the `--adapter hipchat` argument, accept the default `campfire` value when prompted, and then re-run yet again, again with the hipchat adapter argument, accepting the prompts to overwrite existing files. This appears to be an issue with the generator itself.)

1. Turn your `hubot` directory into a git repository:

        % git init
        % git add .
        % git commit -m "Initial commit"

1. Install the [Heroku command line tools](http://devcenter.heroku.com/articles/heroku-command) if you don't have them installed yet.

1. Create a new Heroku application and (optionally) rename it:

        % heroku create our-company-hubot

1. Add [Redis To Go](http://devcenter.heroku.com/articles/redistogo) to your Heroku app:

        % heroku addons:create redistogo:nano --app our-company-hubot

1. Configure it:

      You will need to set a configuration variable if you are hosting on the free Heroku plan.

        % heroku config:add HEROKU_URL=http://our-company-hubot.herokuapp.com

      Where the URL is your Heroku app's URL (shown after running `heroku create`, or `heroku rename`).

      Set the JID to the "Jabber ID" shown on your bot's [XMPP/Jabber account settings](https://www.hipchat.com/account/xmpp):

        % heroku config:add HUBOT_HIPCHAT_JID="..."

      Set the password to the password chosen when you created the bot's account.

        % heroku config:add HUBOT_HIPCHAT_PASSWORD="..."

      If using HipChat Server Beta, you need to set xmppDomain to btf.hipchat.com.

        % heroku config:add HUBOT_HIPCHAT_XMPP_DOMAIN="btf.hipchat.com"

1. Deploy and start the bot:

        % git push heroku master
        % heroku ps:scale web=1

      This will tell Heroku to run 1 of the `web` process type which is described in the `Procfile`.

1. You should see the bot join all rooms it has access to (or are specified in HUBOT\_HIPCHAT\_ROOMS, see below). If not, check the output of `heroku logs`. You can also use `heroku config` to check the config vars and `heroku restart` to restart the bot. `heroku ps` will show you its current process state.

1. Assuming your bot's name is "Hubot", the bot will respond to commands like "@hubot help". It will also respond in 1-1 chat ("@hubot" must be omitted there, so just use "help" for example).

1. To configure the commands the bot responds to, you'll need to edit the `hubot-scripts.json` file ([valid script names here](https://github.com/github/hubot-scripts/tree/master/src/scripts)) or add scripts to the `scripts/` directory.

1. To deploy an updated version of the bot, simply commit your changes and run `git push heroku master` again.

Bonus: Add a notification hook to Heroku so a notification is sent to a room whenever the bot is updated: https://www.hipchat.com/help/page/heroku-integration

## Scripting Gotchas
`robot.messageRoom` syntax is as follows
```
robot.messageRoom("1234_room@conf.hipchat.com", "message");
```

## Adapter configuration

This adapter uses the following environment variables:

### HUBOT\_HIPCHAT\_JID

This is your bot's Jabber ID which can be found in your [XMPP/Jabber account settings](https://www.hipchat.com/account/xmpp). It will look something like `123_456@chat.hipchat.com`

### HUBOT\_HIPCHAT\_PASSWORD

This is the password for your bot's HipChat account.

### HUBOT\_HIPCHAT\_ROOMS

Optional. This is a comma separated list of room JIDs that you want your bot to join. You can leave this blank or set it to "All" to have your bot join every room. Room JIDs look like "123_development@conf.hipchat.com" and can be found in the [XMPP/Jabber account settings](https://www.hipchat.com/account/xmpp) - just add "@conf.hipchat.com" to the end of the room's "XMPP/Jabber Name".

### HUBOT\_HIPCHAT\_ROOMS\_BLACKLIST

Optional. This is a comma separated list of room JIDs that should not be joined.

### HUBOT\_HIPCHAT\_JOIN\_ROOMS\_ON\_INVITE

Optional. Setting to `false` will prevent the HipChat adapter from auto-joining rooms when invited.

### HUBOT\_HIPCHAT\_JOIN\_PUBLIC\_ROOMS

Optional. Setting to `false` will prevent the HipChat adapter from auto-joining rooms that are publicly available (i.e. guest-accessible).

### HUBOT\_HIPCHAT\_HOST

Optional. Use to force the host to open the XMPP connection to.

### HUBOT\_HIPCHAT\_XMPP\_DOMAIN

Optional. Set to btf.hipchat.com if using HipChat Server.

### HUBOT\_LOG\_LEVEL

Optional. Set to `debug` to enable detailed debug logging.

### HUBOT\_HIPCHAT\_RECONNECT

Optional. Seting to `false` will prevent the HipChat adapter from auto-reconnecting if it detects a server error or disconnection.

## Running locally

To run locally on OSX or Linux you'll need to set the required environment variables and run the `bin/hubot` script. An example script to run the bot might look like:

    #!/bin/bash

    export HUBOT_HIPCHAT_JID="..."
    export HUBOT_HIPCHAT_PASSWORD="..."

    bin/hubot --adapter hipchat

But be aware that credentials normally shouldn't be checked into your vcs.
