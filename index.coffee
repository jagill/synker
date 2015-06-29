Rsync = require 'rsync'
util = require 'util'
pvc = require 'pvc'
pvcf = require 'pvc-file'
_path = require 'path'

parseOptions = (argv) ->
  program = require 'commander'
  program
    .arguments '<source> <destination>'
    #.option '-c, --checksum', 'Skip updates based on checksum, not mod-time and size.'
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
    .parse(argv)


  if program.args.length != 2
    program.outputHelp()
    process.exit 1

  return {
    destination: program.args[1]
    source: program.args[0]
    #checksum: program.checksum
  }

# Convert a full path like a/b/c/d to /a/b/./c/d if base is a/b/
# This is to make it into the form needed by resync 'relative' option.
# XXX: This assumes that base is a valid base of full.
makeRsyncRelativePath = (base, full) ->
  # FIXME: Probably doesn't handle a base like './' correctly.
  if full.indexOf(base) != 0
    throw new Error "#{base} is not a valid base for #{full}"
  if base.charAt(base.length - 1) == '/'
    base = base.slice 0, -1
  baseParts = base.split _path.sep
  parts = full.split _path.sep
  parts.splice(baseParts.length, 0, '.')
  return parts.join _path.sep

exports.sync = sync = (source, destination) ->

  rsyncOpts =
    destination: destination
    exclude:     ['.git']
    flags:       'avRz'
    shell:       'ssh'

  pvcf.watcher source
    .pipe pvc.filter (event) -> event.type in ['add', 'change']
    .pipe pvc.map (event) -> event.path
    .pipe pvc.map (path) -> makeRsyncRelativePath source, path
    .pipe pvc.debounce delay: 500
    .pipe pvc.mapAsync (paths, cb) ->
      #console.log 'Trying to rsync', paths
      rsync = Rsync.build rsyncOpts
      rsync.source paths
      rsync.execute (err, code, cmd) ->
          cb err, paths
    .on 'data', (paths) ->
      console.log 'Completed rsync of', paths

exports.run = ->
  {source, destination} = parseOptions process.argv
  sync source, destination
