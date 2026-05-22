import { Controller } from "@hotwired/stimulus"

const DRAFT_MARKER = "data-locale-workspace-draft"

// [REQ-FIT-UI-005] Attach unsaved setup drafts to locale PATCH before redirect.
export default class extends Controller {
  attachWorkspaceDraft(event) {
    const localeForm = event.currentTarget
    if (!(localeForm instanceof HTMLFormElement)) return

    localeForm.querySelectorAll(`[${DRAFT_MARKER}]`).forEach((node) => node.remove())

    const inventoryElement = document.querySelector("[data-controller~='sheet-inventory']")
    if (inventoryElement) {
      const inventory = this.application.getControllerForElementAndIdentifier(
        inventoryElement,
        "sheet-inventory"
      )
      inventory?.exportToForm(localeForm)
    }

    this.exportLayerSelection(localeForm)
  }

  exportLayerSelection(targetForm) {
    document.querySelectorAll('[name^="project_layers["]').forEach((input) => {
      if (input.disabled) return
      if (input.type === "radio" && !input.checked) return
      if (input.type === "checkbox" && !input.checked) return

      const clone = document.createElement("input")
      clone.type = "hidden"
      clone.name = input.name
      clone.value = input.value
      clone.setAttribute(DRAFT_MARKER, "true")
      targetForm.appendChild(clone)
    })
  }
}
