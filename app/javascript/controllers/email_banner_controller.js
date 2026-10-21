import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "../lib/ng"

// AdminShellComponent's "confirm your address" banner: resend the link
// (then say so), or put it away for the rest of this browser session —
// a session cookie, since every Rails page is a fresh load (M-07).
export default class extends Controller {
  static targets = ["body", "resend"]
  static values = { url: String, resent: String }

  async resend() {
    this.resendTarget.disabled = true
    try {
      const response = await fetch(this.urlValue, { method: "POST", headers: { "X-CSRF-Token": csrfToken() }, credentials: "same-origin" })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      // verificationResent: the message alone, without the link.
      this.bodyTarget.textContent = this.resentValue
      this.resendTarget.remove()
    } catch {
      this.resendTarget.disabled = false
    }
  }

  dismiss() {
    document.cookie = "fitora_email_banner=dismissed; path=/; samesite=lax"
    this.element.remove()
  }
}
