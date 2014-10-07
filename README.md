# hubot-hipchat

## Quickstart: Hubot for HipChat on Heroku

This is a HipChat-specific version of the more general [instructions in the Hubot wiki](https://github.com/github/hubot/wiki/Deploying-Hubot-onto-Heroku).

1. From your existing HipChat account add your bot as a [new user](http://help.hipchat.com/knowledgebase/articles/64413-how-do-i-add-invite-new-users-). Stay signed in to the account - we'll need to access its account settings later.

1. Make sure native dependencies are installed:

        (e.g. OS X with brew)
        % brew install icu4c
        % brew link icu4c

        (e.g. Linux with apt-get)
        % apt-get install libexpat1-dev
        % apt-get install libicu-dev

1. Install `hubot` from npm, if you don't already have it. Note the explicit version reference. The version # of hubot-hipchat is kept in line with hubot. If your hubot's version is greater than hubot-hipchat's, that means it hasn't been tested and may not work!

        % npm install --global coffee-script hubot@v2.7.5

1. Create a new `hubot` if necessary:

        % hubot --create <path>

1. Switch to the new `hubot` directory:

        % cd <above path>

1. Install `hubot` dependencies:

        % npm install

1. Install the `hipchat` adapter:

        % npm install --save hubot-hipchat

1. Edit `Procfile` and change it to use the `hipchat` adapter. You can also remove the `-n Hubot` arg as the bot will automatically fetch its @mention name from HipChat.

        web: bin/hubot --adapter hipchat

1. Turn your `hubot` directory into a git repository:

        % git init
        % git add .
        % git commit -m "Initial commit"

1. Install the [Heroku command line tools](http://devcenter.heroku.com/articles/heroku-command) if you don't have them installed yet.

1. Create a new Heroku application and (optionally) rename it:

        % heroku create our-company-hubot

1. Add [Redis To Go](http://devcenter.heroku.com/articles/redistogo) to your Heroku app:

        % heroku addons:add redistogo:nano

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

### HUBOT\_HIPCHAT\_HOST

Optional. Use to force the host to open the XMPP connection to.

### HUBOT\_HIPCHAT\_XMPP\_DOMAIN

Optional. Set to btf.hipchat.com if using HipChat Server Beta.

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
