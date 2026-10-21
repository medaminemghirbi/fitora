import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Moves on by itself after a moment, as a component's setTimeout(navigate) does.
export default class extends Controller {
  static values = { url: String, after: Number }

  connect() {
    this.timer = setTimeout(() => Turbo.visit(this.urlValue), this.afterValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
