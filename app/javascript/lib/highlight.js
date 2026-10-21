// HighlightPipe: every case-insensitive occurrence of the term wrapped in
// <mark class="fx-hl">, the text and the term escaped first.
const ESCAPE = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }
const escapeHtml = (value) => value.replace(/[&<>"']/g, (c) => ESCAPE[c])
const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")

export function highlight(text, term) {
  const source = text == null ? "" : String(text)
  const needle = (term ?? "").trim()
  if (!needle) return escapeHtml(source)
  const re = new RegExp(escapeRegExp(escapeHtml(needle)), "gi")
  return escapeHtml(source).replace(re, (match) => `<mark class="fx-hl">${match}</mark>`)
}
