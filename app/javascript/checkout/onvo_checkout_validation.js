export const CARD_NUMBER_MAX = 19
export const CARD_CVV_MAX = 4
export const HOLDER_NAME_MAX = 100
export const SINPE_IDENTIFICATION_MIN = 9
export const SINPE_IDENTIFICATION_MAX = 12
export const SINPE_MOBILE_LEN = 8

export function formatCardExpValue(raw) {
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

export function isValidCardNumber(number, testCards = []) {
  if (!/^\d{13,19}$/.test(number)) return false

  if (testCards.length > 0 && !testCards.includes(number)) {
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

export function expirationValidationError(value, messageFor) {
  const match = value.match(/^(\d{2})\/(\d{2})$/)
  if (!match) return messageFor("card_exp_invalid")

  const month = Number.parseInt(match[1], 10)
  const year = 2000 + Number.parseInt(match[2], 10)
  if (month < 1 || month > 12) return messageFor("card_exp_invalid")

  const lastValidDay = new Date(year, month, 0)
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  if (lastValidDay < today) return messageFor("card_exp_expired")

  return null
}

export function validateCardForm({ holderName, cardNumber, cardExp, cvv, testCards, messageFor }) {
  if (holderName.length < 2 || holderName.length > HOLDER_NAME_MAX || !/^[\p{L}\s'.-]+$/u.test(holderName)) {
    return messageFor("holder_name_invalid")
  }

  if (testCards.length > 0 && !testCards.includes(cardNumber)) {
    return messageFor("card_number_test_only")
  }

  if (!isValidCardNumber(cardNumber, testCards)) {
    return messageFor("card_number_invalid")
  }

  const expirationError = expirationValidationError(cardExp, messageFor)
  if (expirationError) return expirationError

  if (!/^\d{3,4}$/.test(cvv)) {
    return messageFor("card_cvv_invalid")
  }

  return null
}

export function validateSinpeForm({ identification, mobileNumber, testSinpeMobileNumbers, messageFor }) {
  if (identification.length < SINPE_IDENTIFICATION_MIN || identification.length > SINPE_IDENTIFICATION_MAX) {
    return messageFor("sinpe_identification_invalid")
  }

  if (mobileNumber.length !== SINPE_MOBILE_LEN) {
    return messageFor("sinpe_mobile_number_invalid")
  }

  if (testSinpeMobileNumbers.length > 0 && !testSinpeMobileNumbers.includes(mobileNumber)) {
    return messageFor("sinpe_mobile_number_test_only")
  }

  return null
}
