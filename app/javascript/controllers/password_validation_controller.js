import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["password", "confirmation", "submit", "lengthError", "matchError", "matchOk"]
  static values = {
    min: Number,
    tooShort: String,
    mismatch: String,
    match: String
  }

  connect() {
    this.validate()
  }

  validate() {
    const password = this.passwordTarget.value
    const confirmation = this.confirmationTarget.value
    const min = this.minValue

    this.updateLengthFeedback(password, min)
    this.updateMatchFeedback(password, confirmation)
    this.updateSubmit(password, confirmation, min)
  }

  updateLengthFeedback(password, min) {
    if (!this.hasLengthErrorTarget) return

    const showError = password.length > 0 && password.length < min
    this.lengthErrorTarget.hidden = !showError
    if (showError) this.lengthErrorTarget.textContent = this.tooShortValue
  }

  updateMatchFeedback(password, confirmation) {
    if (!this.hasMatchErrorTarget || !this.hasMatchOkTarget) return

    const checkMatch = confirmation.length > 0
    this.matchErrorTarget.hidden = !checkMatch || password === confirmation
    this.matchOkTarget.hidden = !checkMatch || password !== confirmation

    if (checkMatch && password !== confirmation) {
      this.matchErrorTarget.textContent = this.mismatchValue
    } else if (checkMatch && password === confirmation) {
      this.matchOkTarget.textContent = this.matchValue
    }
  }

  updateSubmit(password, confirmation, min) {
    if (!this.hasSubmitTarget) return

    const valid =
      password.length >= min &&
      confirmation.length > 0 &&
      password === confirmation

    this.submitTarget.disabled = !valid
  }
}
