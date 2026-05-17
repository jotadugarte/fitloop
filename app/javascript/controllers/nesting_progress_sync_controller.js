import { Controller } from "@hotwired/stimulus"

// Polls nesting UI when the job finished before the Turbo stream subscription connected.
export default class extends Controller {
  static values = {
    url: String
  }

  connect() {
    this.poll()
    this.timer = window.setInterval(() => this.poll(), 2000)
  }

  disconnect() {
    if (this.timer) window.clearInterval(this.timer)
  }

  async poll() {
    const response = await fetch(this.urlValue, {
      headers: { Accept: "text/vnd.turbo-stream.html" },
      credentials: "same-origin"
    })

    if (!response.ok) return

    const message = await response.text()
    if (message.trim()) window.Turbo.renderStreamMessage(message)

    if (document.querySelector('[data-testid="nesting-result"]')) {
      window.clearInterval(this.timer)
    }
  }
}
