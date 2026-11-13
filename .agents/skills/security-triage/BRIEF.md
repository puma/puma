# Pitching a claim

The maintainer knows Puma's Ruby code well. Assume no deep knowledge of HTTP, TLS, or the RFCs. Wherever a call depends on protocol mechanics (chunked bodies, trailers, keep-alive, framing), explain them from first principles in a few plain sentences, with a byte-level example.

Give evidence and reasoning the maintainer could defend at a whiteboard. Don't draft replies to the reporter: the maintainer writes those.

## Sections, in order

1. **What the report alleges**: what the attacker sends, what the reporter says happens, and which versions and configs they name. Report it without judging it yet.
2. **Background**: only the mechanics the rest needs.
3. **Evidence**: the exact commands and trimmed output, on `main` and each affected release.
4. **Scope**: the attacker, the reachable path with file:line references, and the quoted `SECURITY.md` clause.
5. **Versions**: when the bug was introduced (commit and PR), and the affected releases.
6. **CVSS 4.0**: the vector, with one line of reasoning per metric. Skip it if the claim is out of scope.
7. **What would change the call**: the specific evidence that would flip it, and whether you have already tested it.
8. **Recommendation**: close, public bug, or advisory, in one line, then why.
9. **Links**: every advisory involved, the private forks, and every issue, PR, and commit cited. Build URLs only from IDs you have.

## A queue

For several claims, open with a table ordered from easiest decision to hardest, with the recommendation and links for each. Pitch one claim at a time after that.
