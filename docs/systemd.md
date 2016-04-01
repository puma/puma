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
# ExecStart=<WorkingDirectory>/sbin/puma -C config.rb

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

# Socket options matching what Puma wants
NoDelay=true
ReusePort=true

[Install]
WantedBy=sockets.target
~~~~

See [systemd.socket](https://www.freedesktop.org/software/systemd/man/systemd.socket.html)
for additional details.
