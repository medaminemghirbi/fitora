import { Controller } from "@hotwired/stimulus"
import { currentTheme, setTheme } from "../lib/theme"

// SettingsAppearanceComponent's theme buttons: ThemeService#setTheme, the
// chosen one marked — and kept marked when the navbar's toggle switches it.
export default class extends Controller {
  connect() {
    this.onChanged = () => this.mark()
    window.addEventListener("theme:changed", this.onChanged)
  }

  disconnect() {
    window.removeEventListener("theme:changed", this.onChanged)
  }

  choose(event) {
    setTheme(event.currentTarget.dataset.themeValue)
  }

  mark() {
    const theme = currentTheme()
    this.element.querySelectorAll("[data-theme-value]").forEach((button) => {
      if (button.dataset.themeValue === theme) button.classList.add("is-active")
      else button.classList.remove("is-active")
      if (button.classList.length === 0) button.removeAttribute("class")
    })
  }
}
