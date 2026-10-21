import { Controller } from "@hotwired/stimulus"
import { currentTheme, setTheme } from "../lib/theme"
import { csrfToken } from "../lib/ng"

// NavbarComponent's behaviour in the admin shell:
//
// - one menu open at a time (the salle switcher, the user menu); a menu is
//   put in the DOM when it opens and taken out when it closes, as Angular's
//   @if does, from the <template> rendered beside its trigger;
// - a click outside the bar, or Escape, closes everything;
// - the mobile panel under the bar, behind the burger;
// - hidden while scrolling down past 80 px, back on the first scroll up,
//   never while a menu is open;
// - the theme toggle (ThemeService), kept in a cookie so the server renders
//   the next page in it;
// - switching salle: a full page load onto the new salle's home, as
//   NavbarComponent#reloadToHome does.
export default class extends Controller {
  static targets = ["menu", "mobile", "burger"]
  static REVEAL_ABOVE = 80

  connect() {
    this.open = {} // menu name → inserted element
    this.mobilePanel = null
    this.lastScrollY = 0
    this.scrollQueued = false
    this.onDocumentClick = (event) => {
      if (!event.target.closest(".app-navbar-menu")) this.closeAll()
    }
    this.onKeydown = (event) => {
      if (event.key === "Escape") {
        this.closeAll()
        this.setMobile(false)
      }
    }
    this.onScroll = () => this.queueScroll()
    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
    window.addEventListener("scroll", this.onScroll, { passive: true })
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("scroll", this.onScroll)
  }

  toggle(event) {
    const name = event.params.menu
    const wasOpen = Boolean(this.open[name])
    this.closeAll()
    if (!wasOpen) this.openMenu(name, event.currentTarget)
  }

  toggleMobile() {
    this.setMobile(!this.mobilePanel)
  }

  toggleTheme() {
    setTheme(currentTheme() === "dark" ? "light" : "dark")
  }

  // A salle button: the current one only closes the menu.
  switch(event) {
    const url = event.params.url
    if (!url) {
      this.closeAll()
      return
    }

    const form = document.createElement("form")
    form.method = "post"
    form.action = url
    form.hidden = true
    form.dataset.turbo = "false"
    const token = document.createElement("input")
    token.type = "hidden"
    token.name = "authenticity_token"
    token.value = csrfToken()
    form.append(token)
    document.body.append(form)
    form.submit()
  }

  // ---------------------------------------------------------------------

  openMenu(name, trigger) {
    const template = this.menuTargets.find((t) => t.dataset.menu === name)
    if (!template) return

    const element = template.content.firstElementChild.cloneNode(true)
    template.after(element)
    this.open[name] = element
    trigger.setAttribute("aria-expanded", "true")
    this.trigger(name)?.setAttribute("aria-expanded", "true")
  }

  closeAll() {
    for (const [name, element] of Object.entries(this.open)) {
      element.remove()
      this.trigger(name)?.setAttribute("aria-expanded", "false")
    }
    this.open = {}
  }

  trigger(name) {
    return this.element.querySelector(`[data-navbar-menu-param="${name}"]`)
  }

  setMobile(on) {
    if (on && !this.mobilePanel) {
      this.mobilePanel = this.mobileTarget.content.firstElementChild.cloneNode(true)
      this.mobileTarget.after(this.mobilePanel)
    } else if (!on && this.mobilePanel) {
      this.mobilePanel.remove()
      this.mobilePanel = null
    }
    if (this.hasBurgerTarget) {
      this.burgerTarget.setAttribute("aria-expanded", String(on))
      const icon = this.burgerTarget.querySelector("i")
      icon.classList.toggle("bi-list", !on)
      icon.classList.toggle("bi-x-lg", on)
    }
  }

  anyOpen() {
    return Object.keys(this.open).length > 0 || Boolean(this.mobilePanel)
  }

  // Scroll arrives far faster than a frame: one decision per frame.
  queueScroll() {
    if (this.scrollQueued) return
    this.scrollQueued = true
    requestAnimationFrame(() => {
      this.scrollQueued = false
      const y = Math.max(0, window.scrollY)
      const hidden = y <= this.constructor.REVEAL_ABOVE || this.anyOpen() ? false : y > this.lastScrollY
      this.element.classList.toggle("is-hidden", hidden)
      this.lastScrollY = y
    })
  }
}
