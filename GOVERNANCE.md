# Governance

## The Short Version

Evan Phoenix ([@evanphx](https://github.com/evanphx)) created Puma and has final say on everything. [Maintainers](./MAINTAINERS) serve at his pleasure.

## Access Levels

We have two levels of access and privileges:

### Gem Release Access

This is kept intentionally small for security reasons. If you can cut a gem release, you can push code to a lot of production systems, so we're intentionally quite narrow here.

**Current members:** Evan Phoenix ([@evanphx](https://github.com/evanphx)), Nate Berkopec ([@nateberkopec](https://github.com/nateberkopec)), and Richard Schneeman ([@schneems](https://github.com/schneems)).

We cut releases ~whenever we feel like it.

We may add or remove people from this group if releases start getting bottlenecked, but security is the priority.

### Commit Bit ("Maintainers" or "Core Team")

We give commit bit if you make significant contributions to minor (or major) releases, consistently over time. Show up, do good work, stick around.

We review this access periodically, but we're looser with it than gem release access.

If you have commit bit, we trust you enough to merge to `main` without necessarily getting review first.

While all [security reports go to Evan directly](./SECURITY.md), maintainers will collaborate together on the fix.

**Current members:** Everyone on the [Maintainers](./MAINTAINERS) list.

## How Decisions Get Made

Evan has final say on who gets these rights. Maintainers make suggestions and talk things through, but ultimately it's his call.

In general, Puma maintainership works on the principle of [lazy consensus](https://openoffice.apache.org/docs/governance/lazyConsensus.html).

We try to mostly work in public, so that more people outside the maintainer team can contribute and help out.

If you have questions or want to suggest changes to how we run things, open an issue.
