import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "dialog", "form" ]

  open(event) {
    event.preventDefault()
    if (!this.hasDialogTarget) return

    this.dialogTarget.showModal()
  }

  close(event) {
    event.preventDefault()
    if (!this.hasDialogTarget) return

    this.dialogTarget.close()
  }

  handleSubmitEnd(event) {
    if (!event.detail.success) return
    if (!this.hasDialogTarget) return

    this.dialogTarget.close()
    if (this.hasFormTarget) this.formTarget.reset()
  }
}
