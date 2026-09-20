import { Controller } from "@hotwired/stimulus"

// Three of the five reasons for handing a job back carry no proposal: the
// design is unusable or forbidden, and no level would change that. Asking for
// a level in those cases would be asking a question with no answer.
//
// Progressive: without JavaScript the fields are simply shown, and the server
// ignores a proposal on a reason that does not take one.
export default class extends Controller {
  static targets = ["reason", "proposal"]

  connect() {
    this.sync()
  }

  sync() {
    const chosen = this.reasonTargets.find((input) => input.checked)

    this.proposalTarget.hidden = !chosen || chosen.dataset.proposes !== "true"
  }
}
