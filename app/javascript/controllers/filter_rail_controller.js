import { Controller } from "@hotwired/stimulus"

// FilterRailComponent's toggle (below lg): opens and closes the rail beside it.
export default class extends Controller {
  toggle() {
    const rail = this.element.nextElementSibling
    const open = !rail.classList.contains("is-open")
    rail.classList.toggle("is-open", open)
    this.element.setAttribute("aria-expanded", String(open))
    const chevron = this.element.querySelector(".bi-chevron-down, .bi-chevron-up")
    chevron.classList.toggle("bi-chevron-down", !open)
    chevron.classList.toggle("bi-chevron-up", open)
  }
}
