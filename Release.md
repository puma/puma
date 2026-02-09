## Before Release

- Make sure tests pass and your last local commit matches main.
- Run tests with latest jruby
- Update the version in `const.rb`.
- On minor or major version updates i.e. from 3.10.x to 3.11.x update the "codename" in `const.rb`. We usually allow the leader of `git shortlog -s -n --no-merges <LAST_VERSION>..HEAD` name the version.
- Create history entries with https://github.com/MSP-Greg/issue-pr-link
  - Usually I run it from the puma repo:

```
$ ruby ../issue-pr-link/json_pr_issue_all.rb ../issue-pr-link/info.sample
```

Then

```
$ ruby ../issue-pr-link/history_new_release.rb ../issue-pr-link/info.sample <LAST_VERSION_TAG>
```

That command will print output you're expected to use to modify `Histroy.md`. Once done you can update the links in the document by running:

```
$ ruby ../issue-pr-link/json_history_update.rb ../issue-pr-link/info.sample
```

# Release process

Using "3.7.1" as a version example.

1. `bundle exec rake release`
1. Switch to latest JRuby version
1. `rake java gem`
1. `gem push pkg/puma-VERSION-java.gem`
1. Add release on Github at https://github.com/puma/puma/releases/new
