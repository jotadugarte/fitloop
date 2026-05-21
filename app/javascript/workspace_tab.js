export const WORKSPACE_TAB_STORAGE_KEY = "fitloop_workspace_tab_id"
export const WORKSPACE_TAB_HEADER = "X-Workspace-Tab-Id"

export function ensureWorkspaceTabId() {
  let tabId = sessionStorage.getItem(WORKSPACE_TAB_STORAGE_KEY)
  if (!tabId) {
    tabId = crypto.randomUUID()
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

export function withWorkspaceTabHeaders(headers = {}) {
  const tabId = workspaceTabId()
  if (!tabId) return headers

  return { ...headers, [WORKSPACE_TAB_HEADER]: tabId }
}
