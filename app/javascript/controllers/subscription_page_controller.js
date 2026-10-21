import { Controller } from "@hotwired/stimulus"
import { csrfToken, interpolate, scoped, spinner } from "../lib/ng"
import { toast } from "../lib/toast"

// SubscriptionComponent's side panel: the billing period (re-pricing the
// plans), the plan picked, and what the call to action says for it — the
// plan in force, a request already sent, or a request to send (warned when
// it gives Pro up). The request is a dialog: a phone number Fitora calls
// back on (required, checked as isValidPhone checks it) and a note, sent as
// a support ticket.
const SCOPE = "subscription"

// isValidPhone (shared/utils/phone.ts).
export function isValidPhone(value) {
  const phone = (value ?? "").trim()
  if (!/^\(?\+?[\d\s().-]+$/.test(phone)) return false
  const digits = phone.replace(/\D/g, "").length
  return digits >= 8 && digits <= 15
}

export default class extends Controller {
  static targets = ["sent", "current", "warn", "request", "modal"]
  static values = { url: String, plans: Array, period: String, billed: String, losesPro: Boolean, phone: String, labels: Object }

  connect() {
    this.period = this.periodValue
    this.picked = null
    this.requested = []
  }

  get pickedPlan() {
    const key = this.picked ?? this.plansValue.find((p) => p.current)?.key ?? null
    return key ? this.plansValue.find((p) => p.key === key) ?? null : null
  }

  get pickIsCurrent() {
    const plan = this.pickedPlan
    if (!plan?.current) return false
    return (this.billedValue || this.period) === this.period
  }

  setPeriod(event) {
    this.period = event.currentTarget.dataset.period
    this.render()
  }

  pick(event) {
    this.picked = event.currentTarget.dataset.plan
    this.render()
  }

  render() {
    const labels = this.labelsValue
    this.element.querySelectorAll(".sub-toggle [data-period]").forEach((button) => {
      const on = button.dataset.period === this.period
      if (on) button.classList.add("is-active")
      else button.classList.remove("is-active")
      if (!button.classList.length) button.removeAttribute("class")
      button.setAttribute("aria-pressed", String(on))
    })
    const picked = this.pickedPlan
    this.element.querySelectorAll(".sub-opt").forEach((option) => {
      const on = option.dataset.plan === picked?.key
      option.classList.toggle("is-picked", on)
      option.setAttribute("aria-pressed", String(on))
      option.querySelector("[data-price]").textContent = labels.prices[option.dataset.plan][this.period]
      option.querySelector("[data-per]").textContent = this.period === "yearly" ? labels.per_year : labels.per_month
    })

    const change = this.element.querySelector(".sub-change")
    change.querySelectorAll("[data-cta]").forEach((node) => node.remove())
    const note = change.querySelector(":scope > .sub-change-note:last-child")
    const place = (node) => note.before(node)
    if (!picked) {
      const p = scoped(document.createElement("p"), SCOPE)
      p.className = "sub-change-note"
      p.dataset.cta = ""
      p.textContent = labels.pick_a_plan ?? ""
      return place(p)
    }
    if (this.requested.includes(`${picked.key}:${this.period}`)) return place(this.clone("sent"))
    if (this.pickIsCurrent) return place(this.clone("current"))
    if (picked.key === "starter" && this.losesProValue) place(this.clone("warn"))
    const button = this.clone("request")
    const switches = picked.current && !this.pickIsCurrent
    const text = switches
      ? (this.period === "yearly" ? labels.switch_yearly : labels.switch_monthly)
      : interpolate(labels.request_cta, { plan: labels.names[picked.key] })
    button.append(` ${text} `)
    place(button)
  }

  clone(name) {
    return this[`${name}Target`].content.firstElementChild.cloneNode(true)
  }

  // ---- the request ------------------------------------------------------------------

  openRequest() {
    this.requestPlan = this.pickedPlan
    this.requesting = false
    this.phoneTouched = false
    this.host = this.clone("modal")
    this.host.dataset.action += " subscription-request:open@window->modal#open modal:opened@window->subscription-page#fill"
    this.element.append(this.host)
    requestAnimationFrame(() => window.dispatchEvent(new CustomEvent("subscription-request:open")))
  }

  fill(event) {
    if (event.detail.name !== "subscription-request") return
    const panel = event.detail.panel
    const labels = this.labelsValue
    const plan = this.requestPlan
    const name = labels.names[plan.key]
    const title = interpolate(labels.request_title, { plan: name })
    panel.querySelector(".modal-panel-header h3").textContent = title
    panel.setAttribute("aria-label", title)
    const price = labels.prices[plan.key][this.period]
    panel.querySelector("[data-request-hint]").textContent = ` ${interpolate(labels.request_hint, { plan: name, price, period: this.period === "yearly" ? labels.per_year : labels.per_month })} `
    this.panel = panel
    this.phone = panel.querySelector("#upgrade-phone")
    this.note = panel.querySelector("#upgrade-note")
    this.phone.value = this.phoneValue
    this.phone.addEventListener("input", () => this.drawPhone())
    this.phone.addEventListener("blur", () => {
      this.phoneTouched = true
      this.drawPhone()
    })
    panel.querySelector("[data-request-cancel]").addEventListener("click", () => this.closeRequest())
    panel.querySelector("[data-request-send]").addEventListener("click", () => this.submitRequest())
  }

  // The field red and its message, once touched and wrong; the hint otherwise.
  drawPhone() {
    const invalid = this.phoneTouched && !isValidPhone(this.phone.value)
    this.phone.classList.toggle("is-invalid", invalid)
    this.phone.setAttribute("aria-invalid", String(invalid))
    const hint = this.panel.querySelector("#upgrade-phone-hint")
    const next = scoped(document.createElement("div"), SCOPE)
    next.id = "upgrade-phone-hint"
    if (invalid) {
      next.className = "invalid-feedback d-block"
      next.textContent = ` ${this.phone.value.trim() ? this.labelsValue.phone_invalid : this.labelsValue.phone_required} `
    } else {
      next.className = "form-text"
      next.textContent = this.labelsValue.phone_hint
    }
    hint.replaceWith(next)
  }

  closeRequest() {
    if (this.requesting) return
    window.dispatchEvent(new CustomEvent("subscription-request:close"))
  }

  // The dialog gone (closed, Escape, the backdrop): its host goes too, as
  // the component's @if takes the whole <app-modal> away.
  requestClosed() {
    this.host?.remove()
    this.host = null
  }

  async submitRequest() {
    const plan = this.requestPlan
    if (!plan || this.requesting) return
    this.phoneTouched = true
    this.drawPhone()
    if (!isValidPhone(this.phone.value)) return
    const labels = this.labelsValue
    const name = labels.names[plan.key]
    const period = this.period === "yearly" ? labels.plan_yearly : labels.plan_monthly
    const subject = interpolate(labels.subject, { plan: name, period })
    const body = interpolate(labels.body, { plan: name, period })
    const note = this.note.value.trim()

    this.setRequesting(true)
    const response = await fetch(this.urlValue, {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ subject, message: note ? `${body}\n\n${note}` : body, contact_phone: this.phone.value.trim() }),
    }).catch(() => null)
    this.setRequesting(false)
    if (response?.ok) {
      this.requested.push(`${plan.key}:${this.period}`)
      window.dispatchEvent(new CustomEvent("subscription-request:close"))
      this.render()
      return toast("success", labels.sent)
    }
    const payload = await response?.json().catch(() => ({}))
    toast("error", payload?.error ?? labels.error)
  }

  setRequesting(on) {
    this.requesting = on
    if (on) this.host.dataset.modalBusy = ""
    else delete this.host.dataset.modalBusy
    const [cancel, send] = this.panel.querySelectorAll(".d-flex.justify-content-end > button")
    cancel.disabled = on
    send.disabled = on
    const icon = send.firstElementChild
    icon.replaceWith(on ? spinner(16, SCOPE) : Object.assign(scoped(document.createElement("i"), SCOPE), { className: "bi bi-send-check" }))
  }
}
