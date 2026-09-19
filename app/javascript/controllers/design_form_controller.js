import { Controller } from "@hotwired/stimulus"

// The creation form follows the technique, because the technique decides what
// the rest of the form even means: an ink count on a DTF press is meaningless.
//
// The print size, on the other hand, is asked whatever the technique. It is not
// only what fixes the definition of a raster file — it is what tells a small
// chest logo apart from a large back print, and it decides which workshops are
// able to print the result at all.
//
// Progressive: without JavaScript every field is shown, the number field alone
// carries the size, and the server bounds whatever comes back. This only spares
// the client questions that do not apply, and shows them what a width means.
export default class extends Controller {
  static targets = ["technique", "inks", "inkValue", "width", "preset", "area", "areaLabel", "sizeHint"]
  static values = { families: Object, ceilings: Object }

  // A t-shirt body is about 50 cm across, drawn 60 units wide in the template.
  static GARMENT_CM = 50
  static GARMENT_UNITS = 60
  static GARMENT_CENTRE = 50

  connect() {
    this.sync()
    this.syncSize()
  }

  sync() {
    const key = this.selectedTechnique
    const ceiling = this.ceilingsValue[key]

    this.inksTarget.hidden = !ceiling

    if (ceiling) {
      const slider = this.inksTarget.querySelector("input[type=range]")
      slider.max = ceiling
      if (Number(slider.value) > ceiling) slider.value = ceiling
      this.showInkValue()
    }

    this.showSizeHint(this.familiesValue[key])
  }

  choosePreset(event) {
    this.widthTarget.value = event.currentTarget.dataset.width
    this.syncSize()
  }

  // Keeps the template, the caption and the pressed preset in step with
  // whatever the client last touched — a chip or the field itself.
  syncSize() {
    const cm = Number(this.widthTarget.value)

    this.presetTargets.forEach((preset) => {
      preset.setAttribute("aria-pressed", String(Number(preset.dataset.width) === cm))
    })

    if (!this.hasAreaTarget) return

    if (!cm || cm <= 0) {
      this.areaTarget.setAttribute("width", "0")
      this.areaLabelTarget.textContent = ""
      return
    }

    const { GARMENT_CM, GARMENT_UNITS, GARMENT_CENTRE } = this.constructor
    const units = Math.min(cm, GARMENT_CM) * (GARMENT_UNITS / GARMENT_CM)

    this.areaTarget.setAttribute("width", units)
    this.areaTarget.setAttribute("height", units)
    this.areaTarget.setAttribute("x", GARMENT_CENTRE - units / 2)
    this.areaLabelTarget.textContent = `${cm} cm`
  }

  showInkValue() {
    const slider = this.inksTarget.querySelector("input[type=range]")
    this.inkValueTarget.textContent = slider.value
  }

  // Why the size matters is not the same question in both families, and saying
  // the wrong reason is worse than saying none.
  showSizeHint(family) {
    if (!this.hasSizeHintTarget) return

    const hints = this.sizeHintTarget.dataset
    this.sizeHintTarget.textContent = family === "raster" ? hints.raster : hints.vector
  }

  get selectedTechnique() {
    const checked = this.techniqueTargets.find((input) => input.checked)
    return checked ? checked.value : this.techniqueTargets[0]?.value
  }
}
