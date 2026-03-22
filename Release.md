# How to Release Puma

Release Puma requies accomplishing the following tasks:

## `tools/release_script.sh`

`release_script.sh prepare` more or less does the following:

1. `git checkout` latest `main` locally and ensure all tests pass, ensure local `main` matches `origin/main`.
1. Ensure current/latest `HEAD` is passing on CI.
1. Generate a changelog with `communique`
1. Figure out what the next version number should be, based on that changelog and following SemVer 2.0.
1. If minor/major release: figure out who "earned" the codename change via git history scoreboard/check. This person is the Namer.
1. Create a PR which bumps the version constant and updates the changelog.
1. **STOP** for manual review. PR must be reviewed and checked by at least one human.

Once the PR is merged, we then `release_script.sh build` which does:

1. Build .gem files (for CRuby and for JRuby)
2. **STOP** for a human to manually `gem push` both artifacts to rubygems.org

Then once that's pushed to rubygems.org for both JRuby and CRuby, we `release_script.sh github` which generates and publishes a Github Release.

## The "Namer"

We usually allow the leader of `git shortlog -s -n --no-merges <LAST_VERSION>..HEAD` name the version.

Tag this person on the "new version PR" and ask them to propose a codename.

## The Changelog Format

In the past we've used [Greg's tool](https://github.com/MSP-Greg/issue-pr-link) to generate, but anything that follows the existing format is fine.

### Using issue-pr-link

Usually I run it from the puma repo:

```
$ ruby ../issue-pr-link/json_pr_issue_all.rb ../issue-pr-link/info.sample
```

Then

```
$ ruby ../issue-pr-link/history_new_release.rb ../issue-pr-link/info.sample <LAST_VERSION_TAG>
```

That command will print output you're expected to use to modify `History.md`. Once done you can update the links in the document by running:

```
$ ruby ../issue-pr-link/json_history_update.rb ../issue-pr-link/info.sample
```


