import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// SettingsShellComponent: the "Outils Pro" menu — open on its button, shut
// by a click elsewhere or Escape — and the phone's section picker.
export default class extends Controller {
  static targets = ["pro", "menu"]

  connect() {
    this.onDocument = (event) => this.menu && !this.proTarget.contains(event.target) && this.close()
    this.onKey = (event) => event.key === "Escape" && this.close()
    document.addEventListener("click", this.onDocument)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocument)
    document.removeEventListener("keydown", this.onKey)
  }

  toggleProMenu(event) {
    event.stopPropagation()
    if (this.menu) return this.close()
    this.menu = this.menuTarget.content.firstElementChild.cloneNode(true)
    this.menu.querySelectorAll("a").forEach((link) => link.addEventListener("click", () => this.close()))
    this.proTarget.append(this.menu)
    event.currentTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    if (!this.menu) return
    this.menu.remove()
    this.menu = null
    this.proTarget.querySelector(".settings-pro-btn").setAttribute("aria-expanded", "false")
  }

  pick(event) {
    if (event.target.value) Turbo.visit(event.target.value)
  }
}
