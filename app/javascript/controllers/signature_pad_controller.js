import { Controller } from "@hotwired/stimulus"

// SignaturePadComponent: a signature drawn with a mouse, a finger or a
// stylus at the screen's pixel density, handed out (signature-pad:signed)
// as a PNG File cropped to the ink on a transparent background — after
// every stroke, and null once cleared.
const INK = "#1d1533"
const LINE_WIDTH = 2.6
const TRIM_PADDING = 12

export default class extends Controller {
  static targets = ["canvas", "hint", "clear"]
  static values = { filename: { type: String, default: "signature.png" } }

  connect() {
    this.empty = true
    this.bounds = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity }
    this.ratio = 1
    this.hint = this.hintTarget
    this.fit()
    const canvas = this.canvasTarget
    this.handlers = {
      pointerdown: (e) => this.start(e),
      pointermove: (e) => this.move(e),
      pointerup: (e) => this.end(e),
      pointercancel: (e) => this.end(e),
    }
    for (const [type, handler] of Object.entries(this.handlers)) canvas.addEventListener(type, handler)
  }

  disconnect() {
    for (const [type, handler] of Object.entries(this.handlers ?? {})) this.canvasTarget.removeEventListener(type, handler)
  }

  clear() {
    const canvas = this.canvasTarget
    this.pen.save()
    this.pen.setTransform(1, 0, 0, 1, 0, 0)
    this.pen.clearRect(0, 0, canvas.width, canvas.height)
    this.pen.restore()
    this.bounds = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity }
    this.setEmpty(true)
    this.dispatch("signed", { detail: { file: null } })
  }

  // The empty paper says how to sign; the eraser waits for ink.
  setEmpty(empty) {
    this.empty = empty
    this.canvasTarget.parentElement.classList.toggle("is-empty", empty)
    this.clearTarget.disabled = empty
    if (empty && !this.hint.isConnected) this.canvasTarget.after(this.hint)
    else if (!empty) this.hint.remove()
  }

  fit() {
    const canvas = this.canvasTarget
    this.ratio = Math.max(window.devicePixelRatio || 1, 1)
    const rect = canvas.getBoundingClientRect()
    const width = Math.max(Math.round(rect.width * this.ratio), 1)
    const height = Math.max(Math.round(rect.height * this.ratio), 1)
    if (this.pen && canvas.width === width && canvas.height === height) return
    canvas.width = width
    canvas.height = height
    // Not this.context: that is the Stimulus controller's own, and its
    // targets are read through it.
    this.pen = canvas.getContext("2d")
    this.pen.setTransform(this.ratio, 0, 0, this.ratio, 0, 0)
    this.pen.strokeStyle = INK
    this.pen.fillStyle = INK
    this.pen.lineWidth = LINE_WIDTH
    this.pen.lineCap = "round"
    this.pen.lineJoin = "round"
  }

  point(event) {
    const rect = this.canvasTarget.getBoundingClientRect()
    return { x: event.clientX - rect.left, y: event.clientY - rect.top }
  }

  start(event) {
    if (event.button !== 0 && event.pointerType === "mouse") return
    event.preventDefault()
    if (this.empty) this.fit()
    this.canvasTarget.setPointerCapture?.(event.pointerId)
    this.drawing = true
    const p = this.point(event)
    this.last = p
    this.lastMid = p
    this.track(p)
    this.pen.beginPath()
    this.pen.arc(p.x, p.y, LINE_WIDTH / 2, 0, Math.PI * 2)
    this.pen.fill()
  }

  move(event) {
    if (!this.drawing || !this.last || !this.lastMid) return
    event.preventDefault()
    const p = this.point(event)
    const mid = { x: (this.last.x + p.x) / 2, y: (this.last.y + p.y) / 2 }
    this.pen.beginPath()
    this.pen.moveTo(this.lastMid.x, this.lastMid.y)
    this.pen.quadraticCurveTo(this.last.x, this.last.y, mid.x, mid.y)
    this.pen.stroke()
    this.last = p
    this.lastMid = mid
    this.track(p)
  }

  end(event) {
    if (!this.drawing) return
    this.drawing = false
    this.canvasTarget.releasePointerCapture?.(event.pointerId)
    this.last = null
    this.lastMid = null
    this.setEmpty(false)
    this.export()
  }

  track(p) {
    this.bounds.minX = Math.min(this.bounds.minX, p.x)
    this.bounds.minY = Math.min(this.bounds.minY, p.y)
    this.bounds.maxX = Math.max(this.bounds.maxX, p.x)
    this.bounds.maxY = Math.max(this.bounds.maxY, p.y)
  }

  export() {
    const source = this.canvasTarget
    const pad = TRIM_PADDING
    const x = Math.max(Math.floor((this.bounds.minX - pad) * this.ratio), 0)
    const y = Math.max(Math.floor((this.bounds.minY - pad) * this.ratio), 0)
    const width = Math.min(Math.ceil((this.bounds.maxX - this.bounds.minX + pad * 2) * this.ratio), source.width - x)
    const height = Math.min(Math.ceil((this.bounds.maxY - this.bounds.minY + pad * 2) * this.ratio), source.height - y)
    const crop = document.createElement("canvas")
    crop.width = Math.max(width, 1)
    crop.height = Math.max(height, 1)
    crop.getContext("2d").drawImage(source, x, y, crop.width, crop.height, 0, 0, crop.width, crop.height)
    crop.toBlob((blob) => {
      if (blob) this.dispatch("signed", { detail: { file: new File([blob], this.filenameValue, { type: "image/png" }) } })
    }, "image/png")
  }
}
