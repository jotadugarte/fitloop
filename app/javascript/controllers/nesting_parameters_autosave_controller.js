import { Controller } from "@hotwired/stimulus"

// [REQ-FIT-UI-001] Auto-save kerf/margin when nesting parameter fields change.
export default class extends Controller {
  connect() {
    this.pending = false
    this.saveTimer = null
  }

  disconnect() {
    clearTimeout(this.saveTimer)
  }

  scheduleSave() {
    clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.submitForm(), 350)
  }

  submitForm() {
    if (this.pending || !this.element.reportValidity()) return

    this.pending = true
    this.element.requestSubmit()
  }

  clearPending() {
    this.pending = false
  }
}
