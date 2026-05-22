import { Controller } from "@hotwired/stimulus"

const DEFAULT_DELAY_MS = 5000
const FADE_MS = 300

export default class extends Controller {
  static values = {
    delay: { type: Number, default: DEFAULT_DELAY_MS }
  }

  connect() {
    this.scheduleDismiss()
  }

  disconnect() {
    this.clearScheduledDismiss()
    this.clearFadeListener()
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

    this.onFadeEnd = (event) => {
      if (event.target !== this.element || event.propertyName !== "opacity") return

      this.clearFadeListener()
      if (this.element.isConnected) this.element.remove()
    }

    this.element.addEventListener("transitionend", this.onFadeEnd)
    this.element.classList.add("flash--dismissing")

    this.fadeFallbackTimeout = window.setTimeout(() => {
      this.clearFadeListener()
      if (this.element.isConnected) this.element.remove()
    }, FADE_MS + 50)
  }

  clearFadeListener() {
    if (this.onFadeEnd) {
      this.element.removeEventListener("transitionend", this.onFadeEnd)
      this.onFadeEnd = null
    }

    if (this.fadeFallbackTimeout) {
      window.clearTimeout(this.fadeFallbackTimeout)
      this.fadeFallbackTimeout = null
    }
  }
}
