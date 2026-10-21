import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { confirmAsk } from "../lib/confirm"
import { send, showFormError } from "../lib/crud"
import { interpolate, scoped } from "../lib/ng"
import { withProgress } from "../lib/progress"
import { toast } from "../lib/toast"

const TAB_FOR = { activity: "activites", plan: "formules", pack: "packs" }

// CAPACITY_BOUNDS (core/models/activity.model.ts) and each format's preset.
const CAPACITY = { individual: { min: 1, max: 1, preset: 1 }, small_group: { min: 2, max: 9, preset: 6 }, collective: { min: 10, max: null, preset: 15 } }

// CatalogueComponent and its tabs. The server renders each tab — searched
// and paged — and this controller does what the components do in the
// browser: switch tab (a visit, ?tab=), search on every keystroke and page
// (the list redrawn in place, the search box kept), edit a price where it
// stands in the grid, and the three forms and the catalogue picker. After a
// save the panel is redrawn in place, as CatalogueStore#reload redraws it:
// no skeleton, and a dialog still open stays open.
export default class extends Controller {
  // embedded: a tool inside another page (the onboarding flow) — the URL is
  // that page's, and the tool alone is redrawn.
  static values = { url: String, tab: String, open: String, data: Object, labels: Object, embedded: Boolean }

  connect() {
    this.term = new URLSearchParams(location.search).get("q") ?? ""
    this.page = Number(new URLSearchParams(location.search).get("page")) || 1
    this.requestId = 0
    // ?action=new (from a setup step, or the old deep link): the tab's form.
    if (this.openValue) {
      history.replaceState(history.state, "", this.pageUrl({ tab: this.tabValue }))
      requestAnimationFrame(() => this.openFor(this.openValue))
    }
  }

  get labels() {
    return this.labelsValue
  }

  // ---- tabs ------------------------------------------------------------------

  select(event) {
    const tab = event.currentTarget.dataset.tab
    if (tab === this.tabValue) return
    Turbo.visit(this.pageUrl({ tab }))
  }

  // start(kind): the tab that owns the form, with the form open.
  start(event) {
    // Embedded, the tools' requestCreate goes nowhere (the onboarding page
    // binds none).
    if (this.embeddedValue) return
    const kind = event.currentTarget.dataset.kind
    const tab = TAB_FOR[kind]
    if (tab === this.tabValue) return this.openFor(tab)
    Turbo.visit(this.pageUrl({ tab, action: "new" }))
  }

  openFor(tab) {
    if (tab === "activites") this.openPicker()
    else if (tab === "formules") this.openPlanForm()
    else if (tab === "packs") this.openPackForm()
  }

  pageUrl(params) {
    const query = new URLSearchParams()
    for (const [key, value] of Object.entries(params)) if (value !== undefined && value !== null && value !== "") query.set(key, value)
    const text = query.toString()
    return `${this.urlValue}${text ? `?${text}` : ""}`
  }

  // ---- search and pages ------------------------------------------------------

  // Every keystroke, as the component's signal does; page 1 again.
  search(event) {
    this.term = event.target.value
    this.page = 1
    this.redraw("list")
  }

  goToPage(event) {
    this.page = Number(event.currentTarget.dataset.page)
    this.redraw("list")
  }

  refresh() {
    return this.redraw("all")
  }

  async redraw(mode) {
    const id = ++this.requestId
    const params = { tab: this.tabValue, q: this.term, page: this.page > 1 ? this.page : "" }
    if (!this.embeddedValue) history.replaceState(history.state, "", this.pageUrl(params))
    const response = await withProgress(() =>
      fetch(this.pageUrl({ ...params, fragment: 1 }), { credentials: "same-origin", headers: { Accept: "text/html" } }).catch(() => null)
    )
    if (id !== this.requestId || !response?.ok) return
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    const freshPanel = fresh.content.querySelector("#cat-panel")
    this.dataValue = JSON.parse(freshPanel.dataset.catalogue)
    // The catalogue's panel, or — embedded — the tool's own host.
    const host = this.embeddedValue ? this.element.querySelector("app-activities, app-plans") : null
    const panel = host ?? this.element.querySelector("#cat-panel")
    const freshSource = host ? freshPanel.querySelector(host.tagName.toLowerCase()) : freshPanel
    if (mode === "list") return this.swapList(panel, freshSource)

    this.element.querySelector("#cat-tabs")?.replaceWith(fresh.content.querySelector("#cat-tabs"))
    // A dialog still open (a refused save) stays as it is.
    const open = [...panel.querySelectorAll("app-modal")].find((modal) => modal.querySelector(".modal-backdrop-custom"))
    if (open) freshSource.querySelector(`app-modal[data-modal-name-value="${open.dataset.modalNameValue}"]`)?.replaceWith(open)
    panel.replaceChildren(...freshSource.childNodes)
  }

  // The list alone — the card, or the cards and the pagination.
  swapList(panel, freshPanel) {
    const old = [...panel.querySelectorAll("[data-catalogue-list]")]
    if (!old.length) return
    old[0].before(...freshPanel.querySelectorAll("[data-catalogue-list]"))
    old.forEach((node) => node.remove())
  }

  // ---- the price grid ----------------------------------------------------------

  gridKey(event) {
    const input = event.target
    if (event.key === "Enter") input.blur()
    else if (event.key === "Escape") {
      input.value = input.closest("td").dataset.price
      input.blur()
    }
  }

  async gridCommit(event) {
    const input = event.target
    const cell = input.closest("td")
    const { plan: planId, kind, id } = cell.dataset
    const raw = input.value.trim()
    const current = cell.dataset.price === "" ? null : Number(cell.dataset.price)
    const next = raw === "" ? null : Number(raw.replace(",", "."))

    if (next !== null && (Number.isNaN(next) || next < 0)) {
      input.value = cell.dataset.price
      return
    }
    if (next === current) return

    const plan = this.dataValue.plans.find((p) => p.id === planId)
    cell.classList.add("is-saving")
    const payload = kind === "activity"
      ? { activity_prices: [...plan.activity_prices.filter((r) => r.activity_id !== id).map((r) => ({ activity_id: r.activity_id, price: Number(r.price) })), ...(next === null ? [] : [{ activity_id: id, price: next }])] }
      : { pack_prices: [...(plan.pack_prices ?? []).filter((r) => r.pack_id !== id).map((r) => ({ pack_id: r.pack_id, price: Number(r.price) })), ...(next === null ? [] : [{ pack_id: id, price: next }])] }
    const result = await this.json("PATCH", `${this.urlValue}/plans/${planId}`, payload)
    cell.classList.remove("is-saving")
    if (!result.ok) {
      input.value = cell.dataset.price
      return toast("error", result.error || this.labels["common.error_generic"])
    }

    // replacePlan(): the formule as the server now has it.
    const data = this.dataValue
    data.plans = data.plans.map((p) => (p.id === planId ? result.body.plan : p))
    this.dataValue = data
    const rows = kind === "activity" ? result.body.plan.activity_prices.find((r) => r.activity_id === id) : (result.body.plan.pack_prices ?? []).find((r) => r.pack_id === id)
    const price = rows ? String(Number(rows.price)) : ""
    cell.dataset.price = price
    input.value = price
    cell.classList.toggle("is-empty", price === "")
    this.markUnsold(cell.closest("tr"))
    cell.classList.add("is-saved")
    const tick = scoped(document.createElement("i"), "price-grid")
    tick.className = "bi bi-check-lg pg-tick"
    tick.setAttribute("aria-hidden", "true")
    cell.append(tick)
    setTimeout(() => {
      cell.classList.remove("is-saved")
      tick.remove()
    }, 1400)
  }

  // soldIn() === 0: the row's "not sold" flag.
  markUnsold(row) {
    const sold = [...row.querySelectorAll("td.pg-cell")].some((td) => td.dataset.price !== "")
    const head = row.querySelector("th.pg-row")
    let flag = head.querySelector(".pg-unsold")
    if (sold) flag?.remove()
    else if (!flag) {
      flag = scoped(document.createElement("span"), "price-grid")
      flag.className = "pg-unsold"
      flag.textContent = this.labels.not_sold
      head.append(flag)
    }
  }

  // ---- dialogs -------------------------------------------------------------------

  modalOpened(event) {
    const { name, panel } = event.detail
    if (name === "catalogue-activity") this.fillActivityForm(panel)
    else if (name === "catalogue-picker") this.fillPicker(panel)
    else if (name === "catalogue-plan") this.fillPlanForm(panel)
    else if (name === "catalogue-pack") this.fillPackForm(panel)
  }

  setTitle(panel, title) {
    panel.querySelector(".modal-panel-header h3").textContent = title
    panel.setAttribute("aria-label", title)
  }

  busy(button, saving) {
    button.disabled = saving
    button.textContent = ` ${this.labels[saving ? "common.saving" : "common.save"]} `
  }

  // ---- activities ----------------------------------------------------------------

  openActivityForm(event) {
    const item = event?.currentTarget?.closest?.("[data-activity]")
    this.editingActivity = item ? JSON.parse(item.dataset.activity) : null
    window.dispatchEvent(new CustomEvent("catalogue-activity:open"))
  }

  fillActivityForm(panel) {
    const activity = this.editingActivity
    this.setTitle(panel, this.labels[activity ? "activities.edit" : "activities.new"])
    const form = panel.querySelector("[data-activity-form]")
    const f = form.elements
    f.name.value = activity?.name ?? ""
    f.emoji.value = activity?.emoji ?? ""
    f.description.value = activity?.description ?? ""
    f.session_format.value = activity?.session_format ?? "collective"
    f.duration.value = activity?.duration ?? 60
    f.capacity.value = activity?.capacity ?? 15
    this.touchedCapacity = false

    const markEmoji = () => form.querySelectorAll("[data-emoji]").forEach((b) => b.classList.toggle("active", f.emoji.value === b.dataset.emoji))
    form.querySelectorAll("[data-emoji]").forEach((button) =>
      button.addEventListener("click", () => {
        f.emoji.value = f.emoji.value === button.dataset.emoji ? "" : button.dataset.emoji
        markEmoji()
      })
    )
    f.emoji.addEventListener("input", markEmoji)
    markEmoji()

    const applyFormat = (snap) => {
      const format = f.session_format.value
      const bounds = CAPACITY[format]
      form.querySelector("[data-format-hint]").textContent = ` ${this.labels.format_hints[format]} `
      f.capacity.min = String(bounds.min)
      if (bounds.max === null) f.capacity.removeAttribute("max")
      else f.capacity.max = String(bounds.max)
      if (format === "individual") {
        f.capacity.value = "1"
        f.capacity.disabled = true
      } else {
        f.capacity.disabled = false
        const current = Number(f.capacity.value)
        if (snap && (current < bounds.min || (bounds.max !== null && current > bounds.max))) f.capacity.value = String(bounds.preset)
      }
      this.renderCapacityError(form)
    }
    f.session_format.addEventListener("change", () => applyFormat(true))
    f.capacity.addEventListener("blur", () => {
      this.touchedCapacity = true
      this.renderCapacityError(form)
    })
    f.capacity.addEventListener("input", () => this.renderCapacityError(form))
    applyFormat(false)
    form.addEventListener("submit", (event) => this.submitActivity(event, form, panel))
  }

  capacityValid(form) {
    const f = form.elements
    const bounds = CAPACITY[f.session_format.value]
    const value = f.capacity.value === "" ? null : Number(f.capacity.value)
    return value !== null && value >= bounds.min && (bounds.max === null || value <= bounds.max)
  }

  // The capacity's message, under it, once touched and wrong.
  renderCapacityError(form) {
    const f = form.elements
    const field = form.querySelector("[data-capacity-field]")
    field.querySelector(".text-danger")?.remove()
    if (f.capacity.disabled || !this.touchedCapacity || this.capacityValid(form)) return
    const bounds = CAPACITY[f.session_format.value]
    const message = scoped(document.createElement("div"), "activities")
    message.className = "form-text text-danger"
    message.textContent = ` ${bounds.max === null ? interpolate(this.labels["activities.capacity_min"], { min: bounds.min }) : interpolate(this.labels["activities.capacity_range"], { min: bounds.min, max: bounds.max })} `
    field.append(message)
  }

  async submitActivity(event, form, panel) {
    event.preventDefault()
    const f = form.elements
    const duration = f.duration.value === "" ? null : Number(f.duration.value)
    if (!f.name.value || duration === null || duration < 1 || f.emoji.value.length > 4 || (!f.capacity.disabled && !this.capacityValid(form))) {
      this.touchedCapacity = true
      return this.renderCapacityError(form)
    }
    const save = form.querySelector("[data-save]")
    this.busy(save, true)
    showFormError(panel, null, "activities")
    const activity = {
      name: f.name.value, emoji: f.emoji.value, description: f.description.value,
      session_format: f.session_format.value, duration, capacity: Number(f.capacity.value),
    }
    const editing = this.editingActivity
    const result = editing
      ? await send("PATCH", `${this.urlValue}/activities/${editing.id}`, { activity })
      : await send("POST", `${this.urlValue}/activities`, { activity })
    this.busy(save, false)
    if (!result.ok) return showFormError(panel, result.error || this.labels["common.error_generic"], "activities")
    window.dispatchEvent(new CustomEvent("catalogue-activity:close"))
    toast("success", this.labels["common.save"])
    this.refresh()
  }

  async deactivateActivity(event) {
    const activity = JSON.parse(event.currentTarget.closest("[data-activity]").dataset.activity)
    const ok = await confirmAsk({
      title: `${this.labels["common.deactivate"]} ${activity.name}?`, body: this.labels["common.confirm"],
      confirmLabel: this.labels["common.deactivate"], danger: true,
    })
    if (!ok) return
    const result = await send("DELETE", `${this.urlValue}/activities/${activity.id}`)
    if (!result.ok) return toast("error", result.error || this.labels["common.error_generic"])
    toast("success", this.labels["common.deactivate"])
    this.refresh()
  }

  // ---- the catalogue picker ----------------------------------------------------
  // The picker itself is the activity-picker controller; this is the
  // dialog around it: "add n", and the blank form instead.

  openPicker() {
    this.pickerSelection = []
    window.dispatchEvent(new CustomEvent("catalogue-picker:open"))
  }

  fillPicker(panel) {
    this.pickerPanel = panel
    this.pickerSelection = []
    this.renderAdopt()
  }

  pickerChanged(event) {
    this.pickerSelection = event.detail.selected
    this.renderAdopt()
  }

  renderAdopt() {
    const count = this.pickerSelection.length
    const add = this.pickerPanel.querySelector("[data-adopt]")
    add.textContent = ` ${interpolate(this.labels["activity_catalogue.add_n"], { count })} `
    add.disabled = count === 0 || this.adopting
  }

  pickerToForm() {
    window.dispatchEvent(new CustomEvent("catalogue-picker:close"))
    this.openActivityForm()
  }

  async adopt() {
    const ids = this.pickerSelection
    if (!ids.length || this.adopting) return
    this.adopting = true
    this.renderAdopt()
    const result = await this.json("POST", `${this.urlValue}/activities/adopt`, { activity_template_ids: ids })
    this.adopting = false
    if (!result.ok) {
      this.renderAdopt()
      return toast("error", result.error || this.labels["common.error_generic"])
    }
    window.dispatchEvent(new CustomEvent("catalogue-picker:close"))
    toast("success", interpolate(this.labels["activity_catalogue.added"], { count: result.body.activities.length }))
    this.refresh()
  }

  // ---- formules -------------------------------------------------------------------

  openPlanForm(event) {
    const card = event?.currentTarget?.closest?.("[data-plan]")
    this.editingPlan = card ? this.dataValue.plans.find((p) => p.id === card.dataset.plan) : null
    window.dispatchEvent(new CustomEvent("catalogue-plan:open"))
  }

  fillPlanForm(panel) {
    const plan = this.editingPlan
    this.planPanel = panel
    this.setTitle(panel, this.labels[plan ? "common.edit" : "contract_types.new"])
    const form = panel.querySelector("[data-plan-form]")
    const f = form.elements
    this.planState = {
      booking_limit: plan?.booking_limit ?? null,
      priority_booking: plan?.priority_booking ?? false,
      unlimited: plan ? plan.unlimited_bookings : true,
    }
    f.name.value = plan?.name ?? ""
    f.description.value = plan?.description ?? ""
    f.billing_period.value = plan?.billing_period ?? "monthly"
    // Held here: render() takes these two fields out of the form when they
    // do not apply (as @if does), and then form.elements no longer has them.
    this.planInputs = { validity: f.validity_days, sessions: f.session_count }
    this.planInputs.validity.value = plan?.validity_days ?? ""
    this.planInputs.sessions.value = plan?.session_count ?? ""
    f.color.value = plan?.color ?? "#4a2a8f"
    f.active.checked = plan ? plan.active : true
    for (const input of form.querySelectorAll("[data-activity-price]")) {
      const row = plan?.activity_prices.find((r) => r.activity_id === input.dataset.activityPrice)
      input.value = row ? String(Number(row.price)) : ""
    }
    for (const input of form.querySelectorAll("[data-pack-price]")) {
      const row = (plan?.pack_prices ?? []).find((r) => r.pack_id === input.dataset.packPrice)
      input.value = row ? String(Number(row.price)) : ""
    }

    const validity = form.querySelector("[data-validity-field]")
    const periodField = f.billing_period.closest(".mb-3")
    const sessions = form.querySelector("[data-sessions-field]")
    const kinds = sessions.parentElement
    const colorText = form.querySelector("[data-color-value]")
    const render = () => {
      if (f.billing_period.value === "custom") periodField.after(validity)
      else validity.remove()
      form.querySelector("#mp-kind-unlimited").checked = this.planState.unlimited
      form.querySelector("#mp-kind-counted").checked = !this.planState.unlimited
      if (this.planState.unlimited) sessions.remove()
      else kinds.append(sessions)
      colorText.textContent = f.color.value
    }
    f.billing_period.addEventListener("change", render)
    form.querySelector("#mp-kind-unlimited").addEventListener("change", () => this.setUnlimited(true, form, render))
    form.querySelector("#mp-kind-counted").addEventListener("change", () => this.setUnlimited(false, form, render))
    f.color.addEventListener("input", render)
    render()
    form.addEventListener("submit", (event) => this.submitPlan(event, form, panel))
  }

  // setUnlimited(): no limit, or a number of sessions — never both.
  setUnlimited(unlimited, form, render) {
    this.planState.unlimited = unlimited
    if (unlimited) {
      this.planInputs.sessions.value = ""
      this.planState.booking_limit = null
    }
    render()
  }

  async submitPlan(event, form, panel) {
    event.preventDefault()
    const f = form.elements
    if (!f.name.value || !f.billing_period.value || !f.color.value) return

    const custom = f.billing_period.value === "custom"
    const { validity: validityInput, sessions: sessionsInput } = this.planInputs
    const validity = validityInput.value === "" ? null : Number(validityInput.value)
    if (custom && !(validity && validity > 0)) return showFormError(panel, this.labels["contract_types.needs_validity"], "plans")
    const sessions = sessionsInput.value === "" ? null : Number(sessionsInput.value)
    if (!this.planState.unlimited && !sessions) return showFormError(panel, this.labels["contract_types.needs_session_count"], "plans")

    const priced = (selector, key) =>
      [...form.querySelectorAll(selector)]
        .filter((input) => input.value !== "" && !Number.isNaN(Number(input.value)) && Number(input.value) >= 0)
        .map((input) => ({ [key]: input.dataset[key === "activity_id" ? "activityPrice" : "packPrice"], price: Number(input.value) }))
    const activity_prices = priced("[data-activity-price]", "activity_id")
    const pack_prices = priced("[data-pack-price]", "pack_id")
    if (!activity_prices.length && !pack_prices.length) return showFormError(panel, this.labels["contract_types.needs_a_price"], "plans")

    const save = form.querySelector("[data-save]")
    this.busy(save, true)
    showFormError(panel, null, "plans")
    const contract_type = {
      name: f.name.value, description: f.description.value, billing_period: f.billing_period.value,
      validity_days: custom ? validity : null, session_count: this.planState.unlimited ? null : sessions,
      unlimited_bookings: this.planState.unlimited, booking_limit: this.planState.booking_limit,
      priority_booking: this.planState.priority_booking, color: f.color.value, active: f.active.checked,
    }
    const editing = this.editingPlan
    const body = { contract_type, activity_prices, pack_prices }
    const result = editing ? await this.json("PATCH", `${this.urlValue}/plans/${editing.id}`, body) : await this.json("POST", `${this.urlValue}/plans`, body)
    this.busy(save, false)
    if (!result.ok) return showFormError(panel, result.error || this.labels["common.error_generic"], "plans")
    window.dispatchEvent(new CustomEvent("catalogue-plan:close"))
    toast("success", this.labels["common.save"])
    this.refresh()
  }

  // ---- packs ------------------------------------------------------------------------

  get canCreatePack() {
    return this.dataValue.activities.filter((a) => a.active).length >= 2
  }

  openPackForm(event) {
    const card = event?.currentTarget?.closest?.("[data-pack]")
    this.editingPack = card ? JSON.parse(card.dataset.pack) : null
    if (!this.editingPack && !this.canCreatePack) return
    window.dispatchEvent(new CustomEvent("catalogue-pack:open"))
  }

  fillPackForm(panel) {
    const pack = this.editingPack
    this.setTitle(panel, this.labels[pack ? "packs.edit" : "packs.new"])
    const form = panel.querySelector("[data-pack-form]")
    const f = form.elements
    f.name.value = pack?.name ?? ""
    f.description.value = pack?.description ?? ""
    f.active.checked = pack ? pack.active : true
    if (!pack) form.querySelector("[data-active-field]").remove()
    this.packSelection = new Set(pack?.activity_ids ?? [])
    this.packPrices = { ...(pack?.prices ?? {}) }
    for (const input of form.querySelectorAll("[data-plan-price]")) {
      const price = this.packPrices[input.dataset.planPrice]
      input.value = price === undefined ? "" : String(price)
      input.addEventListener("input", () => {
        if (input.value === "") delete this.packPrices[input.dataset.planPrice]
        else this.packPrices[input.dataset.planPrice] = Number(input.value)
      })
    }
    for (const button of form.querySelectorAll("[data-pick]")) {
      button.addEventListener("click", () => {
        const id = button.dataset.pick
        if (this.packSelection.has(id)) this.packSelection.delete(id)
        else this.packSelection.add(id)
        this.renderPackPicks(form)
      })
    }
    this.renderPackPicks(form)
    form.addEventListener("submit", (event) => this.submitPack(event, form, panel))
  }

  // The toggles' state, and each formule's "separately" once two are picked.
  renderPackPicks(form) {
    for (const button of form.querySelectorAll("[data-pick]")) {
      const on = this.packSelection.has(button.dataset.pick)
      button.classList.toggle("is-on", on)
      button.setAttribute("aria-pressed", String(on))
      button.querySelector("i")?.remove()
      if (on) {
        const icon = scoped(document.createElement("i"), "packs")
        icon.className = "bi bi-check-lg"
        icon.setAttribute("aria-hidden", "true")
        button.prepend(icon)
      }
    }
    for (const input of form.querySelectorAll("[data-plan-price]")) {
      const plan = this.dataValue.plans.find((p) => p.id === input.dataset.planPrice)
      const label = form.querySelector(`label[for="${input.id}"]`)
      label.querySelector(".pk-sep")?.remove()
      const rows = plan.activity_prices.filter((r) => this.packSelection.has(r.activity_id))
      if (rows.length < 2) continue
      const sum = rows.reduce((total, r) => total + Number(r.price), 0)
      const sep = scoped(document.createElement("span"), "packs")
      sep.className = "pk-sep"
      sep.textContent = interpolate(this.labels["packs.separately"], { amount: this.money(sum, plan.currency) })
      label.append(sep)
    }
  }

  async submitPack(event, form, panel) {
    event.preventDefault()
    const f = form.elements
    if (!f.name.value) return
    if (this.packSelection.size < 2) return showFormError(panel, this.labels["packs.needs_two"], "packs")

    const save = form.querySelector("[data-save]")
    this.busy(save, true)
    showFormError(panel, null, "packs")
    const editing = this.editingPack
    const body = { pack: { name: f.name.value, description: f.description.value, active: f.active.checked }, activity_ids: [...this.packSelection] }
    const saved = editing ? await this.json("PATCH", `${this.urlValue}/packs/${editing.id}`, body) : await this.json("POST", `${this.urlValue}/packs`, body)
    const result = saved.ok ? await this.writePackPrices(saved.body.pack.id) : saved
    this.busy(save, false)
    if (!result.ok) {
      showFormError(panel, result.error || this.labels["common.error_generic"], "packs")
      return this.refresh()
    }
    window.dispatchEvent(new CustomEvent("catalogue-pack:close"))
    toast("success", this.labels["common.save"])
    this.refresh()
  }

  // writePrices(): each active formule whose price for this pack changed.
  async writePackPrices(packId) {
    const updates = this.dataValue.plans.filter((p) => p.active).flatMap((plan) => {
      const rows = (plan.pack_prices ?? []).filter((r) => r.pack_id !== packId)
      const before = (plan.pack_prices ?? []).find((r) => r.pack_id === packId)
      const after = this.packPrices[plan.id]
      const beforePrice = before ? Number(before.price) : undefined
      if (after === beforePrice || (after !== undefined && Number.isNaN(after))) return []
      const pack_prices = rows.map((r) => ({ pack_id: r.pack_id, price: Number(r.price) }))
      if (after !== undefined) pack_prices.push({ pack_id: packId, price: after })
      return [this.json("PATCH", `${this.urlValue}/plans/${plan.id}`, { pack_prices })]
    })
    const results = await Promise.all(updates)
    return results.find((r) => !r.ok) ?? { ok: true }
  }

  async deactivatePack(event) {
    const pack = JSON.parse(event.currentTarget.closest("[data-pack]").dataset.pack)
    const ok = await confirmAsk({
      title: `${this.labels["common.deactivate"]} ${pack.name}?`, body: this.labels["packs.deactivate_body"],
      confirmLabel: this.labels["common.deactivate"], danger: true,
    })
    if (!ok) return
    const result = await send("DELETE", `${this.urlValue}/packs/${pack.id}`)
    if (!result.ok) return toast("error", result.error || this.labels["common.error_generic"])
    toast("success", this.labels["common.deactivate"])
    this.refresh()
  }

  async reactivatePack(event) {
    const pack = JSON.parse(event.currentTarget.closest("[data-pack]").dataset.pack)
    const result = await send("PATCH", `${this.urlValue}/packs/${pack.id}`, { pack: { active: true } })
    if (!result.ok) return toast("error", result.error || this.labels["common.error_generic"])
    toast("success", this.labels["common.save"])
    this.refresh()
  }

  // ---------------------------------------------------------------------------------

  // MoneyPipe.
  money(amount, currency) {
    const formatted = Number.isFinite(amount) ? amount.toFixed(2).replace(/\.00$/, "") : amount
    return `${formatted} ${this.labels.currency_symbols[currency] ?? currency}`
  }

  // send(), keeping the answer's body.
  async json(method, url, body) {
    const response = await fetch(url, {
      method, credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "" },
      body: body === undefined ? undefined : JSON.stringify(body),
    }).catch(() => null)
    if (!response) return { ok: false, error: null }
    const payload = await response.json().catch(() => ({}))
    return response.ok ? { ok: true, body: payload } : { ok: false, error: payload.error ?? null }
  }
}
