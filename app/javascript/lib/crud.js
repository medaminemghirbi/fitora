import { Turbo } from "@hotwired/turbo-rails"
import { csrfToken, scoped } from "./ng"

// What the Angular list pages do around a save or a delete: send it; on a
// refusal show the API's message at the top of the modal (formError); on
// success close it, toast, and load the list again — the same skeleton in
// the card while it comes (the server's flash carries the toast).

export async function send(method, url, body) {
  const response = await fetch(url, {
    method, credentials: "same-origin",
    headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
    body: body === undefined ? undefined : JSON.stringify(body),
  }).catch(() => null)
  if (!response) return { ok: false, error: null }
  if (response.ok) return { ok: true }
  const payload = await response.json().catch(() => ({}))
  return { ok: false, error: payload.error ?? null }
}

// The modal's error alert, first in its body (`@if (formError())`).
export function showFormError(panel, message, scope) {
  const body = panel.querySelector(".modal-panel-body")
  body.querySelector(":scope > .alert-danger")?.remove()
  if (!message) return
  const alert = scoped(document.createElement("div"), scope)
  alert.className = "alert alert-danger"
  alert.textContent = message
  body.prepend(alert)
}

// load() again: the skeleton in the card, then the page as it is now.
export function reloadList(card, rows, cols, { visit = true } = {}) {
  if (card) {
    const body = document.createElement("div")
    body.className = "app-card-body"
    const host = scoped(document.createElement("app-skeleton"), null, "skeleton")
    const table = scoped(document.createElement("div"), "skeleton")
    table.className = "fx-skeleton-table"
    table.setAttribute("aria-hidden", "true")
    for (let r = 0; r <= rows; r++) {
      const row = scoped(document.createElement("div"), "skeleton")
      row.className = `fx-skeleton-table-row${r === 0 ? " fx-skeleton-table-row--head" : ""}`
      for (let c = 0; c < cols; c++) {
        const cell = scoped(document.createElement("span"), "skeleton")
        cell.className = "fx-skeleton fx-skeleton--text"
        row.append(cell)
      }
      table.append(row)
    }
    host.append(table)
    body.append(host)
    card.replaceChildren(body)
  }
  if (visit) Turbo.visit(window.location.href, { action: "replace" })
}
