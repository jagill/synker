Rsync = require 'rsync'
util = require 'util'
pvc = require 'pvc'
pvcf = require 'pvc-file'
_path = require 'path'

list = (val) -> val.split(',')

parseOptions = (argv) ->
  #argv = require('yargs')
    #.usage('Usage: $0 [options] <sourcepaths> <destination>')
    #.help('h')
    #.alias('h', 'help')
    #.argv

  program = require 'commander'
  program
    .arguments '<source> <destination>'
    .option '-i, --include <items>', 'Only include files with this prefix.', list
    .option '-x, --exclude <items>', 'Exclude files with this prefix.  Applied after include.', list
    .on '--help', ->
      console.log '  Keep directories in sync.  Watch for changes, and rsync the
                     modified files to the remote host.'
      console.log '  This does not currently delete missing files.
                     More options available on request.'
      console.log ''
      console.log '  Arguments:'
      console.log '    source: Local dir to sync, eg from/here/ .  This is recursive.'
      console.log '    destination: rsync style destination, eg somehost:some/path/'
      console.log ''
      console.log '  Examples:'
      console.log ''
      console.log '    ## sync my/dir/ with foo.example.com:another/dir/'
      console.log '    $ synker my/dir/ foo.example.com:another/dir/'
    .parse(process.argv)

  if program.args.length != 2
    program.outputHelp()
    process.exit 1

  program.destination = program.args[1]
  program.source = program.args[0]
  return program

# Convert a full path like a/b/c/d to /a/b/./c/d if base is a/b/
# This is to make it into the form needed by resync 'relative' option.
makeRsyncRelativePath = (base, full, root) ->
  if base.indexOf(root) != 0
    throw new Error "#{root} is not a valid root for #{base}"
  if full.indexOf(base) != 0
    throw new Error "#{base} is not a valid base for #{full}"

  # if base == root, then we are rsyncing directly into dest.
  # (This handles the ./a/b/c case)
  return _path.relative(base, full) if base == root

  # otherwise, we need to rsync relative to base.
  relativeFull = _path.relative base, full
  relativeBase = _path.relative root, base
  return [relativeBase, '.', relativeFull].join(_path.sep)

###*
# @param opts:
#   source: (String) Source path
#   destination: (String) rsync-style destination.
#   base: (Optional String) use this to calculate the base of the sources.
###
exports.sync = sync = (opts) ->
  {source, destination, include, exclude} = opts
  root = _path.resolve process.cwd()
  source = _path.resolve source
  relativeSource = _path.relative root, source
  include ?= []
  exclude ?= []

  shouldInclude = (path) ->
    path = _path.relative source, path
    return true if include.length == 0
    for target in include
      return true if path.indexOf(target) == 0
    return false

  shouldExclude = (path) ->
    path = _path.relative source, path
    return false if exclude.length == 0
    for target in exclude
      return true if path.indexOf(target) == 0
    return false


  rsyncOpts =
    destination: destination
    exclude:     ['.git']
    flags:       'avRz'
    shell:       'ssh'

  pvc.source(pvcf.watcher source)
    .filter (event) -> event.type in ['add', 'change']
    .map (event) -> event.path
    .filter (path) -> shouldInclude(path)
    .filter (path) -> !shouldExclude(path)
    .map (path) -> makeRsyncRelativePath source, path, root
    .debounce delay: 300
    .mapAsync (paths, cb) ->
      #console.log 'Trying to rsync', paths
      rsync = Rsync.build rsyncOpts
      rsync.source paths
      rsync.execute (err, code, cmd) ->
          cb err, paths
    .on 'exception', (ex) ->
      console.error 'Exception:', ex
    .on 'data', (paths) ->
      console.log 'Completed rsync of', paths

exports.run = ->
  opts = parseOptions process.argv
  sync opts
