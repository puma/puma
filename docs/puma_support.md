# Puma Support Policy

## What

This document's purpose is to help users and contributors of this library make future plans based on the trajectory of this project. It is loosely worded and should be expected to change over time. Maintainers and contributors are encouraged to follow the guidance here but are not strictly bound by it.

## What does "not supported" mean?

Puma is a community-supported and run project. Support entitles the community to open issues and file PRs. It does not guarantee or warranty any action regarding those issues and PRs. All issues and PRs can be closed at a maintainer's discretion, regardless of whether they qualify under "support." If an issue falls outside of Puma support, maintainers are not obliged to keep it open, and if a PR falls outside of Puma support, maintainers are not obliged to review it.

## Puma release support policy

By default, Puma supports one release version, the latest release. That means if there is a bug in 3.2.1 (made-up numbers for example only), but the latest release is 4.3.2, the bug must be reproduced in 4.3.2 to qualify for support.

When a new major (and sometimes minor) version is released, Puma maintainers will try to preserve the status of the old version via branches and/or tags. Puma maintainers can choose to backport fixes to older versions and cut a release of older versions, but this behavior should not be assumed.

If a bug report cannot be reproduced with the latest Puma version, it may be closed.

## Ruby version support policy

 "Ruby version" refers to the https://github.com/ruby/ruby implementation. Puma also supports other Ruby implementations (the origin of Puma involves an alternate Ruby implementation, rubinius) see below.

Puma supports "Ruby upstream + 2 versions". Ruby upstream support is documented at this page https://www.ruby-lang.org/en/downloads/branches/. At this time of writing, it is 3 "major" versions, where a major version is X.Y with X.Y.Z being a patch release. If a Ruby version is not EOL, it is supported. Because we support "+ 2 versions", if 3.2 is the last non-EOL version, Puma will support 3.1 and 3.0 as well. The Puma team recommends you always use the latest Ruby release.

When Puma supports a Ruby version, it will include that version in the CI matrix. The gemspec specifies the minimum supported Ruby versions. If a bug is reported, the report must be reproducible on a currently supported Ruby version.

Puma may rely on upstream support to fix bugs in Ruby rather than working around them. That means, if a bug exists only in a "+2 version" that is no longer supported upstream, it may be closed (it's not guaranteed that we will workaround legacy Ruby issues).

## Alternate implementations of Ruby (version support policy)

An example of an "alternate" implementation of Ruby is JRuby. Ruby implementations typically target a specific "spec" of ruby/ruby, for example, JRuby 10.0.2.0 targets ruby/ruby version 3.4.2. The target version of a supported implementation must be within the above "Ruby version support policy." Additionally, the implementation release must be supported upstream.

Puma supports the JRuby implementation. Puma supports the TruffleRuby implementation.

## Rack (and SPEC) version support

From the current Rack documentation https://github.com/rack/rack?tab=readme-ov-file#version-support, Rack lists support levels to be:

- Bug fixes and security patches
- Security patches only
- End of support

Puma will support any Rack version that still accepts "bug fixes" in addition to security patches.

Due to the need to support "hot" reloading applications (via phased restart) which might have different Rack versions, [Puma cannot directly declare the minimum Rack version](https://github.com/puma/puma/commit/537bc21593182cd9c4c0079a3936d05b1f91fe14). Puma may use runtime or boot time checks to warn or error about Rack version support.

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

