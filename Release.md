## Before Release

- Make sure tests pass and your last local commit matches master.
- Run tests with latest jruby
- Update the version in `const.rb`.
- Make sure there is a history entry in `History.md`.
- On minor version updates i.e. from 3.10.x to 3.11.x update the "codename" in `const.rb`.

# Release process

Using "3.7.1" as a version example.

1. `bundle exec rake release`
2. Switch to latest JRuby version
3. `rake java gem`
4. `gem push pkg/puma-3.7.1-java.gem`
