import { Controller } from "@hotwired/stimulus"

// The proposals of a click and what to do next, on one page: the client
// picks a card, and the panel underneath — retouch, other versions, send to a
// workshop — now acts on that one. Nothing is kept until one of those is sent:
// the server keeps the picked proposal and sets the others aside then.
//
// Progressive: without JavaScript a card's button keeps the proposal outright
// (POST /choisir), and the panel acts on the first ready proposal.
export default class extends Controller {
  static targets = ["card", "form", "submit", "selection", "panel"]
  static values = { selected: String }

  connect() {
    this.render()
  }

  // A card's "Choisir celle-ci" form, intercepted.
  select(event) {
    event.preventDefault()
    const { token, refineUrl, variantsUrl, choiceUrl, number } = event.params

    this.selectedValue = token
    this.urls = { refine: refineUrl, variants: variantsUrl, choice: choiceUrl }
    this.number = number
    this.render()
    // On a phone the three cards stack: bring the panel into view.
    if (this.hasPanelTarget) this.panelTarget.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }

  render() {
    const chosen = this.selectedValue

    this.cardTargets.forEach((card) => {
      const on = card.dataset.token === chosen
      card.classList.toggle("ring-2", on)
      card.classList.toggle("ring-emulsion", on)
      card.setAttribute("aria-current", on ? "true" : "false")
      card.querySelectorAll("[data-proposals-pick]").forEach((button) => {
        button.setAttribute("aria-pressed", on ? "true" : "false")
        button.textContent = on ? button.dataset.pickedLabel : button.dataset.pickLabel
        button.classList.toggle("btn-primary", on || !chosen)
        button.classList.toggle("btn-secondary", !on && Boolean(chosen))
      })
    })

    this.submitTargets.forEach((button) => { button.disabled = !chosen })
    if (!chosen || !this.urls) return

    this.formTargets.forEach((form) => {
      const url = this.urls[form.dataset.kind]
      if (url) form.action = url + (form.dataset.suffix || "")
    })
    if (this.hasSelectionTarget) {
      this.selectionTarget.textContent = this.selectionTarget.dataset.template.replace("%{number}", this.number)
    }
  }
}
