import { Controller } from "@hotwired/stimulus"
import { scoped } from "../lib/ng"

// SetupProgressComponent: the current step moves to 2 at 35 % of the
// duration and to 3 at 85 %; every step before the current one is done.
export default class extends Controller {
  static targets = ["step"]
  static values = { duration: Number }

  connect() {
    this.timers = [
      setTimeout(() => this.show(2), this.durationValue * 0.35),
      setTimeout(() => this.show(3), this.durationValue * 0.85),
    ]
  }

  disconnect() {
    this.timers.forEach(clearTimeout)
  }

  show(current) {
    this.stepTargets.forEach((li, i) => {
      const state = i < current ? "done" : i === current ? "active" : "todo"
      if (li.dataset.state === state) return
      li.dataset.state = state
      const icon = li.querySelector(".sp-icon")
      icon.replaceChildren()
      if (state === "done") {
        const check = scoped(document.createElement("i"), "setup-progress")
        check.className = "bi bi-check-lg"
        icon.append(check)
      } else if (state === "active") {
        const spin = scoped(document.createElement("span"), "setup-progress")
        spin.className = "sp-spin"
        icon.append(spin)
      }
    })
  }
}
