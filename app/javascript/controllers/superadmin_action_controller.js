import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { confirmAsk } from "../lib/confirm"
import { csrfToken } from "../lib/ng"
import { toast } from "../lib/toast"

// A console action asked first (an account's access, deleting a template): the
// confirmation, then the page comes back as the server has it, with its toast.
export default class extends Controller {
  static values = { url: String, method: { type: String, default: "POST" }, title: String, body: String, confirm: String, danger: Boolean, error: String }

  async run() {
    const confirmed = await confirmAsk({ title: this.titleValue, body: this.bodyValue, confirmLabel: this.confirmValue, danger: this.dangerValue })
    if (!confirmed) return

    this.element.disabled = true
    const response = await fetch(this.urlValue, {
      method: this.methodValue,
      headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
      credentials: "same-origin",
    }).catch(() => null)
    if (response?.ok) return Turbo.visit(window.location.href, { action: "replace" })

    this.element.disabled = false
    toast("error", this.errorValue)
  }
}
