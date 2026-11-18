<p align="center">
  <img src="docs/images/standard-logo.svg" alt="Puma logo">
</p>

# Puma: A Ruby Web Server Built For Parallelism

[![Actions](https://github.com/puma/puma/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/puma/puma/actions/workflows/tests.yml?query=branch%3Amain)

<a href="https://commitgoods.com/collections/puma?utm_source=github&amp;utm_medium=referral">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://cdn.shopify.com/s/files/1/0101/8752/files/commitgoods-badge-stacked-navy-dark.svg">
    <img src="https://cdn.shopify.com/s/files/1/0101/8752/files/commitgoods-badge-stacked-navy.svg" height="28" alt="Official merch on commitgoods.com">
  </picture>
</a>

Puma is a **simple, fast, multi-threaded, and highly parallel HTTP 1.1 server for Ruby/Rack applications**.

## Built For Speed &amp; Parallelism

Puma is a server for [Rack](https://github.com/rack/rack)-powered HTTP applications written in Ruby.  It is:
* **Multi-threaded**. Each request is served in a separate thread. This helps you serve more requests per second with less memory use.
* **Multi-process**. "Pre-forks" in cluster mode, using less memory per-process thanks to copy-on-write memory.
* **Standalone**. With SSL support, zero-downtime rolling restarts and a built-in request bufferer, you can deploy Puma without any reverse proxy.
* **Battle-tested**. Our HTTP parser is inherited from Mongrel and has over 15 years of production use. Puma is currently the most popular Ruby webserver, and is the default server for Ruby on Rails.

Originally designed as a server for [Rubinius](https://github.com/rubinius/rubinius), Puma also works well with Ruby (MRI) and JRuby.

On MRI, there is a Global VM Lock (GVL) that ensures only one thread can run Ruby code at a time. But if you're doing a lot of blocking IO (such as HTTP calls to external APIs like Twitter), Puma still improves MRI's throughput by allowing IO waiting to be done in parallel. Truly parallel Ruby implementations (TruffleRuby, JRuby) don't have this limitation.

## Quick Start

```
$ gem install puma
$ puma
```

Without arguments, puma will look for a rackup (.ru) file in
the working directory called `config.ru`.

## SSL Connection Support

Puma will install/compile with support for ssl sockets, assuming OpenSSL
development files are installed on the system.

If the system does not have OpenSSL development files installed, Puma will
install/compile, but it will not allow ssl connections.

## Frameworks

### Rails

Puma is the default server for Rails, included in the generated Gemfile.

Start your server with the `rails` command:

```
$ rails server
```

Many configuration options and Puma features are not available when using `rails server`. It is recommended that you use Puma's executable instead:

```
$ bundle exec puma
```

### Sinatra

You can run your Sinatra application with Puma from the command line like this:

```
$ ruby app.rb -s Puma
```

In order to actually configure Puma using a config file, like `puma.rb`, however, you need to use the `puma` executable. To do this, you must add a rackup file to your Sinatra app:

```ruby
# config.ru
require './app'
run Sinatra::Application
```

You can then start your application using:

```
$ bundle exec puma
```

## Configuration

Puma provides numerous options. Consult `puma -h` (or `puma --help`) for a full list of CLI options, or see `Puma::DSL` or [dsl.rb](https://github.com/puma/puma/blob/main/lib/puma/dsl.rb).

You can also find several configuration examples as part of the
[test](https://github.com/puma/puma/tree/main/test/config) suite.

For debugging purposes, you can set the environment variable `PUMA_LOG_CONFIG` with a value
and the loaded configuration will be printed as part of the boot process.

## Documentation

* [Configuration](docs/configuration.md)
* [Cluster mode](docs/cluster_mode.md)
* [Binding TCP / Sockets and SSL](docs/binding.md)
* [HTTPS behind a reverse proxy or in Puma](docs/ssl.md)
* [Control/Status Server and stats](docs/control_server.md)
* [Restart](docs/restart.md)
* [Signals](docs/signals.md)
* [Plugins](docs/plugins.md)
* [Deployment](docs/deployment/README.md)
* [Running Puma in Rails development mode](docs/rails_dev_mode.md)
* [Compile options](docs/compile_options.md) and [Java options](docs/java_options.md)
* [Architecture](docs/architecture.md)
* [Support policy](docs/puma_support.md)
* [Upgrade guides](docs/upgrading)

## Platform Constraints

Some platforms do not support all Puma features.

  * **JRuby**, **Windows**: server sockets are not seamless on restart, they must be closed and reopened. These platforms have no way to pass descriptors into a new process that is exposed to Ruby. Also, cluster mode is not supported due to a lack of fork(2).
  * **Windows**: Cluster mode is not supported due to a lack of fork(2).
  * **Kubernetes**: The way Kubernetes handles pod shutdowns interacts poorly with server processes implementing graceful shutdown, like Puma. See the [kubernetes section of the documentation](docs/deployment/kubernetes.md) for more details.

## Merchandise

Puma stickers, shirts, hoodies, and mugs are available at [commitgoods.com](https://commitgoods.com/collections/puma?utm_source=github&utm_medium=referral).

## Contributing

Find details for contributing in the [contribution guide](CONTRIBUTING.md). AI-assisted contributions are welcome; coding agents should start with [AGENTS.md](AGENTS.md).

Report a suspected vulnerability privately, as described in the [security policy](SECURITY.md), not in a public issue or pull request.

## License

Puma is copyright Evan Phoenix and contributors, licensed under the BSD 3-Clause license. See the included LICENSE file for details.

Puma includes a copy of [`sd_notify`](https://github.com/agis/ruby-sdnotify) (commit `cca575c`), licensed under the MIT license. See [`lib/puma/sd_notify.rb`](lib/puma/sd_notify.rb) for the license text.
