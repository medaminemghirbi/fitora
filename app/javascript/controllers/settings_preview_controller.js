import { Controller } from "@hotwired/stimulus"

// The gym's documents beside a settings form: each printed line is redrawn as
// its field is typed in, and lit while that field has the focus. A line names
// the fields it prints (data-preview-line), with what goes between and before
// them, as the PDFs compose them.
export default class extends Controller {
  static targets = ["tab", "doc", "terms", "termsDefault", "signature", "signatureEmpty"]
  static values = { values: Object }

  connect() {
    this.fields = { ...this.valuesValue }
  }

  update(event) {
    const { name, value } = event.target
    if (!name || !(name in this.fields)) return
    this.fields[name] = value
    this.draw()
  }

  draw() {
    for (const line of this.lines) {
      const { previewJoin, previewPrefix, previewFallback } = line.dataset
      const text = line.dataset.previewLine.split(" ").map((field) => this.fields[field]).filter(Boolean).join(previewJoin ?? " ")
        || (previewFallback && this.fields[previewFallback]) || ""
      line.textContent = text ? `${previewPrefix ?? ""}${text}` : ""
      line.hidden = !text
    }
    if (this.hasTermsTarget) this.drawTerms()
  }

  // The first clauses, numbered by the list as the contract numbers them; the
  // PDF's own terms when the gym has written none.
  drawTerms() {
    const clauses = String(this.fields.contract_terms ?? "").split(/\r?\n/).map((line) => line.trim().replace(/^\d+[.)]\s*/, "")).filter(Boolean)
    this.termsTarget.replaceChildren(...clauses.slice(0, 3).map((clause) => {
      const item = document.createElement("li")
      item.textContent = clause
      return item
    }))
    this.termsTarget.hidden = clauses.length === 0
    this.termsDefaultTarget.hidden = clauses.length > 0
  }

  // settings-branding#announceSignature: the signature as it now stands.
  signatureChanged(event) {
    const { src } = event.detail
    for (const image of this.signatureTargets) {
      if (src) image.src = src
      image.hidden = !src
    }
    for (const empty of this.signatureEmptyTargets) empty.hidden = Boolean(src)
  }

  light(event) {
    this.dim()
    const name = event.target.name
    if (!name) return
    for (const line of this.lines) {
      if (line.dataset.previewLine.split(" ").includes(name)) line.classList.add("is-lit")
    }
    if (name === "contract_terms" && this.hasTermsTarget) {
      (this.termsTarget.hidden ? this.termsDefaultTarget : this.termsTarget).classList.add("is-lit")
    }
  }

  dim() {
    for (const lit of this.element.querySelectorAll(".set-doc .is-lit")) lit.classList.remove("is-lit")
  }

  show(event) {
    const wanted = event.currentTarget.dataset.doc
    for (const doc of this.docTargets) doc.hidden = doc.dataset.doc !== wanted
    for (const tab of this.tabTargets) tab.classList.toggle("is-active", tab.dataset.doc === wanted)
  }

  get lines() {
    return this.element.querySelectorAll("[data-preview-line]")
  }
}
