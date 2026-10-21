import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// DeskCheckinComponent#select / #back: the roster of the session picked, or
// the picker again — with the URL kept honest (?session=), replacing the
// history entry as the Angular page does (replaceUrl), so Back leaves the
// page rather than stepping through every session looked at.
export default class extends Controller {
  static values = { url: String }

  pick() {
    Turbo.visit(this.urlValue, { action: "replace" })
  }
}
