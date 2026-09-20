import { Controller } from "@hotwired/stimulus"

// Opens the browser's print dialogue. The button is hidden from the printed
// page itself, and Ctrl-P does the same thing for anyone who prefers it.
export default class extends Controller {
  now() {
    window.print()
  }
}
