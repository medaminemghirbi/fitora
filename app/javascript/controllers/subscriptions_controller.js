import { Controller } from "@hotwired/stimulus"
import { confirmAsk } from "../lib/confirm"
import { send, showFormError } from "../lib/crud"
import { downloadBlob, interpolate, money } from "../lib/ng"
import { toast } from "../lib/toast"

// Everything the desk does to a subscription, wherever it shows — a row of
// the subscriptions page, a member's file: sell, renew, collect, edit,
// pause, resume, cancel, and the two documents. An action reads its term
// off the nearest [data-subscription] (SubscriptionsHelper#subscription_payload),
// fills its dialog (contracts/_dialogs) as it opens, sends the write, and
// announces subscriptions:changed so the page draws itself again.
//
// Selling and renewing are one form: pick an offer (a formule for one
// activity or pack, at its price), the start (a renewal starts where the
// term ends), a discount, paid now — and how — or later.
export default class extends Controller {
  static targets = ["keepCurrent"]
  static values = { url: String, offers: Array, member: Object, today: String, locale: String, symbols: Object, labels: Object }
  static SEARCH_DEBOUNCE_MS = 250

  connect() {
    this.onOpened = (event) => this.opened(event.detail)
    window.addEventListener("modal:opened", this.onOpened)
  }

  disconnect() {
    window.removeEventListener("modal:opened", this.onOpened)
    clearTimeout(this.searchTimer)
  }

  // ---- the actions -----------------------------------------------------------------

  sell() {
    this.mode = "sell"
    this.term = null
    this.open("abo-sale")
  }

  renew(event) {
    this.mode = "renew"
    this.term = this.termOf(event)
    this.open("abo-sale")
  }

  collect(event) {
    this.term = this.termOf(event)
    this.open("abo-collect")
  }

  edit(event) {
    this.term = this.termOf(event)
    this.open("abo-edit")
  }

  async pause(event) {
    const term = this.termOf(event)
    const labels = this.labelsValue
    const ok = await confirmAsk({ title: labels.pause_confirm_title, body: interpolate(labels.pause_confirm_body, { name: term.client.name }) })
    if (ok) this.act(`${this.urlValue}/${term.id}/pause`, labels.paused_done)
  }

  resume(event) {
    const term = this.termOf(event)
    this.act(`${this.urlValue}/${term.id}/resume`, this.labelsValue.resumed_done)
  }

  async cancel(event) {
    const term = this.termOf(event)
    const labels = this.labelsValue
    const ok = await confirmAsk({
      title: labels.cancel_confirm_title, body: interpolate(labels.cancel_confirm_body, { name: term.client.name, label: term.label }),
      confirmLabel: labels.cancel_confirm_ok, danger: true,
    })
    if (ok) this.act(`${this.urlValue}/${term.id}/cancel`, labels.cancelled_done)
  }

  downloadAgreement(event) {
    const term = this.termOf(event)
    this.download(`${this.urlValue}/${term.id}/agreement`, `contrat-${term.ref}.pdf`)
  }

  downloadInvoice(event) {
    const term = this.termOf(event)
    this.download(`${this.urlValue}/${term.id}/receipt`, `facture-${term.ref}.pdf`)
  }

  // ---- the dialogs, filled as they open --------------------------------------------

  opened({ name, panel }) {
    if (name === "abo-sale") this.fillSale(panel)
    else if (name === "abo-collect") this.fillCollect(panel)
    else if (name === "abo-edit") this.fillEdit(panel)
  }

  fillSale(panel) {
    const form = panel.querySelector('[data-abo-form="sale"]')
    const labels = this.labelsValue
    const renewing = this.mode === "renew"
    const term = this.term
    const part = (name) => form.querySelector(`[data-part="${name}"]`)
    this.sale = { panel, form, part }
    this.saving = false

    const title = renewing ? labels.renew_title : labels.sell_title
    panel.querySelector(".modal-panel-header h3").textContent = title
    panel.setAttribute("aria-label", title)

    // Who: the term's member, the page's member, or one to find.
    this.member = renewing ? { id: term.client.id, name: term.client.name, holds: [] } : this.memberValue?.id ? this.memberValue : null
    this.searchable = !renewing && !this.memberValue?.id
    part("current").textContent = renewing ? interpolate(labels.current, { label: term.label, date: this.date(term.expires_on) }) : ""
    this.show(part("current"), renewing)

    // A renewal opens on the term's own offer — or, when that is not on sale
    // any more, on "keep it as it is".
    this.currentKey = renewing && term.item ? `${term.plan_id}|${term.item}` : null
    if (renewing && !this.offerFor(this.currentKey)) {
      const keep = this.keepCurrentTarget.content.firstElementChild.cloneNode(true)
      keep.querySelector("[data-keep-label]").textContent = term.label
      keep.querySelector("[data-keep-price]").textContent = this.money(term.price, term.currency)
      const legend = form.querySelector("fieldset.abo-field > legend")
      legend.after(keep)
      this.currentKey = "current"
    }
    this.offerKey = renewing ? this.currentKey : this.offersValue.length === 1 ? this.offersValue[0].key : null
    for (const radio of form.querySelectorAll('input[name="offer"]')) radio.checked = radio.value === this.offerKey

    const f = form.elements
    f.starts_on.value = this.todayValue
    f.discount.value = String(renewing ? term.discount || 0 : 0)
    this.discountTouched = false

    form.addEventListener("change", (event) => {
      const input = event.target
      if (input.name === "offer") {
        this.offerKey = input.value
        // A discount agreed for one formule does not follow onto another.
        if (renewing && !this.discountTouched) f.discount.value = String(this.offerKey === this.currentKey ? term.discount || 0 : 0)
      }
      this.drawSale()
    })
    f.discount.addEventListener("input", () => {
      this.discountTouched = true
      this.drawSale()
    })
    f.starts_on.addEventListener("input", () => this.drawSale())
    const search = form.querySelector("[data-member-search]")
    search.addEventListener("input", () => this.searchMembers(search.value))
    search.addEventListener("keydown", (event) => event.key === "Enter" && event.preventDefault())
    form.querySelector("[data-member-change]").addEventListener("click", () => {
      this.member = null
      this.drawSale()
      search.value = ""
      form.querySelector("[data-member-results]").replaceChildren()
      search.focus()
    })
    form.addEventListener("submit", (event) => {
      event.preventDefault()
      this.submitSale()
    })

    this.drawSale()
    if (this.searchable) queueMicrotask(() => search.focus())
  }

  // What the form shows for what is picked so far.
  drawSale() {
    const { form, part } = this.sale
    const labels = this.labelsValue
    const renewing = this.mode === "renew"
    const offer = this.chosenOffer

    this.show(part("member-pick"), this.searchable && !this.member)
    this.show(part("member-shown"), Boolean(this.member))
    this.show(part("member-change"), this.searchable)
    if (this.member) form.querySelector("[data-member-name]").textContent = [this.member.name, this.member.phone].filter(Boolean).join(" · ")

    // Selling what the member already holds would overlap it: say so, and
    // what to do instead.
    const hold = !renewing && offer && this.member?.holds?.find((h) => h.item === offer.item)
    this.show(part("overlap"), Boolean(hold))
    if (hold) part("overlap").textContent = interpolate(labels.overlap, { name: this.member.name, label: hold.label, date: hold.until })
    this.show(part("other-formule"), renewing && Boolean(offer) && this.offerKey !== this.currentKey)

    this.show(part("start"), !renewing)
    const starts = renewing ? this.term.next_starts_on : form.elements.starts_on.value
    const dates = part("dates")
    this.show(dates, Boolean(offer && starts))
    if (offer && starts) {
      dates.textContent = interpolate(renewing ? labels.starts_on_renewal : labels.ends_on, {
        start: this.date(starts), end: this.date(this.addDays(starts, offer.duration_days)),
      })
    }

    const total = offer ? Math.max(0, offer.price - this.discount(form)) : null
    form.querySelector("[data-total]").textContent = total === null ? "—" : this.money(total, offer.currency)

    const later = form.querySelector('input[name="pay"][value="later"]')
    if (later) this.show(part("methods"), !later.checked)

    const save = form.querySelector("[data-save]")
    const label = renewing ? labels.renew_submit : labels.sell_submit
    save.textContent = total === null ? label : `${label} · ${this.money(total, offer.currency)}`
    save.disabled = this.saving || !offer || !this.member || (!renewing && !form.elements.starts_on.value)
  }

  async submitSale() {
    const { form, panel } = this.sale
    const offer = this.chosenOffer
    const renewing = this.mode === "renew"
    if (!offer || !this.member || this.saving) return

    const body = { discount: this.discount(form) }
    const pay = form.querySelector('input[name="pay"]:checked')?.value
    if (pay === "now") {
      body.collect_payment = true
      body.payment_method = form.querySelector('input[name="payment_method"]:checked')?.value ?? "cash"
    }
    // A renewal on the term's own offer names none: the same formule.
    if (!renewing || this.offerKey !== this.currentKey) {
      Object.assign(body, { contract_type_id: offer.contract_type_id }, offer.pack_id ? { pack_id: offer.pack_id } : { activity_id: offer.activity_id })
    }
    if (!renewing) Object.assign(body, { client_id: this.member.id, starts_on: form.elements.starts_on.value })

    const labels = this.labelsValue
    const url = renewing ? `${this.urlValue}/${this.term.id}/renew` : this.urlValue
    await this.save(panel, form, "abo-sale", "POST", url, body, renewing ? labels.renewed : labels.sold, () => this.drawSale())
  }

  get chosenOffer() {
    if (this.offerKey === "current") {
      const t = this.term
      return { key: "current", item: t.item, price: t.price, currency: t.currency, duration_days: t.duration_days }
    }
    return this.offerFor(this.offerKey)
  }

  offerFor(key) {
    return key ? (this.offersValue.find((o) => o.key === key) ?? null) : null
  }

  discount(form) {
    return Math.max(0, Number(form.elements.discount.value) || 0)
  }

  // The member search: name or phone, a page of matches to pick from.
  searchMembers(text) {
    clearTimeout(this.searchTimer)
    const results = this.sale.form.querySelector("[data-member-results]")
    if (!text.trim()) {
      results.replaceChildren()
      return
    }
    this.searchTimer = setTimeout(async () => {
      const id = (this.searchId = (this.searchId ?? 0) + 1)
      results.replaceChildren(this.note(this.labelsValue.searching))
      const response = await fetch(`${this.urlValue}/members?search=${encodeURIComponent(text.trim())}`, {
        headers: { Accept: "application/json" }, credentials: "same-origin",
      }).catch(() => null)
      if (id !== this.searchId || !results.isConnected) return
      const members = response?.ok ? (await response.json()).members : []
      if (!members.length) return results.replaceChildren(this.note(this.labelsValue.no_member_found))
      results.replaceChildren(...members.map((member) => {
        const button = document.createElement("button")
        button.type = "button"
        button.className = "abo-member-result"
        const name = document.createElement("span")
        name.textContent = member.name
        button.append(name)
        if (member.phone) {
          const phone = document.createElement("small")
          phone.dir = "ltr"
          phone.textContent = member.phone
          button.append(phone)
        }
        button.addEventListener("click", () => {
          this.member = member
          this.drawSale()
          this.sale.form.querySelector('input[name="offer"]:checked, input[name="offer"]')?.focus()
        })
        return button
      }))
    }, this.constructor.SEARCH_DEBOUNCE_MS)
  }

  fillCollect(panel) {
    const form = panel.querySelector('[data-abo-form="collect"]')
    const term = this.term
    const labels = this.labelsValue
    this.saving = false
    const amount = this.money(term.amount_due, term.currency)
    form.querySelector("[data-collect-what]").textContent = `${term.client.name} — ${term.label} (${term.ref})`
    form.querySelector("[data-total]").textContent = amount
    form.querySelector("[data-save]").textContent = interpolate(labels.collect_submit, { amount })
    form.addEventListener("submit", (event) => {
      event.preventDefault()
      if (this.saving) return
      const method = form.querySelector('input[name="payment_method"]:checked')?.value ?? "cash"
      this.save(panel, form, "abo-collect", "POST", `${this.urlValue}/${term.id}/collect`, { payment_method: method }, labels.collected)
    })
  }

  fillEdit(panel) {
    const form = panel.querySelector('[data-abo-form="edit"]')
    const f = form.elements
    const term = this.term
    const labels = this.labelsValue
    this.saving = false
    form.querySelector("[data-edit-what]").textContent = `${term.client.name} — ${term.label}`
    f.starts_on.value = term.starts_on ?? ""
    f.expires_on.value = term.expires_on ?? ""
    f.discount.value = String(term.discount || 0)
    // A paid term's price is settled: its discount no longer moves.
    f.discount.disabled = term.paid
    this.show(form.querySelector('[data-part="discount-locked"]'), term.paid)

    const draw = () => {
      form.querySelector("[data-total]").textContent = this.money(Math.max(0, term.price - this.discount(form)), term.currency)
      form.querySelector("[data-save]").disabled = this.saving || !f.starts_on.value || !f.expires_on.value
    }
    // Moving the start moves the end with it: the length stays the same.
    let start = f.starts_on.value
    f.starts_on.addEventListener("input", () => {
      if (start && f.starts_on.value && f.expires_on.value) {
        f.expires_on.value = this.addDays(f.expires_on.value, this.daysBetween(start, f.starts_on.value))
      }
      start = f.starts_on.value
      draw()
    })
    f.expires_on.addEventListener("input", draw)
    f.discount.addEventListener("input", draw)
    form.addEventListener("submit", (event) => {
      event.preventDefault()
      if (this.saving) return
      const body = { starts_on: f.starts_on.value, expires_on: f.expires_on.value }
      if (!term.paid) body.discount = this.discount(form)
      this.save(panel, form, "abo-edit", "PATCH", `${this.urlValue}/${term.id}`, body, labels.updated)
    })
    draw()
  }

  // ---- sending ------------------------------------------------------------------------

  // A dialog's write: busy while it runs (the modal stays open), the
  // refusal at the top of the dialog, or closed, a toast, the page again.
  async save(panel, form, modal, method, url, body, done, redraw = null) {
    const host = panel.closest("app-modal")
    const button = form.querySelector("[data-save]")
    this.saving = true
    button.disabled = true
    host?.setAttribute("data-modal-busy", "")
    showFormError(panel, null, null)
    const result = await send(method, url, body)
    host?.removeAttribute("data-modal-busy")
    this.saving = false
    if (!result.ok) {
      showFormError(panel, result.error || this.labelsValue.error_generic, null)
      button.disabled = false
      redraw?.()
      return
    }
    window.dispatchEvent(new CustomEvent(`${modal}:close`))
    toast("success", done)
    this.changed()
  }

  // A one-click action (pause, resume, cancel), one at a time.
  async act(url, done) {
    if (this.busy) return
    this.busy = true
    const result = await send("POST", url)
    this.busy = false
    if (!result.ok) return toast("error", result.error || this.labelsValue.error_generic)
    toast("success", done)
    this.changed()
  }

  changed() {
    window.dispatchEvent(new CustomEvent("subscriptions:changed"))
  }

  async download(url, filename) {
    const response = await fetch(url, { credentials: "same-origin" }).catch(() => null)
    if (!response?.ok) return toast("error", this.labelsValue.error_generic)
    downloadBlob(await response.blob(), filename)
  }

  // ---- small things -------------------------------------------------------------------

  open(name) {
    window.dispatchEvent(new CustomEvent(`${name}:open`))
  }

  termOf(event) {
    return JSON.parse(event.currentTarget.closest("[data-subscription]").dataset.subscription)
  }

  show(element, visible) {
    if (element) element.hidden = !visible
  }

  note(text) {
    const p = document.createElement("p")
    p.className = "abo-member-note"
    p.textContent = text
    return p
  }

  money(value, currency) {
    return money(value, this.symbolsValue[currency] ?? currency ?? "")
  }

  // "23 oct. 2026" from "2026-10-23", in the page's language (Latin digits).
  date(iso) {
    if (!iso) return ""
    const [y, m, d] = iso.split("-").map(Number)
    return new Intl.DateTimeFormat(`${this.localeValue}-u-nu-latn`, { day: "numeric", month: "short", year: "numeric" }).format(new Date(y, m - 1, d))
  }

  addDays(iso, days) {
    const [y, m, d] = iso.split("-").map(Number)
    const date = new Date(y, m - 1, d + Number(days || 0))
    const pad = (n) => String(n).padStart(2, "0")
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
  }

  daysBetween(from, to) {
    const day = (iso) => {
      const [y, m, d] = iso.split("-").map(Number)
      return Date.UTC(y, m - 1, d) / 86400000
    }
    return day(to) - day(from)
  }
}
