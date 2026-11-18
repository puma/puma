---
name: pull-request
description: Take a Puma change from idea to a mergeable pull request. Use before writing code for a bug fix, feature, performance or docs change bound for puma/puma, and when answering review comments or red CI on one.
---

# Pull request

Maintainer review time is the scarce resource. A pull request earns it by being the only one for its problem, small, and proven by commands you ran.

[`CONTRIBUTING.md`](../../../CONTRIBUTING.md) "Pull requests" holds the rules. This skill is the order to apply them in. The **operator** is the person you work for: they answer for the PR, and they approve every GitHub write.

## Steps

1. **Search.** Search puma/puma issues and pull requests, open and closed, for the issue number and for the method, option or error text involved. Read the issue's whole thread. Done when you can list every PR that has touched this problem, with its state, and every maintainer decision in the thread. An open PR that covers the problem, or a maintainer decision against the change, ends the work: report it to the operator and offer to test or review the existing PR. If the operator is not listed in `MAINTAINERS` and already has a PR in puma/puma waiting for review, ask before starting another.
2. **Reproduce.** Branch from a fresh `origin/main`. Done when the problem shows on that commit and you have saved the command and its output. For a performance change, the reproduction is the benchmark that CONTRIBUTING "Performance changes" asks for. For a docs change, it is each claim checked against the code. A problem that does not show on `main` is already fixed: report the commit that fixed it and stop.
3. **Scope.** State the change in one sentence. A second clause is a second PR. A new option, hook or public method, or a changed default, needs a maintainer to agree first: draft the interface as an issue comment for the operator to post, and wait for the answer.
4. **Red.** Write the test before the fix and run it on its own against `main`. Done when it is red on the assertion that states the bug, not on a missing `require` or a timeout. Commit the tests alone, as CONTRIBUTING "Pull requests - bug fixes" describes.
5. **Fix.** Make the smallest change that turns the test green, in the idiom of the surrounding code.
6. **Verify.** Run each command in [`AGENTS.md`](../../../AGENTS.md) "Commands" against the final diff, and `test/local-ci --base main` where Docker is available. Done when every command has run and each failure is either fixed or shown to fail the same way on `main`. Code you could not run stays out of the PR: tell the operator what the machine lacks.
7. **Trim.** Read the final diff hunk by hunk against the sentence from step 3 and every rule in CONTRIBUTING "Pull requests". Done when each hunk is needed for that sentence and each remaining comment says something the code cannot.
8. **Describe.** The title is a plain sentence that says what changes, plus `[ci skip]` for a docs-only change. The description's first line is `_This is AI-assisted. Model: <model id>_`. Then it states the problem, the change, why this approach, and the evidence from steps 2, 4 and 6 as commands with their output before and after. It links the issue with "Closes #N" and each related PR from step 1. Write over the template's prompt text, and tick only the checklist boxes that are true. Done when a reviewer who has never seen the issue can judge the PR in one minute of reading.
9. **Hand over.** Give the operator the diff, the description, and a list of anything you could not verify. Done when the operator has told you to open the PR.
10. **Follow through.** After each push, check CI. For each red job, name the failing test, then run it on `main` or find a run on `main` that fails the same way. Answer each review comment with a new commit or a reply, and rebase on `main` when a maintainer asks. Done when CI is green or every red job has that evidence posted in one comment, and every review comment has an answer.
