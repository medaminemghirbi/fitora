import { Controller } from "@hotwired/stimulus"
import { spinner } from "../lib/ng"

// What a reactive form on the Angular account screens does before anything
// is sent, configured from the markup so every screen keeps its own rules:
//
//   data-checks="required email minlength:8 matches:#password"   on an input
//   data-check-message="…"         the message shown under it once it is
//                                  "touched" (left, or on a refused submit)
//                                  and invalid; no message, no element — as
//                                  in Angular, where most fields show none
//   data-check-anchor=".auth-password"  where the message goes (after the
//                                  closest such element; default: the input)
//
// A submit while anything is invalid marks every field touched and goes no
// further (markAllAsTouched). The eye shows or hides every password of the
// form at once (one showPassword signal). While the request runs the submit
// button shows the spinner: replacing its label (busy: "replace:16") or
// before it (busy: "prepend:18"). The server checks everything again.
// A form whose answer is a page rather than a redirect (the "sent" and
// "done" states) carries data-turbo="false": Turbo only follows redirects.
export default class extends Controller {
  static targets = ["submit", "eye"]
  static values = { scope: String, busy: { type: String, default: "replace:16" } }

  // Angular's Validators.email pattern.
  static EMAIL = /^(?=.{1,254}$)(?=.{1,64}@)[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+)*@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  connect() {
    // A form the server sent back refused has its messages already shown.
    this.touched = new Set([...this.element.querySelectorAll("[data-check-error]")].map((el) => el.dataset.checkError))
    for (const input of this.inputs) {
      input.addEventListener("blur", () => this.touch(input))
      input.addEventListener("input", () => this.render())
    }
  }

  get inputs() {
    return [...this.element.querySelectorAll("[data-checks]")]
  }

  touch(input) {
    this.touched.add(input.id)
    this.render()
  }

  submit(event) {
    if (this.inputs.every((input) => this.valid(input))) {
      // A form Turbo leaves alone (its answer is a page, not a redirect)
      // still shows the spinner while it goes.
      if (this.element.dataset.turbo === "false") this.busy()
      return
    }

    event.preventDefault()
    event.stopImmediatePropagation()
    for (const input of this.inputs) this.touched.add(input.id)
    this.render()
  }

  togglePassword() {
    const passwords = [...this.element.querySelectorAll("[data-password]")]
    const show = passwords[0]?.type === "password"
    for (const input of passwords) input.type = show ? "text" : "password"
    for (const eye of this.eyeTargets) {
      const icon = eye.querySelector("i")
      icon.classList.toggle("bi-eye", !show)
      icon.classList.toggle("bi-eye-slash", show)
      eye.setAttribute("aria-pressed", String(show))
      eye.setAttribute("aria-label", show ? eye.dataset.hideLabel : eye.dataset.showLabel)
    }
  }

  busy() {
    if (!this.hasSubmitTarget) return
    const [mode, size] = this.busyValue.split(":")
    this.label = this.submitTarget.innerHTML
    this.submitTarget.disabled = true
    if (mode === "prepend") this.submitTarget.prepend(spinner(Number(size), this.scopeValue))
    else this.submitTarget.replaceChildren(spinner(Number(size), this.scopeValue))
  }

  idle() {
    if (this.label === undefined) return
    this.submitTarget.disabled = false
    this.submitTarget.innerHTML = this.label
  }

  // ---------------------------------------------------------------------

  valid(input) {
    const value = input.value
    for (const check of input.dataset.checks.split(/\s+/)) {
      const [name, arg] = check.split(":")
      if (name === "required" && value === "") return false
      if (name === "email" && value !== "" && !this.constructor.EMAIL.test(value)) return false
      if (name === "minlength" && value !== "" && value.length < Number(arg)) return false
      if (name === "matches") {
        const other = this.element.querySelector(arg)?.value
        if (value && other && value !== other) return false
      }
    }
    return true
  }

  render() {
    for (const input of this.inputs) {
      const message = input.dataset.checkMessage
      if (!message) continue
      const show = this.touched.has(input.id) && !this.valid(input)
      const existing = this.element.querySelector(`[data-check-error="${input.id}"]`)
      if (show && !existing) this.anchor(input).after(this.errorElement(input.id, message))
      if (!show && existing) existing.remove()
    }
  }

  anchor(input) {
    const selector = input.dataset.checkAnchor
    return (selector && input.closest(selector)) || input
  }

  errorElement(id, message) {
    const div = document.createElement("div")
    if (this.scopeValue) div.setAttribute(`_ngcontent-${this.scopeValue}`, "")
    div.className = "invalid-feedback d-block"
    div.dataset.checkError = id
    div.textContent = message
    return div
  }
}
