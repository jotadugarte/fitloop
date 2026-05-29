import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message", "timeoutPanel", "title", "successLead"]
  static values = {
    statusUrl: String,
    pollIntervalMs: { type: Number, default: 2500 },
    timeoutMs: { type: Number, default: 60000 },
    redirectDelayMs: { type: Number, default: 4000 },
    checkoutUrl: String,
    successTitle: String,
    successBody: String,
    timeoutTitle: String,
    revisit: { type: Boolean, default: false },
    revisitTitle: String,
    revisitBody: String
  }

  connect() {
    this.startedAt = Date.now()
    if (this.revisitValue) this.applyRevisitCopy()
    this.poll()
    this.intervalId = window.setInterval(() => this.poll(), this.pollIntervalMsValue)
  }

  applyRevisitCopy() {
    if (this.hasTitleTarget && this.revisitTitleValue) {
      this.titleTarget.textContent = this.revisitTitleValue
    }
    if (this.hasMessageTarget && this.revisitBodyValue) {
      this.messageTarget.textContent = this.revisitBodyValue
    }
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
    if (data.status === "succeeded" && data.gateway_status === "succeeded" && data.redirect_url) {
      this.stopPolling()
      this.showSuccessThenRedirect(data.redirect_url)
      return
    }

    if (data.checkout_return_url) {
      this.stopPolling()
      window.location.href = data.checkout_return_url
      return
    }

    if (data.checkout_failed_url) {
      this.stopPolling()
      window.location.href = data.checkout_failed_url
      return
    }

    if (data.status === "failed") {
      this.stopPolling()
      window.location.href = this.checkoutUrlValue
    }
  }

  timedOut() {
    return Date.now() - this.startedAt >= this.timeoutMsValue
  }

  showTimeout() {
    this.stopPolling()
    if (this.hasTitleTarget && this.timeoutTitleValue) {
      this.titleTarget.textContent = this.timeoutTitleValue
    }
    if (this.hasTimeoutPanelTarget) this.timeoutPanelTarget.hidden = false
    if (this.hasMessageTarget) this.messageTarget.hidden = true
  }

  showSuccessThenRedirect(url) {
    if (this.hasTitleTarget && this.successTitleValue) {
      this.titleTarget.textContent = this.successTitleValue
    }
    if (this.hasMessageTarget) this.messageTarget.hidden = true
    if (this.hasTimeoutPanelTarget) this.timeoutPanelTarget.hidden = true
    if (this.hasSuccessLeadTarget) {
      this.successLeadTarget.textContent = this.successBodyValue
      this.successLeadTarget.hidden = false
    }

    window.setTimeout(() => {
      window.location.href = url
    }, this.redirectDelayMsValue)
  }

  stopPolling() {
    if (this.intervalId) {
      window.clearInterval(this.intervalId)
      this.intervalId = null
    }
  }
}
