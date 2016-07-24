require 'colors'
Bluebird = require 'bluebird'
request = require 'request'
log = require './log'
fs = Bluebird.promisifyAll require 'fs'
_ = require 'lodash'
path = require 'path'
os = require 'os'
url = require 'url'
unzip = require 'extract-zip'
async = require 'async'

mvAsync = (source, destination) ->
  return new Bluebird (resolve, reject) ->
    mv = require 'mv'
    mv source, destination, (error) ->
      return reject error if error?
      resolve()

rimrafAsync = (target) ->
  return new Bluebird (resolve, reject) ->
    rimraf = require 'rimraf'
    rimraf target, (error) ->
      return reject error if error?
      resolve()

wamfileFormatError = "Invalid #{'wamfile'.magenta} format! Check
                      #{'wamfile.demo'.magenta} for an example."

wamfileFormatErrorWrongWowpathFormat =
  "Invalid #{'wamfile'.magenta} format! #{'wowPath'.red} key should have
   associated the path to your World of Warcraft installation. Check
   #{'wamfile.demo'.magenta} for an example."

wamfileFormatErrorWrongWowpath =
  "Invalid #{'wamfile'.magenta} format! #{'wowPath'.red} key should have
   associated the path to your World of Warcraft installation but the actual
   path did not contain a World of Warcraft installation. Check
   #{'wamfile.demo'.magenta} for an example."

addonsIdentifiersHelp =
  "WAM uses Curse's identifiers. To get the identifier of an addon just use
   #{'mods.curse.com'.blue} search engine. Clicking on an Addon from search
   results list will open a page with a URL following this format:
   #{'http://mods.curse.com/addons/wow/'.blue}#{'<addon-identifier>'.yellow}."

wamfileFormatErrorWrongAddonsFormat =
  "Invalid #{'wamfile'.magenta} format! #{'addons'.red} key should have
   associated an array of identifiers of Addons. Check #{'wamfile.demo'.magenta}
   for an example.\n\n#{addonsIdentifiersHelp}"

ErrorCodeDoesntExist = 'ENOENT'

wamfilePath = './wamfile'
if process.argv.length > 2
  wamfilePath = process.argv[2]
  log.info "Using #{'wamfile'.magenta} at #{wamfilePath.yellow}."
else
  log.info "Using local #{'wamfile'.magenta} at #{wamfilePath.yellow}."

fs.statAsync wamfilePath
  .then (stats) ->

    if stats.isDirectory()
      wamfilePath = path.resolve wamfilePath, './wamfile'

    readWamfile wamfilePath

  .caught (error) ->
    if error.code is ErrorCodeDoesntExist
      log.error "Given path (#{wamfilePath.yellow}) was neither a folder nor a
                 #{'wamfile'.magenta}!"
    else
      log.error "#{error}"

readWamfile = ->
  fs.readFileAsync wamfilePath
    .then (data) ->
      try
        return JSON.parse data
      catch
        throw wamfileFormatError
    .then (json) ->

      if _.isString json.wowPath
        json.addonsPath = path.resolve json.wowPath, 'Interface', 'AddOns'
        return fs.statAsync json.addonsPath
          .then (stats) ->
            throw wamfileFormatError unless stats.isDirectory()
            return json
          .caught (error) ->
            if error.code is ErrorCodeDoesntExist
              throw wamfileFormatErrorWrongWowpathFormat
      else
        throw wamfileFormatErrorWrongWowpath

    .then (json) ->
      throw wamfileFormatErrorWrongAddonsFormat unless _.isArray json.addons
      return json

    .then (json) ->

      promises = async.mapLimit json.addons, 100, (addon, callback) ->
        return getAddonMetadata addon
          .then (addonURL) ->
            return downloadAddon addonURL, addon
          .then (zipFilePath) ->
            return unzipAddon zipFilePath, addon
          .then (tmpAddonPath) ->
            return flattenAddon tmpAddonPath, addon, json.addonsPath
          .then (version) ->
            version = if version? then " v#{version}" else ''
            log.success "Downloaded #{addon.magenta}#{version.yellow}."
            callback()
          .caught (error) ->
            console.log "ERROR: #{error}"
            log.error error
            console.log error
            callback error

    .caught (error) ->
      log.error "#{error}"

getAddonMetadata = (addonIdentifier) ->

  return new Bluebird (resolve, reject) ->

    downloadPageURL =
      "http://mods.curse.com/addons/wow/#{addonIdentifier}/download"

    request {
      followAllRedirects: true,
      url: downloadPageURL
    }, (error, response) ->
      if error
        return reject "Error getting Addon information for
                       #{addonIdentifier.yellow}"

      curseIdentifier =
        _.last response.request.uri.href.split addonIdentifier
      curseIdentifier = _.first curseIdentifier.split '?'
      curseIdentifier = curseIdentifier.substr 1

      linkRegex = new RegExp "data-file=\"#{curseIdentifier}\"
                              data-href=\"([^\"]*)\""

      match = linkRegex.exec response.body

      unless match?
        return reject "Error getting Addon information for
                       #{addonIdentifier.yellow}"

      downloadURL = match[1]

      resolve downloadURL

downloadAddon = (addonURL, addonIdentifier) ->

  return new Bluebird (resolve, reject) ->

    filename = path.basename url.parse(addonURL).path
    tmpFilePath = path.resolve os.tmpdir(), filename

    log.info "Downloading #{addonIdentifier.magenta}..."

    request {
      followAllRedirects: true,
      url: "#{addonURL}"
    }
    .pipe fs.createWriteStream "#{tmpFilePath}"
    .on 'error', (error) ->
      console.log error
      if error.code is ErrorCodeDoesntExist
        reject "Error writing Addon #{addonIdentifier.yellow} in temporary
                folder #{tmpFilePath.yellow}."
      else
        reject "Error downloading Addon #{addonIdentifier.yellow}."

    .on 'finish', () ->
      resolve tmpFilePath

unzipAddon = (zipFilePath, addonIdentifier) ->

  return new Bluebird (resolve, reject) ->

    filename = path.basename zipFilePath
    outputPath = path.resolve path.dirname(zipFilePath),
                              "#{filename.replace '.zip', ''}"

    unzip zipFilePath, {dir: outputPath}, (error) ->
      return reject error if error?
      resolve outputPath

flattenAddon = (tmpOutputPath, addonIdentifier, addonsPath) ->

  return new Bluebird (resolve, reject) ->

    fs.readdir tmpOutputPath, (error, files) ->

      if error
        return reject "Error listing contents of Addon
                       #{addonIdentifier.yellow}"

      files = _.filter files, (file) ->
        return file[0] isnt '.'

      files = _.map files, (file) ->
        return path.resolve tmpOutputPath, file

      fileCount = _.reduce files, (sum, file) ->
        return sum + (if !fs.statSync(file).isDirectory() then 1 else 0)
      , 0

      matches = /(\d+\.\d+\.\d+)$/.exec path.basename tmpOutputPath
      version = matches?[1]

      if fileCount is 0

        Bluebird.all _.map files, (file) ->

          outputPath = path.resolve addonsPath, path.basename file

          rimrafAsync outputPath
            .then ->
              return mvAsync file, outputPath
            .then ->
              return outputPath
          .then ->
            resolve version
          .caught (error) ->
            reject error

      else

        outputPath = path.resolve addonsPath, addonIdentifier

        rimrafAsync outputPath
          .then ->
            mvAsync tmpOutputPath, outputPath
          .then ->
            resolve version
          .caught (error) ->
            reject error
