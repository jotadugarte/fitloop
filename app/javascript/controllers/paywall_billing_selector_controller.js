import { Controller } from "@hotwired/stimulus"

// [REQ-FIT-BILL-001] Auto-apply billing currency/method on paywall (no Apply button).
export default class extends Controller {
  static targets = ["form"]

  submit() {
    const form = this.hasFormTarget ? this.formTarget : this.element
    if (form instanceof HTMLFormElement) {
      form.requestSubmit()
    }
  }
}
