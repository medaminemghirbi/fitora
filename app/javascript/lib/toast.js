import { scoped } from "./ng"

// ToastService#success / #error from the browser: the same markup the
// server's flash renders (web/shared/_toast), into the same stack.
const ICONS = { success: "bi-check-circle-fill", error: "bi-x-circle-fill", info: "bi-info-circle-fill", warning: "bi-exclamation-triangle-fill" }

export function toast(kind, message) {
  const stack = document.getElementById("toasts")
  if (!stack) return
  const item = scoped(document.createElement("div"), "toast-container")
  item.className = `toast-item toast-item--${kind}`
  item.dataset.toastsTarget = "toast"
  const icon = scoped(document.createElement("i"), "toast-container")
  icon.className = `bi ${ICONS[kind]}`
  const text = scoped(document.createElement("span"), "toast-container")
  text.textContent = message
  const close = scoped(document.createElement("button"), "toast-container")
  close.type = "button"
  close.className = "toast-close"
  close.dataset.action = "toasts#dismiss"
  close.setAttribute("aria-label", "Close")
  const x = scoped(document.createElement("i"), "toast-container")
  x.className = "bi bi-x"
  close.append(x)
  item.append(icon, text, close)
  stack.append(item)
}
