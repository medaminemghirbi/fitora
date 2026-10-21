import { scoped } from "./ng"

// <app-pagination [meta]="meta" />, built in the browser exactly as
// web/shared/_pagination renders it, for a list paged client-side.
// `parent`: the scope of the page that writes the host. `labels`: unit
// ("12 résultats"), page, of. `action`: the controller method a page button
// calls.
export function pagination(meta, labels, parent, action = "client-list#goToPage") {
  const host = scoped(document.createElement("app-pagination"), parent, "pagination")
  const box = el("div", "app-pagination")
  const count = el("span", "app-pagination-count")
  count.textContent = `${meta.total} ${labels.unit}`
  box.append(count)
  if (meta.total_pages > 1) {
    const controls = el("div", "app-pagination-controls")
    const where = el("span", "text-muted-token")
    where.textContent = ` ${labels.page} ${meta.page} ${labels.of} ${meta.total_pages} `
    controls.append(where, button("bi-chevron-left", meta.page - 1, meta.page <= 1, action), button("bi-chevron-right", meta.page + 1, meta.page >= meta.total_pages, action))
    box.append(controls)
  }
  host.append(box)
  return host
}

function el(tag, className) {
  const node = scoped(document.createElement(tag), "pagination")
  if (className) node.className = className
  return node
}

function button(icon, page, disabled, action) {
  const b = el("button", "btn btn-outline-secondary btn-sm")
  b.type = "button"
  b.disabled = disabled
  b.dataset.page = String(page)
  b.dataset.action = action
  b.append(el("i", `bi ${icon}`))
  return b
}
