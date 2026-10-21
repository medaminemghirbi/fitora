import { Controller } from "@hotwired/stimulus"
import { saveCompany } from "./settings_company_controller"
import { refreshShellNav } from "../lib/branding"
import { toast } from "../lib/toast"

// SettingsBookingComponent: each rule saved the moment it changes — only
// its own section sent — and the screen redrawn from what the server kept
// (it clamps and drops). A feature switch also changes the menus (rooms,
// packs), which follow it. While a save runs, every control waits.
export default class extends Controller {
  static targets = ["online", "sms"]
  static values = { url: String, labels: Object }

  connect() {
    this.settings = this.read()
  }

  // The state as the controls show it.
  read() {
    const features = {}
    const booking = {}
    this.element.querySelectorAll("[data-feature]").forEach((input) => (features[input.dataset.feature] = input.checked))
    this.element.querySelectorAll("[data-rule]").forEach((input) => {
      if (input.closest("template")) return
      booking[input.dataset.rule] = input.type === "checkbox" ? input.checked : Number(input.value)
    })
    return { features, booking }
  }

  async change(event) {
    const input = event.target
    const value = input.type === "checkbox" ? input.checked : Number(input.value)
    const section = input.dataset.feature ? "features" : "booking"
    const key = input.dataset.feature ?? input.dataset.rule
    const before = structuredClone(this.settings)
    this.settings[section] = { ...this.settings[section], [key]: value }
    this.render()
    this.busy(true)
    const result = await saveCompany(this.urlValue, { company: { settings: { [section]: { [key]: value } } } })
    this.busy(false)
    if (result.ok) {
      this.settings = { features: { ...result.company.settings.features }, booking: { ...result.company.settings.booking } }
      this.render()
      toast("success", this.labelsValue.saved)
      if (section === "features") refreshShellNav()
    } else {
      toast("error", result.error ?? this.labelsValue.error)
      // load(): the server's version again.
      this.settings = before
      this.render()
    }
  }

  render() {
    const { features, booking } = this.settings
    this.element.querySelectorAll("[data-feature]").forEach((input) => (input.checked = Boolean(features[input.dataset.feature])))
    this.toggleRows("online", Boolean(features.online_booking), "#sb-online")
    this.toggleRows("sms", booking.reminder_hours > 0, "#sb-reminder")
    this.element.querySelectorAll("[data-rule]").forEach((input) => {
      const value = booking[input.dataset.rule]
      if (input.type === "checkbox") input.checked = Boolean(value)
      else if (value !== undefined) input.value = String(value)
    })
  }

  // The rows that only make sense with another rule on, after that rule's row.
  toggleRows(name, shown, anchor) {
    const ids = [...this[`${name}Target`].content.children].map((row) => row.querySelector("[id]").id)
    const present = ids.map((id) => this.element.querySelector(`.sb-group #${id}`)?.closest(".sb-row")).filter(Boolean)
    if (shown && present.length === 0) {
      this.element.querySelector(anchor).closest(".sb-row").after(this[`${name}Target`].content.cloneNode(true))
    } else if (!shown) {
      present.forEach((row) => row.remove())
    }
  }

  busy(on) {
    this.element.querySelectorAll(".sb-group input, .sb-group select").forEach((control) => (control.disabled = on))
  }
}
