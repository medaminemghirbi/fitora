# Angular ↔ Rails parity

The checks that a migrated page is the Angular page (MIGRATION_AUDIT_2026-10-15.md §12).
Nothing here runs in CI yet: the Angular app is a separate repository.

## Run

```sh
test/parity/serve.sh                      # terminal 1: both apps, frozen clock, parity data
node test/parity/run.mjs                  # terminal 2: screenshots → test/parity/output/report.html
node test/parity/behaviour.mjs            # keyboard, focus, debounce, tabs… (adds one member: reseed after)
```

`run.mjs` takes `--only=V5,V16a`, `--viewports=mobile,tablet,desktop`, `--locales=fr,ar` and
`--themes=light,dark`. It exits 1 when any capture differs by more than 0.1 % of its pixels or
in size.

## What makes the two captures comparable

- **One server, one database.** Rails on :3100 serves the API to Angular (:4300, e2e
  configuration) *and* the web UI, against `backend_parity_demo`: Studio Lumen
  (`demo:seed`) plus `lib/tasks/parity/fixtures.rb`. `tmp/parity.json` names the
  logins and salles.
- **One clock.** `FITORA_FROZEN_TIME` stops the server's clock (dev/test only,
  `config/initializers/frozen_clock.rb`); every page gets `page.clock.setFixedTime`.
- **One browser.** The same Chromium, 1× pixels, Africa/Tunis, `fr-FR` / `ar-TN`, reduced
  motion; captures wait for fonts, an idle network and no progress bar.
- **The same steps.** Each state in `states.mjs` is reached by the same clicks and typing in
  both apps. Only the salle in the URL differs (MIGRATION_AUDIT §8).
- **No masks.** Nothing is masked; a difference that is there by design is labelled with its
  MIGRATION_AUDIT §10 entry instead.

## Keeping the copies honest

`node test/parity/sync-from-angular.mjs` checks that the copied stylesheets and translation
files still match the Angular source (`--write` refreshes them).
`node test/parity/extract-date-words.mjs` regenerates `lib/web/date_words.json`, the month and
weekday words Angular and Chromium print, after an upgrade of either.
