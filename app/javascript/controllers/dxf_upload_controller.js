import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { url: String }

  upload() {
    const files = this.inputTarget.files
    if (!files?.length) return

    const body = new FormData()
    Array.from(files).forEach((file) => body.append("files[]", file))
    const token = this.csrfToken
    if (token) body.append("authenticity_token", token)

    fetch(this.urlValue, {
      method: "POST",
      body,
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": token
      },
      credentials: "same-origin"
    })
      .then(async (response) => {
        const bodyText = await response.text()
        if (!response.ok) throw new Error(`upload failed (${response.status})`)

        if (bodyText.includes("turbo-stream") && window.Turbo?.renderStreamMessage) {
          window.Turbo.renderStreamMessage(bodyText)
          this.expandLayerSections()
        } else if (response.redirected) {
          window.Turbo.visit(response.url)
        }

        this.inputTarget.value = ""
      })
      .catch(() => {
        window.alert(this.uploadFailedMessage)
      })
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }

  get uploadFailedMessage() {
    return this.element.dataset.dxfUploadFailedValue || "Upload failed"
  }

  expandLayerSections() {
    document.querySelector("[data-testid='setup-dxf-upload']")?.setAttribute("open", "")
    document.querySelector("[data-testid='source-dxf-detail']")?.setAttribute("open", "")

    // Turbo stream DOM is synchronous; wait one frame so <details open> layout settles.
    requestAnimationFrame(() => {
      requestAnimationFrame(() => this.scrollToLayers())
    })
  }

  scrollToLayers() {
    const layersPanel = document.querySelector("[data-testid='dxf-files-layers']")
    const expandedEntry =
      document.querySelector("[data-testid='dxf-file-entry'][open]") ||
      document.querySelector("[data-testid='dxf-file-entry']:last-of-type")

    const target = layersPanel || expandedEntry
    if (!target) return

    target.scrollIntoView({ behavior: "smooth", block: "start", inline: "nearest" })
  }
}
