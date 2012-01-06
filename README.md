# Puma: A Ruby Web Server Built For Concurrency

## Description

Puma is a simple, fast, and highly concurrent HTTP 1.1 server for Ruby web applications. It can be used with any application that supports Rack, and is considered the replacement for Webrick and Mongrel. It was designed to be the go-to server for [Rubinius](http://rubini.us), but also works well with JRuby and MRI. Puma is intended for use in both development and production environments.

Under the hood, Puma processes requests using a C-optimized Ragel extention (inherited from Mongrel) that provides fast, accurate HTTP 1.1 protocol parsing in a portable way. Puma then serves the request in a thread from an internal thread pool (which you can control). This allows Puma to provide real concurrency for your web application!

With Rubinius 2.0, Puma will utilize all cores on your CPU with real threads, meaning you won't have to spawn multiple processes to increase throughput. You can expect to see a similar benefit from JRuby.

On MRI, there is a Global Interpreter Lock (GIL) that ensures only one thread can be run at a time. But if you're doing a lot of blocking IO (such as HTTP calls to external APIs like Twitter), Puma still improves MRI's throughput by allowing blocking IO to be run concurrently (EventMachine-based servers such as Thin turn off this ability, requiring you to use special libraries). Your mileage may vary.. in order to get the best throughput, it is highly recommended that you use a Ruby implementation with real threads like [Rubinius](http://rubini.us) or [JRuby](http://jruby.org).

## Quick Start

The easiest way to get started with Puma is to install it via RubyGems. You can do this easily:

    $ gem install puma

Now you should have the puma command available in your PATH, so just do the following in the root folder of your Rack application:

    $ puma app.ru

## Advanced Setup

### Sinatra

You can run your Sinatra application with Puma from the command line like this:

    $ ruby app.rb -s Puma

Or you can configure your application to always use Puma:

    require 'sinatra'
    configure { set :server, :puma }

If you use Bundler, make sure you add Puma to your Gemfile (see below).

### Rails

First, make sure Puma is in your Gemfile:

    gem 'puma'

Then start your server with the `rails` command:

    $ rails s puma

### Rackup

You can pass it as an option to `rackup`:

    $ rackup -s puma

Alternatively, you can modify your `config.ru` to choose Puma by default, by adding the following as the first line:

    #\ -s puma

## Configuration

Puma provides numerous options for controlling the operation of the server. Consult `puma -h` (or `puma --help`) for a full list.

### Thread Pool

Puma utilizes a dynamic thread pool which you can modify. You can set the minimum and maximum number of threads that are available in the pool with the `-t` (or `--threads`) flag:

    $ puma -t 8:32
    
Puma will automatically scale the number of threads based on how much traffic is present. The current default is `0:16`. Feel free to experiment, but be careful not to set the number of maximum threads to a very large number, as you may exhaust resources on the system (or hit resource limits).

### Binding TCP / Sockets

In contrast to many server configs, Puma simply uses takes one URI parameter with the `-b` (or `--bind`) flag:

    $ puma -b tcp://127.0.0.1:9292

Want to use UNIX Sockets instead of TCP (which can provide a 5-10% performance boost)? No problem!

    $ puma -b unix:///var/run/puma.sock

## License

Puma is copyright 2011 Evan Phoenix and contributors. It is licensed under the BSD license. See the include LICENSE file for details.
