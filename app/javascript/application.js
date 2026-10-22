// The web UI's JavaScript: Turbo for navigation and form submission, and the
// Stimulus controllers that do what the Angular components did in the
// browser. Built by esbuild (package.json "build") into app/assets/builds.
import "./lib/error_reporting"
import { Turbo } from "@hotwired/turbo-rails"
import "./controllers"
import "./lib/live_notifications"

// ngx-progressbar shows its bar at once; Turbo waits 500 ms by default
// (MIGRATION_AUDIT §10, M-04).
Turbo.config.drive.progressBarDelay = 0

// jwt.interceptor, for the requests pages make themselves: a 401 means the
// session is over (sign in again), a 402 that the account is locked.
const nativeFetch = window.fetch.bind(window)
window.fetch = async (...args) => {
  const response = await nativeFetch(...args)
  if (new URL(response.url || String(args[0]), window.location.href).origin === window.location.origin) {
    if (response.status === 402) window.location.assign("/account-locked")
    else if (response.status === 401) window.location.assign("/connexion")
  }
  return response
}

// Chrome lays out a <select> parsed before the web fonts arrived with the
// fallback font's metrics, and keeps them for its label once the fonts are
// in; the Angular app builds its selects after the fonts. Lay them out again
// whenever fonts finish loading (on a first visit; later pages arrive with
// the fonts already there).
function relayoutSelects() {
  for (const select of document.querySelectorAll("select")) {
    select.style.display = "none"
    void select.offsetHeight
    select.style.removeProperty("display")
    if (!select.getAttribute("style")) select.removeAttribute("style")
  }
}
document.fonts.ready.then(relayoutSelects)
document.fonts.addEventListener("loadingdone", relayoutSelects)
