import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { confirmAsk } from "../lib/confirm"
import { csrfToken } from "../lib/ng"
import { toast } from "../lib/toast"

// The door (Web::Admin::EntriesController). A USB or Bluetooth scanner types
// the card's number and Enter, as a keyboard does, so a scan is a submit:
// the verdict comes at once and, when it is green and the desk asked for it,
// the visit is recorded without a click. Typing a name lists who it matches
// instead. Where the browser can read QR codes itself (BarcodeDetector), the
// device's camera can scan the card too.
const AUTO_KEY = "fitora.entries.auto"
const SEARCH_DELAY = 250

export default class extends Controller {
  static targets = ["query", "result", "idle", "day", "auto", "camera", "video", "cameraButton", "admit"]
  static values = { url: String, date: String, member: String, labels: Object }

  connect() {
    if (this.hasAutoTarget) this.autoTarget.checked = this.readAuto()
    if (this.hasCameraButtonTarget && "BarcodeDetector" in window && navigator.mediaDevices?.getUserMedia) {
      this.cameraButtonTarget.hidden = false
    }
    if (this.memberValue && this.hasResultTarget) this.check(this.memberValue)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.closeCamera()
  }

  // ---- finding the member ------------------------------------------------------------

  search() {
    clearTimeout(this.timer)
    const query = this.queryTarget.value.trim()
    if (query === "") return this.showIdle()
    this.timer = setTimeout(() => this.lookup(query, { scanned: false }), SEARCH_DELAY)
  }

  // Enter: a scanner's end of line, or the desk done typing a number.
  submit(event) {
    event.preventDefault()
    clearTimeout(this.timer)
    const query = this.queryTarget.value.trim()
    if (query === "") return
    const single = this.resultTarget.querySelectorAll("[data-action='entries#pick']")
    if (single.length === 1 && !/^\d+$/.test(query)) return this.check(single[0].dataset.clientId)
    this.lookup(query, { scanned: true })
  }

  pick(event) {
    this.check(event.currentTarget.dataset.clientId)
  }

  async lookup(query, { scanned }) {
    const html = await this.fetchHtml(`${this.urlValue}/lookup?q=${encodeURIComponent(query)}`)
    if (html === null || query !== this.queryTarget.value.trim()) return
    this.resultTarget.innerHTML = html
    if (scanned) this.autoAdmit()
  }

  async check(clientId) {
    const html = await this.fetchHtml(`${this.urlValue}/check/${clientId}`)
    if (html === null) return
    this.resultTarget.innerHTML = html
    if (this.hasAdmitTarget) this.admitTarget.focus()
  }

  // Green, and the desk asked for it: in, without a click. Amber and red
  // always wait for someone to read them.
  autoAdmit() {
    const verdict = this.resultTarget.querySelector("[data-entries-verdict]")
    if (!verdict) return
    if (verdict.dataset.tone === "green" && this.hasAutoTarget && this.autoTarget.checked) {
      this.record(verdict.dataset.clientId, false)
    } else if (this.hasAdmitTarget) {
      this.admitTarget.focus()
    }
  }

  // ---- letting them in ---------------------------------------------------------------

  async admit(event) {
    const verdict = event.currentTarget.closest("[data-entries-verdict]")
    const force = event.currentTarget.dataset.force === "true"
    if (force) {
      const ok = await confirmAsk({ title: this.labelsValue.force_title, body: this.labelsValue.force_body, confirmLabel: this.labelsValue.force_confirm, danger: true })
      if (!ok) return
    }
    this.record(verdict.dataset.clientId, force)
  }

  async record(clientId, force) {
    const result = await this.send("POST", this.urlValue, { client_id: clientId, force })
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    toast(force ? "warning" : "success", force ? this.labelsValue.admitted_forced : this.labelsValue.admitted)
    this.queryTarget.value = ""
    this.showIdle()
    this.queryTarget.focus()
    this.reloadDay()
  }

  async undo(event) {
    const ok = await confirmAsk({ title: this.labelsValue.undo_title, body: this.labelsValue.undo_body, confirmLabel: this.labelsValue.undo_confirm, danger: true })
    if (!ok) return
    const result = await this.send("DELETE", `${this.urlValue}/${event.currentTarget.dataset.visitId}`)
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    toast("success", this.labelsValue.undone)
    this.reloadDay()
  }

  async reloadDay() {
    const html = await this.fetchHtml(`${this.urlValue}?fragment=day&date=${this.dateValue}`)
    if (html !== null) this.dayTarget.innerHTML = html
  }

  changeDate(event) {
    if (event.currentTarget.value) Turbo.visit(`${this.urlValue}?date=${event.currentTarget.value}`)
  }

  toggleAuto() {
    try { localStorage.setItem(AUTO_KEY, this.autoTarget.checked ? "1" : "0") } catch { /* private mode */ }
  }

  readAuto() {
    try { return localStorage.getItem(AUTO_KEY) !== "0" } catch { return true }
  }

  showIdle() {
    if (this.hasIdleTarget && this.hasResultTarget) this.resultTarget.replaceChildren(this.idleTarget.content.cloneNode(true))
  }

  // ---- the camera ----------------------------------------------------------------------

  async openCamera() {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false })
    } catch {
      return toast("error", this.labelsValue.camera_error)
    }
    this.cameraTarget.hidden = false
    this.videoTarget.srcObject = this.stream
    await this.videoTarget.play().catch(() => {})
    const detector = new window.BarcodeDetector({ formats: ["qr_code", "code_128", "ean_13"] })
    const scan = async () => {
      if (!this.stream) return
      const codes = await detector.detect(this.videoTarget).catch(() => [])
      if (codes.length > 0) {
        this.closeCamera()
        this.queryTarget.value = codes[0].rawValue
        return this.lookup(codes[0].rawValue.trim(), { scanned: true })
      }
      this.scanTimer = setTimeout(scan, 250)
    }
    scan()
  }

  closeCamera() {
    clearTimeout(this.scanTimer)
    this.stream?.getTracks().forEach((track) => track.stop())
    this.stream = null
    if (this.hasCameraTarget) this.cameraTarget.hidden = true
  }

  // ---- the server ------------------------------------------------------------------------

  async fetchHtml(url) {
    const response = await fetch(url, { credentials: "same-origin", headers: { Accept: "text/html" } }).catch(() => null)
    if (!response?.ok) {
      toast("error", this.labelsValue.error)
      return null
    }
    return response.text()
  }

  async send(method, url, body) {
    const response = await fetch(url, {
      method, credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: body === undefined ? undefined : JSON.stringify(body),
    }).catch(() => null)
    if (!response) return { ok: false, error: null }
    if (response.ok) return { ok: true }
    const payload = await response.json().catch(() => ({}))
    return { ok: false, error: payload.error ?? null }
  }
}
