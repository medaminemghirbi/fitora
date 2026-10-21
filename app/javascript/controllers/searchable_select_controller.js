import { Controller } from "@hotwired/stimulus"
import { scoped } from "../lib/ng"

// SearchableSelectComponent: a text-filterable dropdown. Type to filter,
// ↑/↓ to move, Enter to pick, Esc to close; a click elsewhere closes it.
// Its options come from the page (setOptions), as the component's input
// does; a pick is announced as searchable-select:change { value }.
export default class extends Controller {
  static values = { id: String, placeholder: String, search: String, empty: String }

  connect() {
    // Kept across a step away and back (the element leaves the DOM and
    // returns: Stimulus connects this same controller again).
    this.options ??= []
    this.value ??= ""
    this.open = false
    this.query = ""
    this.highlight = 0
    // The event's path, not contains(): a click inside may have re-rendered
    // (and so detached) the element it landed on.
    this.onDocument = (event) => this.open && !event.composedPath().includes(this.element) && this.close()
    document.addEventListener("click", this.onDocument)
    this.render()
  }

  disconnect() {
    document.removeEventListener("click", this.onDocument)
  }

  setOptions(options, value) {
    this.options = options
    this.value = value ?? ""
    this.render()
  }

  get filtered() {
    const q = this.query.trim().toLowerCase()
    if (!q) return this.options
    return this.options.filter((o) => o.label.toLowerCase().includes(q) || o.value.toLowerCase().includes(q))
  }

  // ---------------------------------------------------------------------------

  toggle() {
    this.open ? this.close() : this.openPanel()
  }

  openPanel() {
    this.query = ""
    this.highlight = Math.max(0, this.filtered.findIndex((o) => o.value === this.value))
    this.open = true
    this.render()
    setTimeout(() => this.element.querySelector(".ss-search input")?.focus())
  }

  close(focusTrigger = false) {
    this.open = false
    this.render()
    if (focusTrigger) this.element.querySelector(".ss-trigger").focus()
  }

  pick(option) {
    this.value = option.value
    this.dispatch("change", { detail: { value: option.value } })
    this.close(true)
  }

  triggerKey(event) {
    if (!this.open && ["ArrowDown", "Enter", " "].includes(event.key)) {
      event.preventDefault()
      this.openPanel()
    }
  }

  searchKey(event) {
    const items = this.filtered
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      if (!items.length) return
      this.highlight = (this.highlight + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length
      this.renderList()
      setTimeout(() => this.element.querySelector(".ss-list").children[this.highlight]?.scrollIntoView({ block: "nearest" }))
    } else if (event.key === "Enter") {
      event.preventDefault()
      const option = items[this.highlight]
      if (option) this.pick(option)
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.close(true)
    }
  }

  // ---- the component's template ------------------------------------------------

  make(tag, className) {
    const element = scoped(document.createElement(tag), "searchable-select")
    if (className) element.className = className
    return element
  }

  render() {
    const root = this.make("div", `ss${this.open ? " is-open" : ""}`)
    const trigger = this.make("button", "ss-trigger form-control")
    trigger.type = "button"
    trigger.id = this.idValue
    trigger.setAttribute("aria-expanded", String(this.open))
    trigger.setAttribute("aria-haspopup", "listbox")
    trigger.addEventListener("click", () => this.toggle())
    trigger.addEventListener("keydown", (event) => this.triggerKey(event))
    const selected = this.options.find((o) => o.value === this.value)
    if (selected) {
      const value = this.make("span", "ss-value")
      if (selected.prefix) {
        const prefix = this.make("span", "ss-prefix")
        prefix.textContent = selected.prefix
        value.append(prefix)
      }
      value.append(` ${selected.label}`)
      trigger.append(value)
    } else {
      const placeholder = this.make("span", "ss-placeholder")
      placeholder.textContent = this.placeholderValue
      trigger.append(placeholder)
    }
    trigger.append(this.make("i", "bi bi-chevron-down ss-chevron"))
    root.append(trigger)

    if (this.open) {
      const panel = this.make("div", "ss-panel")
      panel.setAttribute("role", "listbox")
      const search = this.make("div", "ss-search")
      const input = this.make("input")
      input.type = "text"
      input.value = this.query
      input.placeholder = this.searchValue
      input.autocomplete = "off"
      input.addEventListener("input", () => {
        this.query = input.value
        this.highlight = 0
        this.renderList()
      })
      input.addEventListener("keydown", (event) => this.searchKey(event))
      search.append(this.make("i", "bi bi-search"), input)
      panel.append(search, this.make("ul", "ss-list"))
      root.append(panel)
    }
    this.element.replaceChildren(root)
    if (this.open) this.renderList()
  }

  renderList() {
    const list = this.element.querySelector(".ss-list")
    const items = this.filtered
    if (!items.length) {
      const empty = this.make("li", "ss-empty")
      empty.textContent = this.emptyValue
      return list.replaceChildren(empty)
    }
    list.replaceChildren(...items.map((option, i) => {
      const item = this.make("li")
      item.setAttribute("role", "option")
      item.setAttribute("aria-selected", String(option.value === this.value))
      if (i === this.highlight) item.classList.add("is-active")
      if (option.value === this.value) item.classList.add("is-selected")
      if (option.prefix) {
        const prefix = this.make("span", "ss-prefix")
        prefix.textContent = option.prefix
        item.append(prefix)
      }
      const label = this.make("span")
      label.textContent = option.label
      item.append(label)
      if (option.value === this.value) item.append(this.make("i", "bi bi-check2 ss-check"))
      item.addEventListener("mouseenter", () => {
        this.highlight = i
        list.querySelectorAll("li").forEach((li, j) => li.classList.toggle("is-active", j === i))
      })
      item.addEventListener("click", () => this.pick(option))
      return item
    }))
  }
}
