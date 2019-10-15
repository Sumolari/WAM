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
cs = require 'cloudscraper'

###
Returns a promise about moving given source path to given destination.

@param [String] source      Source path to be moved.
@param [String] destination Destination path where source path will be moved.

@return [Promise] Promise that will be resolved with no parameters on success.
###
mvAsync = (source, destination) ->
  return new Bluebird (resolve, reject) ->
    mv = require 'mv'
    mv source, destination, (error) ->
      return reject error if error?
      resolve()

###
Returns a promise about removing given target path, including any content stored
there.

@param [String] target Target path to be removed.

@return [Promise] Promise that will be resolved with no parameters on success.
###
rimrafAsync = (target) ->
  return new Bluebird (resolve, reject) ->
    rimraf = require 'rimraf'
    rimraf target, (error) ->
      return reject error if error?
      resolve()

WamfileFormatError = "Invalid #{'wamfile'.magenta} format! Check
                      #{'wamfile.demo'.magenta} for an example."

AddonsIdentifiersHelp =
  "WAM uses Curse's identifiers. To get the identifier of an addon just use
   #{'mods.curse.com'.blue} search engine. Clicking on an Addon from search
   results list will open a page with a URL following this format:
   #{'http://mods.curse.com/addons/wow/'.blue}#{'<addon-identifier>'.yellow}."

ErrorCodeDoesntExist = 'ENOENT'

if process.argv.length < 3
  log.info "Usage: #{'wam'.yellow} #{'<command>'.blue}
            #{'[wamfilePath]'.magenta}\n\
            Commands:\n - #{'init'.blue}     Create a new wamfile with demo
                                             content
                     \n - #{'update'.blue}   Install or update addons in given
                                             #{'wamfile'.magenta}"
  process.exit 1

wamfilePath = './wamfile'
if process.argv.length > 3
  wamfilePath = process.argv[3]
  log.info "Using #{'wamfile'.magenta} at #{wamfilePath.yellow}."
else
  log.info "Using local #{'wamfile'.magenta} at #{wamfilePath.yellow}."

operations =
  update: ->
    log.info 'Installing or updating AddOns...'

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
  init: ->
    log.info 'Creating sample configuration file...'

    inputPath = path.resolve __dirname, '../wamfile.demo'

    fs.statAsync wamfilePath
    .then (stats) ->

      if stats.isDirectory()
        return path.resolve wamfilePath, 'wamfile'
      else
        return path.resolve path.dirname(wamfilePath), 'wamfile'

    .caught (error) ->

      throw error unless error.code is ErrorCodeDoesntExist

      return fs.statAsync path.dirname wamfilePath
      .then (stats) ->
        if stats.isDirectory()
          return path.resolve path.dirname(wamfilePath), 'wamfile'
        else
          throw error

    .then (outputPath) ->

      fs
      .createReadStream inputPath
      .pipe fs.createWriteStream outputPath
      .on 'close', ->
        log.info "File ready at #{outputPath.yellow}"

    .caught (error) ->
      log.error "#{error}"

operations[process.argv[2]]()

###
Reads `wamfile` at given path and downloads addons.
###
readWamfile = (wamfilePath) ->
  fs.readFileAsync wamfilePath
    .then (data) ->
      try
        return JSON.parse data
      catch
        throw new Error WamfileFormatError
    .then (json) ->

      if _.isString json.wowPath
        json.addonsPath = path.resolve json.wowPath, 'Interface', 'AddOns'
        return fs.statAsync json.addonsPath
          .then (stats) ->
            throw new Error WamfileFormatError unless stats.isDirectory()
            return json
          .caught (error) ->
            if error.code is ErrorCodeDoesntExist
              throw new Error "Invalid #{'wamfile'.magenta} format!
                               #{'wowPath'.red} key should have associated the
                               path to your World of Warcraft installation.
                               Check #{'wamfile.demo'.magenta} for an example."
      else
        throw new Error "Invalid #{'wamfile'.magenta} format! #{'wowPath'.red}
                         key should have associated the path to your World of
                         Warcraft installation but the actual path did not
                         contain a World of Warcraft installation. Check
                         #{'wamfile.demo'.magenta} for an example."

    .then (json) ->
      unless _.isArray json.addons
        throw new Error "Invalid #{'wamfile'.magenta} format! #{'addons'.red}
                         key should have associated an array of identifiers of
                         Addons. Check #{'wamfile.demo'.magenta} for an example.
                         \n\n#{AddonsIdentifiersHelp}"
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
            log.error error
            callback error

    .caught (error) ->
      log.error "#{error}"

###
Returns a promise that will be resolved with the identifier assigned by Curse
to latest version of given addon.

@parameter [String] addonIdentifier Identifier used by Curse to identify the
                                    addon.
@return [Promise] Promise that will be resolved with addon's latest version.
###
getAddonMetadata = (addonIdentifier) ->

  return new Bluebird (resolve, reject) ->

    downloadPageURL =
      "https://www.curseforge.com/wow/addons/#{addonIdentifier}/download"

    cs.get downloadPageURL
      .then (data) ->
        linkRegex = new RegExp(
          "/wow/addons/#{addonIdentifier}/download/[^\"]*/file"
        )

        match = linkRegex.exec data

        unless match?
          return reject "Error getting Addon information for
                         #{addonIdentifier.yellow}"

        downloadURL = match[0]

        resolve "https://www.curseforge.com#{downloadURL}"

      .catch (ex) ->
        return reject "Error getting Addon information for
                       #{addonIdentifier.yellow}"

###
Returns a promise that will be resolved with local path to zip file for addon
at given URL with given Curse identifier.

@parameter [String] addonURL        URL to zip file returned by Curse website.
@parameter [String] addonIdentifier Identifier assigned by Curse to the addon.

@return [Promise] Promise that will be resolved with path to local copy of given
                  zip file.
###
downloadAddon = (addonURL, addonIdentifier) ->

  return new Bluebird (resolve, reject) ->

    filename = path.basename url.parse(addonURL).path
    tmpFilePath = path.resolve os.tmpdir(), "#{addonIdentifier}-#{filename}.zip"

    log.info "Downloading #{addonIdentifier.magenta}..."
    
    cs
      method: 'GET'
      uri: addonURL
      rejectUnauthorized: false
      realEncoding: null
    .then (body) ->

      buffer = Buffer.from body, 'utf8'

      fs.writeFile tmpFilePath, buffer, (error) ->
        if error
          reject "Error saving Addon #{addonIdentifier.yellow}."
        else
          resolve tmpFilePath
          
    .catch (error) ->
        console.log error
        reject "Error downloading Addon #{addonIdentifier.yellow}."

###
Unzips given local file, returning a promise that will be resolved with local
path to unzipped folder.

@param [String] zipFilePath Path to zip file to be extracted.

@return [Promise] Promise that will be resolved with path to uncompressed
                  content.
###
unzipAddon = (zipFilePath) ->

  return new Bluebird (resolve, reject) ->

    filename = path.basename zipFilePath
    outputPath = path.resolve path.dirname(zipFilePath),
                              "#{filename.replace '.zip', ''}"

    unzip zipFilePath, {dir: outputPath}, (error) ->
      return reject error if error?
      resolve outputPath

###
Flattens content of given folder so if folder only contains directories all of
them are moved to destination folder, otherwise container folder is moved to
destination directory.

@param [String] tmpOutputPath   Path to folder to be flattened.
@param [String] addonIdentifier Identifier of addon being flattened.
@param [String] addonsPath      Path to World of Warcraft addons folder, where
                                content will be flattened.

@return [Promise] Promise that will be resolved with addon's version (if known)
                  or a `null` value.
###
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
