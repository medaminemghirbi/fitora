import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { confirmAsk } from "../lib/confirm"
import { csrfToken, downloadBlob, interpolate, money, scoped } from "../lib/ng"
import { toast } from "../lib/toast"

// ClientProfileComponent's actions. Each write goes to the server, then
// load(): the file drawn again from what it now holds. The four dialogs are
// filled here when they open — a subscription (the formule's items, its
// price after the discount, collecting now), a booking (the day's sessions
// for an activity, how the seat is paid), a payment (what is owed, one line
// each), the health file.
const SCOPE = "client-profile"

// sellableItems (contract-type.model.ts): the formule's activities, then its packs.
function sellableItems(plan) {
  if (!plan) return []
  const activities = (plan.activity_prices ?? []).map((row) => ({
    kind: "activity", id: row.activity_id, key: `activity:${row.activity_id}`,
    label: row.activity_emoji ? `${row.activity_emoji} ${row.activity_name}` : row.activity_name, price: Number(row.price),
  }))
  const packs = (plan.pack_prices ?? []).map((row) => ({
    kind: "pack", id: row.pack_id, key: `pack:${row.pack_id}`,
    label: `${row.pack_name} (${row.activity_names.join(" + ")})`, price: Number(row.price),
  }))
  return [...activities, ...packs]
}

function sellableTarget(key) {
  if (!key) return {}
  const [kind, id] = key.split(":")
  return kind === "pack" ? { pack_id: id } : { activity_id: id }
}

export default class extends Controller {
  static targets = ["data", "noActivity"]
  static values = { url: String, paymentsUrl: String, attendanceUrl: String, contractsUrl: String, clientsUrl: String, plans: Array, dropIn: Boolean, today: String, labels: Object }

  connect() {
    this.read()
    this.filter = "all"
  }

  read() {
    this.profile = JSON.parse(this.dataTarget.textContent)
  }

  // load(): the file again, the activity filter kept.
  async load() {
    const response = await fetch(`${this.urlValue}?fragment=1`, { credentials: "same-origin", headers: { Accept: "text/html" } }).catch(() => null)
    if (!response?.ok) return
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    this.element.replaceChildren(fresh.content)
    this.read()
    if (this.filter !== "all") this.applyFilter()
  }

  // ---- what happened -------------------------------------------------------------

  setFilter(event) {
    this.filter = event.currentTarget.dataset.filter
    this.applyFilter()
  }

  applyFilter() {
    this.element.querySelectorAll(".prof-filter").forEach((b) => b.classList.toggle("is-active", b.dataset.filter === this.filter))
    const list = this.element.querySelector(".prof-timeline")
    this.allEntries ??= list ? [...list.children] : []
    if (list && !this.timeline) this.timeline = list
    const shown = this.allEntries.filter((li) => this.filter === "all" || li.dataset.stream === this.filter)
    const head = this.element.querySelector(".prof-main-head")
    head.parentElement.querySelector(":scope > app-empty-state")?.remove()
    if (shown.length === 0) {
      this.timeline?.remove()
      head.after(this.noActivityTarget.content.cloneNode(true))
      return
    }
    this.timeline.replaceChildren(...shown)
    if (!this.timeline.isConnected) head.after(this.timeline)
  }

  // ---- the desk's actions ------------------------------------------------------------

  async checkIn() {
    const today = this.todayValue
    const booking = this.profile.bookings.find((b) => b.status === "confirmed" && b.starts_at.slice(0, 10) === today)
    if (!booking) return toast("info", this.labelsValue.no_session_today)
    const result = await this.request("POST", this.attendanceUrlValue, { booking_id: booking.id, status: "present" })
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    toast("success", this.labelsValue.present)
    this.load()
  }

  async invite() {
    const client = this.profile.client
    if (!client.email) return
    const ok = await confirmAsk({ title: this.labelsValue.invite_title, body: interpolate(this.labelsValue.invite_body, { email: client.email }) })
    if (!ok) return
    const result = await this.request("POST", `${this.urlValue}/invite`)
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    toast("success", interpolate(this.labelsValue.invite_sent, { email: client.email }))
    this.load()
  }

  async remove() {
    const client = this.profile.client
    const ok = await confirmAsk({
      title: interpolate(this.labelsValue.remove_title, { name: client.full_name }), body: this.labelsValue.remove_body,
      confirmLabel: this.labelsValue.remove, danger: true,
    })
    if (!ok) return
    const result = await this.request("DELETE", this.urlValue)
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    // The toast travels with the members page (the server's flash).
    Turbo.visit(this.clientsUrlValue)
  }

  async togglePause(event) {
    const button = event.currentTarget
    const id = button.dataset.contractId
    const pausing = button.dataset.paused !== "true"
    if (pausing) {
      const ok = await confirmAsk({ title: this.labelsValue.pause_title, body: interpolate(this.labelsValue.pause_body, { name: this.profile.client.full_name }) })
      if (!ok) return
    }
    const result = await this.request("POST", `${this.contractsUrlValue}/${id}/${pausing ? "pause" : "resume"}`)
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    toast("success", pausing ? this.labelsValue.paused_done : this.labelsValue.resumed_done)
    this.load()
  }

  async download(event) {
    const button = event.currentTarget
    const response = await fetch(button.dataset.url, { credentials: "same-origin" }).catch(() => null)
    if (!response?.ok) return toast("error", this.labelsValue.error)
    downloadBlob(await response.blob(), button.dataset.filename)
  }

  // ---- the dialogs ----------------------------------------------------------------

  openContract() {
    window.dispatchEvent(new CustomEvent("profile-contract:open"))
  }

  openBooking() {
    window.dispatchEvent(new CustomEvent("profile-booking:open"))
  }

  openPayment() {
    window.dispatchEvent(new CustomEvent("profile-payment:open"))
  }

  openHealth() {
    window.dispatchEvent(new CustomEvent("profile-health:open"))
  }

  fill(event) {
    const { name, panel } = event.detail
    this.saving = false
    if (name === "profile-contract") this.fillContract(panel)
    else if (name === "profile-booking") this.fillBooking(panel)
    else if (name === "profile-payment") this.fillPayment(panel)
    else if (name === "profile-health") this.fillHealth(panel)
  }

  // ---- a subscription ----------------------------------------------------------------

  fillContract(panel) {
    const form = panel.querySelector('[data-profile-form="contract"]')
    const f = form.elements
    f.starts_on.value = this.todayValue
    const extras = form.querySelector("template[data-plan-extras]").content
    this.contract = {
      form, panel,
      noPrice: extras.querySelector("[data-no-price]"), total: extras.querySelector("[data-total]"),
      collect: extras.querySelector("[data-collect]"), hint: extras.querySelector("[data-collect-hint]"),
    }
    this.contract.collect.querySelector("input").addEventListener("change", () => this.drawContract())
    f.contract_type_id.addEventListener("change", () => {
      // A new formule may not sell what was picked; when it sells one thing, that is the answer.
      const items = sellableItems(this.plan)
      if (!items.some((i) => i.key === f.namedItem("item").value)) this.chosenItem = items.length === 1 ? items[0].key : ""
      this.drawItems()
      this.drawContract()
    })
    // namedItem: "item" is also HTMLFormControlsCollection's own method.
    f.namedItem("item").addEventListener("change", () => {
      this.chosenItem = f.namedItem("item").value
      this.drawContract()
    })
    f.discount.addEventListener("input", () => this.drawContract())
    form.addEventListener("submit", (e) => {
      e.preventDefault()
      this.submitContract()
    })
    this.chosenItem = ""
  }

  get plan() {
    return this.plansValue.find((p) => p.id === this.contract?.form.elements.contract_type_id.value) ?? null
  }

  // The item list: "—" (or "pick a formule first"), the activities, then the packs.
  drawItems() {
    const select = this.contract.form.elements.namedItem("item")
    const plan = this.plan
    const items = sellableItems(plan)
    const option = (value, text, disabled = false) => {
      const o = scoped(document.createElement("option"), SCOPE)
      o.value = value
      o.textContent = text
      o.disabled = disabled
      return o
    }
    const first = option("", plan ? "—" : this.labelsValue.pick_plan_first, true)
    const activities = select.querySelector("optgroup")
    activities.replaceChildren(...items.filter((i) => i.kind === "activity").map((i) => option(i.key, i.label)))
    const children = [first, activities]
    if (plan?.pack_prices?.length) {
      const packs = scoped(document.createElement("optgroup"), SCOPE)
      packs.label = this.labelsValue.packs
      packs.append(...items.filter((i) => i.kind === "pack").map((i) => option(i.key, i.label)))
      children.push(packs)
    }
    select.replaceChildren(...children)
    select.value = this.chosenItem
    if (select.value !== this.chosenItem) select.value = ""
  }

  get price() {
    return sellableItems(this.plan).find((i) => i.key === this.chosenItem)?.price ?? null
  }

  get total() {
    const price = this.price
    if (price === null) return 0
    return Math.max(0, price - (Number(this.contract.form.elements.discount.value) || 0))
  }

  // Under the dates: nothing until a formule is picked; then the missing
  // price, or the total and "collect now" (with what it records).
  drawContract() {
    const { form, noPrice, total, collect, hint } = this.contract
    const anchor = form.querySelector(":scope > .row")
    for (const node of [noPrice, total, collect, hint]) node.remove()
    const plan = this.plan
    const save = form.querySelector("[data-save]")
    save.disabled = this.saving || this.price === null
    if (!plan) return
    if (this.price === null) return anchor.after(noPrice)
    const symbol = this.labelsValue.symbols[plan.currency] ?? plan.currency
    total.querySelector("strong").textContent = money(this.total, symbol)
    anchor.after(total, collect)
    if (collect.querySelector("input").checked) {
      hint.textContent = ` ${interpolate(this.labelsValue.collect_hint, { amount: money(this.total, symbol) })} `
      collect.append(hint)
    }
  }

  async submitContract() {
    const { form, panel } = this.contract
    const f = form.elements
    if (!f.contract_type_id.value || !this.chosenItem || !f.starts_on.value || this.saving) return
    const collect = this.contract.collect.querySelector("input").checked
    await this.save(panel, form, "profile-contract", "POST", `${this.urlValue}/contracts`, {
      contract_type_id: f.contract_type_id.value, ...sellableTarget(this.chosenItem), starts_on: f.starts_on.value,
      discount: Number(f.discount.value) || 0, collect_payment: collect || undefined, payment_method: collect ? "cash" : undefined,
    }, this.labelsValue.save, this.labelsValue.abo_create)
  }

  // ---- a booking ----------------------------------------------------------------------

  fillBooking(panel) {
    const form = panel.querySelector('[data-profile-form="booking"]')
    const f = form.elements
    f.date.value = this.todayValue
    const contract = this.profile.current_contract
    const covered = Boolean(contract) && !contract.paused
    const kind = covered || !this.dropInValue ? "contract" : "trial"
    if (f.kind) {
      for (const radio of form.querySelectorAll('input[name="kind"]')) radio.checked = radio.value === kind
      this.drawKindHint(form)
      form.querySelectorAll('input[name="kind"]').forEach((radio) => radio.addEventListener("change", () => this.drawKindHint(form)))
    }
    this.kind = kind
    this.noSessions = form.querySelector("[data-no-sessions]")
    f.activity_id.addEventListener("change", () => this.loadSessions(form))
    // The form control's own event (DefaultValueAccessor): `input`, so the
    // blur that follows a typed date does not drop the session chosen since.
    f.date.addEventListener("input", () => this.loadSessions(form))
    form.addEventListener("submit", (e) => {
      e.preventDefault()
      this.submitBooking(panel, form)
    })
  }

  drawKindHint(form) {
    this.kind = form.querySelector('input[name="kind"]:checked')?.value ?? "contract"
    form.querySelector("[data-kind-hint]").textContent = this.labelsValue.kind_hints[this.kind]
  }

  // onBookingFiltersChange: the session forgotten at once; the day's
  // sessions for the activity, when both are chosen, in place of the list
  // shown until they arrive. Only the latest request's answer is used: the
  // activity then the date send two, and an earlier day's list must not
  // land after (or beside) the day asked for.
  async loadSessions(form) {
    const f = form.elements
    const select = f.session_id
    const placeholder = select.querySelector("option")
    const seq = (this.sessionsSeq = (this.sessionsSeq ?? 0) + 1)
    select.value = ""
    const show = (empty) => {
      if (empty && !this.noSessions.isConnected) select.after(this.noSessions)
      if (!empty) this.noSessions.remove()
    }
    if (!f.activity_id.value || !f.date.value) {
      select.replaceChildren(placeholder)
      return show(true)
    }
    const query = new URLSearchParams({ activity_id: f.activity_id.value, date: f.date.value })
    const response = await fetch(`${this.urlValue}/sessions?${query}`, { credentials: "same-origin", headers: { Accept: "text/html" } }).catch(() => null)
    if (!response?.ok || seq !== this.sessionsSeq) return
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    if (seq !== this.sessionsSeq) return
    const options = [...fresh.content.querySelectorAll("option")]
    select.replaceChildren(placeholder, ...options)
    select.value = ""
    show(options.length === 0)
  }

  async submitBooking(panel, form) {
    const f = form.elements
    if (!f.activity_id.value || !f.date.value || !f.session_id.value || this.saving) return
    await this.save(panel, form, "profile-booking", "POST", `${this.urlValue}/bookings`, {
      session_id: f.session_id.value, ...(this.kind === "trial" ? { trial: true } : {}), ...(this.kind === "drop_in" ? { drop_in: true } : {}),
    }, this.labelsValue.save, this.labelsValue.save)
  }

  // ---- a payment ----------------------------------------------------------------------

  fillPayment(panel) {
    const form = panel.querySelector('[data-profile-form="payment"]')
    const select = form.elements.payable_key
    const contracts = this.profile.contracts.filter((c) => Number(c.amount_due) > 0)
      .map((c) => ({ key: `contract:${c.id}`, label: `${this.labelsValue.contract_label} — ${c.plan}`, due: Number(c.amount_due) }))
    const bookings = this.profile.bookings.filter((b) => b.payment_status !== "paid" && b.amount > 0)
      .map((b) => ({ key: `booking:${b.id}`, label: `${this.labelsValue.booking_label} — ${b.activity}`, due: b.amount }))
    const options = [...contracts, ...bookings]
    for (const o of options) {
      const option = scoped(document.createElement("option"), SCOPE)
      option.value = o.key
      option.textContent = `${o.label} (${o.due})`
      select.append(option)
    }
    if (options.length > 0) form.querySelector("[data-nothing-outstanding]").remove()
    const save = form.querySelector("[data-save]")
    save.disabled = options.length === 0
    form.addEventListener("submit", (e) => {
      e.preventDefault()
      if (!select.value || this.saving) return
      const [kind, id] = select.value.split(":")
      this.save(panel, form, "profile-payment", "POST", this.paymentsUrlValue, {
        client_id: this.profile.client.id, payment_method: "cash",
        contract_id: kind === "contract" ? id : undefined, booking_id: kind === "booking" ? id : undefined,
      }, this.labelsValue.save, ` ${this.labelsValue.save} `)
    })
  }

  // ---- the health file ------------------------------------------------------------------

  fillHealth(panel) {
    const form = panel.querySelector('[data-profile-form="health"]')
    const f = form.elements
    f.health_notes.value = this.profile.client.health_notes ?? ""
    f.waiver_signed_on.value = this.profile.client.waiver_signed_on ?? ""
    form.querySelector("[data-waiver-today]").addEventListener("click", () => (f.waiver_signed_on.value = this.todayValue))
    form.addEventListener("submit", (e) => {
      e.preventDefault()
      if (this.saving) return
      this.save(panel, form, "profile-health", "PATCH", this.urlValue, {
        client: { health_notes: f.health_notes.value.trim() || null, waiver_signed_on: f.waiver_signed_on.value || null },
      }, this.labelsValue.saved, this.labelsValue.save)
    })
  }

  // ---- shared -----------------------------------------------------------------------------

  // A dialog's save: busy, then closed with a toast and load(); or the API's
  // message first in the dialog (formError).
  async save(panel, form, name, method, url, body, done, idleLabel) {
    const button = form.querySelector("[data-save]")
    this.saving = true
    button.disabled = true
    button.textContent = this.labelsValue.saving
    this.showError(panel, null)
    const result = await this.request(method, url, body)
    this.saving = false
    if (result.ok) {
      window.dispatchEvent(new CustomEvent(`${name}:close`))
      toast("success", done)
      return this.load()
    }
    button.disabled = false
    button.textContent = idleLabel
    if (name === "profile-contract") this.drawContract()
    this.showError(panel, result.error ?? this.labelsValue.error)
  }

  showError(panel, message) {
    const body = panel.querySelector(".modal-panel-body")
    body.querySelector(":scope > .alert-danger")?.remove()
    if (!message) return
    const alert = scoped(document.createElement("div"), SCOPE)
    alert.className = "alert alert-danger"
    alert.textContent = message
    body.prepend(alert)
  }

  async request(method, url, body) {
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
