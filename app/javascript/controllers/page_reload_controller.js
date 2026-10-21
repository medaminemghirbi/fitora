import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// An error state's retry on a page that loaded nothing else: the page again.
export default class extends Controller {
  reload() {
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
