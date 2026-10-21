import { Controller } from "@hotwired/stimulus"
import { highlight } from "../lib/highlight"
import { pagination } from "../lib/pagination"

// A list the page loads whole and searches and pages in the browser, as the
// Angular pages do with client-list.ts: filterBySearch (every word of each
// row's data-search, case-insensitive), pages of 25 (pageSlice,
// clientPageMeta), the search highlighted, page 1 again on every new search.
//
// The server renders every row once in a <template> (rowsTarget) and the
// first page in place, so the first paint needs no script.
const PER_PAGE = 25

export default class extends Controller {
  static targets = ["rows", "body", "noResultsTemplate", "card", "tableWrap"]
  static values = { labels: Object, scope: String }

  connect() {
    this.rows = [...this.rowsTarget.content.children]
    // Kept here: a target that has left the DOM can no longer be read.
    this.tableWrap = this.tableWrapTarget
    this.body = this.bodyTarget
    this.noResults = this.noResultsTemplateTarget.content.firstElementChild.cloneNode(true)
    this.term = ""
    this.page = 1
  }

  search(event) {
    this.term = event.target.value
    this.page = 1
    this.render()
  }

  goToPage(event) {
    this.page = Number(event.currentTarget.dataset.page)
    this.render()
  }

  render() {
    const needle = this.term.trim().toLowerCase()
    const filtered = needle ? this.rows.filter((row) => (row.dataset.search ?? "").toLowerCase().split("\u001f").some((f) => f.includes(needle))) : this.rows
    const card = this.cardTarget
    card.querySelector(":scope > app-pagination")?.remove()

    if (filtered.length === 0) {
      this.tableWrap.remove()
      if (!this.noResults.isConnected) card.append(this.noResults)
      return
    }
    this.noResults.remove()
    if (!this.tableWrap.isConnected) card.append(this.tableWrap)

    const start = (this.page - 1) * PER_PAGE
    const shown = filtered.slice(start, start + PER_PAGE).map((row) => {
      const copy = row.cloneNode(true)
      copy.querySelectorAll("[data-highlight]").forEach((cell) => {
        cell.innerHTML = highlight(cell.dataset.highlight, this.term)
      })
      return copy
    })
    this.body.replaceChildren(...shown)
    const meta = { page: this.page, total: filtered.length, total_pages: Math.max(1, Math.ceil(filtered.length / PER_PAGE)) }
    card.append(pagination(meta, this.labelsValue, this.scopeValue))
  }
}
