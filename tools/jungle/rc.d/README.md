# Puma as a service using rc.d

Manage one (currently) Puma server as a service on one box using FreeBSD's rc.d service.

## Installation

    # Copy the puma script to the rc.d directory (make sure everyone has read/execute perms)
    sudo cp puma /usr/local/etc/rc.d/

    # Create an empty configuration file
    sudo touch /usr/local/etc/puma.conf

    # Enable the puma service
    sudo echo 'puma_enable="YES"' >> /etc/rc.conf

## Managing the jungle

Puma apps are referenced in /usr/local/etc/puma.conf by default.

Start the jungle running:

`service puma start`

This script will run at boot time.

## Conventions

* The script expects:
  * a config file to exist under `config/puma.rb` in your app. E.g.: `/home/apps/my-app/config/puma.rb`.

You can always change those defaults by editing the scripts.

## Here's what a minimal app's config file should have

```
dir="/path/to/rails/project"
user="user-to-run-puma"
ruby_version="version.to.run"
ruby_env="rbenv"
```

## Before starting...

You need to customise `puma.conf` to:

* Set the right user your app should be running on unless you want root to execute it!
* Set the directory of the app
* Set the ruby version to execute
* Set the ruby environment (currently set to rbenv, since that is the only ruby environment currently supported)

## Notes:

Only rbenv is currently supported because that's what I've been working with. I might try other implementation and/or manage multiple instances
