# Contributing to Puma

By participating in this project, you agree to follow the [code of conduct].

[code of conduct]: https://github.com/puma/puma/blob/master/CODE_OF_CONDUCT.md

There are lots of ways to contribute to Puma. Some examples include:

* creating a [bug report] or [feature request]
* verifying [existing bug reports] and adding [reproduction steps]
* reviewing [pull requests] and testing the changes locally on your machine
* writing or editing [documentation]
* improving test coverage
* fixing a [reproducing bug] or adding a new feature

[bug report]: https://github.com/puma/puma/issues/new?template=bug_report.md
[feature request]: https://github.com/puma/puma/issues/new?template=feature_request.md
[existing bug reports]: https://github.com/puma/puma/issues?q=is%3Aopen+is%3Aissue+label%3Aneeds-repro
[pull requests]: https://github.com/puma/puma/pulls
[documentation]: https://github.com/puma/puma/tree/master/docs
[reproduction steps]: https://github.com/puma/puma/blob/CONTRIBUTING.md#reproduction-steps
[reproducing bug]: https://github.com/puma/puma/issues?utf8=%E2%9C%93&q=is%3Aopen+is%3Aissue+label%3Abug

Newbies welcome! We would be happy to help you make your first contribution to a F/OSS project.

## Setup

First step: join us on Matrix at [#puma-contrib:matrix.org](https://matrix.to/#/!blREBEDhVeXTYdjTVT:matrix.org?via=matrix.org)

**If you're nervous, get stuck, need help, or want to know where to start and where you can help**, please don't hesitate to [book 30 minutes with maintainer @nateberkopec here](https://calendly.com/nate-berkopec/puma). He is happy to help!

Clone the Puma repository:
```sh
git clone git@github.com:puma/puma.git && cd puma
```

You need to install [ragel] (use Ragel version 7.0.0.9) to generate Puma's extension code.

macOS:

```sh
brew install ragel
```

Linux:
```sh
apt-get install ragel
```

Windows (Ruby 2.5 and later):
```sh
ridk exec pacman -S mingw-w64-x86_64-openssl mingw-w64-x86_64-ragel
```

Install the Ruby dependencies:
```sh
bundle install
```

To run Puma locally, you must compile the native extension.

Ubuntu, macOS, etc:
```sh
bundle exec rake compile
```

Windows:
```sh
bundle exec rake -rdevkit compile
```

Now, you should be able to run Puma locally:

```sh
bundle exec bin/puma test/rackup/hello.ru
# -or-
bundle exec ruby -Ilib bin/puma test/rackup/hello.ru
```

Alternatively, you can reference your local copy in a project's `Gemfile`:

```ruby
gem "puma", path: "/path/to/local/puma"
```

See the [Bundler docs](https://bundler.io/man/gemfile.5.html#PATH) for more details.

[ragel]: https://www.colm.net/open-source/ragel/

## Running tests

To run the entire test suite:
```sh
bundle exec rake test:all
```

To run a single test file:
```sh
bundle exec ruby test/test_binder.rb
```

You can also run tests with [`m`](https://github.com/qrush/m):
```sh
bundle exec m test/test_binder.rb
```

To run a single test:
```sh
bundle exec m test/test_binder.rb:37
```

## How to contribute

Puma could use your help in several areas!

**The [contrib-wanted] label indicates that an issue might approachable to first-time contributors.**\

**Reproducing bug reports**: The [needs-repro] label indicates than an issue lacks reproduction steps. You can help by reproducing the issue and sharing the steps you took in the comments.

**Helping with our native extensions**: If you are interested in writing C or Java, we could really use your help. Check out the issue labels for [c-ext] and [JRuby].

**Fixing bugs**: Issues with the [bug] label have working reproduction steps, which you can use to write a test and submit a patch.

**Writing features**: The [feature] label highlights requests for new functionality. Write tests and code up our new feature!

**Code review**: Take a look at open pull requests and offer your feedback. Code review is not just for maintainers. We need your help and eyeballs!

**Write documentation**: Puma needs more docs in many areas, especially where we have open issues with the [docs] label.

[bug]: https://github.com/puma/puma/issues?q=is%3Aopen+is%3Aissue+label%3Abug
[c-ext]: https://github.com/puma/puma/issues?q=is%3Aopen+is%3Aissue+label%3Ac-ext
[contrib-wanted]: https://github.com/puma/puma/issues?q=is%3Aopen+is%3Aissue+label%3Acontrib-wanted
[docs]: https://github.com/puma/puma/issues?q=is%3Aopen+is%3Aissue+label%3Adocs
[feature]: https://github.com/puma/puma/issues?q=is%3Aopen+is%3Aissue+label%3Afeature
[jruby]: https://github.com/puma/puma/issues?q=is%3Aopen+is%3Aissue+label%3Ajruby
[needs-repro]: https://github.com/puma/puma/issues?q=is%3Aopen+is%3Aissue+label%3Aneeds-repro

## Reproduction steps

Reproducing a bug helps identify the root cause of that bug so it can be fixed.

To get started, create a rackup file and config file and then run your test app
with:
```sh
bundle exec puma -C <path/to/config.rb> <path/to/rackup.ru>
```

For example, using a test rack app ([`test/rackup/hello.ru`][rackup]) and a
test config file ([`test/config/settings.rb`][config]):
```sh
bundle exec puma -C test/config/settings.rb test/rackup/hello.ru
```

There is also a Dockerfile available for reproducing Linux-specific issues:
```sh
docker build -f tools/docker/Dockerfile -t puma .
docker run -p 9292:9292 -it puma
```

[rackup]: https://github.com/puma/puma/blob/master/test/rackup/hello.ru
[config]: https://github.com/puma/puma/blob/master/test/config/settings.rb

## Pull requests

Code contributions should generally include test coverage. If you aren't sure how to
test your changes, please open a pull request and leave a comment asking for
help.

There's no need to update the changelog ([`History.md`](History.md)); that is done [when a new release is made](Release.md).

Puma uses [GitHub Actions](https://docs.github.com/en/actions) for CI testing. Please consider running the workflows in your fork before creating a PR. It is possible to enable GitHub Actions on your fork in the repositories' `Actions` tab.

## Backports

Puma does not have a backport "policy" - maintainers will not consistently backport bugfixes to previous minor or major versions (we do treat security differently, see [`SECURITY.md`](SECURITY.md).

As a contributor, you may make pull requests against `-stable` branches to backport fixes, and maintainers will release them once they're merged. For example, if you'd like to make a backport for 4.3.x, you can make a pull request against `4-3-stable`. If there is no appropriate branch for the release you'd like to backport against, please just open an issue and we'll make one for you.

## Join the community

If you're looking to contribute to Puma, please join us on Matrix at [#puma-contrib:matrix.org](https://matrix.to/#/!blREBEDhVeXTYdjTVT:matrix.org?via=matrix.org).

## Bibliography/Reading

Puma can be a bit intimidating for your first contribution because there's a lot of concepts here that you've probably never had to think about before - Rack, sockets, forking, threads etc. Here are some helpful links for learning more about things related to Puma:

* [Puma's Architecture docs](https://github.com/puma/puma/blob/master/docs/architecture.md)
* [The Rack specification](https://github.com/rack/rack/blob/master/SPEC.rdoc)
* The Ruby docs for IO.pipe, TCPServer/Socket.
* [nio4r documentation](https://github.com/socketry/nio4r/wiki/Getting-Started)
