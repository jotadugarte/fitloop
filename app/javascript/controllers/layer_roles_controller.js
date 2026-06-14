import { Controller } from "@hotwired/stimulus"

// Keeps primary (radio) and auxiliary (checkbox) mutually exclusive per layer row.
export default class extends Controller {
  static targets = ["row", "primary", "auxiliary", "meta"]
  static values = {
    metaTemplate: String,
    total: Number
  }

  connect() {
    this.updateSelectionCount()
  }

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
    this.updateSelectionCount()
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

    this.updateSelectionCount()
  }

  updateSelectionCount() {
    if (!this.hasMetaTarget || !this.metaTemplateValue) return

    let selected = 0
    if (this.primaryTargets.some((input) => input.checked)) selected += 1
    selected += this.auxiliaryTargets.filter((input) => input.checked).length

    this.metaTarget.textContent = this.metaTemplateValue
      .replace("%{selected}", String(selected))
      .replace("%{total}", String(this.totalValue))
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

  setDeleting(event) {
    const submitter = event.detail.submitter
    if (submitter && this.element.contains(submitter)) {
      this.element.classList.add("is-deleting")
    }
  }
}
