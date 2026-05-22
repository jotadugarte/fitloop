import { Controller } from "@hotwired/stimulus"

// [REQ-FIT-AUTH-002] Captures browser IANA timezone for registration and OAuth (D49).
export default class extends Controller {
  static targets = ["timeZone", "oauthLink"]
  static values = { fallback: { type: String, default: "America/Costa_Rica" } }

  connect() {
    const timeZone = this.resolvedTimeZone()
    if (this.hasTimeZoneTarget) {
      this.timeZoneTarget.value = timeZone
    }
    this.oauthLinkTargets.forEach((element) => this.appendTimeZoneField(element, timeZone))
  }

  resolvedTimeZone() {
    const detected = Intl.DateTimeFormat().resolvedOptions().timeZone
    return detected && detected.length > 0 ? detected : this.fallbackValue
  }

  appendTimeZoneField(element, timeZone) {
    const form = element.closest("form")
    if (!form) return

    const input = document.createElement("input")
    input.type = "hidden"
    input.name = "time_zone"
    input.value = timeZone
    form.appendChild(input)
  }
}
