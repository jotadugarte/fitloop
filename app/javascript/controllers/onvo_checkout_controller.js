import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "cardPanel",
    "sinpePanel",
    "sdkContainer",
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
    processingUrl: String,
    publishableKey: String,
    paymentMethod: String,
    sdkUrl: { type: String, default: "https://sdk.onvopay.com/sdk.js" }
  }

  connect() {
    this.paymentId = null
    this.syncPanels()
  }

  paymentMethodValueChanged() {
    this.syncPanels()
  }

  syncPanels() {
    const sinpe = this.isSinpe()
    if (this.hasCardPanelTarget) this.cardPanelTarget.hidden = sinpe
    if (this.hasSinpePanelTarget) this.sinpePanelTarget.hidden = !sinpe
  }

  async processPayment(event) {
    event.preventDefault()
    this.clearError()
    this.processButtonTarget.disabled = true

    try {
      const data = await this.startPayment()
      this.paymentId = data.payment_id

      if (this.isSinpe()) {
        await this.confirmSinpe(data.payment_id)
      } else {
        await this.startCardPayment(data)
      }
    } catch (error) {
      this.showError(error.message)
      this.processButtonTarget.disabled = false
    }
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

  async startCardPayment(data) {
    await this.ensureSdk()
    const publicKey = data.onvo_publishable_key || this.publishableKeyValue
    const paymentIntentId = data.onvo_payment_intent_id

    if (!publicKey || !paymentIntentId) {
      throw new Error("Missing ONVO payment session")
    }

    this.sdkContainerTarget.replaceChildren()

    await window.onvo.pay({
      publicKey,
      paymentIntentId,
      paymentType: "one_time",
      onSuccess: () => {
        window.location.href = this.processingUrlValue.replace(":payment_id", data.payment_id)
      },
      onError: (error) => {
        this.showError(error?.message || "Card payment failed")
        this.processButtonTarget.disabled = false
      }
    }).render(this.sdkContainerTarget)
  }

  ensureSdk() {
    if (window.onvo?.pay) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = this.sdkUrlValue
      script.async = true
      script.onload = () => resolve()
      script.onerror = () => reject(new Error("Could not load ONVO SDK"))
      document.head.appendChild(script)
    })
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
