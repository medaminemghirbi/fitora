import { Controller } from "@hotwired/stimulus"
import { confirmAsk } from "../lib/confirm"
import { interpolate } from "../lib/ng"

const PLACEHOLDER = /\{\{\s*([^{}]*?)\s*\}\}/g

// Writing a mailing (web/superadmin/mailings/new): a template fills the text;
// the accounts are searched, narrowed and ticked; the preview shows what the
// first ticked account will read (what no account can fill stays as typed, and
// the server refuses it); sending is asked first. The server checks it all again.
export default class extends Controller {
  static targets = ["template", "row", "search", "state", "all", "count", "empty", "previewFor", "previewSubject", "previewBody", "submit"]
  static values = { templates: Array, labels: Object }

  connect() {
    this.filter()
  }

  get subjectField() {
    return this.element.querySelector('[data-mail-editor-target="subject"]')
  }

  get bodyField() {
    return this.element.querySelector('[data-mail-editor-target="body"]')
  }

  get ticked() {
    return this.rowTargets.filter((row) => row.querySelector("input").checked)
  }

  applyTemplate() {
    const chosen = this.templatesValue.find((template) => template.id === this.templateTarget.value)
    if (!chosen) return

    this.subjectField.value = chosen.subject
    this.bodyField.value = chosen.body
    this.refresh()
  }

  filter() {
    const term = this.searchTarget.value.trim().toLowerCase()
    const state = this.stateTarget.value
    this.rowTargets.forEach((row) => {
      row.hidden = !row.dataset.search.includes(term) || (state !== "" && row.dataset.state !== state)
    })
    this.emptyTarget.hidden = this.rowTargets.some((row) => !row.hidden)
    this.refresh()
  }

  // Ticks or unticks what the search and the filter leave showing.
  toggleAll({ currentTarget }) {
    this.rowTargets.filter((row) => !row.hidden).forEach((row) => (row.querySelector("input").checked = currentTarget.checked))
    this.refresh()
  }

  // Not for "tick all" itself: its input event comes before its change, and
  // answering it here would untick it before toggleAll reads it.
  refresh(event) {
    if (event?.target === this.allTarget) return

    const ticked = this.ticked
    const count = ticked.length
    this.countTarget.textContent = interpolate(this.labelsValue.selected, { count })
    const showing = this.rowTargets.filter((row) => !row.hidden)
    this.allTarget.checked = showing.length > 0 && showing.every((row) => row.querySelector("input").checked)
    this.submitTarget.textContent = count ? interpolate(this.labelsValue.send, { count }) : this.labelsValue.send_empty
    this.drawPreview(ticked[0])
  }

  drawPreview(row) {
    const values = row ? JSON.parse(row.dataset.values) : null
    const fill = (text) => (values ? text.replace(PLACEHOLDER, (typed, name) => values[name] ?? typed) : text)
    this.previewForTarget.textContent = row ? interpolate(this.labelsValue.preview_for, { name: row.dataset.name }) : this.labelsValue.preview_none
    this.previewSubjectTarget.textContent = fill(this.subjectField.value)
    this.previewBodyTarget.textContent = fill(this.bodyField.value)
  }

  // What is plainly missing goes to the server, which says so on the fields;
  // what is ready is asked first, since a sending cannot be taken back.
  async submit(event) {
    event.preventDefault()
    const count = this.ticked.length
    if (count && this.subjectField.value.trim() && this.bodyField.value.trim()) {
      const confirmed = await confirmAsk({
        title: this.labelsValue.confirm_title,
        body: interpolate(this.labelsValue.confirm_body, { count }),
        confirmLabel: this.labelsValue.send_empty,
      })
      if (!confirmed) return
    }
    this.submitTarget.disabled = true
    this.element.submit()
  }
}
