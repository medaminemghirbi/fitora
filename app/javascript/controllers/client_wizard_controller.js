import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "../lib/ng"

// The new-member wizard of ClientsListComponent, step for step:
//
//   1 who they are — first name, last name and phone required; the rest
//     folded under "more details";
//   2 what they buy — one offer (a formule for one activity or pack, at its
//     price: the subscriptions dialogs' own list), then the start date, a
//     discount and the total;
//   3 whether they pay now — and how.
//
// Only the first step is compulsory: with no offer picked, step 2's button
// finishes there. The state lives here, as it lives in the component's
// signals and forms, and the markup is put in and taken out the way its
// @if blocks are, from the <template>s _wizard.html.erb renders. Moving
// between steps keeps every value; each opening starts blank (the modal
// clones a fresh copy). The final submit sends what ClientsService#create
// sends, through a form Turbo submits: a redirect to the member's file, or
// the refusal shown at the top of the modal.
export default class extends Controller {
  static targets = [
    "actions", "cancel", "back", "primary", "finish", "stepsTemplate",
    "identity", "details", "offers", "pricing", "total", "payment", "method", "payLater"
  ]
  static values = { offers: Array, currencySymbol: String, today: String, labels: Object }

  static IDENTITY = ["first_name", "last_name", "phone", "email", "date_of_birth", "gender", "emergency_contact_name", "emergency_contact_phone", "notes"]
  static REQUIRED = ["first_name", "last_name", "phone"]

  connect() {
    this.step = 0
    this.moreDetails = false
    this.person = Object.fromEntries(this.constructor.IDENTITY.map((k) => [k, ""]))
    this.offerKey = ""
    this.discount = 0
    this.startsOn = this.todayValue
    this.collect = true
    this.method = "cash"
    this.saving = false

    // The step's nodes, made once and kept, so what was typed survives a
    // step change — as the FormGroup's values do.
    this.nodes = {}
    this.buttons = { cancel: this.cancelTarget, back: this.backTarget, primary: this.primaryTarget, finish: this.finishTarget }
    this.render()
  }

  // ---- what is on sale ----------------------------------------------------

  get offer() {
    return this.offersValue.find((o) => o.key === this.offerKey) ?? null
  }

  get total() {
    const offer = this.offer
    return offer ? Math.max(offer.price - (this.discount || 0), 0) : null
  }

  get identityValid() {
    return this.constructor.REQUIRED.every((k) => this.person[k] !== "")
  }

  // canAdvance(): the step's own requirements, never a later step's.
  get canAdvance() {
    if (this.step === 0) return this.identityValid
    if (this.step === 1) return !this.offer || this.total !== null
    return true
  }

  // ---- the controls ----------------------------------------------------

  input(event) {
    this.person[event.target.dataset.field] = event.target.value
    this.renderActions()
  }

  toggleDetails() {
    this.moreDetails = !this.moreDetails
    this.renderStep()
  }

  offerChanged(event) {
    if (event.target.name !== "cl-offer") return
    this.offerKey = event.target.value
    this.renderStep()
  }

  startChanged(event) {
    this.startsOn = event.target.value
  }

  // onDiscountChange(+value): a value that is not a number counts as 0, and
  // the box then shows what the signal holds, as the [value] binding does.
  discountChanged(event) {
    const value = Number(event.target.value) || 0
    if (value !== this.discount) {
      this.discount = value
      if (event.target.value !== String(value)) event.target.value = String(value)
    }
    this.renderTotals()
    this.renderActions()
  }

  collectChanged(event) {
    this.collect = event.target.checked
    this.renderStep()
  }

  methodChanged(event) {
    this.method = event.target.value
  }

  // The form's submit (the primary button, or Enter in a field): next().
  next(event) {
    event.preventDefault()
    if (this.saving) return
    if (this.step === 0 && !this.identityValid) return
    // Nothing was bought, so there is nothing to collect: skip step 3.
    if (this.step === 1 && !this.offer) {
      this.submit()
      return
    }
    this.goTo(Math.min(this.step + 1, 2))
  }

  back() {
    this.goTo(Math.max(this.step - 1, 0))
  }

  submit() {
    if (!this.identityValid) {
      this.goTo(0)
      return
    }

    this.clearError()
    const form = document.createElement("form")
    form.method = "post"
    form.action = this.element.action
    form.hidden = true
    const add = (name, value) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      form.append(input)
    }
    add("authenticity_token", csrfToken())
    for (const key of this.constructor.IDENTITY) add(`client[${key}]`, this.person[key])
    const offer = this.offer
    if (offer) {
      add("subscription[contract_type_id]", offer.contract_type_id)
      add(offer.pack_id ? "subscription[pack_id]" : "subscription[activity_id]", offer.pack_id ?? offer.activity_id)
      add("subscription[starts_on]", this.startsOn)
      add("subscription[discount]", String(this.discount))
      add("subscription[collect_payment]", String(this.collect))
      add("subscription[payment_method]", this.method)
    }
    form.addEventListener("turbo:submit-start", () => this.setSaving(true))
    form.addEventListener("turbo:submit-end", (event) => {
      if (!event.detail.success) this.setSaving(false)
      form.remove()
    })
    document.body.append(form)
    form.requestSubmit()
  }

  // ---- rendering ---------------------------------------------------------

  goTo(step) {
    this.step = step
    const steps = document.getElementById("cl-wizard-steps")
    const template = this.stepsTemplateTargets.find((t) => Number(t.dataset.step) === step)
    if (steps && template) steps.replaceChildren(template.content.firstElementChild.cloneNode(true))
    this.renderStep()
  }

  render() {
    this.renderStep()
  }

  // Puts the current step's blocks in the form, in order, before the actions.
  renderStep() {
    const blocks = this.blocksFor(this.step)
    const wanted = new Set(blocks.flat())
    for (const node of [...this.element.childNodes]) {
      if (node !== this.actionsTarget && node.tagName !== "TEMPLATE" && !wanted.has(node)) node.remove()
    }
    for (const node of blocks.flat()) this.actionsTarget.before(node)
    this.renderTotals()
    this.renderActions()
  }

  blocksFor(step) {
    if (step === 0) return [this.identityNodes(), this.moreDetails ? this.block("details") : []]
    if (step === 1) {
      const blocks = [this.offerNodes()]
      if (this.offer) blocks.push(this.pricingNodes(), this.block("total"))
      return blocks
    }
    return [this.block("total"), this.paymentNodes(), this.collect ? this.methodNodes() : this.block("payLater")]
  }

  // A block's nodes, cloned from its template the first time.
  block(name) {
    if (!this.nodes[name]) {
      const template = this[`${name}Target`]
      this.nodes[name] = [...template.content.cloneNode(true).childNodes]
      for (const field of this.nodes[name].flatMap((n) => (n.querySelectorAll ? [...n.querySelectorAll("[data-field]")] : []))) {
        field.value = this.person[field.dataset.field] ?? ""
        field.addEventListener("input", (event) => this.input(event))
      }
    }
    return this.nodes[name]
  }

  identityNodes() {
    const nodes = this.block("identity")
    const toggle = nodes.find((n) => n.matches?.("button.btn-link"))
    toggle.setAttribute("aria-expanded", String(this.moreDetails))
    const icon = toggle.querySelector("i")
    icon.classList.toggle("bi-chevron-down", !this.moreDetails)
    icon.classList.toggle("bi-chevron-up", this.moreDetails)
    return nodes
  }

  offerNodes() {
    const nodes = this.block("offers")
    const fieldset = nodes.find((n) => n.querySelector)
    if (!fieldset.dataset.wired) {
      fieldset.addEventListener("change", (event) => this.offerChanged(event))
      fieldset.dataset.wired = "true"
    }
    for (const radio of fieldset.querySelectorAll('input[name="cl-offer"]')) radio.checked = radio.value === this.offerKey
    return nodes
  }

  pricingNodes() {
    const nodes = this.block("pricing")
    nodes[0].querySelector("#cl-start").value = this.startsOn
    nodes[0].querySelector("#cl-discount").value = String(this.discount)
    return nodes
  }

  paymentNodes() {
    const nodes = this.block("payment")
    nodes[0].querySelector("#cl-collect").checked = this.collect
    return nodes
  }

  methodNodes() {
    const nodes = this.block("method")
    nodes[0].querySelector("select").value = this.method
    return nodes
  }

  renderTotals() {
    const text = this.money(this.total)
    for (const node of this.nodes.total ?? []) {
      const strong = node.querySelector?.("[data-total]")
      if (strong) strong.textContent = text
    }
  }

  // The buttons the step shows, and what they say (clients-list.component.html).
  renderActions() {
    const { cancel, back, primary, finish } = this.buttons
    const labels = this.labelsValue
    const order = [this.step > 0 ? back : cancel, this.step < 2 ? primary : finish]
    for (const button of Object.values(this.buttons)) if (!order.includes(button)) button.remove()
    this.actionsTarget.replaceChildren(...order)

    if (this.step < 2) {
      primary.disabled = !this.canAdvance
      primary.textContent = ` ${this.step === 1 && !this.offer ? (this.saving ? labels.saving : labels.finish_without_plan) : labels.next} `
    } else {
      finish.disabled = this.saving
      finish.textContent = ` ${this.saving ? labels.saving : labels.finish} `
    }
  }

  setSaving(on) {
    this.saving = on
    this.renderActions()
  }

  // MoneyPipe.
  money(value) {
    if (value === null || value === undefined) return "—"
    const formatted = Number.isFinite(value) ? value.toFixed(2).replace(/\.00$/, "") : String(value)
    return `${formatted} ${this.currencySymbolValue}`
  }

  clearError() {
    const error = document.getElementById("cl-wizard-error")
    if (error && error.tagName !== "TEMPLATE") {
      const placeholder = document.createElement("template")
      placeholder.id = "cl-wizard-error"
      error.replaceWith(placeholder)
    }
  }
}
