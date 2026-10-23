import { Controller } from "@hotwired/stimulus"
import { toast } from "../lib/toast"

// A copy button: puts its text on the clipboard, says so in a toast, and
// shows a tick for a moment. No clipboard (a page not on HTTPS): an error,
// rather than a click that does nothing.
export default class extends Controller {
  static values = { text: String, done: String, error: String }

  copy() {
    if (!navigator.clipboard) return toast("error", this.errorValue)

    navigator.clipboard.writeText(this.textValue).then(
      () => this.copied(),
      () => toast("error", this.errorValue)
    )
  }

  copied() {
    toast("success", this.doneValue)
    const icon = this.element.querySelector("i")
    icon?.classList.replace("bi-clipboard", "bi-clipboard-check")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => icon?.classList.replace("bi-clipboard-check", "bi-clipboard"), 1500)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
