export function formatSinpeMobileDisplay(number) {
  const digits = (number || "").toString().replace(/\D/g, "")
  if (digits.length === 8) return `+506 ${digits.slice(0, 4)} ${digits.slice(4)}`
  if (digits.length === 11 && digits.startsWith("506")) {
    return `+${digits.slice(0, 3)} ${digits.slice(3, 7)} ${digits.slice(7)}`
  }
  return digits || "—"
}

export function populateSinpeTransferInstructions(targets, data, fallback = {}) {
  const identification = data.transfer_identification || fallback.identification || "—"
  const mobileNumber = data.transfer_mobile_number || fallback.mobileNumber

  if (targets.identification) {
    targets.identification.textContent = identification
  }
  if (targets.mobileNumber) {
    targets.mobileNumber.textContent = formatSinpeMobileDisplay(mobileNumber)
  }
  if (targets.amount) {
    targets.amount.textContent = data.amount_label || data.amount
  }
  if (targets.destinationNumber) {
    targets.destinationNumber.textContent = data.destination_number
  }
  if (targets.destinationName) {
    targets.destinationName.textContent = data.destination_holder_name
  }
}

export function revealSinpeTransferPanel({ instructions, fields, how, secondaryActions }) {
  if (instructions) instructions.hidden = false
  if (fields) fields.hidden = true
  if (how) how.hidden = true
  if (secondaryActions) secondaryActions.hidden = true
}
