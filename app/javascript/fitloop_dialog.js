// Fitloop-styled <dialog> alerts/confirms (replaces 127.0.0.1 native prompts).
const DIALOG_ID = "fitloop-dialog"

function dialogElement() {
  return document.getElementById(DIALOG_ID)
}

function target(name) {
  return dialogElement()?.querySelector(`[data-fitloop-dialog-target='${name}']`)
}

function defaultAcceptLabel() {
  return dialogElement()?.dataset.defaultAccept || "OK"
}

function defaultCancelLabel() {
  return dialogElement()?.dataset.defaultCancel || "Cancel"
}

function resetDialogState() {
  const cancelBtn = target("cancel")
  const acceptBtn = target("accept")
  if (cancelBtn) {
    cancelBtn.hidden = true
    cancelBtn.textContent = defaultCancelLabel()
  }
  if (acceptBtn) acceptBtn.textContent = defaultAcceptLabel()
}

function showDialog() {
  const dialog = dialogElement()
  if (!dialog || typeof dialog.showModal !== "function") return false

  dialog.showModal()
  return true
}

function readConfirmOptions(formElement, submitter) {
  const nodes = [submitter, formElement].filter(Boolean)
  const read = (key) => {
    for (const node of nodes) {
      const value = node.dataset?.[key]
      if (value) return value
    }
    return null
  }

  return {
    title: read("turboConfirmTitle"),
    acceptLabel: read("turboConfirmAccept") || read("turboConfirmButton"),
    cancelLabel: read("turboConfirmCancel")
  }
}

export function configureTurboConfirm() {
  const turbo = window.Turbo
  if (!turbo?.config?.forms) return

  turbo.config.forms.confirm = (message, formElement, submitter) => {
    const options = readConfirmOptions(formElement, submitter)
    return fitloopConfirm(message, options.title, options)
  }
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

export function fitloopConfirm(message, title = null, { acceptLabel = null, cancelLabel = null } = {}) {
  resetDialogState()
  const dialog = dialogElement()
  if (!dialog) return Promise.resolve(window.confirm(message))

  const titleEl = target("title")
  const messageEl = target("message")
  const cancelBtn = target("cancel")
  const acceptBtn = target("accept")
  if (titleEl) titleEl.textContent = title || dialog.dataset.defaultTitle || "Fitloop"
  if (messageEl) messageEl.textContent = message
  if (cancelBtn) {
    cancelBtn.hidden = false
    if (cancelLabel) cancelBtn.textContent = cancelLabel
  }
  if (acceptBtn && acceptLabel) acceptBtn.textContent = acceptLabel

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
