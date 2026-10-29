# Continuous integration

Every pull request, every push to `master` (or `main`), every Monday at 06:00 UTC and any manual run (**Actions → CI → Run workflow**) runs [.github/workflows/ci.yml](../.github/workflows/ci.yml). Its six jobs run side by side, and each one shows as its own check on a pull request.

| Check | Job | What fails it |
|---|---|---|
| **Rubocop** | `lint` | A style offense, or one of the house cops in `lib/rubocop/cop/fitora`. One of those, `Fitora/UnscopedTenantQuery`, catches a query on a tenant model that does not start from the gym. Offenses show as annotations on the diff. |
| **Brakeman** | `security` | Any Brakeman warning, at any confidence, that `config/brakeman.ignore` does not list; also a file Brakeman could not parse. The HTML and JSON reports are the `brakeman` artifact. |
| **Bundler Audit** | `dependency-audit` | A gem version in `Gemfile.lock` with a published advisory in the [ruby-advisory-db](https://github.com/rubysec/ruby-advisory-db), fetched fresh on every run. |
| **Secret scan (Gitleaks)** | `secret-scan` | Something that looks like a credential, anywhere in the Git history: this pull request's commits and every commit before them. |
| **Migrations** | `migrations` | The migrations, run on an empty database, do not write the committed `db/schema.rb`. |
| **RSpec** | `rspec` | Any failing example; line coverage under 94 % or branch coverage under 78 % (`spec/spec_helper.rb`); an N+1 query (Bullet); or a `doc/openapi.yaml` that no longer matches the API. The JSON results and the coverage report are the `rspec` artifact. |

No job uses a secret or a deployment credential. CI talks to its own throwaway Postgres 16 and Redis 7 and nothing else. A pull request from a fork runs with a read-only token, as every `pull_request` run does. The workflow never uses `pull_request_target`.

The security regressions run with the rest of the suite. They are in `spec/requests/security/`: tenant isolation, role boundaries, impersonation, member identity and consent, rate limits, direct uploads, and the request-level ones. `spec/models/same_company_foreign_keys_spec.rb` checks that the database itself refuses a cross-gym link.

## Running the checks locally

```bash
bundle exec rubocop                                  # Rubocop
bundle exec brakeman --no-pager                      # Brakeman
bundle exec bundle-audit check --update              # Bundler Audit
gitleaks git --redact=100 --verbose .                # Secret scan (Gitleaks 8.30.1)
CI=1 bundle exec rspec                               # RSpec with the coverage floor
rm doc/openapi.yaml && OPENAPI=1 COVERAGE=0 bundle exec rspec spec/requests --order defined   # API contract

# Migrations: an empty database of its own, then compare
RAILS_ENV=test DATABASE_URL=postgres:///backend_migrations SCHEMA=tmp/schema.migrated.rb \
  bin/rails db:create db:migrate && diff -u db/schema.rb tmp/schema.migrated.rb
dropdb backend_migrations
```

To install Gitleaks, download the release binary from [github.com/gitleaks/gitleaks/releases](https://github.com/gitleaks/gitleaks/releases) and check it against the `checksums.txt` published with it.

## When a check fails

**Brakeman.** Fix the code. If the warning is a false positive, run `bundle exec brakeman -I` to add it to `config/brakeman.ignore`, with a note saying why. That ignores this one warning, not the check, and the change is reviewed in the pull request like any other. Never lower the confidence level or skip checks to get past it.

**Bundler Audit.** The output names the gem, the advisory and the versions that fix it.

1. `bundle update <gem> --conservative` moves only that gem, and its dependencies only where they must move.
2. If the fix is in a new major version, read the gem's upgrade notes first. Dependabot does not open those on its own.
3. Run the full suite, and commit `Gemfile.lock` on its own branch.

If no fixed version exists, read the advisory: is the vulnerable code reachable from Fitora? Record the decision in the pull request. `bundle-audit check --ignore <advisory id>` exists, but keep any ignore in CI temporary and dated.

**Secret scan.** The log names the file, line, commit and rule. The value itself is always redacted.

- **If it is a real secret, rotate it first**: revoke the key with whoever issued it and issue a new one. Deleting it from the file does not remove it from Git history. Anyone who cloned or forked the repository has it, and GitHub keeps unreachable commits for a while. Rewriting history (`git filter-repo`) helps only after rotation, and it needs a force push that every clone must follow.
- **If it is not a secret** (a test fixture, a character set), add that one finding's fingerprint (`commit:file:rule:line`, from the log or the `gitleaks` artifact) to `.gitleaksignore`, with the reason above it. Never ignore a whole file or rule: a new finding in the same file still has to fail.

**Migrations.** A migration was edited after it ran somewhere, or `db/schema.rb` was edited by hand. Write a new migration instead, run `bin/rails db:migrate`, and commit both files.

## Dependency updates

Dependabot ([.github/dependabot.yml](../.github/dependabot.yml)) opens pull requests every Monday for:

- **Bundler** — gems.
- **npm** — the web UI's build.
- **GitHub Actions** — the workflow's actions, pinned by commit SHA. Dependabot updates the SHA and the version comment together.

How it batches and limits them:

- Minor and patch releases come grouped, one pull request per ecosystem (Rails gems in a group of their own).
- A release is proposed once it is seven days old.
- No more than 2 to 5 pull requests are open per ecosystem.
- **Major versions are not proposed.** Upgrade them on purpose, with their notes read.
- **Security fixes are not held back by any of this.** An advisory opens its own pull request at once, major version or not, once Dependabot security updates are on (below).

Each Dependabot pull request runs the full CI. **Nothing merges automatically.** A dependency pull request holds only the dependency change.

Not covered by Dependabot:

- **The Ruby version.** Change `.ruby-version` and the Dockerfile's `ruby:` image together, since the Gemfile requires that exact Ruby.
- **The Dockerfile's `node:20-slim` and CI's Node 20.** Node 20 reached end of life in April 2026; moving to Node 22 or 24 should be its own change, with a Docker build to confirm it.
- **`config/deploy.yml`'s `postgres:16` and `redis:7`.**

## Making the checks required (GitHub settings)

**Settings → Rules → Rulesets → New branch ruleset** (or **Branches → branch protection rule**), on `master`:

- Require a pull request before merging, with at least one approval if anyone else works on the repository.
- Require status checks to pass, and pick **Rubocop**, **Brakeman**, **Bundler Audit**, **Secret scan (Gitleaks)**, **Migrations** and **RSpec**. They show in the list once the workflow has run once.
- Require branches to be up to date before merging.
- Block force pushes and deletions.

Elsewhere in **Settings**:

- **Security → Code security**:
  - turn on **Dependabot alerts** and **Dependabot security updates**;
  - turn on **Secret scanning** and **Push protection** where your plan offers them, as a second net in front of Gitleaks.
- **Actions → General**:
  - set **Workflow permissions** to *Read repository contents*;
  - for a public repository, require approval for workflows from outside collaborators.

CI needs no repository secrets.
