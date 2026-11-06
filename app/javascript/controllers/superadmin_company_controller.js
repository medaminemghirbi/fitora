import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { confirmAsk } from "../lib/confirm"
import { csrfToken, interpolate } from "../lib/ng"
import { toast } from "../lib/toast"

// One gym's account (web/superadmin/companies/show):
//
// - every write (the credentials sent again, the gym's language and currency)
//   waits on its button, then the page comes back as the server has it, with
//   the server's toast; a refusal is a toast with the server's words and
//   changes nothing;
// - stepping inside the gym's account: the admin's dashboard, in their
//   session (Web::Authentication#start_impersonation).
export default class extends Controller {
  static targets = ["settings", "settingsFoot"]
  static values = { url: String, labels: Object, email: String }

  async impersonate(event) {
    const button = event.currentTarget
    button.disabled = true
    const response = await this.send("POST", `${this.urlValue}/impersonate`)
    if (response?.ok) return window.location.assign((await response.json()).next)
    button.disabled = false
    toast("error", await this.errorOf(response))
  }

  async sendCredentials({ currentTarget }) {
    const confirmed = await confirmAsk({
      title: this.labelsValue.resend_title,
      body: interpolate(this.labelsValue.resend_body, { email: this.emailValue }),
      confirmLabel: this.labelsValue.resend_confirm,
    })
    if (confirmed) this.write(currentTarget, "POST", `${this.urlValue}/credentials`)
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
    control.disabled = true
    if (control.matches("[data-action*=saveSettings]")) control.textContent = ` ${this.labelsValue.saving} `
    const response = await this.send(method, url, payload)
    if (response?.ok) return Turbo.visit(window.location.href, { action: "replace" })

    control.disabled = false
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
