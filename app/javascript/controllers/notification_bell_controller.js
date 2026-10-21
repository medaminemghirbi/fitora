import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { csrfToken } from "../lib/ng"

// NotificationBellComponent: the badge ("9+" past nine) follows the unread
// count; the panel opens with its first page of ten, loads the next as the
// list nears its end, and closes on a click elsewhere or Escape. A row is
// marked read and opens the notification; "see all" opens the inbox.
export default class extends Controller {
  static targets = ["button", "panel", "badge"]
  static values = { url: String, unread: Number, inbox: { type: Boolean, default: true } }

  connect() {
    this.page = 0
    this.hasMore = false
    this.loading = false
    this.onDocumentClick = (event) => {
      if (!event.target.closest("app-notification-bell")) this.close()
    }
    this.onKeydown = (event) => event.key === "Escape" && this.close()
    this.onUnread = (event) => {
      this.unreadValue = event.detail.count
    }
    this.onCreated = () => this.prependNew()
    document.addEventListener("click", this.onDocumentClick)
    document.addEventListener("keydown", this.onKeydown)
    document.addEventListener("notifications:unread", this.onUnread)
    document.addEventListener("notifications:created", this.onCreated)
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("notifications:unread", this.onUnread)
    document.removeEventListener("notifications:created", this.onCreated)
  }

  unreadValueChanged() {
    const n = this.unreadValue
    let badge = this.buttonTarget.querySelector(".notif-bell-badge")
    if (n > 0 && !badge) {
      badge = this.badgeTarget.content.firstElementChild.cloneNode(true)
      this.buttonTarget.append(badge)
    }
    if (n > 0) badge.textContent = n > 9 ? "9+" : String(n)
    else badge?.remove()
    this.renderClear()
  }

  toggle() {
    this.panel ? this.close() : this.open()
  }

  async open() {
    this.emptyNode = this.moreNode = this.footNode = this.clearNode = null
    this.panel = this.panelTarget.content.firstElementChild.cloneNode(true)
    this.panelTarget.after(this.panel)
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.rows = []
    this.renderClear()
    this.renderList()
    await this.fetchPage(1)
  }

  close() {
    this.panel?.remove()
    this.panel = null
    this.buttonTarget.setAttribute("aria-expanded", "false")
  }

  scrolled(event) {
    const el = event.currentTarget
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 120 && this.hasMore && !this.loading) this.fetchPage(this.page + 1)
  }

  async select(event) {
    const row = event.currentTarget
    const { notificationId: id, notificationUrl: url } = row.dataset
    // NotificationService#markRead: nothing to send for one already read.
    const read = row.classList.contains("is-unread") ? this.send("PATCH", `${this.urlValue}/${id}/read`) : null
    this.close()
    // The inbox's page for it (which marks it read itself), or — in a shell
    // without one — what it is about, once the badge there will be right.
    if (this.inboxValue) return Turbo.visit(`${this.urlValue}/${id}`)
    if (read && (await read)) this.unreadValue = Math.max(0, this.unreadValue - 1)
    if (url) Turbo.visit(url)
  }

  seeAll() {
    this.close()
    Turbo.visit(this.urlValue)
  }

  async markAllRead() {
    if (!(await this.send("POST", `${this.urlValue}/read_all`))) return
    for (const row of this.rows) {
      row.classList.remove("is-unread")
      row.querySelector(".notif-row-dot")?.remove()
    }
    this.unreadValue = 0
  }

  // ---------------------------------------------------------------------

  // A notification pushed live (lib/live_notifications.js) joins the open
  // list at the top, as NotificationService#onEvent puts it first in items.
  async prependNew() {
    if (!this.panel) return
    const html = await fetch(`${this.urlValue}?page=1&fragment=panel`, { credentials: "same-origin" }).then((r) => r.text()).catch(() => "")
    const doc = new DOMParser().parseFromString(`<body>${html}</body>`, "text/html")
    const known = new Set(this.rows.map((row) => row.dataset.notificationId))
    const fresh = [...doc.querySelectorAll(".notif-row")].filter((row) => !known.has(row.dataset.notificationId))
    if (fresh.length === 0 || !this.panel) return
    this.rows.unshift(...fresh)
    this.renderList()
  }

  async fetchPage(page) {
    this.loading = true
    this.renderList()
    const html = await fetch(`${this.urlValue}?page=${page}&fragment=panel`, { credentials: "same-origin" }).then((r) => r.text()).catch(() => "")
    const doc = new DOMParser().parseFromString(`<body>${html}</body>`, "text/html")
    this.rows.push(...doc.querySelectorAll(".notif-row"))
    this.hasMore = Boolean(doc.querySelector("[data-has-more]"))
    this.page = page
    this.loading = false
    this.renderList()
  }

  // @for rows @empty { the empty state } · @if (loading) { … } · the foot when there are rows
  renderList() {
    if (!this.panel) return
    const list = this.panel.querySelector(".notif-panel-list")
    const empty = this.emptyNode ??= list.querySelector(".notif-empty")
    const more = this.moreNode ??= list.querySelector(".notif-more")
    list.replaceChildren(...(this.rows.length ? this.rows : [empty]), ...(this.loading ? [more] : []))
    const foot = this.footNode ??= this.panel.querySelector(".notif-panel-foot")
    if (!foot) return
    if (this.rows.length && !foot.isConnected) this.panel.append(foot)
    if (!this.rows.length) foot.remove()
  }

  renderClear() {
    if (!this.panel) return
    const clear = this.clearNode ??= this.panel.querySelector(".notif-panel-clear")
    if (this.unreadValue > 0 && !clear.isConnected) this.panel.querySelector(".notif-panel-head").append(clear)
    if (this.unreadValue === 0) clear.remove()
  }

  send(method, url) {
    return fetch(url, { method, headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() }, credentials: "same-origin" })
      .then((r) => (r.ok ? r : null)).catch(() => null)
  }
}
