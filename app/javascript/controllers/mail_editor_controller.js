import { Controller } from "@hotwired/stimulus"

// A subject and a text with variables (web/superadmin/mailings/_editor): a click
// on a variable writes it where the cursor was, in whichever of the two.
export default class extends Controller {
  static targets = ["subject", "body"]

  remember({ currentTarget }) {
    this.field = currentTarget
  }

  insert({ params: { token } }) {
    const field = this.field || this.bodyTarget
    const { selectionStart: start, selectionEnd: end, value } = field
    field.value = `${value.slice(0, start)}${token}${value.slice(end)}`
    field.focus()
    field.setSelectionRange(start + token.length, start + token.length)
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
