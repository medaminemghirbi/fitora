import { Controller } from "@hotwired/stimulus"

// LocaleService#setLocale, the Rails way (D6): the language is remembered
// and the same page comes back in it — same path, same query string.
export default class extends Controller {
  choose(event) {
    const form = document.getElementById("locale-form")
    const locale = document.createElement("input")
    locale.type = "hidden"
    locale.name = "locale"
    locale.value = event.params.locale
    form.append(locale)
    form.submit()
  }
}
