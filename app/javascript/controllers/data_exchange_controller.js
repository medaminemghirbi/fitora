import { Controller } from "@hotwired/stimulus"
import { csrfToken, downloadBlob, interpolate, scoped, spinner } from "../lib/ng"
import { toast } from "../lib/toast"

// DataExchangeComponent: per entity, its CSV template and its export
// (downloaded under the component's own file names); an import read and
// previewed in the browser — nothing sent until "Importer" — then followed
// until the server is done (every second, as the service polls), and its
// result kept per entity.
const SCOPE = "data-exchange"
const PREVIEW_ROW_LIMIT = 20
const IMPORT_POLL_MS = 1000

// parseCsv (csv.util.ts): RFC 4180, enough to preview a file.
export function parseCsv(text) {
  const rows = []
  let row = []
  let field = ""
  let inQuotes = false
  for (let i = 0; i < text.length; i++) {
    const char = text[i]
    if (inQuotes) {
      if (char === '"') {
        if (text[i + 1] === '"') {
          field += '"'
          i++
        } else {
          inQuotes = false
        }
      } else {
        field += char
      }
      continue
    }
    if (char === '"') {
      inQuotes = true
    } else if (char === ",") {
      row.push(field)
      field = ""
    } else if (char === "\n" || char === "\r") {
      if (char === "\r" && text[i + 1] === "\n") i++
      row.push(field)
      field = ""
      if (row.some((cell) => cell !== "")) rows.push(row)
      row = []
    } else {
      field += char
    }
  }
  if (field !== "" || row.length > 0) {
    row.push(field)
    if (row.some((cell) => cell !== "")) rows.push(row)
  }
  return rows
}

export default class extends Controller {
  static targets = ["title", "desc", "body", "upload", "previewTemplate", "entities"]
  static values = { url: String, labels: Object }

  connect() {
    this.entities = JSON.parse(this.entitiesTarget.textContent)
    this.entity = "clients"
    this.results = {}
    this.preview = null
    this.previewError = null
    this.importing = false
    // Held: it leaves the DOM while a file is previewed.
    this.upload = this.uploadTarget
  }

  selectEntity(event) {
    const entity = event.target.value
    if (entity === this.entity) return
    this.entity = entity
    const card = this.entities[entity]
    const icon = scoped(document.createElement("i"), SCOPE)
    icon.className = `bi ${card.icon}`
    this.titleTarget.replaceChildren(icon, ` ${card.title}`)
    this.descTarget.textContent = card.desc
    this.preview = null
    this.previewError = null
    this.render()
  }

  // ---- downloads ------------------------------------------------------------------

  async download(event) {
    const button = event.currentTarget
    const kind = button.dataset.download
    const entity = this.entity
    const icon = button.querySelector("i")
    button.disabled = true
    const busy = spinner(14, SCOPE)
    icon.replaceWith(busy)
    const response = await fetch(`${this.urlValue}/${entity}/${kind}`, { credentials: "same-origin" }).catch(() => null)
    button.disabled = false
    busy.replaceWith(icon)
    if (!response?.ok) return toast("error", this.labelsValue.error)
    downloadBlob(await response.blob(), `fitora-${entity}-${kind === "template" ? "modele" : "export"}.csv`)
  }

  // ---- the preview ----------------------------------------------------------------

  fileSelected(event) {
    const input = event.target
    const file = input.files?.[0]
    input.value = ""
    if (!file) return
    delete this.results[this.entity]
    this.previewError = null
    const reader = new FileReader()
    reader.onload = () => {
      const rows = parseCsv(String(reader.result ?? ""))
      if (rows.length === 0) {
        this.previewError = this.labelsValue.preview_empty
        return this.render()
      }
      this.preview = { file, headers: rows[0], total: rows.length - 1, rows: rows.slice(1, 1 + PREVIEW_ROW_LIMIT) }
      this.render()
    }
    reader.onerror = () => {
      this.previewError = this.labelsValue.preview_empty
      this.render()
    }
    reader.readAsText(file)
    this.render()
  }

  clearPreview() {
    this.preview = null
    this.previewError = null
    this.render()
  }

  // ---- the import -----------------------------------------------------------------

  async confirmImport() {
    if (!this.preview) return
    const entity = this.entity
    this.importing = true
    this.render()
    const form = new FormData()
    form.append("file", this.preview.file)
    let status = await this.request("POST", `${this.urlValue}/${entity}/import`, form)
    while (status.ok && !status.data.finished) {
      await new Promise((resolve) => setTimeout(resolve, IMPORT_POLL_MS))
      status = await this.request("GET", `${this.urlValue}/imports/${status.data.id}`)
    }
    this.importing = false
    if (!status.ok || status.data.status === "failed") {
      this.render()
      return toast("error", (status.ok ? status.data.message : status.error) ?? this.labelsValue.error)
    }
    const result = { created: status.data.created, errors: status.data.errors }
    this.results[entity] = result
    this.preview = null
    this.render()
    if (result.created > 0) toast("success", interpolate(this.labelsValue.created, { count: result.created }))
    if (result.errors.length > 0 && result.created === 0) toast("error", this.labelsValue.failed)
  }

  async request(method, url, body) {
    const response = await fetch(url, {
      method, credentials: "same-origin",
      headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body,
    }).catch(() => null)
    const data = await response?.json().catch(() => ({}))
    return response?.ok ? { ok: true, data } : { ok: false, error: data?.error ?? null }
  }

  // ---- drawing ----------------------------------------------------------------------
  // After the actions: the upload (and its error), or the preview; then the
  // entity's last result.

  render() {
    const body = this.bodyTarget
    const actions = body.querySelector(".data-exchange-actions")
    while (actions.nextSibling) actions.nextSibling.remove()

    if (!this.preview) {
      body.append(this.upload)
      if (this.previewError) {
        const p = this.el("p", "data-exchange-preview-error")
        p.append(this.el("i", "bi bi-exclamation-triangle"), ` ${this.previewError}`)
        body.append(p)
      }
    } else {
      body.append(this.previewBox())
    }

    const result = this.results[this.entity]
    if (result) {
      const box = this.el("div", `data-exchange-result${result.errors.length > 0 ? " has-errors" : ""}`)
      const summary = this.el("p", "data-exchange-result-summary")
      summary.append(this.el("i", "bi bi-check-circle-fill"), ` ${interpolate(this.labelsValue.created, { count: result.created })} `)
      box.append(summary)
      if (result.errors.length > 0) {
        const list = this.el("ul", "data-exchange-errors")
        for (const err of result.errors) {
          const li = this.el("li")
          const strong = this.el("strong")
          strong.textContent = `${this.labelsValue.row} ${err.row}`
          li.append(strong, ` — ${err.message}`)
          list.append(li)
        }
        box.append(list)
      }
      body.append(box)
    }
  }

  previewBox() {
    const p = this.preview
    const box = this.previewTemplateTarget.content.firstElementChild.cloneNode(true)
    // After the icon (the template's trailing space is dropped, as Angular drops it).
    box.querySelector("[data-file-name]").append(` ${p.file.name}`)
    box.querySelector("[data-rows]").textContent = interpolate(this.labelsValue.preview_rows, { count: p.total })
    const head = box.querySelector("[data-head]")
    for (const h of p.headers) {
      const th = this.el("th")
      th.textContent = h
      head.append(th)
    }
    const tbody = box.querySelector("[data-body]")
    for (const row of p.rows) {
      const tr = this.el("tr")
      for (const cell of row) {
        const td = this.el("td")
        td.textContent = cell
        tr.append(td)
      }
      tbody.append(tr)
    }
    if (p.total > p.rows.length) {
      const note = this.el("p", "text-muted-token small")
      note.textContent = interpolate(this.labelsValue.truncated, { shown: p.rows.length, total: p.total })
      box.querySelector(".data-exchange-preview-scroll").after(note)
    }
    const buttons = box.querySelectorAll(".data-exchange-preview-actions button")
    buttons.forEach((b) => (b.disabled = this.importing))
    if (this.importing) buttons[1].querySelector("i").replaceWith(spinner(14, SCOPE))
    return box
  }

  el(tag, className) {
    const node = scoped(document.createElement(tag), SCOPE)
    if (className) node.className = className
    return node
  }
}
