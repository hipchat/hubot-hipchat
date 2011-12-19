# hubot-hipchat

## Getting Started

The HipChat adapter requires `node-stringprep` which in turn, requires
`icu-config` to be available in the path. If you're trying to play locally,
then you need to install `icu4c`, which, conveniently, homebrew can take care
of for you

    % brew install icu4c

But `brew` will not link any of the utilities, you'll have to do that by hand
(in particular `icu-config` which is needed for `node-stringprep` to build
correctly (it'll just appear like a broken package otherwise which will be
really disturbing)). You can link it with brew using `brew link icu4c`.

You will also need to edit the `package.json` for your hubot and add the
`hubot-hipchat` adapter dependency.

    "dependencies": {
      "hubot-hipchat": ">= 0.0.1",
      "hubot": ">= 2.0.0",
      ...
    }

Then save the file, and commit the changes to your hubot's git repository.

If deploying to Heroku you will need to edit the `Procfile` and change the
`-a campfire` option to `-a hipchat`. Or if you're deploying locally
you will need to use `-a hipchat` when running your hubot.

## Configuring the Adapter

The HipChat adapter requires the following environment variables.

* `HUBOT_HIPCHAT_JID`
* `HUBOT_HIPCHAT_NAME`
* `HUBOT_HIPCHAT_PASSWORD`
* `HUBOT_HIPCHAT_ROOMS`

### HipChat JID

This is your hubot's Jabber ID, it can be found in your [XMPP/Jabber account settings](https://www.hipchat.com/account/xmpp) and will look something like `123_456@chat.hipchat.com`.

### HipChat Name

This is the full name exactly as you see it on the HipChat account for your hubot. For example "Gnomotron Bot".

### HipChat Password

This is the password for your hubot's HipChat account.

### HipChat Rooms

This is a comma separated list of JID/conference rooms that you want your hubot
to join. You can leave this blank to have your hubot join every room.

### Configuring the variables on Heroku

    % heroku config:add HUBOT_HIPCHAT_JID="..."
    % heroku config:add HUBOT_HIPCHAT_NAME="..."
    % heroku config:add HUBOT_HIPCHAT_PASSWORD="..."
    % heroku config:add HUBOT_HIPCHAT_ROOMS="...,..."

### Configuring the variables on UNIX

    % export HUBOT_HIPCHAT_JID="..."
    % export HUBOT_HIPCHAT_NAME="..."
    % export HUBOT_HIPCHAT_PASSWORD="..."
    % export HUBOT_HIPCHAT_ROOMS="...,..."

### Configuring the variables on Windows

Coming soon!
