import { Controller } from "@hotwired/stimulus"
import { interpolate, scoped } from "../lib/ng"

// Lower-case, accents off — so "pilate", "Pilates" and "PILATÈS" all match.
const fold = (text) => text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim()

// ActivityPickerComponent: tiles to pick, family by family; a search that
// takes out of the DOM what does not match (the component's computed
// groups); and, where allowed, activities the gym names itself. Each change
// is announced as activity-picker:change { selected, custom }, the
// component's two models.
export default class extends Controller {
  static targets = ["count", "other", "customTemplate"]
  static values = { labels: Object }

  connect() {
    // Taken out of the DOM and put back (a step away and back), it is the
    // same picker: what was picked stays picked.
    if (this.selected) return
    this.selected = []
    this.custom = []
    this.term = ""
    this.groups = [...this.element.querySelectorAll("[data-family]")].map((section) => ({
      section, grid: section.querySelector(".ap-grid"), tiles: [...section.querySelectorAll(".ap-tile")],
    }))
    this.renderCount()
  }

  toggle(event) {
    const tile = event.currentTarget
    const id = tile.dataset.template
    const on = !this.selected.includes(id)
    this.selected = on ? [...this.selected, id] : this.selected.filter((x) => x !== id)
    tile.classList.toggle("is-on", on)
    tile.setAttribute("aria-checked", String(on))
    this.changed()
  }

  search(event) {
    this.term = event.target.value
    const term = fold(this.term)
    const bar = this.element.querySelector(".ap-bar")
    let last = this.element.querySelector(".ap-chips") ?? bar
    let any = false
    for (const { section, grid, tiles } of this.groups) {
      const matching = tiles.filter((tile) => !term || JSON.parse(tile.dataset.names).some((name) => fold(name).includes(term)))
      grid.replaceChildren(...matching)
      if (matching.length) {
        last.after(section)
        last = section
        any = true
      } else {
        section.remove()
      }
    }
    this.element.querySelector(".ap-empty")?.remove()
    if (!any) {
      const empty = this.make("p", "ap-empty")
      empty.textContent = interpolate(this.labelsValue.no_match, { term: this.term })
      last.after(empty)
    }
  }

  // ---- what the gym names itself -------------------------------------------

  // openCustom(): the name starts as what was being searched for.
  openCustom() {
    // Held: out of the DOM while the form stands in its place, it is no
    // longer a target Stimulus can find.
    const other = this.otherTarget
    const form = this.customTemplateTarget.content.firstElementChild.cloneNode(true)
    const name = form.querySelector("[data-custom-name]")
    const add = form.querySelector("[data-custom-add]")
    let emoji = null
    name.value = this.term.trim()
    add.disabled = !name.value.trim()
    name.addEventListener("input", () => (add.disabled = !name.value.trim()))
    name.addEventListener("keydown", (event) => {
      if (event.key !== "Enter") return
      event.preventDefault()
      submit()
    })
    for (const button of form.querySelectorAll("[data-custom-emoji]")) {
      button.addEventListener("click", () => {
        emoji = emoji === button.dataset.customEmoji ? null : button.dataset.customEmoji
        form.querySelectorAll("[data-custom-emoji]").forEach((b) => {
          b.classList.toggle("is-on", b.dataset.customEmoji === emoji)
          b.setAttribute("aria-pressed", String(b.dataset.customEmoji === emoji))
        })
      })
    }
    const close = () => form.replaceWith(other)
    const submit = () => {
      const text = name.value.trim()
      if (!text) return
      this.custom = [...this.custom, { name: text, emoji }]
      close()
      this.renderChips()
      this.changed()
    }
    form.querySelector("[data-custom-cancel]").addEventListener("click", close)
    add.addEventListener("click", submit)
    other.replaceWith(form)
  }

  removeCustom(index) {
    this.custom = this.custom.filter((_, i) => i !== index)
    this.renderChips()
    this.changed()
  }

  // The gym's own, ahead of the catalogue so it stays in view.
  renderChips() {
    this.element.querySelector(".ap-chips")?.remove()
    if (!this.custom.length) return
    const list = this.make("ul", "ap-chips")
    list.setAttribute("aria-label", this.labelsValue.yours)
    this.custom.forEach((entry, index) => {
      const chip = this.make("li", "ap-chip")
      if (entry.emoji) {
        const glyph = this.make("span")
        glyph.setAttribute("aria-hidden", "true")
        glyph.textContent = entry.emoji
        chip.append(glyph)
      }
      chip.append(` ${entry.name} `)
      const remove = this.make("button", "ap-chip-x")
      remove.type = "button"
      remove.setAttribute("aria-label", `${this.labelsValue.remove} ${entry.name}`)
      const x = this.make("i", "bi bi-x-lg")
      x.setAttribute("aria-hidden", "true")
      remove.append(x)
      remove.addEventListener("click", () => this.removeCustom(index))
      chip.append(remove)
      list.append(chip)
    })
    this.element.querySelector(".ap-bar").after(list)
  }

  // ---------------------------------------------------------------------------

  changed() {
    this.renderCount()
    this.dispatch("change", { detail: { selected: this.selected, custom: this.custom } })
  }

  renderCount() {
    const count = this.selected.length + this.custom.length
    if (count === 0) return this.countTarget.replaceChildren(` ${this.labelsValue.none} `)
    const strong = this.make("strong")
    strong.textContent = interpolate(this.labelsValue.n, { count })
    this.countTarget.replaceChildren(strong)
  }

  make(tag, className) {
    const element = scoped(document.createElement(tag), "activity-picker")
    if (className) element.className = className
    return element
  }
}
