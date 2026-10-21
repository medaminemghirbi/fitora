import { Controller } from "@hotwired/stimulus"
import { confirmAsk } from "../lib/confirm"
import { csrfToken, interpolate, scoped } from "../lib/ng"
import { toast } from "../lib/toast"

// SettingsRolesComponent: the matrix as edited — each role's ticked
// permissions held here (drafts), the boxes, the group boxes and the counts
// redrawn on every tick, a box flipped against what is saved marked until
// saved, the rows narrowed by the search (taken out of the table, as
// Angular's @for leaves them out), and the save bar while anything changed.
// The name dialog creates or renames a role; deleting asks first. After a
// save: the skeleton, then the matrix as saved (load()).
const SCOPE = "settings-roles"

export default class extends Controller {
  static targets = ["body", "data", "emptyRow", "savebar"]
  static values = { url: String, labels: Object }

  connect() {
    this.setup()
  }

  setup() {
    const data = JSON.parse(this.dataTarget.textContent)
    this.roles = data.roles
    this.columns = data.columns.map((id) => this.roles.find((r) => r.id === id))
    this.keys = data.keys
    this.groupDefs = data.groups
    this.permLabels = data.labels
    this.permHints = data.hints
    this.query = ""
    this.saving = false
    this.drafts = Object.fromEntries(this.roles.map((r) => [r.id, new Set(r.permissions)]))
    // Every row as rendered, to put back after a search.
    this.rows = new Map([...this.bodyTarget.querySelectorAll("tr.rm-row")].map((row) => [row.dataset.key, row]))
    this.groupRows = new Map([...this.bodyTarget.querySelectorAll("tr.rm-group")].map((row) => [row.dataset.group, row]))
    this.rm = this.element.querySelector(".rm")
  }

  // ---- reading the matrix -------------------------------------------------------

  isLocked(role) {
    return role.key === "admin"
  }

  isOn(role, key) {
    return this.isLocked(role) || this.drafts[role.id].has(key)
  }

  isChanged(role, key) {
    return !this.isLocked(role) && this.isOn(role, key) !== role.permissions.includes(key)
  }

  get groups() {
    const q = this.query.trim().toLowerCase()
    const matches = (k) => !q || this.permLabels[k].toLowerCase().includes(q) || this.permHints[k].toLowerCase().includes(q)
    const known = new Set(this.groupDefs.flatMap((g) => g.keys))
    const groups = this.groupDefs.map((g) => ({ id: g.id, keys: g.keys.filter((k) => this.keys.includes(k) && matches(k)) }))
    groups.push({ id: "other", keys: this.keys.filter((k) => !known.has(k) && matches(k)) })
    return groups.filter((g) => g.keys.length > 0)
  }

  groupState(role, group) {
    const n = group.keys.filter((k) => this.isOn(role, k)).length
    return n === group.keys.length ? "all" : n === 0 ? "none" : "some"
  }

  roleCount(role) {
    if (this.isLocked(role)) return this.keys.length
    return this.keys.filter((k) => this.drafts[role.id].has(k)).length
  }

  get changeCount() {
    let n = 0
    for (const role of this.roles) {
      if (this.isLocked(role)) continue
      const draft = this.drafts[role.id]
      const saved = new Set(role.permissions)
      draft.forEach((k) => saved.has(k) || n++)
      saved.forEach((k) => draft.has(k) || n++)
    }
    return n
  }

  roleOf(event) {
    return this.roles.find((r) => r.id === event.currentTarget.dataset.roleId)
  }

  // ---- editing --------------------------------------------------------------------

  toggle(event) {
    const role = this.roleOf(event)
    if (this.isLocked(role)) return
    const key = event.currentTarget.dataset.key
    const draft = this.drafts[role.id]
    draft.has(key) ? draft.delete(key) : draft.add(key)
    this.render()
  }

  toggleGroup(event) {
    const role = this.roleOf(event)
    if (this.isLocked(role)) return
    const group = this.groups.find((g) => g.id === event.currentTarget.dataset.group)
    const clear = this.groupState(role, group) === "all"
    group.keys.forEach((k) => (clear ? this.drafts[role.id].delete(k) : this.drafts[role.id].add(k)))
    this.render()
  }

  search(event) {
    this.query = event.target.value
    this.render()
  }

  reset() {
    this.drafts = Object.fromEntries(this.roles.map((r) => [r.id, new Set(r.permissions)]))
    this.render()
  }

  // ---- drawing --------------------------------------------------------------------

  render() {
    const groups = this.groups
    const body = []
    for (const group of groups) {
      const head = this.groupRows.get(group.id)
      head.querySelector(".rm-group-label span").textContent = group.keys.length
      head.querySelectorAll("button.rm-box").forEach((box) => this.drawGroupBox(box, group))
      body.push(head)
      for (const key of group.keys) {
        const row = this.rows.get(key)
        row.querySelectorAll("button.rm-box").forEach((box) => this.drawBox(box, key))
        body.push(row)
      }
    }
    if (groups.length === 0) body.push(this.emptyRowTarget.content.firstElementChild.cloneNode(true))
    this.bodyTarget.replaceChildren(...body)

    for (const role of this.columns) {
      const meta = this.element.querySelector(`[data-role-count="${role.id}"]`)
      if (meta) meta.textContent = ` ${interpolate(this.labelsValue.perm_count, { count: this.roleCount(role), total: this.keys.length })} `
    }
    this.drawSavebar()
  }

  drawBox(box, key) {
    const role = this.roles.find((r) => r.id === box.dataset.roleId)
    const on = this.isOn(role, key)
    box.classList.toggle("is-on", on && !this.isLocked(role))
    box.classList.toggle("is-changed", this.isChanged(role, key))
    box.setAttribute("aria-checked", String(on))
    box.disabled = this.isLocked(role) || this.saving
    box.replaceChildren(...(on ? [this.icon("bi-check-lg")] : []))
  }

  drawGroupBox(box, group) {
    const role = this.roles.find((r) => r.id === box.dataset.roleId)
    const state = this.groupState(role, group)
    box.classList.toggle("is-on", state === "all" && !this.isLocked(role))
    box.classList.toggle("is-mixed", state === "some")
    box.setAttribute("aria-checked", state === "all" ? "true" : state === "none" ? "false" : "mixed")
    box.disabled = this.isLocked(role) || this.saving
    box.replaceChildren(...(state === "all" ? [this.icon("bi-check-lg")] : state === "some" ? [this.icon("bi-dash-lg")] : []))
  }

  icon(name) {
    const i = scoped(document.createElement("i"), SCOPE)
    i.className = `bi ${name}`
    i.setAttribute("aria-hidden", "true")
    return i
  }

  drawSavebar() {
    const n = this.changeCount
    let bar = this.rm.querySelector(":scope > .rm-savebar")
    if (n === 0) return bar?.remove()
    if (!bar) {
      bar = this.savebarTarget.content.firstElementChild.cloneNode(true)
      this.rm.append(bar)
    }
    bar.querySelector("span").textContent = ` ${n === 1 ? this.labelsValue.changes_one : interpolate(this.labelsValue.changes_many, { count: n })} `
    const [ghost, save] = bar.querySelectorAll("button")
    ghost.disabled = this.saving
    save.disabled = this.saving
    save.textContent = ` ${this.saving ? this.labelsValue.saving : this.labelsValue.save} `
  }

  // ---- saving -----------------------------------------------------------------------

  async save() {
    const changed = this.roles.filter((role) => {
      if (this.isLocked(role)) return false
      const draft = this.drafts[role.id]
      const saved = new Set(role.permissions)
      return draft.size !== saved.size || [...draft].some((k) => !saved.has(k))
    })
    if (!changed.length) return
    this.saving = true
    this.render()
    const results = await Promise.all(changed.map((role) =>
      this.request("PATCH", `${this.urlValue}/${role.id}`, { role: { permissions: this.keys.filter((k) => this.drafts[role.id].has(k)) } })))
    this.saving = false
    const failed = results.find((r) => !r.ok)
    if (failed) {
      this.render()
      return toast("error", failed.error ?? this.labelsValue.error)
    }
    toast("success", this.labelsValue.saved)
    this.load()
  }

  // load(): the skeleton in place of the matrix, then the matrix as saved.
  async load() {
    const skeleton = this.element.ownerDocument.createElement("template")
    skeleton.innerHTML = this.skeletonMarkup()
    this.element.replaceChildren(skeleton.content)
    const response = await fetch(`${window.location.pathname}?fragment=1`, { credentials: "same-origin", headers: { Accept: "text/html" } }).catch(() => null)
    if (!response?.ok) return
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    this.element.replaceChildren(fresh.content)
    this.setup()
  }

  // <app-skeleton variant="table" [rows]="8" [cols]="4" />.
  skeletonMarkup() {
    const cell = '<span _ngcontent-skeleton="" class="fx-skeleton fx-skeleton--text"></span>'.repeat(4)
    const row = (head) => `<div _ngcontent-skeleton="" class="fx-skeleton-table-row${head ? " fx-skeleton-table-row--head" : ""}">${cell}</div>`
    return `<app-skeleton _ngcontent-${SCOPE}="" _nghost-skeleton=""><div _ngcontent-skeleton="" class="fx-skeleton-table" aria-hidden="true">${row(true)}${row(false).repeat(8)}</div></app-skeleton>`
  }

  // ---- adding, renaming, removing a role -------------------------------------------

  // Leaving unsaved boxes behind asks first (a reload would drop them).
  async canLeave() {
    if (this.changeCount === 0) return true
    return confirmAsk({ title: this.labelsValue.discard_title, body: this.labelsValue.discard_body, confirmLabel: this.labelsValue.discard_confirm, danger: true })
  }

  async startCreate() {
    if (!(await this.canLeave())) return
    this.openName("create", null)
  }

  async startRename(event) {
    const role = this.roleOf(event)
    if (role.builtin || !(await this.canLeave())) return
    this.openName("rename", role)
  }

  openName(mode, role) {
    this.dialog = { mode, role }
    this.nameError = null
    this.savingName = false
    const once = (event) => {
      if (event.detail.name !== "roles-name") return
      window.removeEventListener("modal:opened", once)
      this.fillName(event.detail.panel)
    }
    window.addEventListener("modal:opened", once)
    window.dispatchEvent(new CustomEvent("roles-name:open"))
  }

  fillName(panel) {
    const { mode, role } = this.dialog
    const title = mode === "rename" ? this.labelsValue.rename : this.labelsValue.new
    panel.querySelector(".modal-panel-header h3").textContent = title
    panel.setAttribute("aria-label", title)
    const form = panel.querySelector("[data-roles-name-form]")
    if (mode !== "create") form.querySelector("[data-create-only]").remove()
    form.elements.name.value = role?.name ?? ""
    this.namePanel = panel
    this.drawName()
    form.addEventListener("submit", (event) => {
      event.preventDefault()
      this.submitName(form)
    })
  }

  drawName() {
    const form = this.namePanel.querySelector("[data-roles-name-form]")
    form.querySelector(".invalid-feedback")?.remove()
    if (this.nameError) {
      const error = scoped(document.createElement("div"), SCOPE)
      error.className = "invalid-feedback d-block"
      error.textContent = this.nameError
      form.elements.name.after(error)
    }
    const save = form.querySelector("[data-save]")
    save.disabled = this.savingName
    save.textContent = ` ${this.savingName ? this.labelsValue.saving : this.dialog.mode === "rename" ? this.labelsValue.save : this.labelsValue.create} `
  }

  async submitName(form) {
    const name = form.elements.name.value.trim()
    if (!name) {
      this.nameError = this.labelsValue.name_required
      return this.drawName()
    }
    this.savingName = true
    this.nameError = null
    this.drawName()
    const { mode, role } = this.dialog
    const result = mode === "rename" && role
      ? await this.request("PATCH", `${this.urlValue}/${role.id}`, { role: { name } })
      : await this.request("POST", this.urlValue, { role: { name, permissions: [] } })
    this.savingName = false
    if (!result.ok) {
      this.nameError = result.error ?? this.labelsValue.error
      return form.isConnected && this.drawName()
    }
    window.dispatchEvent(new CustomEvent("roles-name:close"))
    toast("success", this.labelsValue.saved)
    this.load()
  }

  async remove(event) {
    const role = this.roleOf(event)
    if (!role.deletable || !(await this.canLeave())) return
    const ok = await confirmAsk({ title: interpolate(this.labelsValue.delete_title, { name: role.name }), body: this.labelsValue.delete_body, danger: true })
    if (!ok) return
    const result = await this.request("DELETE", `${this.urlValue}/${role.id}`)
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    toast("success", this.labelsValue.deleted)
    this.load()
  }

  async request(method, url, body) {
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
}
