// Small things several controllers need to look like the Angular components.

// The attributes Angular's emulated encapsulation puts on an element of
// component `scope` (and on the host of component `host`), so markup built
// here is matched by the scoped CSS (bin/build-css.mjs) like server-rendered
// markup is (Web::AngularTemplate).
export function scoped(element, scope, host = null) {
  if (scope) element.setAttribute(`_ngcontent-${scope}`, "")
  if (host) element.setAttribute(`_nghost-${host}`, "")
  return element
}

// <app-spinner [size]="n" /> as it renders inside a component scoped `parent`.
export function spinner(size, parent) {
  const host = scoped(document.createElement("app-spinner"), parent, "spinner")
  const span = scoped(document.createElement("span"), "spinner")
  span.className = "app-spinner"
  span.style.width = `${size}px`
  span.style.height = `${size}px`
  span.setAttribute("role", "status")
  span.setAttribute("aria-label", "Loading")
  host.append(span)
  return host
}

export function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content ?? ""
}

// TranslateService#instant's interpolation: {{ key }} → params[key]; a key
// with no value is left as written, as ngx-translate leaves it.
export function interpolate(text, params = {}) {
  return String(text).replace(/{{\s?([^{}\s]*)\s?}}/g, (match, key) => (params[key] !== undefined ? params[key] : match))
}

// downloadBlob (core/services/download.util.ts): saves a fetched file under
// the name the page gives it.
export function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob)
  const link = document.createElement("a")
  link.href = url
  link.download = filename
  link.rel = "noopener"
  document.body.appendChild(link)
  link.click()
  link.remove()
  setTimeout(() => URL.revokeObjectURL(url), 0)
}

// Validators.email's pattern (Angular 17): what an Angular form accepts as
// an address.
export const NG_EMAIL = /^(?=.{1,254}$)(?=.{1,64}@)[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+)*@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

// MoneyPipe: two decimals, ".00" dropped, then the currency's symbol;
// null prints "—".
export function money(value, symbol) {
  if (value === null || value === undefined) return "—"
  const amount = typeof value === "string" ? Number(value) : value
  const formatted = Number.isFinite(amount) ? amount.toFixed(2).replace(/\.00$/, "") : String(value)
  return `${formatted} ${symbol}`
}
