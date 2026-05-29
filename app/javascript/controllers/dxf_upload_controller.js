import { Controller } from "@hotwired/stimulus"
import { fitloopAlert } from "fitloop_dialog"
import { withWorkspaceTabHeaders } from "workspace_tab"

export default class extends Controller {
  static targets = ["input", "fileName"]
  static values = { url: String, emptyFiles: String, filesSelected: String }

  connect() {
    this.updateFileLabel()
  }

  upload() {
    const files = this.inputTarget.files
    this.updateFileLabel()
    if (!files?.length) return

    const body = new FormData()
    Array.from(files).forEach((file) => body.append("files[]", file))
    const token = this.csrfToken
    if (token) body.append("authenticity_token", token)

    fetch(this.urlValue, {
      method: "POST",
      body,
      headers: withWorkspaceTabHeaders({
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": token
      }),
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
        this.updateFileLabel()
      })
      .catch(() => {
        fitloopAlert(this.uploadFailedMessage)
      })
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }

  get uploadFailedMessage() {
    return this.element.dataset.dxfUploadFailedValue || "Upload failed"
  }

  updateFileLabel() {
    if (!this.hasFileNameTarget) return

    const files = this.inputTarget.files
    if (!files?.length) {
      this.fileNameTarget.textContent = this.emptyFilesLabel
      return
    }

    if (files.length === 1) {
      this.fileNameTarget.textContent = files[0].name
      return
    }

    this.fileNameTarget.textContent = this.filesSelectedLabel(files.length)
  }

  get emptyFilesLabel() {
    return this.hasEmptyFilesValue ? this.emptyFilesValue : "No files selected"
  }

  filesSelectedLabel(count) {
    const template = this.hasFilesSelectedValue
      ? this.filesSelectedValue
      : "%{count} files selected"
    return template.replace("%{count}", String(count))
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
