import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const normalize = (text) => text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase()

// The settings' own menu: narrowed as you type, by a section's name or what it
// holds ("logo", "signature"), Enter opening the first one left; and the phone's
// section picker.
export default class extends Controller {
  static targets = ["group", "item", "empty"]

  filter(event) {
    const query = normalize(event.target.value.trim())
    for (const item of this.itemTargets) item.hidden = !normalize(item.dataset.search).includes(query)
    for (const group of this.groupTargets) group.hidden = !group.querySelector(".set-nav-item:not([hidden])")
    this.emptyTarget.hidden = this.itemTargets.some((item) => !item.hidden)
  }

  openFirst(event) {
    event.preventDefault()
    const first = this.itemTargets.find((item) => !item.hidden)
    if (first) Turbo.visit(first.href)
  }

  pick(event) {
    if (event.target.value) Turbo.visit(event.target.value)
  }
}
