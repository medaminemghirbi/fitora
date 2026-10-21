import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { NG_EMAIL as EMAIL, csrfToken, interpolate, spinner } from "../lib/ng"
import { COUNTRIES, CURRENCIES, ensureTimezone, guessLocation, timezoneForCountry } from "../lib/places"

const PREP_MS = 5000

// CompanySetupComponent. Two steps — who the salle is, then what it
// teaches — swapped in place (the step not shown is kept aside, as the
// component's form group keeps its values), then the salle is opened and
// the "getting your account ready" moment holds for at least five seconds
// before the getting-started guide.
export default class extends Controller {
  static targets = ["card", "form", "country", "activitiesStep", "stepsTemplate"]
  static values = { url: String, labels: Object }

  connect() {
    // The "getting ready" scene takes the page out of the DOM and puts it
    // back on a refusal: Stimulus then connects this same controller again.
    if (this.started) return
    this.started = true
    // guessLocation(): the browser's own timezone, and its country.
    const detected = guessLocation()
    this.country = detected.country
    this.selected = []
    this.custom = []
    // Held: on the second step the details are out of the DOM, where
    // Stimulus can no longer find them as a target.
    this.form = this.formTarget

    const f = this.form.elements
    for (const group of ensureTimezone(detected.timezone)) {
      const optgroup = document.createElement("optgroup")
      optgroup.label = group.region
      for (const zone of group.zones) optgroup.append(new Option(zone.label, zone.value))
      f.timezone.append(optgroup)
    }
    f.timezone.value = detected.timezone
    for (const c of CURRENCIES) f.currency.append(new Option(`${this.labelsValue.currencies[c.code] ?? `currency.${c.code}`} — ${c.symbol} (${c.code})`, c.code))
    f.currency.value = "TND"

    // The country picker, once its controller is up; picking a country
    // moves the timezone to that country's main zone.
    queueMicrotask(() => this.countrySelect?.setOptions(COUNTRIES.map((c) => ({ value: c.code, label: c.name, prefix: c.flag })), this.country))
    this.countryTarget.addEventListener("searchable-select:change", (event) => {
      this.country = event.detail.value
      const tz = timezoneForCountry(this.country)
      if (tz) f.timezone.value = tz
    })
    this.detailsStep = null
  }

  get countrySelect() {
    return this.application.getControllerForElementAndIdentifier(this.countryTarget, "searchable-select")
  }

  get valid() {
    const f = this.form.elements
    return Boolean(f.name.value) && (f.email.value === "" || EMAIL.test(f.email.value)) && Boolean(f.timezone.value) && Boolean(f.currency.value)
  }

  // ---- the two steps ------------------------------------------------------------

  // next(): step 1 → step 2, once the details hold.
  next(event) {
    event.preventDefault()
    if (!this.valid) return
    this.error = null
    this.showStep(1)
  }

  back() {
    this.showStep(0)
  }

  showStep(step) {
    const card = this.cardTarget
    const steps = card.querySelector("#cs-wizard-steps")
    const template = this.stepsTemplateTargets.find((t) => Number(t.dataset.step) === step)
    steps.replaceChildren(template.content.firstElementChild.cloneNode(true))
    const after = [...card.children].slice([...card.children].indexOf(steps) + 1)
    if (step === 1) {
      this.detailsNodes = after
      after.forEach((node) => node.remove())
      if (!this.activityNodes) this.activityNodes = [...this.activitiesStepTarget.content.cloneNode(true).childNodes]
      card.append(...this.activityNodes)
      card.classList.add("is-wide")
      // The picker starts unsearched each time, as it is recreated.
      const search = card.querySelector(".ap-search input")
      if (search.value) {
        search.value = ""
        search.dispatchEvent(new Event("input", { bubbles: true }))
      }
      this.renderError()
      this.renderCreate()
    } else {
      after.forEach((node) => node.remove())
      card.append(...this.detailsNodes)
      card.classList.remove("is-wide")
    }
  }

  picked(event) {
    this.selected = event.detail.selected
    this.custom = event.detail.custom
    this.renderCreate()
  }

  renderCreate() {
    const create = this.cardTarget.querySelector("[data-create]")
    if (!create) return
    const count = this.selected.length + this.custom.length
    create.disabled = this.saving || count === 0
    if (this.saving) create.replaceChildren(spinner(16, "company-setup"))
    else create.textContent = ` ${interpolate(this.labelsValue.create_with, { count })} `
    this.cardTarget.querySelectorAll("[data-saving]").forEach((button) => (button.disabled = Boolean(this.saving)))
  }

  // The step's error, under its subtitle.
  renderError() {
    const card = this.cardTarget
    card.querySelector(":scope > .alert-danger")?.remove()
    if (!this.error) return
    const alert = document.createElement("div")
    alert.setAttribute("_ngcontent-company-setup", "")
    alert.className = "alert alert-danger"
    alert.setAttribute("role", "alert")
    alert.textContent = this.error
    card.querySelector(":scope > p.text-muted-token").after(alert)
  }

  // ---- opening the salle ---------------------------------------------------------

  skip() {
    this.submit(true)
  }

  create() {
    this.submit(false)
  }

  async submit(skip) {
    if (!this.valid) return this.showStep(0)
    this.saving = true
    this.error = null
    this.renderCreate()
    this.startPreparing()
    const startedAt = Date.now()

    const f = this.form.elements
    const company = {
      name: f.name.value, description: "", phone: f.phone.value, email: f.email.value, country: this.country,
      city: f.city.value, address: f.address.value, timezone: f.timezone.value, currency: f.currency.value,
    }
    const activities = skip ? {} : { activity_template_ids: this.selected, custom_activities: this.custom }
    const response = await fetch(this.urlValue, {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ company, ...activities }),
    }).catch(() => null)
    const payload = await response?.json().catch(() => ({}))

    if (!response?.ok) {
      this.stopPreparing()
      this.saving = false
      // extractErrorMessage: the answer's `error`, as it is (K-08).
      this.error = payload?.error ?? this.labelsValue.error
      this.renderCreate()
      return this.renderError()
    }
    setTimeout(() => Turbo.visit(payload.next), Math.max(0, PREP_MS - (Date.now() - startedAt)))
  }

  // The page gives way to the "getting ready" scene, its line moving on.
  startPreparing() {
    this.page = this.element
    const prep = document.getElementById("cs-prep").content.firstElementChild.cloneNode(true)
    const line = prep.querySelector("[data-prep-step]")
    let step = 0
    line.textContent = this.labelsValue.prep_steps[0]
    this.prepTimer = setInterval(() => {
      step = Math.min(step + 1, this.labelsValue.prep_steps.length - 1)
      line.textContent = this.labelsValue.prep_steps[step]
    }, PREP_MS / this.labelsValue.prep_steps.length)
    this.prep = prep
    this.page.replaceWith(prep)
  }

  stopPreparing() {
    clearInterval(this.prepTimer)
    this.prep?.replaceWith(this.page)
    this.prep = null
  }
}
