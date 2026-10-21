import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { csrfToken } from "../lib/ng"

// VerifyEmailComponent: spends the link's token, then shows how it went —
// confirmed (and, signed in here, moves on by itself once the progress has
// ticked over), or not. Tells the "check your inbox" screen, if it is open
// in another tab, at once. The markup of each outcome is a <template> the
// page rendered (data-ve="…"). This element is the envelope's host, which
// stays; the "checking" title after it is what the outcome replaces.
export const AUTH_CHANNEL = "fitora-auth"

export default class extends Controller {
  static values = { token: String, authenticated: Boolean, delay: Number }

  async connect() {
    if (!this.tokenValue) return this.show(false, "/connexion")

    try {
      const response = await fetch("/verify-email", {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
        credentials: "same-origin",
        body: JSON.stringify({ token: this.tokenValue }),
      })
      const outcome = await response.json()
      this.show(outcome.status === "success", outcome.continue_url)
    } catch {
      this.show(false, "/connexion")
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  show(success, continueUrl) {
    const key = success ? (this.authenticatedValue ? "success-in" : "success-elsewhere") : (this.authenticatedValue ? "error-in" : "error-out")
    this.element.replaceChildren(this.template(`stage-${success ? "confirmed" : "error"}`))

    const nodes = [...this.template(key).childNodes]
    this.element.nextElementSibling.replaceWith(...nodes)

    for (const node of nodes) {
      const link = node.matches?.("[data-ve-continue-link]") ? node : null
      if (link) link.href = continueUrl
      if (node.matches?.("[data-ve-continue]")) node.addEventListener("click", () => this.continue(continueUrl))
    }

    if (success) {
      if (typeof BroadcastChannel !== "undefined") {
        const channel = new BroadcastChannel(AUTH_CHANNEL)
        channel.postMessage({ type: "email-verified" })
        channel.close()
      }
      if (this.authenticatedValue) this.timer = setTimeout(() => this.continue(continueUrl), this.delayValue)
    }
  }

  continue(url) {
    clearTimeout(this.timer)
    Turbo.visit(url)
  }

  template(name) {
    return document.querySelector(`template[data-ve="${name}"]`).content.cloneNode(true)
  }
}
