Promise = require "fantasy-promises"

Promise::done = (done) -> @fork done, null
Promise::fail = (fail) -> @fork null, fail

module.exports = (fork) ->
  new Promise (resolve, reject) ->
    fork (resolve or ->), (reject or ->)
