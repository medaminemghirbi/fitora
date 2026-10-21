// The pilot's visual-regression suite (MIGRATION_AUDIT §12): every state in
// states.mjs, captured in the Angular reference and in the Rails web UI under
// identical conditions, diffed pixel by pixel, written up as an HTML report.
//
//   test/parity/serve.sh                  # both apps, frozen clock, parity data
//   node test/parity/run.mjs              # everything
//   node test/parity/run.mjs --only=V5,V16a --viewports=desktop --locales=fr --themes=light
//
// Output: test/parity/output/report.html (+ the images beside it).
// Exit code 1 when any capture is over the threshold or differs in size.
import { execFileSync } from "node:child_process"
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { chromium } from "playwright"
import pixelmatch from "pixelmatch"
import { PNG } from "pngjs"
import { STATES, VIEWPORTS } from "./states.mjs"

const BACKEND = join(dirname(fileURLToPath(import.meta.url)), "../..")
const OUTPUT = process.env.PARITY_OUTPUT ?? join(BACKEND, "test/parity/output")
const APPS = { angular: process.env.PARITY_ANGULAR ?? "http://localhost:4300", rails: process.env.PARITY_RAILS ?? "http://localhost:3100" }
const FROZEN_AT = process.env.FITORA_FROZEN_TIME ?? "2026-10-14T10:00:00+01:00"
const DATABASE_URL = process.env.PARITY_DATABASE_URL ?? "postgres:///backend_parity_demo"
// Pass: at most this share of the pixels differ (§12.2), and the same size.
const THRESHOLD = Number(process.env.PARITY_THRESHOLD ?? "0.001")
const BROWSER_LOCALES = { fr: "fr-FR", ar: "ar-TN", en: "en-US" }

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, "").split("=")))
const list = (value, all) => (value ? value.split(",") : all)
const only = args.only ? new Set(args.only.split(",")) : null
const locales = list(args.locales, ["fr", "ar"])
const themes = list(args.themes, ["light", "dark"])
const viewportNames = list(args.viewports, Object.keys(VIEWPORTS))
const fixtures = JSON.parse(readFileSync(join(BACKEND, "tmp/parity.json"), "utf8"))

function railsTask(name) {
  try {
    execFileSync("bin/rails", [`parity:state[${name}]`], {
      cwd: BACKEND, stdio: "pipe", encoding: "utf8",
      env: { ...process.env, DATABASE_URL, FITORA_FROZEN_TIME: FROZEN_AT, DISABLE_RACK_ATTACK: "1" },
    })
  } catch (error) {
    throw new Error(`parity:state[${name}] failed:\n${error.stderr}`)
  }
}

// Emailed-link tokens, one set per app (parity:state[tokens]).
const tokens = () => JSON.parse(readFileSync(join(BACKEND, "tmp/parity-tokens.json"), "utf8"))

// What undoes a parity:state.
const RESETS = { trial_3: "trial_14", trial_0: "trial_14", lock: "unlock", lac_catalogue: "lac_empty", lac_onboarding_activities: "lac_empty", lac_onboarding_plans: "lac_empty", lac_team: "lac_team_empty", pro: "pro_off" }

// The Angular route, or its Rails twin with the salle in the path (§8.1).
// A state's path may depend on the app (its own token).
function urlFor(app, state) {
  const salle = fixtures.salles[state.salle ?? "lumen"]
  const raw = typeof state.path === "function" ? state.path(app, tokens()[app], fixtures) : state.path
  const shell = raw.match(/^\/(admin|desk|coach)\//)?.[1]
  const path = app === "rails" && shell ? raw.replace(`/${shell}/`, `/${shell}/${salle}/`) : raw
  return APPS[app] + path
}

async function settle(page) {
  await page.waitForLoadState("networkidle")
  await page.evaluate(() => document.fonts.ready)
  // Neither progress bar (ngx-progressbar, Turbo's) still on screen.
  await page.waitForFunction(() => !document.querySelector("ng-progress.ng-progress-bar-active") && !document.querySelector(".turbo-progress-bar"))
  await page.waitForTimeout(300)
}

const browser = await chromium.launch()
const chromiumVersion = browser.version()
const contexts = new Map()

// One signed-in context per app × login × locale × theme, reused across
// states the way a person keeps one browser open.
// A salle other than the account's own gets a browser of its own: the
// Angular app caches the user a tab last loaded in localStorage, and a new
// tab then opens on that tab's salle (MIGRATION_AUDIT §10, B-05).
// Memoised as a promise: the viewports of a state ask for it at once.
function contextFor(app, login, locale, theme, salle = "lumen") {
  const key = [app, login, locale, theme, salle].join("|")
  if (!contexts.has(key)) contexts.set(key, openContext(app, login, locale, theme))
  return contexts.get(key)
}

async function openContext(app, login, locale, theme) {
  const context = await browser.newContext({
    locale: BROWSER_LOCALES[locale], timezoneId: "Africa/Tunis", colorScheme: theme, reducedMotion: "reduce", deviceScaleFactor: 1,
    viewport: VIEWPORTS.desktop,
  })
  // Each app's own way of remembering language and theme.
  if (app === "angular") {
    await context.addInitScript(({ locale, theme }) => {
      localStorage.setItem("fitora_locale", locale)
      localStorage.setItem("fitora_theme", theme)
    }, { locale, theme })
  } else {
    await context.addCookies([
      { name: "fitora_locale", value: locale, url: APPS.rails },
      { name: "fitora_theme", value: theme, url: APPS.rails },
    ])
  }

  if (!login) {
    // A browser that has been here before: one session for every page it
    // then opens at once. Three first requests at the same moment would each
    // start a session of their own, and only one CSRF token would match.
    // The clock is installed here too, once: its first install in a context
    // racing on three pages at once leaves some without it (Playwright's
    // TypeError "reading 'controller'"), as the signed-in branch avoids.
    const page = await context.newPage()
    await page.clock.setFixedTime(new Date(FROZEN_AT))
    await page.goto(`${APPS[app]}/connexion`)
    await page.close()
  } else {
    const page = await context.newPage()
    await page.clock.setFixedTime(new Date(FROZEN_AT))
    await page.goto(`${APPS[app]}/connexion`)
    const { email, password } = fixtures.logins[login]
    await page.locator("#email").fill(email)
    await page.locator("#password").fill(password)
    await page.locator("button[type=submit]").click()
    await page.waitForURL((url) => !url.pathname.startsWith("/connexion"))
    await settle(page)
    await page.close()
  }
  return context
}

async function capture(app, state, viewport, locale, theme, file) {
  try {
    return await captureIn(app, state, viewport, locale, theme, file)
  } catch (error) {
    throw new Error(`${app}: ${error.message.split("\n")[0]}`)
  }
}

async function captureIn(app, state, viewport, locale, theme, file) {
  const context = await contextFor(app, state.login, locale, theme, state.salle)
  const page = await context.newPage()
  const errors = []
  page.on("pageerror", (error) => errors.push(error.message))
  await page.setViewportSize(VIEWPORTS[viewport])
  await page.clock.setFixedTime(new Date(FROZEN_AT))
  if (app === "angular" && state.salle) {
    // The tab's salle (active-company.ts), as a tab opened on it would have.
    await page.addInitScript((id) => sessionStorage.setItem("fitora_company_id", id), fixtures.salles[state.salle])
  }
  await page.goto(urlFor(app, state))
  await settle(page)
  if (state.steps) await state.steps({ page, app })
  await page.locator(state.ready).first().waitFor({ state: state.readyState ?? "visible", timeout: 15_000 })
  await settle(page)
  const buffer = await page.screenshot({ path: file, fullPage: true, animations: "disabled", caret: "hide" })
  await page.close()
  return { png: PNG.sync.read(buffer), errors }
}

function compare(a, b, file) {
  if (a.width !== b.width || a.height !== b.height) {
    return { ratio: 1, pixels: null, size: `${a.width}×${a.height} vs ${b.width}×${b.height}` }
  }
  const diff = new PNG({ width: a.width, height: a.height })
  const pixels = pixelmatch(a.data, b.data, diff.data, a.width, a.height, { threshold: 0.1 })
  writeFileSync(file, PNG.sync.write(diff))
  return { ratio: pixels / (a.width * a.height), pixels, size: `${a.width}×${a.height}` }
}

rmSync(OUTPUT, { recursive: true, force: true })
mkdirSync(OUTPUT, { recursive: true })
const results = []

try {
  for (const locale of locales) {
    // The salles' own language: the Angular app re-applies it on every load,
    // and the Rails one at sign-in (MIGRATION_AUDIT §10, M-02).
    railsTask(`locale_${locale}`)
    for (const context of contexts.values()) await (await context).close()
    contexts.clear()

    for (const theme of themes) {
      for (const state of STATES) {
        if (only && !only.has(state.id)) continue
        for (const name of state.db ?? []) railsTask(name)
        try {
          // A state's viewports are captured side by side, each its own page —
          // except a state that spends a token, which gets fresh ones for each.
          const viewports = (state.viewports ?? viewportNames).filter((v) => viewportNames.includes(v))
          const each = async (viewport) => {
            const stem = `${locale}-${theme}-${state.id}-${viewport}`
            const files = Object.fromEntries(["angular", "rails", "diff"].map((k) => [k, `${stem}-${k}.png`]))
            let outcome
            try {
              const settled = await Promise.allSettled([
                capture("angular", state, viewport, locale, theme, join(OUTPUT, files.angular)),
                capture("rails", state, viewport, locale, theme, join(OUTPUT, files.rails)),
              ])
              const failed = settled.filter((s) => s.status === "rejected").map((s) => s.reason.message)
              if (failed.length) throw new Error(failed.join(" / "))
              const [angular, rails] = settled.map((s) => s.value)
              outcome = { ...compare(angular.png, rails.png, join(OUTPUT, files.diff)), errors: [...angular.errors.map((e) => `angular: ${e}`), ...rails.errors.map((e) => `rails: ${e}`)] }
            } catch (error) {
              outcome = { ratio: 1, pixels: null, size: "—", errors: [`capture failed: ${error.message.split("\n")[0]}`] }
            }
            const pass = outcome.pixels !== null && outcome.ratio <= THRESHOLD
            return { stem, row: { state, locale, theme, viewport, files, pass, ...outcome } }
          }
          let rows = []
          if (state.freshTokens || state.serial) {
            for (const viewport of viewports) {
              if (state.freshTokens) railsTask("tokens")
              rows.push(await each(viewport))
            }
          } else {
            rows = await Promise.all(viewports.map(each))
          }
          for (const { stem, row } of rows) {
            results.push(row)
            console.log(`${row.pass ? "pass" : "FAIL"}  ${stem.padEnd(36)} ${row.pixels === null ? row.size : `${(row.ratio * 100).toFixed(3)} %`}${state.register ? `  [${state.register}]` : ""}${row.errors.length ? `  ${row.errors.join("; ")}` : ""}`)
          }
        } finally {
          for (const name of state.db ?? []) if (RESETS[name]) railsTask(RESETS[name])
        }
      }
    }
  }
} finally {
  await browser.close()
  // Leave the data as serve.sh seeded it (French salles).
  if (locales.at(-1) !== "fr") railsTask("locale_fr")
}

writeFileSync(join(OUTPUT, "report.html"), report(results))
writeFileSync(join(OUTPUT, "results.json"), JSON.stringify(results.map(({ state, files, ...r }) => ({ id: state.id, title: state.title, register: state.register ?? null, ...r, files })), null, 2))
const failed = results.filter((r) => !r.pass)
console.log(`\n${results.length - failed.length}/${results.length} within ${(THRESHOLD * 100).toFixed(1)} %. Report: ${join(OUTPUT, "report.html")}`)
process.exitCode = failed.length ? 1 : 0

function report(rows) {
  const escape = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c])
  const sorted = [...rows].sort((a, b) => b.ratio - a.ratio)
  const passed = rows.filter((r) => r.pass).length
  const body = sorted.map((r) => `
    <section class="${r.pass ? "pass" : "fail"}">
      <h2>${r.pass ? "✓" : "✗"} ${escape(r.state.id)} — ${escape(r.state.title)} <small>${r.locale} · ${r.theme} · ${r.viewport} · ${r.size}</small></h2>
      <p>${r.pixels === null ? "not compared" : `${r.pixels} px differ (${(r.ratio * 100).toFixed(3)} %)`}${r.state.register ? ` · by design: <b>${escape(r.state.register)}</b> (MIGRATION_AUDIT §10)` : ""}${r.errors.length ? ` · <span class="err">${escape(r.errors.join("; "))}</span>` : ""}</p>
      <div class="imgs"><figure><figcaption>Angular</figcaption><img loading="lazy" src="${r.files.angular}"></figure><figure><figcaption>Rails</figcaption><img loading="lazy" src="${r.files.rails}"></figure><figure><figcaption>Diff</figcaption><img loading="lazy" src="${r.files.diff}"></figure></div>
    </section>`).join("")
  return `<!doctype html><html><head><meta charset="utf-8"><title>Parity report</title><style>
    body{font:14px system-ui,sans-serif;margin:24px;background:#f7f5fb;color:#1d1533}
    section{background:#fff;border:1px solid #e8e3f2;border-radius:10px;padding:12px 16px;margin:12px 0}
    section.fail{border-color:#d21f3c} h2{font-size:15px;margin:0 0 4px} small{color:#5a5175;font-weight:400}
    .imgs{display:grid;grid-template-columns:repeat(3,1fr);gap:8px} figure{margin:0} img{width:100%;border:1px solid #e8e3f2}
    figcaption{font-size:12px;color:#5a5175} .err{color:#d21f3c}</style></head><body>
    <h1>Angular ↔ Rails parity — ${passed}/${rows.length} within ${(THRESHOLD * 100).toFixed(1)} %</h1>
    <p>Frozen at ${escape(FROZEN_AT)} · Chromium ${escape(chromiumVersion)} · pixelmatch threshold 0.1, anti-aliasing excluded · sorted worst first.</p>
    ${body}</body></html>`
}
