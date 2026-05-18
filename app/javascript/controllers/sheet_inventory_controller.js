import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// [REQ-FIT-UI-001] Sheet inventory composer + sortable table (finite stocks before unlimited).
export default class extends Controller {
  static targets = ["list", "template", "width", "height", "quantity"]

  static values = {
    summaryUnlimited: String,
    alertDimensions: String,
    alertQuantity: String
  }

  connect() {
    this.listTarget.dataset.sortable = "true"
    this.sortable = Sortable.create(this.listTarget, {
      handle: "[data-testid='sheet-stock-drag-handle']",
      draggable: "[data-sheet-inventory-row]",
      animation: 150,
      onEnd: () => {
        this.pinUnlimitedLast()
        this.reindexSortOrders()
      }
    })
    this.reindexSortOrders()
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
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-sheet-inventory-row]")
    if (!row) return

    const destroyField = row.querySelector("[data-sheet-inventory-field='_destroy']")
    const idField = row.querySelector("[data-sheet-inventory-field='id']")
    if (idField && idField.value) {
      destroyField.value = "1"
      row.dataset.destroyed = "true"
      row.hidden = true
    } else {
      row.remove()
    }
    this.pinUnlimitedLast()
    this.reindexSortOrders()
    this.clearComposer()
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
  }

  flushComposerIfNeeded() {
    const data = this.readComposer()
    if (!this.hasComposerInput(data)) return true
    if (!this.validateComposer(data)) return false

    this.buildRow(this.nextIndex(), data)
    this.clearComposer()
    return true
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
    const width = parseFloat(data.width)
    const height = parseFloat(data.height)
    if (!data.width || !data.height || Number.isNaN(width) || Number.isNaN(height) || width <= 0 || height <= 0) {
      window.alert(this.alertDimensionsValue)
      return false
    }
    if (data.quantity !== "") {
      const qty = parseInt(data.quantity, 10)
      if (Number.isNaN(qty) || qty < 1) {
        window.alert(this.alertQuantityValue)
        return false
      }
    }
    return true
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
}
