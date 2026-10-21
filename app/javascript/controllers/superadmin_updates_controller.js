import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { csrfToken, interpolate } from "../lib/ng"

const MAX_FILES = 8
const MAX_FILE_SIZE = 100 * 1024 * 1024
const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif", "video/mp4", "video/quicktime", "video/webm"]

// SuperadminUpdatesComponent's drawer: version and title required (the
// button waits for both), the files checked as they are picked — eight at
// most, images and videos up to 100 MB — and listed, each removable; then
// published, the page coming back with the new release first and the toast.
// A refusal is said at the top of the drawer.
export default class extends Controller {
  static values = { url: String, labels: Object }

  openCreate() {
    window.dispatchEvent(new CustomEvent("update-create:open"))
  }

  opened(event) {
    if (event.detail.name !== "update-create") return
    this.drawer = event.detail.panel
    this.host = this.drawer.closest("app-drawer")
    this.files = []
    this.form = this.drawer.querySelector("#update-form")
    this.submitButton = this.drawer.querySelector("[data-update-submit]")
    this.form.addEventListener("input", () => this.refreshSubmit())
    this.form.querySelector("#update-files").addEventListener("change", (change) => this.pick(change.target))
    this.form.addEventListener("submit", (submit) => this.submit(submit))
  }

  pick(input) {
    const picked = [...(input.files ?? [])]
    input.value = ""
    const combined = [...this.files, ...picked]
    if (combined.length > MAX_FILES) return this.fileError(interpolate(this.labelsValue.too_many, { max: MAX_FILES }))
    const invalid = picked.find((f) => !ALLOWED_TYPES.includes(f.type) || f.size > MAX_FILE_SIZE)
    if (invalid) return this.fileError(interpolate(this.labelsValue.invalid, { name: invalid.name }))

    this.fileError(null)
    this.files = combined
    this.renderFiles()
  }

  async submit(event) {
    event.preventDefault()
    const version = this.form.elements.version.value.trim()
    const title = this.form.elements.title.value.trim()
    if (!version || !title) return

    this.saving(true)
    this.formError(null)
    const data = new FormData()
    data.append("app_update[version]", version)
    data.append("app_update[title]", title)
    data.append("app_update[description]", this.form.elements.description.value.trim())
    this.files.forEach((file) => data.append("media[]", file))
    const response = await fetch(this.urlValue, { method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() }, credentials: "same-origin", body: data }).catch(() => null)
    if (response?.ok) return Turbo.visit(this.urlValue, { action: "replace" })

    this.saving(false)
    const body = response ? await response.json().catch(() => null) : null
    this.formError(body?.error || this.labelsValue.error)
  }

  // ---------------------------------------------------------------------

  refreshSubmit() {
    if (this.busy) return
    this.submitButton.disabled = !this.form.elements.version.value.trim() || !this.form.elements.title.value.trim()
  }

  saving(on) {
    this.busy = on
    const icon = this.submitButton.firstElementChild
    icon.replaceWith(on ? this.template("spinner").firstElementChild : Object.assign(document.createElement("i"), { className: "bi bi-broadcast" }))
    if (!on) this.submitButton.firstElementChild.setAttribute(this.scopeAttr(), "")
    this.submitButton.disabled = on
    if (!on) this.refreshSubmit()
  }

  renderFiles() {
    const zone = this.form.querySelector("#update-files").parentElement
    zone.querySelector(".update-file-list")?.remove()
    if (!this.files.length) return
    const list = this.template("file-list").firstElementChild
    this.files.forEach((file, index) => {
      const item = this.template("file-item").firstElementChild
      const icon = item.querySelector("i")
      icon.classList.toggle("bi-file-earmark-image", file.type.startsWith("image/"))
      icon.classList.toggle("bi-file-earmark-play", file.type.startsWith("video/"))
      item.querySelector(".update-file-name").textContent = file.name
      item.querySelector("button").addEventListener("click", () => {
        this.files.splice(index, 1)
        this.fileError(null)
        this.renderFiles()
      })
      list.append(item)
    })
    zone.append(list)
  }

  fileError(message) {
    const zone = this.form.querySelector("#update-files").parentElement
    zone.querySelector(".update-file-error")?.remove()
    if (!message) return
    const line = this.template("file-error").firstElementChild
    line.textContent = message
    this.form.querySelector("#update-files").after(line)
  }

  formError(message) {
    const body = this.drawer.querySelector(".fx-drawer-body")
    body.querySelector(":scope > .alert")?.remove()
    if (!message) return
    const alert = this.template("error").firstElementChild
    alert.textContent = message
    body.prepend(alert)
  }

  template(name) {
    return this.host.querySelector(`template[data-update-${name}]`).content.cloneNode(true)
  }

  scopeAttr() {
    return [...this.submitButton.attributes].find((a) => a.name.startsWith("_ngcontent-"))?.name ?? "_ngcontent-superadmin-updates"
  }
}
