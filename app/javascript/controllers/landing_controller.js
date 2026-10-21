import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { NG_EMAIL } from "../lib/ng"
import { currentTheme, setTheme } from "../lib/theme"

// LandingComponent's signals: the mobile menu, the theme, step 2's booking
// mock (a day, then a free slot on it), the billing period the prices are
// shown for, the questions (one open at a time) and the closing form, which
// hands what it has over to /inscription.
export default class extends Controller {
  static targets = ["burger", "menu", "day", "slot", "billing", "price", "period", "faq", "firstName", "email", "emailField"]
  static values = { taken: Array, billingLabels: Object }

  connect() {
    this.selectedDay = 0
    this.selectedSlot = "18:00"
    this.emailTouched = false
  }

  toggleTheme(event) {
    const next = currentTheme() === "dark" ? "light" : "dark"
    setTheme(next)
    const icon = event.currentTarget.querySelector("i")
    icon.classList.toggle("bi-moon-stars", next === "light")
    icon.classList.toggle("bi-sun", next === "dark")
  }

  toggleMenu() {
    this.setMenu(!this.menuTarget.classList.contains("is-open"))
  }

  closeMenu() {
    this.setMenu(false)
  }

  setMenu(open) {
    this.menuTarget.classList.toggle("is-open", open)
    this.burgerTarget.setAttribute("aria-expanded", String(open))
    const icon = this.burgerTarget.querySelector("i")
    icon.classList.toggle("bi-list", !open)
    icon.classList.toggle("bi-x-lg", open)
  }

  // ---- Step 2's booking mock ----
  pickDay(event) {
    this.selectedDay = event.params.day
    this.dayTargets.forEach((button, i) => this.mark(button, "is-on", i === this.selectedDay))
    this.drawSlots()
  }

  pickSlot(event) {
    if (this.isTaken(event.params.time)) return
    this.selectedSlot = event.params.time
    this.drawSlots()
  }

  isTaken(time) {
    return this.takenValue[this.selectedDay].includes(time)
  }

  drawSlots() {
    this.slotTargets.forEach((button) => {
      const time = button.dataset.landingTimeParam
      const taken = this.isTaken(time)
      const on = !taken && this.selectedSlot === time
      button.classList.toggle("is-on", on)
      button.classList.toggle("is-taken", taken)
      button.disabled = taken
      button.setAttribute("aria-pressed", String(on))
    })
  }

  // ---- Pricing: per month, or the year's total after the discount ----
  pickBilling(event) {
    const billing = event.params.billing
    this.billingTargets.forEach((button) => this.mark(button, "is-on", button.dataset.landingBillingParam === billing))
    this.priceTargets.forEach((price) => (price.textContent = price.dataset[billing]))
    this.periodTargets.forEach((period) => (period.textContent = `DT / ${this.billingLabelsValue[billing]}`))
  }

  // ---- Questions: one open panel at a time ----
  toggleFaq(event) {
    const item = event.currentTarget.closest(".lp-faq-item")
    const open = !item.classList.contains("is-open")
    this.faqTargets.forEach((faq) => {
      const on = open && faq === item
      faq.classList.toggle("is-open", on)
      faq.querySelector("button").setAttribute("aria-expanded", String(on))
      const icon = faq.querySelector(".lp-faq-ic i")
      icon.classList.toggle("bi-plus-lg", !on)
      icon.classList.toggle("bi-dash-lg", on)
      faq.querySelector(".lp-faq-a").hidden = !on
    })
  }

  // ---- The closing form: Validators.email on the address, shown once touched ----
  touchEmail() {
    this.emailTouched = true
    this.drawEmailError()
  }

  checkEmail() {
    this.drawEmailError()
  }

  emailValid() {
    const value = this.emailTarget.value
    return value === "" || NG_EMAIL.test(value)
  }

  drawEmailError() {
    const show = this.emailTouched && !this.emailValid()
    const shown = this.emailFieldTarget.querySelector(".lp-field-err")
    if (show && !shown) {
      this.emailFieldTarget.append(document.getElementById("lp-email-error").content.cloneNode(true))
    } else if (!show && shown) {
      shown.remove()
    }
  }

  start(event) {
    event.preventDefault()
    if (!this.emailValid()) {
      this.emailTouched = true
      this.drawEmailError()
      return
    }
    const query = new URLSearchParams()
    const firstName = this.firstNameTarget.value.trim()
    const email = this.emailTarget.value.trim()
    if (firstName) query.set("first_name", firstName)
    if (email) query.set("email", email)
    const search = query.toString()
    Turbo.visit(search ? `/inscription?${search}` : "/inscription")
  }

  // [class.x]="on" with [attr.aria-pressed]="on", on a button with no other class.
  mark(button, name, on) {
    button.classList.toggle(name, on)
    button.setAttribute("aria-pressed", String(on))
    if (button.classList.length === 0) button.removeAttribute("class")
  }
}
