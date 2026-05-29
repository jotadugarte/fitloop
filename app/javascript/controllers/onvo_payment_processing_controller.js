import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message", "timeoutPanel"]
  static values = {
    statusUrl: String,
    pollIntervalMs: { type: Number, default: 2500 },
    timeoutMs: { type: Number, default: 60000 },
    checkoutUrl: String
  }

  connect() {
    this.startedAt = Date.now()
    this.poll()
    this.intervalId = window.setInterval(() => this.poll(), this.pollIntervalMsValue)
  }

  disconnect() {
    this.stopPolling()
  }

  async poll() {
    if (this.timedOut()) {
      this.showTimeout()
      return
    }

    const response = await fetch(this.statusUrlValue, {
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    })

    if (!response.ok) return

    const data = await response.json()
    if (data.status === "succeeded" && data.redirect_url) {
      this.stopPolling()
      window.location.href = data.redirect_url
      return
    }

    if (data.status === "failed") {
      this.stopPolling()
      window.location.href = `${this.checkoutUrlValue}?payment_failed=1`
    }
  }

  timedOut() {
    return Date.now() - this.startedAt >= this.timeoutMsValue
  }

  showTimeout() {
    this.stopPolling()
    if (this.hasTimeoutPanelTarget) this.timeoutPanelTarget.hidden = false
    if (this.hasMessageTarget) this.messageTarget.hidden = true
  }

  stopPolling() {
    if (this.intervalId) {
      window.clearInterval(this.intervalId)
      this.intervalId = null
    }
  }
}
