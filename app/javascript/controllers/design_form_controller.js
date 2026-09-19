import { Controller } from "@hotwired/stimulus"

// The creation form follows the technique, because the technique decides what
// the rest of the form even means: an ink count on a DTF press is meaningless,
// and a print width only matters where the file is measured in pixels.
//
// Progressive: without JavaScript every field is shown and the server bounds
// whatever comes back. This only spares the client questions that do not apply.
export default class extends Controller {
  static targets = ["technique", "inks", "width", "inkValue"]
  static values = { families: Object, ceilings: Object }

  connect() {
    this.sync()
  }

  sync() {
    const key = this.selectedTechnique
    const family = this.familiesValue[key]
    const ceiling = this.ceilingsValue[key]

    this.inksTarget.hidden = !ceiling
    this.widthTarget.hidden = family !== "raster"

    if (ceiling) {
      const slider = this.inksTarget.querySelector("input[type=range]")
      slider.max = ceiling
      if (Number(slider.value) > ceiling) slider.value = ceiling
      this.showInkValue()
    }
  }

  showInkValue() {
    const slider = this.inksTarget.querySelector("input[type=range]")
    this.inkValueTarget.textContent = slider.value
  }

  get selectedTechnique() {
    const checked = this.techniqueTargets.find((input) => input.checked)
    return checked ? checked.value : this.techniqueTargets[0]?.value
  }
}
