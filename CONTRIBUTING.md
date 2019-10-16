# Contributing to Puma

By participating in this project, you agree to follow the [code of conduct].

[code of conduct]: https://github.com/puma/puma/blob/master/CODE_OF_CONDUCT.md

There are lots of ways to contribute to puma. Some examples include:

* creating a [bug report] or [feature request]
* verifying bug reports and adding [reproduction steps]
* reviewing [pull requests] and testing the changes on your own machine
* writing or editing documentation
* improving test coverage
* fixing a bug or adding a new feature

[bug report]: https://github.com/puma/puma/issues/new?template=bug_report.md
[feature request]: https://github.com/puma/puma/issues/new?template=feature_request.md
[pull requests]: https://github.com/puma/puma/pulls
[reproduction steps]: https://github.com/puma/puma/blob/CONTRIBUTING.md#reproduction-steps

## Setup

You will need to install [ragel] to generate puma's extension code.

macOS:

```sh
brew install ragel
```

Linux:
```sh
apt-get install ragel
```

Install Ruby dependencies with:

```sh
bundle install
```

[ragel]: https://www.colm.net/open-source/ragel/

## Running tests

You can run the full test suite with:

```sh
bundle exec rake test:all
```

To run a single test file:

```sh
ruby -Ilib test/test_integration.rb
```

Or use [`m`](https://github.com/qrush/m):

```sh
bundle exec m test/test_binder.rb
```

Which can also be used to run a single test case:

```sh
bundle exec m test/test_binder.rb:37
```

## Reproduction steps

Reproducing a bug helps identify the root cause of that bug so it can be fixed.
To get started, create a rackup file and config file and then run your test app
with:

```sh
bundle exec puma -C <path/to/config.rb> <path/to/rackup.ru>
```

As an example, using one of the test rack apps:
[`test/rackup/hello.ru`][rackup], and one of the test config files:
[`test/config/settings.rb`][config], you would run the test app with:

```sh
bundle exec puma -C test/config/settings.rb test/rackup/hello.ru
```

There is also a Dockerfile available for reproducing Linux-specific issues. To use:

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

If you open a pull request with a change that doesn't need to be noted in the
changelog ([`History.md`](History.md)), add the text `[changelog skip]` to the
pull request title to skip [the changelog
check](https://github.com/puma/puma/pull/1991).
