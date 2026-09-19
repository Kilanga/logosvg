import { Controller } from "@hotwired/stimulus"

// Adds up the size run as it is typed.
//
// The total is what a workshop prices on, and a client filling seven boxes
// should not have to add them up in their head to see whether they have reached
// the shop's minimum. The server recomputes it on save regardless — this only
// shows the number while the decision is being made.
export default class extends Controller {
  static targets = ["quantity", "output"]

  connect() {
    this.total()
  }

  total() {
    const sum = this.quantityTargets.reduce(
      (running, field) => running + Math.max(0, Number(field.value) || 0),
      0
    )

    this.outputTarget.textContent = sum
  }
}
