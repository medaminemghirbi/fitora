import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { csrfToken, scoped, spinner } from "../lib/ng"

// AdminSupportComponent's form: the button opens once subject and message
// say something; up to five files (images, PDF, video, 100 MB each), listed
// under the drop zone with a way to take each back; sending posts them all
// and the server answers with the new history and a toast.
const MAX_FILES = 5
const MAX_FILE_SIZE = 100 * 1024 * 1024
const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif", "application/pdf", "video/mp4", "video/quicktime", "video/webm"]
const SCOPE = "admin-support"

export default class extends Controller {
  static targets = ["subject", "message", "files", "submit"]
  static values = { url: String, labels: Object }

  connect() {
    this.chosen = []
    this.submitting = false
    this.icon = this.submitTarget.querySelector("i")
  }

  changed() {
    this.renderButton()
  }

  picked(event) {
    const input = event.target
    const picked = [...(input.files ?? [])]
    input.value = ""
    const combined = [...this.chosen, ...picked]
    if (combined.length > MAX_FILES) return this.error(this.labelsValue.too_many)
    const invalid = picked.find((f) => !ALLOWED_TYPES.includes(f.type) || f.size > MAX_FILE_SIZE)
    if (invalid) return this.error(this.labelsValue.invalid.replace(/{{\s?name\s?}}/, invalid.name))
    this.error(null)
    this.chosen = combined
    this.renderFiles()
  }

  async submit() {
    const subject = this.subjectTarget.value.trim()
    const message = this.messageTarget.value.trim()
    if (!subject || !message || this.submitting) return

    this.submitting = true
    this.renderButton()
    const body = new FormData()
    body.append("subject", subject)
    body.append("message", message)
    this.chosen.forEach((file) => body.append("attachments[]", file))
    const response = await fetch(this.urlValue, {
      method: "POST", body, credentials: "same-origin",
      headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": csrfToken() },
    }).catch(() => null)
    this.submitting = false
    if (response) Turbo.renderStreamMessage(await response.text())
    if (response?.ok) {
      this.subjectTarget.value = ""
      this.messageTarget.value = ""
      this.chosen = []
      this.renderFiles()
    }
    this.renderButton()
  }

  remove(event) {
    this.chosen.splice(Number(event.currentTarget.dataset.index), 1)
    this.error(null)
    this.renderFiles()
  }

  // ---------------------------------------------------------------------

  renderButton() {
    const ready = this.subjectTarget.value.trim() && this.messageTarget.value.trim()
    this.submitTarget.disabled = this.submitting || !ready
    this.submitTarget.firstElementChild.replaceWith(this.submitting ? spinner(16, SCOPE) : this.icon)
  }

  error(text) {
    this.filesTarget.querySelector(".contact-file-error")?.remove()
    if (!text) return
    const p = scoped(document.createElement("p"), SCOPE)
    p.className = "contact-file-error"
    p.textContent = text
    this.filesTarget.querySelector("input[type=file]").after(p)
  }

  renderFiles() {
    this.filesTarget.querySelector(".contact-file-list")?.remove()
    if (!this.chosen.length) return
    const list = scoped(document.createElement("ul"), SCOPE)
    list.className = "contact-file-list"
    this.chosen.forEach((file, i) => {
      const li = scoped(document.createElement("li"), SCOPE)
      const icon = scoped(document.createElement("i"), SCOPE)
      icon.className = `bi${file.type.startsWith("image/") ? " bi-file-earmark-image" : ""}${file.type.startsWith("video/") ? " bi-file-earmark-play" : ""}${file.type === "application/pdf" ? " bi-file-earmark-pdf" : ""}`
      const name = scoped(document.createElement("span"), SCOPE)
      name.className = "contact-file-name"
      name.textContent = file.name
      const button = scoped(document.createElement("button"), SCOPE)
      button.type = "button"
      button.className = "icon-btn"
      button.dataset.action = "support-form#remove"
      button.dataset.index = String(i)
      button.setAttribute("aria-label", this.labelsValue.cancel)
      const x = scoped(document.createElement("i"), SCOPE)
      x.className = "bi bi-x-lg"
      button.append(x)
      li.append(icon, name, button)
      list.append(li)
    })
    this.filesTarget.append(list)
  }
}
