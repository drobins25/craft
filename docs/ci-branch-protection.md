# Making the CI checks required on `main`

This is a runbook, not a reference page: an ordered procedure the repo admin
(drobins25 - the sole admin) follows once, where the output of each step feeds
the next. Applying branch protection is a human action; no agent or automation
applies it. Follow the steps in order - step 2 is dangerous without step 1.

Context: `.github/workflows/ci.yml` runs eight jobs on every pull request
targeting `main`. Seven are blocking suites; making them *required checks*
is what turns a red job into a blocked merge button. Until then, a PR with
failing checks still shows a green merge button to anyone who does not
scroll.

## The checks

Required - these seven job ids, exactly as they appear in the workflow file
(the job id IS the check name; there is no `name:` override):

- `dashboard`
- `hooks`
- `lifecycle`
- `flows`
- `misc`
- `doc-drift`
- `template-stamp`

`browser` is deliberately NOT required. It is the one job that needs
installed software (the runner's Chrome) and the one whose Linux behavior
was unproven when it shipped; it reports its result on every PR but never
blocks a merge. If it proves solid over time, promoting it is a one-line
addition to the `checks` array below - a later decision, on purpose.

## Step 1 - read what is there (do this first, save the output)

`main` already carries a classic branch protection rule whose contents are
not readable by non-admin accounts. Do not write anything until you have
read and saved what exists:

```
gh api repos/drobins25/craft/branches/main/protection
```

Save that output to a file before changing anything. Everything in it is
configuration you chose at some point; step 3's fallback needs it verbatim.

## Step 2 - the safe apply (status checks already enabled)

The sub-resource endpoint touches ONLY the status-check settings and leaves
every other protection setting alone:

```
gh api --method PATCH repos/drobins25/craft/branches/main/protection/required_status_checks \
  --input - <<'EOF'
{
  "strict": false,
  "checks": [
    {"context": "dashboard"},
    {"context": "hooks"},
    {"context": "lifecycle"},
    {"context": "flows"},
    {"context": "misc"},
    {"context": "doc-drift"},
    {"context": "template-stamp"}
  ]
}
EOF
```

About `strict: false` (GitHub's "require branches to be up to date before
merging"): recommended OFF. On, every green PR that outlives another merge
to main demands an update-branch plus a full re-run of all eight jobs before
the merge button unblocks - overt friction on a repo where the maintainer
merges frequently. Off accepts a small window where two PRs green against
the same base merge in sequence and conflict semantically on main; because
CI is PR-only, that breakage surfaces on the NEXT PR's checks rather than
immediately. On a repo with one admin, low PR concurrency, and a fast
suite, that window is small - and if it ever bites, `strict` is a one-field
flip using this same command.

## Step 3 - if step 2 returns 404 (status checks not enabled at all)

The PATCH endpoint 404s when the protection rule has no status-check block
yet. The only way to add one is the full-object endpoint - and that is the
trap: `PUT .../branches/main/protection` REPLACES THE ENTIRE PROTECTION
OBJECT. Anything you do not include in the payload is silently dropped.
The next admin who finds this endpoint on their own six months from now:
this paragraph is for you.

Assemble the payload FROM the step-1 output - carry over every field it
showed (`required_pull_request_reviews`, `enforce_admins`, `restrictions`,
and anything else present), and add the status-check block:

```
gh api --method PUT repos/drobins25/craft/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": false,
    "checks": [
      {"context": "dashboard"},
      {"context": "hooks"},
      {"context": "lifecycle"},
      {"context": "flows"},
      {"context": "misc"},
      {"context": "doc-drift"},
      {"context": "template-stamp"}
    ]
  },
  "enforce_admins": <carry over from step 1>,
  "required_pull_request_reviews": <carry over from step 1, or null>,
  "restrictions": <carry over from step 1, or null>
}
EOF
```

The `<carry over>` placeholders are not optional decoration - fill each one
from the saved step-1 output before running this. If step 1 showed a field
this template does not list, add it.

## Step 4 - verify

Open a pull request (any small change). Confirm:

1. The seven required checks and `browser` all appear in the PR's checks
   section.
2. The merge button is blocked while any required check is red or pending.
3. `browser` reports a result but a red `browser` does not block the merge.

`tests/test-ci-workflow.sh` keeps this document and the workflow's job ids
in agreement - if a job is ever renamed in `ci.yml`, that test fails until
this file (and the protection rule, by re-running step 2) catch up.
