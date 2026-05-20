import { Controller } from "@hotwired/stimulus"

// Keeps primary (radio) and auxiliary (checkbox) mutually exclusive per layer row.
export default class extends Controller {
  static targets = ["row", "primary", "auxiliary"]

  primaryChanged(event) {
    if (!event.target.checked) return

    const row = event.target.closest("[data-layer-roles-target='row']")
    if (!row) return

    const auxiliary = row.querySelector("[data-layer-roles-target='auxiliary']")
    if (!auxiliary) return

    auxiliary.checked = false
    auxiliary.disabled = true

    this.#enableAuxiliaryOnOtherRows(row)
    this.#enablePrimaryOnRow(row)
  }

  auxiliaryChanged(event) {
    const row = event.target.closest("[data-layer-roles-target='row']")
    if (!row) return

    const primary = row.querySelector("[data-layer-roles-target='primary']")
    if (!primary) return

    if (event.target.checked) {
      if (primary.checked) primary.checked = false
      primary.disabled = true
    } else {
      primary.disabled = false
    }
  }

  #enableAuxiliaryOnOtherRows(activeRow) {
    this.rowTargets.forEach((row) => {
      if (row === activeRow) return

      const auxiliary = row.querySelector("[data-layer-roles-target='auxiliary']")
      if (auxiliary) auxiliary.disabled = false
    })
  }

  #enablePrimaryOnRow(row) {
    const primary = row.querySelector("[data-layer-roles-target='primary']")
    if (primary) primary.disabled = false
  }
}
