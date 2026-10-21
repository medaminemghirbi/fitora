// ConfirmService#ask: the app's one confirmation dialog (ConfirmDialogComponent),
// as a promise — true for the confirm button, false for cancel, the backdrop
// or Escape. Focus is trapped in it the way cdkTrapFocusAutoCapture traps it
// (two tabbable anchors, the first button focused, focus restored after).
export function confirmAsk({ title, body, confirmLabel, cancelLabel, danger = false }) {
  const host = document.querySelector("app-confirm-dialog")
  const labels = JSON.parse(host.dataset.confirmLabels || "{}")
  const backdrop = host.querySelector("template[data-confirm-template]").content.firstElementChild.cloneNode(true)
  const dialog = backdrop.querySelector(".confirm-dialog")
  dialog.setAttribute("aria-label", title)
  dialog.querySelector("h3").textContent = title
  dialog.querySelector("p").textContent = body
  const cancel = dialog.querySelector("[data-confirm-cancel]")
  const ok = dialog.querySelector("[data-confirm-ok]")
  cancel.textContent = ` ${cancelLabel || labels.cancel} `
  ok.textContent = ` ${confirmLabel || labels.confirm} `
  ok.classList.add(danger ? "btn-danger" : "btn-primary")

  const restoreTo = document.activeElement
  const anchor = (onFocus) => {
    const div = document.createElement("div")
    div.tabIndex = 0
    div.className = "cdk-visually-hidden cdk-focus-trap-anchor"
    div.setAttribute("aria-hidden", "true")
    div.addEventListener("focus", onFocus)
    return div
  }
  dialog.before(anchor(() => ok.focus()))
  dialog.after(anchor(() => cancel.focus()))
  host.append(backdrop)
  requestAnimationFrame(() => cancel.focus())

  return new Promise((resolve) => {
    const done = (value) => {
      document.removeEventListener("keydown", onKey)
      backdrop.remove()
      restoreTo?.focus?.()
      resolve(value)
    }
    const onKey = (event) => event.key === "Escape" && done(false)
    document.addEventListener("keydown", onKey)
    backdrop.addEventListener("click", (event) => event.target === backdrop && done(false))
    cancel.addEventListener("click", () => done(false))
    ok.addEventListener("click", () => done(true))
  })
}
