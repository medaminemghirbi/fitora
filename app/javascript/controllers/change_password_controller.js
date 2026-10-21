import { Controller } from "@hotwired/stimulus"
import { confirmAsk } from "../lib/confirm"
import { csrfToken, scoped } from "../lib/ng"
import { toast } from "../lib/toast"

// ChangePasswordComponent: the new password (8 or more, typed twice), the
// current one checked by the server — and signing out of every device.
const SCOPE = "change-password"

export default class extends Controller {
  static values = { url: String, everywhereUrl: String, labels: Object }

  connect() {
    this.confirmTouched = false
    const confirm = this.element.elements.password_confirmation
    confirm.addEventListener("blur", () => {
      this.confirmTouched = true
      this.drawMismatch()
    })
    for (const name of ["password", "password_confirmation"]) this.element.elements[name].addEventListener("input", () => this.drawMismatch())
  }

  get mismatch() {
    const f = this.element.elements
    return Boolean(f.password.value && f.password_confirmation.value && f.password.value !== f.password_confirmation.value)
  }

  // form.hasError("mismatch") && password_confirmation.touched
  drawMismatch() {
    const confirm = this.element.elements.password_confirmation
    confirm.parentElement.querySelector(".text-danger")?.remove()
    if (!(this.mismatch && this.confirmTouched)) return
    const small = scoped(document.createElement("small"), SCOPE)
    small.className = "text-danger"
    small.textContent = this.labelsValue.mismatch
    confirm.after(small)
  }

  async submit(event) {
    event.preventDefault()
    const f = this.element.elements
    if (!f.current_password.value || f.password.value.length < 8 || !f.password_confirmation.value || this.mismatch) {
      this.confirmTouched = true
      return this.drawMismatch()
    }
    const save = this.element.querySelector("[data-save]")
    save.disabled = true
    save.textContent = ` ${this.labelsValue.saving} `
    this.showError(null)
    const response = await fetch(this.urlValue, {
      method: "PATCH", credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ current_password: f.current_password.value, password: f.password.value }),
    }).catch(() => null)
    save.disabled = false
    save.textContent = ` ${this.labelsValue.submit} `
    if (response?.ok) {
      this.element.reset()
      this.confirmTouched = false
      this.drawMismatch()
      return toast("success", this.labelsValue.changed)
    }
    const payload = await response?.json().catch(() => ({}))
    this.showError(payload?.error === "current_password_invalid" ? this.labelsValue.wrong : (payload?.error ?? this.labelsValue.error))
  }

  showError(message) {
    this.element.querySelector(":scope > .alert-danger")?.remove()
    if (!message) return
    const alert = scoped(document.createElement("div"), SCOPE)
    alert.className = "alert alert-danger"
    alert.setAttribute("role", "alert")
    alert.textContent = message
    this.element.prepend(alert)
  }

  async signOutEverywhere(event) {
    const button = event.currentTarget
    const ok = await confirmAsk({ title: this.labelsValue.everywhere_title, body: this.labelsValue.everywhere_body, confirmLabel: this.labelsValue.everywhere })
    if (!ok) return
    button.disabled = true
    const response = await fetch(this.everywhereUrlValue, {
      method: "POST", credentials: "same-origin",
      headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
    }).catch(() => null)
    const payload = await response?.json().catch(() => ({}))
    if (response?.ok && payload?.next) return window.location.assign(payload.next)
    button.disabled = false
    toast("error", payload?.error ?? this.labelsValue.error)
  }
}
