# Writing a Puma security advisory

Base it on Puma's published GHSAs; GHSA-2vqw-3mp8-cgmx and GHSA-qpgp-93vx-g8v8 show the house style. Write as if the patched versions have already shipped. The reader is a Puma user who has seen nothing but this advisory: not the report, not this triage.

## Title

`<Feature or component> <does what wrong> [leading to <impact>]`

- Leave out "Puma". The package field already names it.
- Use sentence case.
- Good: "PROXY protocol v1 parser allows remote memory exhaustion"
- Good: "Header normalization allows clients to clobber proxy-set headers"
- Avoid generic titles such as "HTTP request smuggling vulnerability".

## Sections, in order

### Impact

1. One sentence: who is affected, and what an attacker can do.
2. If the bug is in an optional feature, when it was added, with a link to the PR or issue.
3. The mechanism, in two to four sentences: what Puma does, what it should do, and what an attacker sends.
4. The consequence for applications, such as a spoofed `REMOTE_ADDR`, an OOM, or another user's response.
5. A "What configurations are affected" heading, followed by the exact config that enables the bug. Say plainly whether the default config is affected.

### Patches

"Users should upgrade to versions X or Y." Give one patched version per supported major. When upgrading requires a config change (for example, a self-signed certificate), give it its own paragraph with example config.

### Workarounds

Give config changes users can make today, as code blocks, including proxy-side mitigations. Write "No known workarounds." only when that is true.

### Possible breakage

Include this when relevant: the legitimate traffic or config the fix now rejects.

### References

The spec or RFC, related CVEs in other servers, Puma's docs for the feature, and the relevant source file.

### Acknowledgements

The reporter and any reviewers, by GitHub handle.

## Metadata

- **Affected versions:** the patched version of each supported major as the bound, as in `<7.2.1, <8.0.2`. Don't research the first affected version.
- **CVSS:** use 4.0. Score the default config, unless only a non-default config is affected. In that case, score that config and name it in Impact.
- **CWE:** smuggling is CWE-444. Resource exhaustion is CWE-400, or CWE-770 for a missing limit. Header injection is CWE-113. Spoofing is CWE-290 or CWE-345.

## Tone

Plain and specific. No marketing words such as "critical flaw". Once exploitability is proven, don't hedge about it. Say what is and isn't affected.
