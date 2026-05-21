export const WORKSPACE_TAB_STORAGE_KEY = "fitloop_workspace_tab_id"
export const WORKSPACE_TAB_HEADER = "X-Workspace-Tab-Id"
export const TAB_LEFT_COOKIE = "fitloop_workspace_tab_left_at"

const INTERNAL_NAV_KEY = "fitloop_workspace_internal_nav"

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

/** Tab-close TTL only when the browser tab is closed, not on in-app Turbo navigation. */
export function configureWorkspaceTabLeave() {
  document.addEventListener("turbo:before-visit", () => {
    sessionStorage.setItem(INTERNAL_NAV_KEY, "1")
    clearTabLeft()
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
