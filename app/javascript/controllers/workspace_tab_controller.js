import { Controller } from "@hotwired/stimulus"
import {
  WORKSPACE_TAB_HEADER,
  ensureWorkspaceTabId,
  workspaceTabId
} from "workspace_tab"

export default class extends Controller {
  connect() {
    ensureWorkspaceTabId()
    this._onBeforeFetch = this._attachTabIdHeader.bind(this)
    document.addEventListener("turbo:before-fetch-request", this._onBeforeFetch)
  }

  disconnect() {
    document.removeEventListener("turbo:before-fetch-request", this._onBeforeFetch)
  }

  get tabId() {
    return workspaceTabId()
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
