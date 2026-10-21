import ServerListController from "./server_list_controller"
import { confirmAsk } from "../lib/confirm"
import { send, showFormError } from "../lib/crud"
import { toast } from "../lib/toast"

// AdminPaymentsComponent: the list (ServerListController) plus what its
// signals redraw at once — the chips, "reset", the active method tab, the
// checked pill — the refund (the admin's, confirmed first), and the record
// dialog: find the member, pick what they owe, take it in cash.
export default class extends ServerListController {
  static targets = [...ServerListController.targets, "rail"]
  static values = { ...ServerListController.values, labels: Object, open: Boolean }

  connect() {
    super.connect()
    // ?action=new: the rail's "+" opens the dialog on arrival.
    if (this.openValue) requestAnimationFrame(() => this.openRecord())
  }

  renderFilters() {
    const f = this.filters
    const labels = this.labelsValue
    const chips = []
    if (f.q) chips.push([`« ${f.q} »`, "q"])
    if (f.status && labels.statuses[f.status]) chips.push([labels.statuses[f.status], "status"])
    if (f.payment_method && labels.methods[f.payment_method]) chips.push([labels.methods[f.payment_method], "payment_method"])

    this.markTab("#pay-tabs", f.payment_method)
    this.checkPill("payment-status", f.status)
    this.drawReset(this.railTarget, Boolean(f.q || f.status || f.payment_method), "payments-reset")
    this.drawChips(chips)
  }

  async refund(event) {
    const id = event.currentTarget.closest("tr").dataset.paymentId
    const ok = await confirmAsk({ title: this.labelsValue.refund_title, body: this.labelsValue.refund_body, danger: true })
    if (!ok) return
    const result = await send("POST", `${this.urlValue}/${id}/refund`)
    if (!result.ok) return toast("error", result.error || this.labelsValue.error)
    toast("success", this.labelsValue.refunded)
    this.load()
  }

  // ---- the record dialog -----------------------------------------------------

  openRecord() {
    this.client = null
    this.payables = []
    window.dispatchEvent(new CustomEvent("payments-record:open"))
  }

  // modal:opened — the client search, fresh.
  fillRecord(event) {
    if (event.detail.name !== "payments-record") return
    this.panel = event.detail.panel
    this.searchBox = this.panel.querySelector("[data-client-search]")
    this.searchBox.addEventListener("input", () => this.searchClients(this.searchBox.value))
    this.form = null
  }

  // searchClients(): from two letters, each keystroke asks again.
  async searchClients(term) {
    const id = (this.clientRequest = (this.clientRequest ?? 0) + 1)
    if (term.trim().length < 2) return this.showResults([])
    const response = await fetch(`${this.urlValue}/clients?search=${encodeURIComponent(term)}`, { headers: { Accept: "application/json" }, credentials: "same-origin" }).catch(() => null)
    if (!response?.ok || id !== this.clientRequest) return
    this.showResults((await response.json()).clients)
  }

  showResults(clients) {
    const field = this.searchBox.closest(".mb-3")
    field.querySelector(".search-results-dropdown")?.remove()
    if (!clients.length) return
    const list = document.createElement("div")
    list.className = "search-results-dropdown"
    for (const client of clients) {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "search-result-item"
      const phone = document.createElement("span")
      phone.className = "fx-muted"
      phone.dir = "ltr"
      phone.textContent = client.phone ?? ""
      button.append(` ${client.full_name} `, phone)
      button.addEventListener("click", () => this.selectClient(client))
      list.append(button)
    }
    field.append(list)
  }

  async selectClient(client) {
    this.clientRequest = (this.clientRequest ?? 0) + 1
    this.showResults([])
    this.searchBox.value = client.full_name
    const response = await fetch(`${this.urlValue}/payables?client_id=${encodeURIComponent(client.id)}`, { headers: { Accept: "application/json" }, credentials: "same-origin" }).catch(() => null)
    if (!response?.ok) return
    const answer = await response.json()
    this.client = answer.client
    this.payables = answer.payables
    this.showForm()
  }

  // @if (selectedClient()): the form, its options the client's payables.
  showForm() {
    if (!this.form) {
      const fragment = document.getElementById("pay-record-form").content.cloneNode(true)
      this.form = fragment.querySelector("form")
      this.nothing = fragment.querySelector("[data-nothing-outstanding]")
      this.form.elements.amount.value = "0"
      this.form.elements.payable_key.value = ""
      this.form.elements.payable_key.addEventListener("change", () => this.payableChanged())
      this.form.addEventListener("submit", (event) => this.submitRecord(event))
      this.panel.querySelector(".modal-panel-body").append(this.form)
    }
    const select = this.form.elements.payable_key
    const kept = select.value
    const placeholder = select.options[0]
    select.replaceChildren(placeholder, ...this.payables.map((p) => new Option(`${p.label} (${p.amount_due})`, `${p.kind}:${p.id}`)))
    select.value = kept
    if (select.value !== kept) select.selectedIndex = -1
    if (this.payables.length === 0) select.after(this.nothing)
    else this.nothing.remove()
    this.form.querySelector("[data-save]").disabled = this.saving || this.payables.length === 0
  }

  // onPayableChange(): the amount becomes what that item costs.
  payableChanged() {
    const key = this.form.elements.payable_key.value
    const option = this.payables.find((p) => `${p.kind}:${p.id}` === key)
    if (option) this.form.elements.amount.value = String(option.amount_due)
  }

  async submitRecord(event) {
    event.preventDefault()
    const { payable_key: payable, amount, notes } = this.form.elements
    // Validators.required on the item, required + min(0.01) on the amount.
    if (!this.client || !payable.value || amount.value === "" || Number(amount.value) < 0.01) return

    const [kind, id] = payable.value.split(":")
    const save = this.form.querySelector("[data-save]")
    this.saving = true
    save.disabled = true
    save.textContent = ` ${this.labelsValue.saving} `
    showFormError(this.panel, null)
    const result = await send("POST", this.urlValue, {
      client_id: this.client.id,
      amount: Number(amount.value),
      notes: notes.value || undefined,
      contract_id: kind === "contract" ? id : undefined,
      booking_id: kind === "booking" ? id : undefined,
    })
    this.saving = false
    if (result.ok) {
      window.dispatchEvent(new CustomEvent("payments-record:close"))
      toast("success", this.labelsValue.saved)
      return this.load()
    }
    save.disabled = this.payables.length === 0
    save.textContent = ` ${this.labelsValue.save} `
    showFormError(this.panel, result.error || this.labelsValue.error)
  }
}
