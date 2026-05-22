import { Controller } from "@hotwired/stimulus"
import { ensureWorkspaceTabId, persistWorkspaceTabCookie, WORKSPACE_TAB_STORAGE_KEY } from "workspace_tab"

export default class extends Controller {
  static values = {
    preferred: String
  }

  connect() {
    if (this.hasPreferredValue && this.preferredValue) {
      sessionStorage.setItem(WORKSPACE_TAB_STORAGE_KEY, this.preferredValue)
      persistWorkspaceTabCookie(this.preferredValue)
    }

    ensureWorkspaceTabId()
  }
}
