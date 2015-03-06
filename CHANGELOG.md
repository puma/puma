# Change Log

## [Unreleased](https://github.com/puma/puma/tree/HEAD)

[Full Changelog](https://github.com/puma/puma/compare/v2.11.0...HEAD)

**Closed issues:**

- Puma hot restart hangs workers [\#659](https://github.com/puma/puma/issues/659)

- on\_worker\_boot can't find ActiveSupport constant on Rails 4.2 [\#656](https://github.com/puma/puma/issues/656)

- stuck in deadlock [\#654](https://github.com/puma/puma/issues/654)

- To add limit memory usage function [\#652](https://github.com/puma/puma/issues/652)

- Undefined method on using Puma on Heroku [\#651](https://github.com/puma/puma/issues/651)

- HTTP Parse Error [\#650](https://github.com/puma/puma/issues/650)

- fatal: Not a git repository \(or any of the parent directories\): .git when Puma starts on Heroku [\#648](https://github.com/puma/puma/issues/648)

- documentation for exception handler [\#641](https://github.com/puma/puma/issues/641)

**Merged pull requests:**

- Update default of NEWRELIC\_DISPACHER for New Relic [\#658](https://github.com/puma/puma/pull/658) ([Tomohiro](https://github.com/Tomohiro))

- Ignore multiple duplicate port declarations [\#657](https://github.com/puma/puma/pull/657) ([schneems](https://github.com/schneems))

- remove smart quotes from sample config file [\#646](https://github.com/puma/puma/pull/646) ([mkonecny](https://github.com/mkonecny))

- Avoid crash in strange restart conditions [\#644](https://github.com/puma/puma/pull/644) ([bpaquet](https://github.com/bpaquet))

## [v2.11.0](https://github.com/puma/puma/tree/v2.11.0) (2015-01-20)

[Full Changelog](https://github.com/puma/puma/compare/v2.10.2...v2.11.0)

**Closed issues:**

- puma.io - Website is down [\#636](https://github.com/puma/puma/issues/636)

- Parent process dies on phased restart when a long running request is in progress [\#635](https://github.com/puma/puma/issues/635)

- Set custom process title in worker processes [\#633](https://github.com/puma/puma/issues/633)

- Installing on a Raspberry Pi [\#631](https://github.com/puma/puma/issues/631)

- RFE: mode option wrt. unix sockets required [\#630](https://github.com/puma/puma/issues/630)

- Unable to install 2.10.x through bundler [\#629](https://github.com/puma/puma/issues/629)

- gem install --version 2.9.1 works, --version 2.9.2 and onward fails [\#627](https://github.com/puma/puma/issues/627)

- No response with Rails 4.2.0.rc2 [\#626](https://github.com/puma/puma/issues/626)

- Problem installing puma on OS X \(SSL\_CTX\_new\(\) prototype not found\) [\#625](https://github.com/puma/puma/issues/625)

- Whem puma run as daemon xmpp4r in initializer disconnects [\#624](https://github.com/puma/puma/issues/624)

- Can't bind socket uri containing a space char [\#622](https://github.com/puma/puma/issues/622)

- Add option to Puma’s config file to set environment variables like `JAVA\_OPTS` [\#621](https://github.com/puma/puma/issues/621)

- do I need to reconnect active record on\_worker\_boot when not in clustered mode? [\#619](https://github.com/puma/puma/issues/619)

- Stats in clustered mode [\#615](https://github.com/puma/puma/issues/615)

- ! WARNING: Detected 2 Thread\(s\) started in app boot: [\#614](https://github.com/puma/puma/issues/614)

- uninitialized constant Puma::Client::HttpParser [\#613](https://github.com/puma/puma/issues/613)

- Dependent requests can deadlock on puma if single-threaded [\#612](https://github.com/puma/puma/issues/612)

- Version 2.10.1 causes performance regressions [\#609](https://github.com/puma/puma/issues/609)

- Fails to start on FreeBSD10 and JRuby 1.7.15  [\#586](https://github.com/puma/puma/issues/586)

- puma 2.9.1 not finding puma.rb [\#584](https://github.com/puma/puma/issues/584)

- Errno::ENOTCONN - Socket is not connected [\#583](https://github.com/puma/puma/issues/583)

- Deploy 20 mini apps, how? [\#582](https://github.com/puma/puma/issues/582)

- 2.9.1 fully merged into master? [\#580](https://github.com/puma/puma/issues/580)

- Puma hangs on startup inside Docker container [\#579](https://github.com/puma/puma/issues/579)

- Puma crashes with no output when stdout\_redirect is set [\#359](https://github.com/puma/puma/issues/359)

**Merged pull requests:**

- Add a configuration option that prevents puma from queueing requests. [\#640](https://github.com/puma/puma/pull/640) ([codehotter](https://github.com/codehotter))

- Fix phased restart with worker shutdown timeout [\#639](https://github.com/puma/puma/pull/639) ([ebeigarts](https://github.com/ebeigarts))

- Update config.rb with on\_worker\_shutdown. [\#637](https://github.com/puma/puma/pull/637) ([raskhadafi](https://github.com/raskhadafi))

- Use the latest ruby 2.2 on travis [\#634](https://github.com/puma/puma/pull/634) ([deepj](https://github.com/deepj))

- Update extconf.rb to compile correctly on OS X [\#628](https://github.com/puma/puma/pull/628) ([rdpoor](https://github.com/rdpoor))

- Don't write lowlevel\_error\_handler to state [\#623](https://github.com/puma/puma/pull/623) ([raldred](https://github.com/raldred))

- Mongrel::HttpServer hack no longer needed [\#616](https://github.com/puma/puma/pull/616) ([jc00ke](https://github.com/jc00ke))

- Update lowlevel error message to be more meaningful. [\#611](https://github.com/puma/puma/pull/611) ([jasonl](https://github.com/jasonl))

- Add the ability to pass environment variables to the init script \(for Ju... [\#610](https://github.com/puma/puma/pull/610) ([kwilczynski](https://github.com/kwilczynski))

- changed pumactl restart for phased-restart in the init script [\#543](https://github.com/puma/puma/pull/543) ([dcrec1](https://github.com/dcrec1))

- Add reload\_worker\_directory to pumactl [\#478](https://github.com/puma/puma/pull/478) ([rubencaro](https://github.com/rubencaro))

- Merge stop, restart and phased\_restart  tasks [\#376](https://github.com/puma/puma/pull/376) ([div](https://github.com/div))

## [v2.10.2](https://github.com/puma/puma/tree/v2.10.2) (2014-11-27)

[Full Changelog](https://github.com/puma/puma/compare/v2.10.1...v2.10.2)

**Closed issues:**

- SIGHUP causes puma to crash [\#588](https://github.com/puma/puma/issues/588)

## [v2.10.1](https://github.com/puma/puma/tree/v2.10.1) (2014-11-24)

[Full Changelog](https://github.com/puma/puma/compare/v2.10.0...v2.10.1)

**Closed issues:**

- Rufus scheduler 3.0.3 doesn´t work with Puma 2.9.2  [\#607](https://github.com/puma/puma/issues/607)

## [v2.10.0](https://github.com/puma/puma/tree/v2.10.0) (2014-11-24)

[Full Changelog](https://github.com/puma/puma/compare/v2.9.2...v2.10.0)

**Closed issues:**

- Should not bind option in config.ru override other setups? [\#606](https://github.com/puma/puma/issues/606)

- might want to add to the doc that for rails one might want to 'spring stop' if console errors [\#604](https://github.com/puma/puma/issues/604)

- Problem installing puma on Ubuntu [\#600](https://github.com/puma/puma/issues/600)

- Puma Cannot Install Extension \(Yosemite, Rails 4.1.4, Ruby 2.0.0\) [\#599](https://github.com/puma/puma/issues/599)

- problems with Puma phased restarts in Rails apps [\#598](https://github.com/puma/puma/issues/598)

- `-b tcp://0.0.0.0 -p 8000` causes type error in JRuby [\#597](https://github.com/puma/puma/issues/597)

- Error while installing puma 2.9.2 \(jruby 1.7.16\) [\#592](https://github.com/puma/puma/issues/592)

- Disable SSLv3? [\#591](https://github.com/puma/puma/issues/591)

- Best practice to use puma with websockets [\#589](https://github.com/puma/puma/issues/589)

- Puma creates lot of sockets flooding limit [\#541](https://github.com/puma/puma/issues/541)

**Merged pull requests:**

- Allow binding to ipv6 addresses for ssl URIs [\#608](https://github.com/puma/puma/pull/608) ([Gu1](https://github.com/Gu1))

- fix typo in README.md [\#602](https://github.com/puma/puma/pull/602) ([1334](https://github.com/1334))

- Change umask examples to more permissive values [\#601](https://github.com/puma/puma/pull/601) ([sorentwo](https://github.com/sorentwo))

- fixed some typos [\#596](https://github.com/puma/puma/pull/596) ([burningTyger](https://github.com/burningTyger))

- Clean out a threads local data before doing work [\#594](https://github.com/puma/puma/pull/594) ([hassox](https://github.com/hassox))

- Fix 2.9.2 release date in History.txt [\#593](https://github.com/puma/puma/pull/593) ([andruby](https://github.com/andruby))

- Added on\_worker\_shutdown mechanism [\#566](https://github.com/puma/puma/pull/566) ([sheltond](https://github.com/sheltond))

- First change the directory to use the correct Gemfile. [\#560](https://github.com/puma/puma/pull/560) ([raskhadafi](https://github.com/raskhadafi))

## [v2.9.2](https://github.com/puma/puma/tree/v2.9.2) (2014-10-30)

[Full Changelog](https://github.com/puma/puma/compare/v2.9.1...v2.9.2)

**Closed issues:**

- I don't want to use Rack::CommonLogger, but puma does [\#585](https://github.com/puma/puma/issues/585)

- Rails 4.1.6 Puma Crash [\#577](https://github.com/puma/puma/issues/577)

- What's the right signal to send to a child worker to tell it to finish requests and then die? [\#575](https://github.com/puma/puma/issues/575)

- Calling HUP kills Puma [\#573](https://github.com/puma/puma/issues/573)

- some problems with upstart [\#572](https://github.com/puma/puma/issues/572)

- Windows 8 x86 cannot find -lssl [\#571](https://github.com/puma/puma/issues/571)

- HTTPS without keepalive causes a memory leak [\#567](https://github.com/puma/puma/issues/567)

- Executing requests count [\#565](https://github.com/puma/puma/issues/565)

- USR2 restart kills master / worker processes with prune\_bundler option [\#550](https://github.com/puma/puma/issues/550)

**Merged pull requests:**

- JRuby SSL POODLE update [\#590](https://github.com/puma/puma/pull/590) ([dmarcotte](https://github.com/dmarcotte))

- better error logging during startup [\#581](https://github.com/puma/puma/pull/581) ([alexch](https://github.com/alexch))

- fixing sexist error messages [\#578](https://github.com/puma/puma/pull/578) ([danielbuechele](https://github.com/danielbuechele))

- Update README.md [\#568](https://github.com/puma/puma/pull/568) ([mariuz](https://github.com/mariuz))

- Instead of hardcoding dependencies, detect and use what is found [\#553](https://github.com/puma/puma/pull/553) ([lowjoel](https://github.com/lowjoel))

- Log the current time when Puma shuts down. [\#549](https://github.com/puma/puma/pull/549) ([bsnape](https://github.com/bsnape))

## [v2.9.1](https://github.com/puma/puma/tree/v2.9.1) (2014-09-05)

[Full Changelog](https://github.com/puma/puma/compare/v2.9.0...v2.9.1)

**Closed issues:**

- Phased-restart sleep 5 [\#574](https://github.com/puma/puma/issues/574)

- TimeoutError when trying to make a request to the same application [\#546](https://github.com/puma/puma/issues/546)

- Bad file descriptor error on `rails server` exiting [\#542](https://github.com/puma/puma/issues/542)

- Not working with chdir of  upstart? [\#539](https://github.com/puma/puma/issues/539)

- How do I create an intra-process cache? [\#534](https://github.com/puma/puma/issues/534)

- RuntimeException with jRuby in server.rb [\#527](https://github.com/puma/puma/issues/527)

- Puma mangles chunked encoding when used with rack-streaming-proxy [\#523](https://github.com/puma/puma/issues/523)

- SSL not working [\#522](https://github.com/puma/puma/issues/522)

- init.d scripts with rvm [\#521](https://github.com/puma/puma/issues/521)

- Puma says "Address already in use" [\#516](https://github.com/puma/puma/issues/516)

- Support for chained ssl cert [\#515](https://github.com/puma/puma/issues/515)

- Configuration file when booted through `rails server` [\#512](https://github.com/puma/puma/issues/512)

- Ruby 2.x with GIL + a single CPU server = saturation despite GIL? [\#509](https://github.com/puma/puma/issues/509)

- Can't start Puma in production mode with Sinatra app [\#504](https://github.com/puma/puma/issues/504)

- unexpected db connection behavior [\#502](https://github.com/puma/puma/issues/502)

- How to get info from activate\_control\_app? \(no docs?\) [\#501](https://github.com/puma/puma/issues/501)

- invalid %-encoding [\#500](https://github.com/puma/puma/issues/500)

- xcode 5.1, clang-503.0.38 error [\#499](https://github.com/puma/puma/issues/499)

- daemon mode not killing a thread [\#498](https://github.com/puma/puma/issues/498)

- Encoding::UndefinedConversionError [\#489](https://github.com/puma/puma/issues/489)

- Reloading config file without hard restart... [\#474](https://github.com/puma/puma/issues/474)

- Puma inconsistently creating PID file [\#466](https://github.com/puma/puma/issues/466)

- upstream timed out \(110: Connection timed out\) while reading response header from upstream [\#464](https://github.com/puma/puma/issues/464)

- MRI Ruby 2.1: Segmentation Fault [\#459](https://github.com/puma/puma/issues/459)

- Google Chrome \(32,30,28...\) hangs in couple with puma \(2.7.X and 2.6.0\) and redmine on windows [\#455](https://github.com/puma/puma/issues/455)

- Puma + Rails 3.2.16 truncates json respond in certain scenario [\#452](https://github.com/puma/puma/issues/452)

- Ruby 2.1: Out-of-Band GC [\#450](https://github.com/puma/puma/issues/450)

- SSL [\#442](https://github.com/puma/puma/issues/442)

- Rubinus 2.2.1 + Puma 2.7.1 raise "Data object has already been freed \(ArgumentError\)" [\#434](https://github.com/puma/puma/issues/434)

- Puma not restarting \(or at least not loading new current\) when notified with SIGUSR2 [\#416](https://github.com/puma/puma/issues/416)

- Threads die in an infinite loop on some requests using Rubinius [\#400](https://github.com/puma/puma/issues/400)

- Read error: \#<IOError: stream closed\> in development environment [\#397](https://github.com/puma/puma/issues/397)

- Puma via capistrano crashes due to missing Gemfile on restart [\#329](https://github.com/puma/puma/issues/329)

**Merged pull requests:**

- Fix thread spawning edge case. [\#570](https://github.com/puma/puma/pull/570) ([havenwood](https://github.com/havenwood))

- Implement SIGHUP for logs reopening [\#561](https://github.com/puma/puma/pull/561) ([krasnoukhov](https://github.com/krasnoukhov))

- dump exception stack trace to STDOUT in production [\#477](https://github.com/puma/puma/pull/477) ([jjb](https://github.com/jjb))

- Freeze ERROR\_400\_RESPONSE const [\#473](https://github.com/puma/puma/pull/473) ([dariocravero](https://github.com/dariocravero))

## [v2.9.0](https://github.com/puma/puma/tree/v2.9.0) (2014-07-13)

[Full Changelog](https://github.com/puma/puma/compare/v2.8.2...v2.9.0)

**Closed issues:**

- Double resource serving [\#552](https://github.com/puma/puma/issues/552)

- NoMethodError: undefined method `bytesize' for \["id", 86261648108\]:Array [\#536](https://github.com/puma/puma/issues/536)

- phased restarts are potentially broken in 2.8.x? [\#533](https://github.com/puma/puma/issues/533)

- How to disable multi-threading completely? [\#531](https://github.com/puma/puma/issues/531)

- puma cluster mode: master forked workers more than configuration [\#526](https://github.com/puma/puma/issues/526)

- runner.rb:34:in `require': cannot load such file -- puma/app/status \(LoadError\) [\#524](https://github.com/puma/puma/issues/524)

- Installing and using Puma on a Apache Server on a CentOS server [\#447](https://github.com/puma/puma/issues/447)

- `pumactl restart` stops puma [\#436](https://github.com/puma/puma/issues/436)

**Merged pull requests:**

- Fix typo in DEPLOYMENT.md [\#551](https://github.com/puma/puma/pull/551) ([jcxplorer](https://github.com/jcxplorer))

- BSD-3-Clause over BSD to avoid confusion [\#544](https://github.com/puma/puma/pull/544) ([chulkilee](https://github.com/chulkilee))

- Typo BUNDLER\_GEMFILE -\> BUNDLE\_GEMFILE [\#540](https://github.com/puma/puma/pull/540) ([allaire](https://github.com/allaire))

- Strongish cipher suite with FS support for some browsers [\#538](https://github.com/puma/puma/pull/538) ([memiux](https://github.com/memiux))

- pumactl - do not modify original ARGV [\#537](https://github.com/puma/puma/pull/537) ([vlmonk](https://github.com/vlmonk))

- SSL support for JRuby [\#530](https://github.com/puma/puma/pull/530) ([dmarcotte](https://github.com/dmarcotte))

- Deploy doc: clarification of the GIL [\#520](https://github.com/puma/puma/pull/520) ([misfo](https://github.com/misfo))

- Change \#rubyforge\_name to \#group\_name [\#507](https://github.com/puma/puma/pull/507) ([yegortimoschenko](https://github.com/yegortimoschenko))

- During upgrade, change directory in main process instead of workers. [\#469](https://github.com/puma/puma/pull/469) ([maljub01](https://github.com/maljub01))

## [v2.8.2](https://github.com/puma/puma/tree/v2.8.2) (2014-04-12)

[Full Changelog](https://github.com/puma/puma/compare/v2.8.1...v2.8.2)

**Closed issues:**

- multiple pumas on different socket addresses [\#497](https://github.com/puma/puma/issues/497)

- Gemfile cleanup [\#496](https://github.com/puma/puma/issues/496)

- IOError: Connection refused error raised if puma socket file existed [\#475](https://github.com/puma/puma/issues/475)

- Logging stops working and IOError [\#465](https://github.com/puma/puma/issues/465)

- Unix sockets, Puma, Nginx Concurrency issues [\#462](https://github.com/puma/puma/issues/462)

- HTTP 2.0 [\#454](https://github.com/puma/puma/issues/454)

**Merged pull requests:**

- fallback from phased restart to start when not started [\#518](https://github.com/puma/puma/pull/518) ([LongMan](https://github.com/LongMan))

- Fix Puma daemon service README typo [\#517](https://github.com/puma/puma/pull/517) ([misfo](https://github.com/misfo))

- Refactor env check to its own method. [\#514](https://github.com/puma/puma/pull/514) ([edogawaconan](https://github.com/edogawaconan))

- Set rack\_env early enough. [\#513](https://github.com/puma/puma/pull/513) ([edogawaconan](https://github.com/edogawaconan))

- `preload\_app!` instead of `preload\_app` [\#511](https://github.com/puma/puma/pull/511) ([macool](https://github.com/macool))

- Somewhere along the way, the variable which held the new Client object i... [\#510](https://github.com/puma/puma/pull/510) ([momer](https://github.com/momer))

- Fix Clang support by deleting -multiply-definedsuppress flag from DLDFLAGS [\#508](https://github.com/puma/puma/pull/508) ([yegortimoschenko](https://github.com/yegortimoschenko))

- allow changing of worker\_timeout in config file [\#506](https://github.com/puma/puma/pull/506) ([dsander](https://github.com/dsander))

- Update README.md [\#505](https://github.com/puma/puma/pull/505) ([sammcj](https://github.com/sammcj))

- Update README.md [\#503](https://github.com/puma/puma/pull/503) ([mariuz](https://github.com/mariuz))

- make phased\_restart a question \(boolean\) [\#495](https://github.com/puma/puma/pull/495) ([catsby](https://github.com/catsby))

- Swap `and` for `&&` in cli.rb [\#494](https://github.com/puma/puma/pull/494) ([catsby](https://github.com/catsby))

- allow tag option in conf file [\#493](https://github.com/puma/puma/pull/493) ([alepore](https://github.com/alepore))

- fix typo in config file [\#492](https://github.com/puma/puma/pull/492) ([ckuttruff](https://github.com/ckuttruff))

- Add preload\_app and prune\_bundler to example config [\#487](https://github.com/puma/puma/pull/487) ([ckuttruff](https://github.com/ckuttruff))

## [v2.8.1](https://github.com/puma/puma/tree/v2.8.1) (2014-03-06)

[Full Changelog](https://github.com/puma/puma/compare/v2.8.0...v2.8.1)

**Closed issues:**

- Puma + SSL + Rails in development and output logs in console [\#488](https://github.com/puma/puma/issues/488)

- Document restart best practices [\#484](https://github.com/puma/puma/issues/484)

- Why is puma not booting on init?  [\#375](https://github.com/puma/puma/issues/375)

- Thread specific data/cleanup hooks [\#356](https://github.com/puma/puma/issues/356)

- 404s on random static files served via middleware [\#337](https://github.com/puma/puma/issues/337)

- after\_fork hook for daemonize without clustering? [\#335](https://github.com/puma/puma/issues/335)

- Restarting process with USR2 doesn't always work [\#197](https://github.com/puma/puma/issues/197)

- Feature request: Chunked mode request handling [\#80](https://github.com/puma/puma/issues/80)

**Merged pull requests:**

- Describe config file finding behavior in 2.8.0 and how to disable it [\#491](https://github.com/puma/puma/pull/491) ([brianknight10](https://github.com/brianknight10))

- Freeze a few more string constants [\#490](https://github.com/puma/puma/pull/490) ([tobinibot](https://github.com/tobinibot))

- Minor copy edits in DEPLOYMENT.md [\#486](https://github.com/puma/puma/pull/486) ([joshwlewis](https://github.com/joshwlewis))

- Test against Ruby 2.1.1 on Travis [\#485](https://github.com/puma/puma/pull/485) ([joneslee85](https://github.com/joneslee85))

- Fix require testhelp [\#471](https://github.com/puma/puma/pull/471) ([arthurnn](https://github.com/arthurnn))

## [v2.8.0](https://github.com/puma/puma/tree/v2.8.0) (2014-02-28)

[Full Changelog](https://github.com/puma/puma/compare/v2.7.1...v2.8.0)

**Closed issues:**

- Extra Puma Process [\#479](https://github.com/puma/puma/issues/479)

- documentation on how to run tests? [\#476](https://github.com/puma/puma/issues/476)

- Phased restart does not persist new code [\#468](https://github.com/puma/puma/issues/468)

- Purpose of `on\_restart` config directive. README file wrong? [\#463](https://github.com/puma/puma/issues/463)

- Stats not available via pid only [\#461](https://github.com/puma/puma/issues/461)

- Maytag\(tm\) repair man error is confusing our users [\#458](https://github.com/puma/puma/issues/458)

- Defeer rails loading till after daemonization for single mode [\#457](https://github.com/puma/puma/issues/457)

- rubinius 2.2.4 + puma 2.7.1 raise ActiveRecord::ConnectionNotEstablished [\#456](https://github.com/puma/puma/issues/456)

- Puma frozen in an infinite loop [\#449](https://github.com/puma/puma/issues/449)

- redis-rb InheritedError in single mode [\#448](https://github.com/puma/puma/issues/448)

- Puma + Rails claims server is running on existence of pidfile. [\#445](https://github.com/puma/puma/issues/445)

- Puma delete pid file in cluster mode [\#444](https://github.com/puma/puma/issues/444)

- Puma stoppped working [\#443](https://github.com/puma/puma/issues/443)

- Monitoring Puma workers for memory, dropping child PIDs [\#440](https://github.com/puma/puma/issues/440)

- Puma no accept connection after error in sidekiq [\#439](https://github.com/puma/puma/issues/439)

- Auto-detect config file [\#438](https://github.com/puma/puma/issues/438)

- SSL unsupported for JRuby [\#435](https://github.com/puma/puma/issues/435)

- Puma installation issue x64 ubuntu [\#430](https://github.com/puma/puma/issues/430)

- ArgumentError on ruby 1.8.7 [\#427](https://github.com/puma/puma/issues/427)

- All threads blocked when Net::Http tries to open a connection [\#426](https://github.com/puma/puma/issues/426)

- Systemd socket activation produces Errno::EOPNOTSUPP [\#425](https://github.com/puma/puma/issues/425)

- Problem installing puma on windows [\#424](https://github.com/puma/puma/issues/424)

- puma 2.7.1 not working, not logging and reinstalling when run with jungle scripts [\#423](https://github.com/puma/puma/issues/423)

- Feature request: JRuby hot restart [\#418](https://github.com/puma/puma/issues/418)

- Add app name for puma processes [\#415](https://github.com/puma/puma/issues/415)

- Where is the log option of the run-puma jungle script being used? [\#414](https://github.com/puma/puma/issues/414)

- Puma process doesn't restart [\#413](https://github.com/puma/puma/issues/413)

- pumactl gives me a `allocator undefined for Proc` error [\#411](https://github.com/puma/puma/issues/411)

- which ruby engines benefit from clustered mode? [\#410](https://github.com/puma/puma/issues/410)

- pumactl stop not working [\#409](https://github.com/puma/puma/issues/409)

- ThreadPool todo list seems to be a stack, rather than a queue? [\#406](https://github.com/puma/puma/issues/406)

- MAX\_REQUEST\_PATH\_LENGTH = 1024; Why? [\#404](https://github.com/puma/puma/issues/404)

-  Errno::EADDRNOTAVAIL: Cannot assign requested address - bind - Cannot assign requested address [\#403](https://github.com/puma/puma/issues/403)

- restart puma kill process and no new one startup when I deploy  [\#401](https://github.com/puma/puma/issues/401)

- restart puma through `cap puma:restart` sometimes not work [\#395](https://github.com/puma/puma/issues/395)

- puma rails server no longer stops correctly with ctrl-c in jruby 1.7.5 [\#394](https://github.com/puma/puma/issues/394)

- Puma stop/restart issue [\#392](https://github.com/puma/puma/issues/392)

- poor performance using jruby and rails [\#391](https://github.com/puma/puma/issues/391)

- Symbols in headers hash raise TypeError [\#388](https://github.com/puma/puma/issues/388)

- puma cannot handle large html files [\#386](https://github.com/puma/puma/issues/386)

- Puma daemon is randomly killed during deploys [\#385](https://github.com/puma/puma/issues/385)

- Puma Stack Trace? [\#381](https://github.com/puma/puma/issues/381)

- unused sock file [\#377](https://github.com/puma/puma/issues/377)

- Release notes for new versions would be awesome:\) [\#371](https://github.com/puma/puma/issues/371)

- Is there something like a backlog? [\#370](https://github.com/puma/puma/issues/370)

- The PID is not updated when there is an error [\#367](https://github.com/puma/puma/issues/367)

- Server running twice \(Upstart\) [\#366](https://github.com/puma/puma/issues/366)

- Puma hangs during asset loading [\#358](https://github.com/puma/puma/issues/358)

- capistrano, puma state file [\#354](https://github.com/puma/puma/issues/354)

- Runaway CPU and memory detection and repair for pumas in cluster mode [\#333](https://github.com/puma/puma/issues/333)

- "pumactl stop" just removed pumactl.sock and left puma process and socket running [\#306](https://github.com/puma/puma/issues/306)

- Add `before\_worker\_boot` config block with clustered mode [\#303](https://github.com/puma/puma/issues/303)

- wicked\_pdf crashes puma when using cluster mode [\#294](https://github.com/puma/puma/issues/294)

- No such file or directory - /tmp/puma-status-1363809668331-14055 [\#224](https://github.com/puma/puma/issues/224)

**Merged pull requests:**

- Added "after worker boot" hook [\#483](https://github.com/puma/puma/pull/483) ([maxilev](https://github.com/maxilev))

- Minor cleanup of signals.md \[ci skip\] [\#482](https://github.com/puma/puma/pull/482) ([prathamesh-sonpatki](https://github.com/prathamesh-sonpatki))

- Create signals.md [\#481](https://github.com/puma/puma/pull/481) ([schneems](https://github.com/schneems))

- readme notes on running test suite [\#480](https://github.com/puma/puma/pull/480) ([jjb](https://github.com/jjb))

- React when a worker does not load on a `phased\_restart` [\#472](https://github.com/puma/puma/pull/472) ([rubencaro](https://github.com/rubencaro))

- Add config to customize the default error message [\#470](https://github.com/puma/puma/pull/470) ([arthurnn](https://github.com/arthurnn))

- Remove non-functioning workers [\#467](https://github.com/puma/puma/pull/467) ([schneems](https://github.com/schneems))

- Fix speling in README.md [\#453](https://github.com/puma/puma/pull/453) ([joevandyk](https://github.com/joevandyk))

- Add status 408 for when server times out waiting for body content. [\#451](https://github.com/puma/puma/pull/451) ([pwiebe](https://github.com/pwiebe))

- Assure worker index is always within 0...@options\[:workers\] [\#446](https://github.com/puma/puma/pull/446) ([sudara](https://github.com/sudara))

- little cleanup [\#441](https://github.com/puma/puma/pull/441) ([shaiguitar](https://github.com/shaiguitar))

- Add rbenv shims to PATH in upstart conf file [\#437](https://github.com/puma/puma/pull/437) ([ibrahima](https://github.com/ibrahima))

- add pretty process name [\#433](https://github.com/puma/puma/pull/433) ([alepore](https://github.com/alepore))

- Add license to gemspec [\#432](https://github.com/puma/puma/pull/432) ([anatol](https://github.com/anatol))

- Add Code Climate badge to README [\#431](https://github.com/puma/puma/pull/431) ([mrb](https://github.com/mrb))

- Revert from 01cb454578. [\#429](https://github.com/puma/puma/pull/429) ([namusyaka](https://github.com/namusyaka))

- add capistrano options puma\_default\_hooks with compatibility [\#428](https://github.com/puma/puma/pull/428) ([alexeyfrank](https://github.com/alexeyfrank))

- Add before\_boot hook for Clustered mode [\#338](https://github.com/puma/puma/pull/338) ([catsby](https://github.com/catsby))

## [v2.7.1](https://github.com/puma/puma/tree/v2.7.1) (2013-12-05)

[Full Changelog](https://github.com/puma/puma/compare/v2.7.0...v2.7.1)

**Closed issues:**

- Puma 2.7 starting with Daemonize does not boot server [\#422](https://github.com/puma/puma/issues/422)

**Merged pull requests:**

- Remove old, outdated, TODO list [\#421](https://github.com/puma/puma/pull/421) ([stevenharman](https://github.com/stevenharman))

## [v2.7.0](https://github.com/puma/puma/tree/v2.7.0) (2013-12-04)

[Full Changelog](https://github.com/puma/puma/compare/v2.6.0...v2.7.0)

**Closed issues:**

- LoadError::InvalidExtensionError when starting Rails or Sinatra application [\#412](https://github.com/puma/puma/issues/412)

- Puma fails to start on JRuby when JMX is enabled [\#407](https://github.com/puma/puma/issues/407)

- error when starting \>3 workers in development environment [\#405](https://github.com/puma/puma/issues/405)

- Many worker processes are forked [\#402](https://github.com/puma/puma/issues/402)

- Capistrano 3 support [\#396](https://github.com/puma/puma/issues/396)

- LoadError: json/json - Rubinius 2.0.0n276 \(Ruby 2.1.0 Mode\) [\#382](https://github.com/puma/puma/issues/382)

- Run error Error [\#380](https://github.com/puma/puma/issues/380)

- ERROR: worker mode not supported on JRuby and Windows [\#374](https://github.com/puma/puma/issues/374)

- Read error: \#<Errno::EPIPE: Broken pipe\> [\#368](https://github.com/puma/puma/issues/368)

- How to determine the status of a puma server [\#364](https://github.com/puma/puma/issues/364)

- asset pipeline weirdness [\#361](https://github.com/puma/puma/issues/361)

- A really lowlevel plumbing error occured. Maytag\(tm\) error [\#360](https://github.com/puma/puma/issues/360)

- Error in reactor loop escaped: closed stream \(IOError\) [\#352](https://github.com/puma/puma/issues/352)

- Puma version 2.4.1 and SSL [\#350](https://github.com/puma/puma/issues/350)

**Merged pull requests:**

- Change position of `cd` so that rvm gemset is loaded [\#419](https://github.com/puma/puma/pull/419) ([daniel-g](https://github.com/daniel-g))

- Fix for issue \#350 [\#417](https://github.com/puma/puma/pull/417) ([cjfuller](https://github.com/cjfuller))

- Increase the max URI path length to 2048 from 1024 [\#408](https://github.com/puma/puma/pull/408) ([priyankc](https://github.com/priyankc))

- Adding TTIN and TTOU to increment/decrement workers [\#399](https://github.com/puma/puma/pull/399) ([softr8](https://github.com/softr8))

- Reactor loop fixes [\#398](https://github.com/puma/puma/pull/398) ([grddev](https://github.com/grddev))

- server.rb: use human readable names for socket options [\#393](https://github.com/puma/puma/pull/393) ([kyrylo](https://github.com/kyrylo))

- Fix compatibility with 1.8.7 [\#390](https://github.com/puma/puma/pull/390) ([namusyaka](https://github.com/namusyaka))

- explain that --preload is necessary to take advantage of CoW [\#387](https://github.com/puma/puma/pull/387) ([jjb](https://github.com/jjb))

- Clarify some platform specifics [\#384](https://github.com/puma/puma/pull/384) ([catsby](https://github.com/catsby))

- Fix String\#byteslice for Ruby 1.9.1, 1.9.2 [\#379](https://github.com/puma/puma/pull/379) ([shigi](https://github.com/shigi))

- Add capistrano restart error handling and try to start. [\#378](https://github.com/puma/puma/pull/378) ([gekola](https://github.com/gekola))

- Update cli.rb [\#373](https://github.com/puma/puma/pull/373) ([mdarby](https://github.com/mdarby))

- Upstart jungle use config/puma.rb instead [\#372](https://github.com/puma/puma/pull/372) ([lukethenuke](https://github.com/lukethenuke))

## [v2.6.0](https://github.com/puma/puma/tree/v2.6.0) (2013-09-13)

[Full Changelog](https://github.com/puma/puma/compare/v2.5.1...v2.6.0)

**Closed issues:**

- puma/tools/jungle/upstart/ README.md different to source code [\#353](https://github.com/puma/puma/issues/353)

- Puma dies on restart under jruby when daemonized [\#344](https://github.com/puma/puma/issues/344)

- windows 8 64bit  [\#341](https://github.com/puma/puma/issues/341)

- cannot load such file -- puma/minissl [\#330](https://github.com/puma/puma/issues/330)

- Does --preload help with CoW utilization? [\#321](https://github.com/puma/puma/issues/321)

- Feature request: make capistrano puma:restart task don't fail if puma is not started [\#318](https://github.com/puma/puma/issues/318)

- cannot stop puma completly on windows [\#284](https://github.com/puma/puma/issues/284)

- Crash without log on win7 [\#261](https://github.com/puma/puma/issues/261)

- No concurrency unless threads count set to 8:8 [\#260](https://github.com/puma/puma/issues/260)

- IO.read does not return the whole string ? [\#241](https://github.com/puma/puma/issues/241)

- Socket is not removed by USR2, resulting in Errno::EADDRINUSE [\#193](https://github.com/puma/puma/issues/193)

**Merged pull requests:**

- Handle BrokenPipe, StandardError and IOError in fat\_wrote and break out [\#369](https://github.com/puma/puma/pull/369) ([nmccready](https://github.com/nmccready))

- Define RSTRING\_NOT\_MODIFIED for Rubinius performance [\#363](https://github.com/puma/puma/pull/363) ([dbussink](https://github.com/dbussink))

- Convince workers to stop by SIGKILL after timeout [\#362](https://github.com/puma/puma/pull/362) ([krasnoukhov](https://github.com/krasnoukhov))

- Return success status on daemonizing to the invoking environment [\#357](https://github.com/puma/puma/pull/357) ([yabawock](https://github.com/yabawock))

- Make NullIO respond to nil? [\#355](https://github.com/puma/puma/pull/355) ([tume](https://github.com/tume))

- Capistrano. Add phased\_restart and accept config file per stage. Phase phased\_restart by default after deploy:restart [\#328](https://github.com/puma/puma/pull/328) ([bugaiov](https://github.com/bugaiov))

- Capistrano. Add phased\_restart. [\#314](https://github.com/puma/puma/pull/314) ([Juanmcuello](https://github.com/Juanmcuello))

## [v2.5.1](https://github.com/puma/puma/tree/v2.5.1) (2013-08-13)

[Full Changelog](https://github.com/puma/puma/compare/v2.5.0...v2.5.1)

**Closed issues:**

- No such file or directory \(puma.sock\) when attempting to deploy with Capistrano [\#343](https://github.com/puma/puma/issues/343)

## [v2.5.0](https://github.com/puma/puma/tree/v2.5.0) (2013-08-08)

[Full Changelog](https://github.com/puma/puma/compare/v2.4.1...v2.5.0)

**Closed issues:**

- Start Puma as pumactl with init.d and config.rb [\#331](https://github.com/puma/puma/issues/331)

**Merged pull requests:**

- Fix issue with non-String header values. [\#351](https://github.com/puma/puma/pull/351) ([RobinDaugherty](https://github.com/RobinDaugherty))

- Correctly report phased-restart availability and log when phased-restart is not available. [\#349](https://github.com/puma/puma/pull/349) ([mjc](https://github.com/mjc))

- Upstart autodetect ruby managers [\#348](https://github.com/puma/puma/pull/348) ([mjc](https://github.com/mjc))

- Fix typo in phased-restart response [\#347](https://github.com/puma/puma/pull/347) ([mjc](https://github.com/mjc))

- Use integers when comparing thread counts [\#345](https://github.com/puma/puma/pull/345) ([jc00ke](https://github.com/jc00ke))

- phased-restart now an option for pumactl [\#340](https://github.com/puma/puma/pull/340) ([karlfreeman](https://github.com/karlfreeman))

## [v2.4.1](https://github.com/puma/puma/tree/v2.4.1) (2013-08-07)

[Full Changelog](https://github.com/puma/puma/compare/v2.4.0...v2.4.1)

**Merged pull requests:**

- pumactl restart will start if not already running [\#346](https://github.com/puma/puma/pull/346) ([tjmcewan](https://github.com/tjmcewan))

- Use Puma::Const::PUMA\_VERSION in gemspec [\#339](https://github.com/puma/puma/pull/339) ([czarneckid](https://github.com/czarneckid))

## [v2.4.0](https://github.com/puma/puma/tree/v2.4.0) (2013-07-22)

[Full Changelog](https://github.com/puma/puma/compare/v2.3.2...v2.4.0)

**Closed issues:**

- Workers deleting pidfile because of inherited at\_exit handler [\#334](https://github.com/puma/puma/issues/334)

- Logging on hijack requests is weird [\#332](https://github.com/puma/puma/issues/332)

- Connection pool options [\#322](https://github.com/puma/puma/issues/322)

- USR1 or smart USR2 not working as expected [\#320](https://github.com/puma/puma/issues/320)

- `on\_worker\_boot': undefined method `<<' for nil:NilClass \(NoMethodError\) [\#317](https://github.com/puma/puma/issues/317)

- Puma server does not serve static files for my app [\#313](https://github.com/puma/puma/issues/313)

- pumactl socket not created [\#312](https://github.com/puma/puma/issues/312)

- Forward REMOTE\_ADDR when using unix socket [\#309](https://github.com/puma/puma/issues/309)

- HTTP element HEADER is longer than the \(1024 \* \(80 + 32\)\) allowed length [\#179](https://github.com/puma/puma/issues/179)

- Server is not restarting [\#165](https://github.com/puma/puma/issues/165)

**Merged pull requests:**

- Allow configuring pumactl with config.rb, closes \#331 [\#336](https://github.com/puma/puma/pull/336) ([ujifgc](https://github.com/ujifgc))

- Convert thread pool sizes to integers [\#327](https://github.com/puma/puma/pull/327) ([lmarburger](https://github.com/lmarburger))

- Fix --port help text [\#326](https://github.com/puma/puma/pull/326) ([chrismytton](https://github.com/chrismytton))

- Add port to DSL [\#325](https://github.com/puma/puma/pull/325) ([lmarburger](https://github.com/lmarburger))

- CLI help typo [\#324](https://github.com/puma/puma/pull/324) ([lmarburger](https://github.com/lmarburger))

- Small README changes [\#323](https://github.com/puma/puma/pull/323) ([lmarburger](https://github.com/lmarburger))

- Fix Typo In Readme [\#316](https://github.com/puma/puma/pull/316) ([jcbantuelle](https://github.com/jcbantuelle))

- Adds support for using puma config file in capistrano deploys. [\#315](https://github.com/puma/puma/pull/315) ([jakubpawlowicz](https://github.com/jakubpawlowicz))

- Move on\_worker\_boot paragraph in clustered mode. [\#311](https://github.com/puma/puma/pull/311) ([Juanmcuello](https://github.com/Juanmcuello))

## [v2.3.2](https://github.com/puma/puma/tree/v2.3.2) (2013-07-09)

[Full Changelog](https://github.com/puma/puma/compare/v2.3.1...v2.3.2)

**Closed issues:**

- cannot load such file -- puma/single \(LoadError\) [\#310](https://github.com/puma/puma/issues/310)

- Puma 2.3 fails to start [\#308](https://github.com/puma/puma/issues/308)

- puma 2.3 gem is missing files [\#307](https://github.com/puma/puma/issues/307)

## [v2.3.1](https://github.com/puma/puma/tree/v2.3.1) (2013-07-06)

[Full Changelog](https://github.com/puma/puma/compare/v2.3.0...v2.3.1)

**Closed issues:**

- Control Server refuses connection in cluster mode [\#293](https://github.com/puma/puma/issues/293)

- Puma 2.0.1 control server fails to start \(rvm, OpenBSD 5.3\) [\#275](https://github.com/puma/puma/issues/275)

- Error on restart using control server on Windows [\#166](https://github.com/puma/puma/issues/166)

- Socket 'already in use' [\#73](https://github.com/puma/puma/issues/73)

## [v2.3.0](https://github.com/puma/puma/tree/v2.3.0) (2013-07-06)

[Full Changelog](https://github.com/puma/puma/compare/v2.2.2...v2.3.0)

**Closed issues:**

- Content-\* headers are stripped off HEAD response [\#304](https://github.com/puma/puma/issues/304)

- Gemfile not refreshed between deploys [\#300](https://github.com/puma/puma/issues/300)

- undefined method `has\_key?' for false:FalseClass when running pumactl [\#292](https://github.com/puma/puma/issues/292)

- Q: proper setup for use of a Rails app with -w clustered mode [\#289](https://github.com/puma/puma/issues/289)

- Could not start puma process via pumactl with -S [\#287](https://github.com/puma/puma/issues/287)

- H12 errors on Heroku: Puma binding to the port too early? [\#276](https://github.com/puma/puma/issues/276)

- requests failing sometimes [\#274](https://github.com/puma/puma/issues/274)

- Unix Socket Removed Between Hot Restarts [\#266](https://github.com/puma/puma/issues/266)

- New routes are not picked up in cluster mode with USR1 [\#258](https://github.com/puma/puma/issues/258)

- Server\#fast\_write could possibly get into an infinite loop [\#257](https://github.com/puma/puma/issues/257)

- various pumactl errors  [\#255](https://github.com/puma/puma/issues/255)

- Jruby Unable to install puma [\#238](https://github.com/puma/puma/issues/238)

- Readme instructions incorrect for capistrano deployment [\#230](https://github.com/puma/puma/issues/230)

- Feature request: Handling large outgoing requests [\#82](https://github.com/puma/puma/issues/82)

- Feature request: Handling large incoming requests before they are fully received. [\#81](https://github.com/puma/puma/issues/81)

- add support for async.callback api [\#3](https://github.com/puma/puma/issues/3)

- add support for pipelining [\#2](https://github.com/puma/puma/issues/2)

**Merged pull requests:**

- Don't crash when given a non-standard HTTP code [\#305](https://github.com/puma/puma/pull/305) ([darkhelmet](https://github.com/darkhelmet))

- Standardize "block" usage [\#302](https://github.com/puma/puma/pull/302) ([catsby](https://github.com/catsby))

- Document preload options [\#301](https://github.com/puma/puma/pull/301) ([catsby](https://github.com/catsby))

## [v2.2.2](https://github.com/puma/puma/tree/v2.2.2) (2013-07-02)

[Full Changelog](https://github.com/puma/puma/compare/v2.2.1...v2.2.2)

## [v2.2.1](https://github.com/puma/puma/tree/v2.2.1) (2013-07-02)

[Full Changelog](https://github.com/puma/puma/compare/v2.2.0...v2.2.1)

**Merged pull requests:**

- Don't allow CRuby 2.0.0 to fail on Travis [\#299](https://github.com/puma/puma/pull/299) ([jc00ke](https://github.com/jc00ke))

- Introduce --preload [\#298](https://github.com/puma/puma/pull/298) ([jc00ke](https://github.com/jc00ke))

- Add hoe-git [\#297](https://github.com/puma/puma/pull/297) ([jc00ke](https://github.com/jc00ke))

- Loading the rackup file before binding to the port. [\#280](https://github.com/puma/puma/pull/280) ([tevanoff](https://github.com/tevanoff))

## [v2.2.0](https://github.com/puma/puma/tree/v2.2.0) (2013-07-02)

[Full Changelog](https://github.com/puma/puma/compare/v2.1.1...v2.2.0)

**Closed issues:**

- RAILS\_ENV is nil although -e production is used to start puma [\#296](https://github.com/puma/puma/issues/296)

- wicked\_pdf crashes puma when using cluster mode [\#295](https://github.com/puma/puma/issues/295)

- Failed to start server with --control [\#288](https://github.com/puma/puma/issues/288)

- Init Script does not work on RedHat [\#262](https://github.com/puma/puma/issues/262)

- puma should not display exception/backtrace in production [\#256](https://github.com/puma/puma/issues/256)

**Merged pull requests:**

- Update README.md [\#291](https://github.com/puma/puma/pull/291) ([TrevorBramble](https://github.com/TrevorBramble))

- Readme typo [\#290](https://github.com/puma/puma/pull/290) ([perplexes](https://github.com/perplexes))

## [v2.1.1](https://github.com/puma/puma/tree/v2.1.1) (2013-06-20)

[Full Changelog](https://github.com/puma/puma/compare/v2.1.0...v2.1.1)

**Closed issues:**

- Puma treats invalid request bodies as 500 instead of 400 [\#286](https://github.com/puma/puma/issues/286)

- Application load errors are lost when run in daemon mode [\#285](https://github.com/puma/puma/issues/285)

## [v2.1.0](https://github.com/puma/puma/tree/v2.1.0) (2013-06-18)

[Full Changelog](https://github.com/puma/puma/compare/v2.0.1...v2.1.0)

**Closed issues:**

- Exit Timeouts on Heroku caused by stream closed \(IOError\) [\#283](https://github.com/puma/puma/issues/283)

- Puma not killing threads [\#281](https://github.com/puma/puma/issues/281)

- HEAD responses include body [\#278](https://github.com/puma/puma/issues/278)

- Doesn't serve files from directory names that include a dot [\#277](https://github.com/puma/puma/issues/277)

- weird problems with server suddenly failing to start [\#273](https://github.com/puma/puma/issues/273)

- \[Bug\] " kill --SIGUSR2 " restart puma failed randomly [\#270](https://github.com/puma/puma/issues/270)

- -d does not start the puma process  [\#268](https://github.com/puma/puma/issues/268)

- \[FEATURE REQUEST\] Add timeout configuration by request [\#265](https://github.com/puma/puma/issues/265)

- Puma start loop [\#264](https://github.com/puma/puma/issues/264)

- Could you handle signal HUP as reload. [\#263](https://github.com/puma/puma/issues/263)

- Puma does not start in daemon mode on Ruby 1.8 [\#253](https://github.com/puma/puma/issues/253)

- unix sockets consumes too many file descriptors [\#252](https://github.com/puma/puma/issues/252)

- SSL is broken [\#251](https://github.com/puma/puma/issues/251)

- How do I use config? [\#249](https://github.com/puma/puma/issues/249)

- "Bad response from server: 500" on restart during Capistrano puma:restart [\#246](https://github.com/puma/puma/issues/246)

- 1.6.3 tag [\#239](https://github.com/puma/puma/issues/239)

- threads per worker? [\#236](https://github.com/puma/puma/issues/236)

- config/puma.rb [\#233](https://github.com/puma/puma/issues/233)

- ERROR: SSL not supported on JRuby [\#223](https://github.com/puma/puma/issues/223)

- Start App with Https Problem [\#201](https://github.com/puma/puma/issues/201)

- Using workers in configuration causes pumactl stop working due PidEvents missing [\#195](https://github.com/puma/puma/issues/195)

- Capistrano won't complete when starting puma with -d option [\#190](https://github.com/puma/puma/issues/190)

- Redhat Init script [\#178](https://github.com/puma/puma/issues/178)

- \[feature request\] add cwd or config.ru option [\#93](https://github.com/puma/puma/issues/93)

- Listen loop error: \#<IOError: closed stream\> [\#48](https://github.com/puma/puma/issues/48)

- JRuby 1.6.6 + Rails 3.2.1 | Lots of errors? [\#41](https://github.com/puma/puma/issues/41)

- Java thread exception with concurrent requests [\#32](https://github.com/puma/puma/issues/32)

- Rails 2 support [\#12](https://github.com/puma/puma/issues/12)

**Merged pull requests:**

- Allow listening socket to be configured via Capistrano variable [\#282](https://github.com/puma/puma/pull/282) ([bai](https://github.com/bai))

- Output results from 'stat's command when using pumactl [\#279](https://github.com/puma/puma/pull/279) ([ehlertij](https://github.com/ehlertij))

- Fixed some typos in upstart scripts [\#272](https://github.com/puma/puma/pull/272) ([allspiritseve](https://github.com/allspiritseve))

- app\_configured? check should fall back to default rackup file [\#271](https://github.com/puma/puma/pull/271) ([Arie](https://github.com/Arie))

- It is 2013 \[ci skip\] [\#269](https://github.com/puma/puma/pull/269) ([joneslee85](https://github.com/joneslee85))

- Fix an error in puma-manager.conf [\#267](https://github.com/puma/puma/pull/267) ([baruchlubinsky](https://github.com/baruchlubinsky))

- fix: stop leaking sockets on restart \(affects ruby 1.9.3 or before\) [\#259](https://github.com/puma/puma/pull/259) ([sugitak](https://github.com/sugitak))

- Starting point for documenting Clustered mode [\#254](https://github.com/puma/puma/pull/254) ([catsby](https://github.com/catsby))

- Make sure to use bytesize instead of size \(MiniSSL write\) [\#250](https://github.com/puma/puma/pull/250) ([cure](https://github.com/cure))

- fix example config file typo of environment [\#248](https://github.com/puma/puma/pull/248) ([niedhui](https://github.com/niedhui))

- Shorten the gemspec description [\#247](https://github.com/puma/puma/pull/247) ([catsby](https://github.com/catsby))

- History.txt -\> CHANGELOG.md. Reformatted changelog. [\#245](https://github.com/puma/puma/pull/245) ([kugaevsky](https://github.com/kugaevsky))

- Fix running puma under jruby [\#244](https://github.com/puma/puma/pull/244) ([randaalex](https://github.com/randaalex))

- Socket activation [\#231](https://github.com/puma/puma/pull/231) ([urbaniak](https://github.com/urbaniak))

## [v2.0.1](https://github.com/puma/puma/tree/v2.0.1) (2013-04-30)

[Full Changelog](https://github.com/puma/puma/compare/v2.0.0...v2.0.1)

## [v2.0.0](https://github.com/puma/puma/tree/v2.0.0) (2013-04-29)

[Full Changelog](https://github.com/puma/puma/compare/v2.0.0.b7...v2.0.0)

**Closed issues:**

- Fork is not avaliable on JRuby [\#242](https://github.com/puma/puma/issues/242)

- Daemonize option doesn't seem to work [\#235](https://github.com/puma/puma/issues/235)

- 2.0.0.b7 doesn't pick up RACK\_ENV/RAILS\_ENV [\#234](https://github.com/puma/puma/issues/234)

- -d option is said to be invalid and yet --help shows me I can use it [\#232](https://github.com/puma/puma/issues/232)

- Cap recipe does not create sockets folder. [\#228](https://github.com/puma/puma/issues/228)

- java platform gems missing for v2.0.0.b5 and v2.0.0.b6 [\#209](https://github.com/puma/puma/issues/209)

- Benchmark of Unicorn is unreadable [\#68](https://github.com/puma/puma/issues/68)

- Benchmark comparison to thin [\#67](https://github.com/puma/puma/issues/67)

**Merged pull requests:**

- Edit rackup start command on readme.md to rackup -s Puma. [\#243](https://github.com/puma/puma/pull/243) ([hendrauzia](https://github.com/hendrauzia))

- Fix stdout/stderr logs to sync outputs [\#240](https://github.com/puma/puma/pull/240) ([sugitak](https://github.com/sugitak))

- Make cap recipe handle tmp/sockets; fixes \#228 [\#237](https://github.com/puma/puma/pull/237) ([andrewdsmith](https://github.com/andrewdsmith))

- Cache all javascript files with max expiry too [\#229](https://github.com/puma/puma/pull/229) ([josephers](https://github.com/josephers))

- Testing against ruby 2.0 [\#227](https://github.com/puma/puma/pull/227) ([joneslee85](https://github.com/joneslee85))

- allow binding to IPv6 addresses [\#226](https://github.com/puma/puma/pull/226) ([ytti](https://github.com/ytti))

- Minor doc fixes in the README.md, Capistrano section [\#225](https://github.com/puma/puma/pull/225) ([petergoldstein](https://github.com/petergoldstein))

- Fix for the capistrano recipe [\#222](https://github.com/puma/puma/pull/222) ([soylent](https://github.com/soylent))

- Bump to v2.0.0.b7, remove non existing files [\#221](https://github.com/puma/puma/pull/221) ([afeistenauer](https://github.com/afeistenauer))

## [v2.0.0.b7](https://github.com/puma/puma/tree/v2.0.0.b7) (2013-03-19)

[Full Changelog](https://github.com/puma/puma/compare/v2.0.0.b6...v2.0.0.b7)

**Closed issues:**

- EAGAIN exception during `client.syswrite` in `Puma::Server\#fast\_write` [\#213](https://github.com/puma/puma/issues/213)

- Hot restart under JRuby [\#210](https://github.com/puma/puma/issues/210)

- Error in reactor: undefined method `timeout\_at' for nil:NilClass [\#208](https://github.com/puma/puma/issues/208)

- Problem with the HTTP1.1 C-Extension with JRuby under Mac OSX? [\#207](https://github.com/puma/puma/issues/207)

- USR2 signal seems to hang Puma when sent before workers have booted [\#206](https://github.com/puma/puma/issues/206)

- When starting, puma sends responses to wrong requests [\#204](https://github.com/puma/puma/issues/204)

- cannot install 2.0.\* on windows [\#202](https://github.com/puma/puma/issues/202)

- pid in pidfile is not correct when daemonizing [\#199](https://github.com/puma/puma/issues/199)

- Error during failsafe response: cannot load such file -- rails/backtrace\_cleaner [\#198](https://github.com/puma/puma/issues/198)

- worker\_boot procs are serialized in state file [\#196](https://github.com/puma/puma/issues/196)

- Socket file got removed in phased restart process [\#192](https://github.com/puma/puma/issues/192)

- incorrect PID in state file, if running as a daemon [\#189](https://github.com/puma/puma/issues/189)

- clarification: cluster mode & phased restarts failure policy [\#187](https://github.com/puma/puma/issues/187)

- Process does not respond to kill or kill -HUP signal [\#184](https://github.com/puma/puma/issues/184)

- Bad file descriptor \(Errno::EBADF\) server restart crash on ruby 2.0.0preview2 [\#177](https://github.com/puma/puma/issues/177)

- restart under jruby causes crash `Errno::EFAULT: Bad address` [\#154](https://github.com/puma/puma/issues/154)

- Add documentation for Puma config file [\#130](https://github.com/puma/puma/issues/130)

- Asset Pipeline, Heroku and Puma [\#129](https://github.com/puma/puma/issues/129)

**Merged pull requests:**

- Prevent Bad file descriptor \(Errno::EBADF\) Errors on restart when running ruby 2.0  [\#220](https://github.com/puma/puma/pull/220) ([lsylvester](https://github.com/lsylvester))

- add capistrano note into README [\#219](https://github.com/puma/puma/pull/219) ([joneslee85](https://github.com/joneslee85))

- Refactor capistrano [\#218](https://github.com/puma/puma/pull/218) ([joneslee85](https://github.com/joneslee85))

- Refactor capistrano [\#217](https://github.com/puma/puma/pull/217) ([joneslee85](https://github.com/joneslee85))

- Refactor capistrano [\#216](https://github.com/puma/puma/pull/216) ([joneslee85](https://github.com/joneslee85))

- Refactor capistrano [\#215](https://github.com/puma/puma/pull/215) ([joneslee85](https://github.com/joneslee85))

- Retry EAGAIN/EWOULDBLOCK during syswrite [\#214](https://github.com/puma/puma/pull/214) ([nixme](https://github.com/nixme))

- Upstart support [\#212](https://github.com/puma/puma/pull/212) ([dariocravero](https://github.com/dariocravero))

- Set Rack run\_once to false [\#211](https://github.com/puma/puma/pull/211) ([kazjote](https://github.com/kazjote))

- Add documentation for puma config file. [\#205](https://github.com/puma/puma/pull/205) ([mkempe](https://github.com/mkempe))

- fix daemonize [\#203](https://github.com/puma/puma/pull/203) ([EvilFaeton](https://github.com/EvilFaeton))

- Respect the header HTTP\_X\_FORWARDED\_PROTO. [\#200](https://github.com/puma/puma/pull/200) ([calavera](https://github.com/calavera))

- Default Rack handler helper [\#194](https://github.com/puma/puma/pull/194) ([nevir](https://github.com/nevir))

- set worker directory from configuration file [\#191](https://github.com/puma/puma/pull/191) ([EvilFaeton](https://github.com/EvilFaeton))

- prevent crash when all workers are gone [\#188](https://github.com/puma/puma/pull/188) ([Wijnand](https://github.com/Wijnand))

- Add Capistrano deploy note [\#175](https://github.com/puma/puma/pull/175) ([huacnlee](https://github.com/huacnlee))

## [v2.0.0.b6](https://github.com/puma/puma/tree/v2.0.0.b6) (2013-02-07)

[Full Changelog](https://github.com/puma/puma/compare/v2.0.0.b5...v2.0.0.b6)

**Closed issues:**

- phased restart not loading new code? [\#185](https://github.com/puma/puma/issues/185)

- Feature request: Websocket support [\#83](https://github.com/puma/puma/issues/83)

**Merged pull requests:**

- Spelling error in log [\#186](https://github.com/puma/puma/pull/186) ([bensie](https://github.com/bensie))

## [v2.0.0.b5](https://github.com/puma/puma/tree/v2.0.0.b5) (2013-02-06)

[Full Changelog](https://github.com/puma/puma/compare/v2.0.0.b4...v2.0.0.b5)

**Closed issues:**

- Rufus Scheduler doesn't run with daemonized puma 2.0.0.b4 [\#183](https://github.com/puma/puma/issues/183)

- Leaking pipe handles on SIGUSR2 [\#182](https://github.com/puma/puma/issues/182)

- Development configuration with config.cache\_class=false causes trap. [\#181](https://github.com/puma/puma/issues/181)

- Wrong PID at puma.state when daemonizing [\#180](https://github.com/puma/puma/issues/180)

- puma cluster 100% cpu usage [\#176](https://github.com/puma/puma/issues/176)

- Error \(closed stream\) [\#173](https://github.com/puma/puma/issues/173)

- \[feature request\] Add log output option [\#92](https://github.com/puma/puma/issues/92)

**Merged pull requests:**

- Correctly specify JRuby on Travis [\#174](https://github.com/puma/puma/pull/174) ([jc00ke](https://github.com/jc00ke))

## [v2.0.0.b4](https://github.com/puma/puma/tree/v2.0.0.b4) (2012-12-13)

[Full Changelog](https://github.com/puma/puma/compare/v2.0.0.b3...v2.0.0.b4)

**Closed issues:**

- Zero-Downtime deployments /w Cluster Mode [\#171](https://github.com/puma/puma/issues/171)

- Clients starved for large requests [\#170](https://github.com/puma/puma/issues/170)

- MiniSSL::Context and invalid SSL file paths [\#168](https://github.com/puma/puma/issues/168)

- Feature request: Start automatically with `rails server`, like Thin [\#167](https://github.com/puma/puma/issues/167)

**Merged pull requests:**

- Fix for: MiniSSL::Context and invalid SSL file paths [\#172](https://github.com/puma/puma/pull/172) ([rubiii](https://github.com/rubiii))

- Specify rbx modes for Travis [\#169](https://github.com/puma/puma/pull/169) ([jc00ke](https://github.com/jc00ke))

- Update travis.yml to use the proper rbx build names [\#163](https://github.com/puma/puma/pull/163) ([frodsan](https://github.com/frodsan))

## [v2.0.0.b3](https://github.com/puma/puma/tree/v2.0.0.b3) (2012-11-22)

[Full Changelog](https://github.com/puma/puma/compare/v2.0.0.b2...v2.0.0.b3)

**Closed issues:**

- puma command is not working on 2.0.0.b2 [\#164](https://github.com/puma/puma/issues/164)

- cannot load such file -- puma/capistrano \(LoadError\) [\#161](https://github.com/puma/puma/issues/161)

**Merged pull requests:**

- update Manifest.txt, Fixes \#161  [\#162](https://github.com/puma/puma/pull/162) ([jinzhu](https://github.com/jinzhu))

## [v2.0.0.b2](https://github.com/puma/puma/tree/v2.0.0.b2) (2012-11-19)

[Full Changelog](https://github.com/puma/puma/compare/v1.6.2...v2.0.0.b2)

**Closed issues:**

- There is no way to change the default request timeout... [\#160](https://github.com/puma/puma/issues/160)

- puma and capistrano [\#156](https://github.com/puma/puma/issues/156)

- Hot deploys are not so hot [\#155](https://github.com/puma/puma/issues/155)

- Unexpected Connection Pooling [\#152](https://github.com/puma/puma/issues/152)

- headers\['Transfer-Encoding'\] = 'chunked' -- makes server fail [\#150](https://github.com/puma/puma/issues/150)

- puma environment in production server [\#149](https://github.com/puma/puma/issues/149)

- 2.0.0b1 showing request headers [\#148](https://github.com/puma/puma/issues/148)

- Pumactl restart crashes trying to run JRuby shell script as Ruby code [\#147](https://github.com/puma/puma/issues/147)

- server freese after restart by SIGUSR2 [\#144](https://github.com/puma/puma/issues/144)

- Parse error not returning error 400 [\#142](https://github.com/puma/puma/issues/142)

- pumactl and config [\#140](https://github.com/puma/puma/issues/140)

- Hanging requests [\#139](https://github.com/puma/puma/issues/139)

- Running sinatra from puma's cli [\#137](https://github.com/puma/puma/issues/137)

- New Relic support [\#128](https://github.com/puma/puma/issues/128)

- Reactor changes in 1.6 seems to break SSL servers [\#127](https://github.com/puma/puma/issues/127)

- How to integrate Puma with Apache [\#125](https://github.com/puma/puma/issues/125)

- Url Params get ignored  [\#119](https://github.com/puma/puma/issues/119)

- error on request in jruby. java extension doesn't compile with bundler & jruby? [\#42](https://github.com/puma/puma/issues/42)

**Merged pull requests:**

- Get puma env from rack\_env or rails\_env in capistrano recipe [\#159](https://github.com/puma/puma/pull/159) ([jinzhu](https://github.com/jinzhu))

- gem build doesn't depend on Gemfile.lock [\#158](https://github.com/puma/puma/pull/158) ([ktheory](https://github.com/ktheory))

- capistrano recipe [\#157](https://github.com/puma/puma/pull/157) ([plentz](https://github.com/plentz))

- Allow for alternate locations in status app [\#153](https://github.com/puma/puma/pull/153) ([kidpollo](https://github.com/kidpollo))

- fixed jruby\_restart.rb for use with bundler [\#151](https://github.com/puma/puma/pull/151) ([nickbarth](https://github.com/nickbarth))

- Added nginx config sample [\#146](https://github.com/puma/puma/pull/146) ([dariocravero](https://github.com/dariocravero))

- improve pumactl  [\#145](https://github.com/puma/puma/pull/145) ([jpascal](https://github.com/jpascal))

- fixes and pumactl was refactored [\#143](https://github.com/puma/puma/pull/143) ([jpascal](https://github.com/jpascal))

## [v1.6.2](https://github.com/puma/puma/tree/v1.6.2) (2012-08-27)

[Full Changelog](https://github.com/puma/puma/compare/v1.5.0...v1.6.2)

**Closed issues:**

- 1.6 unexpected connection closing [\#138](https://github.com/puma/puma/issues/138)

- Puma terminates on SIGUSR2 \(instead of restarting\) [\#136](https://github.com/puma/puma/issues/136)

- cannot load such file -- puma/detect [\#135](https://github.com/puma/puma/issues/135)

- Can't start 1.6.0 with jruby [\#134](https://github.com/puma/puma/issues/134)

- Hot restart clarification [\#126](https://github.com/puma/puma/issues/126)

- errors with jruby 1.6.7 -1.9 [\#100](https://github.com/puma/puma/issues/100)

- Loading Incorrect Images [\#57](https://github.com/puma/puma/issues/57)

**Merged pull requests:**

- Move singleton method to MiniSSL.java [\#141](https://github.com/puma/puma/pull/141) ([jingweno](https://github.com/jingweno))

- Update README.md [\#133](https://github.com/puma/puma/pull/133) ([dariocravero](https://github.com/dariocravero))

- updated IOBuffer impl to use native Java ByteArrayOutputStream; added test [\#132](https://github.com/puma/puma/pull/132) ([ahamid](https://github.com/ahamid))

- Init script [\#131](https://github.com/puma/puma/pull/131) ([dariocravero](https://github.com/dariocravero))

## [v1.5.0](https://github.com/puma/puma/tree/v1.5.0) (2012-07-19)

[Full Changelog](https://github.com/puma/puma/compare/v1.4.0...v1.5.0)

**Closed issues:**

- Enable SSL V2 Context [\#113](https://github.com/puma/puma/issues/113)

- Compiliation fails on Debain wheezy [\#109](https://github.com/puma/puma/issues/109)

- Unable to bind to a UNIX socket with java.nio.channels.IllegalSelectorException [\#107](https://github.com/puma/puma/issues/107)

- the pid file is not deleted when the server stops [\#75](https://github.com/puma/puma/issues/75)

**Merged pull requests:**

- Delete pidfile when the server stops  [\#124](https://github.com/puma/puma/pull/124) ([spastorino](https://github.com/spastorino))

- Cast status to Integer before comparison [\#123](https://github.com/puma/puma/pull/123) ([jcoene](https://github.com/jcoene))

- Allow compilation with -Werror=format-security option [\#122](https://github.com/puma/puma/pull/122) ([tjouan](https://github.com/tjouan))

- Use String\#bytesize instead of String\#length [\#121](https://github.com/puma/puma/pull/121) ([tomykaira](https://github.com/tomykaira))

- Fix wrong HTTP version for a HTTP/1.0 request [\#120](https://github.com/puma/puma/pull/120) ([tomykaira](https://github.com/tomykaira))

- Added support for setting RACK\_ENV through the CLI and the config file. [\#118](https://github.com/puma/puma/pull/118) ([dariocravero](https://github.com/dariocravero))

- Add missing localvars. Accessing localvars is faster than accessing ivars [\#117](https://github.com/puma/puma/pull/117) ([spastorino](https://github.com/spastorino))

- Do not execute @app.call twice in the tests [\#116](https://github.com/puma/puma/pull/116) ([spastorino](https://github.com/spastorino))

- Delegate cli log and error to events [\#115](https://github.com/puma/puma/pull/115) ([spastorino](https://github.com/spastorino))

- Remove unused code [\#114](https://github.com/puma/puma/pull/114) ([spastorino](https://github.com/spastorino))

- Avoid executing @app.call twice in the tests + Remove unneeded code [\#112](https://github.com/puma/puma/pull/112) ([spastorino](https://github.com/spastorino))

- Unobtrusively modify Server\#run to optionally execute in Thread\#current. [\#111](https://github.com/puma/puma/pull/111) ([kenkeiter](https://github.com/kenkeiter))

- Allow Server\#run to be optionally executed in the current thread \(enabling custom threading\). [\#110](https://github.com/puma/puma/pull/110) ([kenkeiter](https://github.com/kenkeiter))

- Win error [\#108](https://github.com/puma/puma/pull/108) ([gpad](https://github.com/gpad))

- Add RSTRING\_NOT\_MODIFIED for Rubinius [\#106](https://github.com/puma/puma/pull/106) ([dbussink](https://github.com/dbussink))

- Updated start command for rails [\#105](https://github.com/puma/puma/pull/105) ([mifix](https://github.com/mifix))

## [v1.4.0](https://github.com/puma/puma/tree/v1.4.0) (2012-06-04)

[Full Changelog](https://github.com/puma/puma/compare/v1.3.1...v1.4.0)

**Merged pull requests:**

- SCRIPT\_NAME should be passed from env to allow mounting apps [\#104](https://github.com/puma/puma/pull/104) ([pzol](https://github.com/pzol))

- Detect and handle unix:// scheme in rack handler [\#103](https://github.com/puma/puma/pull/103) ([ender672](https://github.com/ender672))

- Add command line -d switch \(daemonize\). [\#102](https://github.com/puma/puma/pull/102) ([ghost](https://github.com/ghost))

- Typo fixed. [\#101](https://github.com/puma/puma/pull/101) ([Antiarchitect](https://github.com/Antiarchitect))

- Fix typo. [\#99](https://github.com/puma/puma/pull/99) ([mikegehard](https://github.com/mikegehard))

## [v1.3.1](https://github.com/puma/puma/tree/v1.3.1) (2012-05-16)

[Full Changelog](https://github.com/puma/puma/compare/v1.3.0...v1.3.1)

**Closed issues:**

- keep-alive logic can result in hanging requests [\#95](https://github.com/puma/puma/issues/95)

**Merged pull requests:**

- Write body to stream when not using a TempFile [\#98](https://github.com/puma/puma/pull/98) ([Flink](https://github.com/Flink))

- Remove NullIO\#close, method is not used. [\#97](https://github.com/puma/puma/pull/97) ([rkh](https://github.com/rkh))

- use \#bytesize instead of \#length for Content-Length header [\#96](https://github.com/puma/puma/pull/96) ([rkh](https://github.com/rkh))

## [v1.3.0](https://github.com/puma/puma/tree/v1.3.0) (2012-05-08)

[Full Changelog](https://github.com/puma/puma/compare/v1.2.2...v1.3.0)

**Closed issues:**

- Ruby Interpreter Hangs on SIGTERM [\#94](https://github.com/puma/puma/issues/94)

- Can't install via :git in Gemfile [\#87](https://github.com/puma/puma/issues/87)

- Doc request on compiling ragel ext [\#86](https://github.com/puma/puma/issues/86)

- Error on restart [\#84](https://github.com/puma/puma/issues/84)

- RACK\_ENV not defaulted to 'development' until after config.ru loads [\#78](https://github.com/puma/puma/issues/78)

- apache? [\#76](https://github.com/puma/puma/issues/76)

- Provide an option to daemonize and better restart [\#74](https://github.com/puma/puma/issues/74)

**Merged pull requests:**

- Add -I option to specify $LOAD\_PATH directories [\#91](https://github.com/puma/puma/pull/91) ([ender672](https://github.com/ender672))

- Make NullIO\#read mimic IO\#read [\#90](https://github.com/puma/puma/pull/90) ([dstrelau](https://github.com/dstrelau))

- Fix gemspec [\#89](https://github.com/puma/puma/pull/89) ([jc00ke](https://github.com/jc00ke))

- Ignore Gemfile.lock [\#88](https://github.com/puma/puma/pull/88) ([jc00ke](https://github.com/jc00ke))

- Return valid Rack responses [\#85](https://github.com/puma/puma/pull/85) ([jc00ke](https://github.com/jc00ke))

- deamonize puma for ruby \>= 1.9 [\#77](https://github.com/puma/puma/pull/77) ([mustafaturan](https://github.com/mustafaturan))

## [v1.2.2](https://github.com/puma/puma/tree/v1.2.2) (2012-04-28)

[Full Changelog](https://github.com/puma/puma/compare/v1.2.1...v1.2.2)

**Closed issues:**

- Exception in response [\#79](https://github.com/puma/puma/issues/79)

- "cannot load such file -- rack/handler/puma" unless launching Puma directly [\#71](https://github.com/puma/puma/issues/71)

- start and stop puma like daemon [\#70](https://github.com/puma/puma/issues/70)

**Merged pull requests:**

- Use status codes from rack. [\#72](https://github.com/puma/puma/pull/72) ([ender672](https://github.com/ender672))

- show error.to\_s along with backtrace for low-level error [\#69](https://github.com/puma/puma/pull/69) ([bporterfield](https://github.com/bporterfield))

- Extract two methods [\#66](https://github.com/puma/puma/pull/66) ([paneq](https://github.com/paneq))

## [v1.2.1](https://github.com/puma/puma/tree/v1.2.1) (2012-04-11)

[Full Changelog](https://github.com/puma/puma/compare/v1.2.0...v1.2.1)

**Closed issues:**

- Rack::Request.scheme should return https if running SSLServer [\#65](https://github.com/puma/puma/issues/65)

## [v1.2.0](https://github.com/puma/puma/tree/v1.2.0) (2012-04-11)

[Full Changelog](https://github.com/puma/puma/compare/v1.1.1...v1.2.0)

**Closed issues:**

- Won't work with Rails 3.0.x because of Rack 1.2.x bug [\#63](https://github.com/puma/puma/issues/63)

- Code Reloading [\#61](https://github.com/puma/puma/issues/61)

- Use REUSEADDR when starting tcp server [\#60](https://github.com/puma/puma/issues/60)

- "Deprecation warning: Database connections will not be closed automatically" [\#59](https://github.com/puma/puma/issues/59)

- How I can launch a rails app in production mode? [\#56](https://github.com/puma/puma/issues/56)

- wrong number of arguments \(4 for 3\) [\#54](https://github.com/puma/puma/issues/54)

- Updated History.txt [\#52](https://github.com/puma/puma/issues/52)

- cannot load such file -- puma/compat [\#51](https://github.com/puma/puma/issues/51)

**Merged pull requests:**

- More helpful fallback error message [\#64](https://github.com/puma/puma/pull/64) ([seamusabshere](https://github.com/seamusabshere))

- Use nil instead of empty strings when initializing proto env hash [\#62](https://github.com/puma/puma/pull/62) ([seamusabshere](https://github.com/seamusabshere))

- Fixed number of arguments in Puma::Events\#unknown\_error [\#58](https://github.com/puma/puma/pull/58) ([paneq](https://github.com/paneq))

- Add Travis build and Gemnasium dependency status images to the README [\#55](https://github.com/puma/puma/pull/55) ([laserlemon](https://github.com/laserlemon))

- Detach server process from terminal [\#53](https://github.com/puma/puma/pull/53) ([sxua](https://github.com/sxua))

## [v1.1.1](https://github.com/puma/puma/tree/v1.1.1) (2012-03-31)

[Full Changelog](https://github.com/puma/puma/compare/v1.1.0...v1.1.1)

## [v1.1.0](https://github.com/puma/puma/tree/v1.1.0) (2012-03-30)

[Full Changelog](https://github.com/puma/puma/compare/v1.0.0...v1.1.0)

**Closed issues:**

- load error: puma/puma\_http11 -- java.lang.UnsatisfiedLinkError [\#50](https://github.com/puma/puma/issues/50)

- Build error with JRuby 1.6.7 and XCode 4.3 [\#49](https://github.com/puma/puma/issues/49)

- Can't use sockets with rails [\#44](https://github.com/puma/puma/issues/44)

## [v1.0.0](https://github.com/puma/puma/tree/v1.0.0) (2012-03-29)

**Closed issues:**

- Large bodies without content-length header [\#45](https://github.com/puma/puma/issues/45)

- Trimming in thread pool can result in requests hanging [\#38](https://github.com/puma/puma/issues/38)

- uninitialized constant Rubinius::FROM\_AGENT \(NameError\) [\#37](https://github.com/puma/puma/issues/37)

- Rails 3.1.3 - JRuby 1.6.5.1 - Sun Java 7: Does Not Respond To Requests [\#36](https://github.com/puma/puma/issues/36)

- Odd error on shutdown on JRuby [\#35](https://github.com/puma/puma/issues/35)

- Default RACK\_ENV to 'development' [\#29](https://github.com/puma/puma/issues/29)

- Add support for ssl cert [\#28](https://github.com/puma/puma/issues/28)

- HTTP Parse Error [\#27](https://github.com/puma/puma/issues/27)

- Ruby Implementations? [\#25](https://github.com/puma/puma/issues/25)

- Add -p and --port flag [\#24](https://github.com/puma/puma/issues/24)

- all requests on a single thread [\#23](https://github.com/puma/puma/issues/23)

- all Sinatra routes are accessed twice [\#22](https://github.com/puma/puma/issues/22)

- PIDFile Support [\#18](https://github.com/puma/puma/issues/18)

- ActiveRecord let's threads starve [\#17](https://github.com/puma/puma/issues/17)

- cannot install puma into rbx [\#16](https://github.com/puma/puma/issues/16)

- Rails 1 support [\#15](https://github.com/puma/puma/issues/15)

- Merb support [\#14](https://github.com/puma/puma/issues/14)

- Sinatra support [\#13](https://github.com/puma/puma/issues/13)

- allow using a unix socket [\#5](https://github.com/puma/puma/issues/5)

- add gemspec to git repo [\#4](https://github.com/puma/puma/issues/4)

- add support for persistent HTTP connections [\#1](https://github.com/puma/puma/issues/1)

**Merged pull requests:**

- Add interruption support to Rack Handler [\#47](https://github.com/puma/puma/pull/47) ([stereobooster](https://github.com/stereobooster))

- Fix typo [\#46](https://github.com/puma/puma/pull/46) ([jc00ke](https://github.com/jc00ke))



\* *This Change Log was automatically generated by [github_changelog_generator](https://github.com/skywinder/Github-Changelog-Generator)*