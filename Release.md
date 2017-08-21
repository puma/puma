# Release process

Using "3.7.1" as a version example.

1. `bundle exec rake release`
2. Switch to latest JRuby version
3. `rake java gem`
4. `gem push pkg/puma-3.7.1-java.gem`
