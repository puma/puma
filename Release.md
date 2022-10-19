## Before Release

- Make sure tests pass and your last local commit matches master.
- Run tests with latest jruby
- Update the version in `const.rb`.
- On minor or major version updates i.e. from 3.10.x to 3.11.x update the "codename" in `const.rb`.
- Create history entries with https://github.com/MSP-Greg/issue-pr-link

# Release process

Using "3.7.1" as a version example.

1. `bundle exec rake release`
1. Switch to latest JRuby version
1. `rake java gem`
1. `gem push pkg/puma-VERSION-java.gem`
1. Add release on Github at https://github.com/puma/puma/releases/new
