import { Controller } from "@hotwired/stimulus"

// Cloudflare's script draws its widget once, when it loads. A form refused
// and rendered again by Turbo brings a new, empty container that nothing
// draws (reported on 15/10/2026: « Cannot find Widget », and the client had
// to reload the page to try again). Drawn here whenever the script is already
// there; on a first visit the script does it itself.
export default class extends Controller {
  connect() {
    const turnstile = window.turnstile
    if (!turnstile || this.element.querySelector("iframe")) return

    try {
      this.widgetId = turnstile.render(this.element)
    } catch (error) {
      console.warn("[turnstile]", error)
    }
  }

  disconnect() {
    if (this.widgetId === undefined || !window.turnstile) return

    try { window.turnstile.remove(this.widgetId) } catch (_) { /* already gone */ }
    this.widgetId = undefined
  }
}
