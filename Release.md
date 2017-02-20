# Release process

Using "3.7.1" as a version string example.

1. `be rake release_sanity VERSION=3.7.1`
2. `be rake release VERSION=3.7.1`
3. Switch to latest JRuby version
4. `rake java gem`
5. `gem push pkg/puma-3.7.1-java.gem`
