# How to Release Puma

Release Puma requires accomplishing the following tasks:

## `tools/release_script.sh`

`release_script.sh prepare` does the following:

1. Ensures local `main` is checked out, clean, and matches `origin/main`.
1. Checks the CI status for the current `HEAD`.
1. Asks `$AGENT_CMD` (default: `claude`) to recommend the semantic version bump from the commits since the last release.
1. Treats `breaking change` PR labels as strong evidence for `major`; otherwise, if any commit looks like a feature or other user-facing addition, it recommends at least `minor`.
1. Uses that recommendation to pick `patch`, `minor`, or `major`, and includes the agent's reasoning with commit links in the release PR body.
1. Generates a changelog with `communique`, validates that it matches Puma's required format, and retries if it doesn't.
1. For minor and major releases, figures out who "earned" the codename via `git shortlog`.
1. Updates `History.md` and `lib/puma/const.rb`.
1. Creates a release branch, commits the release changes, pushes the branch, and opens the release PR.
1. Creates or updates a draft GitHub release for the upcoming tag using the new `History.md` section as the release notes.
1. **STOP** for manual review. The PR must be reviewed and checked by at least one human.

Once the PR is merged, `release_script.sh build` does the following:

1. Ensures the release tag points at `HEAD` and pushes that tag to GitHub.
1. Builds the CRuby gem with `bundle exec rake build`.
1. If `mise` is installed, looks up the latest JRuby version, runs `mise exec jruby@<latest> -- rake java gem`, and builds the JRuby gem automatically.
1. If `mise` is not installed, stops after the CRuby gem and tells you to build the JRuby gem manually.
1. **STOP** so a human can manually `gem push` both artifacts to rubygems.org.

Once both gems are pushed to rubygems.org, `release_script.sh github` does the following:

1. Creates the GitHub release as a draft if it does not already exist.
1. Compares the current release notes against the matching `History.md` section and updates the release notes if needed.
1. Publishes the release if it is still a draft.
1. Uploads the built gem artifacts:
   - `pkg/puma-<version>.gem`
   - `pkg/puma-<version>-java.gem`

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


