import ServerListController from "./server_list_controller"

// The subscriptions page's list (ServerListController): the work-list tabs,
// the search and the formule filter, re-asked on every change — and again
// whenever a dialog changed a subscription (subscriptions:changed). What a
// row does is the subscriptions controller's.
export default class extends ServerListController {
  static values = { ...ServerListController.values, labels: Object }

  // The tab picked shows as picked at once, before the answer redraws it.
  renderFilters() {
    const status = this.filters.status || ""
    this.element.querySelectorAll("#abo-lists .abo-list").forEach((tab) => {
      const on = tab.dataset.value === status
      tab.classList.toggle("is-active", on)
      tab.setAttribute("aria-pressed", String(on))
    })
  }
}
