import { Controller } from "@hotwired/stimulus"

// [REQ-FIT-UI-001] Debounced form autosave with queued follow-up when a save is in flight.
export default class extends Controller {
  connect() {
    this.pending = false
    this.dirty = false
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
    if (!this.element.reportValidity()) return

    if (this.pending) {
      this.dirty = true
      return
    }

    this.pending = true
    this.dirty = false
    this.element.requestSubmit()
  }

  clearPending() {
    this.pending = false

    if (!this.dirty) return

    this.dirty = false
    this.submitForm()
  }
}
