import { Controller } from "@hotwired/stimulus"
import { confirmAsk } from "../lib/confirm"
import { reloadList, send, showFormError } from "../lib/crud"

// SpacesComponent's actions: open the form blank or on a room, save it, and
// remove a room — deleted, or only deactivated while sessions are booked in
// it (the backend decides; the confirmation says which up front).
export default class extends Controller {
  static targets = ["card"]
  // fragment: embedded (the onboarding page), the tool reloads itself
  // alone; on its own page, the page.
  static values = { url: String, labels: Object, fragment: String }

  openCreate() {
    this.editing = null
    window.dispatchEvent(new CustomEvent("spaces-modal:open"))
  }

  openEdit(event) {
    this.editing = this.spaceOf(event)
    window.dispatchEvent(new CustomEvent("spaces-modal:open"))
  }

  // modal:opened — the fresh form, filled as openCreate / openEdit reset it.
  fill(event) {
    if (event.detail.name !== "spaces") return
    const panel = event.detail.panel
    this.panel = panel
    const space = this.editing
    const title = space ? this.labelsValue.edit : this.labelsValue.new
    panel.querySelector(".modal-panel-header h3").textContent = title
    panel.setAttribute("aria-label", title)
    const form = panel.querySelector("[data-spaces-form]")
    form.elements.name.value = space?.name ?? ""
    form.elements.kind.value = space?.kind ?? ""
    form.elements.capacity.value = space?.capacity ?? ""
    for (const box of form.querySelectorAll("[data-activity]")) box.checked = Boolean(space?.activity_ids.includes(box.value))
    form.addEventListener("submit", (e) => this.submit(e, form))
  }

  async submit(event, form) {
    event.preventDefault()
    // Validators.required on the name, Validators.min(1) on the capacity.
    const capacity = form.elements.capacity.value
    if (!form.elements.name.value || (capacity !== "" && Number(capacity) < 1)) return

    const save = form.querySelector("[data-save]")
    save.disabled = true
    save.textContent = ` ${this.labelsValue.saving} `
    showFormError(this.panel, null, "spaces")
    const payload = {
      space: {
        name: form.elements.name.value,
        kind: form.elements.kind.value || null,
        capacity: capacity === "" ? null : Number(capacity),
        activity_ids: [...form.querySelectorAll("[data-activity]:checked")].map((box) => box.value),
      },
    }
    const result = this.editing
      ? await send("PATCH", `${this.urlValue}/${this.editing.id}`, payload)
      : await send("POST", this.urlValue, payload)
    if (result.ok) {
      window.dispatchEvent(new CustomEvent("spaces-modal:close"))
      return this.reload()
    }
    save.disabled = false
    save.textContent = ` ${this.labelsValue.save} `
    showFormError(this.panel, result.error, "spaces")
  }

  async remove(event) {
    const space = this.spaceOf(event)
    const deletable = space.deletable
    const ok = await confirmAsk({
      title: deletable ? this.labelsValue.delete_title : this.labelsValue.deactivate_title,
      body: (deletable ? this.labelsValue.delete_message : this.labelsValue.deactivate_message).replace(/{{\s?name\s?}}/, space.name),
      confirmLabel: deletable ? this.labelsValue.delete : this.labelsValue.deactivate,
      danger: true,
    })
    if (!ok) return
    const result = await send("DELETE", `${this.urlValue}/${space.id}`)
    if (result.ok) this.reload()
  }

  // load(): the skeleton in the card, then the rooms as they are now.
  async reload() {
    if (!this.fragmentValue) return reloadList(this.cardTarget, 4, 5)
    const host = this.element.closest("app-spaces")
    reloadList(this.cardTarget, 4, 5, { visit: false })
    const response = await fetch(this.fragmentValue, { credentials: "same-origin" }).catch(() => null)
    if (!response?.ok) return
    const fresh = document.createElement("template")
    fresh.innerHTML = await response.text()
    host.replaceChildren(...fresh.content.childNodes)
  }

  spaceOf(event) {
    return JSON.parse(event.target.closest("tr").dataset.space)
  }
}
