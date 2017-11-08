# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and
this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Changed
- `message.user` returns an object from the brain.
  - Changed by [Andrew Widdersheim](https://github.com/awiddersheim) in Pull Request [#277](https://github.com/hipchat/hubot-hipchat/pull/277).
- `user.room` always returns a JID.
  - Changed by [Andrew Widdersheim](https://github.com/awiddersheim) in Pull Request [#277](https://github.com/hipchat/hubot-hipchat/pull/277).

### Removed
- `reply_to` from `envelope.user` and `message.user`.
  - Removed by [Andrew Widdersheim](https://github.com/awiddersheim) in Pull Request [#277](https://github.com/hipchat/hubot-hipchat/pull/277).
