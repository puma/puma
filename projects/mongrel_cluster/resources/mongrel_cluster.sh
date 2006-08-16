#!/bin/sh
#
# PROVIDE: mongrel_cluster
# REQUIRE: DAEMON
# KEYWORD: shutdown
#
# Author: Andrew Bennett, potatosaladx@gmail.com
#
# Add the following line to /etc/rc.conf to enable 'mongrel_cluster':
#
#   mongrel_cluster_enable="YES"
#   # optional
#   mongrel_cluster_config="/usr/local/etc/mongrel_cluster"

. "/etc/rc.subr"

# Set some defaults
mongrel_cluster_enable=${mongrel_cluster_enable:-"NO"}
mongrel_cluster_config=${mongrel_cluster_config:-"/usr/local/etc/mongrel_cluster"}

name="mongrel_cluster"
rcvar=`set_rcvar`

load_rc_config $name
: ${mongrel_cluster_enable="NO"}

command=/usr/local/bin/mongrel_cluster_ctl
command_args="$1 -c ${mongrel_cluster_config}"
restart_cmd="restart_cmd"
start_cmd="start_cmd"
stop_cmd="stop_cmd"

restart_cmd()
{
    eval "${command} restart -c ${mongrel_cluster_config}"
}

start_cmd()
{
    eval "${command} start -c ${mongrel_cluster_config}"
}

stop_cmd()
{
    eval "${command} stop -c ${mongrel_cluster_config}"
}

run_rc_command "$1"
