export const CARD_DRAFT_PREFIX = "fitloop:checkout:card-draft:"
export const CARD_DRAFT_SAVE_MS = 300

// Persist holder/number/expiry only — never store CVV (PCI hygiene).
export function cardDraftStorageKey(runId) {
  return `${CARD_DRAFT_PREFIX}${runId || "default"}`
}

export function saveCardDraft(storageKey, draft) {
  sessionStorage.setItem(storageKey, JSON.stringify(draft))
}

export function restoreCardDraft(storageKey) {
  const raw = sessionStorage.getItem(storageKey)
  if (!raw) return null

  try {
    return JSON.parse(raw)
  } catch (_error) {
    sessionStorage.removeItem(storageKey)
    return null
  }
}

export function clearCardDraft(storageKey) {
  sessionStorage.removeItem(storageKey)
}

export function createCardDraftScheduler(onSave, delayMs = CARD_DRAFT_SAVE_MS) {
  let timer = null

  return {
    schedule() {
      if (timer) window.clearTimeout(timer)
      timer = window.setTimeout(() => {
        timer = null
        onSave()
      }, delayMs)
    },
    cancel() {
      if (timer) {
        window.clearTimeout(timer)
        timer = null
      }
    }
  }
}
