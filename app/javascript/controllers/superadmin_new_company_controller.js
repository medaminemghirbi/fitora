import { Controller } from "@hotwired/stimulus"
import { ensureTimezone } from "../lib/places"

// The console's new-account form: the time zones, by region, around the one the
// field holds.
export default class extends Controller {
  static targets = ["timezone"]

  connect() {
    const select = this.timezoneTarget
    const current = select.value
    select.replaceChildren()
    for (const group of ensureTimezone(current)) {
      const optgroup = document.createElement("optgroup")
      optgroup.label = group.region
      for (const zone of group.zones) optgroup.append(new Option(zone.label, zone.value))
      select.append(optgroup)
    }
    select.value = current
  }
}
