import { Controller } from "@hotwired/stimulus"

// Keeps nesting UI in sync when Turbo Streams are missed (fast jobs, late WebSocket connect).
export default class extends Controller {
  static values = {
    url: String
  }

  connect() {
    this.runSyncLoop()
  }

  disconnect() {
    this.clearTimers()
  }

  runSyncLoop() {
    this.poll()
    if (!this.shouldKeepPolling()) return

    this.intervalId = window.setInterval(() => this.poll(), 1500)
    this.burstIds = [400, 900, 2000, 3500].map((delay) =>
      window.setTimeout(() => this.poll(), delay)
    )
  }

  shouldKeepPolling() {
    const badge = document.querySelector('[data-testid="project-status-badge"]')
    if (badge?.classList.contains("status-badge--processing")) return true

    return document.querySelector('[data-testid="nesting-progress"]') !== null
  }

  clearTimers() {
    if (this.intervalId) {
      window.clearInterval(this.intervalId)
      this.intervalId = null
    }
    if (this.burstIds) {
      this.burstIds.forEach((id) => window.clearTimeout(id))
      this.burstIds = null
    }
  }

  async poll() {
    const response = await fetch(this.urlValue, {
      headers: { Accept: "text/vnd.turbo-stream.html" },
      credentials: "same-origin"
    })

    if (!response.ok) return

    const message = await response.text()
    if (message.trim()) window.Turbo.renderStreamMessage(message)

    if (!this.shouldKeepPolling()) this.clearTimers()
  }
}
