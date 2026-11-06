import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The bar at the foot of a settings form: how many things differ from what is
// saved, and the way to save them or drop them. It reads the form's named
// fields and its toggle buttons; what a form holds elsewhere (a drawn
// signature) it reports with a settings:touched event { key, dirty }. The form's
// own controller saves, then says so with settings:saved.
export default class extends Controller {
  static targets = ["bar", "state", "save", "cancel"]
  static CHANGES = ["input", "change", "click", "searchable-select:change"]

  connect() {
    this.touched = new Set()
    this.onChange = () => this.draw()
    this.onTouched = ({ detail }) => {
      if (detail.dirty) this.touched.add(detail.key)
      else this.touched.delete(detail.key)
      this.draw()
    }
    this.onSaved = () => this.settle()
    for (const type of this.constructor.CHANGES) this.element.addEventListener(type, this.onChange)
    this.element.addEventListener("settings:touched", this.onTouched)
    this.element.addEventListener("settings:saved", this.onSaved)
    // Once the other controllers on the form have filled in their fields.
    queueMicrotask(() => this.settle())
  }

  disconnect() {
    for (const type of this.constructor.CHANGES) this.element.removeEventListener(type, this.onChange)
    this.element.removeEventListener("settings:touched", this.onTouched)
    this.element.removeEventListener("settings:saved", this.onSaved)
  }

  settle() {
    this.baseline = this.read()
    this.touched.clear()
    this.draw()
  }

  read() {
    const fields = new Map()
    for (const field of this.element.elements) {
      if (!field.name) continue
      fields.set(field.name, field.type === "file" ? field.files.length : field.value)
    }
    this.element.querySelectorAll("[aria-pressed]").forEach((button, index) => fields.set(`pressed-${index}`, button.getAttribute("aria-pressed")))
    return fields
  }

  draw() {
    if (!this.baseline) return
    const current = this.read()
    let count = this.touched.size
    for (const [key, value] of current) if (this.baseline.get(key) !== value) count += 1

    const { none, one, many } = this.stateTarget.dataset
    this.stateTarget.textContent = count === 0 ? none : count === 1 ? one : many.replace("{{count}}", count)
    this.barTarget.classList.toggle("is-dirty", count > 0)
    this.cancelTarget.hidden = count === 0
    this.saveTarget.disabled = count === 0
  }

  // The page again: a picked file, a drawn signature and a chosen country have
  // no simpler way back to what is saved.
  discard() {
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
