{Promise} = require "rsvp"

Promise::done = (done) -> @then done
Promise::fail = (fail) -> @then null, fail

module.exports = -> new Promise()
