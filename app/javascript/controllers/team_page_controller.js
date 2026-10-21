import { Controller } from "@hotwired/stimulus"
import { confirmAsk } from "../lib/confirm"
import { highlight } from "../lib/highlight"
import { NG_EMAIL, csrfToken, interpolate, scoped } from "../lib/ng"
import { pagination } from "../lib/pagination"
import { toast } from "../lib/toast"

// TeamComponent. The people come with the page (cards, and the same people
// as data); this filters them by kind (tabs), by access (pills) and by
// search, pages them by 25 and redraws the cards — all in the browser, as
// the component does. The create drawer and the three modals are filled
// here when they open; each save goes to the server, and then load(): the
// skeleton where the cards were, the people as they are now, the filters
// left as they were.
const PER_PAGE = 25
const MODERATOR = "moderator"
const ORDER = ["revenue", "payments", "clients", "sessions", "bookings", "checkin"]
const isMasked = (value) => Boolean(value) && value.includes("****")

export default class extends Controller {
  static targets = ["main", "count", "search"]
  static values = { url: String, admin: Boolean, roles: Array, open: String, labels: Object }

  connect() {
    this.host = this.element.closest("app-team")
    this.tab = "all"
    this.access = ""
    this.term = ""
    this.page = 1
    this.loading = false
    this.readParts(this.host.querySelector("[data-team-parts]"))
    // localeCompare settles the order the server approximated (Web::Collation).
    if (this.sortMembers()) this.render()
    // ?action=new: the drawer open from the start (ngOnInit). A microtask:
    // the drawer's own controller connects in this same pass.
    if (this.openValue) queueMicrotask(() => this.openCreate(this.openValue))
  }

  // ---- the people -----------------------------------------------------------

  readParts(parts) {
    const data = JSON.parse(parts.querySelector('script[data-team-part="members"]').textContent)
    this.members = data.members
    this.cards = new Map([...parts.querySelector('template[data-team-part="cards"]').content.children].map((card) => [card.dataset.key, card]))
    this.parts = parts
  }

  sortMembers() {
    const before = this.members.map((m) => m.key).join()
    this.members.sort((a, b) => a.name.localeCompare(b.name))
    return this.members.map((m) => m.key).join() !== before
  }

  get moderator() {
    return this.members.find((m) => m.active && m.staff && !m.staff.coach_id && m.staff.role_key === MODERATOR) ?? null
  }

  isRoleTaken(role, except = null) {
    const holder = this.moderator?.staff
    return role.key === MODERATOR && Boolean(holder) && holder.id !== except?.id
  }

  get availableRoles() {
    return this.rolesValue.filter((role) => !this.isRoleTaken(role))
  }

  permissionSummary(permissions) {
    const labels = this.labelsValue.access
    if (ORDER.every((key) => permissions.includes(key))) return labels.everything
    const named = ORDER.filter((key) => permissions.includes(key)).map((key) => labels[key])
    return named.length > 0 ? named.join(" · ") : labels.nothing
  }

  roleAccessSummary(roleId) {
    const role = this.rolesValue.find((r) => r.id === roleId)
    return role ? this.permissionSummary(role.permissions) : ""
  }

  get filtered() {
    let list = this.members
    if (this.tab === "coaches") list = list.filter((m) => m.coach)
    else if (this.tab === "backoffice") list = list.filter((m) => m.staff)
    if (this.access === "mobile") list = list.filter((m) => m.has_mobile)
    else if (this.access === "web") list = list.filter((m) => m.has_web)
    else if (this.access === "none") list = list.filter((m) => !m.has_mobile && !m.has_web)
    const needle = this.term.trim().toLowerCase()
    if (!needle) return list
    return list.filter((m) => [m.name, m.email, m.phone].some((f) => (f ?? "").toLowerCase().includes(needle)))
  }

  get hasFilters() {
    return this.term !== "" || this.tab !== "all" || this.access !== ""
  }

  // ---- filters --------------------------------------------------------------
  // The component resets the page when the tab or the search changes (an
  // effect: only on a real change), and the access pills reset it themselves.

  setTab(event) {
    const tab = event.currentTarget.dataset.tab
    if (tab !== this.tab) this.page = 1
    this.tab = tab
    this.render()
  }

  setAccess(event) {
    this.access = event.target.value
    this.page = 1
    this.render()
  }

  search(event) {
    if (event.target.value !== this.term) this.page = 1
    this.term = event.target.value
    this.render()
  }

  resetFilters() {
    if (this.term !== "" || this.tab !== "all") this.page = 1
    this.term = ""
    this.searchTarget.value = ""
    this.tab = "all"
    this.access = ""
    this.render()
  }

  goToPage(event) {
    this.page = Number(event.currentTarget.dataset.page)
    this.render()
  }

  // ---- drawing --------------------------------------------------------------

  regionTemplate(name) {
    return this.host.querySelector(`template[data-team-region-template="${name}"]`).content.firstElementChild.cloneNode(true)
  }

  render() {
    const main = this.mainTarget
    main.querySelectorAll(".fx-cat-tab").forEach((tab) => tab.classList.toggle("is-active", tab.dataset.tab === this.tab))
    main.querySelectorAll('input[name="team-access"]').forEach((radio) => (radio.checked = radio.value === this.access))
    const filters = main.querySelector(".lst-filters")
    if (filters) {
      const reset = filters.querySelector("[data-team-reset]")
      if (this.hasFilters && !reset) filters.append(this.regionTemplate("reset"))
      else if (!this.hasFilters) reset?.remove()
    }

    main.querySelectorAll(":scope > [data-team-region]").forEach((node) => node.remove())
    if (this.loading) return main.append(this.regionTemplate("skeleton"))
    if (this.members.length === 0) return main.append(this.regionTemplate("none"))
    const filtered = this.filtered
    if (filtered.length === 0) return main.append(this.regionTemplate("no-results"))

    // clientPageMeta / pageSlice: a page past the end shows no card, as there.
    const meta = { page: Math.max(1, this.page), total: filtered.length, total_pages: Math.max(1, Math.ceil(filtered.length / PER_PAGE)) }
    const grid = scoped(document.createElement("div"), "team")
    grid.className = "fx-people-grid"
    grid.dataset.teamRegion = ""
    const start = (meta.page - 1) * PER_PAGE
    for (const member of filtered.slice(start, start + PER_PAGE)) grid.append(this.card(member))
    const labels = this.labelsValue
    const pager = pagination(meta, { unit: labels.results, page: labels.page, of: labels.of }, "team", "team-page#goToPage")
    pager.dataset.teamRegion = ""
    main.append(grid, pager)
  }

  card(member) {
    const card = this.cards.get(member.key).cloneNode(true)
    card.querySelectorAll("[data-highlight]").forEach((node) => (node.innerHTML = highlight(node.dataset.highlight, this.term)))
    return card
  }

  // load(): the skeleton where the cards were, then the people as they are
  // now — the count, tabs and pills redrawn with them, the filters kept.
  async load() {
    this.loading = true
    this.render()
    const response = await fetch(`${this.urlValue}?fragment=1`, { credentials: "same-origin", headers: { Accept: "text/html" } }).catch(() => null)
    this.loading = false
    if (!response?.ok) return this.render()
    const fresh = document.createElement("div")
    fresh.innerHTML = await response.text()
    this.parts.replaceChildren(...fresh.childNodes)
    this.readParts(this.parts)
    this.sortMembers()
    this.countTarget.textContent = this.members.length
    // The tabs and pills, with their new counts (none for an empty team).
    this.mainTarget.querySelectorAll(":scope > .fx-cat-tabs, :scope > .lst-filters").forEach((node) => node.remove())
    this.mainTarget.querySelector(":scope > .lst-head").after(this.parts.querySelector('template[data-team-part="filters"]').content.cloneNode(true))
    // The drawer opens from its template: from now on, as the team now is.
    const drawerTemplate = document.querySelector('app-drawer [data-modal-target="template"]')
    drawerTemplate.innerHTML = this.parts.querySelector('template[data-team-part="drawer"]').innerHTML
    if (this.drawer?.isConnected) this.refreshDrawer()
    this.render()
  }

  memberOf(event) {
    const key = event.target.closest(".fx-person-card").dataset.key
    return this.members.find((m) => m.key === key)
  }

  // ---- the create drawer ------------------------------------------------------

  openCreate(eventOrKind) {
    const kind = typeof eventOrKind === "string" ? eventOrKind : (eventOrKind.currentTarget.dataset.kind ?? "coach")
    const backofficeAvailable = this.availableRoles.length > 0
    this.createKind = this.adminValue && !(kind === "backoffice" && !backofficeAvailable) ? kind : "coach"
    this.createError = null
    this.saving = false
    window.dispatchEvent(new CustomEvent("team-create:open"))
  }

  fill(event) {
    const { name, panel } = event.detail
    if (name === "team-create") this.fillCreate(panel)
    else if (name === "team-edit-coach") this.fillEditCoach(panel)
    else if (name === "team-role") this.fillRole(panel)
    else if (name === "team-login") this.fillLogin(panel)
  }

  fillCreate(panel) {
    this.drawer = panel
    this.forms = {
      coach: panel.querySelector('form[data-team-form="coach"]'),
      backoffice: panel.querySelector('form[data-team-form="backoffice"]'),
    }
    this.mobilePassword = this.forms.coach.querySelector("[data-team-mobile-password]")
    this.mobilePassword.remove()
    this.preview = this.forms.backoffice.querySelector("[data-team-role-preview]")
    this.forms.backoffice.elements.role_id.value = this.availableRoles[0]?.id ?? ""
    this.renderPreview()
    this.bindDrawer(panel)
    for (const form of Object.values(this.forms)) {
      form.addEventListener("submit", (e) => {
        e.preventDefault()
        this.submitCreate()
      })
    }
    this.showKind()
    this.renderCreate()
  }

  // The drawer's own controls (it is the page's sibling: no data-action
  // reaches this controller from there). `root`: the drawer, or what was
  // just redrawn in it.
  bindDrawer(root) {
    root.querySelectorAll("[data-create-kind]").forEach((button) => button.addEventListener("click", () => this.setKind(button.dataset.createKind)))
    root.querySelector("[data-team-free-seat]")?.addEventListener("click", () => this.freeBackofficeSeat())
    root.querySelector('input[name="with_mobile"]')?.addEventListener("change", (event) => this.toggleMobile(event))
    root.querySelector('select[name="role_id"]')?.addEventListener("change", () => this.renderPreview())
  }

  // After a save while the drawer is open (freeing the moderator seat): the
  // kind cards and the role list as they stand now, the values kept.
  refreshDrawer() {
    const fresh = document.querySelector('app-drawer [data-modal-target="template"]').content
    const block = this.drawer.querySelector(".team-kind-block")
    const freshBlock = fresh.querySelector(".team-kind-block")?.cloneNode(true)
    if (block && freshBlock) {
      block.replaceWith(freshBlock)
      this.bindDrawer(freshBlock)
    }
    const form = this.forms.backoffice
    const chosen = form.elements.role_id.value
    const section = form.querySelector("#tb-role").parentElement
    const freshSection = fresh.querySelector("#tb-role").parentElement.cloneNode(true)
    section.replaceWith(freshSection)
    this.bindDrawer(freshSection)
    this.preview = freshSection.querySelector("[data-team-role-preview]")
    form.elements.role_id.value = chosen
    this.renderPreview()
    this.showKind()
  }

  setKind(kind) {
    this.createKind = kind
    this.showKind()
  }

  showKind() {
    this.drawer.querySelectorAll(".team-kind-opt").forEach((opt) => opt.classList.toggle("is-active", opt.dataset.createKind === this.createKind))
    const shown = this.forms[this.createKind]
    const other = this.forms[this.createKind === "coach" ? "backoffice" : "coach"]
    if (shown.isConnected && !other.isConnected) return
    if (other.isConnected) other.replaceWith(shown)
  }

  toggleMobile(event) {
    if (event.target.checked) event.target.closest(".form-check").after(this.mobilePassword)
    else this.mobilePassword.remove()
  }

  // "Ce compte pourra : …", under the role — when the role says anything.
  renderPreview() {
    const select = this.forms.backoffice.elements.role_id
    const summary = this.roleAccessSummary(select.value)
    if (!summary) return this.preview.remove()
    this.preview.textContent = interpolate(this.labelsValue.role_access_preview, { access: summary })
    if (!this.preview.isConnected) select.after(this.preview)
  }

  renderCreate() {
    const body = this.drawer.querySelector(".fx-drawer-body")
    body.querySelector(":scope > .alert-danger")?.remove()
    if (this.createError) body.prepend(this.alert(this.createError))
    const submit = this.drawer.querySelector("[data-team-create-submit]")
    submit.disabled = this.saving
    submit.textContent = ` ${this.saving ? this.labelsValue.creating : this.labelsValue.create} `
  }

  submitCreate() {
    if (this.saving) return
    if (this.createKind === "coach") this.submitCreateCoach()
    else this.submitCreateBackoffice()
  }

  async submitCreateCoach() {
    const f = this.forms.coach.elements
    const password = this.mobilePassword.querySelector("input").value
    const v = { first_name: f.first_name.value, last_name: f.last_name.value, email: f.email.value, phone: f.phone.value, birthdate: f.birthdate.value, bio: f.bio.value, with_mobile: f.with_mobile.checked }
    if (!v.first_name || !v.last_name) return
    if (v.with_mobile && (!v.email || password.length < 8)) {
      this.createError = this.labelsValue.mobile_needs_credentials
      return this.renderCreate()
    }

    this.saving = true
    this.createError = null
    this.renderCreate()
    const created = await this.request("POST", `${this.urlValue}/coaches`, {
      coach: { first_name: v.first_name, last_name: v.last_name, email: v.email || undefined, phone: v.phone || undefined, birthdate: v.birthdate || null, bio: v.bio || undefined },
    })
    if (!created.ok) return this.createFailed(created.error)
    if (v.with_mobile) {
      const login = await this.request("POST", `${this.urlValue}/coaches/${created.data.coach.id}/login`, { email: v.email, password })
      if (!login.ok) return this.createFailed(login.error)
    }
    this.afterCreate()
  }

  async submitCreateBackoffice() {
    const f = this.forms.backoffice.elements
    const v = { first_name: f.first_name.value, last_name: f.last_name.value, email: f.email.value, phone: f.phone.value, birthdate: f.birthdate.value, password: f.password.value, role_id: f.role_id.value }
    // Validators: required on the names, the address (an address), the
    // password (8 or more) and the role.
    if (!v.first_name || !v.last_name || !v.email || !NG_EMAIL.test(v.email) || v.password.length < 8 || !v.role_id) return

    this.saving = true
    this.createError = null
    this.renderCreate()
    const result = await this.request("POST", `${this.urlValue}/staff`, {
      staff_member: { first_name: v.first_name, last_name: v.last_name, email: v.email, phone: v.phone || undefined, password: v.password, role_id: v.role_id, birthdate: v.birthdate || null },
    })
    if (!result.ok) return this.createFailed(result.error)
    this.afterCreate()
  }

  afterCreate() {
    this.saving = false
    window.dispatchEvent(new CustomEvent("team-create:close"))
    toast("success", this.labelsValue.save)
    this.load()
  }

  createFailed(error) {
    this.saving = false
    this.createError = error ?? this.labelsValue.error
    if (this.drawer?.isConnected) this.renderCreate()
  }

  // From the drawer: free the moderator seat, then the back-office form on it.
  async freeBackofficeSeat() {
    const moderator = this.moderator
    if (moderator) await this.deactivateMember(moderator, () => {
      this.createKind = "backoffice"
      const role = this.rolesValue.find((r) => r.key === MODERATOR)
      if (role) this.forms.backoffice.elements.role_id.value = role.id
      if (this.drawer?.isConnected) {
        this.showKind()
        this.renderPreview()
      }
    })
  }

  // ---- edit a coach -------------------------------------------------------------

  openEditCoach(event) {
    this.editingCoach = this.memberOf(event).coach
    this.editError = null
    this.saving = false
    window.dispatchEvent(new CustomEvent("team-edit-coach:open"))
  }

  fillEditCoach(panel) {
    const coach = this.editingCoach
    this.editPanel = panel
    const form = panel.querySelector('form[data-team-form="edit-coach"]')
    const f = form.elements
    f.first_name.value = coach.first_name
    f.last_name.value = coach.last_name
    f.email.value = coach.email || ""
    f.phone.value = coach.phone || ""
    f.birthdate.value = coach.birthdate || ""
    f.bio.value = coach.bio || ""
    form.addEventListener("submit", (e) => {
      e.preventDefault()
      this.submitEditCoach(form)
    })
    // Lists carry e-mails masked: the form takes the whole address from the
    // coach's own record, which the admin sees whole.
    this.fetchCoach(coach.id).then((full) => {
      if (full && this.editingCoach?.id === coach.id && form.isConnected) f.email.value = full.email || ""
    })
  }

  async submitEditCoach(form) {
    const coach = this.editingCoach
    const f = form.elements
    if (!coach || !f.first_name.value || !f.last_name.value) return
    const raw = { first_name: f.first_name.value, last_name: f.last_name.value, email: f.email.value, phone: f.phone.value, birthdate: f.birthdate.value, bio: f.bio.value }
    // A still-masked address is left out, never sent back over the real one.
    const payload = isMasked(raw.email) ? { ...raw, email: undefined } : raw
    await this.saveModal(form, "team-edit-coach", "PATCH", `${this.urlValue}/coaches/${coach.id}`, { coach: payload }, this.labelsValue.save)
  }

  // ---- role & web access ------------------------------------------------------

  openRole(event) {
    this.editingStaff = this.memberOf(event).staff
    this.saving = false
    window.dispatchEvent(new CustomEvent("team-role:open"))
  }

  fillRole(panel) {
    const staff = this.editingStaff
    const line = panel.querySelector("[data-team-staff-line]")
    const email = scoped(document.createElement("span"), "team")
    email.dir = "ltr"
    email.textContent = staff.user.email
    line.replaceChildren(`${staff.user.full_name} · `, email)

    const form = panel.querySelector('form[data-team-form="role"]')
    const f = form.elements
    for (const role of this.rolesValue) {
      const taken = this.isRoleTaken(role, staff)
      const option = scoped(document.createElement("option"), "team")
      option.value = role.id
      option.disabled = taken
      option.textContent = ` ${role.name}${taken ? ` — ${this.labelsValue.role_taken_suffix}` : ""} `
      f.role_id.append(option)
    }
    f.role_id.value = this.rolesValue.find((r) => r.key === staff.role_key)?.id ?? ""
    f.active.checked = staff.active
    f.birthdate.value = staff.birthdate || ""
    form.addEventListener("submit", (e) => {
      e.preventDefault()
      if (!f.role_id.value) return
      this.saveModal(form, "team-role", "PATCH", `${this.urlValue}/staff/${staff.id}`, { staff_member: { role_id: f.role_id.value, active: f.active.checked, birthdate: f.birthdate.value } }, this.labelsValue.save)
    })
  }

  // ---- mobile login -------------------------------------------------------------

  openLogin(event) {
    this.loginTarget = this.memberOf(event).coach
    this.saving = false
    window.dispatchEvent(new CustomEvent("team-login:open"))
  }

  fillLogin(panel) {
    const coach = this.loginTarget
    panel.querySelector("[data-team-coach-name]").textContent = coach.full_name
    const form = panel.querySelector('form[data-team-form="login"]')
    const f = form.elements
    f.email.value = coach.login_email || coach.email || ""
    f.password.value = ""
    form.addEventListener("submit", (e) => {
      e.preventDefault()
      const email = f.email.value
      if (!email || !NG_EMAIL.test(email) || f.password.value.length < 8) return
      // The login's error sits under the coach's name, not first.
      if (isMasked(email)) return this.showLoginError(panel, this.labelsValue.email_type_full)
      this.saveModal(form, "team-login", "POST", `${this.urlValue}/coaches/${coach.id}/login`, { email, password: f.password.value }, this.labelsValue.login_set)
    })
    this.fetchCoach(coach.id).then((full) => {
      if (full && this.loginTarget?.id === coach.id && form.isConnected) f.email.value = full.login_email || full.email || ""
    })
  }

  showLoginError(panel, message) {
    const body = panel.querySelector(".modal-panel-body")
    body.querySelector(":scope > .alert-danger")?.remove()
    if (message) body.querySelector("[data-team-coach-name]").after(this.alert(message))
  }

  // ---- deactivate ---------------------------------------------------------------

  deactivate(event) {
    this.deactivateMember(this.memberOf(event))
  }

  async deactivateMember(member, onDone) {
    const ok = await confirmAsk({
      title: this.labelsValue.deactivate_title, body: this.labelsValue.deactivate_body,
      confirmLabel: this.labelsValue.deactivate, danger: true,
    })
    if (!ok) return
    const result = member.coach
      ? await this.request("DELETE", `${this.urlValue}/coaches/${member.coach.id}`)
      : await this.request("PATCH", `${this.urlValue}/staff/${member.staff.id}`, { staff_member: { active: false } })
    if (!result.ok) return toast("error", result.error ?? this.labelsValue.error)
    toast("success", this.labelsValue.deactivate)
    this.load()
    onDone?.()
  }

  // ---- shared -------------------------------------------------------------------

  // A modal's save: the button busy, then closed with a toast and load(), or
  // the API's message at the top (the login's under the coach's name).
  async saveModal(form, name, method, url, body, done) {
    if (this.saving) return
    const panel = form.closest("[data-modal-target~=panel]")
    const save = form.querySelector("[data-save]")
    this.saving = true
    save.disabled = true
    save.textContent = this.labelsValue.saving
    const result = await this.request(method, url, body)
    this.saving = false
    if (result.ok) {
      window.dispatchEvent(new CustomEvent(`${name}:close`))
      toast("success", done)
      return this.load()
    }
    if (!form.isConnected) return
    save.disabled = false
    save.textContent = this.labelsValue.save
    const message = result.error ?? this.labelsValue.error
    if (name === "team-login") return this.showLoginError(panel, message)
    const modalBody = panel.querySelector(".modal-panel-body")
    modalBody.querySelector(":scope > .alert-danger")?.remove()
    modalBody.prepend(this.alert(message))
  }

  async fetchCoach(id) {
    const result = await this.request("GET", `${this.urlValue}/coaches/${id}`)
    return result.ok ? result.data.coach : null
  }

  async request(method, url, body) {
    const response = await fetch(url, {
      method, credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
      body: body === undefined ? undefined : JSON.stringify(body),
    }).catch(() => null)
    if (!response) return { ok: false, error: null }
    const data = await response.json().catch(() => ({}))
    return response.ok ? { ok: true, data } : { ok: false, error: data.error ?? null }
  }

  alert(message) {
    const alert = scoped(document.createElement("div"), "team")
    alert.className = "alert alert-danger"
    alert.textContent = message
    return alert
  }
}
