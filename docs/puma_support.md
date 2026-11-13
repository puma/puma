# Puma Support Policy

## What

This document's purpose is to help users and contributors of this library make future plans based on the trajectory of this project. It is loosely worded and should be expected to change over time. Maintainers and contributors are encouraged to follow the guidance here but are not strictly bound by it.

## What does "supported" mean?

Puma is a community-run project. "Support" means "what do the maintainers pay attention to and what are they likely to merge", and doesn't mean that we do anything by any particular date, or even at all. We may all jet off to a private island tomorrow and never speak again.

But, if we do decide to keep devoting our free time to open source software, we will **support the environments (combinations of Ruby version, Ruby implementation, Rack version, and operating system) which run on our CI.**

If you open a PR or bug report for a combination of those factors outside of our CI matrix, we may still accept it if it's a small and low-risk fix.

We may add environments to CI at any time, but we only drop a supported environment in a minor or major release.

## Puma release support policy

By default, Puma supports one release version, the latest release. That means if there is a bug in 3.2.1 (made-up numbers for example only), but the latest release is 4.3.2, the bug must be reproduced in 4.3.2 to qualify for support.

When a new major (and sometimes minor) version is released, Puma maintainers will try to preserve the status of the old version via branches and/or tags. Puma maintainers can choose to backport fixes to older versions and cut a release of older versions, but this behavior should not be assumed.

If a bug report cannot be reproduced with the latest Puma version, it may be closed.

## Ruby version support policy

"Ruby version" refers to the https://github.com/ruby/ruby implementation. Puma also supports other Ruby implementations (the origin of Puma involves an alternate Ruby implementation, Rubinius); see below.

Ruby upstream support is documented at https://www.ruby-lang.org/en/downloads/branches/. A "minor" version is X.Y, with X.Y.Z being a patch release. Puma supports every Ruby minor version that is not EOL upstream. Puma may also continue to support older, EOL Ruby versions; the gemspec's `required_ruby_version` declares the oldest supported version. Maintainers decide when to raise that minimum. The Puma team recommends you always use the latest Ruby release.

When Puma supports a Ruby version, it will include that version in the CI matrix. CI runs only the most recent patch version of each supported Ruby minor version. If a bug is reported, the report must be reproducible using the most recent patch version of a currently supported Ruby minor version.

Puma may rely on upstream support to fix bugs in Ruby rather than working around them. That means, if a bug exists only in a Ruby version that is EOL upstream, it may be closed (it's not guaranteed that we will work around legacy Ruby issues).

When Puma does work around a bug in a specific Ruby patch version, the workaround stays until Puma drops support for that Ruby minor version.

## Alternate implementations of Ruby (version support policy)

An example of an "alternate" implementation of Ruby is JRuby. Ruby implementations typically target a specific "spec" of ruby/ruby, for example, JRuby 10.0 targets ruby/ruby version 3.4. The target version of a supported implementation must be within the above "Ruby version support policy." Additionally, the implementation release must be supported upstream.

Puma supports the JRuby implementation. Puma supports the TruffleRuby implementation.

## Rack (and SPEC) version support

From the current Rack documentation https://github.com/rack/rack?tab=readme-ov-file#version-support, Rack lists support levels to be:

- Bug fixes and security patches
- Security patches only
- End of support

Puma will support any Rack version that still accepts "bug fixes" in addition to security patches. Rack versions that receive only security patches, or are at end of support, are not supported.

Due to the need to support "hot" reloading applications (via phased restart) which might have different Rack versions, [Puma cannot directly declare the minimum Rack version](https://github.com/puma/puma/commit/537bc21593182cd9c4c0079a3936d05b1f91fe14). Puma may use runtime or boot time checks to warn or error about Rack version support.

## Bundler version support

Puma supports the Bundler version that ships with each supported Ruby version.

## How to use this document

You can use the guidelines here to make suggestions to contributors (anyone reporting an issue, helping with via a comment, or opening a PR) or maintainers. For example, "I could not reproduce your issue using a currently supported Ruby version. Can you please update to version X.Y and verify the issue persists?" Please link to this doc, state what action you're requesting, and why you feel that action is supported by this document. Please act in "good faith" and do not "bikeshed" (the practice of focusing on non-structural or seemingly irrelevant details).

## How to update this document?

Generally, you shouldn't suggest changes to policies in this document unless you have committed to the Puma project.

Non-committers:

- Spelling fixes are fine; do not re-grammar or "refactor" the wording.
- Updating stale details derived from the policies is fine. For example, if a canonical URL changes or if specific upstream versions are listed.

Committers:

- Suggest whatever policy changes you feel are appropriate.
- Suggest improvements to the wording or consistency or presentation of information.
- Do not merge policy changes without oversight of other "significant" contributors.
- When reviewing a policy change, please mark comments as either blocking or non/blocking. Please try to make blocking comments either satisfiable or falsifiable.

