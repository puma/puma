# Deployment engineering for Puma

Puma is software that is expected to be run in a deployed environment eventually.
You can certainly use it as your dev server only, but most people look to use
it in their production deployments as well.

To that end, this is meant to serve as a foundation of wisdom how to do that
in a way that increases happiness and decreases downtime.

## Specifying Puma

Most people want to do this by putting `gem "puma"` into their Gemfile, so we'll
go ahead and assume that. Go add it now... we'll wait.

Welcome back!

## Single vs Cluster mode

Puma was originally conceived as a thread-only web server, but grew the ability to
also use processes in version 2.

To run `puma` in single mode (e.g. for a development environment) you will need to
set the number of workers to 0, anything above will run in cluster mode.

Here are some rules of thumb for cluster mode:

### MRI

* Use cluster mode and set the number of workers to 1.5x the number of cpu cores
  in the machine, minimum 2.
* Set the number of threads to desired concurrent requests / number of workers.
  Puma defaults to 5 and that's a decent number.

#### Migrating from Unicorn

* If you're migrating from unicorn though, here are some settings to start with:
  * Set workers to half the number of unicorn workers you're using
  * Set threads to 2
  * Enjoy 50% memory savings
* As you grow more confident in the thread safety of your app, you can tune the
  workers down and the threads up.

#### Ubuntu / Systemd (Systemctl) Installation

See [systemd.md](systemd.md)

#### Worker utilization

**How do you know if you've got enough (or too many workers)?**

A good question. Due to MRI's GIL, only one thread can be executing Ruby code at a time.
But since so many apps are waiting on IO from DBs, etc., they can utilize threads
to make better use of the process.

The rule of thumb is you never want processes that are pegged all the time. This
means that there is more work to do than the process can get through. On the other
hand, if you have processes that sit around doing nothing, then they're just eating
up resources.

Watch your CPU utilization over time and aim for about 70% on average. This means
you've got capacity still but aren't starving threads.

**Measuring utilization**

Using a timestamp header from an upstream proxy server (eg. nginx or haproxy), it's
possible to get an indication of how long requests have been waiting for a Puma
thread to become available.

* Have your upstream proxy set a header with the time it received the request:
    * nginx: `proxy_set_header X-Request-Start "${msec}";`
    * haproxy >= 1.9: `http-request set-header X-Request-Start t=%[date()]%[date_us()]`
    * haproxy < 1.9: `http-request set-header X-Request-Start t=%[date()]`
* In your Rack middleware, determine the amount of time elapsed since `X-Request-Start`.
* To improve accuracy, you will want to subtract time spent waiting for slow clients:
    * `env['puma.request_body_wait']` contains the number of milliseconds Puma spent
      waiting for the client to send the request body.
    * haproxy: `%Th` (TLS handshake time) and `%Ti` (idle time before request) can
      can also be added as headers.

## Should I daemonize?

Daemonization was removed in Puma 5.0. For alternatives, continue reading.

I prefer to not daemonize my servers and use something like `runit` or `systemd` to
monitor them as child processes. This gives them fast response to crashes and
makes it easy to figure out what is going on. Additionally, unlike `unicorn`,
puma does not require daemonization to do zero-downtime restarts.

I see people using daemonization because they start puma directly via capistrano
task and thus want it to live on past the `cap deploy`. To these people I say:
You need to be using a process monitor. Nothing is making sure puma stays up in
this scenario! You're just waiting for something weird to happen, puma to die,
and to get paged at 3am. Do yourself a favor, at least the process monitoring
your OS comes with, be it `sysvinit` or `systemd`. Or branch out
and use `runit` or hell, even `monit`.

## Restarting

You probably will want to deploy some new code at some point, and you'd like
puma to start running that new code. There are a few options for restarting
puma, described separately in our [restart documentation](restart.md).
