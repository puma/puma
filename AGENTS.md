# Puma for agents

[`CONTRIBUTING.md`](CONTRIBUTING.md) is the rulebook for people and agents alike. This file adds what you cannot find by looking.

## Commands

```sh
bundle install && bundle exec rake compile      # once, and again after a change under ext/
bundle exec ruby test/test_binder.rb -n /name/  # one test, on its own
test/runner --unit                              # in-process tests, about 30 seconds
test/runner --integration                       # tests that spawn Puma, about 1 minute
bundle exec rake rubocop
test/local-ci --base main                       # Linux CI jobs in Docker, incl. JRuby and TruffleRuby; reports only failures new since main
```

On a machine with Docker and no Ruby: `docker build -f tools/Dockerfile -t puma-dev .`, then `docker run --rm puma-dev bundle exec ruby test/test_binder.rb`. The image copies the source, so rebuild after each change.

## Traps

- **Twin code.** The HTTP parser and TLS exist in C and in Java, both under `ext/puma_http11/`. A change to one needs the same change in the other.
- **Generated parsers.** `http11_parser.c` and `Http11Parser.java` come from the `.rl` files. Regenerate them as CONTRIBUTING "Ragel" describes; the `ragel` CI job fails on output from any other Ragel version or CPU architecture.
- **New files.** `test/test_gem_manifest.rb` fails until each new tracked file matches a pattern in `test/gem_manifest.rb`. `test/test_categories.rb` fails until a new process-spawning test file is listed in `test/categories.rb`.
- **Retries hide flakes.** CI reruns a failed test up to three times, so a timing-dependent test can pass on your PR and fail on later ones. Synchronize with a `Queue` or the `wait_for_server_to_*` helpers.
- **Ruby 3.0 is the floor.** RuboCop catches newer syntax; newer core methods fail only in the Ruby 3.0 CI jobs.
- **Docs-only changes.** Put `[ci skip]` in the PR title. `History.md` is written at release time, so leave it alone.
- **Private by default.** Everything in Ruby outside the config DSL is private API ([versioning](docs/puma_support.md#versioning)). Adding public surface needs a maintainer's agreement before the code.

## When to read more

- Before writing code that will become a pull request, and when CI is red or a review arrives on one: follow [`.agents/skills/pull-request/SKILL.md`](.agents/skills/pull-request/SKILL.md).
- A suspected vulnerability: stop, keep it out of public issues and PRs, and tell your operator to report it as [`SECURITY.md`](SECURITY.md) describes. Maintainers triaging a report use [`.agents/skills/security-triage/SKILL.md`](.agents/skills/security-triage/SKILL.md).
- Cutting a release or backporting: [`.agents/skills/releasing-puma/SKILL.md`](.agents/skills/releasing-puma/SKILL.md).
