require 'colors'
_ = require 'lodash'

log = (header, headerLength) ->
  headerLength = header.length unless headerLength?
  headerLength += 1
  separator = _.repeat ' ', headerLength
  return (message) ->
    regex = new RegExp ".{1,#{80 - headerLength}}", 'g'
    console.log header, message.match( regex ).join "\n#{separator}"

module.exports =
  success: (message) ->
    log( '[OK]'.green, 4 ) message
  info: (message) ->
    log( '[INFO]'.blue, 6 ) message
  debug: (message) ->
    log( '[DEBUG]'.grey, 7 ) message
  warn: (message) ->
    log( '[WARNING]'.yellow, 9 ) message
  error: (message) ->
    log( '[ERROR]'.red, 7 ) message