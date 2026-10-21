import ServerListController from "./server_list_controller"
import { confirmAsk } from "../lib/confirm"
import { send } from "../lib/crud"
import { downloadBlob, interpolate } from "../lib/ng"
import { toast } from "../lib/toast"

// ContractsComponent: the list (ServerListController) plus what its signals
// redraw at once — the chips, "reset", the active plan tab, the checked pill
// — and what the row does: settle in cash, renew (the dialog, onto the same
// formule or another), pause or resume, and the two documents.
export default class extends ServerListController {
  static targets = [...ServerListController.targets, "rail"]
  static values = { ...ServerListController.values, labels: Object, plans: Array, currency: String, symbols: Object, catalogue: String }

  // resetFilters(): the status, the plan and the search — the payment filter
  // stays (K-06).
  reset() {
    this.filters.status = ""
    this.filters.contract_type_id = ""
    this.filters.q = ""
    if (this.hasSearchTarget) this.searchTarget.value = ""
    this.reload()
  }

  renderFilters() {
    const f = this.filters
    const labels = this.labelsValue
    const chips = []
    if (f.q) chips.push([`« ${f.q} »`, "q"])
    if (f.status && labels.statuses[f.status]) chips.push([labels.statuses[f.status], "status"])
    if (f.payment) chips.push([labels.unpaid, "payment"])
    if (f.contract_type_id && labels.plans[f.contract_type_id]) chips.push([labels.plans[f.contract_type_id], "contract_type_id"])

    this.markTab("#ct-tabs", f.contract_type_id)
    this.checkPill("contract-status", f.status)
    // hasFilters(): "reset" after the pills while one is set.
    this.drawReset(this.railTarget, Boolean(f.status || f.contract_type_id || f.q), "contracts-reset")
    this.drawChips(chips)
  }

  // ---- row actions ---------------------------------------------------------
  // One at a time: while any runs, every row's buttons are disabled (rowBusy).

  get busy() {
    return this.busyId !== undefined && this.busyId !== null
  }

  setBusy(id) {
    this.busyId = id
    document.querySelectorAll("[data-row-busy]").forEach((button) => (button.disabled = this.busy))
    this.renderRenew()
  }

  contractOf(event) {
    return JSON.parse(event.currentTarget.closest("tr").dataset.contract)
  }

  // collect(): the whole amount, in cash.
  async collect(event) {
    if (this.busy) return
    const contract = this.contractOf(event)
    this.setBusy(contract.id)
    const result = await send("POST", `${this.urlValue}/${contract.id}/collect`)
    this.setBusy(null)
    if (!result.ok) return toast("error", result.error || this.labelsValue.error)
    toast("success", this.labelsValue.recorded)
    this.load()
  }

  // togglePause(): pausing is confirmed first; resuming is not.
  async togglePause(event) {
    if (this.busy) return
    const contract = this.contractOf(event)
    const pausing = !contract.paused
    if (pausing) {
      const ok = await confirmAsk({ title: this.labelsValue.pause_title, body: interpolate(this.labelsValue.pause_body, { name: contract.name }) })
      if (!ok) return
    }
    this.setBusy(contract.id)
    const result = await send("POST", `${this.urlValue}/${contract.id}/${pausing ? "pause" : "resume"}`)
    this.setBusy(null)
    if (!result.ok) return toast("error", result.error || this.labelsValue.error)
    toast("success", pausing ? this.labelsValue.paused_done : this.labelsValue.resumed_done)
    this.load()
  }

  downloadAgreement(event) {
    const contract = this.contractOf(event)
    this.download(`${this.urlValue}/${contract.id}/agreement`, `contrat-${contract.ref}.pdf`)
  }

  downloadInvoice(event) {
    const contract = this.contractOf(event)
    this.download(`${this.urlValue}/${contract.id}/receipt`, `facture-${contract.ref}.pdf`)
  }

  async download(url, filename) {
    const response = await fetch(url, { credentials: "same-origin" }).catch(() => null)
    if (!response?.ok) return toast("error", this.labelsValue.error)
    downloadBlob(await response.blob(), filename)
  }

  // ---- renewing --------------------------------------------------------------
  // A renewal is a new contract, so it can be for another formule: the
  // dialog opens on the one the member is on, and the desk may pick another.

  renew(event) {
    if (this.busy) return
    this.renewing = this.contractOf(event)
    this.renewPlanId = this.renewing.plan_id
    this.renewItem = this.renewing.item
    window.dispatchEvent(new CustomEvent("contracts-renew:open"))
  }

  get renewPlan() {
    return this.plansValue.find((p) => p.id === this.renewPlanId) ?? null
  }

  // sellableItems(plan): its activities, then its packs.
  sellableItems(plan) {
    if (!plan) return []
    const activities = (plan.activity_prices ?? []).map((row) => ({
      key: `activity:${row.activity_id}`,
      label: row.activity_emoji ? `${row.activity_emoji} ${row.activity_name}` : row.activity_name,
      price: Number(row.price),
    }))
    const packs = (plan.pack_prices ?? []).map((row) => ({
      key: `pack:${row.pack_id}`,
      label: `${row.pack_name} (${row.activity_names.join(" + ")})`,
      price: Number(row.price),
    }))
    return [...activities, ...packs]
  }

  get renewPrice() {
    return this.sellableItems(this.renewPlan).find((i) => i.key === this.renewItem)?.price ?? null
  }

  get renewSameFormule() {
    return Boolean(this.renewing) && this.renewing.plan_id === this.renewPlanId && this.renewItem === this.renewing.item
  }

  get renewBlocked() {
    return !this.renewSameFormule && this.renewPrice === null
  }

  // modal:opened — the dialog's body for the contract it opens on.
  fillRenew(event) {
    if (event.detail.name !== "contracts-renew") return
    const labels = this.labelsValue
    const contract = this.renewing
    const body = event.detail.panel.querySelector(".modal-panel-body")

    const intro = document.createElement("p")
    intro.className = "fx-muted"
    intro.style.fontSize = "0.875rem"
    intro.textContent = ` ${interpolate(labels.renew_body, { name: contract.name })} `

    const planSelect = this.select("rn-plan")
    for (const plan of this.plansValue) {
      planSelect.append(new Option(`${plan.name} — ${interpolate(labels.periods[plan.billing_period] ?? `contract_types.period_${plan.billing_period}`, { days: plan.validity_days })}`, plan.id))
    }
    planSelect.value = this.renewPlanId
    planSelect.addEventListener("change", () => this.renewPlanChanged(planSelect.value))
    const planField = this.field("rn-plan", `${labels.formula} *`, planSelect)

    this.itemSelect = this.select("rn-item")
    this.itemSelect.addEventListener("change", () => {
      this.renewItem = this.itemSelect.value
      this.renderRenew()
    })
    this.itemField = this.field("rn-item", `${labels.item} *`, this.itemSelect)

    this.hint = document.createElement("p")
    this.hint.className = "fx-muted"
    this.hint.style.fontSize = "0.8125rem"
    this.hint.textContent = labels.other_hint

    this.blocked = document.createElement("div")
    this.blocked.className = "alert alert-warning"
    const link = document.createElement("a")
    link.href = this.catalogueValue
    link.textContent = labels.no_price_link
    this.blocked.append(` ${labels.no_price} `, link)

    this.totalLine = document.createElement("div")
    this.totalLine.className = "abo-total-line mb-3"
    this.totalAmount = document.createElement("strong")
    const totalLabel = document.createElement("span")
    totalLabel.textContent = labels.total
    this.totalLine.append(totalLabel, this.totalAmount)

    this.buttons = document.createElement("div")
    this.buttons.className = "d-flex justify-content-end gap-2 mt-4"
    const cancel = document.createElement("button")
    cancel.type = "button"
    cancel.className = "btn btn-outline-secondary"
    cancel.textContent = labels.cancel
    cancel.addEventListener("click", () => window.dispatchEvent(new CustomEvent("contracts-renew:close")))
    this.confirmButton = document.createElement("button")
    this.confirmButton.type = "button"
    this.confirmButton.className = "btn btn-primary"
    this.confirmButton.textContent = ` ${labels.renew} `
    this.confirmButton.addEventListener("click", () => this.confirmRenew())
    this.buttons.append(cancel, this.confirmButton)

    this.renewBody = body
    body.replaceChildren(intro, planField)
    this.fillItems()
    this.renderRenew()
  }

  renewPlanChanged(planId) {
    this.renewPlanId = planId
    const items = this.sellableItems(this.renewPlan)
    // Keep the activity or pack when the new formule sells it too.
    if (!items.some((i) => i.key === this.renewItem)) this.renewItem = items.length === 1 ? items[0].key : null
    this.fillItems()
    this.renderRenew()
  }

  fillItems() {
    const placeholder = new Option("—", "")
    placeholder.disabled = true
    this.itemSelect.replaceChildren(placeholder, ...this.sellableItems(this.renewPlan).map((i) => new Option(i.label, i.key)))
    // [ngValue]: null picks the "—" option; a value no option holds, none.
    if (this.renewItem === null) this.itemSelect.value = ""
    else {
      this.itemSelect.value = this.renewItem
      if (this.itemSelect.value !== this.renewItem) this.itemSelect.selectedIndex = -1
    }
  }

  // The @if blocks of the dialog, in their order, each there or not.
  renderRenew() {
    const body = this.renewBody
    if (!body?.isConnected || !this.renewing) return
    const same = this.renewSameFormule
    const price = this.renewPrice
    const shown = [
      [this.itemField, !(same && this.renewing.all_access)],
      [this.hint, !same],
      [this.blocked, this.renewBlocked],
      [this.totalLine, !this.renewBlocked && price !== null],
      [this.buttons, true],
    ]
    let previous = body.querySelector(".mb-3") // the plan field
    for (const [node, show] of shown) {
      if (show) {
        if (previous.nextSibling !== node) previous.after(node)
        previous = node
      } else {
        node.remove()
      }
    }
    if (price !== null) this.totalAmount.textContent = this.money(price, this.renewPlan?.currency ?? this.currencyValue)
    this.confirmButton.disabled = this.busy || this.renewBlocked
  }

  async confirmRenew() {
    const contract = this.renewing
    if (!contract || this.busy || this.renewBlocked) return
    const payload = this.renewSameFormule ? {} : { contract_type_id: this.renewPlanId, ...this.target(this.renewItem) }
    this.setBusy(contract.id)
    const result = await send("POST", `${this.urlValue}/${contract.id}/renew`, payload)
    this.setBusy(null)
    if (!result.ok) return toast("error", result.error || this.labelsValue.error)
    window.dispatchEvent(new CustomEvent("contracts-renew:close"))
    toast("success", this.labelsValue.renewed)
    this.load()
  }

  // sellableTarget(key): activity_id or pack_id.
  target(key) {
    if (!key) return {}
    const [kind, id] = key.split(":")
    return kind === "pack" ? { pack_id: id } : { activity_id: id }
  }

  // MoneyPipe, with the currency's symbol from the plans' own catalogue.
  money(amount, currency) {
    const formatted = Number.isFinite(amount) ? amount.toFixed(2).replace(/\.00$/, "") : amount
    return `${formatted} ${this.symbolsValue[currency] ?? currency}`
  }

  select(id) {
    const select = document.createElement("select")
    select.id = id
    select.className = "form-select"
    return select
  }

  field(id, text, control) {
    const div = document.createElement("div")
    div.className = "mb-3"
    const label = document.createElement("label")
    label.htmlFor = id
    label.textContent = text
    div.append(label, control)
    return div
  }
}
