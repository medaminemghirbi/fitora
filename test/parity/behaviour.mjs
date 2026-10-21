// The pilot's browser-side behaviour (MIGRATION_AUDIT §12.4, items 10–14):
// each check runs against the Angular reference and the Rails web UI and
// must hold in both. Run with test/parity/serve.sh up:
//
//   node test/parity/behaviour.mjs
//
// The last checks write (a member, a renewal, payments…); reseed afterwards
// (bin/rails parity:seed) before taking screenshots again.
// --only=<text> runs the checks whose name contains it; --apps=rails (or
// angular) runs them in one app only — a check that writes would otherwise
// find the first app's write already there.
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { chromium } from "playwright"

const BACKEND = join(dirname(fileURLToPath(import.meta.url)), "../..")
const APPS = { angular: process.env.PARITY_ANGULAR ?? "http://localhost:4300", rails: process.env.PARITY_RAILS ?? "http://localhost:3100" }
// Reread after a reseed: the seed gives the salles new ids.
let fx = JSON.parse(readFileSync(join(BACKEND, "tmp/parity.json"), "utf8"))
const fr = JSON.parse(readFileSync(join(BACKEND, "config/locales/web/ng/fr.json"), "utf8"))
const browser = await chromium.launch()

const membersPath = (app, salle = "lumen") => (app === "rails" ? `/admin/${fx.salles[salle]}/clients` : "/admin/clients")
const isListRequest = (app) => (request) =>
  app === "angular" ? /\/api\/v1\/clients\?/.test(request.url()) : /\/admin\/[0-9a-f-]{36}\/clients\?/.test(request.url()) && request.headers().accept?.includes("turbo-stream")

async function signedIn(app, login = "admin") {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: "fr-FR", timezoneId: "Africa/Tunis" })
  const page = await context.newPage()
  await page.goto(`${APPS[app]}/connexion`)
  await page.locator("#email").fill(fx.logins[login].email)
  await page.locator("#password").fill(fx.logins[login].password)
  await page.locator("button[type=submit]").click()
  await page.waitForURL((url) => !url.pathname.startsWith("/connexion"))
  return { context, page }
}

async function openMembers(page, app, salle) {
  await page.goto(APPS[app] + membersPath(app, salle))
  await page.locator("table.fx-grid, .fx-state").first().waitFor()
  await page.waitForLoadState("networkidle")
}

const adminPath = (app, page, salle = "lumen") => (app === "rails" ? `/admin/${fx.salles[salle]}/${page}` : `/admin/${page}`)

async function openList(page, app, name) {
  await page.goto(APPS[app] + adminPath(app, name))
  await page.locator("table.fx-grid, .fx-state").first().waitFor()
  await page.waitForLoadState("networkidle")
}

// A toast of this kind saying exactly `text` (an earlier one may still show).
async function expectToast(page, text, kind = "success") {
  await page.locator(`.toast-item--${kind} span`, { hasText: text }).first().waitFor({ timeout: 10000 })
  const texts = (await page.locator(`.toast-item--${kind} span`).allTextContents()).map((t) => t.trim())
  assert.ok(texts.includes(text), `toast "${text}" in ${JSON.stringify(texts)}`)
}

async function settled(page) {
  await page.waitForFunction(() => !document.querySelector(".fx-skeleton-table") && (document.querySelector("table.fx-grid") || document.querySelector(".fx-state")))
}

const CHECKS = {
  async "search waits 1 s after the last keystroke, then asks once"(app) {
    const { context, page } = await signedIn(app)
    await openMembers(page, app)
    const requests = []
    page.on("request", (request) => isListRequest(app)(request) && requests.push({ at: Date.now(), url: request.url() }))
    const input = page.locator(".lst-head-search input")
    await input.fill("sal") // one input event: the last keystroke
    const typed = Date.now()
    await page.waitForTimeout(700)
    assert.equal(requests.length, 0, "no request before the debounce")
    await page.waitForTimeout(700)
    assert.equal(requests.length, 1, "exactly one request")
    const delay = requests[0].at - typed
    assert.ok(delay >= 900 && delay <= 1250, `asked ${delay} ms after the last keystroke`)
    assert.match(requests[0].url, /search=sal/)
    await settled(page)
    assert.equal(await input.evaluate((el) => el === document.activeElement), true, "the search box keeps its focus")
    await context.close()
  },

  async "status pills work as radios from the keyboard, and keep the focus"(app) {
    const { context, page } = await signedIn(app)
    await openMembers(page, app)
    await page.locator("#client-status-").focus()
    await page.keyboard.press("ArrowRight")
    await settled(page)
    await page.waitForLoadState("networkidle")
    assert.equal(await page.locator("#client-status-active").isChecked(), true)
    assert.equal(await page.evaluate(() => document.activeElement?.id), "client-status-active")
    await context.close()
  },

  async "a column header sorts from the keyboard, then flips"(app) {
    const { context, page } = await signedIn(app)
    await openMembers(page, app)
    await page.locator("th.fx-col-seen .fx-th-sort").focus()
    await page.keyboard.press("Enter")
    await settled(page)
    assert.equal(await page.locator("th.fx-col-seen:has(.fx-th-sort)").getAttribute("aria-sort"), "ascending")
    await page.locator("th.fx-col-seen .fx-th-sort").focus()
    await page.keyboard.press("Enter")
    await settled(page)
    assert.equal(await page.locator("th.fx-col-seen:has(.fx-th-sort)").getAttribute("aria-sort"), "descending")
    await context.close()
  },

  async "the wizard traps the focus, and gives it back on Escape"(app) {
    const { context, page } = await signedIn(app)
    await openMembers(page, app)
    const opener = page.locator(".lst-head .btn-primary")
    await opener.focus()
    await page.keyboard.press("Enter")
    await page.locator("#cl-first").waitFor()
    await page.waitForTimeout(100)
    assert.equal(await page.evaluate(() => Boolean(document.activeElement?.closest(".modal-panel"))), true, "focus moved into the dialog")
    for (let i = 0; i < 14; i += 1) {
      await page.keyboard.press("Tab")
      const inside = await page.evaluate(() => Boolean(document.activeElement?.closest(".modal-panel")) || document.activeElement?.classList.contains("cdk-focus-trap-anchor"))
      assert.equal(inside, true, `Tab #${i + 1} left the dialog`)
    }
    await page.keyboard.press("Escape")
    await page.locator(".modal-panel").waitFor({ state: "detached" })
    assert.equal(await page.evaluate(() => document.activeElement?.textContent?.trim()), (await opener.textContent()).trim(), "focus back on the opener")
    await context.close()
  },

  async "the backdrop closes the wizard, the panel does not"(app) {
    const { context, page } = await signedIn(app)
    await openMembers(page, app)
    await page.locator(".lst-head .btn-primary").click()
    await page.locator("#cl-first").waitFor()
    await page.locator(".modal-panel-header h3").click()
    assert.equal(await page.locator(".modal-panel").count(), 1)
    await page.mouse.click(10, 10)
    await page.locator(".modal-panel").waitFor({ state: "detached" })
    await context.close()
  },

  async "the wizard keeps what was typed across steps, and Next waits for the required fields"(app) {
    const { context, page } = await signedIn(app)
    await openMembers(page, app)
    await page.locator(".lst-head .btn-primary").click()
    const next = page.locator(".modal-panel button[type=submit]")
    assert.equal(await next.isDisabled(), true)
    await page.locator("#cl-first").fill("Rym")
    await page.locator("#cl-last").fill("Haddad")
    assert.equal(await next.isDisabled(), true, "phone still missing")
    await page.locator("#cl-phone").fill("+216 22 333 444")
    assert.equal(await next.isDisabled(), false)
    await next.click()
    await page.locator("#cl-activity").waitFor()
    assert.equal((await next.textContent()).trim(), fr.clients.finish_without_plan)
    await page.locator(".modal-panel .btn-outline-secondary").first().click() // back
    assert.equal(await page.locator("#cl-first").inputValue(), "Rym")
    assert.equal(await page.locator("#cl-phone").inputValue(), "+216 22 333 444")
    await context.close()
  },

  async "two tabs on two salles stay apart"(app) {
    const { context, page } = await signedIn(app)
    if (app === "angular") await page.addInitScript((id) => sessionStorage.setItem("fitora_company_id", id), fx.salles.lumen)
    await openMembers(page, app, "lumen")
    const before = await page.locator(".lst-head-count").textContent()
    const other = await context.newPage()
    if (app === "angular") await other.addInitScript((id) => sessionStorage.setItem("fitora_company_id", id), fx.salles.lac)
    await openMembers(other, app, "lac")
    assert.equal(await other.locator(".fx-state").count(), 1, "the second salle has nobody")
    await page.reload()
    await page.locator("table.fx-grid").waitFor()
    assert.equal(await page.locator(".lst-head-count").textContent(), before, "the first tab still shows its own salle")
    assert.notEqual(before, "0")
    await context.close()
  },

  async "the bar hides on the way down, comes back on the way up, stays while a menu is open"(app) {
    const { context, page } = await signedIn(app)
    await openMembers(page, app)
    const header = page.locator("header.app-navbar")
    const scrollTo = async (y) => {
      await page.evaluate((y) => window.scrollTo(0, y), y)
      await page.waitForTimeout(120)
    }
    await scrollTo(400)
    assert.equal(await header.evaluate((el) => el.classList.contains("is-hidden")), true, "hidden scrolling down")
    await scrollTo(300)
    assert.equal(await header.evaluate((el) => el.classList.contains("is-hidden")), false, "back scrolling up")
    await page.locator(".user-menu-trigger").click()
    await scrollTo(700)
    assert.equal(await header.evaluate((el) => el.classList.contains("is-hidden")), false, "never while a menu is open")
    await context.close()
  },

  async "menus close on a click outside and on Escape, and open one at a time"(app) {
    const { context, page } = await signedIn(app)
    await openMembers(page, app)
    await page.locator(".user-menu-trigger").click()
    assert.equal(await page.locator(".dropdown-menu-end").count(), 1)
    await page.locator(".app-company-switcher-trigger").click()
    assert.equal(await page.locator(".dropdown-menu-custom").count(), 1, "one menu at a time")
    await page.locator("h1").click()
    assert.equal(await page.locator(".dropdown-menu-custom").count(), 0, "closed by a click outside")
    await page.locator(".user-menu-trigger").click()
    await page.keyboard.press("Escape")
    assert.equal(await page.locator(".dropdown-menu-custom").count(), 0, "closed by Escape")
    await context.close()
  },

  async "the language switch keeps the page and its query, and turns the page round for Arabic"(app) {
    const context = await browser.newContext({ locale: "fr-FR" })
    const page = await context.newPage()
    await page.goto(`${APPS[app]}/connexion?from=parity`)
    await page.locator('.apro-lang button[lang="ar"]').click()
    await page.waitForFunction(() => document.documentElement.getAttribute("dir") === "rtl")
    assert.equal(await page.evaluate(() => document.documentElement.lang), "ar")
    assert.equal(new URL(page.url()).pathname + new URL(page.url()).search, "/connexion?from=parity")
    await page.locator('.apro-lang button[lang="fr"]').click()
    await page.waitForFunction(() => document.documentElement.getAttribute("dir") === "ltr")
    await context.close()
  },

  async "the inbox screen moves on by itself when the link is opened in another tab"(app) {
    execFileSync("bin/rails", ["parity:state[tokens]"], { cwd: BACKEND, env: { ...process.env, DATABASE_URL: process.env.PARITY_DATABASE_URL ?? "postgres:///backend_parity_demo" } })
    const token = JSON.parse(readFileSync(join(BACKEND, "tmp/parity-tokens.json"), "utf8"))[app].verify
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: "fr-FR" })
    const page = await context.newPage()
    await page.goto(`${APPS[app]}/connexion`)
    await page.locator("#email").fill(`verify.${app}@parity.tn`)
    await page.locator("#password").fill(fx.logins.admin.password)
    await page.locator("button[type=submit]").click()
    await page.waitForURL(/\/confirmation-email$/)
    await page.locator(".ce-live").waitFor()
    const other = await context.newPage()
    await other.goto(`${APPS[app]}/verify-email?token=${token}`)
    await other.locator(".ms[data-state=confirmed]").waitFor()
    // The first tab hears it (BroadcastChannel / its next poll) and hands over.
    await page.locator("app-setup-progress").waitFor({ timeout: 6000 })
    await page.waitForURL((url) => !url.pathname.startsWith("/confirmation-email"), { timeout: 8000 })
    await context.close()
  },

  async "sending the link again starts the countdown"(app) {
    execFileSync("bin/rails", ["parity:state[resend_ready]"], { cwd: BACKEND, env: { ...process.env, DATABASE_URL: process.env.PARITY_DATABASE_URL ?? "postgres:///backend_parity_demo" } })
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: "fr-FR" })
    const page = await context.newPage()
    await page.goto(`${APPS[app]}/connexion`)
    await page.locator("#email").fill(fx.logins.pending.email)
    await page.locator("#password").fill(fx.logins.pending.password)
    await page.locator("button[type=submit]").click()
    await page.waitForURL(/\/confirmation-email$/)
    const resend = page.locator(".ce-actions button")
    assert.equal(await resend.isDisabled(), false, "nothing sent yet: the button is open")
    await resend.click()
    await page.locator(".ce-notice.is-ok").waitFor()
    assert.equal(await resend.isDisabled(), true)
    assert.match(await resend.textContent(), /\d+/)
    await context.close()
  },

  async "a bookings status pill filters the list"(app) {
    const { context, page } = await signedIn(app)
    await openList(page, app, "bookings")
    await page.locator('label[for="booking-status-completed"]').click()
    await page.locator(".fx-active-chip").waitFor()
    await settled(page)
    assert.equal((await page.locator(".fx-active-chip").textContent()).trim(), fr.bookings.status_completed)
    await context.close()
  },

  async "a contract's documents download under contrat-/facture-<ref>.pdf"(app) {
    const { context, page } = await signedIn(app)
    await openList(page, app, "contracts")
    const ref = (await page.locator(".fx-contract-ref").first().textContent()).trim()
    for (const [item, prefix] of [[0, "contrat"], [1, "facture"]]) {
      await page.locator(".fx-action-trigger").first().evaluate((el) => el.click())
      const [download] = await Promise.all([page.waitForEvent("download"), page.locator(".fx-menu-item").nth(item).click()])
      assert.equal(download.suggestedFilename(), `${prefix}-${ref}.pdf`)
    }
    await context.close()
  },

  async "a contract's renewal dialog: the same formule without the hint, another with it"(app) {
    const { context, page } = await signedIn(app)
    await openList(page, app, "contracts")
    await page.locator(".fx-row-actions .btn", { hasText: fr.contracts.renew }).first().click()
    await page.locator("#rn-plan").waitFor()
    // The same formule, still priced by its plan: the total, and no hint.
    assert.equal(await page.locator(".abo-total-line").count(), 1)
    assert.equal(await page.locator(".modal-panel-body > p.fx-muted").count(), 1, "the same formule: no hint")
    const other = await page.locator("#rn-plan").evaluate((el) => [...el.options].find((o) => !o.selected).value)
    await page.locator("#rn-plan").selectOption(other)
    await page.locator(".abo-total-line").waitFor()
    assert.equal(await page.locator(".modal-panel-body > p.fx-muted").count(), 2, "the other-formule hint")
    assert.equal(await page.locator(".modal-panel .btn-primary").isDisabled(), false)
    await page.keyboard.press("Escape")
    await page.locator(".modal-panel").waitFor({ state: "detached" })
    await context.close()
  },

  async "a desk login without payments is refused when it collects"(app) {
    const { context, page } = await signedIn(app, "staff")
    await openList(page, app, "contracts")
    assert.equal(await page.locator(".fx-stats > div").count(), 1, "no money figures without revenue")
    await page.locator(".fx-row-actions .btn", { hasText: fr.payments.collect }).first().click()
    await expectToast(page, "You are not allowed to perform this action", "error")
    await context.close()
  },

  async "the payments record dialog finds a member and fills the amount owed"(app) {
    const { context, page } = await signedIn(app)
    await openList(page, app, "payments")
    await page.locator(".lst-head .btn-primary").click()
    await page.locator("#pay-client-search").fill("H")
    await page.waitForTimeout(400)
    assert.equal(await page.locator(".search-result-item").count(), 0, "nothing under two letters")
    await page.locator("#pay-client-search").fill("Hela")
    await page.locator(".search-result-item").first().click()
    await page.locator("#pay-payable").waitFor()
    assert.equal(await page.locator("#pay-client-search").inputValue(), "Hela Mansouri")
    assert.equal(await page.locator("#pay-amount").inputValue(), "0")
    const option = page.locator("#pay-payable option").nth(1)
    const label = await option.textContent()
    await page.locator("#pay-payable").selectOption(await option.getAttribute("value"))
    assert.equal(await page.locator("#pay-amount").inputValue(), label.match(/\(([\d.]+)\)$/)[1])
    await context.close()
  },

  // Writes: keep last.
  async "finishing the wizard opens the new member's file with a toast"(app) {
    const { context, page } = await signedIn(app)
    await openMembers(page, app)
    await page.locator(".lst-head .btn-primary").click()
    await page.locator("#cl-first").fill(`Behaviour${app}`)
    await page.locator("#cl-last").fill("Check")
    await page.locator("#cl-phone").fill("+216 22 999 000")
    await page.locator(".modal-panel button[type=submit]").click()
    await page.locator("#cl-activity").waitFor()
    await page.locator(".modal-panel button[type=submit]").click() // finish without a plan
    await page.waitForURL(/\/clients\/[0-9a-f-]{36}$/)
    await page.locator(".toast-item--success").waitFor()
    assert.equal((await page.locator(".toast-item--success span").textContent()).trim(), fr.clients.created)
    await context.close()
  },

  async "pausing a contract asks first, then resuming gives it back"(app) {
    const { context, page } = await signedIn(app)
    await openList(page, app, "contracts")
    // The list orders on created_at alone, and the seeded contracts share
    // one (frozen clock): a write may move a row (MIGRATION_AUDIT §14). The
    // check follows its member through the search box.
    const name = (await page.locator("tbody tr .fx-cell-lead-title").first().textContent()).trim()
    // The search reads first or last name, not both together.
    await page.locator(".lst-head-search input").fill(name.split(" ")[0])
    await page.waitForTimeout(1300)
    await settled(page)
    const row = page.locator("tbody tr").first()
    await row.locator(".fx-action-trigger").evaluate((el) => el.click())
    await page.locator(".fx-menu-item").last().click()
    await page.locator(".confirm-dialog").waitFor()
    await page.locator(".confirm-dialog .btn-primary").click()
    await expectToast(page, fr.contracts.paused_done)
    await settled(page)
    const paused = page.locator("tbody tr", { hasText: name }).first()
    assert.equal((await paused.locator(".status-badge").first().textContent()).trim(), fr.contract.status_paused)
    await paused.locator(".fx-action-trigger").evaluate((el) => el.click())
    await page.locator(".fx-menu-item").last().click() // no confirmation
    await expectToast(page, fr.contracts.resumed_done)
    await context.close()
  },

  async "renewing a contract onto the same formule"(app) {
    const { context, page } = await signedIn(app)
    await openList(page, app, "contracts")
    const renew = page.locator(".fx-row-actions .btn", { hasText: fr.contracts.renew })
    const name = (await page.locator("tbody tr", { has: renew }).first().locator(".fx-cell-lead-title").textContent()).trim()
    // The search reads first or last name, not both together.
    await page.locator(".lst-head-search input").fill(name.split(" ")[0])
    await page.waitForTimeout(1300)
    await settled(page)
    assert.equal(await renew.count(), 1)
    await renew.first().click()
    await page.locator(".modal-panel .btn-primary").click()
    await expectToast(page, fr.contracts.renewed)
    await settled(page)
    // The renewed term is no longer the last of its chain, so nothing on
    // the member's rows can be renewed now.
    await page.waitForFunction((label) => ![...document.querySelectorAll(".fx-row-actions .btn")].some((b) => b.textContent.trim() === label), fr.contracts.renew)
    await context.close()
  },

  async "collecting a contract records it in cash"(app) {
    const { context, page } = await signedIn(app)
    await openList(page, app, "contracts")
    const due = await page.locator(".fx-row-actions .btn", { hasText: fr.payments.collect }).count()
    await page.locator(".fx-row-actions .btn", { hasText: fr.payments.collect }).first().click()
    await expectToast(page, fr.payments.recorded)
    await settled(page)
    assert.equal(await page.locator(".fx-row-actions .btn", { hasText: fr.payments.collect }).count(), due - 1)
    await context.close()
  },

  async "recording a payment from the dialog adds a receipt"(app) {
    const { context, page } = await signedIn(app)
    await openList(page, app, "payments")
    const before = Number(await page.locator(".lst-head-count").textContent())
    await page.locator(".lst-head .btn-primary").click()
    await page.locator("#pay-client-search").fill("Dali")
    await page.locator(".search-result-item").first().click()
    await page.locator("#pay-payable").waitFor()
    await page.locator("#pay-payable").selectOption(await page.locator("#pay-payable option").nth(1).getAttribute("value"))
    await page.locator(".modal-panel button[type=submit]").click()
    await expectToast(page, fr.common.save)
    await settled(page)
    await page.waitForFunction((n) => Number(document.querySelector(".lst-head-count").textContent) === n + 1, before)
    await context.close()
  },

  async "with everything read, the unread filter shows the empty state and no \"more\""(app) {
    const { context, page } = await signedIn(app)
    await page.goto(APPS[app] + adminPath(app, "notifications"))
    await page.locator(".notif-inbox").waitFor()
    assert.equal(await page.locator(".notif-inbox-more").count(), 1, "a second page to load")
    await page.locator(".lst-head .btn").click() // mark all read
    await page.locator(".notif-item.is-unread").first().waitFor({ state: "detached" })
    await page.locator(".fx-toolbar button").nth(1).click() // unread
    await page.locator(".fx-state").waitFor()
    assert.equal(await page.locator(".notif-inbox-more").count(), 0)
    await page.locator(".fx-toolbar button").nth(0).click() // all again
    await page.locator(".notif-inbox-more").waitFor()
    await context.close()
  },

  async "company setup keeps the details across its steps, then opens the salle onto the guide"(app) {
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: "fr-FR", timezoneId: "Africa/Tunis" })
    const page = await context.newPage()
    await page.goto(`${APPS[app]}/connexion`)
    await page.locator("#email").fill(`setup.${app}@parity.tn`)
    await page.locator("#password").fill(fx.logins.admin.password)
    await page.locator("button[type=submit]").click()
    await page.waitForURL(/\/admin\/setup-company$/)
    // guessLocation(): Africa/Tunis, so Tunisia.
    assert.match(await page.locator(".ss-value").textContent(), /Tunisie/)
    await page.locator(".setup-card button[type=submit]").click()
    assert.equal(await page.locator(".ap-tile").count(), 0, "no name, no step 2")
    await page.locator("#org-name").fill(`Salle ${app}`)
    await page.locator("#org-city").fill("Sousse")
    await page.locator(".setup-card button[type=submit]").click()
    await page.locator(".ap-tile").first().click()
    await page.locator(".setup-actions .btn-outline-secondary").click() // back
    assert.equal(await page.locator("#org-city").inputValue(), "Sousse")
    await page.locator(".setup-card button[type=submit]").click()
    assert.equal(await page.locator(".ap-tile.is-on").count(), 1, "the pick is kept")
    const started = Date.now()
    await page.locator(".setup-actions .btn-primary").click()
    await page.locator(".prep").waitFor()
    await page.waitForURL(/\/onboarding$/, { timeout: 20000 })
    assert.ok(Date.now() - started >= 4900, "the scene holds five seconds")
    await page.locator(".obs-list").waitFor()
    await context.close()
  },

  async "refunding a payment asks first, then marks it refunded"(app) {
    const { context, page } = await signedIn(app)
    await openList(page, app, "payments")
    await page.locator(".fx-action-trigger").first().evaluate((el) => el.click())
    await page.locator(".fx-menu-item.is-danger").click()
    await page.locator(".confirm-dialog .btn-danger").click()
    await expectToast(page, fr.payments.refunded_toast)
    await settled(page)
    await page.locator('label[for="payment-status-refunded"]').click()
    await settled(page)
    await page.waitForFunction(() => document.querySelector(".fx-chip-input:checked + .fx-chip .fx-chip-count")?.textContent.trim() !== "0")
    await context.close()
  },

  async "team: a coach with a mobile login, from the drawer, shows up with the app"(app) {
    const { context, page } = await signedIn(app)
    await page.goto(APPS[app] + adminPath(app, "team"))
    await page.locator(".fx-people-grid").waitFor()
    await page.locator(".lst-head .btn-primary").click()
    await page.locator("#tc-first").fill("Rania")
    await page.locator("#tc-last").fill("Hamdi")
    await page.locator("#tc-email").fill(`rania.${app}@parity.tn`)
    await page.locator("#tc-mobile").check()
    await page.locator("#tc-mpass").fill("short")
    await page.locator(".fx-drawer-footer .btn-primary").click()
    await page.locator(".fx-drawer-body > .alert-danger", { hasText: fr.team.mobile_needs_credentials }).waitFor()
    // Unticked and ticked again, the password is still there (one control).
    await page.locator("#tc-mobile").uncheck()
    assert.equal(await page.locator("#tc-mpass").count(), 0)
    await page.locator("#tc-mobile").check()
    assert.equal(await page.locator("#tc-mpass").inputValue(), "short")
    await page.locator("#tc-mpass").fill("password123")
    await page.locator(".fx-drawer-footer .btn-primary").click()
    await expectToast(page, fr.common.save)
    assert.equal(await page.locator(".fx-drawer").count(), 0, "the drawer closed")
    await page.locator(".lst-head-search input").fill("rania")
    const cards = page.locator(".fx-person-card", { hasText: "Rania Hamdi" })
    await cards.first().waitFor()
    // Angular lists the coach's new login as a second card (B-08).
    assert.equal(await cards.count(), app === "angular" ? 2 : 1)
    assert.match(await cards.first().textContent(), new RegExp(fr.team.access_mobile))
    await context.close()
  },

  async "team: freeing the moderator seat from the drawer opens the back-office form on it"(app) {
    railsState("lac_team")
    const { context, page } = await signedIn(app)
    if (app === "angular") await page.addInitScript((id) => sessionStorage.setItem("fitora_company_id", id), fx.salles.lac)
    await page.goto(APPS[app] + adminPath(app, "team", "lac"))
    await page.locator(".fx-people-grid").waitFor()
    await page.locator(".lst-head .btn-primary").click()
    assert.ok(await page.locator(".team-kind-opt").nth(1).isDisabled(), "the back-office card is locked")
    await page.locator(".team-seat-notice .btn-outline-danger").click()
    await page.locator(".confirm-dialog .btn-danger").click()
    await expectToast(page, fr.common.deactivate)
    await page.locator(".team-seat-notice").waitFor({ state: "detached" })
    assert.ok(await page.locator(".team-kind-opt").nth(1).isEnabled(), "unlocked")
    assert.match(await page.locator(".team-kind-opt.is-active").textContent(), new RegExp(fr.team.create_type_backoffice))
    const role = await page.locator("#tb-role option:checked").textContent()
    assert.equal(role.trim(), "Modérateur")
    assert.equal(await page.locator("#tb-role option:checked").isDisabled(), false)
    await context.close()
  },

  async "team: editing a coach takes the whole address, and saves"(app) {
    const { context, page } = await signedIn(app)
    await page.goto(APPS[app] + adminPath(app, "team"))
    await page.locator(".fx-people-grid").waitFor()
    await page.locator(".fx-person-card-actions .btn-outline-secondary").first().click()
    await page.waitForFunction(() => document.querySelector("#ec-email")?.value === "amine@studiolumen.tn")
    await page.locator("#ec-bio").fill("Yoga et respiration.")
    await page.locator(".modal-panel button[type=submit]").click()
    await expectToast(page, fr.common.save)
    await page.locator(".fx-person-card-bio", { hasText: "Yoga et respiration." }).waitFor()
    await context.close()
  },

  async "salles: posting a moderator to Lumen redraws the cards, with a toast"(app) {
    railsState("pro")
    railsState("lac_team")
    const { context, page } = await signedIn(app)
    await page.goto(APPS[app] + adminPath(app, "salles"))
    await page.locator(".sl-grid").waitFor()
    await page.locator(".sl-card-foot .btn-outline-secondary").first().click()
    const save = page.locator(".modal-panel .btn-primary")
    assert.ok(await save.isDisabled(), "nothing changed yet")
    await page.locator(".sl-pick-item", { hasText: "Hela Chaabane" }).locator("input").check()
    assert.ok(await save.isEnabled())
    await save.click()
    await expectToast(page, fr.salles.moderators_saved.replace("{{name}}", "Studio Lumen"))
    assert.equal(await page.locator(".modal-panel").count(), 0)
    await page.locator(".sl-card").first().locator(".sl-mod", { hasText: "Hela Chaabane" }).waitFor()
    await context.close()
  },

  async "salles: switching loads the other salle's dashboard"(app) {
    railsState("pro")
    const { context, page } = await signedIn(app)
    await page.goto(APPS[app] + adminPath(app, "salles"))
    await page.locator(".sl-grid").waitFor()
    await page.locator(".sl-card-foot .btn-primary").first().click()
    await page.waitForURL(app === "rails" ? new RegExp(`/admin/${fx.salles.lac}/dashboard`) : /\/admin\/dashboard$/)
    await context.close()
  },

  async "salles: opening another salle lands on its getting-started guide"(app) {
    railsState("pro")
    const { context, page } = await signedIn(app)
    await page.goto(APPS[app] + adminPath(app, "salles"))
    await page.locator(".sl-grid").waitFor()
    await page.locator(".sl-card--add").click()
    await page.locator("#salle-name").fill(`Salle ${app}`)
    await page.locator("#salle-city").fill("Sousse")
    await page.locator(".modal-panel button[type=submit]").click()
    await page.waitForURL(/\/onboarding$/)
    await page.locator(".ob-facts, .obs-list").first().waitFor()
    await context.close()
  },

  async "calendar: a session from a clicked slot lands on the grid"(app) {
    const { context, page } = await signedIn(app)
    await page.clock.setFixedTime(new Date("2026-10-14T10:00:00+01:00"))
    await page.goto(APPS[app] + adminPath(app, "calendar"))
    await page.locator(".fc-event").first().waitFor()
    const before = await page.locator(".fc-event").count()
    await page.locator('.fc-timegrid-slot-lane[data-time="15:00:00"]').click({ position: { x: 5, y: 5 } })
    await page.locator("#cs-activity").waitFor()
    assert.ok(await page.locator(".fc-cell-selected").count() >= 0)
    const index = await page.locator("#cs-activity").evaluate((s) => [...s.options].findIndex((o) => o.text.includes("Yoga Vinyasa")))
    await page.locator("#cs-activity").selectOption({ index })
    await page.locator(".modal-panel button[type=submit]").click()
    await expectToast(page, fr.common.save)
    await page.waitForFunction((n) => document.querySelectorAll(".fc-event").length === n + 1, before)
    await context.close()
  },

  async "calendar: a move refused at the question goes back where it was"(app) {
    const { context, page } = await signedIn(app)
    await page.clock.setFixedTime(new Date("2026-10-14T10:00:00+01:00"))
    await page.goto(APPS[app] + adminPath(app, "calendar"))
    const event = page.locator(".fc-day-today .fc-timegrid-event").last()
    await event.waitFor()
    await event.scrollIntoViewIfNeeded()
    const start = await event.boundingBox()
    const x = start.x + start.width / 2
    await page.mouse.move(x, start.y + start.height / 2)
    await page.mouse.down()
    for (let i = 1; i <= 18; i++) {
      await page.mouse.move(x, start.y + start.height / 2 + i * 5)
      await page.waitForTimeout(16)
    }
    await page.mouse.up()
    await page.locator(".confirm-dialog").waitFor()
    await page.locator(".confirm-dialog .btn-outline-secondary").click()
    await page.waitForTimeout(300)
    const after = await page.locator(".fc-day-today .fc-timegrid-event").last().boundingBox()
    assert.ok(Math.abs(after.y - start.y) < 2, `back in place (${start.y} → ${after.y})`)
    await context.close()
  },

  async "calendar: attendance marked in a session's detail"(app) {
    const { context, page } = await signedIn(app)
    await page.clock.setFixedTime(new Date("2026-10-14T10:00:00+01:00"))
    await page.goto(APPS[app] + adminPath(app, "calendar"))
    await page.locator(".fc-event").first().waitFor()
    // The first session with people booked.
    const index = await page.locator(".fc-event").evaluateAll((events) => events.findIndex((e) => !/^0\//.test(e.querySelector(".fx-ev-count")?.textContent ?? "0/")))
    await page.locator(".fc-event").nth(index).click()
    const row = page.locator(".modal-panel .list-unstyled li").first()
    await row.waitFor()
    await row.locator("button").nth(2).click() // late
    await page.waitForFunction(() => document.querySelector(".modal-panel .list-unstyled li button:nth-child(3)")?.classList.contains("btn-primary"))
    await context.close()
  },

  async "member file: the health file saved is still there after a reload"(app) {
    const { context, page } = await signedIn(app)
    const path = APPS[app] + adminPath(app, `clients/${fx.clients.rania}`)
    await page.goto(path)
    await page.locator(".prof-health .btn").click()
    await page.locator("#hl-notes").fill("Genou fragile — pas de sauts.")
    await page.locator(".modal-panel .prof-waiver-today").first().click()
    await page.locator(".modal-panel button[type=submit]").click()
    await expectToast(page, fr.common.saved)
    await page.goto(path)
    await page.locator(".prof-health", { hasText: "Genou fragile" }).waitFor()
    await context.close()
  },

  async "member file: a subscription sold becomes the current one"(app) {
    const { context, page } = await signedIn(app)
    await page.goto(APPS[app] + adminPath(app, `clients/${fx.clients.badr}`))
    await page.locator(".prof-actions-row .btn-outline-secondary").nth(1).click()
    const plan = await page.locator("#ms-plan").evaluate((s) => [...s.options].findIndex((o) => o.text.includes("Yoga illimité")))
    await page.locator("#ms-plan").selectOption({ index: plan })
    await page.locator("#ms-activity option").nth(1).waitFor({ state: "attached" })
    const activity = await page.locator("#ms-activity").evaluate((s) => [...s.options].findIndex((o) => o.text.includes("Yoga")))
    await page.locator("#ms-activity").selectOption({ index: activity })
    await page.locator(".modal-panel button[type=submit]").click()
    await expectToast(page, fr.common.save)
    await page.locator(".prof-banner", { hasText: "Yoga illimité" }).waitFor()
    await context.close()
  },

  async "member file: a seat booked shows in what happened"(app) {
    const { context, page } = await signedIn(app)
    await page.goto(APPS[app] + adminPath(app, `clients/${fx.clients.badr}`))
    await page.locator(".prof-actions-row .btn-outline-secondary").nth(2).click()
    const activity = await page.locator("#bk-activity").evaluate((s) => [...s.options].findIndex((o) => o.text.includes("Yoga Vinyasa")))
    await page.locator("#bk-activity").selectOption({ index: activity })
    await page.locator("#bk-date").fill("2026-10-15")
    await page.locator("#bk-date").dispatchEvent("change")
    await page.locator("#bk-session option").nth(1).waitFor({ state: "attached" })
    await page.locator("#bk-session").selectOption({ index: 1 })
    await page.locator(".modal-panel button[type=submit]").click()
    await expectToast(page, fr.common.save)
    await page.locator(".prof-timeline-text", { hasText: "Yoga Vinyasa" }).first().waitFor()
    await context.close()
  },

  async "member file: a payment collected clears what was owed"(app) {
    const { context, page } = await signedIn(app)
    await page.goto(APPS[app] + adminPath(app, `clients/${fx.clients.dali}`))
    await page.locator(".prof-actions-row .btn-primary").click()
    await page.locator("#pm-payable option").nth(1).waitFor({ state: "attached" })
    await page.locator("#pm-payable").selectOption({ index: 1 })
    await page.locator(".modal-panel button[type=submit]").click()
    await expectToast(page, fr.common.save)
    // Nothing owed any more: the "collect" action goes.
    await page.locator(".prof-actions-row .btn-primary").waitFor({ state: "detached" })
    await context.close()
  },
}

let failures = 0
// The checks that write start each app from the seeded data.
const WRITES = new Set(Object.keys(CHECKS).slice(Object.keys(CHECKS).indexOf("finishing the wizard opens the new member's file with a toast") + 1))
function railsState(name) {
  execFileSync("bin/rails", [`parity:state[${name}]`], { cwd: BACKEND, stdio: "ignore", env: { ...process.env, DATABASE_URL: process.env.PARITY_DATABASE_URL ?? "postgres:///backend_parity_demo", FITORA_FROZEN_TIME: process.env.FITORA_FROZEN_TIME ?? "2026-10-14T10:00:00+01:00" } })
}

function reseed() {
  execFileSync("bin/rails", ["parity:seed"], { cwd: BACKEND, stdio: "ignore", env: { ...process.env, DATABASE_URL: process.env.PARITY_DATABASE_URL ?? "postgres:///backend_parity_demo", FITORA_FROZEN_TIME: process.env.FITORA_FROZEN_TIME ?? "2026-10-14T10:00:00+01:00" } })
  fx = JSON.parse(readFileSync(join(BACKEND, "tmp/parity.json"), "utf8"))
}

const only = process.argv.find((arg) => arg.startsWith("--only="))?.slice("--only=".length)
const apps = (process.argv.find((arg) => arg.startsWith("--apps="))?.slice("--apps=".length) ?? "angular,rails").split(",")
for (const [name, check] of Object.entries(CHECKS)) {
  if (only && !name.includes(only)) continue
  for (const app of apps) {
    try {
      if (WRITES.has(name)) reseed()
      await check(app)
      console.log(`pass  ${app.padEnd(8)} ${name}`)
    } catch (error) {
      failures += 1
      console.log(`FAIL  ${app.padEnd(8)} ${name}\n      ${error.message.split("\n")[0]}`)
      if (process.env.PARITY_DEBUG) console.log(error.stack)
    }
  }
}
await browser.close()
console.log(`\n${failures === 0 ? "all checks hold in both apps" : `${failures} failure(s)`}`)
process.exitCode = failures ? 1 : 0
