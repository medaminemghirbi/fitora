import { createConsumer } from "@rails/actioncable"

// NotificationService's live half: one NotificationChannel subscription for
// the signed-in admin, superadmin or member (the layout's fitora-live meta
// names them; nobody else is connected, as in Angular). Same origin, so the
// session cookie opens it (ApplicationCable::Connection). What arrives goes
// out as document events the bell and the inbox already follow:
//
//   notifications:unread   { count }          the badge, the inbox's counts
//   notifications:created  { notification }   a new one, for an open list
//
// and a release (system_update) moves the shell's version badge on, as
// AppVersionService#refresh does.
let consumer = null
let who = null

function sync() {
  const wanted = document.querySelector('meta[name="fitora-live"]')?.content ?? null
  if (wanted === who) return
  consumer?.disconnect()
  consumer = null
  who = wanted
  if (!wanted) return

  consumer = createConsumer("/cable")
  consumer.subscriptions.create("NotificationChannel", { received })
}

function received(event) {
  if (event.type === "unread_count") {
    document.dispatchEvent(new CustomEvent("notifications:unread", { detail: { count: event.count ?? 0 } }))
  } else if (event.type === "created" && event.id) {
    document.dispatchEvent(new CustomEvent("notifications:created", { detail: { notification: event } }))
    if (event.kind === "system_update" && event.data?.version) showVersion(String(event.data.version))
  }
}

// Each badge writes the version its own way ("v1.4", "v1.4 — Fitora"): the
// old number is swapped for the new one where it stands.
function showVersion(version) {
  document.querySelectorAll("[data-app-version]").forEach((badge) => {
    badge.textContent = badge.textContent.replace(badge.dataset.appVersion, version)
    badge.dataset.appVersion = version
  })
}

document.addEventListener("turbo:load", sync)
