# Release process

Using "3.7.1" as a version example.

2. `bundle exec rake release`
3. Switch to latest JRuby version
4. `rake java gem`
5. `gem push pkg/puma-3.7.1-java.gem`
