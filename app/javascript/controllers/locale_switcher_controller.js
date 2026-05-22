import { Controller } from "@hotwired/stimulus"

// [REQ-FIT-UI-005] Attach unsaved sheet inventory to locale PATCH before redirect.
export default class extends Controller {
  attachSheetInventory(event) {
    const localeForm = event.currentTarget
    if (!(localeForm instanceof HTMLFormElement)) return

    const inventoryElement = document.querySelector("[data-controller~='sheet-inventory']")
    if (!inventoryElement) return

    const inventory = this.application.getControllerForElementAndIdentifier(
      inventoryElement,
      "sheet-inventory"
    )
    if (!inventory) return

    inventory.exportToForm(localeForm)
  }
}
