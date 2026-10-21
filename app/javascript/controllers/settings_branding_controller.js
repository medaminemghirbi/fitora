import { Controller } from "@hotwired/stimulus"
import { saveCompany } from "./settings_company_controller"
import { applyBranding } from "../lib/branding"
import { scoped } from "../lib/ng"
import { toast } from "../lib/toast"

// SettingsBrandingComponent: the logo (previewed before it is sent), the
// colour, the identifier; the contract signature — drawn on the pad or an
// image file — the signatory and the terms. One multipart save, as the
// component's updateBranding sends it (empty, null and false left out);
// then the shell's mark and colour follow (BrandingService#load).
const SCOPE = "settings-branding"

export default class extends Controller {
  static targets = ["form", "body", "logoBox", "colorText", "previewBar", "previewMark", "signatureBlock", "current", "currentHint", "uploadTemplate", "currentTemplate"]
  static values = { url: String, labels: Object }

  connect() {
    this.logo = null
    this.signature = null
    this.removeSignature = false
    this.mode = "draw"
    this.logoUrl = this.hasLogoBoxTarget ? this.logoBoxTarget.querySelector("img")?.getAttribute("src") ?? null : null
    this.signatureUrl = this.hasCurrentTarget ? this.currentTarget.querySelector("img").getAttribute("src") : null
    if (this.hasCurrentTarget) this.current = this.currentTarget
    // The pad as it first came, for drawing again after an upload.
    const pad = this.element.querySelector("app-signature-pad")
    if (pad) this.padTemplate = pad.cloneNode(true)
  }

  // ---- the brand ------------------------------------------------------------

  logoPicked(event) {
    const file = event.target.files?.[0] ?? null
    this.logo = file
    if (!file) return this.showLogo(this.logoUrl)
    const reader = new FileReader()
    reader.onload = () => this.showLogo(reader.result)
    reader.readAsDataURL(file)
  }

  // The picked logo, or the saved one, or the placeholder — in the field's
  // box and in the preview.
  showLogo(src) {
    const place = (box, fallback) => {
      if (!box) return
      if (src) {
        const img = scoped(document.createElement("img"), SCOPE)
        img.src = src
        img.alt = ""
        box.replaceChildren(img)
      } else {
        const icon = scoped(document.createElement("i"), SCOPE)
        icon.className = `bi ${fallback}`
        box.replaceChildren(icon)
      }
    }
    if (this.hasLogoBoxTarget) place(this.logoBoxTarget, "bi-image")
    if (this.hasPreviewMarkTarget) place(this.previewMarkTarget, "bi-lightning-charge-fill")
  }

  colorChanged(event) {
    this.colorTextTarget.textContent = event.target.value
    this.previewBarTarget.style.setProperty("--preview-color", event.target.value)
  }

  // ---- the signature ----------------------------------------------------------

  setMode(event) {
    const mode = event.currentTarget.dataset.mode
    if (mode === this.mode) return
    this.mode = mode
    this.element.querySelectorAll(".branding-signature-head [data-mode]").forEach((tab) => {
      const on = tab.dataset.mode === mode
      tab.classList.toggle("is-active", on)
      tab.setAttribute("aria-selected", String(on))
    })
    this.renderSignature()
  }

  // A stroke finished on the pad, or the pad cleared (null).
  drawn(event) {
    this.choose(event.detail.file)
  }

  signaturePicked(event) {
    const input = event.target
    const file = input.files?.[0] ?? null
    this.signatureError = null
    // PNG or JPEG only — what a PDF can embed.
    if (file && !["image/png", "image/jpeg"].includes(file.type)) {
      this.signatureError = this.labelsValue.type_error
      input.value = ""
      return this.renderSignature()
    }
    this.choose(file)
  }

  choose(file) {
    this.signatureError = null
    this.signature = file
    this.removeSignature = false
    this.signaturePreview = null
    if (!file) return this.renderSignature()
    const reader = new FileReader()
    reader.onload = () => {
      this.signaturePreview = reader.result
      this.renderSignature()
    }
    reader.readAsDataURL(file)
    this.renderSignature()
  }

  clearSignature() {
    this.signature = null
    this.signaturePreview = null
    this.removeSignature = Boolean(this.signatureUrl)
    this.renderSignature()
  }

  // The block under the tabs: the signature on file (kept while a new one
  // is drawn, marked as about to be replaced), then the pad or the file
  // field, then the error.
  renderSignature() {
    const block = this.signatureBlockTarget
    const head = block.querySelector(".branding-signature-head")
    const showCurrent = !this.removeSignature && Boolean(this.signatureUrl)
    if (this.current) {
      if (showCurrent && !this.current.isConnected) head.after(this.current)
      if (!showCurrent) this.current.remove()
      this.current.classList.toggle("is-replaced", Boolean(this.signature))
      this.current.querySelector("[data-settings-branding-target=currentHint]").textContent = ` ${this.signature ? this.labelsValue.will_replace : this.labelsValue.replace_hint} `
    }

    const anchor = this.current?.isConnected ? this.current : head
    const pad = block.querySelector("app-signature-pad")
    const upload = block.querySelector("[data-signature-upload]")
    if (this.mode === "draw") {
      upload?.remove()
      if (!pad) {
        const fresh = this.padTemplate.cloneNode(true)
        anchor.after(fresh, this.drawHint)
      }
    } else {
      if (pad) {
        this.drawHint = pad.nextElementSibling
        pad.remove()
        this.drawHint.remove()
      }
      let box = upload
      if (!box) {
        box = this.uploadTemplateTarget.content.firstElementChild.cloneNode(true)
        box.dataset.signatureUpload = ""
        anchor.after(box)
      }
      box.querySelector(".branding-signature-preview")?.remove()
      if (this.signaturePreview) {
        const preview = scoped(document.createElement("div"), SCOPE)
        preview.className = "branding-signature-preview"
        const img = scoped(document.createElement("img"), SCOPE)
        img.src = this.signaturePreview
        img.alt = this.labelsValue.signature
        preview.append(img)
        box.prepend(preview)
      }
    }

    block.querySelector(":scope > .text-danger")?.remove()
    if (this.signatureError) {
      const error = scoped(document.createElement("div"), SCOPE)
      error.className = "text-danger small mt-1"
      error.textContent = this.signatureError
      block.append(error)
    }
  }

  // ---- saving -----------------------------------------------------------------

  async submit(event) {
    event.preventDefault()
    const f = this.formTarget.elements
    const save = this.formTarget.querySelector("[data-save]")
    save.disabled = true
    save.textContent = ` ${this.labelsValue.saving} `
    this.showError(null)

    const fields = {
      slug: f.slug ? f.slug.value || null : undefined,
      primary_color: f.primary_color ? f.primary_color.value || null : undefined,
      logo: this.logo,
      signature: this.signature,
      remove_signature: this.removeSignature,
      signatory_name: f.signatory_name ? f.signatory_name.value.trim() : undefined,
      contract_terms: f.contract_terms ? f.contract_terms.value.trim() : undefined,
    }
    // The half not on screen is the form's untouched controls in Angular,
    // sent as they were loaded; here they are not on the page at all, so
    // they are not sent — the server keeps them as they are.
    const form = new FormData()
    for (const [key, value] of Object.entries(fields)) {
      if (value === undefined || value === null || value === false) continue
      form.append(`company[${key}]`, value instanceof File ? value : String(value))
    }
    const result = await saveCompany(this.urlValue, form)
    save.disabled = false
    save.textContent = ` ${this.labelsValue.save} `
    if (!result.ok) return this.showError(result.error ?? this.labelsValue.error)

    const company = result.company
    this.logo = null
    this.logoUrl = company.logo_url
    this.showLogo(this.logoUrl)
    this.signature = null
    this.signaturePreview = null
    this.removeSignature = false
    this.signatureUrl = company.signature_url
    if (this.hasSignatureBlockTarget) this.refreshCurrent()
    toast("success", this.labelsValue.saved)
    applyBranding(company)
  }

  // The signature on file after a save: the new image, or none. (The pad
  // keeps its ink and the file fields their names, as in the component.)
  refreshCurrent() {
    if (this.signatureUrl) {
      this.current ??= this.currentTemplateTarget.content.firstElementChild.cloneNode(true)
      this.current.querySelector("img").src = this.signatureUrl
    }
    this.renderSignature()
  }

  // formError: first in the card, above the form.
  showError(message) {
    this.bodyTarget.querySelector(":scope > .alert-danger")?.remove()
    if (!message) return
    const alert = scoped(document.createElement("div"), SCOPE)
    alert.className = "alert alert-danger"
    alert.textContent = message
    this.bodyTarget.prepend(alert)
  }
}
