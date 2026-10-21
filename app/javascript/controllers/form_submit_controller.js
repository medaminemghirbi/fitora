import { Controller } from "@hotwired/stimulus"

// A plain button (type="button", as the Angular markup has it) that submits
// a form kept outside the page's markup: sign out, start over…
export default class extends Controller {
  static values = { form: String }

  submit() {
    document.getElementById(this.formValue)?.requestSubmit()
  }
}
