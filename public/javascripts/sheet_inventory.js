(function () {
  const ROOT_SELECTOR = "[data-sheet-inventory]";

  function nextIndex(list) {
    const indices = Array.from(list.querySelectorAll("[data-sheet-inventory-row]")).map((row) =>
      parseInt(row.dataset.sheetInventoryIndex || "0", 10)
    );
    return indices.length ? Math.max(...indices) + 1 : 0;
  }

  function reindexSortOrders(list) {
    list.querySelectorAll("[data-sheet-inventory-row]:not([data-destroyed='true'])").forEach((row, index) => {
      const input = row.querySelector("[data-sheet-inventory-field='sort_order']");
      if (input) input.value = index;
    });
  }

  function readComposer(root) {
    const quantityInput = root.querySelector("[data-sheet-inventory-composer-quantity]");
    return {
      width: root.querySelector("[data-sheet-inventory-composer-width]").value,
      height: root.querySelector("[data-sheet-inventory-composer-height]").value,
      quantity: quantityInput.value.trim()
    };
  }

  function clearComposer(root) {
    root.querySelector("[data-sheet-inventory-composer-width]").value = "";
    root.querySelector("[data-sheet-inventory-composer-height]").value = "";
    root.querySelector("[data-sheet-inventory-composer-quantity]").value = "";
    root.dataset.editingIndex = "";
  }

  function formatDimension(value) {
    const number = parseFloat(value);
    if (Number.isNaN(number)) return value;
    if (Number.isInteger(number)) return String(number);
    return String(Math.round(number * 10) / 10);
  }

  function quantityLabel(root, quantity) {
    return quantity !== "" ? quantity : root.dataset.summaryUnlimited;
  }

  function updateRowDisplay(row, root, data) {
    row.querySelector("[data-sheet-inventory-display='width_mm']").textContent = formatDimension(data.width);
    row.querySelector("[data-sheet-inventory-display='height_mm']").textContent = formatDimension(data.height);
    row.querySelector("[data-sheet-inventory-display='quantity']").textContent = quantityLabel(root, data.quantity);
  }

  function validateComposer(root, data) {
    const width = parseFloat(data.width);
    const height = parseFloat(data.height);
    if (!data.width || !data.height || Number.isNaN(width) || Number.isNaN(height) || width <= 0 || height <= 0) {
      window.alert(root.dataset.alertDimensions);
      return false;
    }
    if (data.quantity !== "") {
      const qty = parseInt(data.quantity, 10);
      if (Number.isNaN(qty) || qty < 1) {
        window.alert(root.dataset.alertQuantity);
        return false;
      }
    }
    return true;
  }

  function buildRow(root, list, index, data) {
    const template = root.querySelector("[data-sheet-inventory-row-template]");
    const fragment = template.content.cloneNode(true);
    const row = fragment.querySelector("[data-sheet-inventory-row]");
    const prefix = `project[sheet_stocks_attributes][${index}]`;

    row.dataset.sheetInventoryIndex = index;
    updateRowDisplay(row, root, data);

    const setField = (name, value) => {
      const input = row.querySelector(`[data-sheet-inventory-field='${name}']`);
      input.name = `${prefix}[${name}]`;
      input.value = value;
    };

    setField("width_mm", data.width);
    setField("height_mm", data.height);
    setField("sort_order", index);
    setField("quantity", data.quantity);
    setField("_destroy", "0");

    list.appendChild(fragment);
    reindexSortOrders(list);
  }

  function updateRow(row, root, data) {
    updateRowDisplay(row, root, data);
    row.querySelector("[data-sheet-inventory-field='width_mm']").value = data.width;
    row.querySelector("[data-sheet-inventory-field='height_mm']").value = data.height;
    row.querySelector("[data-sheet-inventory-field='quantity']").value = data.quantity;
  }

  function fillComposerFromRow(root, row) {
    root.querySelector("[data-sheet-inventory-composer-width]").value =
      row.querySelector("[data-sheet-inventory-field='width_mm']").value;
    root.querySelector("[data-sheet-inventory-composer-height]").value =
      row.querySelector("[data-sheet-inventory-field='height_mm']").value;
    root.querySelector("[data-sheet-inventory-composer-quantity]").value =
      row.querySelector("[data-sheet-inventory-field='quantity']").value;
    root.dataset.editingIndex = row.dataset.sheetInventoryIndex;
  }

  function initRoot(root) {
    const list = root.querySelector("[data-sheet-inventory-list]");
    const addButton = root.querySelector("[data-sheet-inventory-add]");

    addButton.addEventListener("click", () => {
      const data = readComposer(root);
      if (!validateComposer(root, data)) return;

      const editingIndex = root.dataset.editingIndex;
      if (editingIndex !== undefined && editingIndex !== "") {
        const row = list.querySelector(`[data-sheet-inventory-row][data-sheet-inventory-index="${editingIndex}"]`);
        if (row) updateRow(row, root, data);
      } else {
        buildRow(root, list, nextIndex(list), data);
      }
      clearComposer(root);
    });

    list.addEventListener("click", (event) => {
      const editBtn = event.target.closest("[data-sheet-inventory-edit]");
      const deleteBtn = event.target.closest("[data-sheet-inventory-remove]");

      if (editBtn) {
        const row = editBtn.closest("[data-sheet-inventory-row]");
        fillComposerFromRow(root, row);
        return;
      }

      if (deleteBtn) {
        const row = deleteBtn.closest("[data-sheet-inventory-row]");
        const destroyField = row.querySelector("[data-sheet-inventory-field='_destroy']");
        const idField = row.querySelector("[data-sheet-inventory-field='id']");
        if (idField && idField.value) {
          destroyField.value = "1";
          row.dataset.destroyed = "true";
          row.hidden = true;
        } else {
          row.remove();
        }
        reindexSortOrders(list);
        clearComposer(root);
      }
    });
  }

  function boot() {
    document.querySelectorAll(ROOT_SELECTOR).forEach(initRoot);
  }

  document.addEventListener("DOMContentLoaded", boot);
  document.addEventListener("turbo:load", boot);
})();
