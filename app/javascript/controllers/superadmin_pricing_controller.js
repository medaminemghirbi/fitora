import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { csrfToken, interpolate, money } from "../lib/ng"
import { toast } from "../lib/toast"

// SuperadminPricingComponent: another currency loads its prices (?currency=,
// M-05); each year is worked out as the prices and the discount are typed
// (#annualUnits); "save" only once something differs from what is saved
// (#dirty), then the page comes back as the server has it, with its toast.
export default class extends Controller {
  static targets = ["save"]
  static values = { url: String, currency: String, symbol: String, discount: Number, preview: String, labels: Object }

  changeCurrency(event) {
    Turbo.visit(`${this.urlValue}?currency=${encodeURIComponent(event.target.value)}`, { action: "replace" })
  }

  changed() {
    const discount = this.discount()
    for (const row of this.rows()) {
      const annual = Math.round(this.units(row) * 12 * (100 - discount)) / 100
      row.querySelector("[data-preview]").textContent = interpolate(this.previewValue, { amount: money(annual, this.symbolValue) })
    }
    this.saveTarget.disabled = !this.dirty()
  }

  async save() {
    const button = this.saveTarget
    button.disabled = true
    button.textContent = ` ${this.labelsValue.saving} `
    const plans = Object.fromEntries(this.rows().map((row) => [row.dataset.plan, Math.max(0, Math.round(this.units(row) * 100))]))
    const response = await fetch(`${this.urlValue}?currency=${encodeURIComponent(this.currencyValue)}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      credentials: "same-origin",
      body: JSON.stringify({ plans, annual_discount_percent: this.discount() }),
    }).catch(() => null)
    if (response?.ok) return Turbo.visit(window.location.href, { action: "replace" })

    button.textContent = ` ${this.labelsValue.save} `
    button.disabled = !this.dirty()
    const body = response ? await response.json().catch(() => null) : null
    toast("error", body?.error || this.labelsValue.error)
  }

  // ---------------------------------------------------------------------

  rows() {
    return [...this.element.querySelectorAll(".pricing-plan")]
  }

  // An emptied number field is null to ngModel, and null counts as 0.
  units(row) {
    return Number(row.querySelector("input").value || 0)
  }

  discount() {
    return Number(this.element.querySelector("#pricing-discount").value || 0)
  }

  dirty() {
    return this.discount() !== this.discountValue || this.rows().some((row) => Math.round(this.units(row) * 100) !== Number(row.dataset.cents))
  }
}
