import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!this.urlValue) return

    const frame = document.createElement("iframe")
    frame.hidden = true
    frame.src = this.urlValue
    frame.setAttribute("aria-hidden", "true")
    this.element.appendChild(frame)

    const cleanUrl = new URL(window.location.href)
    cleanUrl.searchParams.delete("auto_download")
    window.history.replaceState({}, "", cleanUrl)
  }
}
