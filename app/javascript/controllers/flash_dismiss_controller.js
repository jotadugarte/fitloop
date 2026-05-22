import { Controller } from "@hotwired/stimulus"

const DEFAULT_DELAY_MS = 5000
const DISMISS_ANIMATION_MS = 260

export default class extends Controller {
  static values = {
    delay: { type: Number, default: DEFAULT_DELAY_MS }
  }

  connect() {
    this.dismissAt = Date.now() + this.delayValue
    this.scheduleDismiss()
  }

  disconnect() {
    this.clearScheduledDismiss()
    this.clearDismissAnimation()
  }

  pause() {
    this.clearScheduledDismiss()
  }

  resume() {
    this.scheduleDismiss()
  }

  scheduleDismiss() {
    this.clearScheduledDismiss()
    const remaining = Math.max(0, this.dismissAt - Date.now())
    this.dismissTimeout = window.setTimeout(() => this.dismiss(), remaining)
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

    this.onAnimationEnd = (event) => {
      if (event.target !== this.element || event.animationName !== "flash-dismiss-out") return

      this.removeElement()
    }

    this.element.addEventListener("animationend", this.onAnimationEnd)
    this.element.classList.add("flash--dismissing")

    this.dismissFallbackTimeout = window.setTimeout(() => {
      this.removeElement()
    }, DISMISS_ANIMATION_MS + 40)
  }

  removeElement() {
    this.clearDismissAnimation()
    if (this.element.isConnected) this.element.remove()
  }

  clearDismissAnimation() {
    if (this.onAnimationEnd) {
      this.element.removeEventListener("animationend", this.onAnimationEnd)
      this.onAnimationEnd = null
    }

    if (this.dismissFallbackTimeout) {
      window.clearTimeout(this.dismissFallbackTimeout)
      this.dismissFallbackTimeout = null
    }
  }
}
