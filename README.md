# Fitora Backend

Fitora — a multi-tenant gym/studio management platform (clients, bookings,
sessions, contracts, staff, payroll, attendance, and real-time notifications).
One Rails 8 app: the server-rendered web UI for every shell (admin, desk,
coach, member, superadmin, the landing page) and the JSON API the mobile app
calls (`/api/v1`).

## Stack

- **Ruby** 3.4.7 (see [.ruby-version](.ruby-version))
- **Rails** 8.1, with **Hotwire** (Turbo + Stimulus) for the web UI
- **jsbundling-rails** (esbuild) + **cssbundling-rails** (sass), served by **Propshaft**
- **PostgreSQL** — primary datastore, UUID primary keys everywhere
- **Redis** — Sidekiq queue backend + ActionCable pub/sub
- **Sidekiq** (+ `sidekiq-cron`) — background jobs (expiry scans, notification fan-out)
- **ActionCable** — real-time notifications
- **JWT** (`jwt` gem) — API authentication (the web UI uses the cookie session)
- **Kamal** — Docker-based deployment
- **Sentry** — error tracking (`sentry-ruby`, `sentry-rails`, `sentry-sidekiq`)

## Requirements

- Ruby 3.4.7 (use [rbenv](https://github.com/rbenv/rbenv)/[asdf](https://asdf-vm.com/) with the provided `.ruby-version`)
- PostgreSQL 14+
- Redis 6+
- Node.js 20 (builds the web UI's JavaScript and CSS)

## Setup

```bash
# Install dependencies
bin/setup --skip-server   # or: bundle install
npm ci

# Configure environment
cp .env.example .env      # then fill in local values as needed

# Create and migrate the database
bin/rails db:create db:schema:load
```

## Running the app

```bash
bin/dev                    # web UI + API on http://localhost:3000, asset watchers, Sidekiq, mailcatcher
```

`bin/dev` runs [Procfile.dev](Procfile.dev) with foreman. To run the server on
its own, build the assets once first:

```bash
npm run build && npm run build:css
bin/rails server
```

The Sidekiq dashboard is mounted at `/sidekiq` — open in development, or in
other environments once `SIDEKIQ_WEB_PASSWORD` is set (HTTP basic auth).

## Configuration

All runtime configuration is via environment variables — see
[.env.example](.env.example) for the full list and inline documentation
(datastores, CORS origins, SMS provider, Sentry, etc). Locally these are
loaded from `.env` by `dotenv-rails`; in production they're set on the host /
in the Kamal deploy config.

## Testing

The test suite uses RSpec, FactoryBot, and a real PostgreSQL test database.

```bash
bin/rails db:test:prepare   # first run / after schema changes
bundle exec rspec           # full suite
bundle exec rspec spec/models/client_spec.rb   # single file
```

Under CI (`CI=true`) the same run also fails on any N+1 query (Bullet) and on
line/branch coverage below the floor in `spec/spec_helper.rb` (SimpleCov,
report in `coverage/`). `COVERAGE=0` skips coverage for a quick local run.

### API contract

`doc/openapi.yaml` is written from the request specs, and CI fails if it no
longer matches the API. After changing what an endpoint accepts or returns:

```bash
rm doc/openapi.yaml && OPENAPI=1 COVERAGE=0 bundle exec rspec spec/requests --order defined
```

and commit the result.

## Linting & static analysis

```bash
bundle exec rubocop                 # style (Omakase Rails style + house cops in lib/rubocop/cop/fitora)
bundle exec brakeman --no-pager     # security static analysis
bundle exec bundle-audit check --update   # gems with a published advisory
```

## Continuous Integration

Every push and pull request runs lint, security scan, and the full test suite —
see [.github/workflows/ci.yml](.github/workflows/ci.yml).

## Deployment

Deployed as a Docker container via [Kamal](https://kamal-deploy.org/) — see
[config/deploy.yml](config/deploy.yml) and the [Dockerfile](Dockerfile).

```bash
bin/kamal deploy
```

Kamal builds the image from a clean checkout of the current commit, so commit
first. To build it by hand: `docker build -t fitora .` from this directory.

Production refuses to boot without `SMTP_*` and `APP_HOST`
(`config/initializers/required_env.rb`) — without mail, no admin can confirm
their address and nothing opens. Every secret the deploy needs is listed in
`.kamal/secrets.example`.

## Backups

The `backup` accessory in `config/deploy.yml` dumps the database nightly,
encrypts it with `PASSPHRASE`, and ships it to an S3-compatible bucket, kept
14 days. Restore one now and then — a backup nobody has restored is not a
backup:

```bash
bin/rails backup:restore_check FILE=path/to/backup.dump        # or .dump.gpg with PASSPHRASE set
```

It restores into a scratch database next to the real one, runs the
`Migration::Audit` invariants on it (orphans, cross-tenant references,
constraints), and drops it again.

## Project structure

- `app/controllers/web`, `app/views/web` — the server-rendered web UI, one namespace per shell; `app/javascript` its Stimulus controllers, `app/assets/stylesheets` its styles
- `app/controllers/api/v1` — versioned JSON API, namespaced by role where relevant (`superadmin/`, `admin/`, `me/`)
- `app/models` — the data and the business rules on it: booking, cancelling, selling a plan, taking a payment are model methods (`Session#book!`, `Booking#cancel!`, `Contract.sell!`, `Payment.collect!`, …). A rule a request breaks raises `ApplicationRecord::Refused`, which the API answers with a 422
- `app/lib` — code that isn't a business rule: PDF receipts and schedules, spreadsheet reports, dashboard figures, CSV import/export, JWT, the SMS gateway client
- `app/models/concerns` — shared model behavior (email verification, password reset, photo attachment)
- `app/jobs` — Sidekiq background jobs, mostly scheduled scans (see `config/sidekiq_cron.yml`)
- `app/policies` — authorization
- `app/serializers` — JSON response shaping
- `lib/rubocop/cop/fitora` — house Rubocop cops (e.g. tenant-scoping enforcement)
