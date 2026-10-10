# Security

This repository is public because the reusable workflows and actions are consumed
by private repositories across the organization. Everything here is readable by
anyone, and anyone can open a pull request. The rules below follow from that.

## Rules for this repository

1. **Generic logic only.** No account ids, ARNs, client names, hostnames or
   secrets. They are variables and secrets of the consuming repositories.
2. **Own CI on GitHub-hosted runners only.** `self-test.yml`, `release.yml` and
   `chart-release.yml` run on `ubuntu-latest`. A fork's pull request runs this
   repository's workflows, so a self-hosted label here would give anyone code
   execution on our AWS-connected runners. The reusable workflows default to the
   self-hosted pools for their callers; the self-test redirects them with
   `runs-on-override`, which exists for that purpose only.
3. **No `pull_request_target`.** It runs with a write token and secrets in the
   context of untrusted code.
4. **Third-party actions pinned by full commit SHA**, with the version in a
   comment. Dependabot updates both together.
5. **Least privilege.** Workflow-level `permissions` is read-only or empty; each
   job asks for what it uses. `id-token: write` appears only where an AWS role is
   assumed.
6. **No secrets in logs.** Git authentication uses an HTTP header, not a token in
   a URL. Secrets reach reusable workflows only through `secrets: inherit`.
7. **Releases are gated.** Chart publishing runs only in the `release`
   environment, which requires reviewer approval, and only from this repository.
8. **No secret in the history.** The self-test job `gitleaks (full history)` scans
   every non-merge commit of every branch on each pull request and push to
   `main`, and fails on any finding. A secret that reaches a commit is public for
   good: rotate it first, then rewrite the history.

## What an org owner must configure (cannot be done from here)

- The self-hosted runner group used by the fleet must **not** allow public
  repositories ("Allow public repositories" off). This is the control that makes
  rule 2 hold even if someone adds a self-hosted label by mistake.
- Organization variables `DELIVERY_*` scoped to private repositories, so this
  public repository never receives them.
- A tag ruleset on this repository restricting who can create `v*` and
  `minca-service-*` tags, since a tag is a release.
- Branch protection on `main` requiring the self-test checks (including
  `gitleaks (full history)`) and a code-owner review.
- Actions setting "Fork pull request workflows from outside collaborators":
  require approval for all outside collaborators.

## Reporting

Report a vulnerability privately through GitHub's "Report a vulnerability" on this
repository, not in a public issue.
