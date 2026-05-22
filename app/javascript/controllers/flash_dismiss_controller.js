import { Controller } from "@hotwired/stimulus"

const DEFAULT_DELAY_MS = 5000
const FADE_MS = 320

export default class extends Controller {
  static values = {
    delay: { type: Number, default: DEFAULT_DELAY_MS }
  }

  connect() {
    this.scheduleDismiss()
  }

  disconnect() {
    this.clearScheduledDismiss()
  }

  pause() {
    this.clearScheduledDismiss()
  }

  resume() {
    this.scheduleDismiss()
  }

  scheduleDismiss() {
    this.clearScheduledDismiss()
    this.dismissTimeout = window.setTimeout(() => this.dismiss(), this.delayValue)
  }

  clearScheduledDismiss() {
    if (this.dismissTimeout) {
      window.clearTimeout(this.dismissTimeout)
      this.dismissTimeout = null
    }
  }

  dismiss() {
    this.clearScheduledDismiss()

    const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (prefersReducedMotion) {
      this.element.remove()
      return
    }

    this.element.classList.add("flash--dismissing")
    window.setTimeout(() => {
      if (this.element.isConnected) this.element.remove()
    }, FADE_MS)
  }
}
