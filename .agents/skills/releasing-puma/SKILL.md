---
name: releasing-puma
description: Cut and publish a Puma release. Use for patch releases on X-Y-stable, minor/major releases from main, backporting fixes to stable branches, or building and pushing gems, tags and GitHub releases.
---

[Release.md](../../../Release.md) is the policy: version choice, codenames, upgrade guides, branch names. This skill is the procedure. Where they disagree, Release.md wins; tell the maintainer.

The **maintainer** is the human releasing. They hold the GPG key, the RubyGems MFA, and every outward-facing go. Each step marked **go** waits for an explicit yes.

Do scratch work (worktrees, gem builds, notes) under `tmp/release/` in the repo root. Cleanup removes only that directory.

Fixes for unpublished security advisories come from the `security-triage` skill. Their disclosure order (private forks, advisories, CVEs) is not covered here; stop and ask the maintainer before pushing anything that contains them.

## 1. Plan

For each series being released, record:

- Base: `origin/main` for minor/major, `origin/X-Y-stable` for a patch. Fetch first.
- Current version (`lib/puma/const.rb` on the base) and the next one.
- The fixes to ship, as commits on `origin/main`, oldest first. A fix that isn't on main yet goes on main first.

Done when the maintainer has confirmed the series, versions and commit list.

## 2. Backport (patch releases)

Per series, in a worktree on `release-vX.Y.Z` from `origin/X-Y-stable`:

- `git cherry-pick -x` each commit. Resolve conflicts so behaviour on this branch matches main, and port the commit's tests. Adapt to the branch's APIs; pull in no unrelated main-only code.
- A commit is **not applicable** only when the code it fixes doesn't exist on this branch. Prove it with `git grep` or `git log`.
- Run each commit's own test file after picking it.

Done when every commit is clean, resolved, or proven not applicable, and you have written down each resolution and its reasoning for the maintainer.

## 3. Review

Get a second model (a different one from the backporter) to review adversarially, assuming the backport is wrong until evidence says otherwise. It checks:

1. **Fidelity**: `git range-diff` against main's commits. Dropped hunks, dropped tests, extra changes.
2. **Completeness**: older copies of the fixed code that only this branch still has.
3. **Not applicable** claims, verified independently.
4. **Scope**: every file touched outside `lib/`, `ext/`, `test/`.
5. **Semver**: new public API, config or DSL, changed defaults, changed responses to valid requests, raised Ruby or dependency floors. A patch release with any of these needs the maintainer's explicit override.

Done when every finding is fixed or the maintainer has ruled on it.

## 4. Release commit

On the release branch, one commit titled `Release vX.Y.Z` that changes only `lib/puma/const.rb` (version, and codename for minor/major) and `History.md`. Write the History section per [history.md](history.md).

Done when the checks in `.github/workflows/release-checks.yml` pass against your branch: version matches the branch name, codename isn't a placeholder, `## X.Y.Z / YYYY-MM-DD` heading exists, and every `[#NNNN]` the section uses has a link definition.

## 5. Build and verify gems

From a clean worktree at the release commit:

```sh
bundle exec rake build
mise exec jruby@latest -- bundle exec rake java gem
.agents/skills/releasing-puma/scripts/check-gems release-vX.Y.Z pkg/puma-X.Y.Z.gem pkg/puma-X.Y.Z-java.gem
```

`check-gems` checks each gem's name, version and platform, compares every packaged file byte-for-byte against the git ref, and prints SHA256s. The compiled JRuby jar is the only file it skips.

Done when both gems verify against the release commit. Build again if the commit changes.

## 6. CI

**go**: push `release-vX.Y.Z` and open the PR into its base, per Release.md. GitHub CI is the test matrix.

Triage every failed job:

- Compare it with recent runs on the base branch. Failures that also happen on the base, or that pass on rerun, are flakes. **Flakes don't gate the release.**
- A failure in a test the release added or changed, or one that only happens on the release, is a **possible blocker**. Bring it to the maintainer with the job link and the failing test.

Done when every job has finished (the maintainer may waive slow ones) and every failure is classified.

## 7. Publish

In this order, 8.x before 7.x when releasing several series. Each step can be rerun.

1. **go**: merge the PR. Then check that `git rev-parse origin/X-Y-stable^{tree}` equals the release branch's tree.
2. **go**: `git tag -s vX.Y.Z -m "Release vX.Y.Z" <stable tip>`, `git tag -v vX.Y.Z`, push the tag.
3. Preflight the RubyGems key: `curl -s -o /dev/null -w '%{http_code}' -H "Authorization: $GEM_HOST_API_KEY" https://rubygems.org/api/v1/gems.json` must print `200`. A 401 means the key is revoked; the maintainer makes a new one scoped to push `puma`.
4. **go**: the maintainer runs `gem push pkg/puma-X.Y.Z.gem --otp <code>` and the same for the `-java` gem. If RubyGems already lists a gem, its SHA256 must match yours; skip it.
5. Write the release notes: `.agents/skills/releasing-puma/scripts/release-notes X.Y.Z History.md > tmp/release/notes-X.Y.Z.md` expands `[#NNNN]` references into full links.
6. **go**: publish the GitHub release for `vX.Y.Z` (the draft, or `https://github.com/puma/puma/releases/new?tag=vX.Y.Z&title=vX.Y.Z`) with the notes and both gems attached. **Uncheck "Set as the latest release"** when an older series is released alongside a newer one.
7. Verify: `https://rubygems.org/api/v1/versions/puma.json` lists both platforms with your SHA256s, and the GitHub release assets match them.

Done when step 7 passes for every series.

## 8. Sync main (patch releases)

**go**: a PR to `main` that adds each new History section in version order (8.x sections above 7.x) along with its link definitions. Done when it is merged.

## Gotchas

- `main` is protected and takes PRs only. Stable branches take direct fast-forward pushes.
- `git diff --no-ext-diff` whenever diff output goes to a file or into `git apply`; a configured external diff tool otherwise replaces the patch.
- `git describe --tags --abbrev=0 origin/X-Y-stable` finds the series' last release.
