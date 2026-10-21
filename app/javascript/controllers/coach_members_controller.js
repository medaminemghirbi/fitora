import { Controller } from "@hotwired/stimulus"

// CoachMembersComponent's search: 250 ms after the typing stops, the list of
// the trimmed term — not again for the same term, the newest request
// winning (debounceTime, distinctUntilChanged, switchMap) — with the
// skeleton in its place meanwhile; the error state with its retry when it
// fails. The term stays in the URL (?q=, M-05).
export default class extends Controller {
  static targets = ["skeleton", "error"]
  static values = { url: String }

  static DEBOUNCE = 250

  connect() {
    this.sent = undefined
  }

  disconnect() {
    clearTimeout(this.timer)
    this.request?.abort()
  }

  search(event) {
    this.query = event.target.value
    clearTimeout(this.timer)
    const term = this.query.trim()
    this.timer = setTimeout(() => {
      if (term === this.sent) return
      this.sent = term
      this.load(term)
    }, this.constructor.DEBOUNCE)
  }

  retry() {
    this.load(this.sent ?? "")
  }

  async load(term) {
    this.request?.abort()
    const request = (this.request = new AbortController())
    this.show(this.skeletonTarget.content.cloneNode(true))
    history.replaceState(history.state, "", term ? `${this.urlValue}?${new URLSearchParams({ q: term })}` : this.urlValue)
    const response = await fetch(`${this.urlValue}?${new URLSearchParams({ q: this.query ?? term, fragment: 1 })}`, { credentials: "same-origin", signal: request.signal }).catch(() => null)
    if (request.signal.aborted) return
    if (!response?.ok) return this.show(this.errorTarget.content.cloneNode(true))
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    if (request.signal.aborted) return
    this.show(fresh.content)
  }

  // The region under the search: whatever is there now, replaced.
  show(content) {
    const region = [...this.element.children].filter((child) => !child.matches(".coach-members-search, template"))
    region.forEach((node) => node.remove())
    this.element.querySelector("template").before(content)
  }
}
