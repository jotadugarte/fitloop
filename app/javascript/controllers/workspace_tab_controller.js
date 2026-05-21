import { Controller } from "@hotwired/stimulus"
import {
  WORKSPACE_TAB_HEADER,
  ensureWorkspaceTabId,
  markTabLeft,
  workspaceTabId
} from "workspace_tab"

export default class extends Controller {
  connect() {
    ensureWorkspaceTabId()
    this._onPageHide = this._handlePageHide.bind(this)
    this._onBeforeFetch = this._attachTabIdHeader.bind(this)
    window.addEventListener("pagehide", this._onPageHide)
    document.addEventListener("turbo:before-fetch-request", this._onBeforeFetch)
  }

  disconnect() {
    window.removeEventListener("pagehide", this._onPageHide)
    document.removeEventListener("turbo:before-fetch-request", this._onBeforeFetch)
  }

  get tabId() {
    return workspaceTabId()
  }

  _handlePageHide() {
    markTabLeft()
  }

  _attachTabIdHeader(event) {
    const tabId = this.tabId
    if (!tabId) return

    const headers = event.detail.fetchOptions.headers
    if (headers instanceof Headers) {
      headers.set(WORKSPACE_TAB_HEADER, tabId)
    } else {
      event.detail.fetchOptions.headers = { ...headers, [WORKSPACE_TAB_HEADER]: tabId }
    }
  }
}
