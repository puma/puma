# How to Release Puma

Scripts live in `.agents/skills/releasing-puma/scripts/` on `main`. Run them from a `main` checkout, even for a stable release; they need git, Ruby and Docker. Release several series newest first (8.x before 7.x).

## Prepare

1. **Plan.** Choose the base: `main` for a major or minor release, `<major>-<minor>-stable` for a patch release on an existing stable line (for example, `7.2.3` from `7-2-stable`). Fetch it and check that CI on its tip passes. Decide on the next version number based on [SemVer 2.0](https://semver.org/). For details about what we consider a breaking change, see [Versioning](docs/puma_support.md#versioning). List the fixes to ship as commits on `main`, oldest first. A fix that isn't on `main` yet goes to `main` first.
1. **Backport (patch releases).** On a branch named `release-vX.Y.Z` from the stable branch, `git cherry-pick -x` each commit. Resolve conflicts so behavior matches `main`, and port each commit's tests. Skip a commit only when the code it fixes doesn't exist on the branch.
1. **Release commit.** On `release-vX.Y.Z`, one commit titled `Release vX.Y.Z` that changes `lib/puma/const.rb` and `History.md` (format below).
   - Minor and major releases also set the codename; see [the Namer](#the-namer).
   - Major releases also update `SECURITY.md` and add a `docs/upgrading/X.0-Upgrade.md` upgrade guide.
1. **PR.** Open a PR from `release-vX.Y.Z` into the base. The `Release Checks` workflow checks the version, codename, History section and links. **STOP** until at least one human has reviewed it and CI has finished.

## Publish

1. Merge the PR.
1. Sign the merge commit's tag, check it and push it: `git tag -s vX.Y.Z -m "Release vX.Y.Z" <merge commit>`, `git tag -v vX.Y.Z`, `git push origin vX.Y.Z`.
1. `build-gems vX.Y.Z` builds both gems from the tag in pinned Docker images, checks every packaged file against the tag, and writes `SHA256SUMS`. Builds are byte-identical on any machine. The `build-gems` workflow runs the same script on the tag push; its job summary's `SHA256SUMS` must equal yours.
1. `GEM_HOST_API_KEY=<key> push-gems vX.Y.Z tmp/release/build-<sha>/pkg/*.gem` refuses unless the tag is signed, is on GitHub, and every gem matches it. Then it asks for one OTP and pushes every gem.
1. Run the `release` workflow with input `tag: vX.Y.Z` (a tag cut from `main` also starts it on push). It builds both gems from the tag and makes a draft GitHub release with the notes from `release-notes` and both gems attached. Run it again after `push-gems`: when RubyGems has both gems with the SHA256s of the tag build, it publishes the release, and marks it latest only if it is the highest version. It stops if RubyGems has different gems.
1. Verify that `https://rubygems.org/api/v1/versions/puma.json` lists both platforms with your SHA256s, and that the GitHub release assets match them.
1. **Patch releases:** open a PR to `main` that adds the new History section and its link definitions, in version order (8.x sections above 7.x). If `VERSION` on `main` is in the released series, the PR also sets it to the new version.

## The "Namer"

We usually let the leader of `git shortlog -s -n --no-merges <LAST_VERSION>..HEAD` name the release.

Tag this person on the new version PR and ask them to propose a codename.

## History.md format

New section at the very top of the file:

```markdown
## X.Y.Z / YYYY-MM-DD

* Security
  * One sentence describing the fix. ([GHSA-xxxx-xxxx-xxxx](https://github.com/puma/puma/security/advisories/GHSA-xxxx-xxxx-xxxx))

* Features
  * One sentence describing the change ([#NNNN])

* Bugfixes
  * One sentence describing the fix ([#NNNN])

* Performance
  * One sentence describing the change ([#NNNN])
```

- `* Security` is only for fixes to vulnerabilities with an advisory, and always goes first. Hardening without an advisory goes in `* Security (Hardening)`, after `* Features`.
- Use only the groups the release needs, in the order above. Minor and major releases also use `* Breaking changes`, `* Refactor` and `* Docs`; copy the previous minor release's layout.
- One line per change, newest first, written for users: what changed in behavior, not how.
- List every PR that changed app or library code (`lib/`, `ext/`, `bin/`). PRs that only touch tests or CI are left out.
- Cite the PR on `main` even when the stable branch received it through a backport PR.
- A security line cites its GHSA as a full link. Once a CVE is assigned, it goes beside the GHSA.

Each `[#NNNN]` the section uses needs a link definition. Add new ones directly above the existing ones near the bottom of the file, in the same order as the section:

```markdown
[#4101]:https://github.com/puma/puma/pull/4101     "PR by Nate Berkopec, merged 2026-11-13"
```

The author is the PR's author and the date is the date it merged to `main`: `git log -1 --format='%an %cs' <merge sha>`.
