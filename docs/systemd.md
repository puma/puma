# systemd

[systemd](https://www.freedesktop.org/wiki/Software/systemd/) is a
commonly available init system (PID 1) on many Linux distributions. It
offers process monitoring (including automatic restarts) and other
useful features for running Puma in production. Below is a sample
puma.service configuration file for systemd:

~~~~
[Unit]
Description=Puma HTTP Server
After=network.target

# Uncomment for socket activation (see below)
# Requires=puma.socket

[Service]
# Foreground process (do not use --daemon in ExecStart or config.rb)
Type=simple

# Preferably configure a non-privileged user
# User=

# Specify the path to your puma application root
# WorkingDirectory=

# Helpful for debugging socket activation, etc.
# Environment=PUMA_DEBUG=1

# The command to start Puma
# Here we are using a binstub generated via:
# `bundle binstubs puma --path ./sbin`
# in the WorkingDirectory (replace <WD> below)
# You can alternatively use `bundle exec --keep-file-descriptors puma`
# ExecStart=<WD>/sbin/puma -b tcp://0.0.0.0:9292 -b ssl://0.0.0.0:9293?key=key.pem&cert=cert.pem

# Alternatively with a config file (in WorkingDirectory) and
# comparable `bind` directives
# ExecStart=<WD>/sbin/puma -C config.rb

Restart=always

[Install]
WantedBy=multi-user.target
~~~~

See [systemd.exec](https://www.freedesktop.org/software/systemd/man/systemd.exec.html)
for additional details.

## Socket Activation

systemd and puma also support socket activation, where systemd opens
the listening socket(s) in advance and provides them to the puma master
process on startup. Among other advantages, this keeps listening
sockets open across puma restarts and achieves graceful restarts. To
use socket activation, configure one or more `ListenStream`
sockets in a companion `*.socket` systemd config file. Here is a sample
puma.socket, matching the ports used in the above puma.service:

~~~~
[Unit]
Description=Puma HTTP Server Accept Sockets

[Socket]
ListenStream=0.0.0.0:9292
ListenStream=0.0.0.0:9293

# AF_UNIX domain socket
# SocketUser, SocketGroup, etc. may be needed for Unix domain sockets
# ListenStream=/run/puma.sock

# Socket options matching Puma defaults
NoDelay=true
ReusePort=true
Backlog=1024

[Install]
WantedBy=sockets.target
~~~~

See [systemd.socket](https://www.freedesktop.org/software/systemd/man/systemd.socket.html)
for additional configuration details.

Note that the above configurations will work with Puma in either
single process or cluster mode.

## Usage

Without socket activation, use `systemctl` as root (e.g. via `sudo`) as
with other system services:

~~~~ sh
# After installing or making changes to puma.service
systemctl daemon-reload

# Enable so it starts on boot
systemctl enable puma.service

# Initial start up.
systemctl start puma.service

# Check status
systemctl status puma.service

# A normal restart. Warning: listeners sockets will be closed
# while a new puma process initializes.
systemctl restart puma.service
~~~~

With socket activation, several but not all of these commands should
be run for both socket and service:

~~~~ sh
# After installing or making changes to either puma.socket or
# puma.service.
systemctl daemon-reload

# Enable both socket and service so they start on boot.  Alternatively
# you could leave puma.service disabled and systemd will start it on
# first use (with startup lag on first request)
systemctl enable puma.socket puma.service

# Initial start up. The Requires directive (see above) ensures the
# socket is started before the service.
systemctl start puma.socket puma.service

# Check status of both socket and service.
systemctl status puma.socket puma.service

# A "hot" restart, with systemd keeping puma.socket listening and
# providing to the new puma (master) instance.
systemctl restart puma.service

# A normal restart, needed to handle changes to
# puma.socket, such as changing the ListenStream ports. Note
# daemon-reload (above) should be run first.
systemctl restart puma.socket puma.service
~~~~

Here is sample output from `systemctl status` with both service and
socket running:

~~~~
● puma.socket - Puma HTTP Server Accept Sockets
   Loaded: loaded (/etc/systemd/system/puma.socket; enabled; vendor preset: enabled)
   Active: active (running) since Thu 2016-04-07 08:40:19 PDT; 1h 2min ago
   Listen: 0.0.0.0:9233 (Stream)
           0.0.0.0:9234 (Stream)

Apr 07 08:40:19 hx systemd[874]: Listening on Puma HTTP Server Accept Sockets.

● puma.service - Puma HTTP Server
   Loaded: loaded (/etc/systemd/system/puma.service; enabled; vendor preset: enabled)
   Active: active (running) since Thu 2016-04-07 08:40:19 PDT; 1h 2min ago
 Main PID: 28320 (ruby)
   CGroup: /system.slice/puma.service
           ├─28320 puma 3.3.0 (tcp://0.0.0.0:9233,ssl://0.0.0.0:9234?key=key.pem&cert=cert.pem) [app]
           ├─28323 puma: cluster worker 0: 28320 [app]
           └─28327 puma: cluster worker 1: 28320 [app]

Apr 07 08:40:19 hx puma[28320]: Puma starting in cluster mode...
Apr 07 08:40:19 hx puma[28320]: * Version 3.3.0 (ruby 2.2.4-p230), codename: Jovial Platypus
Apr 07 08:40:19 hx puma[28320]: * Min threads: 0, max threads: 16
Apr 07 08:40:19 hx puma[28320]: * Environment: production
Apr 07 08:40:19 hx puma[28320]: * Process workers: 2
Apr 07 08:40:19 hx puma[28320]: * Phased restart available
Apr 07 08:40:19 hx puma[28320]: * Activated tcp://0.0.0.0:9233
Apr 07 08:40:19 hx puma[28320]: * Activated ssl://0.0.0.0:9234?key=key.pem&cert=cert.pem
Apr 07 08:40:19 hx puma[28320]: Use Ctrl-C to stop
~~~~

## Alternative background process configuration

If Capistrano and [capistrano3-puma](https://github.com/seuros/capistrano-puma) tasks are used you can use the following configuration. In this case, you would skip systemd Socket Activation, since Puma handles the socket by itself.

First (as root, indicated by commands being prefixed with `#`), create a `puma.service`
```
# cd /etc/systemd/system
# touch puma.service
# chmod 664 puma.service
```

then pull that into an editor and insert the following setup. Then replace `<WD>` and do the dry-runs it suggests.

~~~~
Unit]
Description=Puma Rails Application/HTTP Server
After=network.target

# Preferably configure a non-privileged user (e.g. "deploy" if that's the user that owns the app and under which you want to run Puma)
User=deploy

# Specify the path to your puma application root
WorkingDirectory=<WD>/current

[Service]
# Background process configuration (use with --daemon in ExecStart)
Type=forking

# To learn which exact command is to be used to execute at "ExecStart" of this
# Service, ask Capistrano: `cap <stage> puma:start --dry-run`. Your result
# may differ from this example, for example if you use a Ruby version
# manager. `<WD>` is short for "your working directory". Replace it with your
# path.
ExecStart=bundle exec puma -C <WD>/shared/puma.rb --daemon

# To learn which exact command is to be used to execute at "ExecStop" of this
# Service, ask Capistrano: `cap <stage> puma:stop --dry-run`. Your result
# may differ from this example, for example if you use a Ruby version
# manager. `<WD>` is short for "your working directory". Replace it with your
# path.
ExecStop=bundle exec pumactl -S <WD>/shared/tmp/pids/puma.state stop

# PIDFile setting is required in order to work properly
PIDFile=<WD>/shared/tmp/pids/puma.pid

Restart=always

[Install]
WantedBy=multi-user.target
~~~~

Then manually stop Puma (on your local machine, being indicated with the prompt `local$`)
```
local$ cap production puma:stop
```

and confirm it's not running
```
# ps aux | grep puma
```

Then reload systemd and start the service
```
# systemctl daemon-reload
# systemctl start puma.service
```

if it all looks good,
```
# systemctl status puma.service
# journalctl -u puma.service -f
```
NOTE: You may see an error like:
```
puma.service: PID file /home/deploy/apps/blog/shared/tmp/pids/puma.pid not readable (yet?) after start: No such file or directory
```
I think this is something systemd does if you have a PID file in a non-standard directory (e.g. not in "/var/run/XXXX.pid"), but it doesn't seem to cause any problems.
https://bbs.archlinux.org/viewtopic.php?pid=1350386#p1350386

then enable it for auto-restart
```
# systemctl enable puma.service
```

and do a reboot
```
# reboot
```
and verify it comes back up.

and kill the process (as your non-privileged user, indicated by `$` preceding the commands)
```
$ ps aux | grep puma
$ kill [pid of puma]
```

and look at the logs to ensure it restarted
```
# journalctl -u puma.service -f
```

### Starting/stopping puma
Since systemd is now managing (and auto-restarting) puma, you can't use the `cap production puma:XYZ` tasks for cleanly starting and stopping it (they'll sort of work, but systemd will just restart things and you'll see backtraces and errors in the journalctl and).

You need to
```
$ sudo systemctl stop puma.service
$ sudo systemctl restart puma.service
etc
```
