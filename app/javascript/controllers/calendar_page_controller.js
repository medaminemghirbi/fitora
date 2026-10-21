import { Controller } from "@hotwired/stimulus"
import { Calendar } from "@fullcalendar/core"
import dayGridPlugin from "@fullcalendar/daygrid"
import timeGridPlugin from "@fullcalendar/timegrid"
import listPlugin from "@fullcalendar/list"
import interactionPlugin from "@fullcalendar/interaction"
import frLocale from "@fullcalendar/core/locales/fr"
import arLocale from "@fullcalendar/core/locales/ar"
import { confirmAsk } from "../lib/confirm"
import { csrfToken, downloadBlob, interpolate, scoped, spinner } from "../lib/ng"
import { statusTone } from "../lib/status_tone"
import { toast } from "../lib/toast"

// CalendarComponent: FullCalendar (the same version) with the component's
// options and callbacks — the page's own toolbar and filters, events read
// from the server for the range on screen, each block laid out as the
// component lays it out, the hover card, the session detail (attendance,
// adding a member, stopping a series, cancelling), the "new session" dialog
// (one session or a weekly class) and moving a session by drag and drop.
const SCOPE = "calendar"
const CAPACITY_BOUNDS = { individual: { min: 1, max: 1 }, small_group: { min: 2, max: 9 }, collective: { min: 10, max: null } }

// A local calendar date, not UTC (toDateInputValue).
function toDateInputValue(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`
}

export default class extends Controller {
  static targets = ["calendar", "title", "resetTemplate", "spinnerTemplate"]
  static values = { url: String, manage: Boolean, locale: String, rtl: Boolean, hours: Object, activities: Array, clients: Array, dropIn: Boolean, labels: Object }

  connect() {
    this.coachFilter = ""
    this.activityFilter = ""
    this.viewMode = window.innerWidth < 992 ? "timeGridDay" : "timeGridWeek"
    this.drawViewButtons()
    const hours = this.hoursValue
    this.businessStart = hours.start || "06:00"
    this.businessEnd = hours.end || "22:00"
    this.workingDays = hours.days ?? [0, 1, 2, 3, 4, 5, 6]

    // Built the way the Angular page builds it, in its order — not merely to
    // the same end: FullCalendar keeps the 06:00–22:00 grid's height when
    // the salle's hours arrive (expandRows), so the rows stretch to fill it.
    // That stretch is what the Angular page shows (K-09); the hours and the
    // closed days come in one batch after the first render, as the
    // company's answer brings them there.
    this.calendar = new Calendar(this.calendarTarget, {
      plugins: [dayGridPlugin, timeGridPlugin, listPlugin, interactionPlugin],
      locales: [frLocale, arLocale],
      initialView: this.viewMode,
      headerToolbar: false,
      height: "auto",
      slotMinTime: "06:00",
      slotMaxTime: "22:00",
      allDaySlot: false,
      slotDuration: "00:30:00",
      slotLabelInterval: "01:00",
      slotLabelFormat: { hour: "2-digit", minute: "2-digit", hour12: false },
      expandRows: true,
      slotEventOverlap: false,
      dayMaxEvents: 3,
      nowIndicator: true,
      selectable: this.manageValue,
      editable: this.manageValue,
      eventContent: (arg) => this.renderEvent(arg),
      eventClick: (arg) => this.openDetail(arg.event.extendedProps.session),
      eventMouseEnter: (arg) => this.showPreview(arg),
      eventMouseLeave: () => this.hidePreview(),
      eventDrop: (arg) => this.onEventDrop(arg),
      dateClick: (arg) => this.onDateClick(arg.date, arg.dayEl),
      datesSet: (arg) => this.onDatesSet(arg.start, arg.end),
      direction: this.rtlValue ? "rtl" : "ltr",
      locale: this.localeValue,
    })
    this.calendar.render()
    setTimeout(() => this.calendar?.updateSize())
    // datesSet adds the event source; then the salle's hours (applyBusinessHours).
    this.batch({ events: (info, success, failure) => this.fetchEvents(info, success, failure) })
    const today = new Date().getDay()
    const closedDays = [0, 1, 2, 3, 4, 5, 6].filter((day) => !this.workingDays.includes(day) && day !== today)
    this.batch({
      slotMinTime: this.businessStart,
      slotMaxTime: this.businessEnd,
      businessHours: { daysOfWeek: this.workingDays, startTime: this.businessStart, endTime: this.businessEnd },
      hiddenDays: closedDays,
    })
  }

  // The Angular wrapper's way of applying changed options: rendering paused,
  // the changes reset together, rendering resumed.
  batch(options) {
    this.calendar.pauseRendering()
    this.calendar.resetOptions(options, Object.keys(options))
    this.calendar.resumeRendering()
  }

  disconnect() {
    this.calendar?.destroy()
    this.hidePreview()
  }

  // ---- the toolbar ---------------------------------------------------------------

  setView(event) {
    this.viewMode = event.currentTarget.dataset.view
    this.drawViewButtons()
    this.calendar.changeView(this.viewMode)
  }

  drawViewButtons() {
    this.element.querySelectorAll(".fx-segmented [data-view]").forEach((button) => {
      if (button.dataset.view === this.viewMode) button.classList.add("is-active")
      else button.classList.remove("is-active")
      if (!button.classList.length) button.removeAttribute("class")
    })
  }

  today() {
    this.calendar.today()
  }

  prev() {
    this.calendar.prev()
  }

  next() {
    this.calendar.next()
  }

  filter(event) {
    if (event.target.dataset.filter === "coach") this.coachFilter = event.target.value
    else this.activityFilter = event.target.value
    this.drawReset()
    this.calendar.refetchEvents()
  }

  resetFilters() {
    this.coachFilter = ""
    this.activityFilter = ""
    this.element.querySelectorAll(".fx-cal-filter select").forEach((select) => (select.value = ""))
    this.drawReset()
    this.calendar.refetchEvents()
  }

  // The reset, before the legend, while a filter is set.
  drawReset() {
    const bar = this.element.querySelector(".fx-cal-filters")
    const reset = bar.querySelector(":scope > .btn")
    const on = this.coachFilter !== "" || this.activityFilter !== ""
    if (on && !reset) bar.querySelector(".fx-legend").before(this.resetTemplateTarget.content.firstElementChild.cloneNode(true))
    else if (!on) reset?.remove()
  }

  onDatesSet(start) {
    this.hidePreview()
    this.rangeStart = start
    this.titleTarget.textContent = this.calendar.view.title
    this.viewMode = this.calendar.view.type
    this.drawViewButtons()
  }

  // The range on screen (datesSet's start and end), as the component asks
  // for it. Called from FullCalendar's constructor too, before this.calendar
  // is set: the range comes with the call.
  async fetchEvents(info, success, failure) {
    const query = new URLSearchParams({ from: toDateInputValue(info.start), to: toDateInputValue(info.end) })
    if (this.coachFilter) query.set("coach_id", this.coachFilter)
    if (this.activityFilter) query.set("activity_id", this.activityFilter)
    const response = await fetch(`${this.urlValue}/events?${query}`, { credentials: "same-origin", headers: { Accept: "application/json" } }).catch(() => null)
    if (!response?.ok) {
      toast("error", this.labelsValue.error)
      return failure(new Error("events"))
    }
    const { sessions } = await response.json()
    success(sessions.map((session) => ({
      id: String(session.id),
      title: `${session.activity_emoji ? session.activity_emoji + " " : ""}${session.activity_name}`,
      start: session.starts_at,
      end: session.ends_at,
      extendedProps: { session },
      classNames: [`fc-status-${session.status}`, ...(this.isSessionEnded(session) ? ["fc-session-ended"] : [])],
    })))
  }

  // ---- an event block ----------------------------------------------------------------

  isRunning(session) {
    const now = Date.now()
    return session.status === "scheduled" && new Date(session.starts_at).getTime() <= now && new Date(session.ends_at).getTime() > now
  }

  isSessionEnded(session) {
    return session.status === "scheduled" && new Date(session.ends_at).getTime() < Date.now()
  }

  renderEvent(arg) {
    const session = arg.event.extendedProps.session
    const minutes = (new Date(session.ends_at).getTime() - new Date(session.starts_at).getTime()) / 60_000
    const compact = arg.view.type === "dayGridMonth" || minutes < 45
    const root = document.createElement("div")
    root.className = compact ? "fx-ev fx-ev--compact" : "fx-ev"
    if (!session.coach_id) root.classList.add("is-uncoached")
    if (this.isRunning(session)) root.classList.add("is-now")
    const open = !!session.individual && session.confirmed_count === 0 && session.status === "scheduled"
    if (open) root.classList.add("is-open")
    const openLabel = open ? ` · ${this.labelsValue.slot_open}` : ""

    if (compact) {
      const line = document.createElement("span")
      line.className = "fx-ev-line"
      line.textContent = `${arg.timeText} ${session.activity_name}${openLabel}`
      root.appendChild(line)
    } else {
      const time = document.createElement("span")
      time.className = "fx-ev-time"
      time.textContent = arg.timeText
      root.appendChild(time)
      const title = document.createElement("span")
      title.className = "fx-ev-title"
      title.textContent = `${session.activity_emoji ? session.activity_emoji + " " : ""}${session.activity_name}${openLabel}`
      root.appendChild(title)
      if (session.space_name) {
        const room = document.createElement("span")
        room.className = "fx-ev-coach"
        room.textContent = session.space_name
        root.appendChild(room)
      }
    }
    if (!compact) {
      const coach = document.createElement("span")
      if (session.coach_name) {
        coach.className = "fx-ev-coach"
        coach.textContent = session.coach_name
      } else {
        coach.className = "fx-ev-coach is-missing"
        coach.textContent = this.labelsValue.no_coach
      }
      root.appendChild(coach)
    }
    const count = document.createElement("span")
    count.className = "fx-ev-count"
    if (compact) count.classList.add("is-hidden")
    if (session.confirmed_count >= session.capacity) count.classList.add("is-full")
    count.textContent = `${session.confirmed_count}/${session.capacity}`
    root.appendChild(count)
    return { domNodes: [root] }
  }

  // ---- the hover card ------------------------------------------------------------------

  showPreview(arg) {
    const session = arg.event.extendedProps.session
    const rect = arg.el.getBoundingClientRect()
    const width = 268
    const height = 210
    const left = rect.right + width + 16 < window.innerWidth ? rect.right + 8 : Math.max(8, rect.left - width - 8)
    const top = Math.min(Math.max(8, rect.top), Math.max(8, window.innerHeight - height - 8))
    this.hidePreview()
    const tip = document.querySelector("template[data-calendar-tip]").content.firstElementChild.cloneNode(true)
    tip.style.top = `${top}px`
    tip.style.left = `${left}px`
    const part = (name) => tip.querySelector(`[data-tip="${name}"]`)
    part("title").textContent = ` ${session.activity_emoji ? session.activity_emoji + " " : ""}${session.activity_name} `
    this.badge(part("badge"), session.status, this.labelsValue.statuses[session.status] ?? session.status, true)
    part("hours").textContent = `${session.labels.start} – ${session.labels.end}`
    part("day").textContent = session.labels.day
    part("coach").append(` ${session.coach_name || this.labelsValue.no_coach_schedule}`)
    part("place").append(` ${session.company_name}`)
    if (session.price > 0) part("price").append(` ${session.price}`)
    else part("price").remove()
    part("fill").textContent = `${session.confirmed_count}/${session.capacity}`
    const bar = part("bar")
    bar.style.width = `${session.capacity <= 0 ? 0 : Math.min(100, Math.round((session.confirmed_count / session.capacity) * 100))}%`
    if (session.confirmed_count >= session.capacity) bar.classList.add("is-full")
    this.element.after(tip)
    this.tip = tip
  }

  hidePreview() {
    this.tip?.remove()
    this.tip = null
  }

  // A StatusBadgeComponent in its host: the tone for the status, the label.
  badge(host, status, label, spaced = false) {
    const span = scoped(document.createElement("span"), "status-badge")
    span.className = `status-badge status-badge--${statusTone(status)}`
    span.textContent = spaced ? ` ${label} ` : label
    host.setAttribute("_nghost-status-badge", "")
    host.replaceChildren(span)
  }

  // ---- moving a session ------------------------------------------------------------------

  async onEventDrop(arg) {
    const session = arg.event.extendedProps.session
    const newStart = arg.event.start
    const ok = await confirmAsk({ title: this.labelsValue.move_title, body: this.labelsValue.move_body })
    if (!ok) return arg.revert()
    const duration = new Date(session.ends_at).getTime() - new Date(session.starts_at).getTime()
    const newEnd = new Date(newStart.getTime() + duration)
    const result = await this.request("PATCH", `${this.urlValue}/sessions/${session.id}`, { session: { starts_at: newStart.toISOString(), ends_at: newEnd.toISOString() } })
    if (!result.ok) {
      toast("error", result.error ?? this.labelsValue.error)
      return arg.revert()
    }
    toast("success", this.labelsValue.save)
    this.calendar.refetchEvents()
  }

  // ---- the session detail -------------------------------------------------------------------

  openDetail(session) {
    this.hidePreview()
    this.detail = session
    window.dispatchEvent(new CustomEvent("calendar-detail:open"))
  }

  fill(event) {
    const { name, panel } = event.detail
    if (name === "calendar-detail") this.fillDetail(panel)
    else if (name === "calendar-create") this.fillCreate(panel)
  }

  closed(event) {
    if (event.target.dataset?.modalNameValue === "calendar-create") this.clearSelectedCell()
  }

  fillDetail(panel) {
    const session = this.detail
    const title = `${session.activity_emoji ? session.activity_emoji + " " : ""}${session.activity_name || ""}`
    panel.querySelector(".modal-panel-header h3").textContent = title
    panel.setAttribute("aria-label", title)
    const part = (name) => panel.querySelector(`[data-detail="${name}"]`)
    // " Studio Lumen" after its icon: the template's own space is dropped, as
    // Angular drops a whitespace-only text node.
    part("place").replaceWith(` ${session.company_name}`)
    part("coach").replaceWith(` ${session.coach_name || "—"}`)
    part("time").replaceWith(` ${session.labels.medium} – ${session.labels.end}`)
    part("fill").textContent = `${session.confirmed_count}/${session.capacity}`
    this.badge(part("badge"), session.status, this.labelsValue.statuses[session.status] ?? session.status)
    if (!this.isSessionEnded(session)) part("ended").remove()

    const add = part("add")
    if (add) this.bindAddMember(add, session)

    const actions = part("actions")
    if (actions) {
      if (session.status !== "scheduled") actions.remove()
      else {
        const stop = part("stop")
        if (!session.recurring_schedule_id) stop.remove()
        else stop.addEventListener("click", () => this.stopSeries(stop))
        part("cancel").addEventListener("click", () => this.cancelSession())
      }
    }
    this.loadRoster(part("bookings"), session)
  }

  // detailLoading: the spinner, then the people, each with four statuses.
  async loadRoster(holder, session) {
    const box = scoped(document.createElement("div"), SCOPE)
    box.className = "d-flex justify-content-center py-4"
    box.append(spinner(28, SCOPE))
    holder.replaceWith(box)
    const response = await fetch(`${this.urlValue.replace(/\/calendar$/, "")}/attendance/${session.id}`, { credentials: "same-origin", headers: { Accept: "application/json" } }).catch(() => null)
    const bookings = response?.ok ? (await response.json()).bookings : []
    if (!box.isConnected) return
    if (bookings.length === 0) {
      const p = scoped(document.createElement("p"), SCOPE)
      p.className = "text-muted-token small"
      p.textContent = this.labelsValue.no_bookings
      return box.replaceWith(p)
    }
    const list = scoped(document.createElement("ul"), SCOPE)
    list.className = "list-unstyled mb-0"
    const template = document.querySelector("template[data-calendar-roster]").content.firstElementChild
    for (const booking of bookings) {
      const li = template.cloneNode(true)
      li.querySelector("[data-name]").replaceWith(Object.assign(scoped(document.createElement("span"), SCOPE), { textContent: booking.client.full_name }))
      this.drawStatuses(li, booking)
      li.querySelectorAll("[data-status]").forEach((button) => button.addEventListener("click", () => this.markAttendance(li, booking, button.dataset.status)))
      list.append(li)
    }
    box.replaceWith(list)
  }

  drawStatuses(li, booking) {
    li.querySelectorAll("[data-status]").forEach((button) => {
      const on = booking.attendance?.status === button.dataset.status
      button.classList.toggle("btn-primary", on)
      button.classList.toggle("btn-outline-secondary", !on)
    })
  }

  async markAttendance(li, booking, status) {
    const buttons = li.querySelectorAll("[data-status]")
    buttons.forEach((b) => (b.disabled = true))
    const result = await this.request("POST", `${this.urlValue.replace(/\/calendar$/, "")}/attendance`, { booking_id: booking.booking_id, status }, true)
    buttons.forEach((b) => (b.disabled = false))
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    Object.assign(booking, result.data.attendance)
    this.drawStatuses(li, booking)
  }

  bindAddMember(add, session) {
    const input = add.querySelector("input")
    let timer = null
    input.addEventListener("input", () => {
      const term = input.value
      clearTimeout(timer)
      add.querySelector(".search-results-dropdown")?.remove()
      if (term.trim().length < 2) return
      timer = setTimeout(async () => {
        const response = await fetch(`${this.urlValue}/clients?${new URLSearchParams({ search: term })}`, { credentials: "same-origin", headers: { Accept: "application/json" } }).catch(() => null)
        if (!response?.ok || input.value !== term) return
        const { clients } = await response.json()
        add.querySelector(".search-results-dropdown")?.remove()
        if (clients.length === 0) return
        const dropdown = scoped(document.createElement("div"), SCOPE)
        dropdown.className = "search-results-dropdown"
        for (const client of clients) {
          const button = scoped(document.createElement("button"), SCOPE)
          button.type = "button"
          button.className = "search-result-item"
          const phone = scoped(document.createElement("span"), SCOPE)
          phone.className = "text-muted-token small"
          phone.textContent = client.phone ?? ""
          button.append(` ${client.full_name} `, phone)
          button.addEventListener("click", () => this.addClient(add, session, client))
          dropdown.append(button)
        }
        add.append(dropdown)
      })
    })
  }

  async addClient(add, session, client) {
    const input = add.querySelector("input")
    input.disabled = true
    const result = await this.request("POST", `${this.urlValue}/sessions/${session.id}/bookings`, { client_id: client.id })
    input.disabled = false
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    input.value = ""
    add.querySelector(".search-results-dropdown")?.remove()
    toast("success", this.labelsValue.save)
    window.dispatchEvent(new CustomEvent("calendar-detail:close"))
    this.openDetail(session)
    this.calendar.refetchEvents()
  }

  async cancelSession() {
    const ok = await confirmAsk({ title: this.labelsValue.cancel_title, body: this.labelsValue.cancel_body, danger: true })
    if (!ok) return
    const result = await this.request("POST", `${this.urlValue}/sessions/${this.detail.id}/cancel`)
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    toast("success", this.labelsValue.confirm)
    window.dispatchEvent(new CustomEvent("calendar-detail:close"))
    this.calendar.refetchEvents()
  }

  async stopSeries(button) {
    const ok = await confirmAsk({ title: this.labelsValue.stop_title, body: this.labelsValue.stop_body, confirmLabel: this.labelsValue.stop, danger: true })
    if (!ok) return
    button.disabled = true
    const result = await this.request("PATCH", `${this.urlValue}/series/${this.detail.recurring_schedule_id}`, { active: false }, true)
    button.disabled = false
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    window.dispatchEvent(new CustomEvent("calendar-detail:close"))
    toast("success", interpolate(this.labelsValue.series_stopped, { count: result.data.cancelled_sessions }))
    if (result.data.kept_sessions > 0) toast("error", interpolate(this.labelsValue.series_kept, { count: result.data.kept_sessions }))
    this.calendar.refetchEvents()
  }

  // ---- a new session -------------------------------------------------------------------------

  onDateClick(date, dayEl) {
    if (!this.manageValue) return
    this.clearSelectedCell()
    dayEl.classList.add("fc-cell-selected")
    this.selectedCell = dayEl
    this.openCreate(date)
  }

  clearSelectedCell() {
    this.selectedCell?.classList.remove("fc-cell-selected")
    this.selectedCell = null
  }

  openCreate(dateOrEvent) {
    this.createDate = dateOrEvent instanceof Date ? dateOrEvent : null
    window.dispatchEvent(new CustomEvent("calendar-create:open"))
  }

  fillCreate(panel) {
    const form = panel.querySelector("[data-calendar-create]")
    const f = form.elements
    const date = this.createDate
    f.date.value = toDateInputValue(date ?? new Date())
    f.start_time.value = date ? `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}` : "09:00"
    this.repeatUntil = toDateInputValue(new Date((date ?? new Date()).getTime() + 8 * 7 * 86400000))
    const part = (name) => form.querySelector(`template[data-create="${name}"]`).content.firstElementChild.cloneNode(true)
    this.create = { panel, form, member: part("member"), kind: part("kind"), until: part("until"), repeat: form.querySelector('[data-create="repeat"]'), format: null, clientId: "" }
    // Held: out of the form while it does not apply, so not in form.elements.
    this.create.repeatBox = this.create.repeat.querySelector("input")
    this.create.repeat.remove()
    this.create.until.querySelector("input").value = this.repeatUntil
    f.activity_id.addEventListener("change", () => this.applyActivity())
    f.date.addEventListener("change", () => this.drawCreate())
    this.create.repeatBox.addEventListener("change", () => this.drawCreate())
    this.create.member.addEventListener("searchable-select:change", (e) => {
      this.create.clientId = e.detail.value
      this.drawCreate()
    })
    form.addEventListener("submit", (e) => {
      e.preventDefault()
      this.submitCreate()
    })
    this.applyActivity()
  }

  // The activity picked drives the capacity and, one-to-one, the member.
  applyActivity() {
    const { form } = this.create
    const f = form.elements
    const activity = this.activitiesValue.find((a) => a.id === f.activity_id.value) ?? null
    this.create.format = activity?.session_format ?? null
    this.create.clientId = ""
    const capacity = f.capacity
    if (!activity) {
      capacity.disabled = false
      capacity.value = ""
      capacity.min = "1"
      capacity.removeAttribute("max")
    } else {
      const bounds = CAPACITY_BOUNDS[activity.session_format]
      capacity.min = String(bounds.min)
      if (bounds.max === null) capacity.removeAttribute("max")
      else capacity.setAttribute("max", String(bounds.max))
      capacity.value = activity.session_format === "individual" ? 1 : activity.capacity
      capacity.disabled = activity.session_format === "individual"
      if (activity.session_format === "individual") {
        queueMicrotask(() => {
          const select = this.application.getControllerForElementAndIdentifier(this.create.member.querySelector("app-searchable-select"), "searchable-select")
          select?.setOptions(this.clientsValue.map((c) => ({ value: c.id, label: c.full_name })), "")
        })
      }
    }
    this.drawCreate()
  }

  get canRepeat() {
    return this.create.format !== "individual" || !this.create.clientId
  }

  get repeats() {
    return this.create.repeatBox.checked && this.canRepeat
  }

  // What the form shows for the activity and choices made: the member (one
  // to one), how their seat is paid, the weekly repeat and its last day, the
  // format's capacity hint.
  drawCreate() {
    const { form, member, kind, until, repeat, format } = this.create
    const activityBlock = form.elements.activity_id.closest(".mb-3")
    if (format === "individual") {
      if (!member.isConnected) activityBlock.after(member)
      const showKind = this.dropInValue && Boolean(this.create.clientId)
      if (showKind && !kind.isConnected) member.after(kind)
      if (!showKind) kind.remove()
    } else {
      member.remove()
      kind.remove()
    }

    const dateRow = form.elements.date.closest(".row")
    if (this.canRepeat) {
      if (!repeat.isConnected) dateRow.after(repeat)
      const day = form.elements.date.value ? new Date(`${form.elements.date.value}T12:00:00`).toLocaleDateString(this.localeValue || "fr", { weekday: "long" }) : ""
      repeat.querySelector("[data-repeat-label]").textContent = interpolate(this.labelsValue.repeat_weekly, { day })
      if (this.repeats && !until.isConnected) repeat.append(until)
      if (!this.repeats) until.remove()
    } else {
      repeat.remove()
    }

    const capacityBlock = form.elements.capacity.closest(".mb-3")
    capacityBlock.querySelector(".form-text")?.remove()
    if (format && format !== "individual") {
      const hint = scoped(document.createElement("div"), SCOPE)
      hint.className = "form-text"
      hint.textContent = this.labelsValue.format_hints[format]
      capacityBlock.append(hint)
    }
  }

  async submitCreate() {
    const { form, panel } = this.create
    const f = form.elements
    const capacity = f.capacity
    if (!f.activity_id.value || !f.date.value || !f.start_time.value || this.saving) return
    if (!capacity.disabled && capacity.value !== "" && (Number(capacity.value) < Number(capacity.min) || (capacity.max && Number(capacity.value) > Number(capacity.max)))) return
    if (this.repeats) return this.submitWeekly()

    const activity = this.activitiesValue.find((a) => a.id === f.activity_id.value)
    if (!activity) return
    const startsAt = new Date(`${f.date.value}T${f.start_time.value}:00`)
    const endsAt = new Date(startsAt.getTime() + activity.duration * 60000)
    const clientId = this.create.clientId
    const bookingKind = form.querySelector('input[name="booking_kind"]:checked')?.value ?? "contract"
    await this.save(panel, form, {
      session: {
        activity_id: activity.id, client_id: clientId || undefined,
        ...(clientId && bookingKind === "trial" ? { trial: true } : {}),
        ...(clientId && bookingKind === "drop_in" ? { drop_in: true } : {}),
        coach_id: f.coach_id.value || null, ...(f.space_id?.value ? { space_id: f.space_id.value } : {}),
        starts_at: startsAt.toISOString(), ends_at: endsAt.toISOString(),
        capacity: (capacity.disabled ? Number(capacity.value) : Number(capacity.value)) || undefined,
        price: Number(f.price.value) || undefined,
      },
    }, () => toast("success", this.labelsValue.save))
  }

  async submitWeekly() {
    const { form, panel, until } = this.create
    const f = form.elements
    const repeatUntil = until.querySelector("input").value
    if (!repeatUntil || repeatUntil < f.date.value) return this.showError(panel, this.labelsValue.repeat_until_invalid)
    await this.save(panel, form, {
      weekly: true,
      recurring_schedule: {
        activity_id: f.activity_id.value, coach_id: f.coach_id.value || null, ...(f.space_id?.value ? { space_id: f.space_id.value } : {}),
        start_time: f.start_time.value, starts_on: f.date.value, ends_on: repeatUntil, weekdays: [new Date(`${f.date.value}T12:00:00`).getDay()],
      },
    }, (data) => {
      toast("success", interpolate(this.labelsValue.weekly_created, { count: data.generated }))
      if (data.conflicts.length > 0) toast("error", interpolate(this.labelsValue.weekly_conflicts, { count: data.conflicts.length }))
    })
  }

  async save(panel, form, body, done) {
    const button = form.querySelector("[data-save]")
    this.saving = true
    button.disabled = true
    button.textContent = ` ${this.labelsValue.saving} `
    this.showError(panel, null)
    const result = await this.request("POST", `${this.urlValue}/sessions`, body, true)
    this.saving = false
    button.disabled = false
    button.textContent = ` ${this.labelsValue.save} `
    if (!result.ok) return this.showError(panel, result.error ?? this.labelsValue.error)
    window.dispatchEvent(new CustomEvent("calendar-create:close"))
    this.clearSelectedCell()
    done(result.data)
    this.calendar.refetchEvents()
  }

  showError(panel, message) {
    const body = panel.querySelector(".modal-panel-body")
    body.querySelector(":scope > .alert-danger")?.remove()
    if (!message) return
    const alert = scoped(document.createElement("div"), SCOPE)
    alert.className = "alert alert-danger"
    alert.textContent = message
    body.prepend(alert)
  }

  // ---- printing the week ---------------------------------------------------------------------

  async printSchedule(event) {
    const button = event.currentTarget
    const icon = button.querySelector("i, .spinner-border")
    button.disabled = true
    const busy = this.spinnerTemplateTarget.content.firstElementChild.cloneNode(true)
    icon.replaceWith(busy)
    const from = toDateInputValue(this.rangeStart ?? new Date())
    const response = await fetch(`${this.urlValue}/schedule?from=${from}`, { credentials: "same-origin" }).catch(() => null)
    button.disabled = false
    busy.replaceWith(icon)
    if (!response?.ok) return toast("error", this.labelsValue.error)
    downloadBlob(await response.blob(), `planning-${from}.pdf`)
  }

  async request(method, url, body, withData = false) {
    const response = await fetch(url, {
      method, credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: body === undefined ? undefined : JSON.stringify(body),
    }).catch(() => null)
    if (!response) return { ok: false, error: null }
    const data = withData || !response.ok ? await response.json().catch(() => ({})) : null
    return response.ok ? { ok: true, data } : { ok: false, error: data?.error ?? null }
  }
}
