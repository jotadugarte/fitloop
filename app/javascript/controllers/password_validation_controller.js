import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "password",
    "confirmation",
    "submit",
    "currentPassword",
    "lengthHint",
    "lengthError",
    "matchFeedback"
  ]
  static values = {
    min: Number,
    optional: Boolean,
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
    const showError = password.length > 0 && password.length < min

    if (this.hasLengthHintTarget) {
      this.lengthHintTarget.hidden = showError
    }

    if (!this.hasLengthErrorTarget) return

    this.lengthErrorTarget.hidden = !showError
    if (showError) this.lengthErrorTarget.textContent = this.tooShortValue
  }

  updateMatchFeedback(password, confirmation) {
    if (!this.hasMatchFeedbackTarget) return

    const feedback = this.matchFeedbackTarget

    if (confirmation.length === 0) {
      feedback.hidden = true
      feedback.classList.remove("field__validation-msg--error", "field__validation-msg--ok")
      return
    }

    feedback.hidden = false

    if (password === confirmation) {
      feedback.textContent = this.matchValue
      feedback.classList.remove("field__validation-msg--error")
      feedback.classList.add("field__validation-msg--ok")
      return
    }

    feedback.textContent = this.mismatchValue
    feedback.classList.remove("field__validation-msg--ok")
    feedback.classList.add("field__validation-msg--error")
  }

  updateSubmit(password, confirmation, min) {
    if (!this.hasSubmitTarget) return

    if (this.optionalValue && !this.passwordChangeAttempted(password, confirmation)) {
      this.submitTarget.disabled = false
      return
    }

    const currentOk =
      !this.hasCurrentPasswordTarget || this.currentPasswordTarget.value.length > 0
    const valid =
      currentOk &&
      password.length >= min &&
      confirmation.length > 0 &&
      password === confirmation

    this.submitTarget.disabled = !valid
  }

  passwordChangeAttempted(password, confirmation) {
    const newFieldsTouched = password.length > 0 || confirmation.length > 0
    if (!this.optionalValue) return true

    if (this.hasCurrentPasswordTarget && this.currentPasswordTarget.value.length > 0) {
      return true
    }

    return newFieldsTouched
  }
}
