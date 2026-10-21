import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { send } from "../lib/crud"
import { toast } from "../lib/toast"

// OnboardingComponent's actions: confirm the company step, skip a step,
// re-read the flow, leave it. While one runs its buttons are disabled
// (working); the flow is then the page again, as the server now has it.
export default class extends Controller {
  static values = { url: String, home: String, error: String }

  confirmCompany() {
    this.act(() => send("POST", `${this.urlValue}/complete`, { step: "company" }))
  }

  skip(event) {
    const step = event.currentTarget.dataset.step
    this.act(() => send("POST", `${this.urlValue}/skip`, { step }))
  }

  refresh() {
    this.act(async () => ({ ok: true }))
  }

  async leave() {
    const result = await send("POST", `${this.urlValue}/dismiss`)
    if (!result.ok) return toast("error", result.error || this.errorValue)
    Turbo.visit(this.homeValue)
  }

  async act(request) {
    const buttons = [...this.element.querySelectorAll("[data-working]")]
    buttons.forEach((button) => (button.disabled = true))
    const result = await request()
    if (!result.ok) {
      buttons.forEach((button) => (button.disabled = false))
      return toast("error", result.error || this.errorValue)
    }
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
