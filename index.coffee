Rsync = require 'rsync'
util = require 'util'
pvc = require 'pvc'
pvcf = require 'pvc-file'

parseOptions = (argv) ->
  program = require 'commander'
  program
    .arguments '<paths...> <destination>'
    # .option '-d, --destpath <destpath>', 'Remote path on host to sync to.  Default localpath.'
    # .action (host, localpath) ->
    #   opts.host = host
    #   opts.localpath = localpath
    #   # Exit with help if we don't have required info.
    #   program.help() unless opts.host and opts.localpath
    .on '--help', ->
      console.log '  Keep directories in sync.  Watch for changes, and rsync the
                     modified files to the remote host.'
      console.log '  This does not currently delete missing files.
                     More options available on request.'
      console.log ''
      console.log '  Arguments:'
      console.log '    paths: Local paths to sync.  They are recursive.'
      console.log '    destination: rsync style destination, eg somehost:some/path/'
      console.log ''
      console.log '  Examples:'
      console.log ''
      console.log '    ## sync my/dir/ with foo.example.com:my/dir/'
      console.log '    $ synker my/dir/ foo.example.com:my/dir/'
      console.log '    ## sync my/dir/*.py with foo.example.com:otherdir/'
      console.log '    $ synker my/dir/*.py foo.example.com:otherdir/'
    .parse(argv)


  if program.args.length < 2
    program.outputHelp()
    process.exit 1

  destination = program.args.pop()
  return {
    destination: destination
    paths: program.args.slice(0)
  }

exports.sync = sync = (opts) ->

  rsyncOpts =
    destination: opts.destination
    exclude:     ['.git']
    flags:       'auvz'
    shell:       'ssh'

  pvcf.watcher opts.paths
    .pipe pvc.filter (event) -> event.type in ['add', 'change']
    .pipe pvc.map (event) -> event.path
    .pipe pvc.debounce delay: 500
    .pipe pvc.mapAsync (paths, cb) ->
      console.log 'Trying to rsync', paths
      rsync = Rsync.build rsyncOpts
      rsync.source paths
      rsync.execute (err, code, cmd) ->
          cb err, paths
    .on 'data', (paths) ->
      console.log 'Completed rsync of', paths
    .on 'error', (err) ->
      console.error err

exports.run = ->
  opts = parseOptions process.argv
  sync opts
