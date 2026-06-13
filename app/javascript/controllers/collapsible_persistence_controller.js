import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "fitloop:collapsible-panels"

function readStore() {
  try {
    return JSON.parse(sessionStorage.getItem(STORAGE_KEY) || "{}")
  } catch {
    return {}
  }
}

function writeStore(store) {
  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(store))
}

function panelKey(details) {
  const attachmentId = details.dataset.attachmentId
  if (attachmentId) return `attachment:${attachmentId}`

  const collapsibleKey = details.dataset.collapsibleKey
  if (collapsibleKey) return collapsibleKey

  const testId = details.dataset.testid
  if (testId) return testId

  return null
}

function pagePath() {
  return window.location.pathname
}

function setupModeActive() {
  return document.querySelector("[data-workshop-setup-mode='true']") != null
}

const SETUP_OPEN_PANEL_KEYS = new Set([
  "workshop-sheet-inventory",
  "workshop-source-dxf-detail"
])

function lockedClosedOnPath(path, key, details) {
  if (details?.dataset.collapsiblePreserveOpen === "true") return false
  if (path !== "/taller") return false
  if (document.querySelector("[data-workshop-setup-mode='true']")) return false

  const pageState = readStore()[path] || {}
  if (pageState[key] === true) return false

  return key === "workshop-sheet-inventory" || key === "workshop-source-dxf-detail"
}

export default class extends Controller {
  connect() {
    this.boundOnToggle = this.onToggle.bind(this)
    this.boundOnTurboRender = this.restorePanels.bind(this)

    document.addEventListener("toggle", this.boundOnToggle, true)
    document.addEventListener("turbo:frame-render", this.boundOnTurboRender)
    document.addEventListener("turbo:load", this.boundOnTurboRender)

    this.restorePanels()
  }

  disconnect() {
    document.removeEventListener("toggle", this.boundOnToggle, true)
    document.removeEventListener("turbo:frame-render", this.boundOnTurboRender)
    document.removeEventListener("turbo:load", this.boundOnTurboRender)
  }

  restorePanels() {
    const path = pagePath()
    const pageState = readStore()[path]
    const state = pageState || {}

    document.querySelectorAll("details.collapsible-panel").forEach((details) => {
      const key = panelKey(details)
      if (!key) return

      if (lockedClosedOnPath(path, key, details)) {
        details.open = false
        return
      }

      if (setupModeActive() && SETUP_OPEN_PANEL_KEYS.has(key)) {
        details.open = true
        return
      }

      const saved = state[key]
      if (saved === true) details.open = true
      if (saved === false) details.open = false
    })
  }

  onToggle(event) {
    const details = event.target
    if (!(details instanceof HTMLDetailsElement)) return
    if (!details.classList.contains("collapsible-panel")) return

    const key = panelKey(details)
    if (!key) return

    const path = pagePath()
    const store = readStore()
    if (!store[path]) store[path] = {}

    store[path][key] = details.open
    if (details.dataset.collapsiblePreserveOpen === "true" && !details.open) {
      delete details.dataset.collapsiblePreserveOpen
    }
    writeStore(store)
  }
}
