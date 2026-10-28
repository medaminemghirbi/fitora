import { Controller } from "@hotwired/stimulus"
import { confirmAsk } from "../lib/confirm"
import { csrfToken } from "../lib/ng"
import { toast } from "../lib/toast"

// The member's photo on their file: taken with the desk's webcam (or the
// tablet's camera), or picked from a file — either way cropped square and
// shrunk to SIZE pixels here, so what reaches the server is a small JPEG,
// never a 12-megapixel original. A phone without getUserMedia goes straight
// to its own camera through the file input (capture="user").
const SIZE = 480
const QUALITY = 0.85

export default class extends Controller {
  static targets = ["file"]
  static values = { url: String, hasPhoto: Boolean, labels: Object }

  disconnect() {
    this.close()
  }

  open() {
    if (!navigator.mediaDevices?.getUserMedia) return this.fileTarget.click()
    this.dialog = this.buildDialog()
    document.body.append(this.dialog)
    this.dialog.querySelector("button").focus()
  }

  close() {
    this.stopCamera()
    this.dialog?.remove()
    this.dialog = null
  }

  // ---- the dialog ------------------------------------------------------------------------

  buildDialog() {
    const backdrop = el("div", "mph-backdrop")
    backdrop.addEventListener("click", (event) => { if (event.target === backdrop) this.close() })
    backdrop.addEventListener("keydown", (event) => { if (event.key === "Escape") this.close() })
    const panel = el("div", "mph-panel")
    panel.setAttribute("role", "dialog")
    panel.setAttribute("aria-modal", "true")
    panel.setAttribute("aria-label", this.labelsValue.title)
    const title = el("h3", "mph-title", this.labelsValue.title)
    this.video = el("video", "mph-video")
    this.video.playsInline = true
    this.video.muted = true
    this.video.hidden = true
    const actions = el("div", "mph-actions")
    this.takeButton = button(this.labelsValue.take, "bi-camera", "btn btn-primary", () => this.startCamera())
    actions.append(
      this.takeButton,
      button(this.labelsValue.choose, "bi-folder2-open", "btn btn-outline-secondary", () => { this.close(); this.fileTarget.click() }),
    )
    if (this.hasPhotoValue) actions.append(button(this.labelsValue.remove, "bi-trash", "btn btn-outline-danger", () => this.remove()))
    actions.append(button(this.labelsValue.cancel, null, "btn btn-ghost", () => this.close()))
    panel.append(title, this.video, actions)
    backdrop.append(panel)
    return backdrop
  }

  async startCamera() {
    if (this.stream) return this.capture()
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user", width: 1280, height: 720 }, audio: false })
    } catch {
      return toast("error", this.labelsValue.camera_error)
    }
    this.video.srcObject = this.stream
    this.video.hidden = false
    await this.video.play().catch(() => {})
    this.takeButton.replaceChildren(icon("bi-record-circle"), document.createTextNode(` ${this.labelsValue.capture}`))
  }

  stopCamera() {
    this.stream?.getTracks().forEach((track) => track.stop())
    this.stream = null
  }

  capture() {
    const canvas = square(this.video, this.video.videoWidth, this.video.videoHeight)
    this.close()
    canvas.toBlob((blob) => this.upload(blob), "image/jpeg", QUALITY)
  }

  // ---- a file --------------------------------------------------------------------------------

  picked() {
    const file = this.fileTarget.files[0]
    this.fileTarget.value = ""
    if (!file) return
    const image = new Image()
    const url = URL.createObjectURL(file)
    image.onload = () => {
      URL.revokeObjectURL(url)
      square(image, image.naturalWidth, image.naturalHeight).toBlob((blob) => this.upload(blob), "image/jpeg", QUALITY)
    }
    image.onerror = () => {
      URL.revokeObjectURL(url)
      toast("error", this.labelsValue.error)
    }
    image.src = url
  }

  // ---- the server ------------------------------------------------------------------------

  async upload(blob) {
    if (!blob) return toast("error", this.labelsValue.error)
    const body = new FormData()
    body.append("photo", blob, "photo.jpg")
    const response = await fetch(this.urlValue, {
      method: "POST", credentials: "same-origin", body,
      headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
    }).catch(() => null)
    if (!response?.ok) {
      const payload = await response?.json().catch(() => ({}))
      return toast("error", payload?.error ?? this.labelsValue.error)
    }
    toast("success", this.labelsValue.saved)
    window.dispatchEvent(new CustomEvent("member-photo:changed"))
  }

  async remove() {
    this.close()
    const ok = await confirmAsk({ title: this.labelsValue.remove, body: this.labelsValue.title, danger: true })
    if (!ok) return
    const response = await fetch(this.urlValue, {
      method: "DELETE", credentials: "same-origin", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
    }).catch(() => null)
    if (!response?.ok) return toast("error", this.labelsValue.error)
    toast("success", this.labelsValue.removed)
    window.dispatchEvent(new CustomEvent("member-photo:changed"))
  }
}

// The middle square of a picture, SIZE pixels wide.
function square(source, width, height) {
  const side = Math.min(width, height)
  const canvas = document.createElement("canvas")
  canvas.width = SIZE
  canvas.height = SIZE
  canvas.getContext("2d").drawImage(source, (width - side) / 2, (height - side) / 2, side, side, 0, 0, SIZE, SIZE)
  return canvas
}

function el(tag, className, text) {
  const element = document.createElement(tag)
  element.className = className
  if (text) element.textContent = text
  return element
}

function icon(name) {
  const i = el("i", `bi ${name}`)
  i.setAttribute("aria-hidden", "true")
  return i
}

function button(label, iconName, className, onClick) {
  const element = el("button", className)
  element.type = "button"
  if (iconName) element.append(icon(iconName), document.createTextNode(" "))
  element.append(document.createTextNode(label))
  element.addEventListener("click", onClick)
  return element
}
