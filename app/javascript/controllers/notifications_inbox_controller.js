import { Controller } from "@hotwired/stimulus"
import { csrfToken, scoped } from "../lib/ng"

// NotificationsInboxComponent: every row loaded so far, filtered client-side
// (all / unread); ✓ marks one read, "mark all read" all of them, and the
// unread count follows everywhere it is shown (the header, the filter, the
// bell); "more" appends the next page of ten. An empty filter shows the
// empty state, as `visible().length === 0` does.
export default class extends Controller {
  static targets = ["head", "filterAll", "filterUnread", "list", "more"]
  static values = { url: String, unread: Number, labels: Object }

  connect() {
    this.filter = "all"
    this.rows = this.hasListTarget ? [...this.listTarget.querySelectorAll(".notif-item")] : []
    this.wrap = this.hasListTarget ? this.listTarget : null
    // Kept to put back: out of the DOM while the filter shows nothing, as
    // @if (hasMore()) inside the list's branch leaves it ([hidden] would
    // lose to its display: flex).
    this.more = this.hasMoreTarget ? this.moreTarget : null
    // Live (lib/live_notifications.js): the counts follow the badge's, and
    // a new notification joins the list at the top — the service's items,
    // which this page reads in Angular.
    this.onUnread = (event) => {
      if (event.detail.count === this.unreadValue) return
      this.unreadValue = event.detail.count
      this.render()
    }
    this.onCreated = () => this.prependNew()
    document.addEventListener("notifications:unread", this.onUnread)
    document.addEventListener("notifications:created", this.onCreated)
  }

  disconnect() {
    document.removeEventListener("notifications:unread", this.onUnread)
    document.removeEventListener("notifications:created", this.onCreated)
  }

  async prependNew() {
    const html = await fetch(`${this.urlValue}?page=1&fragment=inbox`, { credentials: "same-origin" }).then((r) => r.text()).catch(() => "")
    const doc = new DOMParser().parseFromString(`<body>${html}</body>`, "text/html")
    const known = new Set(this.rows.map((row) => row.dataset.notificationId))
    const fresh = [...doc.querySelectorAll(".notif-item")].filter((row) => !known.has(row.dataset.notificationId))
    if (fresh.length === 0) return
    this.rows.unshift(...fresh)
    this.render()
  }

  showAll() {
    this.filter = "all"
    this.render()
  }

  showUnread() {
    this.filter = "unread"
    this.render()
  }

  async markRead(event) {
    event.preventDefault()
    event.stopPropagation()
    const row = event.currentTarget.closest(".notif-item")
    const response = await this.send("PATCH", `${this.urlValue}/${row.dataset.notificationId}/read`)
    if (!response) return
    this.read(row)
    this.unreadValue = (await response.json()).unread_count
    this.render()
  }

  async markAllRead() {
    if (!(await this.send("POST", `${this.urlValue}/read_all`))) return
    this.rows.forEach((row) => this.read(row))
    this.unreadValue = 0
    this.render()
  }

  async loadMore(event) {
    const button = event.currentTarget
    button.disabled = true
    button.textContent = ` ${this.labelsValue.loading} `
    const page = this.more.dataset.nextPage
    const html = await fetch(`${this.urlValue}?page=${page}&fragment=inbox`, { credentials: "same-origin" }).then((r) => r.text())
    const doc = new DOMParser().parseFromString(`<body>${html}</body>`, "text/html")
    this.rows.push(...doc.querySelectorAll(".notif-item"))
    const next = doc.querySelector(".notif-inbox-more")
    if (next) {
      this.more.dataset.nextPage = next.dataset.nextPage
      button.disabled = false
      button.textContent = ` ${this.labelsValue.more} `
    } else {
      this.more.remove()
      this.more = null
    }
    this.render()
  }

  // ---------------------------------------------------------------------

  read(row) {
    row.classList.remove("is-unread")
    row.querySelector(".notif-item-read")?.remove()
  }

  render() {
    const visible = this.filter === "unread" ? this.rows.filter((row) => row.classList.contains("is-unread")) : this.rows
    this.filterAllTarget.classList.toggle("is-active", this.filter === "all")
    this.filterUnreadTarget.classList.toggle("is-active", this.filter === "unread")
    this.renderCounts()

    const empty = this.element.querySelector(":scope > .app-card")
    if (visible.length === 0) {
      this.wrap?.remove()
      this.more?.remove()
      if (!empty) this.element.append(document.querySelector('template[data-ni="empty"]').content.cloneNode(true))
      return
    }
    empty?.remove()
    if (!this.wrap) {
      this.wrap = scoped(document.createElement("div"), "notifications-inbox")
      this.wrap.className = "notif-inbox"
    }
    if (!this.wrap.isConnected) this.element.querySelector(".fx-toolbar").after(this.wrap)
    this.wrap.replaceChildren(...visible)
    if (this.more && !this.more.isConnected) this.wrap.after(this.more)
  }

  // The header's count and button, the filter's "(n)", the bell's badge.
  renderCounts() {
    const n = this.unreadValue
    const head = this.headTarget
    head.querySelector(".lst-head-count")?.remove()
    head.querySelector("button")?.remove()
    if (n > 0) {
      const count = scoped(document.createElement("span"), "notifications-inbox")
      count.className = "lst-head-count"
      count.textContent = String(n)
      const button = scoped(document.createElement("button"), "notifications-inbox")
      button.type = "button"
      button.className = "btn btn-sm btn-outline-secondary"
      button.dataset.action = "notifications-inbox#markAllRead"
      button.textContent = ` ${this.labelsValue.mark_all} `
      head.append(count, button)
    }
    this.filterUnreadTarget.textContent = ` ${this.labelsValue.unread} ${n > 0 ? ` (${n}) ` : ""}`
    document.dispatchEvent(new CustomEvent("notifications:unread", { detail: { count: n } }))
  }

  send(method, url) {
    return fetch(url, { method, headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() }, credentials: "same-origin" })
      .then((r) => (r.ok ? r : null)).catch(() => null)
  }
}
