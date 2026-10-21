import { Controller } from "@hotwired/stimulus"
import { saveCompany } from "./settings_company_controller"
import { toast } from "../lib/toast"

// SettingsPlanningComponent: the working days (toggled, kept in Ruby wday
// order) and the calendar's hours, saved together.
export default class extends Controller {
  static values = { url: String, days: Array, labels: Object }

  connect() {
    this.days = [...this.daysValue]
  }

  toggle(event) {
    const button = event.currentTarget
    const value = Number(button.dataset.day)
    this.days = this.days.includes(value) ? this.days.filter((d) => d !== value) : [...this.days, value].sort((a, b) => a - b)
    const on = this.days.includes(value)
    button.classList.toggle("btn-primary", on)
    button.classList.toggle("btn-outline-secondary", !on)
    button.setAttribute("aria-pressed", String(on))
  }

  async submit(event) {
    event.preventDefault()
    const form = event.target
    const f = form.elements
    if (!f.business_hours_start.value || !f.business_hours_end.value) return
    if (this.days.length === 0) return toast("error", this.labelsValue.days_required)
    const save = form.querySelector("[data-save]")
    save.disabled = true
    save.textContent = ` ${this.labelsValue.saving} `
    const result = await saveCompany(this.urlValue, {
      company: { business_hours_start: f.business_hours_start.value, business_hours_end: f.business_hours_end.value, working_days: this.days },
    })
    save.disabled = false
    save.textContent = ` ${this.labelsValue.save} `
    if (result.ok) toast("success", this.labelsValue.saved)
    else toast("error", result.error ?? this.labelsValue.error)
  }
}
