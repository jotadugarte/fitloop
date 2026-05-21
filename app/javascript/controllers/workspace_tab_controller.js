import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "fitloop_workspace_tab_id"
const HEADER_NAME = "X-Workspace-Tab-Id"

export default class extends Controller {
  connect() {
    if (!sessionStorage.getItem(STORAGE_KEY)) {
      sessionStorage.setItem(STORAGE_KEY, crypto.randomUUID())
    }
    this._onBeforeFetch = this._attachTabIdHeader.bind(this)
    document.addEventListener("turbo:before-fetch-request", this._onBeforeFetch)
  }

  disconnect() {
    document.removeEventListener("turbo:before-fetch-request", this._onBeforeFetch)
  }

  get tabId() {
    return sessionStorage.getItem(STORAGE_KEY)
  }

  _attachTabIdHeader(event) {
    const tabId = this.tabId
    if (!tabId) return

    const headers = event.detail.fetchOptions.headers
    if (headers instanceof Headers) {
      headers.set(HEADER_NAME, tabId)
    } else {
      event.detail.fetchOptions.headers = { ...headers, [HEADER_NAME]: tabId }
    }
  }
}
