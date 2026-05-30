import { Controller } from "@hotwired/stimulus"

const CARD_NUMBER_MAX = 19
const CARD_CVV_MAX = 4
const HOLDER_NAME_MAX = 100
const SINPE_IDENTIFICATION_MIN = 9
const SINPE_IDENTIFICATION_MAX = 12
const SINPE_MOBILE_LEN = 8
const CARD_DRAFT_PREFIX = "fitloop:checkout:card-draft:"
const CARD_DRAFT_SAVE_MS = 300

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
    "sinpeFields",
    "sinpeHow",
    "sinpeInstructions",
    "sinpeInstructionIdentification",
    "sinpeInstructionMobileNumber",
    "sinpeInstructionAmount",
    "sinpeInstructionNumber",
    "sinpeInstructionName",
    "errorMessage",
    "processButton",
    "processButtonLabel",
    "secondaryActions",
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
    validationMessages: Object,
    processPaymentLabel: String,
    processPaymentBusyLabel: String,
    sinpeContinueLabel: String,
    sinpeContinueBusyLabel: String,
    testCards: { type: Array, default: [] },
    testSinpeMobileNumbers: { type: Array, default: [] },
    resumePaymentId: Number,
    resumeSinpeAwaitingTransfer: Boolean,
    resumeAmountLabel: String,
    resumeDestinationNumber: String,
    resumeDestinationName: String,
    resumeTransferIdentification: String,
    resumeTransferMobileNumber: String
  }

  connect() {
    this.paymentId = null
    this.sinpeAwaitingTransfer = false
    this.saveCardDraftTimer = null
    this.syncPanels()
    this.syncRequiredFields()
    this.bootstrapSinpeResume()
    if (!this.isSinpe() && !this.sinpeAwaitingTransfer) this.restoreCardDraft()
    this.bindCardDraftPersistence()
  }

  disconnect() {
    if (this.saveCardDraftTimer) window.clearTimeout(this.saveCardDraftTimer)
  }

  bootstrapSinpeResume() {
    if (!this.hasResumePaymentIdValue) return

    this.paymentId = this.resumePaymentIdValue
    if (this.resumeSinpeAwaitingTransferValue) {
      this.showSinpeTransferStep({
        amount_label: this.resumeAmountLabelValue,
        destination_number: this.resumeDestinationNumberValue,
        destination_holder_name: this.resumeDestinationNameValue,
        transfer_identification: this.resumeTransferIdentificationValue,
        transfer_mobile_number: this.resumeTransferMobileNumberValue
      })
    }
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

  cardDraftStorageKey() {
    const runId = this.hasNestingRunIdTarget && this.nestingRunIdTarget.value
      ? this.nestingRunIdTarget.value
      : "default"
    return `${CARD_DRAFT_PREFIX}${runId}`
  }

  bindCardDraftPersistence() {
    if (!this.hasCardHolderNameTarget) return

    ;[
      this.cardHolderNameTarget,
      this.cardNumberTarget,
      this.cardExpTarget,
      this.cardCvvTarget
    ].forEach((field) => {
      field.addEventListener("input", () => this.scheduleSaveCardDraft())
    })
  }

  scheduleSaveCardDraft() {
    if (this.saveCardDraftTimer) window.clearTimeout(this.saveCardDraftTimer)
    this.saveCardDraftTimer = window.setTimeout(() => this.saveCardDraft(), CARD_DRAFT_SAVE_MS)
  }

  saveCardDraft() {
    if (!this.hasCardHolderNameTarget || this.isSinpe()) return

    sessionStorage.setItem(
      this.cardDraftStorageKey(),
      JSON.stringify({
        holder_name: this.cardHolderNameTarget.value,
        card_number: this.cardNumberTarget.value,
        card_exp: this.cardExpTarget.value,
        card_cvv: this.cardCvvTarget.value
      })
    )
  }

  restoreCardDraft() {
    if (!this.hasCardHolderNameTarget) return

    const raw = sessionStorage.getItem(this.cardDraftStorageKey())
    if (!raw) return

    try {
      const draft = JSON.parse(raw)
      if (draft.holder_name) this.cardHolderNameTarget.value = draft.holder_name
      if (draft.card_number) this.cardNumberTarget.value = draft.card_number
      if (draft.card_exp) this.cardExpTarget.value = draft.card_exp
      if (draft.card_cvv) this.cardCvvTarget.value = draft.card_cvv
    } catch (_error) {
      sessionStorage.removeItem(this.cardDraftStorageKey())
    }
  }

  clearCardDraft() {
    sessionStorage.removeItem(this.cardDraftStorageKey())
  }

  formatHolderName(event) {
    event.target.value = event.target.value
      .replace(/[^\p{L}\s'.-]/gu, "")
      .slice(0, HOLDER_NAME_MAX)
    this.scheduleSaveCardDraft()
  }

  formatCardNumber(event) {
    event.target.value = event.target.value.replace(/\D/g, "").slice(0, CARD_NUMBER_MAX)
    this.scheduleSaveCardDraft()
  }

  formatCardExp(event) {
    event.target.value = this.formatCardExpValue(event.target.value)
    this.scheduleSaveCardDraft()
  }

  formatCardExpValue(raw) {
    let digits = raw.replace(/\D/g, "").slice(0, 4)
    if (digits.length === 0) return ""

    if (digits.length === 1 && Number.parseInt(digits, 10) > 1) {
      digits = `0${digits}`
    }

    if (digits.length >= 2) {
      let month = Number.parseInt(digits.slice(0, 2), 10)
      if (month === 0) month = 1
      if (month > 12) month = 12
      digits = `${String(month).padStart(2, "0")}${digits.slice(2)}`
    }

    if (digits.length <= 2) return digits

    return `${digits.slice(0, 2)}/${digits.slice(2)}`
  }

  formatCardCvv(event) {
    event.target.value = event.target.value.replace(/\D/g, "").slice(0, CARD_CVV_MAX)
    this.scheduleSaveCardDraft()
  }

  formatSinpeIdentification(event) {
    event.target.value = event.target.value.replace(/\D/g, "").slice(0, SINPE_IDENTIFICATION_MAX)
  }

  formatSinpeMobileNumber(event) {
    event.target.value = event.target.value.replace(/\D/g, "").slice(0, SINPE_MOBILE_LEN)
  }

  async processPayment(event) {
    event.preventDefault()
    this.clearError()

    if (this.sinpeAwaitingTransfer) {
      this.setProcessButtonBusy(true)
      this.continueToProcessing(event)
      return
    }

    this.setProcessButtonBusy(true)

    if (!this.isSinpe()) {
      const validationError = this.validateCardForm()
      if (validationError) {
        this.setProcessButtonBusy(false)
        this.showError(validationError)
        return
      }
    } else {
      const validationError = this.validateSinpeForm()
      if (validationError) {
        this.setProcessButtonBusy(false)
        this.showError(validationError)
        return
      }
    }

    let keepBusy = false

    try {
      if (!this.paymentId) {
        const started = await this.startPayment()
        this.paymentId = started.payment_id
      }

      const paymentId = this.paymentId
      if (this.isSinpe()) {
        await this.confirmSinpe(paymentId)
      } else {
        await this.confirmCard(paymentId)
        keepBusy = true
      }
    } catch (error) {
      this.showError(error.message)
      this.setProcessButtonBusy(false)
    } finally {
      if (!keepBusy && !this.sinpeAwaitingTransfer) this.setProcessButtonBusy(false)
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

    if (this.hasTestCardsValue && this.testCardsValue.length > 0 && !this.testCardsValue.includes(cardNumber)) {
      return this.validationMessage("card_number_test_only")
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

  validateSinpeForm() {
    const identification = this.sinpeIdentificationTarget.value.replace(/\D/g, "")
    const mobileNumber = this.sinpeMobileNumberTarget.value.replace(/\D/g, "")

    if (identification.length < SINPE_IDENTIFICATION_MIN || identification.length > SINPE_IDENTIFICATION_MAX) {
      return this.validationMessage("sinpe_identification_invalid")
    }

    if (mobileNumber.length !== SINPE_MOBILE_LEN) {
      return this.validationMessage("sinpe_mobile_number_invalid")
    }

    if (this.hasTestSinpeMobileNumbersValue && this.testSinpeMobileNumbersValue.length > 0) {
      if (!this.testSinpeMobileNumbersValue.includes(mobileNumber)) {
        return this.validationMessage("sinpe_mobile_number_test_only")
      }
    }

    return null
  }

  isValidCardNumber(number) {
    if (!/^\d{13,19}$/.test(number)) return false

    if (this.hasTestCardsValue && this.testCardsValue.length > 0 && !this.testCardsValue.includes(number)) {
      return false
    }

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
      this.clearCardDraft()
      window.location.href = data.redirect_url
      return
    }

    this.clearCardDraft()
    window.location.href = this.processingUrlValue.replace(":payment_id", paymentId)
  }

  async confirmSinpe(paymentId) {
    const url = this.sinpeUrlValue.replace(":payment_id", paymentId)
    const body = new FormData()
    body.append("sinpe_identification", this.sinpeIdentificationTarget.value.replace(/\D/g, ""))
    body.append("sinpe_mobile_number", this.sinpeMobileNumberTarget.value.replace(/\D/g, ""))

    const response = await fetch(url, {
      method: "POST",
      headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken },
      body
    })

    const data = await response.json()
    if (!response.ok) throw new Error(data.error || "SINPE confirmation failed")

    this.showSinpeTransferStep(data)
  }

  showSinpeTransferStep(data) {
    const identification = data.transfer_identification || this.sinpeIdentificationTarget?.value?.replace(/\D/g, "")
    const mobileNumber = data.transfer_mobile_number || this.sinpeMobileNumberTarget?.value?.replace(/\D/g, "")

    if (this.hasSinpeInstructionIdentificationTarget) {
      this.sinpeInstructionIdentificationTarget.textContent = identification || "—"
    }
    if (this.hasSinpeInstructionMobileNumberTarget) {
      this.sinpeInstructionMobileNumberTarget.textContent = this.formatSinpeMobileDisplay(mobileNumber)
    }
    if (this.hasSinpeInstructionAmountTarget) {
      this.sinpeInstructionAmountTarget.textContent = data.amount_label || data.amount
    }
    if (this.hasSinpeInstructionNumberTarget) {
      this.sinpeInstructionNumberTarget.textContent = data.destination_number
    }
    if (this.hasSinpeInstructionNameTarget) {
      this.sinpeInstructionNameTarget.textContent = data.destination_holder_name
    }

    this.sinpeInstructionsTarget.hidden = false
    if (this.hasSinpeFieldsTarget) this.sinpeFieldsTarget.hidden = true
    if (this.hasSinpeHowTarget) this.sinpeHowTarget.hidden = true
    if (this.hasSecondaryActionsTarget) this.secondaryActionsTarget.hidden = true

    this.setProcessButtonBusy(false)
    this.setProcessButtonLabel(this.sinpeContinueLabelValue)
    this.processButtonTarget.dataset.testid = "checkout-sinpe-continue"
    this.sinpeAwaitingTransfer = true
    this.sinpeInstructionsTarget.scrollIntoView({ behavior: "smooth", block: "nearest" })
  }

  continueToProcessing(event) {
    event.preventDefault()
    if (!this.paymentId) return

    window.location.href = this.processingUrlValue.replace(":payment_id", this.paymentId)
  }

  setProcessButtonBusy(busy) {
    if (!this.hasProcessButtonTarget) return

    const button = this.processButtonTarget
    if (busy) {
      button.classList.add("btn--busy")
      button.disabled = true
      button.setAttribute("aria-busy", "true")
      this.setProcessButtonLabel(this.processButtonBusyText())
      return
    }

    button.classList.remove("btn--busy")
    button.disabled = false
    button.removeAttribute("aria-busy")
    this.resetPrimaryButtonLabel()
  }

  processButtonBusyText() {
    if (this.sinpeAwaitingTransfer && this.hasSinpeContinueBusyLabelValue) {
      return this.sinpeContinueBusyLabelValue
    }
    if (this.hasProcessPaymentBusyLabelValue) return this.processPaymentBusyLabelValue
    return "…"
  }

  setProcessButtonLabel(text) {
    if (!this.hasProcessButtonLabelTarget) return

    this.processButtonLabelTarget.textContent = text
  }

  resetPrimaryButtonLabel() {
    if (this.sinpeAwaitingTransfer && this.hasSinpeContinueLabelValue) {
      this.setProcessButtonLabel(this.sinpeContinueLabelValue)
      return
    }
    if (this.hasProcessPaymentLabelValue) {
      this.setProcessButtonLabel(this.processPaymentLabelValue)
    }
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

  formatSinpeMobileDisplay(number) {
    const digits = (number || "").toString().replace(/\D/g, "")
    if (digits.length === 8) return `+506 ${digits.slice(0, 4)} ${digits.slice(4)}`
    if (digits.length === 11 && digits.startsWith("506")) {
      return `+${digits.slice(0, 3)} ${digits.slice(3, 7)} ${digits.slice(7)}`
    }
    return digits || "—"
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
