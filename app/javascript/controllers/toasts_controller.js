import { Controller } from "@hotwired/stimulus"

// ToastContainerComponent + ToastService: each toast goes after 4 seconds,
// or at once with its ×.
export default class extends Controller {
  static targets = ["toast"]

  toastTargetConnected(toast) {
    toast._timer = setTimeout(() => toast.remove(), 4000)
  }

  toastTargetDisconnected(toast) {
    clearTimeout(toast._timer)
  }

  dismiss(event) {
    event.currentTarget.closest("[data-toasts-target~=toast]")?.remove()
  }
}
