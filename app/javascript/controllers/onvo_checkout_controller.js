import { Controller } from "@hotwired/stimulus"
import {
  CARD_CVV_MAX,
  CARD_NUMBER_MAX,
  HOLDER_NAME_MAX,
  formatCardExpValue,
  validateCardForm as validateCardCheckoutForm,
  validateSinpeForm as validateSinpeCheckoutForm
} from "../checkout/onvo_checkout_validation"
import {
  cardDraftStorageKey,
  clearCardDraft as removeStoredCardDraft,
  createCardDraftScheduler,
  restoreCardDraft as readStoredCardDraft,
  saveCardDraft as writeStoredCardDraft
} from "../checkout/onvo_checkout_card_draft"

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
    this.cardDraftScheduler = createCardDraftScheduler(() => this.saveCardDraft())
    this.syncPanels()
    this.syncRequiredFields()
    this.bootstrapSinpeResume()
    if (!this.isSinpe() && !this.sinpeAwaitingTransfer) this.restoreCardDraft()
    this.bindCardDraftPersistence()
  }

  disconnect() {
    this.cardDraftScheduler?.cancel()
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

  cardDraftKey() {
    const runId = this.hasNestingRunIdTarget && this.nestingRunIdTarget.value
      ? this.nestingRunIdTarget.value
      : null
    return cardDraftStorageKey(runId)
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
    this.cardDraftScheduler.schedule()
  }

  saveCardDraft() {
    if (!this.hasCardHolderNameTarget || this.isSinpe()) return

    writeStoredCardDraft(this.cardDraftKey(), {
      holder_name: this.cardHolderNameTarget.value,
      card_number: this.cardNumberTarget.value,
      card_exp: this.cardExpTarget.value
    })
  }

  restoreCardDraft() {
    if (!this.hasCardHolderNameTarget) return

    const draft = readStoredCardDraft(this.cardDraftKey())
    if (!draft) return

    if (draft.holder_name) this.cardHolderNameTarget.value = draft.holder_name
    if (draft.card_number) this.cardNumberTarget.value = draft.card_number
    if (draft.card_exp) this.cardExpTarget.value = draft.card_exp
  }

  clearCardDraft() {
    removeStoredCardDraft(this.cardDraftKey())
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
    event.target.value = formatCardExpValue(event.target.value)
    this.scheduleSaveCardDraft()
  }

  formatCardCvv(event) {
    event.target.value = event.target.value.replace(/\D/g, "").slice(0, CARD_CVV_MAX)
    this.scheduleSaveCardDraft()
  }

  formatSinpeIdentification(event) {
    event.target.value = event.target.value.replace(/\D/g, "").slice(0, 12)
  }

  formatSinpeMobileNumber(event) {
    event.target.value = event.target.value.replace(/\D/g, "").slice(0, 8)
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
    return validateCardCheckoutForm({
      holderName: this.cardHolderNameTarget.value.trim(),
      cardNumber: this.cardNumberTarget.value.replace(/\D/g, ""),
      cardExp: this.cardExpTarget.value.trim(),
      cvv: this.cardCvvTarget.value.replace(/\D/g, ""),
      testCards: this.hasTestCardsValue ? this.testCardsValue : [],
      messageFor: (key) => this.validationMessage(key)
    })
  }

  validateSinpeForm() {
    return validateSinpeCheckoutForm({
      identification: this.sinpeIdentificationTarget.value.replace(/\D/g, ""),
      mobileNumber: this.sinpeMobileNumberTarget.value.replace(/\D/g, ""),
      testSinpeMobileNumbers: this.hasTestSinpeMobileNumbersValue ? this.testSinpeMobileNumbersValue : [],
      messageFor: (key) => this.validationMessage(key)
    })
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
