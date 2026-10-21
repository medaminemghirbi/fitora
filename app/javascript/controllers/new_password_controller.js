import { Controller } from "@hotwired/stimulus"
import { scoped } from "../lib/ng"

// ResetPasswordComponent's live feedback: the strength bar under the new
// password (only once something is typed), and the two rules ticking over.
// The strength is the component's passwordStrength(): a nudge, not a rule.
export default class extends Controller {
  static targets = ["password", "confirmation", "longEnough", "matches"]
  static values = { labels: Object }

  connect() {
    this.update()
  }

  update() {
    const password = this.passwordTarget.value
    const level = this.constructor.strength(password)
    this.renderStrength(level)
    this.tick(this.longEnoughTarget, password.length >= 8)
    this.tick(this.matchesTarget, Boolean(password) && password === this.confirmationTarget.value)
  }

  static strength(password) {
    if (!password) return 0
    if (password.length < 8) return 1
    let variety = 0
    if (/[a-z]/.test(password) && /[A-Z]/.test(password)) variety++
    if (/\d/.test(password)) variety++
    if (/[^A-Za-z0-9]/.test(password)) variety++
    if (password.length >= 12) variety++
    return variety >= 3 ? 4 : variety === 2 ? 3 : 2
  }

  // @if (strength() > 0) { <div class="auth-strength">…</div> <span …>label</span> }
  renderStrength(level) {
    const box = this.passwordTarget.closest(".auth-password")
    let bar = box.parentElement.querySelector(".auth-strength")
    let label = box.parentElement.querySelector(".auth-strength-label")
    if (level === 0) {
      bar?.remove()
      label?.remove()
      return
    }
    if (!bar) {
      bar = scoped(document.createElement("div"), "reset-password")
      bar.className = "auth-strength"
      bar.setAttribute("aria-hidden", "true")
      for (let i = 0; i < 4; i++) bar.append(scoped(document.createElement("span"), "reset-password"))
      label = scoped(document.createElement("span"), "reset-password")
      label.id = "password-strength"
      label.className = "auth-strength-label"
      label.setAttribute("aria-live", "polite")
      box.after(bar, label)
    }
    bar.dataset.level = String(level)
    label.dataset.level = String(level)
    label.textContent = ` ${this.labelsValue[level]} `
  }

  tick(item, met) {
    item.classList.toggle("is-met", met)
    const icon = item.querySelector("i")
    icon.classList.toggle("bi-check-circle-fill", met)
    icon.classList.toggle("bi-circle", !met)
  }
}
