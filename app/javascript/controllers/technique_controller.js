import { Controller } from "@hotwired/stimulus"

// Reveals a technique's settings once the shop says it practises it.
//
// Progressive on purpose: the fields are rendered visible, and this controller
// hides the unchecked ones on connect. Without JavaScript the form shows
// everything and still saves correctly — a long form that silently drops half
// its fields would be far worse than a long form.
export default class extends Controller {
  static targets = ["toggle", "settings"]

  connect() {
    this.sync()
  }

  sync() {
    this.settingsTarget.hidden = !this.toggleTarget.checked
  }
}
