# How to Release Puma

The [Release workflow](.github/workflows/release.yml) uses [ruby-gem-release](https://github.com/dblock/ruby-gem-release/tree/593b161261c504f2ec3dda97b6df4d816cad4ac5) to build, audit, and publish CRuby/Java gems without editing reviewed files, creating commits/tags, or bumping versions. Local publishing is disabled.

## One-time setup

Before publishing:

1. Protect the `release` environment for `main` and maintained `*-stable` branches; require another human maintainer's approval and prevent self-review.
2. Register a RubyGems Trusted Publisher for `puma`: repository `puma/puma`, workflow `release.yml`, environment `release`.
3. Set Actions variable `RELEASE_SIGNING_KEYS` to allowed ASCII-armored **public** GPG keys. Never upload private keys.
4. Allow the workflow's PR/check reads and GitHub Release writes; retain branch protections.
5. Backport workflows, tooling, manifest, and tests to maintained branches with supported build runtimes.

## Prepare a reviewed release

Follow the [release skill](.agents/skills/releasing-puma/SKILL.md) for planning, backports, review, CI triage, and disclosure approvals. Start clean at the target's remote tip with passing CI.

1. Target `main` for major/minor releases or `<major>-<minor>-stable` for patches. Follow [SemVer 2.0](https://semver.org/); `breaking change` labels suggest a major bump. Only HTTP serving behavior and configuration are public APIs. HTTP/1.1 RFC deviations are patchable bugs.
2. For minor/major releases, ask the leader of `git shortlog -s -n --no-merges <LAST_VERSION>..HEAD` (the "Namer") for a codename and tag them on the PR. For majors, update `SECURITY.md` and add `docs/upgrading/X.0-Upgrade.md`.
3. On `release-vX.Y.Z`, prepare `lib/puma/const.rb`, a final codename, and a dated, nonempty [History.md section](.agents/skills/releasing-puma/history.md).
4. Open a PR to the target branch. Require another human maintainer's approval **on the final head** and successful checks; flakes are not waived.

## Dry run

Use the checked-in version. Dry runs default to true and need no publishing credentials, PR number, tag, or signing keys:

```sh
gh workflow run release.yml --ref main -f version=X.Y.Z
```

The release-only [Package workflow](.github/workflows/package.yml) builds, audits, and installs both platforms, including Ruby 3.0/JRuby 9.4 consumers, without publishing. Archives/checksums are retained for 30 days. Audits check `test/gem_manifest.rb` and Git bytes; installed tests exercise parser, SSL, and CLI. The generated Java 8 JAR replaces C sources and is exempt only from Git-byte comparison.

## Publish

With explicit maintainer approval, merge the PR and sign its merge commit: `git tag -s vX.Y.Z -m "Release vX.Y.Z" <merge-commit>`. Verify with `git tag -v vX.Y.Z`, then push the tag. The merge commit must remain the branch tip. Dispatch from that branch:

```sh
gh workflow run release.yml --ref 8-1-stable \
  -f version=8.1.2 -f release-pr=1234 -f dry-run=false
```

Approve the `release` environment after reviewing builds. Publication rechecks source, approval, CI, signed tag, and both archives before uploading the **same run's retained bytes** with original SHA256s. Exact registry matches are skipped; conflicts/errors stop publication. GitHub receives expanded notes and both assets; older series never become latest.

## Verify and recover

Check both platforms at `https://rubygems.org/api/v2/rubygems/puma/versions/X.Y.Z.json?platform=ruby` (also `platform=java`) against retained SHA256s; visibility may lag successful uploads. Verify the remote signed tag's commit, GitHub notes/latest setting, and downloaded assets' SHA256s. For patches, PR the dated History section and references back to `main`; update main's version only if still in that series.

Before retrying, inspect registry state, refs, and assets; never overwrite tags/published versions or regenerate digests. Verify both original artifacts in `pkg/release/` from a clean signed-commit checkout with `bundle exec rake release:verify`. With unchanged tip/approval, rerun only the failed publishing job to reuse archives and complete missing publications. Whole-workflow reruns rebuild: compare checksums and preserve originals. If the branch advances, stop for authorized recovery; never reset shared branches.

## Local validation

Follow [standard setup](CONTRIBUTING.md#setup) on Ruby 3.3+; leave `PUMA_NO_RUBOCOP` unset. Run `bundle exec rake` and `actionlint .github/workflows/package.yml .github/workflows/release.yml`. Release tests use subprocesses, isolated Git remotes, and fake publication; signed-source tests need Unix GPG. CI does not validate live OIDC or environment protection.

From a clean checkout, run `bundle exec rake release:build release:smoke`. For Java, use current JRuby with JDK 17+ (CI: JDK 25 LTS), compile first, and set `PUMA_RELEASE_PLATFORM=java`. Touch the committed Ragel outputs before compiling to avoid regeneration. The standalone consumer accepts an archive path; unset/empty selects the only matching archive.
