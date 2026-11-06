import { Controller } from "@hotwired/stimulus"
import { currentTheme, setTheme } from "../lib/theme"

// LandingComponent's signals: the mobile menu, the theme, step 2's booking
// mock (a day, then a free slot on it) and the questions (one open at a time).
export default class extends Controller {
  static targets = ["burger", "menu", "day", "slot", "faq"]
  static values = { taken: Array }

  connect() {
    this.selectedDay = 0
    this.selectedSlot = "18:00"
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

  // [class.x]="on" with [attr.aria-pressed]="on", on a button with no other class.
  mark(button, name, on) {
    button.classList.toggle(name, on)
    button.setAttribute("aria-pressed", String(on))
    if (button.classList.length === 0) button.removeAttribute("class")
  }
}
