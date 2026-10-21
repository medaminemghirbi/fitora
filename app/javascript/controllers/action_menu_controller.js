import { Controller } from "@hotwired/stimulus"

// ActionMenuComponent: the row's "⋯" menu, in the DOM only while open, placed
// against its trigger (below it, or above when there is no room; right- or
// left-aligned, kept inside the viewport). Closes on an item, a click
// elsewhere, Escape, a scroll or a resize.
export default class extends Controller {
  static targets = ["trigger", "menu"]
  static values = { align: String }

  connect() {
    this.onDocument = (event) => this.menu && !this.element.contains(event.target) && this.close()
    this.onKey = (event) => event.key === "Escape" && this.close()
    this.onViewport = () => this.close()
    document.addEventListener("click", this.onDocument)
    document.addEventListener("keydown", this.onKey)
    window.addEventListener("scroll", this.onViewport)
    window.addEventListener("resize", this.onViewport)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocument)
    document.removeEventListener("keydown", this.onKey)
    window.removeEventListener("scroll", this.onViewport)
    window.removeEventListener("resize", this.onViewport)
  }

  toggle(event) {
    event.stopPropagation()
    if (this.menu) return this.close()
    this.menu = this.menuTarget.content.firstElementChild.cloneNode(true)
    this.element.append(this.menu)
    this.triggerTarget.classList.add("is-open")
    this.triggerTarget.setAttribute("aria-expanded", "true")
    setTimeout(() => this.position())
  }

  close() {
    if (!this.menu) return
    this.menu.remove()
    this.menu = null
    this.triggerTarget.classList.remove("is-open")
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  position() {
    if (!this.menu) return
    const t = this.triggerTarget.getBoundingClientRect()
    const m = this.menu.getBoundingClientRect()
    const gap = 4
    const margin = 8
    const below = window.innerHeight - t.bottom
    const top = below < m.height + margin && t.top > m.height + margin ? t.top - m.height - gap : t.bottom + gap
    let left = this.alignValue === "start" ? t.left : t.right - m.width
    left = Math.max(margin, Math.min(left, window.innerWidth - m.width - margin))
    this.menu.style.top = `${Math.round(top)}px`
    this.menu.style.left = `${Math.round(left)}px`
  }
}
