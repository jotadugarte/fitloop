import { Controller } from "@hotwired/stimulus"
import { ensureWorkspaceTabId } from "workspace_tab"

export default class extends Controller {
  connect() {
    ensureWorkspaceTabId()
  }
}
