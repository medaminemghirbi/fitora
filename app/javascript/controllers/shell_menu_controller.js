import { Controller } from "@hotwired/stimulus"
import { currentTheme, setTheme } from "../lib/theme"
import { csrfToken } from "../lib/ng"

// The top bars of the desk, coach, member and superadmin shells: their
// menus (the user menu, a salle or gym switcher, the language), each put in
// the DOM when it opens and taken out when it closes — as their components'
// @if (menuOpen()) does — from the <template> beside its trigger. Opening a
// menu leaves the others as they are, as each component keeps one signal
// per menu, and a click elsewhere closes nothing, as in those components.
// What Escape closes is each shell's own (`escape`): the desk's menus
// (DeskShellComponent#onEsc), the coach's sidebar (CoachShellComponent
// #onEsc), nothing in the member's and superadmin's shells. The theme
// toggle (ThemeService), and the switches that reload the shell.
export default class extends Controller {
  static targets = ["menu", "sidebar", "backdrop"]
  static values = { escape: String }

  connect() {
    this.open = {} // menu name → inserted element
    this.onKeydown = (event) => {
      if (event.key !== "Escape") return
      if (this.escapeValue === "menus") this.closeAll()
      if (this.escapeValue === "sidebar") this.setSidebar(false)
    }
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  toggle(event) {
    const name = event.params.menu
    if (this.open[name]) return this.close(name)

    const template = this.menuTargets.find((t) => t.dataset.menu === name)
    if (!template) return
    const element = template.content.firstElementChild.cloneNode(true)
    template.after(element)
    this.open[name] = element
  }

  close(name) {
    this.open[name]?.remove()
    delete this.open[name]
  }

  closeAll() {
    Object.keys(this.open).forEach((name) => this.close(name))
  }

  // A link inside a menu closes it as it is followed (the member's
  // "Profil": (click)="userMenuOpen.set(false)").
  closeMenu(event) {
    this.close(event.params.menu)
  }

  toggleTheme() {
    setTheme(currentTheme() === "dark" ? "light" : "dark")
    this.element.querySelectorAll('[data-action~="shell-menu#toggleTheme"] i').forEach((icon) => {
      icon.classList.toggle("bi-moon-stars", currentTheme() === "light")
      icon.classList.toggle("bi-sun", currentTheme() === "dark")
    })
  }

  // DeskShellComponent#switchSalle: the current salle only closes the menu;
  // another is recorded, then the shell reloads on its home. A refusal
  // (the switch is Pro's) closes the menu and changes nothing.
  async switchSalle(event) {
    const url = event.params.url
    if (!url || this.switching) return this.closeAll()

    this.switching = true
    this.element.querySelectorAll('[data-action~="shell-menu#switchSalle"]').forEach((b) => (b.disabled = true))
    const response = await this.post(url)
    if (response?.ok) {
      const { next } = await response.json()
      return window.location.assign(next)
    }
    this.switching = false
    this.closeAll()
  }

  // A form in a menu posted as a full page load: the member's gym, the
  // superadmin's language.
  submit(event) {
    const form = document.createElement("form")
    form.method = "post"
    form.action = event.params.url
    form.hidden = true
    form.dataset.turbo = "false"
    const fields = { authenticity_token: csrfToken(), ...(event.params.fields || {}) }
    for (const [name, value] of Object.entries(fields)) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      form.append(input)
    }
    document.body.append(form)
    form.submit()
  }

  // The coach shell's sidebar below 992 px, behind the burger, with its
  // backdrop put in while it is open.
  toggleSidebar() {
    this.setSidebar(!this.sidebarOpen)
  }

  closeSidebar() {
    this.setSidebar(false)
  }

  setSidebar(on) {
    if (!this.hasSidebarTarget) return
    this.sidebarOpen = on
    this.sidebarTarget.classList.toggle("is-open", on)
    if (on && !this.backdrop) {
      this.backdrop = this.backdropTarget.content.firstElementChild.cloneNode(true)
      this.backdropTarget.after(this.backdrop)
    } else if (!on && this.backdrop) {
      this.backdrop.remove()
      this.backdrop = null
    }
  }

  post(url) {
    return fetch(url, { method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() }, credentials: "same-origin" }).catch(() => null)
  }
}
