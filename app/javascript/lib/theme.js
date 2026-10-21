// ThemeService#setTheme: the theme on <html>, remembered in a cookie (so the
// server renders the next page in it), and every theme toggle's icon
// following — the navbar's moon / sun, the settings' segmented buttons
// (theme:changed).
export function currentTheme() {
  return document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light"
}

export function setTheme(next) {
  document.documentElement.setAttribute("data-theme", next)
  document.cookie = `fitora_theme=${next}; path=/; max-age=${60 * 60 * 24 * 365 * 20}; samesite=lax`
  document.querySelectorAll('[data-action~="navbar#toggleTheme"] i').forEach((icon) => {
    icon.classList.toggle("bi-moon-stars", next === "light")
    icon.classList.toggle("bi-sun", next === "dark")
  })
  window.dispatchEvent(new CustomEvent("theme:changed", { detail: { theme: next } }))
}
