// Fitloop-styled <dialog> alerts/confirms (replaces 127.0.0.1 native prompts).
const DIALOG_ID = "fitloop-dialog"

function dialogElement() {
  return document.getElementById(DIALOG_ID)
}

function target(name) {
  return dialogElement()?.querySelector(`[data-fitloop-dialog-target='${name}']`)
}

function resetDialogState() {
  const cancelBtn = target("cancel")
  if (cancelBtn) cancelBtn.hidden = true
}

function showDialog() {
  const dialog = dialogElement()
  if (!dialog || typeof dialog.showModal !== "function") return false

  dialog.showModal()
  return true
}

export function configureTurboConfirm() {
  const turbo = window.Turbo
  if (!turbo?.config?.forms) return

  turbo.config.forms.confirm = (message) => fitloopConfirm(message)
}

export function fitloopAlert(message, title = null) {
  resetDialogState()
  const dialog = dialogElement()
  if (!dialog) {
    window.alert(message)
    return Promise.resolve()
  }

  const titleEl = target("title")
  const messageEl = target("message")
  if (titleEl) titleEl.textContent = title || dialog.dataset.defaultTitle || "Fitloop"
  if (messageEl) messageEl.textContent = message

  return new Promise((resolve) => {
    const onClose = () => {
      dialog.removeEventListener("close", onClose)
      resetDialogState()
      resolve()
    }
    dialog.addEventListener("close", onClose)
    if (!showDialog()) {
      window.alert(message)
      resolve()
    }
  })
}

export function fitloopConfirm(message, title = null) {
  resetDialogState()
  const dialog = dialogElement()
  if (!dialog) return Promise.resolve(window.confirm(message))

  const titleEl = target("title")
  const messageEl = target("message")
  const cancelBtn = target("cancel")
  if (titleEl) titleEl.textContent = title || dialog.dataset.defaultTitle || "Fitloop"
  if (messageEl) messageEl.textContent = message
  if (cancelBtn) cancelBtn.hidden = false

  return new Promise((resolve) => {
    const onClose = () => {
      dialog.removeEventListener("close", onClose)
      const accepted = dialog.returnValue === "ok"
      resetDialogState()
      resolve(accepted)
    }
    dialog.addEventListener("close", onClose)
    if (!showDialog()) resolve(window.confirm(message))
  })
}
