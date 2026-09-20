import { Controller } from "@hotwired/stimulus"

// Copies the shop's link. The field is readable and selectable on its own, so
// without JavaScript nothing is lost — this only saves a drag and a Ctrl-C.
export default class extends Controller {
  static targets = ["source", "button"]
  static values = { copied: String }

  copy() {
    this.sourceTarget.select()

    navigator.clipboard
      .writeText(this.sourceTarget.value)
      .then(() => this.confirm())
      // The clipboard API is refused outside a secure context and in some
      // embedded browsers. The text is selected either way.
      .catch(() => this.sourceTarget.focus())
  }

  confirm() {
    const original = this.buttonTarget.textContent

    this.buttonTarget.textContent = this.copiedValue
    setTimeout(() => {
      this.buttonTarget.textContent = original
    }, 2000)
  }
}
