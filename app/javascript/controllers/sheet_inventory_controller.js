import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import {
  blockDecimalKey,
  blockIntegerKey,
  validateComposer
} from "sheet_inventory_composer"

// [REQ-FIT-UI-001] Sheet inventory composer + sortable table (finite stocks before unlimited).
export default class extends Controller {
  static targets = ["list", "template", "width", "height", "quantity"]

  static values = {
    summaryUnlimited: String,
    alertDimensions: String,
    alertQuantity: String,
    alertSingleUnlimited: String,
    hasUnlimited: Boolean
  }

  connect() {
    this.listTarget.dataset.sortable = "true"
    this.sortable = Sortable.create(this.listTarget, {
      handle: "[data-testid='sheet-stock-drag-handle']",
      draggable: "[data-sheet-inventory-row]",
      animation: 150,
      onStart: () => this.enforceTableLayout(),
      onEnd: () => {
        this.enforceTableLayout()
        this.pinUnlimitedLast()
        this.reindexSortOrders()
      }
    })
    this.enforceTableLayout()
    this.syncInventoryState()
  }

  disconnect() {
    this.sortable?.destroy()
  }

  add(event) {
    event.preventDefault()
    event.stopPropagation()
    this.addComposerToList()
  }

  flushOnSubmit(event) {
    if (!this.flushComposerIfNeeded()) event.preventDefault()
  }

  edit(event) {
    event.preventDefault()
    const row = event.target.closest("[data-sheet-inventory-row]")
    if (!row) return
    this.fillComposerFromRow(row)
    this.syncInventoryState()
  }

  remove(event) {
    event.preventDefault()
    event.stopPropagation()
    const row = event.target.closest("tr[data-sheet-inventory-row]")
    if (!row) return

    const destroyField = row.querySelector("[data-sheet-inventory-field='_destroy']")
    const idField = row.querySelector("[data-sheet-inventory-field='id']")
    if (idField?.value) {
      if (destroyField) destroyField.value = "1"
      row.dataset.destroyed = "true"
      row.style.display = "none"
    } else {
      row.remove()
    }
    this.pinUnlimitedLast()
    this.reindexSortOrders()
    this.clearComposer()
    this.syncInventoryState()
  }

  addComposerToList() {
    const data = this.readComposer()
    if (!this.validateComposer(data)) return

    const editingIndex = this.element.dataset.editingIndex
    if (editingIndex !== undefined && editingIndex !== "") {
      const row = this.listTarget.querySelector(
        `[data-sheet-inventory-row][data-sheet-inventory-index="${editingIndex}"]`
      )
      if (row) this.updateRow(row, data)
      this.pinUnlimitedLast()
      this.reindexSortOrders()
    } else {
      this.buildRow(this.nextIndex(), data)
    }
    this.clearComposer()
    this.syncInventoryState()
  }

  flushComposerIfNeeded() {
    const data = this.readComposer()
    if (!this.hasComposerInput(data)) return true
    if (!this.validateComposer(data)) return false

    this.buildRow(this.nextIndex(), data)
    this.clearComposer()
    return true
  }

  exportToForm(targetForm) {
    const sourceForm = this.element.closest("form")
    if (!sourceForm || sourceForm === targetForm) return

    targetForm.querySelectorAll("[data-locale-sheet-draft]").forEach((node) => node.remove())

    this.visibleRows().forEach((row, index) => {
      const prefix = `project[sheet_stocks_attributes][${index}]`
      row.querySelectorAll("[data-sheet-inventory-field]").forEach((field) => {
        const name = field.dataset.sheetInventoryField
        if (!name) return

        const clone = document.createElement("input")
        clone.type = "hidden"
        clone.name = `${prefix}[${name}]`
        clone.value = field.value
        clone.dataset.localeSheetDraft = "true"
        targetForm.appendChild(clone)
      })
    })

    this.exportComposerDraft(targetForm)
  }

  exportComposerDraft(targetForm) {
    ;["width_mm", "height_mm", "quantity"].forEach((name) => {
      const source = this.element.querySelector(`[name="composer_draft[${name}]"]`)
      if (!source || source.value.trim() === "") return

      const clone = document.createElement("input")
      clone.type = "hidden"
      clone.name = `composer_draft[${name}]`
      clone.value = source.value
      clone.dataset.localeSheetDraft = "true"
      targetForm.appendChild(clone)
    })
  }

  readComposer() {
    return {
      width: this.widthTarget.value.trim(),
      height: this.heightTarget.value.trim(),
      quantity: this.quantityTarget.value.trim()
    }
  }

  hasComposerInput(data) {
    return data.width !== "" || data.height !== "" || data.quantity !== ""
  }

  clearComposer() {
    this.widthTarget.value = ""
    this.heightTarget.value = ""
    this.quantityTarget.value = ""
    this.element.dataset.editingIndex = ""
  }

  validateComposer(data) {
    return validateComposer(data, this.composerContext())
  }

  composerContext() {
    return {
      alertDimensions: this.alertDimensionsValue,
      alertQuantity: this.alertQuantityValue,
      alertSingleUnlimited: this.alertSingleUnlimitedValue,
      hasUnlimitedStock: () => this.hasUnlimitedStock(),
      editingUnlimitedRow: () => this.editingUnlimitedRow()
    }
  }

  nextIndex() {
    const indices = this.visibleRows().map((row) => parseInt(row.dataset.sheetInventoryIndex || "0", 10))
    return indices.length ? Math.max(...indices) + 1 : 0
  }

  reindexSortOrders() {
    this.visibleRows().forEach((row, index) => {
      const input = row.querySelector("[data-sheet-inventory-field='sort_order']")
      if (input) input.value = index

      const priority = row.querySelector("[data-sheet-inventory-display='priority']")
      if (priority) priority.textContent = `#${index + 1}`
    })
    this.syncInventoryState()
  }

  pinUnlimitedLast() {
    const unlimitedRow = this.unlimitedRow()
    if (!unlimitedRow) return

    this.listTarget.appendChild(unlimitedRow)
  }

  buildRow(index, data) {
    const fragment = this.templateTarget.content.cloneNode(true)
    const row = fragment.querySelector("[data-sheet-inventory-row]")
    const prefix = `project[sheet_stocks_attributes][${index}]`

    row.dataset.sheetInventoryIndex = index
    this.updateRowDisplay(row, data)

    const setField = (name, value) => {
      const input = row.querySelector(`[data-sheet-inventory-field='${name}']`)
      input.name = `${prefix}[${name}]`
      input.value = value
    }

    setField("width_mm", data.width)
    setField("height_mm", data.height)
    setField("sort_order", index)
    setField("quantity", data.quantity)
    setField("_destroy", "0")

    const insertBefore = this.isUnlimitedData(data) ? null : this.unlimitedRow()
    if (insertBefore) {
      this.listTarget.insertBefore(fragment, insertBefore)
    } else {
      this.listTarget.appendChild(fragment)
    }

    this.pinUnlimitedLast()
    this.reindexSortOrders()
    this.syncInventoryState()
  }

  updateRow(row, data) {
    this.updateRowDisplay(row, data)
    row.querySelector("[data-sheet-inventory-field='width_mm']").value = data.width
    row.querySelector("[data-sheet-inventory-field='height_mm']").value = data.height
    row.querySelector("[data-sheet-inventory-field='quantity']").value = data.quantity
  }

  updateRowDisplay(row, data) {
    row.querySelector("[data-sheet-inventory-display='width_mm']").textContent = this.formatDimension(data.width)
    row.querySelector("[data-sheet-inventory-display='height_mm']").textContent = this.formatDimension(data.height)
    row.querySelector("[data-sheet-inventory-display='quantity']").textContent = this.quantityLabel(data.quantity)
  }

  fillComposerFromRow(row) {
    this.widthTarget.value = row.querySelector("[data-sheet-inventory-field='width_mm']").value
    this.heightTarget.value = row.querySelector("[data-sheet-inventory-field='height_mm']").value
    this.quantityTarget.value = row.querySelector("[data-sheet-inventory-field='quantity']").value
    this.element.dataset.editingIndex = row.dataset.sheetInventoryIndex
  }

  visibleRows() {
    return Array.from(
      this.listTarget.querySelectorAll("[data-sheet-inventory-row]:not([data-destroyed='true'])")
    )
  }

  unlimitedRow() {
    return this.visibleRows().find((row) => this.isUnlimitedRow(row))
  }

  isUnlimitedRow(row) {
    const quantityField = row.querySelector("[data-sheet-inventory-field='quantity']")
    return quantityField?.value === ""
  }

  isUnlimitedData(data) {
    return data.quantity === ""
  }

  formatDimension(value) {
    const number = parseFloat(value)
    if (Number.isNaN(number)) return value
    if (Number.isInteger(number)) return String(number)
    return String(Math.round(number * 10) / 10)
  }

  quantityLabel(quantity) {
    return quantity !== "" ? quantity : this.summaryUnlimitedValue
  }

  syncInventoryState() {
    this.hasUnlimitedValue = this.hasUnlimitedStock()
  }

  enforceTableLayout() {
    this.listTarget.style.display = "table-row-group"
    this.listTarget.querySelectorAll("tr[data-sheet-inventory-row]").forEach((row) => {
      if (row.dataset.destroyed === "true") {
        row.style.display = "none"
        return
      }

      row.style.display = "table-row"
      row.querySelectorAll("td").forEach((cell) => {
        cell.style.display = "table-cell"
      })
    })
  }

  blockDecimalKey(event) {
    blockDecimalKey(event)
  }

  blockIntegerKey(event) {
    blockIntegerKey(event)
  }

  hasUnlimitedStock() {
    return Boolean(this.unlimitedRow())
  }

  editingUnlimitedRow() {
    const editingIndex = this.element.dataset.editingIndex
    if (editingIndex === undefined || editingIndex === "") return false

    const row = this.listTarget.querySelector(
      `[data-sheet-inventory-row][data-sheet-inventory-index="${editingIndex}"]`
    )
    return Boolean(row && this.isUnlimitedRow(row))
  }
}
