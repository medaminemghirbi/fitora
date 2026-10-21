import { Controller } from "@hotwired/stimulus"

// ModalComponent (and DrawerComponent, which works the same way): nothing in
// the DOM while closed; opened, its markup comes from the <template> inside
// the host — one root (the modal's backdrop) or several (the drawer's
// backdrop and its panel, side by side). Backdrop click and Escape close it.
// The focus trap is CDK's cdkTrapFocus + cdkTrapFocusAutoCapture, done the
// way CDK does it: two tabbable anchors around the panel send focus back
// round, the first tabbable element takes focus on open, and focus goes back
// where it was on close.
export default class extends Controller {
  static targets = ["template", "panel"]
  static values = { name: String }

  connect() {
    this.onKeydown = (event) => {
      if (event.key === "Escape" && this.isOpen) this.close()
    }
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  get isOpen() {
    return Boolean(this.openNodes)
  }

  open(event) {
    if (this.isOpen) return

    this.restoreFocusTo = document.activeElement
    const fragment = this.templateTarget.content.cloneNode(true)
    this.openNodes = [...fragment.children]
    this.element.append(fragment)
    const panel = this.openNodes.map((node) => (node.matches("[data-modal-target~=panel]") ? node : node.querySelector("[data-modal-target~=panel]"))).find(Boolean)
    // Beside the panel: inside the modal's backdrop, or beside the drawer's
    // panel in the host — so they are taken out with the rest on close.
    const anchors = [this.anchor(() => this.focusLast(panel)), this.anchor(() => this.focusFirst(panel))]
    panel.before(anchors[0])
    panel.after(anchors[1])
    this.openNodes.push(...anchors)
    // The page fills it in (a new record's blank form, or the one edited).
    // On window: the modal is the page's sibling, as Angular's DOM has it,
    // so the page's controller is not an ancestor to bubble to.
    this.dispatch("opened", { target: window, detail: { panel, name: this.nameValue } })
    // CDK focuses once the zone is stable — within this task, before the
    // next frame (or anything typed). A microtask runs after Stimulus has
    // connected the controllers inside (its MutationObserver records come
    // first), as late as CDK and no later.
    queueMicrotask(() => this.focusFirst(panel))
  }

  // A page busy saving (data-modal-busy on the host) keeps it open, as the
  // components' (closed) handlers ignore a close while saving.
  close() {
    if (!this.isOpen || this.element.hasAttribute("data-modal-busy")) return

    this.openNodes.forEach((node) => node.remove())
    this.openNodes = null
    this.restoreFocusTo?.focus?.()
    this.dispatch("closed")
  }

  // The backdrop's own clicks close; the panel's do not (stopPropagation).
  backdropClick(event) {
    if (event.target === event.currentTarget) this.close()
  }

  // ---------------------------------------------------------------------

  anchor(onFocus) {
    const div = document.createElement("div")
    div.tabIndex = 0
    div.className = "cdk-visually-hidden cdk-focus-trap-anchor"
    div.setAttribute("aria-hidden", "true")
    div.addEventListener("focus", onFocus)
    return div
  }

  tabbables(panel) {
    const selector = 'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
    return [...panel.querySelectorAll(selector)].filter((el) => el.offsetParent !== null || el === document.activeElement)
  }

  focusFirst(panel) {
    this.tabbables(panel)[0]?.focus()
  }

  focusLast(panel) {
    const all = this.tabbables(panel)
    all[all.length - 1]?.focus()
  }
}
