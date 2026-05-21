import { Controller } from "@hotwired/stimulus"
import { withWorkspaceTabHeaders } from "workspace_tab"

// Keeps nesting UI in sync when Turbo Streams are missed (fast jobs, late WebSocket connect).
export default class extends Controller {
  static values = {
    url: String
  }

  connect() {
    if (!this.shouldKeepPolling()) return

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
    return badge?.classList.contains("status-badge--processing") === true
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
      headers: withWorkspaceTabHeaders({ Accept: "text/vnd.turbo-stream.html" }),
      credentials: "same-origin"
    })

    if (!response.ok) return

    const message = await response.text()
    if (message.trim()) window.Turbo.renderStreamMessage(message)

    const status = document.querySelector('[data-testid="project-status-badge"]')?.dataset.projectStatus
    if (status) this.element.dataset.projectStatus = status

    if (!this.shouldKeepPolling()) this.clearTimers()
  }
}
