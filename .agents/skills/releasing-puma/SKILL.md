---
name: releasing-puma
description: Cut and publish a Puma release. Use for patch releases on X-Y-stable, minor/major releases from main, backporting fixes to stable branches, or building and pushing gems, tags and GitHub releases.
---

[Release.md](../../../Release.md) is the procedure, for humans and agents alike. Follow its steps in order. This skill adds what an agent needs on top: approval gates, an adversarial backport review, and CI triage.

The **maintainer** is the human releasing. They hold the GPG key, the RubyGems MFA, and every outward-facing go. Each step marked **go** below waits for an explicit yes.

Do scratch work (worktrees, gem builds, notes) under `tmp/release/` in the repo root. Cleanup removes only that directory.

**Local CI** is `test/local-ci` from a `main` checkout: it runs the Linux jobs from the current checkout's `tests.yml` in Docker. Stable branches don't carry it, so run main's copy from inside the release worktree, e.g. `$MAIN/test/local-ci`. `--help` lists its options.

Fixes for unpublished security advisories come from the `security-triage` skill. Their disclosure order (private forks, advisories, CVEs) is not covered here; stop and ask the maintainer before pushing anything that contains them.

## Prepare

**Plan.** If a `release-vX.Y.Z` PR already exists, read its review threads first. Done when the maintainer has confirmed the series, versions and commit list.

**Backport.** Work in a worktree. After picking each commit, run its own test file under local CI: `$MAIN/test/local-ci -- <test_file>`. Prove each skipped commit is not applicable with `git grep` or `git log`. Done when every commit is clean, resolved, or proven not applicable, and you have written down each resolution and its reasoning for the maintainer.

**Review.** Get a second model (a different one from the backporter) to review the backport adversarially, assuming it is wrong until evidence says otherwise. It checks:

1. **Fidelity**: `git range-diff` against main's commits. Dropped hunks, dropped tests, extra changes.
2. **Completeness**: older copies of the fixed code that only this branch still has.
3. **Not applicable** claims, verified independently.
4. **Scope**: every file touched outside `lib/`, `ext/`, `test/`.
5. **SemVer**: anything [Versioning](../../../docs/puma_support.md#versioning) calls a breaking change, plus new config or DSL, changed defaults, and raised Ruby or dependency floors. A patch release with any of these needs the maintainer's explicit override.

Done when every finding is fixed or the maintainer has ruled on it.

**Release commit.** Done when `.github/workflows/release-checks.yml` passes against your branch. To check it before pushing, run `build-gems release-vX.Y.Z` as a smoke build; the gems you publish are rebuilt from the signed tag.

**PR.** First, from the release worktree, run `$MAIN/test/local-ci --all --base origin/X-Y-stable`. It takes about 40 minutes. It reruns each new failure on both commits and labels it. Each `REGRESSION` or job error is a **possible blocker**; bring it to the maintainer before pushing. For a release that carries unpublished advisory fixes, this is the only test matrix until disclosure.

**go**: push `release-vX.Y.Z` and open the PR. Then triage every failed job:

- Compare it with recent runs on the base branch. Failures that also happen on the base, or that pass on rerun, are flakes. **Flakes don't gate the release.** For a Linux job, `$MAIN/test/local-ci --only '<job name>' --base origin/X-Y-stable --repeat 10 -- <test_file>` settles it without a CI round trip.
- A failure in a test the release added or changed, or one that only happens on the release, is a **possible blocker**. Bring it to the maintainer with the job link and the failing test.

Done when every job has finished (the maintainer may waive slow ones) and every failure is classified.

## Publish

Each of these steps in Release.md needs a **go**: merging, pushing the tag, pushing the gems, publishing the GitHub release, and the PR to `main`.

To push the gems, ask the maintainer where their RubyGems API key is stored, then hand them one command that sets `GEM_HOST_API_KEY` from that source for this run only, e.g. `env GEM_HOST_API_KEY=(<read secret>) .agents/skills/releasing-puma/scripts/push-gems vX.Y.Z tmp/release/build-<sha>/pkg/*.gem`. If its key check fails with a 401, the key is revoked; the maintainer makes a new one scoped to push `puma`. If RubyGems already lists a gem, its SHA256 must match yours; leave it off the command.

Done when the verify step passes for every series.

## Security releases

The maintainer can publish an advisory only after its fix is on `main`. Plan this with the release, not after it. Each PR below needs a **go**.

1. After the gems are pushed, push each fix commit to `puma/puma` as branch `ghsa-<id>`. Open one PR per fix into `main`, starting "This PR puts the fix for [GHSA-…](link) on `main`" and naming the releases that have it.
2. Squash-merge each with its fix commit's message, so `Reported-by:` trailers survive.
3. Merge the **Patch releases** History PR from Release.md after the fixes.
4. Tell the maintainer the advisories are ready to publish.

## Gotchas

- `main` is protected and takes PRs only. Stable branches take direct fast-forward pushes.
- `git diff --no-ext-diff` whenever diff output goes to a file or into `git apply`; a configured external diff tool otherwise replaces the patch.
- `git describe --tags --abbrev=0 origin/X-Y-stable` finds the series' last release.
