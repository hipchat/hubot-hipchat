# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and
this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.13.0] - 2017-11-21
### Changed
- `message.user` returns an object from the brain.
  - Changed by [Andrew Widdersheim](https://github.com/awiddersheim) in Pull Request [#277](https://github.com/hipchat/hubot-hipchat/pull/277).
- `user.room` always returns a JID.
  - Changed by [Andrew Widdersheim](https://github.com/awiddersheim) in Pull Request [#277](https://github.com/hipchat/hubot-hipchat/pull/277).

### Removed
- `reply_to` from `envelope.user` and `message.user`.
  - Removed by [Andrew Widdersheim](https://github.com/awiddersheim) in Pull Request [#277](https://github.com/hipchat/hubot-hipchat/pull/277).

### Security
- Updated `node-xmpp-client` to 3.2.0.
  - Updated by [Sam](https://github.com/samcday) in Pull Request [#272](https://github.com/hipchat/hubot-hipchat/pull/272).
