# Puma: A Ruby Web Server Built For Concurrency

## Description

Puma is a small library that provides a very fast and concurrent HTTP 1.1 server for Ruby web applications.  It is designed for running rack apps only.

What makes Puma so fast is the careful use of an Ragel extension to provide fast, accurate HTTP 1.1 protocol parsing. This makes the server scream without too many portability issues.

## License

Puma is copyright 2011 Evan Phoenix and contributors. It is licensed under the BSD license. See the include LICENSE file for details.

## Quick Start

The easiest way to get started with Puma is to install it via RubyGems and then run a Ruby on Rails application. You can do this easily:

    $ gem install puma

Now you should have the puma command available in your PATH, so just do the following:

    $ puma app.ru

## Install

    $ gem install puma

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
