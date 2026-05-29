import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    statusUrl: String,
    pollIntervalMs: { type: Number, default: 2500 }
  }

  connect() {
    this.poll()
    this.intervalId = window.setInterval(() => this.poll(), this.pollIntervalMsValue)
  }

  disconnect() {
    if (this.intervalId) {
      window.clearInterval(this.intervalId)
      this.intervalId = null
    }
  }

  async poll() {
    const response = await fetch(this.statusUrlValue, {
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    })

    if (!response.ok) return

    const data = await response.json()
    if (data.status === "succeeded" && data.gateway_status === "succeeded" && data.redirect_url) {
      this.stopPolling()
      window.location.href = data.redirect_url
      return
    }

    if (data.status === "failed") this.stopPolling()
  }

  stopPolling() {
    if (this.intervalId) {
      window.clearInterval(this.intervalId)
      this.intervalId = null
    }
  }
}
