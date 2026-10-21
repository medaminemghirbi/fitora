import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { confirmAsk } from "../lib/confirm"
import { csrfToken, interpolate } from "../lib/ng"
import { toast } from "../lib/toast"

// SuperadminCompanyDetailComponent:
//
// - the tabs and the ledger's years switch in place: the one not shown
//   waits in a <template>, as Angular's @if keeps it out of the DOM; the tab
//   stays in the URL (?tab=gym, M-05);
// - every write (access, plan, billing period, an invoice in or out, the
//   gym's language and currency) waits on its button, then the page comes
//   back as the server has it, with the server's toast; a refusal is a toast
//   with the server's words and changes nothing;
// - stepping inside the gym's account: the admin's dashboard, in their
//   session (Web::Authentication#start_impersonation).
export default class extends Controller {
  static targets = ["pane", "year", "ledger", "settings", "settingsFoot"]
  static values = { url: String, tab: String, labels: Object }

  setTab({ params: { tab } }) {
    if (tab === this.tabValue) return
    const tabs = this.element.querySelector(".nav-tabs")
    const shown = document.createElement("template")
    shown.dataset.superadminCompanyTarget = "pane"
    shown.dataset.tab = this.tabValue
    while (tabs.nextElementSibling && tabs.nextElementSibling.tagName !== "TEMPLATE") shown.content.append(tabs.nextElementSibling)
    const next = this.paneTargets.find((t) => t.dataset.tab === tab)
    tabs.after(next.content)
    next.replaceWith(shown)
    this.tabValue = tab
    tabs.querySelectorAll(".nav-link").forEach((link) => link.classList.toggle("active", link.dataset.superadminCompanyTabParam === tab))
    history.replaceState(history.state, "", tab === "gym" ? `${this.urlValue}?tab=gym` : this.urlValue)
  }

  showYear({ currentTarget, params: { year } }) {
    currentTarget.parentElement.querySelectorAll("button").forEach((button) => {
      button.classList.toggle("is-active", button === currentTarget)
      if (!button.classList.length) button.removeAttribute("class")
    })
    const [summary, ...cells] = this.yearTargets.find((t) => Number(t.dataset.year) === year).content.cloneNode(true).children
    this.element.querySelector(".ac-ledger-head > div > p").replaceWith(summary)
    this.ledgerTarget.replaceChildren(...cells)
  }

  async impersonate(event) {
    const button = event.currentTarget
    button.disabled = true
    const response = await this.send("POST", `${this.urlValue}/impersonate`)
    if (response?.ok) return window.location.assign((await response.json()).next)
    button.disabled = false
    toast("error", await this.errorOf(response))
  }

  issueInvoice(event) {
    this.write(event.currentTarget, "POST", `${this.urlValue}/invoices`)
  }

  async voidInvoice({ currentTarget, params: { id, number } }) {
    const confirmed = await confirmAsk({ title: this.labelsValue.void_title, body: interpolate(this.labelsValue.void_body, { number }), danger: true })
    if (confirmed) this.write(currentTarget, "DELETE", `${this.urlValue}/invoices/${id}`)
  }

  toggleAccess({ currentTarget, params: { active } }) {
    this.write(currentTarget, "PATCH", `${this.urlValue}/subscription`, { active })
  }

  changePlan(event) {
    this.write(event.currentTarget, "PATCH", `${this.urlValue}/subscription`, { plan: event.currentTarget.value })
  }

  changeBillingPeriod(event) {
    this.write(event.currentTarget, "PATCH", `${this.urlValue}/subscription`, { billing_period: event.currentTarget.value })
  }

  // #settingsDirty: the save button only once a choice differs from the gym's.
  settingsChanged() {
    const card = this.settingsTarget
    const dirty = card.querySelector("[name=currency]").value !== card.dataset.currency || card.querySelector("[name=locale]").value !== card.dataset.locale
    const foot = card.querySelector(".ac-card-foot")
    if (dirty && !foot) this.settingsFootTarget.before(this.settingsFootTarget.content.cloneNode(true))
    if (!dirty) foot?.remove()
  }

  saveSettings(event) {
    const card = this.settingsTarget
    const company = { currency: card.querySelector("[name=currency]").value, locale: card.querySelector("[name=locale]").value }
    this.write(event.currentTarget, "PATCH", `${this.urlValue}/settings`, { company })
  }

  // ---------------------------------------------------------------------

  async write(control, method, url, payload) {
    const before = control.tagName === "SELECT" ? control.dataset.value ?? [...control.options].find((o) => o.defaultSelected)?.value : null
    control.disabled = true
    if (control.matches("[data-action*=saveSettings]")) control.textContent = ` ${this.labelsValue.saving} `
    const response = await this.send(method, url, payload)
    if (response?.ok) return Turbo.visit(window.location.href, { action: "replace" })

    control.disabled = false
    if (before !== null) control.value = before
    toast("error", await this.errorOf(response))
  }

  send(method, url, payload) {
    return fetch(url, {
      method,
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      credentials: "same-origin",
      body: payload ? JSON.stringify(payload) : undefined,
    }).catch(() => null)
  }

  async errorOf(response) {
    const body = response ? await response.json().catch(() => null) : null
    return body?.error || this.labelsValue.error
  }
}
