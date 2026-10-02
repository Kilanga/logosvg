import { Controller } from "@hotwired/stimulus"

// The design's own comparison tools: which file, which background, which
// fabric colour, and a closer look. See docs/SPEC.md, "Détails d'interface à
// respecter" → "Aperçu".
export default class extends Controller {
  static targets = [
    "image", "garment", "stage",
    "finalButton", "originalButton", "lightButton", "darkButton",
    "swatch", "zoomDialog", "zoomImage"
  ]
  static values = { printSrc: String, originalSrc: String }

  showFinal() {
    this.imageTarget.src = this.printSrcValue
    this.press(this.finalButtonTarget, this.originalButtonTarget)
  }

  showOriginal() {
    if (!this.hasOriginalSrcValue || this.originalSrcValue === "") return

    this.imageTarget.src = this.originalSrcValue
    this.press(this.originalButtonTarget, this.finalButtonTarget)
  }

  lightBackground() {
    this.stageTarget.classList.add("screen-tint")
    this.stageTarget.classList.remove("bg-ink")
    this.press(this.lightButtonTarget, this.darkButtonTarget)
  }

  darkBackground() {
    this.stageTarget.classList.remove("screen-tint")
    this.stageTarget.classList.add("bg-ink")
    this.press(this.darkButtonTarget, this.lightButtonTarget)
  }

  tint(event) {
    this.garmentTarget.style.fill = event.params.color
    this.swatchTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button === event.currentTarget))
    })
  }

  zoom() {
    this.zoomImageTarget.src = this.imageTarget.src
    this.zoomDialogTarget.showModal()
  }

  closeZoom() {
    this.zoomDialogTarget.close()
  }

  press(on, off) {
    on.setAttribute("aria-pressed", "true")
    off.setAttribute("aria-pressed", "false")
  }
}
