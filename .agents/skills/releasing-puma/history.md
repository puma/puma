# History.md format

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

- Use only the groups the release needs, in the order above. Minor and major releases also use `* Breaking changes`, `* Refactor` and `* Docs`; copy the previous minor release's layout.
- One line per change, newest first, written for users: what changed in behaviour, not how.
- List every PR that changed app or library code (`lib/`, `ext/`, `bin/`). PRs that only touch tests or CI are left out.
- Cite the PR on `main` even when the stable branch received it through a backport PR.
- A security line cites its GHSA as a full link. Once a CVE is assigned, it goes beside the GHSA.

## Link definitions

Each `[#NNNN]` the section uses needs a definition. Add new ones directly above the existing ones near the bottom of the file, in the same order as the section:

```markdown
[#4101]:https://github.com/puma/puma/pull/4101     "PR by Nate Berkopec, merged 2026-11-13"
```

The author is the PR's author and the date is the date it merged to `main`: `git log -1 --format='%an %cs' <merge sha>`.
