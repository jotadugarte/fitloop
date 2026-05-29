import { Controller } from "@hotwired/stimulus"

const CARD_NUMBER_MAX = 19
const CARD_CVV_MAX = 4
const HOLDER_NAME_MAX = 100

export default class extends Controller {
  static targets = [
    "cardPanel",
    "sinpePanel",
    "cardHolderName",
    "cardNumber",
    "cardExp",
    "cardCvv",
    "sinpeIdentification",
    "sinpeMobileNumber",
    "sinpeInstructions",
    "sinpeInstructionsBody",
    "errorMessage",
    "processButton",
    "nestingRunId",
    "tierMonths",
    "paymentMethodField"
  ]

  static values = {
    payUrl: String,
    sinpeUrl: String,
    cardUrl: String,
    processingUrl: String,
    paymentMethod: String,
    validationMessages: Object
  }

  connect() {
    this.paymentId = null
    this.syncPanels()
    this.syncRequiredFields()
  }

  paymentMethodValueChanged() {
    this.syncPanels()
    this.syncRequiredFields()
  }

  syncPanels() {
    const sinpe = this.isSinpe()
    if (this.hasCardPanelTarget) this.cardPanelTarget.hidden = sinpe
    if (this.hasSinpePanelTarget) this.sinpePanelTarget.hidden = !sinpe
  }

  syncRequiredFields() {
    const sinpe = this.isSinpe()
    this.setRequired(this.cardHolderNameTarget, !sinpe)
    this.setRequired(this.cardNumberTarget, !sinpe)
    this.setRequired(this.cardExpTarget, !sinpe)
    this.setRequired(this.cardCvvTarget, !sinpe)
    this.setRequired(this.sinpeIdentificationTarget, sinpe)
    this.setRequired(this.sinpeMobileNumberTarget, sinpe)
  }

  setRequired(target, required) {
    if (!target) return
    target.required = required
  }

  formatHolderName(event) {
    event.target.value = event.target.value
      .replace(/[^\p{L}\s'.-]/gu, "")
      .slice(0, HOLDER_NAME_MAX)
  }

  formatCardNumber(event) {
    event.target.value = event.target.value.replace(/\D/g, "").slice(0, CARD_NUMBER_MAX)
  }

  formatCardExp(event) {
    const digits = event.target.value.replace(/\D/g, "").slice(0, 4)
    if (digits.length <= 2) {
      event.target.value = digits
      return
    }
    event.target.value = `${digits.slice(0, 2)}/${digits.slice(2)}`
  }

  formatCardCvv(event) {
    event.target.value = event.target.value.replace(/\D/g, "").slice(0, CARD_CVV_MAX)
  }

  async processPayment(event) {
    event.preventDefault()
    this.clearError()

    if (!this.isSinpe()) {
      const validationError = this.validateCardForm()
      if (validationError) {
        this.showError(validationError)
        return
      }
    }

    this.processButtonTarget.disabled = true

    try {
      const data = await this.startPayment()
      this.paymentId = data.payment_id

      if (this.isSinpe()) {
        await this.confirmSinpe(data.payment_id)
      } else {
        await this.confirmCard(data.payment_id)
      }
    } catch (error) {
      this.showError(error.message)
      this.processButtonTarget.disabled = false
    }
  }

  validateCardForm() {
    const holderName = this.cardHolderNameTarget.value.trim()
    const cardNumber = this.cardNumberTarget.value.replace(/\D/g, "")
    const cardExp = this.cardExpTarget.value.trim()
    const cvv = this.cardCvvTarget.value.replace(/\D/g, "")

    if (holderName.length < 2 || holderName.length > HOLDER_NAME_MAX || !/^[\p{L}\s'.-]+$/u.test(holderName)) {
      return this.validationMessage("holder_name_invalid")
    }

    if (!this.isValidCardNumber(cardNumber)) {
      return this.validationMessage("card_number_invalid")
    }

    const expirationError = this.expirationValidationError(cardExp)
    if (expirationError) return expirationError

    if (!/^\d{3,4}$/.test(cvv)) {
      return this.validationMessage("card_cvv_invalid")
    }

    return null
  }

  isValidCardNumber(number) {
    if (!/^\d{13,19}$/.test(number)) return false

    let sum = 0
    let alternate = false
    for (let index = number.length - 1; index >= 0; index -= 1) {
      let digit = Number.parseInt(number.charAt(index), 10)
      if (alternate) {
        digit *= 2
        if (digit > 9) digit -= 9
      }
      sum += digit
      alternate = !alternate
    }
    return sum % 10 === 0
  }

  expirationValidationError(value) {
    const match = value.match(/^(\d{2})\/(\d{2})$/)
    if (!match) return this.validationMessage("card_exp_invalid")

    const month = Number.parseInt(match[1], 10)
    const year = 2000 + Number.parseInt(match[2], 10)
    if (month < 1 || month > 12) return this.validationMessage("card_exp_invalid")

    const lastValidDay = new Date(year, month, 0)
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    if (lastValidDay < today) return this.validationMessage("card_exp_expired")

    return null
  }

  validationMessage(key) {
    if (this.hasValidationMessagesValue && this.validationMessagesValue[key]) {
      return this.validationMessagesValue[key]
    }
    return key
  }

  async startPayment() {
    const response = await fetch(this.payUrlValue, {
      method: "POST",
      headers: this.jsonHeaders(),
      body: this.payFormData()
    })

    const data = await response.json()
    if (!response.ok) throw new Error(data.error || "Payment could not be started")
    return data
  }

  async confirmCard(paymentId) {
    const url = this.cardUrlValue.replace(":payment_id", paymentId)
    const body = new FormData()
    body.append("card_holder_name", this.cardHolderNameTarget.value.trim())
    body.append("card_number", this.cardNumberTarget.value.replace(/\D/g, ""))
    body.append("card_exp", this.cardExpTarget.value.trim())
    body.append("card_cvv", this.cardCvvTarget.value.replace(/\D/g, ""))

    const response = await fetch(url, {
      method: "POST",
      headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken },
      body
    })

    const data = await response.json()
    if (!response.ok) throw new Error(data.error || "Card payment failed")

    if (data.redirect_url) {
      window.location.href = data.redirect_url
      return
    }

    window.location.href = this.processingUrlValue.replace(":payment_id", paymentId)
  }

  async confirmSinpe(paymentId) {
    const url = this.sinpeUrlValue.replace(":payment_id", paymentId)
    const body = new FormData()
    body.append("sinpe_identification", this.sinpeIdentificationTarget.value)
    body.append("sinpe_mobile_number", this.sinpeMobileNumberTarget.value)

    const response = await fetch(url, {
      method: "POST",
      headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken },
      body
    })

    const data = await response.json()
    if (!response.ok) throw new Error(data.error || "SINPE confirmation failed")

    this.sinpeInstructionsBodyTarget.textContent = this.sinpeInstructionsText(data)
    this.sinpeInstructionsTarget.hidden = false
    this.processButtonTarget.disabled = true

    window.setTimeout(() => {
      window.location.href = this.processingUrlValue.replace(":payment_id", paymentId)
    }, 4000)
  }

  payFormData() {
    const body = new FormData()
    if (this.hasNestingRunIdTarget && this.nestingRunIdTarget.value) {
      body.append("nesting_run_id", this.nestingRunIdTarget.value)
    }
    if (this.hasTierMonthsTarget && this.tierMonthsTarget.value) {
      body.append("tier_months", this.tierMonthsTarget.value)
    }
    body.append("payment_method", this.paymentMethodValue)
    return body
  }

  sinpeInstructionsText(data) {
    const template = this.element.dataset.sinpeInstructionsTemplate
    if (!template) {
      return `Transfer exactly ${data.amount} ${data.currency} to ${data.destination_number}`
    }
    return template
      .replace("%{amount}", data.amount_label || data.amount)
      .replace("%{currency}", data.currency)
      .replace("%{destination}", data.destination_number)
  }

  isSinpe() {
    return this.paymentMethodValue.startsWith("sinpe")
  }

  jsonHeaders() {
    return {
      Accept: "application/json",
      "X-CSRF-Token": this.csrfToken
    }
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  clearError() {
    if (!this.hasErrorMessageTarget) return
    this.errorMessageTarget.hidden = true
    this.errorMessageTarget.textContent = ""
  }

  showError(message) {
    if (!this.hasErrorMessageTarget) return
    this.errorMessageTarget.textContent = message
    this.errorMessageTarget.hidden = false
  }
}
