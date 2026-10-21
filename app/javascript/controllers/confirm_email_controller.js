import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { csrfToken, spinner } from "../lib/ng"
import { AUTH_CHANNEL } from "./verify_email_controller"

// ConfirmEmailComponent: waits for the emailed link to be clicked — asking
// the server every 4 s while the tab is visible, at once when it comes back
// into view or when another tab says the link was clicked — then moves on by
// itself. Resending is counted down (60 s, or what the server says is left)
// and says that only the newest link works. This element is the envelope's
// host; the page's waiting blocks carry data-ce-waiting.
const POLL_MS = 4000
const RESEND_COOLDOWN_SECONDS = 60

export default class extends Controller {
  static values = { resendIn: Number, delay: Number, labels: Object }

  connect() {
    this.phase = "waiting"
    this.resending = false
    this.timeouts = []
    this.resendButton = document.querySelector("[data-ce-resend]")
    this.resendButton.addEventListener("click", () => this.resend())
    this.startCountdown(this.resendInValue)

    this.pollTimer = setInterval(() => {
      if (document.visibilityState === "visible") this.check()
    }, POLL_MS)
    this.onWake = () => {
      if (document.visibilityState === "visible") this.check()
    }
    window.addEventListener("focus", this.onWake)
    document.addEventListener("visibilitychange", this.onWake)
    if (typeof BroadcastChannel !== "undefined") {
      this.channel = new BroadcastChannel(AUTH_CHANNEL)
      this.channel.onmessage = (event) => {
        if (event.data?.type === "email-verified") this.check()
      }
    }
  }

  disconnect() {
    this.stop()
  }

  // Has the link been clicked yet? Quiet on failure: the next tick asks again.
  async check() {
    if (this.checking || this.phase === "confirmed") return
    this.checking = true
    try {
      const response = await fetch("/confirmation-email/status", { headers: { Accept: "application/json" }, credentials: "same-origin" })
      const status = await response.json()
      if (status.email_verified) this.confirmed(status.continue_url)
    } catch {
      // asked again on the next tick
    } finally {
      this.checking = false
    }
  }

  async resend() {
    if (this.resendIn > 0 || this.resending) return
    this.resending = true
    this.notice(null)
    this.renderResend()

    const response = await fetch("/confirmation-email/resend", {
      method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() }, credentials: "same-origin",
    }).catch(() => null)
    this.resending = false

    if (response?.ok) {
      this.notice("sent")
      this.startCountdown(RESEND_COOLDOWN_SECONDS)
      this.fly()
    } else if (response?.status === 429) {
      const body = await response.json().catch(() => ({}))
      this.startCountdown(Number(body.retry_in) || RESEND_COOLDOWN_SECONDS)
    } else if (response && (await response.clone().json().catch(() => ({}))).error === "already_verified") {
      this.check() // clicked in the meantime
    } else {
      this.notice("error")
    }
    this.renderResend()
  }

  // ---------------------------------------------------------------------

  confirmed(continueUrl) {
    this.phase = "confirmed"
    this.stopListening()
    this.stage("confirmed")

    const email = document.querySelector('[data-ce-step="email"]')
    email.classList.add("is-done")
    email.removeAttribute("aria-current")
    email.querySelector("span").replaceChildren(this.template("check"))
    document.querySelector('[data-ce-step="gym"]').setAttribute("aria-current", "step")

    const waiting = [...document.querySelectorAll("[data-ce-waiting]")]
    const done = [...this.template("done").childNodes]
    waiting[0].before(...done)
    waiting.forEach((node) => node.remove())
    const go = () => {
      this.stop()
      Turbo.visit(continueUrl)
    }
    done.find((node) => node.matches?.("[data-ce-continue]"))?.addEventListener("click", go)
    this.later(go, this.delayValue)
  }

  fly() {
    this.stage("sending")
    this.later(() => {
      if (this.phase === "waiting") this.stage("waiting")
    }, 1100)
  }

  stage(state) {
    this.element.replaceChildren(this.template(`stage-${state}`))
  }

  notice(kind) {
    document.querySelector("[data-ce-notice]")?.remove()
    if (kind) document.querySelector(".ce-actions").after(this.template(`notice-${kind}`))
  }

  startCountdown(seconds) {
    clearInterval(this.tickTimer)
    this.resendIn = Math.max(0, Math.ceil(seconds))
    this.renderResend()
    if (this.resendIn === 0) return
    this.tickTimer = setInterval(() => {
      this.resendIn = Math.max(0, this.resendIn - 1)
      this.renderResend()
      if (this.resendIn === 0) clearInterval(this.tickTimer)
    }, 1000)
  }

  // The resend button: the spinner while sending, else its icon; the
  // countdown while it runs, else the label.
  renderResend() {
    const button = this.resendButton
    if (!button?.isConnected) return
    button.disabled = this.resendIn > 0 || this.resending
    const icon = this.resending ? spinner(18, "confirm-email") : Object.assign(document.createElement("i"), { className: "bi bi-arrow-repeat" })
    if (!this.resending) {
      icon.setAttribute("_ngcontent-confirm-email", "")
      icon.setAttribute("aria-hidden", "true")
    }
    const text = this.resendIn > 0 ? this.labelsValue.resend_in.replace(/{{\s?seconds\s?}}/, String(this.resendIn)) : this.labelsValue.resend
    button.replaceChildren(icon, ` ${text} `)
  }

  template(name) {
    return document.querySelector(`template[data-ce="${name}"]`).content.cloneNode(true)
  }

  later(fn, ms) {
    this.timeouts.push(setTimeout(fn, ms))
  }

  stopListening() {
    clearInterval(this.pollTimer)
    window.removeEventListener("focus", this.onWake)
    document.removeEventListener("visibilitychange", this.onWake)
    this.channel?.close()
    this.channel = null
  }

  stop() {
    this.stopListening()
    clearInterval(this.tickTimer)
    this.timeouts.forEach(clearTimeout)
    this.timeouts = []
  }
}
