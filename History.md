## Master

* Features
  * Your feature goes here <Most recent on the top, like GitHub> (#Github Number)

* Bugfixes
  * Your bugfix goes here <Most recent on the top, like GitHub> (#Github Number)

## 5.0.2 / 2020-09-28

* Bugfixes 
  * Reverted API changes to Server.

## 5.0.1 / 2020-09-28

* Bugfixes
  * Fix LoadError in CentOS 8 ([#2381])
  * Better error handling during force shutdown ([#2271])
  * Prevent connections from entering Reactor after shutdown begins ([#2377])
  * Fix error backtrace debug logging && Do not log request dump if it is not parsed ([#2376])
  * Split TCP_CORK and TCP_INFO ([#2372])
  * Do not log EOFError when a client connection is closed without write ([#2384])

* Refactor
  * Change Events#ssl_error signature from (error, peeraddr, peercert) to (error, ssl_socket) ([#2375])
  * Consolidate option handling in Server, Server small refactors, doc chang ([#2373])

## 5.0.0 / 2020-09-17

* Features
  * Allow compiling without OpenSSL and dynamically load files needed for SSL, add 'no ssl' CI ([#2305])
  * EXPERIMENTAL: Add `fork_worker` option and `refork` command for reduced memory usage by forking from a worker process instead of the master process. ([#2099])
  * EXPERIMENTAL: Added `wait_for_less_busy_worker` config. This may reduce latency on MRI through inserting a small delay before re-listening on the socket if worker is busy ([#2079]).
  * EXPERIMENTAL: Added `nakayoshi_fork` option. Reduce memory usage in preloaded cluster-mode apps by GCing before fork and compacting, where available. ([#2093], [#2256])
  * Added pumactl `thread-backtraces` command to print thread backtraces ([#2054])
  * Added incrementing `requests_count` to `Puma.stats`. ([#2106])
  * Increased maximum URI path length from 2048 to 8192 bytes ([#2167], [#2344])
  * `lowlevel_error_handler` is now called during a forced threadpool shutdown, and if a callable with 3 arguments is set, we now also pass the status code ([#2203])
  * Faster phased restart and worker timeout ([#2220])
  * Added `state_permission` to config DSL to set state file permissions ([#2238])
  * Added `Puma.stats_hash`, which returns a stats in Hash instead of a JSON string ([#2086], [#2253])
  * `rack.multithread` and `rack.multiprocess` now dynamically resolved by `max_thread` and `workers` respectively ([#2288])

* Deprecations, Removals and Breaking API Changes
  * `--control` has been removed. Use `--control-url` ([#1487])
  * `worker_directory` has been removed. Use `directory`.
  * min_threads now set by environment variables PUMA_MIN_THREADS and MIN_THREADS. ([#2143])
  * max_threads now set by environment variables PUMA_MAX_THREADS and MAX_THREADS. ([#2143])
  * max_threads default to 5 in MRI or 16 for all other interpreters. ([#2143])
  * preload by default if workers > 1 ([#2143])
  * Puma::Plugin.workers_supported? has been removed. Use Puma.forkable? instead. ([#2143])
  * `tcp_mode` has been removed without replacement. ([#2169])
  * Daemonization has been removed without replacement. ([#2170])
  * Changed #connected_port to #connected_ports ([#2076])
  * Configuration: `environment` is read from `RAILS_ENV`, if `RACK_ENV` can't be found ([#2022])
  * Log binding on http:// for TCP bindings to make it clickable

* Bugfixes
  * Fix JSON loading issues on phased-restarts ([#2269])
  * Improve shutdown reliability ([#2312], [#2338])
  * Close client http connections made to an ssl server with TLSv1.3 ([#2116])
  * Do not set user_config to quiet by default to allow for file config ([#2074])
  * Always close SSL connection in Puma::ControlCLI ([#2211])
  * Windows update extconf.rb for use with ssp and varied Ruby/MSYS2 combinations ([#2069])
  * Ensure control server Unix socket is closed on shutdown ([#2112])
  * Preserve `BUNDLE_GEMFILE` env var when using `prune_bundler` ([#1893])
  * Send 408 request timeout even when queue requests is disabled ([#2119])
  * Rescue IO::WaitReadable instead of EAGAIN for blocking read ([#2121])
  * Ensure `BUNDLE_GEMFILE` is unspecified in workers if unspecified in master when using `prune_bundler` ([#2154])
  * Rescue and log exceptions in hooks defined by users (on_worker_boot, after_worker_fork etc) ([#1551])
  * Read directly from the socket in #read_and_drop to avoid raising further SSL errors ([#2198])
  * Set `Connection: closed` header when queue requests is disabled ([#2216])
  * Pass queued requests to thread pool on server shutdown ([#2122])
  * Fixed a few minor concurrency bugs in ThreadPool that may have affected non-GVL Rubies ([#2220])
  * Fix `out_of_band` hook never executed if the number of worker threads is > 1 ([#2177])
  * Fix ThreadPool#shutdown timeout accuracy ([#2221])
  * Fix `UserFileDefaultOptions#fetch` to properly use `default` ([#2233])
  * Improvements to `out_of_band` hook ([#2234])
  * Prefer the rackup file specified by the CLI ([#2225])
  * Fix for spawning subprocesses with fork_worker option ([#2267])
  * Set `CONTENT_LENGTH` for chunked requests ([#2287])
  * JRuby - Add Puma::MiniSSL::Engine#init? and #teardown methods, run all SSL tests ([#2317])
  * Improve shutdown reliability ([#2312])
  * Resolve issue with threadpool waiting counter decrement when thread is killed
  * Constrain rake-compiler version to 0.9.4 to fix `ClassNotFound` exception when using MiniSSL with Java8.
  * Fix recursive `prune_bundler` ([#2319]).
  * Ensure that TCP_CORK is usable
  * Fix corner case when request body is chunked ([#2326])
  * Fix filehandle leak in MiniSSL ([#2299])

* Refactor
  * Remove unused loader argument from Plugin initializer ([#2095])
  * Simplify `Configuration.random_token` and remove insecure fallback ([#2102])
  * Simplify `Runner#start_control` URL parsing ([#2111])
  * Removed the IOBuffer extension and replaced with Ruby ([#1980])
  * Update `Rack::Handler::Puma.run` to use `**options` ([#2189])
  * ThreadPool concurrency refactoring ([#2220])
  * JSON parse cluster worker stats instead of regex ([#2124])
  * Support parallel tests in verbose progress reporting ([#2223])
  * Refactor error handling in server accept loop ([#2239])

## 4.3.6 / 2020-09-05

* Bugfixes
  * Explicitly include ctype.h to fix compilation warning and build error on macOS with Xcode 12 ([#2304])
  * Don't require json at boot ([#2269])

## 4.3.4/4.3.5 and 3.12.5/3.12.6 / 2020-05-22

Each patchlevel release contains a separate security fix. We recommend simply upgrading to 4.3.5/3.12.6.

* Security
  * Fix: Fixed two separate HTTP smuggling vulnerabilities that used the Transfer-Encoding header. CVE-2020-11076 and CVE-2020-11077.

## 4.3.3 and 3.12.4 / 2020-02-28

* Bugfixes
  * Fix: Fixes a problem where we weren't splitting headers correctly on newlines ([#2132])
* Security
  * Fix: Prevent HTTP Response splitting via CR in early hints. CVE-2020-5249.

## 4.3.2 and 3.12.3 / 2020-02-27 (YANKED)

* Security
  * Fix: Prevent HTTP Response splitting via CR/LF in header values. CVE-2020-5247.

## 4.3.1 and 3.12.2 / 2019-12-05

* Security
  * Fix: a poorly-behaved client could use keepalive requests to monopolize Puma's reactor and create a denial of service attack. CVE-2019-16770.

## 4.3.0 / 2019-11-07

* Features
  * Strip whitespace at end of HTTP headers ([#2010])
  * Optimize HTTP parser for JRuby ([#2012])
  * Add SSL support for the control app and cli ([#2046], [#2052])

* Bugfixes
  * Fix Errno::EINVAL when SSL is enabled and browser rejects cert ([#1564])
  * Fix pumactl defaulting puma to development if an environment was not specified ([#2035])
  * Fix closing file stream when reading pid from pidfile ([#2048])
  * Fix a typo in configuration option `--extra_runtime_dependencies` ([#2050])

## 4.2.1 / 2019-10-07

* 3 bugfixes
  * Fix socket activation of systemd (pre-existing) unix binder files ([#1842], [#1988])
  * Deal with multiple calls to bind correctly ([#1986], [#1994], [#2006])
  * Accepts symbols for `verify_mode` ([#1222])

## 4.2.0 / 2019-09-23

* 6 features
  * Pumactl has a new -e environment option and reads `config/puma/<environment>.rb` config files ([#1885])
  * Semicolons are now allowed in URL paths (MRI only), useful for Angular or Redmine ([#1934])
  * Allow extra dependencies to be defined when using prune_bundler ([#1105])
  * Puma now reports the correct port when binding to port 0, also reports other listeners when binding to localhost ([#1786])
  * Sending SIGINFO to any Puma worker now prints currently active threads and their backtraces ([#1320])
  * Puma threads all now have their name set on Ruby 2.3+ ([#1968])
* 4 bugfixes
  * Fix some misbehavior with phased restart and externally SIGTERMed workers ([#1908], [#1952])
  * Fix socket closing on error ([#1941])
  * Removed unnecessary SIGINT trap for JRuby that caused some race conditions ([#1961])
  * Fix socket files being left around after process stopped ([#1970])
* Absolutely thousands of lines of test improvements and fixes thanks to @MSP-Greg

## 4.1.1 / 2019-09-05

* 3 bugfixes
  * Revert our attempt to not dup STDOUT/STDERR ([#1946])
  * Fix socket close on error ([#1941])
  * Fix workers not shutting down correctly ([#1908])

## 4.1.0 / 2019-08-08

* 4 features
  * Add REQUEST_PATH on parse error message ([#1831])
  * You can now easily add custom log formatters with the `log_formatter` config option ([#1816])
  * Puma.stats now provides process start times ([#1844])
  * Add support for disabling TLSv1.1 ([#1836])

* 7 bugfixes
  * Fix issue where Puma was creating zombie process entries ([#1887])
  * Fix bugs with line-endings and chunked encoding ([#1812])
  * RACK_URL_SCHEME is now set correctly in all conditions ([#1491])
  * We no longer mutate global STDOUT/STDERR, particularly the sync setting ([#1837])
  * SSL read_nonblock no longer blocks ([#1857])
  * Swallow connection errors when sending early hints ([#1822])
  * Backtrace no longer dumped when invalid pumactl commands are run ([#1863])

* 5 other
  * Avoid casting worker_timeout twice ([#1838])
  * Removed a call to private that wasn't doing anything ([#1882])
  * README, Rakefile, docs and test cleanups ([#1848], [#1847], [#1846], [#1853], #1859, [#1850], [#1866], [#1870], [#1872], [#1833], [#1888])
  * Puma.io has proper documentation now (https://puma.io/puma/)
  * Added the Contributor Covenant CoC

* 1 known issue
  * Some users are still experiencing issues surrounding socket activation and Unix sockets ([#1842])

## 4.0.1 / 2019-07-11

* 2 bugfixes
  * Fix socket removed after reload - should fix problems with systemd socket activation. ([#1829])
  * Add extconf tests for DTLS_method & TLS_server_method, use in minissl.rb. Should fix "undefined symbol: DTLS_method" when compiling against old OpenSSL versions. ([#1832])
* 1 other
  * Removed unnecessary RUBY_VERSION checks. ([#1827])

## 4.0.0 / 2019-06-25

* 9 features
  * Add support for disabling TLSv1.0 ([#1562])
  * Request body read time metric ([#1569])
  * Add out_of_band hook ([#1648])
  * Re-implement (native) IOBuffer for JRuby ([#1691])
  * Min worker timeout ([#1716])
  * Add option to suppress SignalException on SIGTERM ([#1690])
  * Allow mutual TLS CA to be set using `ssl_bind` DSL ([#1689])
  * Reactor now uses nio4r instead of `select` ([#1728])
  * Add status to pumactl with pidfile ([#1824])

* 10 bugfixes
  * Do not accept new requests on shutdown ([#1685], [#1808])
  * Fix 3 corner cases when request body is chunked ([#1508])
  * Change pid existence check's condition branches ([#1650])
  * Don't call .stop on a server that doesn't exist ([#1655])
  * Implemented NID_X9_62_prime256v1 (P-256) curve over P-521 ([#1671])
  * Fix @notify.close can't modify frozen IOError (RuntimeError) ([#1583])
  * Fix Java 8 support ([#1773])
  * Fix error `uninitialized constant Puma::Cluster` ([#1731])
  * Fix `not_token` being able to be set to true ([#1803])
  * Fix "Hang on SIGTERM with ruby 2.6 in clustered mode" (PR [#1741], [#1674], [#1720], [#1730], [#1755])

## 3.12.1 / 2019-03-19

* 1 features
  * Internal strings are frozen ([#1649])
* 3 bugfixes
  * Fix chunked ending check ([#1607])
  * Rack handler should use provided default host ([#1700])
  * Better support for detecting runtimes that support `fork` ([#1630])

## 3.12.0 / 2018-07-13

* 5 features:
  * You can now specify which SSL ciphers the server should support, default is unchanged ([#1478])
  * The setting for Puma's `max_threads` is now in `Puma.stats` ([#1604])
  * Pool capacity is now in `Puma.stats` ([#1579])
  * Installs restricted to Ruby 2.2+ ([#1506])
  * `--control` is now deprecated in favor of `--control-url` ([#1487])

* 2 bugfixes:
  * Workers will no longer accept more web requests than they have capacity to process. This prevents an issue where one worker would accept lots of requests while starving other workers ([#1563])
  * In a test env puma now emits the stack on an exception ([#1557])

## 3.11.4 / 2018-04-12

* 2 features:
  * Manage puma as a service using rc.d ([#1529])
  * Server stats are now available from a top level method ([#1532])
* 5 bugfixes:
  * Fix parsing CLI options ([#1482])
  * Order of stderr and stdout is made before redirecting to a log file ([#1511])
  * Init.d fix of `ps -p` to check if pid exists ([#1545])
  * Early hints bugfix ([#1550])
  * Purge interrupt queue when closing socket fails ([#1553])

## 3.11.3 / 2018-03-05

* 3 bugfixes:
  * Add closed? to MiniSSL::Socket for use in reactor ([#1510])
  * Handle EOFError at the toplevel of the server threads ([#1524]) ([#1507])
  * Deal with zero sized bodies when using SSL ([#1483])

## 3.11.2 / 2018-01-19

* 1 bugfix:
  * Deal with read\_nonblock returning nil early

## 3.11.1 / 2018-01-18

* 1 bugfix:
  * Handle read\_nonblock returning nil when the socket close ([#1502])

## 3.11.0 / 2017-11-20

* 2 features:
  * HTTP 103 Early Hints ([#1403])
  * 421/451 status codes now have correct status messages attached ([#1435])

* 9 bugfixes:
  * Environment config files (/config/puma/<ENV>.rb) load correctly ([#1340])
  * Specify windows dependencies correctly ([#1434], [#1436])
  * puma/events required in test helper ([#1418])
  * Correct control CLI's option help text ([#1416])
  * Remove a warning for unused variable in mini_ssl ([#1409])
  * Correct pumactl docs argument ordering ([#1427])
  * Fix an uninitialized variable warning in server.rb ([#1430])
  * Fix docs typo/error in Launcher init ([#1429])
  * Deal with leading spaces in RUBYOPT ([#1455])

* 2 other:
  * Add docs about internals ([#1425], [#1452])
  * Tons of test fixes from @MSP-Greg ([#1439], [#1442], [#1464])

## 3.10.0 / 2017-08-17

* 3 features:
  * The status server has a new /gc and /gc-status command. ([#1384])
  * The persistent and first data timeouts are now configurable ([#1111])
  * Implemented RFC 2324 ([#1392])

* 12 bugfixes:
  * Not really a Puma bug, but @NickolasVashchenko created a gem to workaround a Ruby bug that some users of Puma may be experiencing. See README for more. ([#1347])
  * Fix hangups with SSL and persistent connections. ([#1334])
  * Fix Rails double-binding to a port ([#1383])
  * Fix incorrect thread names ([#1368])
  * Fix issues with /etc/hosts and JRuby where localhost addresses were not correct. ([#1318])
  * Fix compatibility with RUBYOPT="--enable-frozen-string-literal" ([#1376])
  * Fixed some compiler warnings ([#1388])
  * We actually run the integration tests in CI now ([#1390])
  * No longer shipping unnecessary directories in the gemfile ([#1391])
  * If RUBYOPT is nil, we no longer blow up on restart. ([#1385])
  * Correct response to SIGINT ([#1377])
  * Proper exit code returned when we receive a TERM signal ([#1337])

* 3 refactors:
  * Various test improvements from @grosser
  * Rubocop ([#1325])
  * Hoe has been removed ([#1395])

* 1 known issue:
  * Socket activation doesn't work in JRuby. Their fault, not ours. ([#1367])

## 3.9.1 / 2017-06-03

* 2 bugfixes:
  * Fixed compatibility with older Bundler versions ([#1314])
  * Some internal test/development cleanup ([#1311], [#1313])

## 3.9.0 / 2017-06-01

* 2 features:
  * The ENV is now reset to its original values when Puma restarts via USR1/USR2 ([#1260]) (MRI only, no JRuby support)
  * Puma will no longer accept more clients than the maximum number of threads. ([#1278])

* 9 bugfixes:
  * Reduce information leakage by preventing HTTP parse errors from writing environment hashes to STDERR ([#1306])
  * Fix SSL/WebSocket compatibility ([#1274])
  * HTTP headers with empty values are no longer omitted from responses. ([#1261])
  * Fix a Rack env key which was set to nil. ([#1259])
  * peercert has been implemented for JRuby ([#1248])
  * Fix port settings when using rails s ([#1277], [#1290])
  * Fix compat w/LibreSSL ([#1285])
  * Fix restarting Puma w/symlinks and a new Gemfile ([#1282])
  * Replace Dir.exists? with Dir.exist? ([#1294])

* 1 known issue:
  * A bug in MRI 2.2+ can result in IOError: stream closed. See [#1206]. This issue has existed since at least Puma 3.6, and probably further back.

* 1 refactor:
  * Lots of test fixups from @grosser.

## 3.8.2 / 2017-03-14

* 1 bugfix:
  * Deal with getsockopt with TCP\_INFO failing for sockets that say they're TCP but aren't really. ([#1241])

## 3.8.1 / 2017-03-10

* 1 bugfix:
  * Remove method call to method that no longer exists ([#1239])

## 3.8.0 / 2017-03-09

* 2 bugfixes:
  * Port from rack handler does not take precedence over config file in Rails 5.1.0.beta2+ and 5.0.1.rc3+ ([#1234])
  * The `tmp/restart.txt` plugin no longer restricts the user from running more than one server from the same folder at a time ([#1226])

* 1 feature:
  * Closed clients are aborted to save capacity ([#1227])

* 1 refactor:
  * Bundler is no longer a dependency from tests ([#1213])

## 3.7.1 / 2017-02-20

* 2 bugfixes:
  * Fix typo which blew up MiniSSL ([#1182])
  * Stop overriding command-line options with the config file ([#1203])

## 3.7.0 / 2017-01-04

* 6 minor features:
  * Allow rack handler to accept ssl host. ([#1129])
  * Refactor TTOU processing. TTOU now handles multiple signals at once. ([#1165])
  * Pickup any remaining chunk data as the next request.
  * Prevent short term thread churn - increased auto trim default to 30 seconds.
  * Raise error when `stdout` or `stderr` is not writable. ([#1175])
  * Add Rack 2.0 support to gemspec. ([#1068])

* 5 refactors:
  * Compare host and server name only once per call. ([#1091])
  * Minor refactor on Thread pool ([#1088])
  * Removed a ton of unused constants, variables and files.
  * Use MRI macros when allocating heap memory
  * Use hooks for on\_booted event. ([#1160])

* 14 bugfixes:
  * Add eof? method to NullIO? ([#1169])
  * Fix Puma startup in provided init.d script ([#1061])
  * Fix default SSL mode back to none. ([#1036])
  * Fixed the issue of @listeners getting nil io ([#1120])
  * Make `get_dh1024` compatible with OpenSSL v1.1.0 ([#1178])
  * More gracefully deal with SSL sessions. Fixes [#1002]
  * Move puma.rb to just autoloads. Fixes [#1063]
  * MiniSSL: Provide write as <<. Fixes [#1089]
  * Prune bundler should inherit fds ([#1114])
  * Replace use of Process.getpgid which does not behave as intended on all platforms ([#1110])
  * Transfer encoding header should be downcased before comparison ([#1135])
  * Use same write log logic for hijacked requests. ([#1081])
  * Fix `uninitialized constant Puma::StateFile` ([#1138])
  * Fix access priorities of each level in LeveledOptions ([#1118])

* 3 others:

  * Lots of tests added/fixed/improved. Switched to Minitest from Test::Unit. Big thanks to @frodsan.
  * Lots of documentation added/improved.
  * Add license indicators to the HTTP extension. ([#1075])

## 3.6.2 / 2016-11-22

* 1 bug fix:

  * Revert [#1118]/Fix access priorities of each level in LeveledOptions. This
    had an unintentional side effect of changing the importance of command line
    options, such as -p.

## 3.6.1 / 2016-11-21

* 8 bug fixes:

  * Fix Puma start in init.d script.
  * Fix default SSL mode back to none. Fixes [#1036]
  * Fixed the issue of @listeners getting nil io, fix rails restart ([#1120])
  * More gracefully deal with SSL sessions. Fixes [#1002]
  * Prevent short term thread churn.
  * Provide write as <<. Fixes [#1089]
  * Fix access priorities of each level in LeveledOptions - fixes TTIN.
  * Stub description files updated for init.d.

* 2 new project committers:

  * Nate Berkopec (@nateberkopec)
  * Richard Schneeman (@schneems)

## 3.6.0 / 2016-07-24

* 12 bug fixes:
  * Add ability to detect a shutting down server. Fixes [#932]
  * Add support for Expect: 100-continue. Fixes [#519]
  * Check SSLContext better. Fixes [#828]
  * Clarify behavior of '-t num'. Fixes [#984]
  * Don't default to VERIFY_PEER. Fixes [#1028]
  * Don't use ENV['PWD'] on windows. Fixes [#1023]
  * Enlarge the scope of catching app exceptions. Fixes [#1027]
  * Execute background hooks after daemonizing. Fixes [#925]
  * Handle HUP as a stop unless there is IO redirection. Fixes [#911]
  * Implement chunked request handling. Fixes [#620]
  * Just rescue exception to return a 500. Fixes [#1027]
  * Redirect IO in the jruby daemon mode. Fixes [#778]

## 3.5.2 / 2016-07-20

* 1 bug fix:
  * Don't let persistent_timeout be nil

* 1 PR merged:
  * Merge pull request [#1021] from benzrf/patch-1

## 3.5.1 / 2016-07-20

* 1 bug fix:
  * Be sure to only listen on host:port combos once. Fixes [#1022]

## 3.5.0 / 2016-07-18

* 1 minor features:
  * Allow persistent_timeout to be configured via the dsl.

* 9 bug fixes:
  * Allow a bare % in a query string. Fixes [#958]
  * Explicitly listen on all localhost addresses. Fixes [#782]
  * Fix `TCPLogger` log error in tcp cluster mode.
  * Fix puma/puma[#968] Cannot bind SSL port due to missing verify_mode option
  * Fix puma/puma[#968] Default verify_mode to peer
  * Log any exceptions in ThreadPool. Fixes [#1010]
  * Silence connection errors in the reactor. Fixes [#959]
  * Tiny fixes in hook documentation for [#840]
  * It should not log requests if we want it to be quiet

* 5 doc fixes:
  * Add How to stop Puma on Heroku using plugins to the example directory
  * Provide both hot and phased restart in jungle script
  * Update reference to the instances management script
  * Update default number of threads
  * Fix typo in example config

* 14 PRs merged:
  * Merge pull request [#1007] from willnet/patch-1
  * Merge pull request [#1014] from jeznet/patch-1
  * Merge pull request [#1015] from bf4/patch-1
  * Merge pull request [#1017] from jorihardman/configurable_persistent_timeout
  * Merge pull request [#954] from jf/master
  * Merge pull request [#955] from jf/add-request-info-to-standard-error-rescue
  * Merge pull request [#956] from maxkwallace/master
  * Merge pull request [#960] from kmayer/kmayer-plugins-heroku-restart
  * Merge pull request [#969] from frankwong15/master
  * Merge pull request [#970] from willnet/delete-blank-document
  * Merge pull request [#974] from rocketjob/feature/name_threads
  * Merge pull request [#977] from snow/master
  * Merge pull request [#981] from zach-chai/patch-1
  * Merge pull request [#993] from scorix/master

## 3.4.0 / 2016-04-07

* 2 minor features:
  * Add ability to force threads to stop on shutdown. Fixes [#938]
  * Detect and commit seppuku when fork(2) fails. Fixes [#529]

* 3 unknowns:
  * Ignore errors trying to update the backport tables. Fixes [#788]
  * Invoke the lowlevel_error in more places to allow for exception tracking. Fixes [#894]
  * Update the query string when an absolute URI is used. Fixes [#937]

* 5 doc fixes:
  * Add Process Monitors section to top-level README
  * Better document the hooks. Fixes [#840]
  * docs/system.md sample config refinements and elaborations
  * Fix typos at couple of places.
  * Cleanup warnings

* 3 PRs merged:
  * Merge pull request [#945] from dekellum/systemd-docs-refined
  * Merge pull request [#946] from vipulnsward/rm-pid
  * Merge pull request [#947] from vipulnsward/housekeeping-typos

## 3.3.0 / 2016-04-05

* 2 minor features:
  * Allow overriding options of Configuration object
  * Rename to inherit_ssl_listener like inherit_tcp|unix

* 2 doc fixes:
  * Add docs/systemd.md (with socket activation sub-section)
  * Document UNIX signals with cluster on README.md

* 3 PRs merged:
  * Merge pull request [#936] from prathamesh-sonpatki/allow-overriding-config-options
  * Merge pull request [#940] from kyledrake/signalsdoc
  * Merge pull request [#942] from dekellum/socket-activate-improve

## 3.2.0 / 2016-03-20

* 1 deprecation removal:
  * Delete capistrano.rb

* 3 bug fixes:
  * Detect gems.rb as well as Gemfile
  * Simplify and fix logic for directory to use when restarting for all phases
  * Speed up phased-restart start

* 2 PRs merged:
  * Merge pull request [#927] from jlecour/gemfile_variants
  * Merge pull request [#931] from joneslee85/patch-10

## 3.1.1 / 2016-03-17

* 4 bug fixes:
  * Disable USR1 usage on JRuby
  * Fixes [#922] - Correctly define file encoding as UTF-8
  * Set a more explicit SERVER_SOFTWARE Rack variable
  * Show RUBY_ENGINE_VERSION if available. Fixes [#923]

* 3 PRs merged:
  * Merge pull request [#912] from tricknotes/fix-allow-failures-in-travis-yml
  * Merge pull request [#921] from swrobel/patch-1
  * Merge pull request [#924] from tbrisker/patch-1

## 3.1.0 / 2016-03-05

* 1 minor feature:
  * Add 'import' directive to config file. Fixes [#916]

* 5 bug fixes:
  * Add 'fetch' to options. Fixes [#913]
  * Fix jruby daemonization. Fixes [#918]
  * Recreate the proper args manually. Fixes [#910]
  * Require 'time' to get iso8601. Fixes [#914]

## 3.0.2 / 2016-02-26

* 5 bug fixes:

  * Fix 'undefined local variable or method `pid` for #<Puma::ControlCLI:0x007f185fcef968>' when execute pumactl with `--pid` option.
  * Fix 'undefined method `windows?` for Puma:Module' when execute pumactl.
  * Harden tmp_restart against errors related to the restart file
  * Make `plugin :tmp_restart` behavior correct in Windows.
  * fix uninitialized constant Puma::ControlCLI::StateFile

* 3 PRs merged:

  * Merge pull request [#901] from mitto/fix-pumactl-uninitialized-constant-statefile
  * Merge pull request [#902] from corrupt952/fix_undefined_method_and_variable_when_execute_pumactl
  * Merge pull request [#905] from Eric-Guo/master

## 3.0.1 / 2016-02-25

* 1 bug fix:

  * Removed the experimental support for async.callback as it broke
    websockets entirely. Seems no server has both hijack and async.callback
    and thus faye is totally confused what to do and doesn't work.

## 3.0.0 / 2016-02-25

* 2 major changes:

  * Ruby pre-2.0 is no longer supported. We'll do our best to not add
    features that break those rubies but will no longer be testing
    with them.
  * Don't log requests by default. Fixes [#852]

* 2 major features:

  * Plugin support! Plugins can interact with configuration as well
    as provide augment server functionality!
  * Experimental env['async.callback'] support

* 4 minor features:

  * Listen to unix socket with provided backlog if any
  * Improves the clustered stats to report worker stats
  * Pass the env to the lowlevel_error handler. Fixes [#854]
  * Treat path-like hosts as unix sockets. Fixes [#824]

* 5 bug fixes:

  * Clean thread locals when using keepalive. Fixes [#823]
  * Cleanup compiler warnings. Fixes [#815]
  * Expose closed? for use by the reactor. Fixes [#835]
  * Move signal handlers to separate method to prevent space leak. Fixes [#798]
  * Signal not full on worker exit [#876]

* 5 doc fixes:

  * Update README.md with various grammar fixes
  * Use newest version of Minitest
  * Add directory configuration docs, fix typo [ci skip]
  * Remove old COPYING notice. Fixes [#849]

* 10 merged PRs:

  * Merge pull request [#871] from deepj/travis
  * Merge pull request [#874] from wallclockbuilder/master
  * Merge pull request [#883] from dadah89/igor/trim_only_worker
  * Merge pull request [#884] from uistudio/async-callback
  * Merge pull request [#888] from mlarraz/tick_minitest
  * Merge pull request [#890] from todd/directory_docs
  * Merge pull request [#891] from ctaintor/improve_clustered_status
  * Merge pull request [#893] from spastorino/add_missing_require
  * Merge pull request [#897] from zendesk/master
  * Merge pull request [#899] from kch/kch-readme-fixes

## 2.16.0 / 2016-01-27

* 7 minor features:

  * Add 'set_remote_address' config option
  * Allow to run puma in silent mode
  * Expose cli options in DSL
  * Support passing JRuby keystore info in ssl_bind DSL
  * Allow umask for unix:/// style control urls
  * Expose `old_worker_count` in stats url
  * Support TLS client auth (verify_mode) in jruby

* 7 bug fixes:

  * Don't persist before_fork hook in state file
  * Reload bundler before pulling in rack. Fixes [#859]
  * Remove NEWRELIC_DISPATCHER env variable
  * Cleanup C code
  * Use Timeout.timeout instead of Object.timeout
  * Make phased restarts faster
  * Ignore the case of certain headers, because HTTP

* 1 doc changes:

  * Test against the latest Ruby 2.1, 2.2, 2.3, head and JRuby 9.0.4.0 on Travis

* 12 merged PRs
  * Merge pull request [#822] from kwugirl/remove_NEWRELIC_DISPATCHER
  * Merge pull request [#833] from joemiller/jruby-client-tls-auth
  * Merge pull request [#837] from YuriSolovyov/ssl-keystore-jruby
  * Merge pull request [#839] from mezuka/master
  * Merge pull request [#845] from deepj/timeout-deprecation
  * Merge pull request [#846] from sriedel/strip_before_fork
  * Merge pull request [#850] from deepj/travis
  * Merge pull request [#853] from Jeffrey6052/patch-1
  * Merge pull request [#857] from zendesk/faster_phased_restarts
  * Merge pull request [#858] from mlarraz/fix_some_warnings
  * Merge pull request [#860] from zendesk/expose_old_worker_count
  * Merge pull request [#861] from zendesk/allow_control_url_umask

## 2.15.3 / 2015-11-07

* 1 bug fix:

  * Fix JRuby parser

## 2.15.2 / 2015-11-06

* 2 bug fixes:
  * ext/puma_http11: handle duplicate headers as per RFC
  * Only set ctx.ca iff there is a params['ca'] to set with.

* 2 PRs merged:
  * Merge pull request [#818] from unleashed/support-duplicate-headers
  * Merge pull request [#819] from VictorLowther/fix-ca-and-verify_null-exception

## 2.15.1 / 2015-11-06

* 1 bug fix:

  * Allow older openssl versions

## 2.15.0 / 2015-11-06

* 6 minor features:
  * Allow setting ca without setting a verify mode
  * Make jungle for init.d support rbenv
  * Use SSL_CTX_use_certificate_chain_file for full chain
  * cluster: add worker_boot_timeout option
  * configuration: allow empty tags to mean no tag desired
  * puma/cli: support specifying STD{OUT,ERR} redirections and append mode

* 5 bug fixes:
  * Disable SSL Compression
  * Fix bug setting worker_directory when using a symlink directory
  * Fix error message in DSL that was slightly inaccurate
  * Pumactl: set correct process name. Fixes [#563]
  * thread_pool: fix race condition when shutting down workers

* 10 doc fixes:
  * Add before_fork explanation in Readme.md
  * Correct spelling in DEPLOYMENT.md
  * Correct spelling in docs/nginx.md
  * Fix spelling errors.
  * Fix typo in deployment description
  * Fix typos (it's -> its) in events.rb and server.rb
  * fixing for typo mentioned in [#803]
  * Spelling correction for README
  * thread_pool: fix typos in comment
  * More explicit docs for worker_timeout

* 18 PRs merged:
  * Merge pull request [#768] from nathansamson/patch-1
  * Merge pull request [#773] from rossta/spelling_corrections
  * Merge pull request [#774] from snow/master
  * Merge pull request [#781] from sunsations/fix-typo
  * Merge pull request [#791] from unleashed/allow_empty_tags
  * Merge pull request [#793] from robdimarco/fix-working-directory-symlink-bug
  * Merge pull request [#794] from peterkeen/patch-1
  * Merge pull request [#795] from unleashed/redirects-from-cmdline
  * Merge pull request [#796] from cschneid/fix_dsl_message
  * Merge pull request [#799] from annafw/master
  * Merge pull request [#800] from liamseanbrady/fix_typo
  * Merge pull request [#801] from scottjg/ssl-chain-file
  * Merge pull request [#802] from scottjg/ssl-crimes
  * Merge pull request [#804] from burningTyger/patch-2
  * Merge pull request [#809] from unleashed/threadpool-fix-race-in-shutdown
  * Merge pull request [#810] from vlmonk/fix-pumactl-restart-bug
  * Merge pull request [#814] from schneems/schneems/worker_timeout-docs
  * Merge pull request [#817] from unleashed/worker-boot-timeout

## 2.14.0 / 2015-09-18

* 1 minor feature:
  * Make building with SSL support optional

* 1 bug fix:
  * Use Rack::Builder if available. Fixes [#735]

## 2.13.4 / 2015-08-16

* 1 bug fix:
  * Use the environment possible set by the config early and from
    the config file later (if set).

## 2.13.3 / 2015-08-15

Seriously, I need to revamp config with tests.

* 1 bug fix:
  * Fix preserving options before cleaning for state. Fixes [#769]

## 2.13.2 / 2015-08-15

The "clearly I don't have enough tests for the config" release.

* 1 bug fix:
  * Fix another place binds wasn't initialized. Fixes [#767]

## 2.13.1 / 2015-08-15

* 2 bug fixes:
  * Fix binds being masked in config files. Fixes [#765]
  * Use options from the config file properly in pumactl. Fixes [#764]

## 2.13.0 / 2015-08-14

* 1 minor feature:
  * Add before_fork hooks option.

* 3 bug fixes:
  * Check for OPENSSL_NO_ECDH before using ECDH
  * Eliminate logging overhead from JRuby SSL
  * Prefer cli options over config file ones. Fixes [#669]

* 1 deprecation:
  * Add deprecation warning to capistrano.rb. Fixes [#673]

* 4 PRs merged:
  * Merge pull request [#668] from kcollignon/patch-1
  * Merge pull request [#754] from nathansamson/before_boot
  * Merge pull request [#759] from BenV/fix-centos6-build
  * Merge pull request [#761] from looker/no-log

## 2.12.3 / 2015-08-03

* 8 minor bugs fixed:
  * Fix Capistrano 'uninitialized constant Puma' error.
  * Fix some ancient and incorrect error handling code
  * Fix uninitialized constant error
  * Remove toplevel rack interspection, require rack on load instead
  * Skip empty parts when chunking
  * Switch from inject to each in config_ru_binds iteration
  * Wrap SSLv3 spec in version guard.
  * ruby 1.8.7 compatibility patches

* 4 PRs merged:
  * Merge pull request [#742] from deivid-rodriguez/fix_missing_require
  * Merge pull request [#743] from matthewd/skip-empty-chunks
  * Merge pull request [#749] from huacnlee/fix-cap-uninitialized-puma-error
  * Merge pull request [#751] from costi/compat_1_8_7

* 1 test fix:
  * Add 1.8.7, rbx-1 (allow failures) to Travis.

## 2.12.2 / 2015-07-17

* 2 bug fix:
  * Pull over and use Rack::URLMap. Fixes [#741]
  * Stub out peercert on JRuby for now. Fixes [#739]

## 2.12.1 / 2015-07-16

* 2 bug fixes:
  * Use a constant format. Fixes [#737]
  * Use strerror for Windows sake. Fixes [#733]

* 1 doc change:
  * typo fix: occured -> occurred

* 1 PR merged:
  * Merge pull request [#736] from paulanunda/paulanunda/typo-fix

## 2.12.0 / 2015-07-14

* 13 bug fixes:
  * Add thread reaping to thread pool
  * Do not automatically use chunked responses when hijacked
  * Do not suppress Content-Length on partial hijack
  * Don't allow any exceptions to terminate a thread
  * Handle ENOTCONN client disconnects when setting REMOTE_ADDR
  * Handle very early exit of cluster mode. Fixes [#722]
  * Install rack when running tests on travis to use rack/lint
  * Make puma -v and -h return success exit code
  * Make pumactl load config/puma.rb by default
  * Pass options from pumactl properly when pruning. Fixes [#694]
  * Remove rack dependency. Fixes [#705]
  * Remove the default Content-Type: text/plain
  * Add Client Side Certificate Auth

* 8 doc/test changes:
  * Added example sourcing of environment vars
  * Added tests for bind configuration on rackup file
  * Fix example config text
  * Update DEPLOYMENT.md
  * Update Readme with example of custom error handler
  * ci: Improve Travis settings
  * ci: Start running tests against JRuby 9k on Travis
  * ci: Convert to container infrastructure for travisci

* 2 ops changes:
  * Check for system-wide rbenv
  * capistrano: Add additional env when start rails

* 16 PRs merged:
  * Merge pull request [#686] from jjb/patch-2
  * Merge pull request [#693] from rob-murray/update-example-config
  * Merge pull request [#697] from spk/tests-bind-on-rackup-file
  * Merge pull request [#699] from deees/fix/require_rack_builder
  * Merge pull request [#701] from deepj/master
  * Merge pull request [#702] from Jimdo/thread-reaping
  * Merge pull request [#703] from deepj/travis
  * Merge pull request [#704] from grega/master
  * Merge pull request [#709] from lian/master
  * Merge pull request [#711] from julik/master
  * Merge pull request [#712] from yakara-ltd/pumactl-default-config
  * Merge pull request [#715] from RobotJiang/master
  * Merge pull request [#725] from rwz/master
  * Merge pull request [#726] from strenuus/handle-client-disconnect
  * Merge pull request [#729] from allaire/patch-1
  * Merge pull request [#730] from iamjarvo/container-infrastructure

## 2.11.3 / 2015-05-18

* 5 bug fixes:
  * Be sure to unlink tempfiles after a request. Fixes [#690]
  * Coerce the key to a string before checking. (thar be symbols). Fixes [#684]
  * Fix hang on bad SSL handshake
  * Remove `enable_SSLv3` support from JRuby

* 1 PR merged:
  * Merge pull request [#698] from looker/hang-handshake

## 2.11.2 / 2015-04-11

* 2 minor features:
  * Add `on_worker_fork` hook, which allows to mimic Unicorn's behavior
  * Add shutdown_debug config option

* 4 bug fixes:
  * Fix the Config constants not being available in the DSL. Fixes [#683]
  * Ignore multiple port declarations
  * Proper 'Connection' header handling compatible with HTTP 1.[01] protocols
  * Use "Puma" instead of "puma" to reporting to New Relic

* 1 doc fixes:
  * Add Gitter badge.

* 6 PRs merged:
  * Merge pull request [#657] from schneems/schneems/puma-once-port
  * Merge pull request [#658] from Tomohiro/newrelic-dispatcher-default-update
  * Merge pull request [#662] from basecrm/connection-compatibility
  * Merge pull request [#664] from fxposter/on-worker-fork
  * Merge pull request [#667] from JuanitoFatas/doc/gemspec
  * Merge pull request [#672] from chulkilee/refactor

## 2.11.1 / 2015-02-11

* 2 bug fixes:
  * Avoid crash in strange restart conditions
  * Inject the GEM_HOME that bundler into puma-wild's env. Fixes [#653]

* 2 PRs merged:
  * Merge pull request [#644] from bpaquet/master
  * Merge pull request [#646] from mkonecny/master

## 2.11.0 / 2015-01-20

* 9 bug fixes:
  * Add mode as an additional bind option to unix sockets. Fixes [#630]
  * Advertise HTTPS properly after a hot restart
  * Don't write lowlevel_error_handler to state
  * Fix phased restart with stuck requests
  * Handle spaces in the path properly. Fixes [#622]
  * Set a default REMOTE_ADDR to avoid using peeraddr on unix sockets. Fixes [#583]
  * Skip device number checking on jruby. Fixes [#586]
  * Update extconf.rb to compile correctly on OS X
  * redirect io right after daemonizing so startup errors are shown. Fixes [#359]

* 6 minor features:
  * Add a configuration option that prevents puma from queueing requests.
  * Add reload_worker_directory
  * Add the ability to pass environment variables to the init script (for Jungle).
  * Add the proctitle tag to the worker. Fixes [#633]
  * Infer a proctitle tag based on the directory
  * Update lowlevel error message to be more meaningful.

* 10 PRs merged:
  * Merge pull request [#478] from rubencaro/master
  * Merge pull request [#610] from kwilczynski/master
  * Merge pull request [#611] from jasonl/better-lowlevel-message
  * Merge pull request [#616] from jc00ke/master
  * Merge pull request [#623] from raldred/patch-1
  * Merge pull request [#628] from rdpoor/master
  * Merge pull request [#634] from deepj/master
  * Merge pull request [#637] from raskhadafi/patch-1
  * Merge pull request [#639] from ebeigarts/fix-phased-restarts
  * Merge pull request [#640] from codehotter/issue-612-dependent-requests-deadlock

## 2.10.2 / 2014-11-26

* 1 bug fix:
  * Conditionalize thread local cleaning, fixes perf degradation fix
    The code to clean out all Thread locals adds pretty significant
    overhead to a each request, so it has to be turned on explicitly
    if a user needs it.

## 2.10.1 / 2014-11-24

* 1 bug fix:
  * Load the app after daemonizing because the app might start threads.

  This change means errors loading the app are now reported only in the redirected
  stdout/stderr.

  If you're app has problems starting up, start it without daemon mode initially
  to test.

## 2.10.0 / 2014-11-23

* 3 minor features:
  * Added on_worker_shutdown hook mechanism
  * Allow binding to ipv6 addresses for ssl URIs
  * Warn about any threads started during app preload

* 5 bug fixes:
  * Clean out a threads local data before doing work
  * Disable SSLv3. Fixes [#591]
  * First change the directory to use the correct Gemfile.
  * Only use config.ru binds if specified. Fixes [#606]
  * Strongish cipher suite with FS support for some browsers

* 2 doc changes:
  * Change umask examples to more permissive values
  * fix typo in README.md

* 9 Merged PRs:
  * Merge pull request [#560] from raskhadafi/prune_bundler-bug
  * Merge pull request [#566] from sheltond/master
  * Merge pull request [#593] from andruby/patch-1
  * Merge pull request [#594] from hassox/thread-cleanliness
  * Merge pull request [#596] from burningTyger/patch-1
  * Merge pull request [#601] from sorentwo/friendly-umask
  * Merge pull request [#602] from 1334/patch-1
  * Merge pull request [#608] from Gu1/master
  * Merge pull request [#538] from memiux/?

## 2.9.2 / 2014-10-25

* 8 bug fixes:
  * Fix puma-wild handling a restart properly. Fixes [#550]
  * JRuby SSL POODLE update
  * Keep deprecated features warnings
  * Log the current time when Puma shuts down.
  * Fix cross-platform extension library detection
  * Use the correct Windows names for OpenSSL.
  * Better error logging during startup
  * Fixing sexist error messages

* 6 PRs merged:
  * Merge pull request [#549] from bsnape/log-shutdown-time
  * Merge pull request [#553] from lowjoel/master
  * Merge pull request [#568] from mariuz/patch-1
  * Merge pull request [#578] from danielbuechele/patch-1
  * Merge pull request [#581] from alexch/slightly-better-logging
  * Merge pull request [#590] from looker/jruby_disable_sslv3

## 2.9.1 / 2014-09-05

* 4 bug fixes:
  * Cleanup the SSL related structures properly, fixes memory leak
  * Fix thread spawning edge case.
  * Force a worker check after a worker boots, don't wait 5sec. Fixes [#574]
  * Implement SIGHUP for logs reopening

* 2 PRs merged:
  * Merge pull request [#561] from theoldreader/sighup
  * Merge pull request [#570] from havenwood/spawn-thread-edge-case

## 2.9.0 / 2014-07-12

* 1 minor feature:
  * Add SSL support for JRuby

* 3 bug fixes:
  * Typo BUNDLER_GEMFILE -> BUNDLE_GEMFILE
  * Use fast_write because we can't trust syswrite
  * pumactl - do not modify original ARGV

* 4 doc fixes:
  * BSD-3-Clause over BSD to avoid confusion
  * Deploy doc: clarification of the GIL
  * Fix typo in DEPLOYMENT.md
  * Update README.md

* 6 PRs merged:
  * Merge pull request [#520] from misfo/patch-2
  * Merge pull request [#530] from looker/jruby-ssl
  * Merge pull request [#537] from vlmonk/patch-1
  * Merge pull request [#540] from allaire/patch-1
  * Merge pull request [#544] from chulkilee/bsd-3-clause
  * Merge pull request [#551] from jcxplorer/patch-1

## 2.8.2 / 2014-04-12

* 4 bug fixes:
  * During upgrade, change directory in main process instead of workers.
  * Close the client properly on error
  * Capistrano: fallback from phased restart to start when not started
  * Allow tag option in conf file

* 4 doc fixes:
  * Fix Puma daemon service README typo
  * `preload_app!` instead of `preload_app`
  * add preload_app and prune_bundler to example config
  * allow changing of worker_timeout in config file

* 11 PRs merged:
  * Merge pull request [#487] from ckuttruff/master
  * Merge pull request [#492] from ckuttruff/master
  * Merge pull request [#493] from alepore/config_tag
  * Merge pull request [#503] from mariuz/patch-1
  * Merge pull request [#505] from sammcj/patch-1
  * Merge pull request [#506] from FlavourSys/config_worker_timeout
  * Merge pull request [#510] from momer/rescue-block-handle-servers-fix
  * Merge pull request [#511] from macool/patch-1
  * Merge pull request [#514] from edogawaconan/refactor_env
  * Merge pull request [#517] from misfo/patch-1
  * Merge pull request [#518] from LongMan/master

## 2.8.1 / 2014-03-06

* 1 bug fixes:
  * Run puma-wild with proper deps for prune_bundler

* 2 doc changes:
  * Described the configuration file finding behavior added in 2.8.0 and how to disable it.
  * Start the deployment doc

* 6 PRs merged:
  * Merge pull request [#471] from arthurnn/fix_test
  * Merge pull request [#485] from joneslee85/patch-9
  * Merge pull request [#486] from joshwlewis/patch-1
  * Merge pull request [#490] from tobinibot/patch-1
  * Merge pull request [#491] from brianknight10/clarify-no-config

## 2.8.0 / 2014-02-28

* 8 minor features:
  * Add ability to autoload a config file. Fixes [#438]
  * Add ability to detect and terminate hung workers. Fixes [#333]
  * Add booted_workers to stats response
  * Add config to customize the default error message
  * Add prune_bundler option
  * Add worker indexes, expose them via on_worker_boot. Fixes [#440]
  * Add pretty process name
  * Show the ruby version in use

* 7 bug fixes:
  * Added 408 status on timeout.
  * Be more hostile with sockets that write block. Fixes [#449]
  * Expect at_exit to exclusively remove the pidfile. Fixes [#444]
  * Expose latency and listen backlog via bind query. Fixes [#370]
  * JRuby raises IOError if the socket is there. Fixes [#377]
  * Process requests fairly. Fixes [#406]
  * Rescue SystemCallError as well. Fixes [#425]

* 4 doc changes:
  * Add 2.1.0 to the matrix
  * Add Code Climate badge to README
  * Create signals.md
  * Set the license to BSD. Fixes [#432]

* 14 PRs merged:
  * Merge pull request [#428] from alexeyfrank/capistrano_default_hooks
  * Merge pull request [#429] from namusyaka/revert-const_defined
  * Merge pull request [#431] from mrb/master
  * Merge pull request [#433] from alepore/process-name
  * Merge pull request [#437] from ibrahima/master
  * Merge pull request [#446] from sudara/master
  * Merge pull request [#451] from pwiebe/status_408
  * Merge pull request [#453] from joevandyk/patch-1
  * Merge pull request [#470] from arthurnn/fix_458
  * Merge pull request [#472] from rubencaro/master
  * Merge pull request [#480] from jjb/docs-on-running-test-suite
  * Merge pull request [#481] from schneems/master
  * Merge pull request [#482] from prathamesh-sonpatki/signals-doc-cleanup
  * Merge pull request [#483] from YotpoLtd/master

## 2.7.1 / 2013-12-05

* 1 bug fix:
  * Keep STDOUT/STDERR the right mode. Fixes [#422]

## 2.7.0 / 2013-12-03

* 1 minor feature:
  * Adding TTIN and TTOU to increment/decrement workers

* N bug fixes:
  * Always use our Process.daemon because it's not busted
  * Add capistrano restart failback to start.
  * Change position of `cd` so that rvm gemset is loaded
  * Clarify some platform specifics
  * Do not close the pipe sockets when retrying
  * Fix String#byteslice for Ruby 1.9.1, 1.9.2
  * Fix compatibility with 1.8.7.
  * Handle IOError closed stream in IO.select
  * Increase the max URI path length to 2048 chars from 1024 chars
  * Upstart jungle use config/puma.rb instead

## 2.6.0 / 2013-09-13

* 2 minor features:
  * Add support for event hooks
  ** Add a hook for state transitions
  * Add phased restart to capistrano recipe.

* 4 bug fixes:
  * Convince workers to stop by SIGKILL after timeout
  * Define RSTRING_NOT_MODIFIED for Rubinius performance
  * Handle BrokenPipe, StandardError and IOError in fat_wrote and break out
  * Return success status to the invoking environment

## 2.5.1 / 2013-08-13

* 2 bug fixes:
  * Keep jruby daemon mode from retrying on a hot restart
  * Extract version from const.rb in gemspec

## 2.5.0 / 2013-08-08

* 2 minor features:
  * Allow configuring pumactl with config.rb
  * make `pumactl restart` start puma if not running

* 6 bug fixes:
  * Autodetect ruby managers and home directory in upstart script
  * Convert header values to string before sending.
  * Correctly report phased-restart availability
  * Fix pidfile creation/deletion race on jruby daemonization
  * Use integers when comparing thread counts
  * Fix typo in using lopez express (raw tcp) mode

* 6 misc changes:
  * Fix typo in phased-restart response
  * Uncomment setuid/setgid by default in upstart
  * Use Puma::Const::PUMA_VERSION in gemspec
  * Update upstart comments to reflect new commandline
  * Remove obsolete pumactl instructions; refer to pumactl for details
  * Make Bundler used puma.gemspec version agnostic

## 2.4.1 / 2013-08-07

* 1 experimental feature:
  * Support raw tcp servers (aka Lopez Express mode)

## 2.4.0 / 2013-07-22

* 5 minor features:
  * Add PUMA_JRUBY_DAEMON_OPTS to get around agent starting twice
  * Add ability to drain accept socket on shutdown
  * Add port to DSL
  * Adds support for using puma config file in capistrano deploys.
  * Make phased_restart fallback to restart if not available

* 10 bug fixes:

  * Be sure to only delete the pid in the master. Fixes [#334]
  * Call out -C/--config flags
  * Change parser symbol names to avoid clash. Fixes [#179]
  * Convert thread pool sizes to integers
  * Detect when the jruby daemon child doesn't start properly
  * Fix typo in CLI help
  * Improve the logging output when hijack is used. Fixes [#332]
  * Remove unnecessary thread pool size conversions
  * Setup :worker_boot as an Array. Fixes [#317]
  * Use 127.0.0.1 as REMOTE_ADDR of unix client. Fixes [#309]


## 2.3.2 / 2013-07-08

* 1 bug fix:
  * Move starting control server to after daemonization.

## 2.3.1 / 2013-07-06

* 2 bug fixes:
  * Include the right files in the Manifest.
  * Disable inheriting connections on restart on windows. Fixes [#166]

* 1 doc change:
  * Better document some platform constraints

## 2.3.0 / 2013-07-05

* 1 major bug fix:
  * Stabilize control server, add support in cluster mode

* 5 minor bug fixes:
  * Add ability to cleanup stale unix sockets
  * Check status data better. Fixes [#292]
  * Convert raw IO errors to ConnectionError. Fixes [#274]
  * Fix sending Content-Type and Content-Length for no body status. Fixes [#304]
  * Pass state path through to `pumactl start`. Fixes [#287]

* 2 internal changes:
  * Refactored modes into seperate classes that CLI uses
  * Changed CLI to take an Events object instead of stdout/stderr (API change)

## 2.2.2 / 2013-07-02

* 1 bug fix:
  * Fix restart_command in the config

## 2.2.1 / 2013-07-02

* 1 minor feature:
  * Introduce preload flag

* 1 bug fix:
  * Pass custom restart command in JRuby

## 2.2.0 / 2013-07-01

* 1 major feature:
  * Add ability to preload rack app

* 2 minor bugfixes:
  * Don't leak info when not in development. Fixes [#256]
  * Load the app, then bind the ports

## 2.1.1 / 2013-06-20

* 2 minor bug fixes:

  * Fix daemonization on jruby
  * Load the application before daemonizing. Fixes [#285]

## 2.1.0 / 2013-06-18

* 3 minor features:
  * Allow listening socket to be configured via Capistrano variable
  * Output results from 'stat's command when using pumactl
  * Support systemd socket activation

* 15 bug fixes:
  * Deal with pipes closing while stopping. Fixes [#270]
  * Error out early if there is no app configured
  * Handle ConnectionError rather than the lowlevel exceptions
  * tune with `-C` config file and `on_worker_boot`
  * use `-w`
  * Fixed some typos in upstart scripts
  * Make sure to use bytesize instead of size (MiniSSL write)
  * Fix an error in puma-manager.conf
  * fix: stop leaking sockets on restart (affects ruby 1.9.3 or before)
  * Ignore errors on the cross-thread pipe. Fixes [#246]
  * Ignore errors while uncorking the socket (it might already be closed)
  * Ignore the body on a HEAD request. Fixes [#278]
  * Handle all engine data when possible. Fixes [#251].
  * Handle all read exceptions properly. Fixes [#252]
  * Handle errors from the server better

* 3 doc changes:
  * Add note about on_worker_boot hook
  * Add some documentation for Clustered mode
  * Added quotes to /etc/puma.conf

## 2.0.1 / 2013-04-30

* 1 bug fix:
  * Fix not starting on JRuby properly

## 2.0.0 / 2013-04-29

RailsConf 2013 edition!

* 2 doc changes:
  * Start with rackup -s Puma, NOT rackup -s puma.
  * Minor doc fixes in the README.md, Capistrano section

* 2 bug fixes:
  * Fix reading RACK_ENV properly. Fixes [#234]
  * Make cap recipe handle tmp/sockets; fixes [#228]

* 3 minor changes:
  * Fix capistrano recipe
  * Fix stdout/stderr logs to sync outputs
  * allow binding to IPv6 addresses

## 2.0.0.b7 / 2013-03-18

* 5 minor enhancements:
  * Add -q option for :start
  * Add -V, --version
  * Add default Rack handler helper
  * Upstart support
  * Set worker directory from configuration file

* 12 bug fixes:
  * Close the binder in the right place. Fixes [#192]
  * Handle early term in workers. Fixes [#206]
  * Make sure that the default port is 80 when the request doesn't include HTTP_X_FORWARDED_PROTO.
  * Prevent Errno::EBADF errors on restart when running ruby 2.0
  * Record the proper @master_pid
  * Respect the header HTTP_X_FORWARDED_PROTO when the host doesn't include a port number.
  * Retry EAGAIN/EWOULDBLOCK during syswrite
  * Run exec properly to restart. Fixes [#154]
  * Set Rack run_once to false
  * Syncronize all access to @timeouts. Fixes [#208]
  * Write out the state post-daemonize. Fixes [#189]
  * Prevent crash when all workers are gone

## 2.0.0.b6 / 2013-02-06

* 2 minor enhancements:
  * Add hook for running when a worker boots
  * Advertise the Configuration object for apps to use.

* 1 bug fix:
  * Change directory in working during upgrade. Fixes [#185]

## 2.0.0.b5 / 2013-02-05

* 2 major features:
  * Add phased worker upgrade
  * Add support for the rack hijack protocol

* 2 minor features:
  * Add -R to specify the restart command
  * Add config file option to specify the restart command

* 5 bug fixes:
  * Cleanup pipes properly. Fixes [#182]
  * Daemonize earlier so that we don't lose app threads. Fixes [#183]
  * Drain the notification pipe. Fixes [#176], thanks @cryo28
  * Move write_pid to after we daemonize. Fixes [#180]
  * Redirect IO properly and emit message for checkpointing

## 2.0.0.b4 / 2012-12-12

* 4 bug fixes:
  * Properly check #syswrite's value for variable sized buffers. Fixes [#170]
  * Shutdown status server properly
  * Handle char vs byte and mixing syswrite with write properly
  * made MiniSSL validate key/cert file existence

## 2.0.0.b3 / 2012-11-22

* 1 bug fix:
  * Package right files in gem

## 2.0.0.b2 / 2012-11-18
* 5 minor feature:
  * Now Puma is bundled with an capistrano recipe. Just require
     'puma/capistrano' in you deploy.rb
  * Only inject CommonLogger in development mode
  * Add -p option to pumactl
  * Add ability to use pumactl to start a server
  * Add options to daemonize puma

* 7 bug fixes:
  * Reset the IOBuffer properly. Fixes [#148]
  * Shutdown gracefully on JRuby with Ctrl-C
  * Various methods to get newrelic to start. Fixes [#128]
  * fixing syntax error at capistrano recipe
  * Force ECONNRESET when read returns nil
  * Be sure to empty the drain the todo before shutting down. Fixes [#155]
  * allow for alternate locations for status app

## 2.0.0.b1 / 2012-09-11

* 1 major feature:
  * Optional worker process mode (-w) to allow for process scaling in
    addition to thread scaling

* 1 bug fix:
  * Introduce Puma::MiniSSL to be able to properly control doing
    nonblocking SSL

NOTE: SSL support in JRuby is not supported at present. Support will
be added back in a future date when a java Puma::MiniSSL is added.

## 1.6.3 / 2012-09-04

* 1 bug fix:
  * Close sockets waiting in the reactor when a hot restart is performed
    so that browsers reconnect on the next request

## 1.6.2 / 2012-08-27

* 1 bug fix:
  * Rescue StandardError instead of IOError to handle SystemCallErrors
    as well as other application exceptions inside the reactor.

## 1.6.1 / 2012-07-23

* 1 packaging bug fixed:
  * Include missing files

## 1.6.0 / 2012-07-23

* 1 major bug fix:
  * Prevent slow clients from starving the server by introducing a
    dedicated IO reactor thread. Credit for reporting goes to @meh.

## 1.5.0 / 2012-07-19

* 7 contributors to this release:
  * Christian Mayer
  * Darío Javier Cravero
  * Dirkjan Bussink
  * Gianluca Padovani
  * Santiago Pastorino
  * Thibault Jouan
  * tomykaira

* 6 bug fixes:
  * Define RSTRING_NOT_MODIFIED for Rubinius
  * Convert status to integer. Fixes [#123]
  * Delete pidfile when stopping the server
  * Allow compilation with -Werror=format-security option
  * Fix wrong HTTP version for a HTTP/1.0 request
  * Use String#bytesize instead of String#length

* 3 minor features:
  * Added support for setting RACK_ENV via the CLI, config file, and rack app
  * Allow Server#run to run sync. Fixes [#111]
  * Puma can now run on windows

## 1.4.0 / 2012-06-04

* 1 bug fix:
  * SCRIPT_NAME should be passed from env to allow mounting apps

* 1 experimental feature:
  * Add puma.socket key for direct socket access

## 1.3.1 / 2012-05-15

* 2 bug fixes:
  * use #bytesize instead of #length for Content-Length header
  * Use StringIO properly. Fixes [#98]

## 1.3.0 / 2012-05-08

* 2 minor features:
  * Return valid Rack responses (passes Lint) from status server
  * Add -I option to specify $LOAD_PATH directories

* 4 bug fixes:
  * Don't join the server thread inside the signal handle. Fixes [#94]
  * Make NullIO#read mimic IO#read
  * Only stop the status server if it's started. Fixes [#84]
  * Set RACK_ENV early in cli also. Fixes [#78]

* 1 new contributor:
  * Jesse Cooke

## 1.2.2 / 2012-04-28

* 4 bug fixes:
  * Report a lowlevel error to stderr
  * Set a fallback SERVER_NAME and SERVER_PORT
  * Keep the encoding of the body correct. Fixes [#79]
  * show error.to_s along with backtrace for low-level error

## 1.2.1 / 2012-04-11

* 1 bug fix:
  * Fix rack.url_scheme for SSL servers. Fixes [#65]

## 1.2.0 / 2012-04-11

* 1 major feature:
 * When possible, the internal restart does a "hot restart" meaning
   the server sockets remains open, so no connections are lost.

* 1 minor feature:
  * More helpful fallback error message

* 6 bug fixes:
  * Pass the proper args to unknown_error. Fixes [#54], [#58]
  * Stop the control server before restarting. Fixes [#61]
  * Fix reporting https only on a true SSL connection
  * Set the default content type to 'text/plain'. Fixes [#63]
  * Use REUSEADDR. Fixes [#60]
  * Shutdown gracefully on SIGTERM. Fixes [#53]

* 2 new contributors:
  * Seamus Abshere
  * Steve Richert

## 1.1.1 / 2012-03-30

* 1 bugfix:
  * Include puma/compat.rb in the gem (oops!)

## 1.1.0 / 2012-03-30

* 1 bugfix:
  * Make sure that the unix socket has the perms 0777 by default

* 1 minor feature:
  * Add umask param to the unix:// bind to set the umask

## 1.0.0 / 2012-03-29

* Released!

## Ignore - this is for maintainers to copy-paste during release
## Master

* Features
  * Your feature goes here <Most recent on the top, like GitHub> (#Github Number)

* Bugfixes
  * Your bugfix goes here <Most recent on the top, like GitHub> (#Github Number)

[#2384]:https://github.com/puma/puma/pull/2384 "2020-09-24 @schneems"
[#2381]:https://github.com/puma/puma/pull/2381 "2020-09-24 @joergschray"
[#2271]:https://github.com/puma/puma/pull/2271 "2020-05-17 @wjordan"
[#2377]:https://github.com/puma/puma/pull/2377 "2020-09-22 @cjlarose"
[#2376]:https://github.com/puma/puma/pull/2376 "2020-09-22 @alexeevit"
[#2372]:https://github.com/puma/puma/pull/2372 "2020-09-18 @ahorek"
[#2375]:https://github.com/puma/puma/pull/2375 "2020-09-20 @MSP-Greg"
[#2373]:https://github.com/puma/puma/pull/2373 "2020-09-19 @MSP-Greg"
[#2305]:https://github.com/puma/puma/pull/2305 "2020-07-06 @MSP-Greg"
[#2099]:https://github.com/puma/puma/pull/2099 "2020-01-04 @wjordan"
[#2079]:https://github.com/puma/puma/pull/2079 "2019-11-21 @ayufan"
[#2093]:https://github.com/puma/puma/pull/2093 "2019-12-18 @schneems"
[#2256]:https://github.com/puma/puma/pull/2256 "2020-05-11 @nateberkopec"
[#2054]:https://github.com/puma/puma/pull/2054 "2019-10-25 @composerinteralia"
[#2106]:https://github.com/puma/puma/pull/2106 "2020-01-25 @ylecuyer"
[#2167]:https://github.com/puma/puma/pull/2167 "2020-03-09 @ChrisBr"
[#2344]:https://github.com/puma/puma/pull/2344 "2020-08-23 @dentarg"
[#2203]:https://github.com/puma/puma/pull/2203 "2020-03-26 @zanker-stripe"
[#2220]:https://github.com/puma/puma/pull/2220 "2020-04-10 @wjordan"
[#2238]:https://github.com/puma/puma/pull/2238 "2020-04-27 @sthirugn"
[#2086]:https://github.com/puma/puma/pull/2086 "2019-12-09 @bdewater"
[#2253]:https://github.com/puma/puma/pull/2253 "2020-05-08 @schneems"
[#2288]:https://github.com/puma/puma/pull/2288 "2020-05-31 @FTLam11"
[#1487]:https://github.com/puma/puma/pull/1487 "2017-12-15 @jxa"
[#2143]:https://github.com/puma/puma/pull/2143 "2020-03-02 @jalevin"
[#2143]:https://github.com/puma/puma/pull/2143 "2020-03-02 @jalevin"
[#2143]:https://github.com/puma/puma/pull/2143 "2020-03-02 @jalevin"
[#2143]:https://github.com/puma/puma/pull/2143 "2020-03-02 @jalevin"
[#2143]:https://github.com/puma/puma/pull/2143 "2020-03-02 @jalevin"
[#2169]:https://github.com/puma/puma/pull/2169 "2020-03-10 @nateberkopec"
[#2170]:https://github.com/puma/puma/pull/2170 "2020-03-10 @nateberkopec"
[#2076]:https://github.com/puma/puma/pull/2076 "2019-11-19 @drews256"
[#2022]:https://github.com/puma/puma/pull/2022 "2019-10-10 @olleolleolle"
[#2269]:https://github.com/puma/puma/pull/2269 "2020-05-17 @MSP-Greg"
[#2312]:https://github.com/puma/puma/pull/2312 "2020-07-20 @MSP-Greg"
[#2338]:https://github.com/puma/puma/issues/2338 "2020-08-17 @micahhainlinestitchfix"
[#2116]:https://github.com/puma/puma/pull/2116 "2020-02-18 @MSP-Greg"
[#2074]:https://github.com/puma/puma/issues/2074 "2019-11-13 @jchristie55332"
[#2211]:https://github.com/puma/puma/pull/2211 "2020-03-29 @MSP-Greg"
[#2069]:https://github.com/puma/puma/pull/2069 "2019-11-08 @MSP-Greg"
[#2112]:https://github.com/puma/puma/pull/2112 "2020-02-08 @wjordan"
[#1893]:https://github.com/puma/puma/pull/1893 "2019-08-08 @seven1m"
[#2119]:https://github.com/puma/puma/pull/2119 "2020-02-20 @wjordan"
[#2121]:https://github.com/puma/puma/pull/2121 "2020-02-20 @wjordan"
[#2154]:https://github.com/puma/puma/pull/2154 "2020-03-07 @cjlarose"
[#1551]:https://github.com/puma/puma/issues/1551 "2018-03-29 @austinthecoder"
[#2198]:https://github.com/puma/puma/pull/2198 "2020-03-23 @eregon"
[#2216]:https://github.com/puma/puma/pull/2216 "2020-04-03 @praboud-stripe"
[#2122]:https://github.com/puma/puma/pull/2122 "2020-02-20 @wjordan"
[#2220]:https://github.com/puma/puma/pull/2220 "2020-04-10 @wjordan"
[#2177]:https://github.com/puma/puma/issues/2177 "2020-03-12 @GuiTeK"
[#2221]:https://github.com/puma/puma/pull/2221 "2020-04-10 @wjordan"
[#2233]:https://github.com/puma/puma/pull/2233 "2020-04-24 @ayufan"
[#2234]:https://github.com/puma/puma/pull/2234 "2020-04-24 @wjordan"
[#2225]:https://github.com/puma/puma/issues/2225 "2020-04-16 @nateberkopec"
[#2267]:https://github.com/puma/puma/pull/2267 "2020-05-15 @wjordan"
[#2287]:https://github.com/puma/puma/pull/2287 "2020-05-29 @eugeneius"
[#2317]:https://github.com/puma/puma/pull/2317 "2020-07-22 @MSP-Greg"
[#2312]:https://github.com/puma/puma/pull/2312 "2020-07-20 @MSP-Greg"
[#2319]:https://github.com/puma/puma/issues/2319 "2020-07-23 @AlexWayfer"
[#2326]:https://github.com/puma/puma/pull/2326 "2020-07-30 @rkistner"
[#2299]:https://github.com/puma/puma/issues/2299 "2020-06-26 @JohnPhillips31416"
[#2095]:https://github.com/puma/puma/pull/2095 "2019-12-24 @bdewater"
[#2102]:https://github.com/puma/puma/pull/2102 "2020-01-06 @bdewater"
[#2111]:https://github.com/puma/puma/pull/2111 "2020-02-07 @wjordan"
[#1980]:https://github.com/puma/puma/pull/1980 "2019-09-20 @nateberkopec"
[#2189]:https://github.com/puma/puma/pull/2189 "2020-03-18 @jkowens"
[#2220]:https://github.com/puma/puma/pull/2220 "2020-04-10 @wjordan"
[#2124]:https://github.com/puma/puma/pull/2124 "2020-02-21 @wjordan"
[#2223]:https://github.com/puma/puma/pull/2223 "2020-04-14 @wjordan"
[#2239]:https://github.com/puma/puma/pull/2239 "2020-04-27 @wjordan"
[#2304]:https://github.com/puma/puma/issues/2304 "2020-07-03 @mpeltomaa"
[#2269]:https://github.com/puma/puma/pull/2269 "2020-05-17 @MSP-Greg"
[#2132]:https://github.com/puma/puma/issues/2132 "2020-02-27 @bmclean"
[#2010]:https://github.com/puma/puma/pull/2010 "2019-10-04 @nateberkopec"
[#2012]:https://github.com/puma/puma/pull/2012 "2019-10-05 @headius"
[#2046]:https://github.com/puma/puma/pull/2046 "2019-10-20 @composerinteralia"
[#2052]:https://github.com/puma/puma/pull/2052 "2019-10-24 @composerinteralia"
[#1564]:https://github.com/puma/puma/issues/1564 "2018-04-18 @perlun"
[#2035]:https://github.com/puma/puma/pull/2035 "2019-10-15 @AndrewSpeed"
[#2048]:https://github.com/puma/puma/pull/2048 "2019-10-21 @hahmed"
[#2050]:https://github.com/puma/puma/pull/2050 "2019-10-23 @olleolleolle"
[#1842]:https://github.com/puma/puma/issues/1842 "2019-07-11 @nateberkopec"
[#1988]:https://github.com/puma/puma/issues/1988 "2019-09-24 @mcg"
[#1986]:https://github.com/puma/puma/issues/1986 "2019-09-24 @flaminestone"
[#1994]:https://github.com/puma/puma/issues/1994 "2019-09-26 @LimeBlast"
[#2006]:https://github.com/puma/puma/pull/2006 "2019-10-01 @nateberkopec"
[#1222]:https://github.com/puma/puma/issues/1222 "2017-02-20 @seanmckinley"
[#1885]:https://github.com/puma/puma/pull/1885 "2019-08-05 @spk"
[#1934]:https://github.com/puma/puma/pull/1934 "2019-08-27 @zarelit"
[#1105]:https://github.com/puma/puma/pull/1105 "2016-09-27 @daveallie"
[#1786]:https://github.com/puma/puma/pull/1786 "2019-04-25 @evanphx"
[#1320]:https://github.com/puma/puma/pull/1320 "2017-06-03 @nateberkopec"
[#1968]:https://github.com/puma/puma/pull/1968 "2019-09-15 @nateberkopec"
[#1908]:https://github.com/puma/puma/pull/1908 "2019-08-13 @MSP-Greg"
[#1952]:https://github.com/puma/puma/pull/1952 "2019-09-06 @MSP-Greg"
[#1941]:https://github.com/puma/puma/pull/1941 "2019-09-01 @MSP-Greg"
[#1961]:https://github.com/puma/puma/pull/1961 "2019-09-11 @nateberkopec"
[#1970]:https://github.com/puma/puma/pull/1970 "2019-09-15 @MSP-Greg"
[#1946]:https://github.com/puma/puma/pull/1946 "2019-09-02 @nateberkopec"
[#1941]:https://github.com/puma/puma/pull/1941 "2019-09-01 @MSP-Greg"
[#1908]:https://github.com/puma/puma/pull/1908 "2019-08-13 @MSP-Greg"
[#1831]:https://github.com/puma/puma/pull/1831 "2019-07-01 @spk"
[#1816]:https://github.com/puma/puma/pull/1816 "2019-06-10 @ylecuyer"
[#1844]:https://github.com/puma/puma/pull/1844 "2019-07-14 @ylecuyer"
[#1836]:https://github.com/puma/puma/pull/1836 "2019-07-09 @MSP-Greg"
[#1887]:https://github.com/puma/puma/pull/1887 "2019-08-06 @MSP-Greg"
[#1812]:https://github.com/puma/puma/pull/1812 "2019-06-08 @kou"
[#1491]:https://github.com/puma/puma/pull/1491 "2017-12-21 @olleolleolle"
[#1837]:https://github.com/puma/puma/pull/1837 "2019-07-10 @montanalow"
[#1857]:https://github.com/puma/puma/pull/1857 "2019-07-19 @Jesus"
[#1822]:https://github.com/puma/puma/pull/1822 "2019-06-18 @Jesus"
[#1863]:https://github.com/puma/puma/pull/1863 "2019-07-28 @dzunk"
[#1838]:https://github.com/puma/puma/pull/1838 "2019-07-10 @bogn83"
[#1882]:https://github.com/puma/puma/pull/1882 "2019-08-05 @okuramasafumi"
[#1848]:https://github.com/puma/puma/pull/1848 "2019-07-16 @nateberkopec"
[#1847]:https://github.com/puma/puma/pull/1847 "2019-07-16 @nateberkopec"
[#1846]:https://github.com/puma/puma/pull/1846 "2019-07-16 @nateberkopec"
[#1853]:https://github.com/puma/puma/pull/1853 "2019-07-18 @Jesus"
[#1850]:https://github.com/puma/puma/pull/1850 "2019-07-18 @nateberkopec"
[#1866]:https://github.com/puma/puma/pull/1866 "2019-07-28 @josacar"
[#1870]:https://github.com/puma/puma/pull/1870 "2019-07-29 @MSP-Greg"
[#1872]:https://github.com/puma/puma/pull/1872 "2019-07-29 @MSP-Greg"
[#1833]:https://github.com/puma/puma/issues/1833 "2019-07-02 @julik"
[#1888]:https://github.com/puma/puma/pull/1888 "2019-08-06 @ClikeX"
[#1842]:https://github.com/puma/puma/issues/1842 "2019-07-11 @nateberkopec"
[#1829]:https://github.com/puma/puma/pull/1829 "2019-07-01 @Fudoshiki"
[#1832]:https://github.com/puma/puma/pull/1832 "2019-07-01 @MSP-Greg"
[#1827]:https://github.com/puma/puma/pull/1827 "2019-06-27 @amrrbakry"
[#1562]:https://github.com/puma/puma/pull/1562 "2018-04-17 @skrobul"
[#1569]:https://github.com/puma/puma/pull/1569 "2018-04-24 @rianmcguire"
[#1648]:https://github.com/puma/puma/pull/1648 "2018-09-13 @wjordan"
[#1691]:https://github.com/puma/puma/pull/1691 "2018-12-20 @kares"
[#1716]:https://github.com/puma/puma/pull/1716 "2019-01-25 @mdkent"
[#1690]:https://github.com/puma/puma/pull/1690 "2018-12-19 @mic-kul"
[#1689]:https://github.com/puma/puma/pull/1689 "2018-12-19 @michaelherold"
[#1728]:https://github.com/puma/puma/pull/1728 "2019-02-20 @evanphx"
[#1824]:https://github.com/puma/puma/pull/1824 "2019-06-23 @spk"
[#1685]:https://github.com/puma/puma/pull/1685 "2018-12-08 @mainameiz"
[#1808]:https://github.com/puma/puma/pull/1808 "2019-05-30 @schneems"
[#1508]:https://github.com/puma/puma/pull/1508 "2018-01-24 @florin555"
[#1650]:https://github.com/puma/puma/pull/1650 "2018-09-18 @adam101"
[#1655]:https://github.com/puma/puma/pull/1655 "2018-09-24 @mipearson"
[#1671]:https://github.com/puma/puma/pull/1671 "2018-11-02 @eric-norcross"
[#1583]:https://github.com/puma/puma/pull/1583 "2018-05-23 @chwevans"
[#1773]:https://github.com/puma/puma/pull/1773 "2019-04-14 @enebo"
[#1731]:https://github.com/puma/puma/issues/1731 "2019-02-22 @Fudoshiki"
[#1803]:https://github.com/puma/puma/pull/1803 "2019-05-21 @Jesus"
[#1741]:https://github.com/puma/puma/pull/1741 "2019-03-12 @MSP-Greg"
[#1674]:https://github.com/puma/puma/issues/1674 "2018-11-08 @atitan"
[#1720]:https://github.com/puma/puma/issues/1720 "2019-01-31 @voxik"
[#1730]:https://github.com/puma/puma/issues/1730 "2019-02-20 @nearapogee"
[#1755]:https://github.com/puma/puma/issues/1755 "2019-03-27 @vbalazs"
[#1649]:https://github.com/puma/puma/pull/1649 "2018-09-17 @schneems"
[#1607]:https://github.com/puma/puma/pull/1607 "2018-07-05 @harmdewit"
[#1700]:https://github.com/puma/puma/pull/1700 "2019-01-04 @schneems"
[#1630]:https://github.com/puma/puma/pull/1630 "2018-08-09 @eregon"
[#1478]:https://github.com/puma/puma/pull/1478 "2017-12-01 @eallison91"
[#1604]:https://github.com/puma/puma/pull/1604 "2018-06-29 @schneems"
[#1579]:https://github.com/puma/puma/pull/1579 "2018-05-04 @schneems"
[#1506]:https://github.com/puma/puma/pull/1506 "2018-01-19 @dekellum"
[#1487]:https://github.com/puma/puma/pull/1487 "2017-12-15 @jxa"
[#1563]:https://github.com/puma/puma/pull/1563 "2018-04-17 @dannyfallon"
[#1557]:https://github.com/puma/puma/pull/1557 "2018-04-07 @swrobel"
[#1529]:https://github.com/puma/puma/pull/1529 "2018-03-11 @desnudopenguino"
[#1532]:https://github.com/puma/puma/pull/1532 "2018-03-12 @schneems"
[#1482]:https://github.com/puma/puma/pull/1482 "2017-12-07 @shayonj"
[#1511]:https://github.com/puma/puma/pull/1511 "2018-01-28 @jemiam"
[#1545]:https://github.com/puma/puma/pull/1545 "2018-03-21 @hoshinotsuyoshi"
[#1550]:https://github.com/puma/puma/pull/1550 "2018-03-28 @eileencodes"
[#1553]:https://github.com/puma/puma/pull/1553 "2018-03-31 @eugeneius"
[#1510]:https://github.com/puma/puma/issues/1510 "2018-01-26 @vincentwoo"
[#1524]:https://github.com/puma/puma/pull/1524 "2018-03-05 @tuwukee"
[#1507]:https://github.com/puma/puma/issues/1507 "2018-01-19 @vincentwoo"
[#1483]:https://github.com/puma/puma/issues/1483 "2017-12-07 @igravious"
[#1502]:https://github.com/puma/puma/issues/1502 "2018-01-10 @vincentwoo"
[#1403]:https://github.com/puma/puma/pull/1403 "2017-08-29 @eileencodes"
[#1435]:https://github.com/puma/puma/pull/1435 "2017-10-10 @juliancheal"
[#1340]:https://github.com/puma/puma/pull/1340 "2017-06-19 @ViliusLuneckas"
[#1434]:https://github.com/puma/puma/pull/1434 "2017-10-10 @jumbosushi"
[#1436]:https://github.com/puma/puma/pull/1436 "2017-10-10 @luislavena"
[#1418]:https://github.com/puma/puma/pull/1418 "2017-09-20 @eileencodes"
[#1416]:https://github.com/puma/puma/pull/1416 "2017-09-20 @hiimtaylorjones"
[#1409]:https://github.com/puma/puma/pull/1409 "2017-09-12 @olleolleolle"
[#1427]:https://github.com/puma/puma/issues/1427 "2017-10-04 @garybernhardt"
[#1430]:https://github.com/puma/puma/pull/1430 "2017-10-05 @MSP-Greg"
[#1429]:https://github.com/puma/puma/pull/1429 "2017-10-05 @perlun"
[#1455]:https://github.com/puma/puma/pull/1455 "2017-11-13 @perlun"
[#1425]:https://github.com/puma/puma/pull/1425 "2017-09-30 @vizcay"
[#1452]:https://github.com/puma/puma/pull/1452 "2017-11-10 @eprothro"
[#1439]:https://github.com/puma/puma/pull/1439 "2017-10-16 @MSP-Greg"
[#1442]:https://github.com/puma/puma/pull/1442 "2017-10-19 @MSP-Greg"
[#1464]:https://github.com/puma/puma/pull/1464 "2017-11-19 @MSP-Greg"
[#1384]:https://github.com/puma/puma/pull/1384 "2017-08-03 @noahgibbs"
[#1111]:https://github.com/puma/puma/pull/1111 "2016-10-12 @alexlance"
[#1392]:https://github.com/puma/puma/pull/1392 "2017-08-11 @hoffm"
[#1347]:https://github.com/puma/puma/pull/1347 "2017-06-27 @NikolayRys"
[#1334]:https://github.com/puma/puma/pull/1334 "2017-06-13 @respire"
[#1383]:https://github.com/puma/puma/pull/1383 "2017-08-02 @schneems"
[#1368]:https://github.com/puma/puma/pull/1368 "2017-07-14 @bongole"
[#1318]:https://github.com/puma/puma/pull/1318 "2017-06-03 @nateberkopec"
[#1376]:https://github.com/puma/puma/pull/1376 "2017-07-22 @pat"
[#1388]:https://github.com/puma/puma/pull/1388 "2017-08-08 @nateberkopec"
[#1390]:https://github.com/puma/puma/pull/1390 "2017-08-09 @junaruga"
[#1391]:https://github.com/puma/puma/pull/1391 "2017-08-09 @junaruga"
[#1385]:https://github.com/puma/puma/pull/1385 "2017-08-05 @grosser"
[#1377]:https://github.com/puma/puma/pull/1377 "2017-07-27 @shayonj"
[#1337]:https://github.com/puma/puma/pull/1337 "2017-06-19 @shayonj"
[#1325]:https://github.com/puma/puma/pull/1325 "2017-06-04 @palkan"
[#1395]:https://github.com/puma/puma/pull/1395 "2017-08-16 @junaruga"
[#1367]:https://github.com/puma/puma/issues/1367 "2017-07-12 @dekellum"
[#1314]:https://github.com/puma/puma/pull/1314 "2017-06-02 @grosser"
[#1311]:https://github.com/puma/puma/pull/1311 "2017-06-01 @grosser"
[#1313]:https://github.com/puma/puma/pull/1313 "2017-06-01 @grosser"
[#1260]:https://github.com/puma/puma/pull/1260 "2017-04-01 @grosser"
[#1278]:https://github.com/puma/puma/pull/1278 "2017-04-27 @evanphx"
[#1306]:https://github.com/puma/puma/pull/1306 "2017-05-30 @jules2689"
[#1274]:https://github.com/puma/puma/pull/1274 "2017-04-14 @evanphx"
[#1261]:https://github.com/puma/puma/pull/1261 "2017-04-01 @jacksonrayhamilton"
[#1259]:https://github.com/puma/puma/pull/1259 "2017-04-01 @jacksonrayhamilton"
[#1248]:https://github.com/puma/puma/pull/1248 "2017-03-20 @davidarnold"
[#1277]:https://github.com/puma/puma/pull/1277 "2017-04-27 @schneems"
[#1290]:https://github.com/puma/puma/pull/1290 "2017-05-12 @schneems"
[#1285]:https://github.com/puma/puma/pull/1285 "2017-05-05 @fmauNeko"
[#1282]:https://github.com/puma/puma/pull/1282 "2017-05-03 @grosser"
[#1294]:https://github.com/puma/puma/pull/1294 "2017-05-15 @masry707"
[#1206]:https://github.com/puma/puma/pull/1206 "2017-02-02 @NikolayRys"
[#1241]:https://github.com/puma/puma/issues/1241 "2017-03-12 @renchap"
[#1239]:https://github.com/puma/puma/pull/1239 "2017-03-10 @schneems"
[#1234]:https://github.com/puma/puma/pull/1234 "2017-03-06 @schneems"
[#1226]:https://github.com/puma/puma/pull/1226 "2017-02-23 @eileencodes"
[#1227]:https://github.com/puma/puma/pull/1227 "2017-02-25 @sirupsen"
[#1213]:https://github.com/puma/puma/pull/1213 "2017-02-16 @junaruga"
[#1182]:https://github.com/puma/puma/issues/1182 "2016-12-28 @brunowego"
[#1203]:https://github.com/puma/puma/pull/1203 "2017-01-31 @twalpole"
[#1129]:https://github.com/puma/puma/pull/1129 "2016-11-10 @chtitux"
[#1165]:https://github.com/puma/puma/pull/1165 "2016-11-28 @sriedel"
[#1175]:https://github.com/puma/puma/pull/1175 "2016-12-14 @jemiam"
[#1068]:https://github.com/puma/puma/pull/1068 "2016-09-01 @junaruga"
[#1091]:https://github.com/puma/puma/pull/1091 "2016-09-13 @frodsan"
[#1088]:https://github.com/puma/puma/pull/1088 "2016-09-10 @frodsan"
[#1160]:https://github.com/puma/puma/pull/1160 "2016-11-23 @frodsan"
[#1169]:https://github.com/puma/puma/pull/1169 "2016-12-04 @scbrubaker02"
[#1061]:https://github.com/puma/puma/pull/1061 "2016-08-29 @michaelsauter"
[#1036]:https://github.com/puma/puma/issues/1036 "2016-07-28 @matobinder"
[#1120]:https://github.com/puma/puma/pull/1120 "2016-10-23 @prathamesh-sonpatki"
[#1178]:https://github.com/puma/puma/pull/1178 "2016-12-16 @Koronen"
[#1002]:https://github.com/puma/puma/issues/1002 "2016-06-16 @mattyb"
[#1063]:https://github.com/puma/puma/issues/1063 "2016-08-31 @mperham"
[#1089]:https://github.com/puma/puma/issues/1089 "2016-09-13 @AdamBialas"
[#1114]:https://github.com/puma/puma/pull/1114 "2016-10-19 @sj26"
[#1110]:https://github.com/puma/puma/pull/1110 "2016-10-12 @montdidier"
[#1135]:https://github.com/puma/puma/pull/1135 "2016-11-18 @jkraemer"
[#1081]:https://github.com/puma/puma/pull/1081 "2016-09-07 @frodsan"
[#1138]:https://github.com/puma/puma/pull/1138 "2016-11-20 @steakknife"
[#1118]:https://github.com/puma/puma/pull/1118 "2016-10-21 @hiroara"
[#1075]:https://github.com/puma/puma/issues/1075 "2016-09-06 @pvalena"
[#1118]:https://github.com/puma/puma/pull/1118 "2016-10-21 @hiroara"
[#1036]:https://github.com/puma/puma/issues/1036 "2016-07-28 @matobinder"
[#1120]:https://github.com/puma/puma/pull/1120 "2016-10-23 @prathamesh-sonpatki"
[#1002]:https://github.com/puma/puma/issues/1002 "2016-06-16 @mattyb"
[#1089]:https://github.com/puma/puma/issues/1089 "2016-09-13 @AdamBialas"
[#932]:https://github.com/puma/puma/issues/932 "2016-03-20 @everplays"
[#519]:https://github.com/puma/puma/issues/519 "2014-04-14 @tmornini"
[#828]:https://github.com/puma/puma/issues/828 "2015-11-20 @Zapotek"
[#984]:https://github.com/puma/puma/issues/984 "2016-05-20 @erichmenge"
[#1028]:https://github.com/puma/puma/issues/1028 "2016-07-23 @matobinder"
[#1023]:https://github.com/puma/puma/issues/1023 "2016-07-20 @fera2k"
[#1027]:https://github.com/puma/puma/issues/1027 "2016-07-22 @rosenfeld"
[#925]:https://github.com/puma/puma/issues/925 "2016-03-07 @lokenmakwana"
[#911]:https://github.com/puma/puma/issues/911 "2016-02-28 @veganstraightedge"
[#620]:https://github.com/puma/puma/issues/620 "2014-12-11 @javanthropus"
[#1027]:https://github.com/puma/puma/issues/1027 "2016-07-22 @rosenfeld"
[#778]:https://github.com/puma/puma/issues/778 "2015-09-07 @niedhui"
[#1021]:https://github.com/puma/puma/pull/1021 "2016-07-19 @sarahzrf"
[#1022]:https://github.com/puma/puma/issues/1022 "2016-07-20 @AKovtunov"
[#958]:https://github.com/puma/puma/issues/958 "2016-04-13 @lalitlogical"
[#782]:https://github.com/puma/puma/issues/782 "2015-09-11 @Tonkpils"
[#968]:https://github.com/puma/puma/issues/968 "2016-04-23 @frankwong15"
[#968]:https://github.com/puma/puma/issues/968 "2016-04-23 @frankwong15"
[#1010]:https://github.com/puma/puma/issues/1010 "2016-06-30 @mneumark"
[#959]:https://github.com/puma/puma/issues/959 "2016-04-13 @mwpastore"
[#840]:https://github.com/puma/puma/issues/840 "2015-12-03 @maxkwallace"
[#1007]:https://github.com/puma/puma/pull/1007 "2016-06-24 @willnet"
[#1014]:https://github.com/puma/puma/pull/1014 "2016-07-11 @szymon-jez"
[#1015]:https://github.com/puma/puma/pull/1015 "2016-07-14 @bf4"
[#1017]:https://github.com/puma/puma/pull/1017 "2016-07-15 @jorihardman"
[#954]:https://github.com/puma/puma/pull/954 "2016-04-11 @jf"
[#955]:https://github.com/puma/puma/pull/955 "2016-04-11 @jf"
[#956]:https://github.com/puma/puma/pull/956 "2016-04-11 @maxkwallace"
[#960]:https://github.com/puma/puma/pull/960 "2016-04-13 @kmayer"
[#969]:https://github.com/puma/puma/pull/969 "2016-04-23 @frankwong15"
[#970]:https://github.com/puma/puma/pull/970 "2016-04-26 @willnet"
[#974]:https://github.com/puma/puma/pull/974 "2016-04-28 @reidmorrison"
[#977]:https://github.com/puma/puma/pull/977 "2016-05-03 @snow"
[#981]:https://github.com/puma/puma/pull/981 "2016-05-17 @zach-chai"
[#993]:https://github.com/puma/puma/pull/993 "2016-06-06 @scorix"
[#938]:https://github.com/puma/puma/issues/938 "2016-03-30 @vandrijevik"
[#529]:https://github.com/puma/puma/issues/529 "2014-05-04 @mperham"
[#788]:https://github.com/puma/puma/issues/788 "2015-09-21 @herregroen"
[#894]:https://github.com/puma/puma/issues/894 "2016-02-21 @rafbm"
[#937]:https://github.com/puma/puma/issues/937 "2016-03-29 @huangxiangdan"
[#840]:https://github.com/puma/puma/issues/840 "2015-12-03 @maxkwallace"
[#945]:https://github.com/puma/puma/pull/945 "2016-04-07 @dekellum"
[#946]:https://github.com/puma/puma/pull/946 "2016-04-07 @vipulnsward"
[#947]:https://github.com/puma/puma/pull/947 "2016-04-07 @vipulnsward"
[#936]:https://github.com/puma/puma/pull/936 "2016-03-26 @prathamesh-sonpatki"
[#940]:https://github.com/puma/puma/pull/940 "2016-03-30 @kyledrake"
[#942]:https://github.com/puma/puma/pull/942 "2016-04-01 @dekellum"
[#927]:https://github.com/puma/puma/pull/927 "2016-03-08 @jlecour"
[#931]:https://github.com/puma/puma/pull/931 "2016-03-17 @runlevel5"
[#922]:https://github.com/puma/puma/issues/922 "2016-03-05 @LavirtheWhiolet"
[#923]:https://github.com/puma/puma/issues/923 "2016-03-06 @donv"
[#912]:https://github.com/puma/puma/pull/912 "2016-02-29 @tricknotes"
[#921]:https://github.com/puma/puma/pull/921 "2016-03-04 @swrobel"
[#924]:https://github.com/puma/puma/pull/924 "2016-03-06 @tbrisker"
[#916]:https://github.com/puma/puma/issues/916 "2016-03-02 @ma11hew28"
[#913]:https://github.com/puma/puma/issues/913 "2016-03-01 @Casara"
[#918]:https://github.com/puma/puma/issues/918 "2016-03-02 @rodrigdav"
[#910]:https://github.com/puma/puma/issues/910 "2016-02-27 @ball-hayden"
[#914]:https://github.com/puma/puma/issues/914 "2016-03-01 @osheroff"
[#901]:https://github.com/puma/puma/pull/901 "2016-02-26 @mitto"
[#902]:https://github.com/puma/puma/pull/902 "2016-02-26 @corrupt952"
[#905]:https://github.com/puma/puma/pull/905 "2016-02-26 @Eric-Guo"
[#852]:https://github.com/puma/puma/issues/852 "2015-12-19 @asia653"
[#854]:https://github.com/puma/puma/issues/854 "2016-01-06 @ollym"
[#824]:https://github.com/puma/puma/issues/824 "2015-11-14 @MattWalston"
[#823]:https://github.com/puma/puma/issues/823 "2015-11-13 @pneuman"
[#815]:https://github.com/puma/puma/issues/815 "2015-11-04 @nate-dipiazza"
[#835]:https://github.com/puma/puma/issues/835 "2015-11-29 @mwpastore"
[#798]:https://github.com/puma/puma/issues/798 "2015-10-16 @schneems"
[#876]:https://github.com/puma/puma/issues/876 "2016-02-04 @osheroff"
[#849]:https://github.com/puma/puma/issues/849 "2015-12-15 @apotheon"
[#871]:https://github.com/puma/puma/pull/871 "2016-01-30 @deepj"
[#874]:https://github.com/puma/puma/pull/874 "2016-02-03 @wallclockbuilder"
[#883]:https://github.com/puma/puma/pull/883 "2016-02-08 @dadah89"
[#884]:https://github.com/puma/puma/pull/884 "2016-02-10 @furkanmustafa"
[#888]:https://github.com/puma/puma/pull/888 "2016-02-16 @mlarraz"
[#890]:https://github.com/puma/puma/pull/890 "2016-02-17 @todd"
[#891]:https://github.com/puma/puma/pull/891 "2016-02-18 @ctaintor"
[#893]:https://github.com/puma/puma/pull/893 "2016-02-21 @spastorino"
[#897]:https://github.com/puma/puma/pull/897 "2016-02-22 @vanchi-zendesk"
[#899]:https://github.com/puma/puma/pull/899 "2016-02-23 @kch"
[#859]:https://github.com/puma/puma/issues/859 "2016-01-15 @boxofrad"
[#822]:https://github.com/puma/puma/pull/822 "2015-11-10 @kwugirl"
[#833]:https://github.com/puma/puma/pull/833 "2015-11-29 @joemiller"
[#837]:https://github.com/puma/puma/pull/837 "2015-12-01 @YurySolovyov"
[#839]:https://github.com/puma/puma/pull/839 "2015-12-03 @ka8725"
[#845]:https://github.com/puma/puma/pull/845 "2015-12-09 @deepj"
[#846]:https://github.com/puma/puma/pull/846 "2015-12-10 @sriedel"
[#850]:https://github.com/puma/puma/pull/850 "2015-12-16 @deepj"
[#853]:https://github.com/puma/puma/pull/853 "2015-12-25 @Jeffrey6052"
[#857]:https://github.com/puma/puma/pull/857 "2016-01-15 @osheroff"
[#858]:https://github.com/puma/puma/pull/858 "2016-01-15 @mlarraz"
[#860]:https://github.com/puma/puma/pull/860 "2016-01-15 @osheroff"
[#861]:https://github.com/puma/puma/pull/861 "2016-01-15 @osheroff"
[#818]:https://github.com/puma/puma/pull/818 "2015-11-06 @unleashed"
[#819]:https://github.com/puma/puma/pull/819 "2015-11-06 @VictorLowther"
[#563]:https://github.com/puma/puma/issues/563 "2014-07-28 @deathbob"
[#803]:https://github.com/puma/puma/issues/803 "2015-10-20 @burningTyger"
[#768]:https://github.com/puma/puma/pull/768 "2015-08-15 @nathansamson"
[#773]:https://github.com/puma/puma/pull/773 "2015-08-25 @rossta"
[#774]:https://github.com/puma/puma/pull/774 "2015-08-29 @snow"
[#781]:https://github.com/puma/puma/pull/781 "2015-09-11 @sunsations"
[#791]:https://github.com/puma/puma/pull/791 "2015-10-01 @unleashed"
[#793]:https://github.com/puma/puma/pull/793 "2015-10-06 @robdimarco"
[#794]:https://github.com/puma/puma/pull/794 "2015-10-07 @peterkeen"
[#795]:https://github.com/puma/puma/pull/795 "2015-10-13 @unleashed"
[#796]:https://github.com/puma/puma/pull/796 "2015-10-13 @cschneid"
[#799]:https://github.com/puma/puma/pull/799 "2015-10-17 @annawinkler"
[#800]:https://github.com/puma/puma/pull/800 "2015-10-17 @liamseanbrady"
[#801]:https://github.com/puma/puma/pull/801 "2015-10-20 @scottjg"
[#802]:https://github.com/puma/puma/pull/802 "2015-10-20 @scottjg"
[#804]:https://github.com/puma/puma/pull/804 "2015-10-20 @burningTyger"
[#809]:https://github.com/puma/puma/pull/809 "2015-10-27 @unleashed"
[#810]:https://github.com/puma/puma/pull/810 "2015-10-28 @vlmonk"
[#814]:https://github.com/puma/puma/pull/814 "2015-11-03 @schneems"
[#817]:https://github.com/puma/puma/pull/817 "2015-11-06 @unleashed"
[#735]:https://github.com/puma/puma/issues/735 "2015-07-15 @trekr5"
[#769]:https://github.com/puma/puma/issues/769 "2015-08-16 @dovestyle"
[#767]:https://github.com/puma/puma/issues/767 "2015-08-15 @kapso"
[#765]:https://github.com/puma/puma/issues/765 "2015-08-15 @monfresh"
[#764]:https://github.com/puma/puma/issues/764 "2015-08-15 @keithpitt"
[#669]:https://github.com/puma/puma/pull/669 "2015-03-13 @chulkilee"
[#673]:https://github.com/puma/puma/pull/673 "2015-03-15 @chulkilee"
[#668]:https://github.com/puma/puma/pull/668 "2015-03-12 @kcollignon"
[#754]:https://github.com/puma/puma/pull/754 "2015-08-06 @nathansamson"
[#759]:https://github.com/puma/puma/pull/759 "2015-08-12 @BenV"
[#761]:https://github.com/puma/puma/pull/761 "2015-08-12 @dmarcotte"
[#742]:https://github.com/puma/puma/pull/742 "2015-07-17 @deivid-rodriguez"
[#743]:https://github.com/puma/puma/pull/743 "2015-07-17 @matthewd"
[#749]:https://github.com/puma/puma/pull/749 "2015-07-27 @huacnlee"
[#751]:https://github.com/puma/puma/pull/751 "2015-07-31 @costi"
[#741]:https://github.com/puma/puma/issues/741 "2015-07-17 @GUI"
[#739]:https://github.com/puma/puma/issues/739 "2015-07-16 @hab278"
[#737]:https://github.com/puma/puma/issues/737 "2015-07-15 @dmill"
[#733]:https://github.com/puma/puma/issues/733 "2015-07-15 @Eric-Guo"
[#736]:https://github.com/puma/puma/pull/736 "2015-07-15 @paulanunda"
[#722]:https://github.com/puma/puma/issues/722 "2015-06-28 @mikeki"
[#694]:https://github.com/puma/puma/issues/694 "2015-04-27 @yld"
[#705]:https://github.com/puma/puma/issues/705 "2015-05-28 @TheTeaNerd"
[#686]:https://github.com/puma/puma/pull/686 "2015-04-15 @jjb"
[#693]:https://github.com/puma/puma/pull/693 "2015-04-24 @rob-murray"
[#697]:https://github.com/puma/puma/pull/697 "2015-04-29 @spk"
[#699]:https://github.com/puma/puma/pull/699 "2015-05-05 @deees"
[#701]:https://github.com/puma/puma/pull/701 "2015-05-19 @deepj"
[#702]:https://github.com/puma/puma/pull/702 "2015-05-20 @OleMchls"
[#703]:https://github.com/puma/puma/pull/703 "2015-05-26 @deepj"
[#704]:https://github.com/puma/puma/pull/704 "2015-05-27 @grega"
[#709]:https://github.com/puma/puma/pull/709 "2015-06-06 @lian"
[#711]:https://github.com/puma/puma/pull/711 "2015-06-08 @julik"
[#712]:https://github.com/puma/puma/pull/712 "2015-06-11 @chewi"
[#715]:https://github.com/puma/puma/pull/715 "2015-06-20 @0RaymondJiang0"
[#725]:https://github.com/puma/puma/pull/725 "2015-07-01 @rwz"
[#726]:https://github.com/puma/puma/pull/726 "2015-07-02 @jshafton"
[#729]:https://github.com/puma/puma/pull/729 "2015-07-09 @allaire"
[#730]:https://github.com/puma/puma/pull/730 "2015-07-14 @iamjarvo"
[#690]:https://github.com/puma/puma/issues/690 "2015-04-20 @bachue"
[#684]:https://github.com/puma/puma/issues/684 "2015-04-12 @tomquas"
[#698]:https://github.com/puma/puma/pull/698 "2015-05-04 @dmarcotte"
[#683]:https://github.com/puma/puma/issues/683 "2015-04-11 @indirect"
[#657]:https://github.com/puma/puma/pull/657 "2015-02-16 @schneems"
[#658]:https://github.com/puma/puma/pull/658 "2015-02-23 @tomohiro"
[#662]:https://github.com/puma/puma/pull/662 "2015-03-06 @iaintshine"
[#664]:https://github.com/puma/puma/pull/664 "2015-03-07 @fxposter"
[#667]:https://github.com/puma/puma/pull/667 "2015-03-12 @JuanitoFatas"
[#672]:https://github.com/puma/puma/pull/672 "2015-03-15 @chulkilee"
[#653]:https://github.com/puma/puma/issues/653 "2015-02-10 @dvrensk"
[#644]:https://github.com/puma/puma/pull/644 "2015-01-29 @bpaquet"
[#646]:https://github.com/puma/puma/pull/646 "2015-02-01 @mkonecny"
[#630]:https://github.com/puma/puma/issues/630 "2014-12-26 @jelmd"
[#622]:https://github.com/puma/puma/issues/622 "2014-12-13 @sabamotto"
[#583]:https://github.com/puma/puma/issues/583 "2014-09-19 @emq"
[#586]:https://github.com/puma/puma/issues/586 "2014-09-27 @ponchik"
[#359]:https://github.com/puma/puma/issues/359 "2013-08-27 @natew"
[#633]:https://github.com/puma/puma/issues/633 "2014-12-31 @joevandyk"
[#478]:https://github.com/puma/puma/pull/478 "2014-02-25 @rubencaro"
[#610]:https://github.com/puma/puma/pull/610 "2014-11-27 @kwilczynski"
[#611]:https://github.com/puma/puma/pull/611 "2014-12-01 @jasonl"
[#616]:https://github.com/puma/puma/pull/616 "2014-12-10 @jc00ke"
[#623]:https://github.com/puma/puma/pull/623 "2014-12-14 @raldred"
[#628]:https://github.com/puma/puma/pull/628 "2014-12-20 @rdpoor"
[#634]:https://github.com/puma/puma/pull/634 "2015-01-06 @deepj"
[#637]:https://github.com/puma/puma/pull/637 "2015-01-13 @raskhadafi"
[#639]:https://github.com/puma/puma/pull/639 "2015-01-15 @ebeigarts"
[#640]:https://github.com/puma/puma/pull/640 "2015-01-20 @bailsman"
[#591]:https://github.com/puma/puma/issues/591 "2014-10-17 @renier"
[#606]:https://github.com/puma/puma/issues/606 "2014-11-21"
[#560]:https://github.com/puma/puma/pull/560 "2014-07-23 @raskhadafi"
[#566]:https://github.com/puma/puma/pull/566 "2014-08-01 @sheltond"
[#593]:https://github.com/puma/puma/pull/593 "2014-10-30 @andruby"
[#594]:https://github.com/puma/puma/pull/594 "2014-10-31 @hassox"
[#596]:https://github.com/puma/puma/pull/596 "2014-11-01 @burningTyger"
[#601]:https://github.com/puma/puma/pull/601 "2014-11-14 @sorentwo"
[#602]:https://github.com/puma/puma/pull/602 "2014-11-15 @1334"
[#608]:https://github.com/puma/puma/pull/608 "2014-11-24 @Gu1"
[#538]:https://github.com/puma/puma/pull/538 "2014-05-25 @memiux"
[#550]:https://github.com/puma/puma/issues/550 "2014-07-01"
[#549]:https://github.com/puma/puma/pull/549 "2014-07-01 @bsnape"
[#553]:https://github.com/puma/puma/pull/553 "2014-07-13 @lowjoel"
[#568]:https://github.com/puma/puma/pull/568 "2014-08-08 @mariuz"
[#578]:https://github.com/puma/puma/pull/578 "2014-09-11 @danielbuechele"
[#581]:https://github.com/puma/puma/pull/581 "2014-09-16 @alexch"
[#590]:https://github.com/puma/puma/pull/590 "2014-10-16 @dmarcotte"
[#574]:https://github.com/puma/puma/issues/574 "2014-09-03 @minasmart"
[#561]:https://github.com/puma/puma/pull/561 "2014-07-27 @krasnoukhov"
[#570]:https://github.com/puma/puma/pull/570 "2014-08-20 @havenwood"
[#520]:https://github.com/puma/puma/pull/520 "2014-04-14 @misfo"
[#530]:https://github.com/puma/puma/pull/530 "2014-05-05 @dmarcotte"
[#537]:https://github.com/puma/puma/pull/537 "2014-05-24 @vlmonk"
[#540]:https://github.com/puma/puma/pull/540 "2014-05-27 @allaire"
[#544]:https://github.com/puma/puma/pull/544 "2014-06-02 @chulkilee"
[#551]:https://github.com/puma/puma/pull/551 "2014-07-02 @jcxplorer"
[#487]:https://github.com/puma/puma/pull/487 "2014-03-01"
[#492]:https://github.com/puma/puma/pull/492 "2014-03-06"
[#493]:https://github.com/puma/puma/pull/493 "2014-03-07 @alepore"
[#503]:https://github.com/puma/puma/pull/503 "2014-03-17 @mariuz"
[#505]:https://github.com/puma/puma/pull/505 "2014-03-18 @sammcj"
[#506]:https://github.com/puma/puma/pull/506 "2014-03-26 @dsander"
[#510]:https://github.com/puma/puma/pull/510 "2014-03-28 @momer"
[#511]:https://github.com/puma/puma/pull/511 "2014-04-02 @macool"
[#514]:https://github.com/puma/puma/pull/514 "2014-04-08 @nanaya"
[#517]:https://github.com/puma/puma/pull/517 "2014-04-09 @misfo"
[#518]:https://github.com/puma/puma/pull/518 "2014-04-10 @alxgsv"
[#471]:https://github.com/puma/puma/pull/471 "2014-02-17 @arthurnn"
[#485]:https://github.com/puma/puma/pull/485 "2014-02-28 @runlevel5"
[#486]:https://github.com/puma/puma/pull/486 "2014-03-01 @joshwlewis"
[#490]:https://github.com/puma/puma/pull/490 "2014-03-05 @tobinibot"
[#491]:https://github.com/puma/puma/pull/491 "2014-03-05 @brianknight10"
[#438]:https://github.com/puma/puma/issues/438 "2014-01-17 @mperham"
[#333]:https://github.com/puma/puma/issues/333 "2013-07-18 @SamSaffron"
[#440]:https://github.com/puma/puma/issues/440 "2014-01-21 @sudara"
[#449]:https://github.com/puma/puma/issues/449 "2014-01-30 @cezarsa"
[#444]:https://github.com/puma/puma/issues/444 "2014-01-23 @le0pard"
[#370]:https://github.com/puma/puma/issues/370 "2013-09-12 @pelcasandra"
[#377]:https://github.com/puma/puma/issues/377 "2013-09-23 @mrbrdo"
[#406]:https://github.com/puma/puma/issues/406 "2013-11-06 @simonrussell"
[#425]:https://github.com/puma/puma/issues/425 "2013-12-06 @jhass"
[#432]:https://github.com/puma/puma/pull/432 "2013-12-21 @anatol"
[#428]:https://github.com/puma/puma/pull/428 "2013-12-10 @alexeyfrank"
[#429]:https://github.com/puma/puma/pull/429 "2013-12-14 @namusyaka"
[#431]:https://github.com/puma/puma/pull/431 "2013-12-20 @mrb"
[#433]:https://github.com/puma/puma/pull/433 "2013-12-22 @alepore"
[#437]:https://github.com/puma/puma/pull/437 "2014-01-06 @ibrahima"
[#446]:https://github.com/puma/puma/pull/446 "2014-01-27 @sudara"
[#451]:https://github.com/puma/puma/pull/451 "2014-01-30 @pwiebe"
[#453]:https://github.com/puma/puma/pull/453 "2014-02-04 @joevandyk"
[#470]:https://github.com/puma/puma/pull/470 "2014-02-17 @arthurnn"
[#472]:https://github.com/puma/puma/pull/472 "2014-02-21 @rubencaro"
[#480]:https://github.com/puma/puma/pull/480 "2014-02-25 @jjb"
[#481]:https://github.com/puma/puma/pull/481 "2014-02-25 @schneems"
[#482]:https://github.com/puma/puma/pull/482 "2014-02-25 @prathamesh-sonpatki"
[#483]:https://github.com/puma/puma/pull/483 "2014-02-26 @maxilev"
[#422]:https://github.com/puma/puma/issues/422 "2013-12-04 @alexandru-calinoiu"
[#334]:https://github.com/puma/puma/issues/334 "2013-07-18 @srgpqt"
[#179]:https://github.com/puma/puma/issues/179 "2012-12-30 @betelgeuse"
[#332]:https://github.com/puma/puma/issues/332 "2013-07-18 @SamSaffron"
[#317]:https://github.com/puma/puma/issues/317 "2013-07-11 @masterkain"
[#309]:https://github.com/puma/puma/issues/309 "2013-07-07 @masterkain"
[#166]:https://github.com/puma/puma/issues/166 "2012-11-21 @emassip"
[#292]:https://github.com/puma/puma/issues/292 "2013-06-26 @pulse00"
[#274]:https://github.com/puma/puma/issues/274 "2013-06-07 @mrbrdo"
[#304]:https://github.com/puma/puma/issues/304 "2013-07-05 @nandosola"
[#287]:https://github.com/puma/puma/issues/287 "2013-06-23 @runlevel5"
[#256]:https://github.com/puma/puma/issues/256 "2013-05-13 @rkh"
[#285]:https://github.com/puma/puma/issues/285 "2013-06-19 @mkwiatkowski"
[#270]:https://github.com/puma/puma/issues/270 "2013-06-01 @iamroody"
[#246]:https://github.com/puma/puma/issues/246 "2013-05-01 @amencarini"
[#278]:https://github.com/puma/puma/issues/278 "2013-06-13 @titanous"
[#251]:https://github.com/puma/puma/issues/251 "2013-05-06 @cure"
[#252]:https://github.com/puma/puma/issues/252 "2013-05-08 @vixns"
[#234]:https://github.com/puma/puma/issues/234 "2013-04-08 @jgarber"
[#228]:https://github.com/puma/puma/issues/228 "2013-03-28 @joelmats"
[#192]:https://github.com/puma/puma/issues/192 "2013-02-09 @steverandy"
[#206]:https://github.com/puma/puma/issues/206 "2013-03-01 @moll"
[#154]:https://github.com/puma/puma/issues/154 "2012-10-09 @trevor"
[#208]:https://github.com/puma/puma/issues/208 "2013-03-03 @ochronus"
[#189]:https://github.com/puma/puma/issues/189 "2013-02-08 @tolot27"
[#185]:https://github.com/puma/puma/issues/185 "2013-02-06 @nicolai86"
[#182]:https://github.com/puma/puma/issues/182 "2013-01-17 @sriedel"
[#183]:https://github.com/puma/puma/issues/183 "2013-01-21 @concept47"
[#176]:https://github.com/puma/puma/issues/176 "2012-12-18 @cryo28"
[#180]:https://github.com/puma/puma/issues/180 "2013-01-04 @tscolari"
[#170]:https://github.com/puma/puma/issues/170 "2012-11-28 @nixme"
[#148]:https://github.com/puma/puma/issues/148 "2012-09-12 @rafaelss"
[#128]:https://github.com/puma/puma/issues/128 "2012-07-31 @fbjork"
[#155]:https://github.com/puma/puma/issues/155 "2012-10-12 @ehlertij"
[#123]:https://github.com/puma/puma/pull/123 "2012-07-19 @jcoene"
[#111]:https://github.com/puma/puma/pull/111 "2012-06-28 @kenkeiter"
[#98]:https://github.com/puma/puma/pull/98 "2012-05-15 @Flink"
[#94]:https://github.com/puma/puma/issues/94 "2012-05-08 @ender672"
[#84]:https://github.com/puma/puma/issues/84 "2012-04-29 @sigursoft"
[#78]:https://github.com/puma/puma/issues/78 "2012-04-27 @dstrelau"
[#79]:https://github.com/puma/puma/issues/79 "2012-04-28 @jammi"
[#65]:https://github.com/puma/puma/issues/65 "2012-04-11 @bporterfield"
[#54]:https://github.com/puma/puma/issues/54 "2012-03-31 @masterkain"
[#58]:https://github.com/puma/puma/pull/58 "2012-04-07 @paneq"
[#61]:https://github.com/puma/puma/issues/61 "2012-04-09 @dustalov"
[#63]:https://github.com/puma/puma/issues/63 "2012-04-11 @seamusabshere"
[#60]:https://github.com/puma/puma/issues/60 "2012-04-08 @paneq"
[#53]:https://github.com/puma/puma/pull/53 "2012-03-31 @sxua"