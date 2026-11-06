import { Controller } from "@hotwired/stimulus"
import { NG_EMAIL, csrfToken } from "../lib/ng"
import { COUNTRIES, ensureTimezone, timezoneForCountry, toCountryCode } from "../lib/places"
import { toast } from "../lib/toast"

// What a section's form may hold. Each form sends the fields it has, so the
// gym's profile and its legal details save apart, the other left as it is.
const FIELDS = ["name", "description", "phone", "email", "address", "city", "tax_id", "country", "timezone"]

// The gym's profile, and its legal details with the country picker and the
// timezone list, filled here: picking a country moves the timezone to that
// country's main zone. Saved as PATCH /api/v1/company saves it.
export default class extends Controller {
  static targets = ["form", "country"]
  static values = { url: String, country: String, timezone: String, labels: Object }

  connect() {
    if (this.formTarget.elements.timezone) this.fillTimezones(this.timezoneValue || "Africa/Tunis")
    if (!this.hasCountryTarget) return

    const country = toCountryCode(this.countryValue)
    this.formTarget.elements.country.value = country
    queueMicrotask(() => {
      this.countrySelect?.setOptions(COUNTRIES.map((c) => ({ value: c.code, label: c.name, prefix: c.flag })), country)
    })
    this.countryTarget.addEventListener("searchable-select:change", (event) => {
      this.formTarget.elements.country.value = event.detail.value
      const tz = timezoneForCountry(event.detail.value)
      if (tz) this.fillTimezones(tz)
    })
  }

  get countrySelect() {
    return this.application.getControllerForElementAndIdentifier(this.countryTarget, "searchable-select")
  }

  fillTimezones(tz) {
    const select = this.formTarget.elements.timezone
    select.replaceChildren()
    for (const group of ensureTimezone(tz)) {
      const optgroup = document.createElement("optgroup")
      optgroup.label = group.region
      for (const zone of group.zones) optgroup.append(new Option(zone.label, zone.value))
      select.append(optgroup)
    }
    select.value = tz
  }

  async submit(event) {
    event.preventDefault()
    const f = this.formTarget.elements
    if (this.refuse(f.name, !f.name?.value) || this.refuse(f.email, f.email?.value && !NG_EMAIL.test(f.email.value)) || this.refuse(f.timezone, !f.timezone?.value)) return

    const save = this.formTarget.querySelector("[data-save]")
    save.disabled = true
    save.textContent = ` ${this.labelsValue.saving} `
    const company = {}
    for (const key of FIELDS) if (f[key]) company[key] = f[key].value
    const result = await saveCompany(this.urlValue, { company })
    save.disabled = false
    save.textContent = ` ${this.labelsValue.save} `
    if (result.ok) {
      toast("success", this.labelsValue.saved)
      this.formTarget.dispatchEvent(new CustomEvent("settings:saved", { bubbles: true }))
    } else {
      toast("error", result.error ?? this.labelsValue.error)
    }
  }

  // A field this form holds that cannot be sent as it stands: marked, and the
  // focus goes there.
  refuse(field, wrong) {
    if (!field) return false
    field.classList.toggle("is-invalid", Boolean(wrong))
    if (wrong) field.focus()
    return Boolean(wrong)
  }
}

// PATCH …/settings/company: { ok, company } or { ok: false, error }.
export async function saveCompany(url, body) {
  const multipart = body instanceof FormData
  const response = await fetch(url, {
    method: "PATCH", credentials: "same-origin",
    headers: { Accept: "application/json", "X-CSRF-Token": csrfToken(), ...(multipart ? {} : { "Content-Type": "application/json" }) },
    body: multipart ? body : JSON.stringify(body),
  }).catch(() => null)
  const payload = await response?.json().catch(() => ({}))
  return response?.ok ? { ok: true, company: payload.company } : { ok: false, error: payload?.error ?? null }
}
