export const WORKSPACE_TAB_STORAGE_KEY = "fitloop_workspace_tab_id"
export const WORKSPACE_TAB_HEADER = "X-Workspace-Tab-Id"
export const TAB_LEFT_COOKIE = "fitloop_workspace_tab_left_at"

const INTERNAL_NAV_KEY = "fitloop_workspace_internal_nav"

function isSameOriginUrl(url) {
  try {
    return new URL(url, window.location.href).origin === window.location.origin
  } catch {
    return false
  }
}

export function ensureWorkspaceTabId() {
  let tabId = sessionStorage.getItem(WORKSPACE_TAB_STORAGE_KEY)
  if (!tabId) {
    tabId = readWorkspaceTabCookie() || crypto.randomUUID()
    sessionStorage.setItem(WORKSPACE_TAB_STORAGE_KEY, tabId)
  }
  persistWorkspaceTabCookie(tabId)
  return tabId
}

export function workspaceTabId() {
  return sessionStorage.getItem(WORKSPACE_TAB_STORAGE_KEY)
}

export function persistWorkspaceTabCookie(tabId) {
  if (!tabId) return

  document.cookie = `${WORKSPACE_TAB_STORAGE_KEY}=${encodeURIComponent(tabId)}; path=/; SameSite=Lax`
}

export function clearTabLeft() {
  document.cookie = `${TAB_LEFT_COOKIE}=; path=/; Max-Age=0; SameSite=Lax`
}

export function markTabLeft() {
  document.cookie = `${TAB_LEFT_COOKIE}=${Date.now()}; path=/; SameSite=Lax`
}

/** In-app navigation (Mi cuenta, Mis pagos, planes, etc.) is not closing the workshop tab. */
export function markInternalNavigation() {
  sessionStorage.setItem(INTERNAL_NAV_KEY, "1")
  clearTabLeft()
}

function configureWorkspaceInternalNavGuards() {
  document.addEventListener(
    "click",
    (event) => {
      const link = event.target.closest("a[href]")
      if (!link || link.target === "_blank" || link.hasAttribute("download")) return
      if (!isSameOriginUrl(link.href)) return

      markInternalNavigation()
    },
    true
  )

  document.addEventListener(
    "submit",
    (event) => {
      const form = event.target
      if (!(form instanceof HTMLFormElement)) return
      const action = form.getAttribute("action") || window.location.href
      if (!isSameOriginUrl(action)) return

      markInternalNavigation()
    },
    true
  )
}

/** Tab-close TTL only when the browser tab is closed, not on in-app navigation. */
export function configureWorkspaceTabLeave() {
  configureWorkspaceInternalNavGuards()

  document.addEventListener("turbo:before-visit", () => {
    markInternalNavigation()
    const tabId = ensureWorkspaceTabId()
    persistWorkspaceTabCookie(tabId)
  })

  document.addEventListener("pagehide", (event) => {
    if (sessionStorage.getItem(INTERNAL_NAV_KEY)) {
      sessionStorage.removeItem(INTERNAL_NAV_KEY)
      return
    }

    if (event.persisted) return

    markTabLeft()
  })
}

/** User still on Fitloop (visible tab): do not treat as workshop closed. */
export function configureWorkspaceTabPresence() {
  const clearIfVisible = () => {
    if (document.visibilityState === "visible") clearTabLeft()
  }

  document.addEventListener("turbo:load", clearIfVisible)
  document.addEventListener("DOMContentLoaded", clearIfVisible)
  document.addEventListener("visibilitychange", clearIfVisible)
}

export function configureWorkspaceTabHeaders() {
  document.addEventListener("turbo:before-fetch-request", (event) => {
    const tabId = workspaceTabId()
    if (!tabId) return

    const headers = event.detail.fetchOptions.headers
    if (headers instanceof Headers) {
      headers.set(WORKSPACE_TAB_HEADER, tabId)
    } else {
      event.detail.fetchOptions.headers = { ...headers, [WORKSPACE_TAB_HEADER]: tabId }
    }
  })
}

export function withWorkspaceTabHeaders(headers = {}) {
  const tabId = workspaceTabId()
  if (!tabId) return headers

  return { ...headers, [WORKSPACE_TAB_HEADER]: tabId }
}

function readWorkspaceTabCookie() {
  const pattern = new RegExp(`(?:^|; )${WORKSPACE_TAB_STORAGE_KEY}=([^;]*)`)
  const match = document.cookie.match(pattern)
  return match ? decodeURIComponent(match[1]) : null
}
