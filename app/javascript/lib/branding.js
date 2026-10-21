import { scoped } from "./ng"

// BrandingService#apply after the branding changed under the page (a save in
// Settings): the colour on <html>, its shades mixed from it, and the rail's
// mark — the logo, or Fitora's bolt.
export function applyBranding({ primary_color: color, logo_url: logo }) {
  if (color) {
    const root = document.documentElement
    root.style.setProperty("--color-primary", color)
    root.style.setProperty("--color-primary-hover", `color-mix(in srgb, ${color} 80%, var(--color-text))`)
    root.style.setProperty("--color-primary-soft", `color-mix(in srgb, ${color} 15%, var(--color-surface))`)
  }
  const mark = document.querySelector(".rail-brand-mark")
  if (!mark) return
  if (logo) {
    const img = scoped(document.createElement("img"), "rail")
    img.src = logo
    img.alt = ""
    mark.replaceChildren(img)
  } else {
    const icon = scoped(document.createElement("i"), "rail")
    icon.className = "bi bi-lightning-charge-fill"
    mark.replaceChildren(icon)
  }
}

// ConfigurationService#load after a feature switch: the menus as the
// bootstrap now says — the page fetched again, its rail and mobile bar put in.
export async function refreshShellNav() {
  const response = await fetch(window.location.href, { credentials: "same-origin", headers: { Accept: "text/html" } }).catch(() => null)
  if (!response?.ok) return
  const fresh = new DOMParser().parseFromString(await response.text(), "text/html")
  for (const selector of ["app-rail", "app-mobile-bar"]) {
    const now = document.querySelector(selector)
    const next = fresh.querySelector(selector)
    if (now && next) now.replaceWith(document.importNode(next, true))
  }
}
