import { Controller } from "@hotwired/stimulus"
import { confirmAsk } from "../lib/confirm"
import { csrfToken } from "../lib/ng"
import { toast } from "../lib/toast"

// SettingsMobileAppComponent: copy a key (in capitals, as shown), or
// replace one — asked first; the old key stops pairing at once — and show
// the new key and QR code.
export default class extends Controller {
  static values = { url: String, labels: Object }

  copy(event) {
    const key = event.currentTarget.closest(".ma-card").querySelector("[data-key]").textContent
    navigator.clipboard?.writeText(key).then(
      () => toast("success", this.labelsValue.copied),
      () => toast("error", this.labelsValue.error)
    )
  }

  async regenerate(event) {
    const button = event.currentTarget
    const card = button.closest(".ma-card")
    const ok = await confirmAsk({ title: this.labelsValue.title, body: this.labelsValue.body, danger: true })
    if (!ok) return
    button.disabled = true
    const response = await fetch(this.urlValue, {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ audience: card.dataset.audience }),
    }).catch(() => null)
    const payload = await response?.json().catch(() => ({}))
    button.disabled = false
    if (!response?.ok) return toast("error", payload?.error ?? this.labelsValue.error)
    for (const [audience, key, svg] of [["member", payload.member_code, payload.member_qr_svg], ["coach", payload.coach_key, payload.coach_qr_svg]]) {
      const each = this.element.querySelector(`.ma-card[data-audience="${audience}"]`)
      each.querySelector("[data-key]").textContent = key.toUpperCase()
      each.querySelector("[data-qr]").innerHTML = svg
    }
    toast("success", this.labelsValue.done)
  }
}
