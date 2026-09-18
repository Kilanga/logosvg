import { Controller } from "@hotwired/stimulus"

// The directory filters. Checking a box applies it immediately, which is what
// anyone expects from a filter panel — but the form still works without any of
// this: it has a submit button, and every filter is a plain form field.
export default class extends Controller {
  static targets = ["form", "latitude", "longitude", "locateButton"]

  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.formTarget.requestSubmit(), 250)
  }

  // "Around me" asks the browser, never a geocoding service: the coordinates
  // come straight from the device and no address is sent to a third party.
  locate() {
    if (!navigator.geolocation) return

    this.locateButtonTarget.disabled = true

    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        this.latitudeTarget.value = coords.latitude.toFixed(5)
        this.longitudeTarget.value = coords.longitude.toFixed(5)
        this.formTarget.requestSubmit()
      },
      () => {
        this.locateButtonTarget.disabled = false
      },
      { timeout: 8000 }
    )
  }

  clearLocation() {
    this.latitudeTarget.value = ""
    this.longitudeTarget.value = ""
    this.formTarget.requestSubmit()
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
