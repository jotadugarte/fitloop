// [REQ-FIT-UI-001] Composer validation and keyboard guards for sheet inventory.

export function validateComposer(data, context) {
  const width = parseFloat(data.width)
  const height = parseFloat(data.height)
  if (!data.width || !data.height || Number.isNaN(width) || Number.isNaN(height) || width <= 0 || height <= 0) {
    window.alert(context.alertDimensions)
    return false
  }
  if (data.quantity !== "") {
    const qty = parseInt(data.quantity, 10)
    if (Number.isNaN(qty) || qty < 1) {
      window.alert(context.alertQuantity)
      return false
    }
  }
  if (data.quantity === "" && context.hasUnlimitedStock() && !context.editingUnlimitedRow()) {
    window.alert(context.alertSingleUnlimited)
    return false
  }
  return true
}

export function isNavigationOrEditKey(event) {
  if (event.ctrlKey || event.metaKey) return true
  return [
    "Backspace",
    "Delete",
    "Tab",
    "Escape",
    "Enter",
    "ArrowLeft",
    "ArrowRight",
    "ArrowUp",
    "ArrowDown",
    "Home",
    "End"
  ].includes(event.key)
}

export function blockDecimalKey(event) {
  if (isNavigationOrEditKey(event)) return
  if (event.key === "." && !event.target.value.includes(".")) return
  if (/^\d$/.test(event.key)) return
  event.preventDefault()
}

export function blockIntegerKey(event) {
  if (isNavigationOrEditKey(event)) return
  if (/^\d$/.test(event.key)) return
  event.preventDefault()
}
