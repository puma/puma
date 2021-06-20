## Before Release

- Make sure tests pass and your last local commit matches master.
- Run tests with latest jruby
- Update the version in `const.rb`.
- On minor or major version updates i.e. from 3.10.x to 3.11.x update the "codename" in `const.rb`.
- Create history entries with https://github.com/MSP-Greg/issue-pr-link

# Release process

Using "3.7.1" as a version example.

1. `bundle exec rake release`
2. `gem push --key github --host https://rubygems.pkg.github.com/puma pkg/puma-VERSION.gem`
3. Switch to latest JRuby version
4. `rake java gem`
5. `gem push pkg/puma-VERSION-java.gem`
