import { Controller } from "@hotwired/stimulus"
import { NG_EMAIL, csrfToken } from "../lib/ng"
import { COUNTRIES, ensureTimezone, timezoneForCountry, toCountryCode } from "../lib/places"
import { toast } from "../lib/toast"

// SettingsCompanyComponent: the profile form. The country picker and the
// timezone list are filled here; picking a country moves the timezone to
// that country's main zone. Saved as PATCH /api/v1/company saves it.
export default class extends Controller {
  static targets = ["form", "country"]
  static values = { url: String, country: String, timezone: String, labels: Object }

  connect() {
    this.country = toCountryCode(this.countryValue)
    this.fillTimezones(this.timezoneValue || "Africa/Tunis")
    queueMicrotask(() => {
      this.countrySelect?.setOptions(COUNTRIES.map((c) => ({ value: c.code, label: c.name, prefix: c.flag })), this.country)
    })
    this.countryTarget.addEventListener("searchable-select:change", (event) => {
      this.country = event.detail.value
      const tz = timezoneForCountry(this.country)
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
    // Validators: the name, an address when one is given, the timezone.
    if (!f.name.value || (f.email.value && !NG_EMAIL.test(f.email.value)) || !f.timezone.value) return
    const save = this.formTarget.querySelector("[data-save]")
    save.disabled = true
    save.textContent = ` ${this.labelsValue.saving} `
    const company = {
      name: f.name.value, description: f.description.value, phone: f.phone.value, email: f.email.value,
      country: this.country, city: f.city.value, address: f.address.value, timezone: f.timezone.value,
    }
    const result = await saveCompany(this.urlValue, { company })
    save.disabled = false
    save.textContent = ` ${this.labelsValue.save} `
    if (result.ok) toast("success", this.labelsValue.saved)
    else toast("error", result.error ?? this.labelsValue.error)
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
