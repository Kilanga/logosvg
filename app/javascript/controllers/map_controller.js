import { Controller } from "@hotwired/stimulus"

// Draws the directory map. Leaflet is loaded on demand: most visitors never
// scroll to it, and it is by far the heaviest script on the page.
//
// Markers are circles drawn by Leaflet itself, not its default pin images —
// which is why the vendored stylesheet needs no icon files, and why a marker
// can carry the emulsion colour of the rest of the interface.
export default class extends Controller {
  static values = {
    points: Array,
    center: Object,
    zoom: { type: Number, default: 6 }
  }

  async connect() {
    // A Leaflet map built inside a hidden container renders at zero size and
    // never recovers. Below the breakpoint that reveals the map, the list is
    // what matters — so nothing is loaded and no tile is fetched.
    if (this.element.offsetParent === null) return

    const { map, tileLayer, circleMarker, latLngBounds } = await import("leaflet")
      .then((L) => L.default ?? L)

    this.map = map(this.element, { scrollWheelZoom: false })

    tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 18,
      // Required by the OpenStreetMap licence, and displayed rather than hidden.
      attribution: this.element.dataset.attribution
    }).addTo(this.map)

    const markers = this.pointsValue.map((point) =>
      circleMarker([point.latitude, point.longitude], {
        radius: 7,
        weight: 2,
        color: "#1F5F7A",
        fillColor: "#1F5F7A",
        fillOpacity: point.featured ? 0.9 : 0.45
      })
        .bindPopup(this.popup(point))
        .addTo(this.map)
    )

    if (markers.length > 0) {
      this.map.fitBounds(latLngBounds(markers.map((m) => m.getLatLng())).pad(0.2))
    } else if (this.hasCenterValue) {
      this.map.setView([this.centerValue.latitude, this.centerValue.longitude], this.zoomValue)
    } else {
      // Metropolitan France, roughly centred.
      this.map.setView([46.6, 2.4], this.zoomValue)
    }
  }

  disconnect() {
    this.map?.remove()
  }

  // Built with the DOM rather than an HTML string: a shop name is user input,
  // and it must never be parsed as markup.
  popup(point) {
    const wrapper = document.createElement("div")

    const link = document.createElement("a")
    link.href = point.url
    link.textContent = point.name
    link.className = "font-display text-base font-bold uppercase"

    const city = document.createElement("p")
    city.textContent = point.city ?? ""
    city.className = "text-sm"

    wrapper.append(link, city)
    return wrapper
  }
}
