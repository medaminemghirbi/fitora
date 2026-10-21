import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "../lib/ng"
import { toast } from "../lib/toast"

// MemberProfileComponent's account:
//
// - "your details" opens a form in place, filled with what is on file; all
//   three are required, and an incomplete form is simply not sent (the
//   Angular form marks its fields touched, which shows nothing). Saved, the
//   name at the top follows, the form closes, a toast says so;
// - leaving Fitora: a dialog asking for the password; refused, it says why
//   at its top; done, the sign-in page with the toast.
export default class extends Controller {
  static targets = ["details", "summary", "form", "name", "phone"]
  static values = { url: String, accountUrl: String, labels: Object }

  editDetails() {
    const form = this.formTarget.content.firstElementChild.cloneNode(true)
    const { firstName, lastName, phone } = this.detailsTarget.dataset
    form.elements.first_name.value = firstName
    form.elements.last_name.value = lastName
    form.elements.phone.value = phone
    this.showInDetails(form)
  }

  closeDetails() {
    this.showInDetails(this.summaryTarget.content.cloneNode(true))
  }

  async saveDetails(event) {
    event.preventDefault()
    const form = event.target
    const client = Object.fromEntries(["first_name", "last_name", "phone"].map((name) => [name, form.elements[name].value]))
    if (Object.values(client).some((value) => !value)) return

    const save = form.querySelector("[data-save]")
    save.disabled = true
    save.textContent = ` ${this.labelsValue.saving} `
    const response = await this.send("PATCH", this.urlValue, { client })
    if (!response?.ok) {
      save.disabled = false
      save.textContent = ` ${this.labelsValue.save} `
      return toast("error", (await this.errorOf(response)) || this.labelsValue.error)
    }
    const { client: saved } = await response.json()
    Object.assign(this.detailsTarget.dataset, { firstName: saved.first_name, lastName: saved.last_name, phone: saved.phone ?? "" })
    this.nameTarget.textContent = saved.full_name
    if (this.hasPhoneTarget) this.phoneTarget.textContent = ` · ${saved.phone}`
    this.closeDetails()
    toast("success", this.labelsValue.saved)
  }

  openDelete() {
    window.dispatchEvent(new CustomEvent("member-delete:open"))
  }

  // The dialog is the page's sibling: its form is wired when it opens.
  openedDelete(event) {
    if (event.detail.name !== "member-delete") return
    this.deletePanel = event.detail.panel
    this.deletePanel.querySelector("form").addEventListener("submit", (submit) => this.deleteAccount(submit))
  }

  async deleteAccount(event) {
    event.preventDefault()
    const form = event.target
    const password = form.elements.password.value
    if (!password) return

    const button = form.querySelector("[data-delete]")
    button.disabled = true
    this.showDeleteError(null)
    const response = await this.send("DELETE", this.accountUrlValue, { password })
    if (response?.ok) {
      const { next } = await response.json()
      return window.location.assign(next)
    }
    button.disabled = false
    const body = response ? await response.json().catch(() => null) : null
    this.showDeleteError(body?.error === "password_invalid" ? this.labelsValue.wrong : body?.error || this.labelsValue.error)
  }

  // ---------------------------------------------------------------------

  // Everything in the details card after its title.
  showInDetails(content) {
    const title = this.detailsTarget.querySelector(".mb-card-head")
    while (title.nextSibling) title.nextSibling.remove()
    title.after(content)
  }

  showDeleteError(message) {
    const body = this.deletePanel.querySelector(".modal-panel-body")
    body.querySelector(":scope > .alert")?.remove()
    if (!message) return
    const alert = document.querySelector("template[data-member-profile-delete-error]").content.firstElementChild.cloneNode(true)
    alert.textContent = message
    body.prepend(alert)
  }

  send(method, url, payload) {
    return fetch(url, {
      method,
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      credentials: "same-origin",
      body: JSON.stringify(payload),
    }).catch(() => null)
  }

  async errorOf(response) {
    const body = response ? await response.json().catch(() => null) : null
    return body?.error
  }
}
