### 2.0.1 / 2013-04-30

* 1 bug fix:

    * Fix not starting on JRuby properly

### 2.0.0 / 2013-04-29

RailsConf 2013 edition!

* 2 doc changes:

    * Start with `rackup -s Puma`, NOT `rackup -s puma`.
    * Minor doc fixes in the README.md, Capistrano section

* 2 bug fixes:

    * Fix reading RACK_ENV properly. Fixes #234
    * Make cap recipe handle tmp/sockets; fixes #228

* 3 minor changes:

    * Fix capistrano recipe
    * Fix stdout/stderr logs to sync outputs
    * Allow binding to IPv6 addresses

### 2.0.0.b7 / 2013-03-18

* 5 minor enhancements:

    * Add `-q` option for `:start`
    * Add `-V`, `--version`
    * Add default Rack handler helper
    * Upstart support
    * Set worker directory from configuration file

* 12 bug fixes:

    * Close the binder in the right place. Fixes #192
    * Handle early term in workers. Fixes #206
    * Make sure that the default port is 80 when the request doesn't include `HTTP_X_FORWARDED_PROTO`.
    * Prevent `Errno::EBADF` errors on restart when running ruby 2.0
    * Record the proper @master_pid
    * Respect the header `HTTP_X_FORWARDED_PROTO` when the host doesn't include a port number.
    * Retry EAGAIN/EWOULDBLOCK during syswrite
    * Run exec properly to restart. Fixes #154
    * Set Rack run_once to false
    * Syncronize all access to @timeouts. Fixes #208
    * Write out the state post-daemonize. Fixes #189
    * Prevent crash when all workers are gone

### 2.0.0.b6 / 2013-02-06

* 2 minor enhancements:

    * Add hook for running when a worker boots
    * Advertise the Configuration object for apps to use.

* 1 bug fix:

    * Change directory in working during upgrade. Fixes #185

### 2.0.0.b5 / 2013-02-05

* 2 major features:

    * Add phased worker upgrade
    * Add support for the rack hijack protocol

* 2 minor features:

    * Add `-R` to specify the restart command
    * Add config file option to specify the restart command

* 5 bug fixes:

    * Cleanup pipes properly. Fixes #182
    * Daemonize earlier so that we don't lose app threads. Fixes #183
    * Drain the notification pipe. Fixes #176, thanks @cryo28
    * Move write_pid to after we daemonize. Fixes #180
    * Redirect IO properly and emit message for checkpointing

### 2.0.0.b4 / 2012-12-12

* 4 bug fixes:

    * Properly check #syswrite's value for variable sized buffers. Fixes #170
    * Shutdown status server properly
    * Handle char vs byte and mixing syswrite with write properly
    * made MiniSSL validate key/cert file existence

### 2.0.0.b3 / 2012-11-22

* 1 bug fix:

    * Package right files in gem

### 2.0.0.b2 / 2012-11-18

* 5 minor features:

    * Now Puma is bundled with an capistrano recipe. Just `require 'puma/capistrano'`
      in you `deploy.rb`
    * Only inject CommonLogger in development mode
    * Add `-p` option to pumactl
    * Add ability to use pumactl to start a server
    * Add options to daemonize puma

* 7 bug fixes:

    * Reset the IOBuffer properly. Fixes #148
    * Shutdown gracefully on JRuby with `Ctrl-C`
    * Various methods to get newrelic to start. Fixes #128
    * fixing syntax error at capistrano recipe
    * Force `ECONNRESET` when read returns nil
    * Be sure to empty the drain the todo before shutting down. Fixes #155
    * Allow for alternate locations for status app

### 2.0.0.b1 / 2012-09-11

* 1 major feature:

    * Optional worker process mode `-w` to allow for process scaling in
      addition to thread scaling

* 1 bug fix:

    * Introduce `Puma::MiniSSL` to be able to properly control doing
      nonblocking SSL

NOTE: SSL support in JRuby is not supported at present. Support will
be added back in a future date when a java `Puma::MiniSSL` is added.

### 1.6.3 / 2012-09-04

* 1 bug fix:

    * Close sockets waiting in the reactor when a hot restart is performed
      so that browsers reconnect on the next request

### 1.6.2 / 2012-08-27

* 1 bug fix:

    * Rescue `StandardError` instead of `IOError` to handle `SystemCallErrors`
      as well as other application exceptions inside the reactor.

### 1.6.1 / 2012-07-23

* 1 packaging bug fixed:

    * Include missing files

### 1.6.0 / 2012-07-23

* 1 major bug fix:

    * Prevent slow clients from starving the server by introducing a
      dedicated IO reactor thread. Credit for reporting goes to @meh.

### 1.5.0 / 2012-07-19

* 7 contributers to this release:

    * Christian Mayer
    * Darío Javier Cravero
    * Dirkjan Bussink
    * Gianluca Padovani
    * Santiago Pastorino
    * Thibault Jouan
    * tomykaira

* 6 bug fixes:

    * Define `RSTRING_NOT_MODIFIED` for Rubinius
    * Convert status to integer. Fixes #123
    * Delete pidfile when stopping the server
    * Allow compilation with `-Werror=format-security` option
    * Fix wrong HTTP version for a HTTP/1.0 request
    * Use `String#bytesize` instead of `String#length`

* 3 minor features:

    * Added support for setting `RACK_ENV` via the CLI, config file, and rack app
    * Allow `Server#run` to run sync. Fixes #111
    * Puma can now run on windows

### 1.4.0 / 2012-06-04

* 1 bug fix:

    * SCRIPT_NAME should be passed from env to allow mounting apps

* 1 experimental feature:

    * Add `puma.socket` key for direct socket access

### 1.3.1 / 2012-05-15

* 2 bug fixes:

    * Use `#bytesize` instead of `#length` for `Content-Length` header
    * Use `StringIO` properly. Fixes #98

### 1.3.0 / 2012-05-08

* 2 minor features:

    * Return valid Rack responses (passes Lint) from status server
    * Add `-I` option to specify `$LOAD_PATH` directories

* 4 bug fixes:

    * Don't join the server thread inside the signal handle. Fixes #94
    * Make `NullIO#read` mimic `IO#read`
    * Only stop the status server if it's started. Fixes #84
    * Set `RACK_ENV` early in CLI also. Fixes #78

* 1 new contributer:

    * Jesse Cooke

### 1.2.2 / 2012-04-28

* 4 bug fixes:

    * Report a lowlevel error to stderr
    * Set a fallback `SERVER_NAME` and `SERVER_PORT`
    * Keep the encoding of the body correct. Fixes #79
    * show `error.to_s` along with backtrace for low-level error

### 1.2.1 / 2012-04-11

* 1 bug fix:

    * Fix `rack.url_scheme` for SSL servers. Fixes #65

### 1.2.0 / 2012-04-11

* 1 major feature:

    * When possible, the internal restart does a "hot restart" meaning
      the server sockets remains open, so no connections are lost.

* 1 minor feature:

    * More helpful fallback error message

* 6 bug fixes:

    * Pass the proper args to unknown_error. Fixes #54, #58
    * Stop the control server before restarting. Fixes #61
    * Fix reporting https only on a true SSL connection
    * Set the default content type to `text/plain`. Fixes #63
    * Use `REUSEADDR`. Fixes #60
    * Shutdown gracefull on SIGTERM. Fixes #53

* 2 new contributers:

    * Seamus Abshere
    * Steve Richert

### 1.1.1 / 2012-03-30

* 1 bugfix:

    * Include `puma/compat.rb` in the gem (oops!)

### 1.1.0 / 2012-03-30

* 1 bugfix:

    * Make sure that the unix socket has the perms `0777` by default

* 1 minor feature:

    * Add umask param to the `unix://` bind to set the umask

### 1.0.0 / 2012-03-29

* Released!
