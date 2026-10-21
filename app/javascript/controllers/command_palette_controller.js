import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { scoped } from "../lib/ng"

const SCOPE = "command-palette"
const NO_REMOTE = { clients: [], contracts: [], payments: [] }

// CommandPaletteComponent: ⌘K (or the navbar's search button) opens it on
// an empty query; typing filters the shell's pages, adds an admin's "new …"
// actions, and — from two characters, 250 ms after the last key — the
// members, contracts and payments the term finds. ↑/↓ move, Enter or a
// click goes there, Escape or the backdrop closes it.
export default class extends Controller {
  static targets = ["overlay"]
  static values = { commands: Array, actions: Array, searchUrl: String, labels: Object }

  connect() {
    this.onKey = (event) => this.key(event)
    this.onOpen = (event) => {
      if (event.target.closest("[data-palette-open]")) this.open()
    }
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("click", this.onOpen)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("click", this.onOpen)
    clearTimeout(this.debounce)
  }

  get isOpen() {
    return Boolean(this.backdrop)
  }

  open() {
    if (this.isOpen) return
    this.term = ""
    this.active = 0
    this.remote = NO_REMOTE
    this.backdrop = this.overlayTarget.content.firstElementChild.cloneNode(true)
    this.element.append(this.backdrop)
    this.results = this.backdrop.querySelector("[data-command-palette-results]")
    this.results.removeAttribute("data-command-palette-results")
    this.draw()
    queueMicrotask(() => document.getElementById("cmdk-input")?.focus())
  }

  close() {
    clearTimeout(this.debounce)
    this.backdrop?.remove()
    this.backdrop = null
    this.searchSeq = (this.searchSeq ?? 0) + 1
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  // A click on the backdrop itself; the dialog stops its own (stopPropagation).
  dismiss(event) {
    if (!event.target.closest(".cmdk")) this.close()
  }

  query(event) {
    this.term = event.target.value
    this.active = 0
    this.draw()
    clearTimeout(this.debounce)
    const term = this.term.trim()
    if (term.length < 2) {
      this.remote = NO_REMOTE
      this.draw()
      return
    }
    this.debounce = setTimeout(() => this.search(term), 250)
  }

  async search(term) {
    if (!this.searchUrlValue) return
    const seq = (this.searchSeq = (this.searchSeq ?? 0) + 1)
    const url = `${this.searchUrlValue}?${new URLSearchParams({ q: term })}`
    const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" }).catch(() => null)
    if (!response?.ok || seq !== this.searchSeq || !this.isOpen) return
    this.remote = await response.json()
    this.draw()
  }

  key(event) {
    if ((event.metaKey || event.ctrlKey) && event.key?.toLowerCase() === "k") {
      event.preventDefault()
      this.toggle()
      return
    }
    if (!this.isOpen) return
    if (event.key === "Escape") {
      this.close()
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      this.active = Math.min(this.active + 1, this.flat().length - 1)
      this.draw()
      this.scrollActive()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.active = Math.max(this.active - 1, 0)
      this.draw()
      this.scrollActive()
    } else if (event.key === "Enter") {
      event.preventDefault()
      const command = this.flat()[this.active]
      if (command) this.run(command)
    }
  }

  run(command) {
    this.close()
    Turbo.visit(command.url)
  }

  // ---- What the list shows: CommandPaletteComponent#sections ----
  sections() {
    const q = this.term.trim().toLowerCase()
    const has = (command) => !q || command.label.toLowerCase().includes(q)
    const out = []
    const nav = this.commandsValue.filter(has).slice(0, 8)
    const actions = q.length > 0 ? this.actionsValue.filter(has) : []
    if (nav.length) out.push({ label: this.labelsValue.goto, items: nav })
    if (actions.length) out.push({ label: this.labelsValue.actions, items: actions })
    for (const key of ["clients", "contracts", "payments"]) {
      if (this.remote[key].length) out.push({ label: this.labelsValue[key], items: this.remote[key] })
    }
    return out
  }

  flat() {
    return this.sections().flatMap((section) => section.items)
  }

  draw() {
    const sections = this.sections()
    const nodes = []
    if (sections.length === 0) {
      nodes.push(this.div("cmdk-empty", this.term ? this.labelsValue.empty : this.labelsValue.placeholder))
    }
    let index = 0
    for (const section of sections) {
      nodes.push(this.div("cmdk-group", section.label))
      for (const command of section.items) nodes.push(this.item(command, index++))
    }
    this.results.replaceChildren(...nodes)
  }

  div(className, text) {
    const div = scoped(document.createElement("div"), SCOPE)
    div.className = className
    div.textContent = text
    return div
  }

  item(command, index) {
    const button = scoped(document.createElement("button"), SCOPE)
    button.type = "button"
    button.className = index === this.active ? "cmdk-item is-active" : "cmdk-item"
    const icon = scoped(document.createElement("i"), SCOPE)
    icon.className = `bi ${command.icon}`
    const label = scoped(document.createElement("span"), SCOPE)
    label.className = "cmdk-label"
    label.textContent = command.label
    button.append(icon, label)
    if (command.sub) {
      const sub = scoped(document.createElement("span"), SCOPE)
      sub.className = "cmdk-sub"
      sub.textContent = command.sub
      button.append(sub)
    }
    button.addEventListener("mouseenter", () => {
      this.active = index
      this.markActive()
    })
    button.addEventListener("click", () => this.run(command))
    return button
  }

  // The hover only moves the highlight: redrawing would replace the row
  // under the pointer.
  markActive() {
    this.results.querySelectorAll(".cmdk-item").forEach((button, i) => button.classList.toggle("is-active", i === this.active))
  }

  scrollActive() {
    queueMicrotask(() => this.results.querySelector(".cmdk-item.is-active")?.scrollIntoView({ block: "nearest" }))
  }
}
