# How to Release Puma

Releasing Puma requires the following steps:

1. Choose the target base branch:
   - `main` for the next major or minor line.
   - `<major>-<minor>-stable` for patch releases on an existing stable line (for example, release `7.2.3` from `7-2-stable`).
1. Ensure your local target branch is checked out, clean, and matches `origin/<target-branch>`.
1. Check the CI status for the current `HEAD`. Stop unless everything is passing.
1. Decide on the next version number based on [SemVer 2.0](https://semver.org/). Treat `breaking change` PR labels as strong evidence that a `major` bump is needed.
1. For minor and major releases, determine who "earned" the codename via `git shortlog`. This person will be the "Namer."
1. For major releases, update `SECURITY.md` and write a `docs/X.X-Upgrade.md` upgrade guide.
1. Update `History.md` in the existing format and update `lib/puma/const.rb`. If a codename change is required for a minor or major release, change the codename constant to "INSERT CODENAME HERE."
1. Create a release branch named `release-vX.Y.Z` from your target base branch, commit the release changes, and open a PR.
1. Create or update a draft GitHub release for the upcoming tag using the new `History.md` section as the release notes.
1. **STOP** for manual review. The PR must be reviewed and checked by at least one human.

Once the PR is merged:

1. Ensure the release tag points at `HEAD`, then push that tag to GitHub.
1. Build the CRuby gem with `bundle exec rake build`.
1. If `mise` is installed, look up the latest JRuby version, run `mise exec jruby@<latest> -- rake java gem`, and build the JRuby gem. Otherwise, manage your environment yourself.
1. `gem push` both artifacts to rubygems.org. This requires manual 2FA.

Once both gems have been pushed to rubygems.org:

1. Create or update the GitHub release based on the release tag.
1. Publish the release if it is still a draft.
1. Upload the built gem artifacts to the GitHub release:
   - `pkg/puma-<version>.gem`
   - `pkg/puma-<version>-java.gem`
1. Verify post-publish state:
   - RubyGems shows `puma` version `<version>`.
   - The GitHub release is published and includes both gem artifacts.

## Branch Conventions

- Name release PR branches as `release-vX.Y.Z`.
- Target `main` for major/minor releases.
- Target `<major>-<minor>-stable` for patch releases on maintained stable lines.

## The "Namer"

We usually let the leader of `git shortlog -s -n --no-merges <LAST_VERSION>..HEAD` name the release.

Tag this person on the new version PR and ask them to propose a codename.

## The Changelog Format

In the past, we've used [Greg's tool](https://github.com/MSP-Greg/issue-pr-link) to generate it, but anything that follows the existing format is fine.
