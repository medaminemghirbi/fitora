import { Controller } from "@hotwired/stimulus"
import { csrfToken, interpolate } from "../lib/ng"
import { ensureTimezone } from "../lib/places"
import { toast } from "../lib/toast"

// SallesComponent's actions. Switching asks the server, then loads the new
// salle's dashboard (a full load, as the component's reload() does).
// Posting moderators: the salle's picker (rendered by the server, one per
// salle) in the modal — a second moderator-role login replaces the one
// picked, the save waits until something changed — then the cards redrawn
// from the answer. Opening a salle: the form, then its getting-started page.
export default class extends Controller {
  static targets = ["network"]
  static values = { url: String, switchUrl: String, timezone: String, currency: String, multi: Boolean, labels: Object }

  // ---- switching --------------------------------------------------------------

  async switchTo(event) {
    if (this.switching || !this.multiValue) return
    const card = event.currentTarget.closest(".sl-card")
    const button = event.currentTarget
    this.switching = card.dataset.salleId
    this.element.querySelectorAll("[data-salles-switch]").forEach((b) => (b.disabled = true))
    button.lastChild.textContent = ` ${this.labelsValue.switching} `
    const response = await fetch(`${this.switchUrlValue}/${this.switching}`, {
      method: "POST", credentials: "same-origin",
      headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
    }).catch(() => null)
    const payload = await response?.json().catch(() => ({}))
    if (response?.ok && payload?.next) return window.location.assign(payload.next)
    this.switching = null
    this.element.querySelectorAll("[data-salles-switch]").forEach((b) => (b.disabled = false))
    button.lastChild.textContent = ` ${this.labelsValue.switch} `
    toast("error", payload?.error ?? this.labelsValue.error)
  }

  // ---- posting moderators -------------------------------------------------------

  openAssign(event) {
    const card = event.currentTarget.closest(".sl-card")
    this.assigning = { id: card.dataset.salleId, name: card.dataset.salleName }
    window.dispatchEvent(new CustomEvent("salles-assign:open"))
  }

  fill(event) {
    const { name, panel } = event.detail
    if (name === "salles-assign") this.fillAssign(panel)
    else if (name === "salles-create") this.fillCreate(panel)
  }

  fillAssign(panel) {
    const salle = this.assigning
    const title = interpolate(this.labelsValue.assign_title, { name: salle.name })
    panel.querySelector(".modal-panel-header h3").textContent = title
    panel.setAttribute("aria-label", title)
    const template = this.networkTarget.querySelector(`template[data-salle-assign="${salle.id}"]`)
    const body = panel.querySelector(".modal-panel-body")
    body.replaceChildren(template.content.cloneNode(true))
    this.original = new Set(JSON.parse(template.dataset.moderatorIds))
    this.boxes = [...body.querySelectorAll(".sl-pick input[type=checkbox]")]
    this.saveButton = body.querySelector("[data-assign-save]")
    this.cancelButton = body.querySelector("[data-assign-cancel]")
    for (const box of this.boxes) box.addEventListener("change", () => this.toggle(box))
    this.cancelButton?.addEventListener("click", () => this.closeAssign())
    this.saveButton?.addEventListener("click", () => this.saveModerators())
    this.renderAssign()
  }

  // One login on the moderator role per salle: ticking a second one
  // unticks the first.
  toggle(box) {
    if (box.checked && box.dataset.roleKey === "moderator") {
      for (const other of this.boxes) if (other !== box && other.dataset.roleKey === "moderator") other.checked = false
    }
    this.renderAssign()
  }

  get picked() {
    return new Set(this.boxes.filter((box) => box.checked).map((box) => box.value))
  }

  get dirty() {
    const picked = this.picked
    return picked.size !== this.original.size || [...this.original].some((id) => !picked.has(id))
  }

  renderAssign() {
    if (!this.saveButton) return
    const saving = Boolean(this.savingModerators)
    for (const box of this.boxes) box.disabled = box.hasAttribute("data-only-salle") || saving
    this.cancelButton.disabled = saving
    this.saveButton.disabled = !this.dirty || saving
    this.saveButton.textContent = ` ${saving ? this.labelsValue.saving : this.labelsValue.save} `
  }

  closeAssign() {
    if (this.savingModerators) return
    window.dispatchEvent(new CustomEvent("salles-assign:close"))
  }

  async saveModerators() {
    const salle = this.assigning
    if (!salle || this.savingModerators || !this.dirty) return
    this.savingModerators = true
    this.lockModal("salles-assign", true)
    this.renderAssign()
    const response = await fetch(`${this.urlValue}/${salle.id}/moderators`, {
      method: "PUT", credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "text/html, application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ user_ids: [...this.picked] }),
    }).catch(() => null)
    this.savingModerators = false
    this.lockModal("salles-assign", false)
    if (response?.ok) {
      this.networkTarget.innerHTML = await response.text()
      this.assigning = null
      window.dispatchEvent(new CustomEvent("salles-assign:close"))
      return toast("success", interpolate(this.labelsValue.saved, { name: salle.name }))
    }
    const payload = await response?.json().catch(() => ({}))
    this.renderAssign()
    toast("error", payload?.error ?? this.labelsValue.error)
  }

  // ---- opening a salle ------------------------------------------------------------

  openCreate() {
    if (!this.multiValue) return
    this.createError = null
    window.dispatchEvent(new CustomEvent("salles-create:open"))
  }

  fillCreate(panel) {
    this.createPanel = panel
    const form = panel.querySelector("[data-salles-create]")
    const select = form.elements.timezone
    for (const group of ensureTimezone(this.timezoneValue)) {
      const optgroup = document.createElement("optgroup")
      optgroup.setAttribute("_ngcontent-salles", "")
      optgroup.label = group.region
      for (const zone of group.zones) {
        const option = new Option(zone.label, zone.value)
        option.setAttribute("_ngcontent-salles", "")
        optgroup.append(option)
      }
      select.append(optgroup)
    }
    select.value = this.timezoneValue
    panel.querySelector("[data-salles-cancel]").addEventListener("click", () => {
      if (!this.savingSalle) window.dispatchEvent(new CustomEvent("salles-create:close"))
    })
    // [class.is-invalid]: touched (left once, or submitted) and empty.
    const name = form.elements.name
    const mark = () => name.classList.toggle("is-invalid", this.nameTouched && !name.value)
    this.nameTouched = false
    name.addEventListener("blur", () => {
      this.nameTouched = true
      mark()
    })
    name.addEventListener("input", mark)
    this.markName = mark
    form.addEventListener("submit", (e) => {
      e.preventDefault()
      this.submitCreate(form)
    })
  }

  async submitCreate(form) {
    const f = form.elements
    // Validators.required on the name and the timezone (markAllAsTouched).
    if (!f.name.value || !f.timezone.value) {
      this.nameTouched = true
      return this.markName()
    }
    if (this.savingSalle) return
    this.savingSalle = true
    this.lockModal("salles-create", true)
    this.renderCreate(form)
    const response = await fetch(this.urlValue, {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify({ company: { name: f.name.value, city: f.city.value, phone: f.phone.value, timezone: f.timezone.value, currency: this.currencyValue } }),
    }).catch(() => null)
    const payload = await response?.json().catch(() => ({}))
    if (response?.ok && payload?.next) return window.location.assign(payload.next)
    this.savingSalle = false
    this.lockModal("salles-create", false)
    // The plan changed since the page loaded: said in the gym's words.
    this.createError = payload?.error === "multi_salle_not_included" ? this.labelsValue.needs_pro_refused : (payload?.error ?? this.labelsValue.error)
    this.renderCreate(form)
  }

  renderCreate(form) {
    const body = this.createPanel.querySelector(".modal-panel-body")
    body.querySelector(":scope > .alert-danger")?.remove()
    if (this.createError) {
      const alert = document.createElement("div")
      alert.setAttribute("_ngcontent-salles", "")
      alert.className = "alert alert-danger"
      alert.textContent = this.createError
      body.prepend(alert)
    }
    const saving = Boolean(this.savingSalle)
    form.querySelector("[data-salles-cancel]").disabled = saving
    const save = form.querySelector("[data-save]")
    save.disabled = saving
    save.textContent = ` ${saving ? this.labelsValue.creating : this.labelsValue.create} `
  }

  // closeAssign / closeCreate ignore the backdrop and Escape while saving.
  lockModal(name, busy) {
    const host = document.querySelector(`app-modal[data-modal-name-value="${name}"]`)
    if (busy) host.dataset.modalBusy = ""
    else delete host.dataset.modalBusy
  }
}
