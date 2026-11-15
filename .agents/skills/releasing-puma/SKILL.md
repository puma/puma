---
name: releasing-puma
description: Cut and publish a Puma release. Use for patch releases on X-Y-stable, minor/major releases from main, backporting fixes to stable branches, or building and pushing gems, tags and GitHub releases.
---

[Release.md](../../../Release.md) is the policy: version choice, codenames, upgrade guides, branch names. This skill is the procedure. Where they disagree, Release.md wins; tell the maintainer.

The **maintainer** is the human releasing. Every **go** below requires explicit approval; preparation does not authorize pushing, merging, tagging, or publishing.

**Local CI** is `test/local-ci` from a `main` checkout: it runs the Linux jobs from the current checkout's `tests.yml` in Docker. Older stable branches may not carry it, so run main's copy from inside the release checkout, e.g. `$MAIN/test/local-ci`. `--help` lists its options.

Fixes for unpublished security advisories come from the `security-triage` skill. Their disclosure order (private forks, advisories, CVEs) is not covered here; stop and ask the maintainer before pushing anything that contains them.

## 1. Plan

For each series being released, record:

- Base: `origin/main` for minor/major, `origin/X-Y-stable` for a patch. Fetch first and use a clean checkout matching the base.
- CI status for the base's current HEAD; stop unless it is passing.
- Current version (`lib/puma/const.rb` on the base) and the next one.
- The fixes to ship, as commits on `origin/main`, oldest first. A public fix that isn't on main yet goes on main first.

Done when the maintainer has confirmed the series, versions and commit list. See Release.md for codenames and major-release preparation.

## 2. Backport patch releases

Per series, work on `release-vX.Y.Z` from `origin/X-Y-stable`:

- `git cherry-pick -x` each commit. Resolve conflicts so behaviour on this branch matches main, and port the commit's tests. Adapt to the branch's APIs; pull in no unrelated main-only code.
- A commit is **not applicable** only when the code it fixes doesn't exist on this branch. Prove it with `git grep` or `git log`.
- After picking each commit, run its own test file under local CI: `$MAIN/test/local-ci -- <test_file>`.

Done when every commit is clean, resolved, or proven not applicable, and you have written down each resolution and its reasoning for the maintainer.

## 3. Review

Get a second model (a different one from the backporter) to review adversarially, assuming the backport is wrong until evidence says otherwise. It checks:

1. **Fidelity**: `git range-diff` against main's commits. Dropped hunks, dropped tests, extra changes.
2. **Completeness**: older copies of the fixed code that only this branch still has.
3. **Not applicable** claims, verified independently.
4. **Scope**: every file touched outside `lib/`, `ext/`, `test/`.
5. **SemVer**: new public API, config or DSL, changed defaults, changed responses to valid requests, raised Ruby or dependency floors. A patch release with any of these needs the maintainer's explicit override.

Done when every finding is fixed or the maintainer has ruled on it.

## 4. Prepare the release PR

On the release branch, one final commit titled `Release vX.Y.Z` changes only `lib/puma/const.rb` (version, and codename for minor/major) and `History.md`. Write the History section per [history.md](history.md).

Done when the version matches the branch name, codename isn't a placeholder, `## X.Y.Z / YYYY-MM-DD` heading exists, and every `[#NNNN]` the section uses has a link definition. The workflow never chooses or edits these files.

Tag the Namer on minor/major version PRs and agree on a codename before approval.

## 5. CI and human approval

First, from the release checkout, run `$MAIN/test/local-ci --all --base origin/X-Y-stable` (the base from the plan). It reruns each new failure on both commits and labels it. Each `REGRESSION` or job error is a **possible blocker**; bring it to the maintainer before pushing. For a release that carries unpublished advisory fixes, this is the only test matrix until disclosure.

**go:** push `release-vX.Y.Z` and open the PR into its base, per Release.md. GitHub CI is the full test matrix, including macOS and Windows.

Triage every failed job:

- Compare it with recent runs on the base branch. Failures that also happen on the base, or that pass on rerun, are flakes rather than new regressions. For a Linux job, `$MAIN/test/local-ci --only '<job name>' --base origin/X-Y-stable --repeat 10 -- <test_file>` settles it without a CI round trip.
- A failure in a test the release added or changed, or one that only happens on the release, is a **possible blocker**. Bring it to the maintainer with the job link and the failing test.

Done when every job has finished and every failure is classified. Another human maintainer must approve the final head; CI gates still apply to flakes and slow jobs.

## 6. Run the release workflow

The workflow builds, audits, tests, and publishes both gems and GitHub assets. Reuse its archives; do not rebuild them for publication.

Start with a dry run, replacing the placeholders:

```sh
gh workflow run release.yml --repo github.com/puma/puma --ref BRANCH -f version=X.Y.Z
```

**go:** merge the PR; verify the target tip is its merge commit and matches the reviewed tree. **go:** have the maintainer sign, verify, and push the tag per Release.md.

**go:** dispatch publication with the merged PR and signed tag. The `release` environment still requires maintainer approval:

```sh
gh workflow run release.yml --repo github.com/puma/puma --ref BRANCH -f version=X.Y.Z -f release-pr=NUMBER -f dry-run=false
```

Release newer series first (8.x before 7.x); older series must not become latest. Verify each series and recover as described in Release.md; never overwrite tags or blindly republish.

## 7. Sync main after patch releases

**go:** a PR to `main` that adds each new History section in version order (8.x sections above 7.x) along with its link definitions. If `VERSION` in `lib/puma/const.rb` on `main` is in the released series, the PR also sets it to the new version. Done when it is merged.

## Gotchas

- `main` is protected and takes PRs only. Stable branches take direct fast-forward pushes, but this release workflow still requires a reviewed release PR.
- `git diff --no-ext-diff` whenever diff output goes to a file or into `git apply`; a configured external diff tool otherwise replaces the patch.
- `git describe --tags --abbrev=0 origin/X-Y-stable` finds the series' last release.
- Clean up only task-owned scratch files and release artifacts; preserve unrelated work.
