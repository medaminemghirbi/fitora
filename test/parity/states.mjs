// The pilot's visual states (MIGRATION_AUDIT §12.3). Each state is reached by
// the same steps in both apps — the same clicks, the same typing — so the two
// screenshots show the same thing; only how a URL names the salle differs
// (MIGRATION_AUDIT §8). `register` labels a state whose difference is by
// design (§10), so the report shows it instead of hiding it.
//
// A state: { id, title, login, salle?, path, steps?, viewports?, db?, register?, ready }
//   login     null (signed out) | "admin" | "staff"
//   salle     "lumen" (default) | "lac"
//   path      the Angular path; the runner adds the salle for Rails
//   steps     async ({ page, app }) => …   after the page has loaded
//   ready     a selector that must be visible (readyState: "attached" — present) before the capture
//   db        parity:state names applied before the state and undone after
//   freshTokens  spends emailed-link tokens: new ones before each viewport
//   serial    its viewports one after another: it moves the clock, which a
//             browser context shares between its pages (pastDebounce)
//   path      may be (app, tokens) => path when it carries the app's own token
//   viewports subset of the default three
export const VIEWPORTS = {
  mobile: { width: 375, height: 812 },
  tablet: { width: 768, height: 1024 },
  desktop: { width: 1440, height: 900 },
}

const SEARCH_DEBOUNCE = 1000 + 300
const FROZEN_AT = Date.parse(process.env.FITORA_FROZEN_TIME ?? "2026-10-14T10:00:00+01:00")

// RxJS's debounceTime measures the wait with Date.now(), which the frozen
// clock stops, so an Angular search behind it never goes. The clock is moved
// on past the wait — in both apps alike — once the typing is done. The
// clock is the browser context's, so a state that does this is `serial`.
async function pastDebounce(page) {
  await page.waitForTimeout(50)
  await page.clock.setFixedTime(new Date(FROZEN_AT + 1000))
  await page.waitForTimeout(400)
  await page.waitForLoadState("networkidle")
}

// A button pressed in place. At 375 px the members page's header is wider
// than the screen in both apps (K-01, UX-01): "+ Ajouter" and the far table
// columns sit past its edge, where a pointer click lands on <html>. Pressing
// them directly reaches the same handler in both apps.
const press = (locator) => locator.evaluate((element) => element.click())

// Picks the option whose text holds `text`: Angular's [ngValue] options have
// no usable value attribute, so both apps are driven by what they show.
async function selectByText(page, selector, text) {
  const index = await page.locator(selector).evaluate((select, t) => [...select.options].findIndex((o) => o.text.includes(t)), text)
  await page.locator(selector).selectOption({ index })
}

async function signInForm(page, email, password) {
  if (email !== undefined) await page.locator("#email").fill(email)
  if (password !== undefined) await page.locator("#password").fill(password)
  await page.locator("button[type=submit]").click()
}

async function settleList(page) {
  // The list's own request has gone and come back: skeleton gone, table or state there.
  await page.waitForFunction(() => !document.querySelector(".fx-skeleton-table") && (document.querySelector("table.fx-grid") || document.querySelector(".fx-state")))
}

async function openWizard(page) {
  await press(page.locator(".lst-head .btn-primary"))
  await page.locator("#cl-first").waitFor()
}

async function fillIdentity(page) {
  await page.locator("#cl-first").fill("Rym")
  await page.locator("#cl-last").fill("Haddad")
  await page.locator("#cl-phone").fill("+216 22 333 444")
}

async function toPlanStep(page) {
  await openWizard(page)
  await fillIdentity(page)
  await page.locator(".modal-panel button[type=submit]").click()
  await page.locator("#cl-activity").waitFor()
}

async function choosePlan(page) {
  await page.locator("#cl-activity").selectOption({ label: "🧘 Yoga Vinyasa" })
  await page.locator("#cl-plan").waitFor()
  await page.locator("#cl-plan").selectOption({ label: "Yoga illimité" })
  await page.locator(".fx-summary-row").waitFor()
}

export const STATES = [
  // ---- sign-in -------------------------------------------------------------
  { id: "V1", title: "Sign-in, empty", login: null, path: "/connexion", ready: "#email" },
  {
    id: "V2", title: "Sign-in, both fields required", login: null, path: "/connexion", ready: ".invalid-feedback",
    steps: ({ page }) => signInForm(page),
  },
  {
    id: "V3", title: "Sign-in, wrong password", login: null, path: "/connexion", ready: ".alert-danger", register: "B-02",
    steps: ({ page }) => signInForm(page, "meriem@studiolumen.tn", "not-the-password"),
  },
  {
    id: "V4", title: "Sign-in, password shown", login: null, path: "/connexion", ready: ".bi-eye-slash",
    steps: async ({ page }) => {
      await page.locator("#password").fill("secret-password")
      await page.locator(".auth-eye").click()
    },
  },

  // ---- the account pages (module 1) -----------------------------------
  { id: "A1", title: "Sign-up, empty", login: null, path: "/inscription", ready: "#reg-first" },
  { id: "A2", title: "Sign-up, prefilled from the landing page", login: null, path: "/inscription?first_name=Sana&email=sana%40example.tn", ready: "#reg-first" },
  {
    id: "A3", title: "Sign-up, malformed address left", login: null, path: "/inscription", ready: ".invalid-feedback",
    steps: async ({ page }) => {
      await page.locator("#reg-email").fill("not-an-address")
      await page.locator("#reg-password").focus()
    },
  },
  {
    id: "A4", title: "Sign-up, address already taken", login: null, path: "/inscription", ready: ".alert-danger", register: "K-04",
    steps: async ({ page }) => {
      await page.locator("#reg-first").fill("Meriem")
      await page.locator("#reg-last").fill("Ben Ammar")
      await page.locator("#reg-email").fill("meriem@studiolumen.tn")
      await page.locator("#reg-password").fill("password123")
      await page.locator("button[type=submit]").click()
    },
  },
  { id: "A5", title: "Forgotten password, empty", login: null, path: "/mot-de-passe-oublie", ready: "#email" },
  {
    id: "A6", title: "Forgotten password, sent", login: null, path: "/mot-de-passe-oublie", ready: ".auth-request-mark",
    steps: async ({ page }) => {
      await page.locator("#email").fill("nobody@example.tn")
      await page.locator("button[type=submit]").click()
    },
  },
  {
    id: "A7", title: "Forgotten password, address required", login: null, path: "/mot-de-passe-oublie", ready: ".invalid-feedback",
    steps: ({ page }) => page.locator("button[type=submit]").click(),
  },
  { id: "A8", title: "New password, link without a token", login: null, path: "/auth/reset-password", ready: ".alert-danger" },
  {
    id: "A9", title: "New password, typing (strength, rules)", login: null, path: (app, t) => `/auth/reset-password?token=${t.reset}`, ready: ".auth-strength", db: ["tokens"],
    steps: async ({ page }) => {
      await page.locator("#password").fill("Lumen-2026!")
      await page.locator("#password_confirmation").fill("Lumen-2026!")
    },
  },
  {
    id: "A10", title: "New password, done", login: null, path: (app, t) => `/auth/reset-password?token=${t.reset}`, ready: ".auth-request-mark", freshTokens: true,
    steps: async ({ page }) => {
      await page.locator("#password").fill("Lumen-2026!")
      await page.locator("#password_confirmation").fill("Lumen-2026!")
      await page.locator("button[type=submit]").click()
    },
  },
  { id: "A11", title: "Invitation, the form", login: null, path: (app, t) => `/auth/accept-invitation?token=${t.invitation}`, ready: "#password", db: ["tokens"] },
  {
    id: "A12", title: "Invitation, done", login: null, path: (app, t) => `/auth/accept-invitation?token=${t.invitation}`, ready: ".auth-request-mark", freshTokens: true,
    steps: async ({ page }) => {
      await page.locator("#password").fill("Member-2026!")
      await page.locator("#password_confirmation").fill("Member-2026!")
      await page.locator("button[type=submit]").click()
    },
  },
  { id: "A13", title: "Address confirmed, opened on another device", login: null, path: (app, t) => `/verify-email?token=${t.verify}`, ready: ".ms[data-state=confirmed]", freshTokens: true },
  { id: "A14", title: "Address link stale", login: null, path: "/verify-email?token=stale", ready: ".ms[data-state=error]" },
  { id: "A15", title: "Check your inbox (waiting)", login: "pending", path: "/confirmation-email", ready: ".ce-live" },
  { id: "A16", title: "Locked: the trial is over (admin)", login: "admin", path: "/account-locked", ready: ".locked-card", db: ["trial_0", "lock"] },
  { id: "A17", title: "Locked (staff)", login: "staff", path: "/account-locked", ready: ".locked-card", db: ["trial_0", "lock"] },

  // ---- the landing page (module 11) ------------------------------------------
  { id: "W1", title: "Landing, at rest", login: null, path: "/", ready: ".lp-hero" },
  { id: "W2", title: "Landing, the menu on a phone", login: null, path: "/", ready: ".lp-mobile-menu.is-open", viewports: ["mobile"],
    steps: ({ page }) => page.locator(".lp-nav-burger").click() },
  { id: "W3", title: "Landing, a year's prices, another day and slot, another question", login: null, path: "/", ready: ".lp-faq-item.is-open #faq-a-4",
    steps: async ({ page }) => {
      await page.locator(".lp-billing button").nth(1).click()
      await page.locator(".lp-days button").nth(2).click()
      await page.locator(".lp-times button", { hasText: "19:00" }).click()
      await page.locator(".lp-faq-item").nth(1).locator("button").click()
    } },
  { id: "W4", title: "Landing, the closing form's address refused", login: null, path: "/", ready: ".lp-field-err",
    steps: async ({ page }) => {
      await page.locator("#lp-first").fill("Sana")
      await page.locator("#lp-email").fill("sana@")
      await page.locator(".lp-start button[type=submit]").click()
    } },

  // ---- module 2: updates, notifications --------------------------------
  { id: "U1", title: "Nouveautés (release notes)", login: "admin", path: "/admin/updates", ready: ".updates-timeline" },
  { id: "N1", title: "Notifications, inbox", login: "admin", path: "/admin/notifications", ready: ".notif-item" },
  {
    id: "N2", title: "Notifications, unread only", login: "admin", path: "/admin/notifications", ready: ".notif-item",
    steps: ({ page }) => page.locator(".fx-segmented button").nth(1).click(),
  },
  {
    id: "N3", title: "Notifications, second page loaded", login: "admin", path: "/admin/notifications", ready: ".notif-item:nth-child(11)",
    steps: async ({ page }) => {
      await page.locator(".notif-inbox-more button").click()
      await page.waitForFunction(() => document.querySelectorAll(".notif-item").length > 10)
    },
  },
  { id: "N4", title: "Notification, detail", login: "admin", path: "/admin/notifications", ready: ".notif-detail-card",
    steps: async ({ page }) => {
      await page.locator(".notif-item").nth(3).click()
      await page.locator(".notif-detail-card").waitFor()
    },
  },
  {
    id: "N5", title: "Bell, panel open", login: "admin", path: "/admin/clients", ready: ".notif-row",
    steps: async ({ page }) => {
      await page.locator(".notif-bell-btn").click()
      await page.locator(".notif-row").first().waitFor()
    },
  },

  { id: "S1", title: "Support, the form and the history", login: "admin", path: "/admin/support", ready: ".ticket-item" },
  {
    id: "S2", title: "Support, a file chosen and the form filled", login: "admin", path: "/admin/support", ready: ".contact-file-list",
    steps: async ({ page }) => {
      await page.locator("#ticket-subject").fill("Une question")
      await page.locator("#ticket-message").fill("Le planning de la semaine prochaine ne s'affiche pas.")
      await page.locator("#ticket-files").setInputFiles({ name: "capture.png", mimeType: "image/png", buffer: Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64") })
    },
  },
  {
    id: "S3", title: "Support, a file of the wrong type", login: "admin", path: "/admin/support", ready: ".contact-file-error",
    steps: ({ page }) => page.locator("#ticket-files").setInputFiles({ name: "notes.txt", mimeType: "text/plain", buffer: Buffer.from("x") }),
  },

  { id: "R1", title: "Rooms, the list", login: "admin", path: "/admin/spaces", ready: "table" },
  { id: "R2", title: "Rooms, searched", login: "admin", path: "/admin/spaces", ready: "mark.fx-hl",
    steps: ({ page }) => page.locator(".fx-toolbar input").fill("ems") },
  { id: "R3", title: "Rooms, nothing matches", login: "admin", path: "/admin/spaces", ready: ".fx-state",
    steps: ({ page }) => page.locator(".fx-toolbar input").fill("zzzz") },
  { id: "R4", title: "Rooms, new room form", login: "admin", path: "/admin/spaces", ready: "#space-name",
    steps: ({ page }) => page.locator(".fx-toolbar .btn-primary").click() },
  {
    id: "R5", title: "Rooms, editing a room", login: "admin", path: "/admin/spaces", ready: "#space-name",
    steps: async ({ page }) => {
      await page.locator(".fx-action-trigger").first().click()
      await page.locator(".fx-menu-item").first().click()
      await page.waitForFunction(() => document.querySelector("#space-name")?.value)
    },
  },
  { id: "R6", title: "Rooms, a row's menu open", login: "admin", path: "/admin/spaces", ready: ".fx-menu",
    steps: ({ page }) => page.locator(".fx-action-trigger").first().click() },
  {
    id: "R7", title: "Rooms, removing: the confirmation", login: "admin", path: "/admin/spaces", ready: ".confirm-dialog",
    steps: async ({ page }) => {
      await page.locator(".fx-action-trigger").first().click()
      await page.locator(".fx-menu-item.is-danger").click()
    },
  },
  { id: "B1", title: "Bookings, the list", login: "admin", path: "/admin/bookings", ready: "table" },
  { id: "B2", title: "Bookings, completed only", login: "admin", path: "/admin/bookings", ready: ".fx-active-chip",
    steps: async ({ page }) => {
      await press(page.locator(".fx-cat-tab").nth(2))
      await settleList(page)
    } },
  { id: "B3", title: "Bookings, on a day", login: "admin", path: "/admin/bookings", ready: ".fx-active-chip",
    steps: async ({ page }) => {
      // In the collapsed rail below lg (both apps): set it in place, with the
      // events Angular's ngModel (input) and the Rails page (change) listen to.
      await page.locator("#booking-date-filter").evaluate((el) => {
        el.value = "2026-10-13"
        el.dispatchEvent(new Event("input", { bubbles: true }))
        el.dispatchEvent(new Event("change", { bubbles: true }))
      })
      await settleList(page)
    } },
  { id: "B4", title: "Bookings, searched", login: "admin", path: "/admin/bookings", ready: "mark.fx-hl",
    steps: async ({ page }) => {
      await page.locator(".lst-head-search input").fill("yoga")
      await page.waitForTimeout(SEARCH_DEBOUNCE)
      await settleList(page)
    } },
  { id: "B5", title: "Bookings, filters open on a phone", login: "admin", path: "/admin/bookings", ready: ".fx-rail.is-open", viewports: ["mobile", "tablet"],
    steps: ({ page }) => page.locator(".fx-rail-toggle").click() },
  { id: "B6", title: "Bookings, cancelling: the confirmation", login: "admin", path: "/admin/bookings", ready: ".confirm-dialog",
    steps: async ({ page }) => {
      await page.locator(".fx-action-trigger").first().evaluate((el) => el.click())
      await page.locator(".fx-menu-item.is-danger").click()
    } },

  // ---- contracts (module 3) ----------------------------------------------
  { id: "C1", title: "Contracts, the list", login: "admin", path: "/admin/contracts", ready: "table" },
  { id: "C2", title: "Contracts, running out", login: "admin", path: "/admin/contracts", ready: ".fx-active-chip",
    steps: async ({ page }) => {
      await press(page.locator('label[for="contract-status-expiring"]'))
      await settleList(page)
    } },
  { id: "C3", title: "Contracts, one plan", login: "admin", path: "/admin/contracts", ready: ".fx-active-chip",
    steps: async ({ page }) => {
      await press(page.locator(".fx-cat-tab").nth(2))
      await settleList(page)
    } },
  { id: "C4", title: "Contracts, searched", login: "admin", path: "/admin/contracts", ready: "mark.fx-hl",
    steps: async ({ page }) => {
      await page.locator(".lst-head-search input").fill("sa")
      await page.waitForTimeout(SEARCH_DEBOUNCE)
      await settleList(page)
    } },
  { id: "C5", title: "Contracts, unpaid (the dashboard's link)", login: "admin", path: "/admin/contracts?payment=unpaid", ready: ".fx-active-chip" },
  { id: "C6", title: "Contracts, page 2", login: "admin", path: "/admin/contracts", ready: "table",
    steps: async ({ page }) => {
      await press(page.locator(".app-pagination-controls button").last())
      await settleList(page)
    } },
  { id: "C7", title: "Contracts, the renewal dialog", login: "admin", path: "/admin/contracts", ready: ".modal-panel",
    steps: ({ page }) => press(page.locator(".fx-row-actions .btn", { hasText: /Renouveler|تجديد/ }).first()) },
  { id: "C8", title: "Contracts, renewing onto another formule", login: "admin", path: "/admin/contracts", ready: ".modal-panel .abo-total-line",
    steps: async ({ page }) => {
      await press(page.locator(".fx-row-actions .btn", { hasText: /Renouveler|تجديد/ }).first())
      const select = page.locator("#rn-plan")
      const other = await select.evaluate((el) => [...el.options].find((o) => !o.selected).value)
      await select.selectOption(other)
    } },
  { id: "C9", title: "Contracts, a row's menu", login: "admin", path: "/admin/contracts", ready: ".fx-menu",
    steps: ({ page }) => page.locator(".fx-action-trigger").first().evaluate((el) => el.click()) },
  { id: "C10", title: "Contracts, pausing: the confirmation", login: "admin", path: "/admin/contracts", ready: ".confirm-dialog",
    steps: async ({ page }) => {
      await page.locator(".fx-action-trigger").first().evaluate((el) => el.click())
      await page.locator(".fx-menu-item").last().click()
    } },
  { id: "C11", title: "Contracts, without revenue (desk login)", login: "staff", path: "/admin/contracts", ready: "table" },

  // ---- payments (module 3) -----------------------------------------------
  { id: "P1", title: "Payments, the list", login: "admin", path: "/admin/payments", ready: "table" },
  { id: "P2", title: "Payments, by bank transfer", login: "admin", path: "/admin/payments", ready: ".fx-active-chip",
    steps: async ({ page }) => {
      await press(page.locator(".fx-cat-tab").nth(2))
      await settleList(page)
    } },
  { id: "P3", title: "Payments, refunded only (none)", login: "admin", path: "/admin/payments", ready: ".fx-active-chip",
    steps: async ({ page }) => {
      await press(page.locator('label[for="payment-status-refunded"]'))
      await settleList(page)
    } },
  { id: "P4", title: "Payments, searched", login: "admin", path: "/admin/payments", ready: "mark.fx-hl",
    steps: async ({ page }) => {
      await page.locator(".lst-head-search input").fill("sa")
      await page.waitForTimeout(SEARCH_DEBOUNCE)
      await settleList(page)
    } },
  { id: "P5", title: "Payments, page 2", login: "admin", path: "/admin/payments", ready: "table",
    steps: async ({ page }) => {
      await press(page.locator(".app-pagination-controls button").last())
      await settleList(page)
    } },
  { id: "P6", title: "Payments, the record dialog (?action=new)", login: "admin", path: "/admin/payments?action=new", ready: ".modal-panel" },
  { id: "P7", title: "Payments, record: members found", login: "admin", path: "/admin/payments", ready: ".search-result-item",
    steps: async ({ page }) => {
      await press(page.locator(".lst-head .btn-primary"))
      await page.locator("#pay-client-search").fill("Hela")
      await settleList(page)
    } },
  { id: "P8", title: "Payments, record: what the member owes", login: "admin", path: "/admin/payments", ready: "#pay-amount",
    steps: async ({ page }) => {
      await press(page.locator(".lst-head .btn-primary"))
      await page.locator("#pay-client-search").fill("Hela")
      await page.locator(".search-result-item").first().click()
      await page.locator("#pay-payable").waitFor()
      await settleList(page)
      const first = await page.locator("#pay-payable option").nth(1).getAttribute("value")
      await page.locator("#pay-payable").selectOption(first)
    } },
  { id: "P9", title: "Payments, refunding: the confirmation", login: "admin", path: "/admin/payments", ready: ".confirm-dialog",
    steps: async ({ page }) => {
      await page.locator(".fx-action-trigger").first().evaluate((el) => el.click())
      await page.locator(".fx-menu-item.is-danger").click()
    } },

  // ---- the catalogue (module 4) ------------------------------------------
  { id: "G1", title: "Catalogue, the price grid", login: "admin", path: "/admin/catalogue", ready: "table.pg" },
  { id: "G2", title: "Catalogue, the activities", login: "admin", path: "/admin/catalogue?tab=activites", ready: ".act-list" },
  { id: "G3", title: "Catalogue, the formules", login: "admin", path: "/admin/catalogue?tab=formules", ready: ".plan-grid" },
  { id: "G4", title: "Catalogue, activities searched", login: "admin", path: "/admin/catalogue?tab=activites", ready: "mark.fx-hl",
    steps: async ({ page }) => {
      await page.locator(".act-toolbar input").fill("yo")
      await page.waitForLoadState("networkidle")
    } },
  { id: "G5", title: "Catalogue, editing an activity", login: "admin", path: "/admin/catalogue?tab=activites", ready: ".modal-panel #act-name",
    steps: async ({ page }) => {
      await page.locator(".fx-action-trigger").first().evaluate((el) => el.click())
      await page.locator(".fx-menu-item").first().click()
    } },
  { id: "G6", title: "Catalogue, a new one-to-one activity", login: "admin", path: "/admin/catalogue?tab=activites", ready: ".modal-panel #act-capacity:disabled",
    steps: async ({ page }) => {
      await press(page.locator(".act-toolbar .btn-outline-secondary"))
      await page.locator("#act-format").selectOption({ index: 0 }) // individual
    } },
  { id: "G7", title: "Catalogue, the activity catalogue", login: "admin", path: "/admin/catalogue?tab=activites", ready: ".ap-tile",
    steps: ({ page }) => press(page.locator(".act-toolbar .btn-primary")) },
  { id: "G8", title: "Catalogue, two picked, then searched", login: "admin", path: "/admin/catalogue?tab=activites", ready: ".ap-count strong",
    steps: async ({ page }) => {
      await press(page.locator(".act-toolbar .btn-primary"))
      await page.locator(".ap-tile").nth(0).click()
      await page.locator(".ap-tile").nth(3).click()
      await page.locator(".ap-search input").fill("bo")
    } },
  { id: "G9", title: "Catalogue, editing a formule", login: "admin", path: "/admin/catalogue?tab=formules", ready: ".modal-panel #mp-name",
    steps: ({ page }) => press(page.locator(".plan-card-foot .btn").first()) },
  { id: "G10", title: "Catalogue, a new carnet formule", login: "admin", path: "/admin/catalogue?tab=formules", ready: ".modal-panel #mp-sessions",
    steps: async ({ page }) => {
      await press(page.locator(".plan-toolbar .btn-primary"))
      await page.locator("#mp-period").selectOption("custom")
      await page.locator("#mp-kind-counted").check()
    } },
  { id: "G11", title: "Catalogue, deactivating an activity: the confirmation", login: "admin", path: "/admin/catalogue?tab=activites", ready: ".confirm-dialog",
    steps: async ({ page }) => {
      await page.locator(".fx-action-trigger").first().evaluate((el) => el.click())
      await page.locator(".fx-menu-item.is-danger").click()
    } },
  { id: "G12", title: "Catalogue, a salle with nothing yet: the three steps", login: "admin", salle: "lac", path: "/admin/catalogue", ready: ".cat-steps" },
  { id: "G13", title: "Catalogue, the grid with packs and a formule off sale", login: "admin", salle: "lac", db: ["lac_catalogue"], path: "/admin/catalogue", ready: ".pg-foot" },
  { id: "G14", title: "Catalogue, the packs", login: "admin", salle: "lac", db: ["lac_catalogue"], path: "/admin/catalogue?tab=packs", ready: ".pk-grid" },
  { id: "G15", title: "Catalogue, editing a pack", login: "admin", salle: "lac", db: ["lac_catalogue"], path: "/admin/catalogue?tab=packs", ready: ".modal-panel .pk-sep",
    steps: ({ page }) => press(page.locator(".pk-card-foot .btn").first()) },
  { id: "G17", title: "Catalogue, the activities of a salle with none", login: "admin", salle: "lac", path: "/admin/catalogue?tab=activites", ready: ".fx-state" },
  { id: "G16", title: "Catalogue, the formules with an inactive one", login: "admin", salle: "lac", db: ["lac_catalogue"], path: "/admin/catalogue?tab=formules", ready: ".plan-grid" },

  // ---- onboarding (module 4) --------------------------------------------
  { id: "O1", title: "Onboarding, a new salle: confirm the company", login: "admin", salle: "lac", path: "/admin/onboarding", ready: ".ob-facts" },
  { id: "O2", title: "Onboarding, Studio Lumen (one step left)", login: "admin", path: "/admin/onboarding", ready: ".obs-list" },
  { id: "O3", title: "Onboarding, the activities step", register: "B-07", login: "admin", salle: "lac", db: ["lac_onboarding_activities"], path: "/admin/onboarding", ready: ".obs-current" },
  { id: "O4", title: "Onboarding, the formules step", register: "B-07", login: "admin", salle: "lac", db: ["lac_onboarding_plans"], path: "/admin/onboarding", ready: ".obs-current" },

  // ---- the first salle (module 4) ------------------------------------------
  { id: "Y1", title: "Company setup, the details", login: "nosalle", path: "/admin/setup-company", ready: ".ss-value" },
  { id: "Y2", title: "Company setup, the country picker open and searched", login: "nosalle", path: "/admin/setup-company", ready: ".ss-panel li",
    steps: async ({ page }) => {
      await page.locator(".ss-trigger").click()
      await page.locator(".ss-search input").fill("ma")
    } },
  { id: "Y3", title: "Company setup, what it teaches", login: "nosalle", path: "/admin/setup-company", ready: ".ap-tile",
    steps: async ({ page }) => {
      await page.locator("#org-name").fill("Studio Parité")
      await page.locator(".setup-card button[type=submit]").click()
    } },
  { id: "Y4", title: "Company setup, two picked and one of its own", login: "nosalle", path: "/admin/setup-company", ready: ".ap-chips",
    steps: async ({ page }) => {
      await page.locator("#org-name").fill("Studio Parité")
      await page.locator(".setup-card button[type=submit]").click()
      await page.locator(".ap-tile").nth(0).click()
      await page.locator(".ap-tile").nth(2).click()
      await page.locator(".ap-other").click()
      await page.locator("#ap-custom-name").fill("Cardio danse")
      await page.locator(".ap-emoji-btn").nth(3).click()
      await page.locator(".ap-custom-actions .btn-primary").click()
    } },
  { id: "Y5", title: "Company setup, naming one of its own", login: "nosalle", path: "/admin/setup-company", ready: ".ap-custom",
    steps: async ({ page }) => {
      await page.locator("#org-name").fill("Studio Parité")
      await page.locator(".setup-card button[type=submit]").click()
      await page.locator(".ap-search input").fill("zumba")
      await page.locator(".ap-other").click()
    } },

  // ---- the team (module 5) ------------------------------------------------
  { id: "T1", register: "B-08", title: "Team, Studio Lumen", login: "admin", path: "/admin/team", ready: ".fx-people-grid" },
  { id: "T2", register: "B-08", title: "Team, searched (highlight)", login: "admin", path: "/admin/team", ready: "mark.fx-hl",
    steps: ({ page }) => page.locator(".lst-head-search input").fill("tra") },
  { id: "T3", register: "B-08", title: "Team, the back-office tab", login: "admin", path: "/admin/team", ready: ".fx-cat-tab.is-active",
    steps: ({ page }) => page.locator(".fx-cat-tab").nth(2).click() },
  { id: "T4", register: "B-08", title: "Team, nobody without access: no results and reset", login: "admin", path: "/admin/team", ready: ".lst-filters .btn-outline-secondary",
    steps: ({ page }) => page.locator('label[for="team-access-none"]').click() },
  { id: "T5", title: "Team, the Lac team (moderator, bio, inactive, no login)", login: "admin", salle: "lac", db: ["lac_team"], path: "/admin/team", ready: ".fx-people-grid" },
  { id: "T6", title: "Team, the drawer with the moderator seat taken", login: "admin", salle: "lac", db: ["lac_team"], path: "/admin/team", ready: ".team-seat-notice",
    steps: ({ page }) => press(page.locator(".lst-head .btn-primary")) },
  { id: "T7", register: "B-08", title: "Team, the drawer: a coach with a mobile login", login: "admin", path: "/admin/team", ready: "#tc-mpass",
    steps: async ({ page }) => {
      await press(page.locator(".lst-head .btn-primary"))
      await page.locator("#tc-first").fill("Rania")
      await page.locator("#tc-mobile").check()
    } },
  { id: "T8", register: "B-08", title: "Team, the drawer: a back-office login", login: "admin", path: "/admin/team", ready: "#tb-role",
    steps: async ({ page }) => {
      await press(page.locator(".lst-head .btn-primary"))
      await page.locator(".team-kind-opt").nth(1).click()
    } },
  { id: "T9", register: "B-08", title: "Team, the drawer: mobile access without credentials", login: "admin", path: "/admin/team", ready: ".fx-drawer-body .alert-danger",
    steps: async ({ page }) => {
      await press(page.locator(".lst-head .btn-primary"))
      await page.locator("#tc-first").fill("Rania")
      await page.locator("#tc-last").fill("Hamdi")
      await page.locator("#tc-mobile").check()
      await page.locator(".fx-drawer-footer .btn-primary").click()
    } },
  { id: "T10", register: "B-08", title: "Team, editing a coach", login: "admin", path: "/admin/team", ready: ".modal-panel #ec-first",
    steps: async ({ page }) => {
      await press(page.locator(".fx-person-card-actions .btn-outline-secondary").first())
      await page.waitForFunction(() => !document.querySelector("#ec-email")?.value.includes("****"))
    } },
  { id: "T11", register: "B-08", title: "Team, role and web access", login: "admin", path: "/admin/team", ready: ".modal-panel #er-role",
    steps: async ({ page }) => {
      await page.locator(".fx-cat-tab").nth(2).click()
      await press(page.locator(".fx-person-card-actions .btn-outline-secondary").first())
    } },
  { id: "T12", register: "B-08", title: "Team, a coach's mobile login", login: "admin", path: "/admin/team", ready: ".modal-panel #tl-email",
    steps: async ({ page }) => {
      await page.locator(".fx-action-trigger").first().evaluate((el) => el.click())
      await page.locator(".fx-menu-item").nth(1).click()
      await page.waitForFunction(() => !document.querySelector("#tl-email")?.value.includes("****"))
    } },
  { id: "T13", register: "B-08", title: "Team, deactivating: the confirmation", login: "admin", path: "/admin/team", ready: ".confirm-dialog",
    steps: async ({ page }) => {
      await page.locator(".fx-action-trigger").first().evaluate((el) => el.click())
      await page.locator(".fx-menu-item.is-danger").click()
    } },
  { id: "T16", title: "Team, Lac: searched", login: "admin", salle: "lac", db: ["lac_team"], path: "/admin/team", ready: "mark.fx-hl",
    steps: ({ page }) => page.locator(".lst-head-search input").fill("ka") },
  { id: "T17", title: "Team, Lac: the back-office tab and the reset", login: "admin", salle: "lac", db: ["lac_team"], path: "/admin/team", ready: ".lst-filters .btn-outline-secondary",
    steps: ({ page }) => page.locator(".fx-cat-tab").nth(2).click() },
  { id: "T18", title: "Team, Lac: the drawer, a coach with a mobile login", login: "admin", salle: "lac", db: ["lac_team"], path: "/admin/team", ready: "#tc-mpass",
    steps: async ({ page }) => {
      await press(page.locator(".lst-head .btn-primary"))
      await page.locator("#tc-first").fill("Rania")
      await page.locator("#tc-mobile").check()
    } },
  { id: "T19", title: "Team, Lac: editing a coach with a bio and a birthday", login: "admin", salle: "lac", db: ["lac_team"], path: "/admin/team", ready: ".modal-panel #ec-bio",
    steps: async ({ page }) => {
      await press(page.locator(".fx-person-card-actions .btn-outline-secondary").nth(2))
      await page.waitForFunction(() => !document.querySelector("#ec-email")?.value.includes("****"))
    } },
  { id: "T20", title: "Team, Lac: the moderator's role and access", login: "admin", salle: "lac", db: ["lac_team"], path: "/admin/team", ready: ".modal-panel #er-role",
    steps: ({ page }) => press(page.locator(".fx-person-card-actions .btn-outline-secondary").first()) },
  { id: "T21", title: "Team, Lac: a mobile login for a coach without one", login: "admin", salle: "lac", db: ["lac_team"], path: "/admin/team", ready: ".modal-panel #tl-email",
    steps: async ({ page }) => {
      await page.locator(".fx-action-trigger").nth(1).evaluate((el) => el.click())
      await page.locator(".fx-menu-item").nth(1).click()
      await page.waitForFunction(() => !document.querySelector("#tl-email")?.value.includes("****"))
    } },
  { id: "T22", title: "Team, Lac: the action menu", login: "admin", salle: "lac", db: ["lac_team"], path: "/admin/team", ready: ".fx-menu",
    steps: ({ page }) => page.locator(".fx-action-trigger").nth(1).evaluate((el) => el.click()) },
  { id: "T14", title: "Team, a salle with nobody yet", login: "admin", salle: "lac", path: "/admin/team", ready: ".fx-state" },
  { id: "T15", register: "B-08", title: "Team, ?action=new&type=backoffice", login: "admin", path: "/admin/team?action=new&type=backoffice", ready: "#tb-role" },

  // ---- my salles (module 5) ------------------------------------------------
  { id: "M1", title: "Salles, on the trial: locked", login: "admin", path: "/admin/salles", ready: ".pro-lock" },
  { id: "M2", title: "Salles, on Pro: the network", login: "admin", db: ["pro"], path: "/admin/salles", ready: ".sl-grid" },
  { id: "M3", title: "Salles, posting moderators to Lumen", login: "admin", db: ["pro", "lac_team"], path: "/admin/salles", ready: ".modal-panel .sl-pick",
    steps: ({ page }) => press(page.locator(".sl-card-foot .btn-outline-secondary").first()) },
  { id: "M4", title: "Salles, a moderator ticked: save open", login: "admin", db: ["pro", "lac_team"], path: "/admin/salles", ready: ".modal-panel .btn-primary:enabled",
    steps: async ({ page }) => {
      await press(page.locator(".sl-card-foot .btn-outline-secondary").first())
      await page.locator(".sl-pick input:not(:disabled)").first().check()
    } },
  { id: "M5", title: "Salles, opening another", login: "admin", db: ["pro"], path: "/admin/salles", ready: ".modal-panel #salle-timezone",
    steps: ({ page }) => press(page.locator(".fx-page-header-actions .btn-primary")) },
  { id: "M6", title: "Salles, opening another without a name", login: "admin", db: ["pro"], path: "/admin/salles", ready: ".modal-panel .is-invalid",
    steps: async ({ page }) => {
      await press(page.locator(".fx-page-header-actions .btn-primary"))
      await page.locator(".modal-panel button[type=submit]").click()
    } },
  { id: "M7", title: "Salles, from the Lac salle", login: "admin", salle: "lac", db: ["pro", "lac_team"], path: "/admin/salles", ready: ".sl-card.is-active" },

  // ---- settings (module 6) ------------------------------------------------
  { id: "E1", title: "Settings, the company", login: "admin", path: "/admin/settings/company", ready: ".ss-value" },
  { id: "E2", title: "Settings, branding on the trial: locked", login: "admin", path: "/admin/settings/branding", ready: ".pro-lock" },
  { id: "E3", title: "Settings, contracts and signature", login: "admin", path: "/admin/settings/contracts", ready: ".sp-paper" },
  { id: "E4", title: "Settings, planning", login: "admin", path: "/admin/settings/planning", ready: "#cal-hours-start" },
  { id: "E5", title: "Settings, booking rules", login: "admin", path: "/admin/settings/booking", ready: ".sb-group" },
  { id: "E6", title: "Settings, roles on the trial: locked", login: "admin", path: "/admin/settings/roles", ready: ".pro-lock" },
  { id: "E7", title: "Settings, appearance", login: "admin", path: "/admin/settings/appearance", ready: ".sa-row" },
  { id: "E8", title: "Settings, my account", login: "admin", path: "/admin/settings/account", ready: "#cp-current" },
  { id: "E9", title: "Settings, the Pro tools menu, locked", login: "admin", path: "/admin/settings/company", ready: ".settings-pro-menu", viewports: ["desktop"],
    steps: ({ page }) => page.locator(".settings-pro-btn").click() },
  { id: "E10", title: "Settings, a password mismatch", login: "admin", path: "/admin/settings/account", ready: ".text-danger",
    steps: async ({ page }) => {
      await page.locator("#cp-new").fill("one-password")
      await page.locator("#cp-confirm").fill("another-one")
      await page.locator("#cp-current").click()
    } },
  { id: "E11", title: "Settings, the country picker open", login: "admin", path: "/admin/settings/company", ready: ".ss-panel li",
    steps: async ({ page }) => {
      await page.locator(".ss-trigger").click()
      await page.locator(".ss-search input").fill("tu")
    } },
  { id: "E12", title: "Settings, Pro: branding", login: "admin", db: ["pro"], path: "/admin/settings/branding", ready: ".branding-preview-bar" },
  { id: "E13", title: "Settings, Pro: the roles matrix", login: "admin", db: ["pro"], path: "/admin/settings/roles", ready: ".rm-table" },
  { id: "E14", title: "Settings, Pro: roles edited (save bar)", login: "admin", db: ["pro"], path: "/admin/settings/roles", ready: ".rm-savebar",
    steps: async ({ page }) => {
      await page.locator("tr.rm-row button.rm-box:not(:disabled)").nth(1).click()
      await page.locator("tr.rm-group button.rm-box:not(:disabled)").nth(4).click()
    } },
  { id: "E15", title: "Settings, Pro: roles searched", login: "admin", db: ["pro"], path: "/admin/settings/roles", ready: ".rm-table",
    steps: ({ page }) => page.locator(".rm-search input").fill("pla") },
  { id: "E16", title: "Settings, Pro: roles searched, nothing", login: "admin", db: ["pro"], path: "/admin/settings/roles", ready: ".rm-empty",
    steps: ({ page }) => page.locator(".rm-search input").fill("zzz") },
  { id: "E17", title: "Settings, Pro: a new role", login: "admin", db: ["pro"], path: "/admin/settings/roles", ready: ".modal-panel #rm-name",
    steps: ({ page }) => press(page.locator(".rm-new")) },
  { id: "E18", title: "Settings, Pro: a new role without a name", login: "admin", db: ["pro"], path: "/admin/settings/roles", ready: ".modal-panel .invalid-feedback",
    steps: async ({ page }) => {
      await press(page.locator(".rm-new"))
      await page.locator(".modal-panel button[type=submit]").click()
    } },
  { id: "E19", title: "Settings, Pro: import / export", login: "admin", db: ["pro"], path: "/admin/settings/data-exchange", ready: ".data-exchange-upload" },
  { id: "E20", title: "Settings, Pro: an import previewed", login: "admin", db: ["pro"], path: "/admin/settings/data-exchange", ready: ".data-exchange-preview",
    steps: async ({ page }) => {
      await page.locator("#data-exchange-entity").selectOption("activities")
      await page.locator(".data-exchange-upload input").setInputFiles({ name: "activites.csv", mimeType: "text/csv", buffer: Buffer.from("name,emoji,duration\nZumba,💃,45\n\"Cardio, boxe\",🥊,60\n") })
    } },
  { id: "E21", title: "Settings, Pro: the mobile app's keys", login: "admin", db: ["pro"], path: "/admin/settings/mobile-app", ready: ".ma-qr svg" },
  { id: "E22", title: "Settings, Pro: the Pro tools menu", login: "admin", db: ["pro"], path: "/admin/settings/booking", ready: ".settings-pro-menu", viewports: ["desktop"],
    steps: ({ page }) => page.locator(".settings-pro-btn").click() },
  { id: "E23", title: "Settings, the signature drawn in the upload mode", login: "admin", path: "/admin/settings/contracts", ready: "#br-signature",
    steps: ({ page }) => page.locator(".branding-signature-head [role=tab]").nth(1).click() },

  // ---- the Fitora subscription (module 6) ---------------------------------
  { id: "F1", title: "Subscription, on the trial", login: "admin", path: "/admin/subscription", ready: ".sub-plan" },
  { id: "F2", title: "Subscription, three days left", login: "admin", db: ["trial_3"], path: "/admin/subscription", ready: ".sub-plan" },
  { id: "F3", title: "Subscription, on Pro", login: "admin", db: ["pro"], path: "/admin/subscription", ready: ".sub-plan" },
  { id: "F4", title: "Subscription, Pro priced by the year", login: "admin", db: ["pro"], path: "/admin/subscription", ready: ".sub-cta",
    steps: ({ page }) => page.locator(".sub-toggle button").nth(1).click() },
  { id: "F5", title: "Subscription, Pro → Starter: the warning", login: "admin", db: ["pro"], path: "/admin/subscription", ready: ".sub-warn",
    steps: ({ page }) => page.locator(".sub-opt").first().click() },
  { id: "F6", title: "Subscription, on the trial, Pro picked", login: "admin", path: "/admin/subscription", ready: ".sub-cta.is-request",
    steps: ({ page }) => page.locator(".sub-opt").nth(1).click() },
  { id: "F7", title: "Subscription, asking for Pro", login: "admin", path: "/admin/subscription", ready: ".modal-panel #upgrade-phone",
    steps: async ({ page }) => {
      await page.locator(".sub-opt").nth(1).click()
      await page.locator(".sub-cta.is-request").click()
    } },
  { id: "F8", title: "Subscription, asking without a phone", login: "admin", path: "/admin/subscription", ready: ".modal-panel .invalid-feedback",
    steps: async ({ page }) => {
      await page.locator(".sub-opt").nth(1).click()
      await page.locator(".sub-cta.is-request").click()
      await page.locator("#upgrade-phone").fill("")
      await page.locator(".modal-panel .btn-primary").click()
    } },

  // ---- the dashboard (module 7) ----------------------------------------------
  { id: "D1", title: "Dashboard, Studio Lumen", login: "admin", path: "/admin/dashboard", ready: ".dash-kpis" },
  { id: "D2", title: "Dashboard, the report export open", login: "admin", path: "/admin/dashboard", ready: "#export-month",
    steps: ({ page }) => page.locator(".dashboard-utility-toggle").first().click() },
  { id: "D3", title: "Dashboard, the export by year and the activity", login: "admin", path: "/admin/dashboard", ready: ".fx-list, .app-card .fx-state",
    steps: async ({ page }) => {
      await page.locator(".dashboard-utility-toggle").first().click()
      await page.locator("#export-period-type").selectOption("year")
      await page.locator(".dashboard-utility-toggle").nth(1).click()
    } },
  { id: "D4", title: "Dashboard, checking people in", login: "admin", path: "/admin/dashboard", ready: ".modal-panel .ckin-row, .modal-panel .fx-state",
    steps: ({ page }) => press(page.locator(".dash-day button").first()) },
  { id: "D5", title: "Dashboard, checking in, searched", login: "admin", path: "/admin/dashboard", ready: ".modal-panel mark.fx-hl",
    steps: async ({ page }) => {
      await press(page.locator(".dash-day button").first())
      await page.locator(".modal-panel .ckin-row").first().waitFor()
      const name = await page.locator(".modal-panel .ckin-name").first().textContent()
      await page.locator(".modal-panel .ckin-head input").fill(name.trim().slice(0, 3))
    } },
  { id: "D6", title: "Dashboard, a salle with nothing yet", login: "admin", salle: "lac", path: "/admin/dashboard", ready: ".dash-kpis" },

  // ---- a member's file (module 8) ------------------------------------------
  { id: "H1", title: "Member file, a full one", login: "admin", path: (app, _t, fx) => `/admin/clients/${fx.clients.salma}`, ready: ".prof-banner" },
  { id: "H2", title: "Member file, waiver not signed", login: "admin", path: (app, _t, fx) => `/admin/clients/${fx.clients.rania}`, ready: ".prof-banner" },
  { id: "H3", title: "Member file, money owed", login: "admin", path: (app, _t, fx) => `/admin/clients/${fx.clients.dali}`, ready: ".prof-banner" },
  { id: "H4", title: "Member file, nothing yet", login: "admin", path: (app, _t, fx) => `/admin/clients/${fx.clients.badr}`, ready: ".prof-banner" },
  { id: "H5", title: "Member file, the payments only", login: "admin", path: (app, _t, fx) => `/admin/clients/${fx.clients.salma}`, ready: ".prof-filter.is-active",
    steps: ({ page }) => page.locator(".prof-filter").nth(2).click() },
  { id: "H6", title: "Member file, the action menu", login: "admin", path: (app, _t, fx) => `/admin/clients/${fx.clients.salma}`, ready: ".fx-menu",
    steps: ({ page }) => page.locator(".fx-action-trigger").first().evaluate((el) => el.click()) },
  { id: "H7", title: "Member file, a new subscription", login: "admin", path: (app, _t, fx) => `/admin/clients/${fx.clients.badr}`, ready: ".modal-panel .abo-total-line",
    steps: async ({ page }) => {
      await press(page.locator(".prof-actions-row .btn-outline-secondary").nth(1))
      await selectByText(page, "#ms-plan", "Yoga illimité")
      await page.locator("#ms-activity option").nth(1).waitFor({ state: "attached" })
      await selectByText(page, "#ms-activity", "Yoga")
      await page.locator("#ms-discount").fill("10")
      await page.locator(".abo-collect input").check()
    } },
  { id: "H8", title: "Member file, a formule with no price", login: "admin", path: (app, _t, fx) => `/admin/clients/${fx.clients.badr}`, ready: ".modal-panel #ms-plan",
    steps: async ({ page }) => {
      await press(page.locator(".prof-actions-row .btn-outline-secondary").nth(1))
      await page.locator("#ms-plan").selectOption({ index: 1 })
    } },
  { id: "H9", title: "Member file, a booking", login: "admin", path: (app, _t, fx) => `/admin/clients/${fx.clients.badr}`, ready: ".modal-panel #bk-session option:nth-child(2)", readyState: "attached",
    steps: async ({ page }) => {
      await press(page.locator(".prof-actions-row .btn-outline-secondary").nth(2))
      await selectByText(page, "#bk-activity", "Yoga Vinyasa")
      await page.locator("#bk-date").fill("2026-10-15")
      await page.locator("#bk-date").dispatchEvent("change")
    } },
  { id: "H10", title: "Member file, a payment", login: "admin", path: (app, _t, fx) => `/admin/clients/${fx.clients.dali}`, ready: ".modal-panel #pm-payable",
    steps: ({ page }) => press(page.locator(".prof-actions-row .btn-primary")) },
  { id: "H11", title: "Member file, the health file", login: "admin", path: (app, _t, fx) => `/admin/clients/${fx.clients.salma}`, ready: ".modal-panel #hl-notes",
    steps: async ({ page }) => {
      await page.locator(".prof-health .btn").click()
      await page.waitForFunction(() => document.querySelector("#hl-notes")?.value !== "")
    } },
  { id: "H12", title: "Member file, not one of this salle's", login: "admin", path: "/admin/clients/00000000-0000-4000-8000-000000000000", ready: ".fx-state" },

  // ---- the planning (module 9) -----------------------------------------------
  { id: "L1", title: "Calendar, this week (the day below 992 px)", login: "admin", path: "/admin/calendar", ready: ".fc-event" },
  { id: "L2", serial: true, title: "Calendar, the month", login: "admin", path: "/admin/calendar", ready: ".fc-daygrid-event, .fc-event",
    steps: ({ page }) => page.locator(".fx-segmented button").nth(2).click() },
  { id: "L3", title: "Calendar, the day", login: "admin", path: "/admin/calendar", ready: ".fc-timeGridDay-view",
    steps: ({ page }) => page.locator(".fx-segmented button").nth(0).click() },
  { id: "L4", title: "Calendar, next week", login: "admin", path: "/admin/calendar", ready: ".fc-event",
    steps: async ({ page }) => {
      // Pressed in place: below 992 px the top bar overlaps the arrow in both apps.
      await press(page.locator(".fx-cal-nav .icon-btn").nth(1))
      await page.waitForLoadState("networkidle")
    } },
  { id: "L5", title: "Calendar, one coach's sessions", login: "admin", path: "/admin/calendar", ready: ".fx-cal-filters .btn",
    steps: async ({ page }) => {
      await selectByText(page, "#cal-coach-filter", "Sarah")
      await page.waitForLoadState("networkidle")
    } },
  { id: "L6", title: "Calendar, the hover card", login: "admin", path: "/admin/calendar", ready: ".fx-session-tip", viewports: ["desktop"],
    steps: ({ page }) => page.locator(".fc-timegrid-event").nth(3).hover() },
  { id: "L7", title: "Calendar, a session's detail", login: "admin", path: "/admin/calendar", ready: ".modal-panel .list-unstyled, .modal-panel p.text-muted-token",
    steps: ({ page }) => page.locator(".fc-event").nth(3).click() },
  { id: "L8", title: "Calendar, a new session", login: "admin", path: "/admin/calendar", ready: ".modal-panel #cs-activity",
    steps: ({ page }) => press(page.locator(".fx-cal-actions .btn-primary")) },
  { id: "L9", title: "Calendar, a new one-to-one session", login: "admin", path: "/admin/calendar", ready: ".modal-panel .ss-trigger",
    steps: async ({ page }) => {
      await press(page.locator(".fx-cal-actions .btn-primary"))
      await selectByText(page, "#cs-activity", "Coaching")
    } },
  { id: "L10", title: "Calendar, a weekly class", login: "admin", path: "/admin/calendar", ready: ".modal-panel #cs-repeat-until",
    steps: async ({ page }) => {
      await press(page.locator(".fx-cal-actions .btn-primary"))
      await selectByText(page, "#cs-activity", "Yoga")
      await page.locator("#cs-repeat").check()
    } },
  { id: "L11", title: "Calendar, a slot clicked", login: "admin", path: "/admin/calendar", ready: ".modal-panel #cs-time", viewports: ["desktop"],
    steps: ({ page }) => page.locator('.fc-timegrid-slot-lane[data-time="16:00:00"]').click({ position: { x: 5, y: 5 } }) },
  { id: "L12", title: "Calendar, a salle with no session", login: "admin", salle: "lac", path: "/admin/calendar", ready: ".fc-view" },

  // ---- the front desk (module 10) ------------------------------------------
  { id: "K1", title: "Desk, today", login: "desk", path: "/desk/dashboard", ready: ".desk-section" },
  { id: "K2", title: "Desk, check-in: pick a session", login: "desk", path: "/desk/checkin", ready: ".desk-session-picker, app-desk-checkin .fx-state" },
  { id: "K3", title: "Desk, check-in: a session's roster", login: "desk", path: "/desk/checkin", ready: ".ckin-head, app-checkin-panel .fx-state",
    steps: ({ page }) => page.locator(".desk-session-option").first().click() },
  { id: "K4", serial: true, title: "Desk, the search's results", login: "desk", path: "/desk/dashboard", ready: ".desk-result",
    steps: async ({ page }) => {
      await page.locator(".desk-search-input").fill("sal")
      await pastDebounce(page)
    } },
  { id: "K5", serial: true, title: "Desk, the search finds no one", login: "desk", path: "/desk/dashboard", ready: ".desk-results-empty",
    steps: async ({ page }) => {
      await page.locator(".desk-search-input").fill("zzzz")
      await pastDebounce(page)
    } },
  { id: "K6", title: "Desk, the user menu", login: "desk", path: "/desk/dashboard", ready: ".dropdown-menu-custom",
    steps: ({ page }) => page.locator(".user-menu-trigger").click() },

  // ---- a coach's day (module 10) -------------------------------------------
  { id: "Q1", title: "Coach, today", login: "coach", path: "/coach/today", ready: ".schedule-list, app-coach-today .fx-state" },
  { id: "Q2", title: "Coach, a session's roster", login: "coach", path: "/coach/today", ready: "app-coach-today .app-card + .app-card table, app-coach-today .app-card + .app-card .fx-state",
    steps: ({ page }) => page.locator(".schedule-row").first().click() },
  { id: "Q3", title: "Coach, the next day", login: "coach", path: "/coach/today", ready: ".schedule-list, app-coach-today .fx-state",
    steps: async ({ page }) => {
      await page.locator(".app-card-header .btn-outline-secondary").nth(1).click()
      await page.waitForLoadState("networkidle")
    } },
  { id: "Q4", title: "Coach, their members", login: "coach", path: "/coach/members", ready: ".coach-member-list, app-coach-members .fx-state" },
  { id: "Q5", serial: true, title: "Coach, a search with no match", login: "coach", path: "/coach/members", ready: "app-coach-members .fx-state",
    steps: async ({ page }) => {
      await page.locator(".coach-members-search input").fill("zzzz")
      await pastDebounce(page)
    } },
  { id: "Q6", title: "Coach, the menu on a phone", login: "coach", path: "/coach/today", ready: ".app-sidebar.is-open", viewports: ["mobile", "tablet"],
    steps: ({ page }) => page.locator(".app-topbar .icon-btn.d-lg-none").click() },
  { id: "Q7", title: "Coach, the user menu", login: "coach", path: "/coach/today", ready: ".dropdown-menu-custom",
    steps: ({ page }) => page.locator(".user-menu-trigger").click() },

  // ---- a member's own app (module 10): their gym on a paid Pro period -------
  { id: "M8", title: "Member, the schedule", login: "member", db: ["pro"], path: "/member/home", ready: ".mb-day, app-member-schedule .fx-state" },
  { id: "M9", title: "Member, upcoming bookings", login: "member", db: ["pro"], path: "/member/bookings", ready: "app-member-bookings .mb-list, app-member-bookings .fx-state" },
  { id: "M10", title: "Member, past bookings", login: "member", db: ["pro"], path: "/member/bookings", ready: "app-member-bookings .mb-list, app-member-bookings .fx-state",
    steps: async ({ page }) => {
      await page.locator(".fx-segmented button").nth(1).click()
      await page.waitForLoadState("networkidle")
    } },
  { id: "M11", title: "Member, their file", login: "member", db: ["pro"], path: "/member/profile", ready: ".mb-card--danger" },
  { id: "M12", title: "Member, editing their details", login: "member", db: ["pro"], path: "/member/profile", ready: "#me-first-name",
    steps: ({ page }) => page.locator(".mb-card .btn-outline-secondary .bi-pencil").click() },
  { id: "M13", title: "Member, leaving Fitora", login: "member", db: ["pro"], path: "/member/profile", ready: "#me-delete-password",
    steps: ({ page }) => page.locator(".mb-card--danger .btn-outline-danger").click() },
  { id: "M14", title: "Member, their menu", login: "member", db: ["pro"], path: "/member/home", ready: ".dropdown-menu-custom",
    steps: ({ page }) => page.locator(".user-menu-trigger").click() },

  // ---- the superadmin's console (module 10) -----------------------------------
  { id: "SA1", title: "Superadmin, overview", login: "superadmin", path: "/superadmin/overview", ready: ".ao-grid" },
  { id: "SA2", title: "Superadmin, the gyms", login: "superadmin", path: "/superadmin/companies", ready: ".companies-table, app-superadmin-companies .fx-state" },
  { id: "SA3", title: "Superadmin, the gyms searched", login: "superadmin", path: "/superadmin/companies", ready: "mark.fx-hl",
    steps: async ({ page }) => {
      await page.locator(".fx-toolbar input").fill("lumen")
      await page.waitForTimeout(SEARCH_DEBOUNCE)
      await page.waitForLoadState("networkidle")
    } },
  { id: "SA4", title: "Superadmin, a gym's billing", register: "B-15", login: "superadmin", path: (_app, _tokens, f) => `/superadmin/companies/${f.salles.lumen}`, ready: ".ac-ledger" },
  { id: "SA5", title: "Superadmin, a gym's own tab", login: "superadmin", path: (_app, _tokens, f) => `/superadmin/companies/${f.salles.lumen}`, ready: ".ac-usage",
    steps: ({ page }) => page.locator(".nav-tabs .nav-link").nth(1).click() },
  { id: "SA6", title: "Superadmin, pricing", login: "superadmin", path: "/superadmin/pricing", ready: ".pricing-plan" },
  { id: "SA7", title: "Superadmin, open tickets", login: "superadmin", path: "/superadmin/support", ready: ".support-row, app-superadmin-support-tickets .fx-state" },
  { id: "SA8", title: "Superadmin, every ticket", login: "superadmin", path: "/superadmin/support", ready: ".support-row, app-superadmin-support-tickets .fx-state",
    steps: async ({ page }) => {
      await page.locator(".fx-segmented button").nth(1).click()
      await page.waitForLoadState("networkidle")
    } },
  { id: "SA9", title: "Superadmin, a ticket", login: "superadmin", path: "/superadmin/support", ready: ".ticket-detail",
    steps: async ({ page }) => {
      await page.locator(".fx-segmented button").nth(1).click()
      await page.waitForLoadState("networkidle")
      await page.locator(".support-row").first().click()
    } },
  { id: "SA10", title: "Superadmin, release notes", login: "superadmin", path: "/superadmin/updates", ready: ".updates-timeline, app-superadmin-updates .fx-state" },
  { id: "SA11", title: "Superadmin, publishing a release", login: "superadmin", path: "/superadmin/updates", ready: "#upd-version",
    steps: ({ page }) => press(page.locator(".lst-head .btn-primary")) },
  { id: "SA12", title: "Superadmin, the language menu", login: "superadmin", path: "/superadmin/overview", ready: ".dropdown-menu-custom",
    steps: ({ page }) => page.locator(".superadmin-bar-ic .bi-translate").click() },

  // ---- the members list --------------------------------------------------
  { id: "V5", title: "Members, first page", login: "admin", path: "/admin/clients", ready: "table.fx-grid" },
  {
    id: "V6", title: "Members, search with matches", login: "admin", path: "/admin/clients", ready: "mark.fx-hl",
    steps: async ({ page }) => {
      await page.locator(".lst-head-search input").fill("sa")
      await page.waitForTimeout(SEARCH_DEBOUNCE)
      await settleList(page)
    },
  },
  {
    id: "V7", title: "Members, search without a match", login: "admin", path: "/admin/clients", ready: ".fx-state",
    steps: async ({ page }) => {
      await page.locator(".lst-head-search input").fill("zzzz")
      await page.waitForTimeout(SEARCH_DEBOUNCE)
      await settleList(page)
    },
  },
  ...["active", "inactive", "contract_active", "contract_expired", "no_contract"].map((status, i) => ({
    id: `V8${"abcde"[i]}`, title: `Members, status "${status}"`, login: "admin", path: "/admin/clients", ready: ".fx-chip-input:checked",
    steps: async ({ page }) => {
      await press(page.locator(`label[for="client-status-${status}"]`))
      await settleList(page)
    },
  })),
  {
    id: "V9", title: "Members, advanced filters open, two set", login: "admin", path: "/admin/clients", ready: ".fx-active-chip",
    steps: async ({ page }) => {
      await press(page.locator(".fx-adv-toggle"))
      await page.locator("#cl-f-plan").selectOption({ label: "Yoga illimité" })
      await settleList(page)
      await page.locator("#cl-f-gender").selectOption("female")
      await settleList(page)
    },
  },
  {
    // The joined column is hidden below desktop in both apps: attached, not visible.
    id: "V10", title: "Members, sorted by joined date, descending", login: "admin", path: "/admin/clients", ready: "th[aria-sort=descending]", readyState: "attached",
    steps: async ({ page }) => {
      await press(page.locator("th.fx-col-seen .fx-th-sort"))
      await settleList(page)
      await press(page.locator("th.fx-col-seen .fx-th-sort"))
      await settleList(page)
    },
  },
  {
    id: "V11", title: "Members, last page", login: "admin", path: "/admin/clients", ready: "table.fx-grid",
    steps: async ({ page }) => {
      for (;;) {
        const next = page.locator(".app-pagination-controls button").last()
        if (await next.isDisabled()) break
        await press(next)
        await settleList(page)
      }
    },
  },
  { id: "V12", title: "Members, a salle with nobody yet", login: "admin", salle: "lac", path: "/admin/clients", ready: ".fx-state" },
  {
    id: "V13", title: "Members, the list fails to load", login: "admin", path: "/admin/clients", ready: ".fx-state--danger",
    steps: async ({ page, app }) => {
      const pattern = app === "angular" ? "**/api/v1/clients?**" : "**/admin/*/clients?**"
      await page.route(pattern, (route) => route.fulfill({ status: 500, body: "" }))
      await press(page.locator('label[for="client-status-active"]'))
      await page.locator(".fx-state--danger").waitFor()
    },
  },
  { id: "V14", title: "Members, as front-desk staff (address unconfirmed)", login: "staff", path: "/admin/clients", ready: "table.fx-grid" },
  { id: "V15a", title: "Shell, trial with 3 days left", login: "admin", path: "/admin/clients", ready: ".trial-shell-banner", db: ["trial_3"] },
  { id: "V15b", title: "Shell, trial ended today", login: "admin", path: "/admin/clients", ready: ".trial-shell-banner", db: ["trial_0"] },

  // ---- the new-member wizard -----------------------------------------------
  {
    id: "V16a", title: "Wizard, step 1, empty", login: "admin", path: "/admin/clients", ready: "#cl-first",
    steps: ({ page }) => openWizard(page),
  },
  {
    id: "V16b", title: "Wizard, step 1, filled, more details open", login: "admin", path: "/admin/clients", ready: "#cl-email",
    steps: async ({ page }) => {
      await openWizard(page)
      await fillIdentity(page)
      await page.locator(".modal-panel .btn-link").click()
    },
  },
  {
    id: "V17a", title: "Wizard, step 2, a plan chosen", login: "admin", path: "/admin/clients", ready: ".fx-summary-row",
    steps: async ({ page }) => {
      await toPlanStep(page)
      await choosePlan(page)
    },
  },
  {
    id: "V17b", title: "Wizard, step 2, an activity no plan prices", login: "admin", path: "/admin/clients", ready: ".text-warning",
    steps: async ({ page }) => {
      await toPlanStep(page)
      await page.locator("#cl-activity").selectOption({ label: "🤸 Stretching" })
    },
  },
  {
    id: "V18a", title: "Wizard, step 3, paying now", login: "admin", path: "/admin/clients", ready: "#cl-method",
    steps: async ({ page }) => {
      await toPlanStep(page)
      await choosePlan(page)
      await page.locator(".modal-panel button[type=submit]").click()
      await page.locator("#cl-collect").waitFor()
    },
  },
  {
    id: "V18b", title: "Wizard, step 3, paying later", login: "admin", path: "/admin/clients", ready: "#cl-collect:not(:checked)",
    steps: async ({ page }) => {
      await toPlanStep(page)
      await choosePlan(page)
      await page.locator(".modal-panel button[type=submit]").click()
      await page.locator("#cl-collect").uncheck()
    },
  },

  // ---- the shell's menus ---------------------------------------------------
  {
    id: "V19a", title: "Shell, user menu open", login: "admin", path: "/admin/clients", ready: ".dropdown-menu-end",
    steps: ({ page }) => page.locator(".user-menu-trigger").click(),
  },
  {
    id: "V19b", title: "Shell, salle switcher open", login: "admin", path: "/admin/clients", ready: ".app-company-switcher-item",
    viewports: ["tablet", "desktop"],
    steps: ({ page }) => page.locator(".app-company-switcher-trigger").click(),
  },
  {
    id: "V20", title: "Shell, mobile menu open", login: "admin", path: "/admin/clients", ready: ".app-navbar-mobile",
    viewports: ["mobile", "tablet"],
    steps: ({ page }) => page.locator(".app-navbar-burger").click(),
  },

  // ---- the command palette (⌘K) ---------------------------------------------
  { id: "X1", title: "Palette, open", login: "admin", path: "/admin/clients", ready: ".cmdk-item",
    steps: ({ page }) => page.locator(".app-navbar-search").click() },
  { id: "X2", title: "Palette, a term: pages, actions, members, contracts, payments", login: "admin", path: "/admin/clients", ready: ".cmdk-item .cmdk-sub",
    steps: async ({ page }) => {
      await page.keyboard.press("Control+k")
      await page.locator("#cmdk-input").fill("sa")
      await page.waitForTimeout(250 + 200)
      await page.waitForLoadState("networkidle")
      await page.keyboard.press("ArrowDown")
    } },
]
