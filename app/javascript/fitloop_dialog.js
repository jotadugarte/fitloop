// Native <dialog> alerts titled "Fitloop" instead of browser origin (127.0.0.1).
const DEFAULT_TITLE = "Fitloop"

export function fitloopAlert(message, title = DEFAULT_TITLE) {
  const dialog = document.getElementById("fitloop-dialog")
  if (!dialog) {
    window.alert(message)
    return Promise.resolve()
  }

  const titleEl = dialog.querySelector("[data-fitloop-dialog-target='title']")
  const messageEl = dialog.querySelector("[data-fitloop-dialog-target='message']")
  if (titleEl) titleEl.textContent = title
  if (messageEl) messageEl.textContent = message

  return new Promise((resolve) => {
    const onClose = () => {
      dialog.removeEventListener("close", onClose)
      resolve()
    }
    dialog.addEventListener("close", onClose)
    if (typeof dialog.showModal === "function") {
      dialog.showModal()
    } else {
      window.alert(message)
      resolve()
    }
  })
}
