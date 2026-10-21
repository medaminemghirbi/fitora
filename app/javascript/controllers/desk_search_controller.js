import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// DeskShellComponent's search, the top of every desk screen: focused on load
// (not on a touch screen, where the keyboard would cover the page); from two
// characters, 250 ms after the typing stops, the first six members whose
// name matches, in a panel under the field — the newest request winning, as
// switchMap has it. The clear button while anything is typed; Escape and a
// result clear it all. A failed lookup empties the results rather than
// leaving the last person's under someone else's name.
//
// Unlike the Angular pipe (MIGRATION_AUDIT §10, B-11): going below two
// characters cancels a search still waiting to go, and the same name typed
// again after a clear is searched again.
// The Angular shell lives on across the desk's own pages, so its search is
// focused once, when the shell is entered (ngAfterViewInit) — not again on
// each desk page the person then opens.
let fromDeskPage = false
document.addEventListener("turbo:before-render", () => {
  fromDeskPage = Boolean(document.querySelector("app-desk-shell"))
})

export default class extends Controller {
  static targets = ["input", "clear", "panel", "loading", "empty"]
  static values = { url: String, noMatch: String }

  static DEBOUNCE = 250

  connect() {
    this.query = ""
    this.lastSent = null
    this.clearButton = null
    this.panel = null
    this.onKeydown = (event) => event.key === "Escape" && this.clear()
    document.addEventListener("keydown", this.onKeydown)
    if (!fromDeskPage && !matchMedia("(hover: none)").matches) this.inputTarget.focus()
    fromDeskPage = false
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    clearTimeout(this.timer)
    this.request?.abort()
  }

  search() {
    this.query = this.inputTarget.value
    this.renderClear()
    const term = this.query.trim()
    clearTimeout(this.timer)
    if (term.length < 2) {
      this.lastSent = null
      this.request?.abort()
      this.setPanel(null)
      return
    }
    this.timer = setTimeout(() => this.send(term), this.constructor.DEBOUNCE)
  }

  async send(term) {
    if (term === this.lastSent) return
    this.lastSent = term
    this.request?.abort()
    const request = (this.request = new AbortController())
    if (this.panel) this.panel.replaceChildren(this.loadingTarget.content.cloneNode(true))
    const query = new URLSearchParams({ search: term, term: this.query })
    const response = await fetch(`${this.urlValue}?${query}`, { credentials: "same-origin", signal: request.signal }).catch(() => null)
    if (request.signal.aborted) return
    if (!response?.ok) {
      // No results, and no longer searching: an open panel says so.
      if (this.panel) this.panel.replaceChildren(this.noMatch())
      return
    }
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    if (request.signal.aborted) return
    this.setPanel(fresh.content)
  }

  clear() {
    clearTimeout(this.timer)
    this.request?.abort()
    this.query = ""
    this.lastSent = null
    this.inputTarget.value = ""
    this.renderClear()
    this.setPanel(null)
  }

  open(event) {
    const href = event.currentTarget.dataset.href
    this.clear()
    Turbo.visit(href)
  }

  // ---------------------------------------------------------------------

  noMatch() {
    const line = this.emptyTarget.content.cloneNode(true)
    line.firstElementChild.textContent = this.noMatchValue.replace("%TERM%", this.query)
    return line
  }

  renderClear() {
    if (this.query && !this.clearButton) {
      this.clearButton = this.clearTarget.content.firstElementChild.cloneNode(true)
      this.inputTarget.after(this.clearButton)
    } else if (!this.query && this.clearButton) {
      this.clearButton.remove()
      this.clearButton = null
    }
  }

  // @if (resultsOpen()): the panel with this content, or no panel.
  setPanel(content) {
    if (!content) {
      this.panel?.remove()
      this.panel = null
      return
    }
    if (!this.panel) {
      this.panel = this.panelTarget.content.firstElementChild.cloneNode(true)
      this.element.append(this.panel)
    }
    this.panel.replaceChildren(content)
  }
}
