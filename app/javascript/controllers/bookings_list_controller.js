import ServerListController from "./server_list_controller"
import { confirmAsk } from "../lib/confirm"
import { send } from "../lib/crud"
import { scoped } from "../lib/ng"
import { toast } from "../lib/toast"

// AdminBookingsComponent: the list (ServerListController) plus what its
// signals redraw at once — the chips, the rail's count and "reset", the
// active tab, the checked pill — and the row actions: remind the member, or
// cancel (confirmed first, then the list again).
export default class extends ServerListController {
  static values = { ...ServerListController.values, labels: Object }

  renderFilters() {
    const f = this.filters
    const labels = this.labelsValue
    const chips = []
    if (f.q) chips.push([`« ${f.q} »`, "q"])
    if (f.status && labels.statuses[f.status]) chips.push([labels.statuses[f.status], "status"])
    if (f.date) chips.push([f.date, "date"])

    this.element.querySelectorAll(".fx-cat-tab").forEach((tab) => tab.classList.toggle("is-active", tab.dataset.value === (f.status || "")))
    const pill = this.element.querySelector(`#booking-status-${f.status || ""}`)
    if (pill) pill.checked = true

    // The rail: its toggle's count, and "reset" while anything is set.
    const toggle = this.element.querySelector(".fx-rail-toggle")
    let count = toggle.querySelector(".fx-rail-toggle-count")
    if (chips.length && !count) {
      count = document.createElement("span")
      count.className = "fx-rail-toggle-count"
      toggle.querySelector(".bi-chevron-down, .bi-chevron-up").before(count)
    }
    if (chips.length) count.textContent = String(chips.length)
    else count?.remove()

    const rail = this.element.querySelector(".fx-rail")
    let reset = rail.querySelector("[data-bookings-reset]")
    if (chips.length && !reset) {
      reset = document.createElement("button")
      reset.type = "button"
      reset.className = "btn btn-sm btn-outline-secondary"
      reset.dataset.action = "bookings-list#reset"
      reset.dataset.bookingsReset = ""
      const icon = document.createElement("i")
      icon.className = "bi bi-arrow-counterclockwise"
      reset.append(icon, ` ${labels.reset} `)
      rail.append(reset)
    } else if (!chips.length) {
      reset?.remove()
    }

    if (this.hasChipsTarget) this.chipsTarget.remove()
    if (chips.length) {
      const row = document.createElement("div")
      row.className = "fx-active-filters p-3 pb-0"
      row.dataset.bookingsListTarget = "chips"
      for (const [label, clear] of chips) {
        const chip = document.createElement("span")
        chip.className = "fx-active-chip"
        const button = document.createElement("button")
        button.type = "button"
        button.dataset.action = "bookings-list#clearChip"
        button.dataset.chip = clear
        button.setAttribute("aria-label", labels.reset)
        const x = document.createElement("i")
        x.className = "bi bi-x"
        button.append(x)
        chip.append(` ${label} `, button)
        row.append(chip)
      }
      this.cardTarget.prepend(row)
    }
  }

  async remind(event) {
    const button = event.currentTarget
    const id = button.closest("tr").dataset.bookingId
    const result = await send("POST", `${this.urlValue}/${id}/remind`)
    result.ok ? toast("success", this.labelsValue.reminder_sent) : toast("error", result.error || this.labelsValue.error)
  }

  async cancel(event) {
    const id = event.currentTarget.closest("tr").dataset.bookingId
    const ok = await confirmAsk({ title: this.labelsValue.cancel_title, body: this.labelsValue.cancel_body, danger: true })
    if (!ok) return
    const result = await send("POST", `${this.urlValue}/${id}/cancel`)
    if (!result.ok) return toast("error", result.error || this.labelsValue.error)
    toast("success", this.labelsValue.confirm)
    this.load()
  }
}
