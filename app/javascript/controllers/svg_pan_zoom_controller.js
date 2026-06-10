import { Controller } from "@hotwired/stimulus"

const MIN_SCALE = 0.25
const MAX_SCALE = 6
const SCALE_STEP = 0.1

export default class extends Controller {
  static targets = [ "viewport", "canvas" ]

  connect() {
    this.scale = 1
    this.translateX = 0
    this.translateY = 0
    this.dragging = false
    this.lastPointerX = 0
    this.lastPointerY = 0
    this.applyTransform()
  }

  disconnect() {
    this.endDrag()
  }

  wheel(event) {
    event.preventDefault()
    const delta = event.deltaY < 0 ? SCALE_STEP : -SCALE_STEP
    this.scale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, this.scale + delta))
    this.applyTransform()
  }

  pointerDown(event) {
    if (event.button !== 0) return

    this.dragging = true
    this.lastPointerX = event.clientX
    this.lastPointerY = event.clientY
    this.viewportTarget.setPointerCapture(event.pointerId)
    this.viewportTarget.classList.add("nesting-preview--dragging")
  }

  pointerMove(event) {
    if (!this.dragging) return

    this.translateX += event.clientX - this.lastPointerX
    this.translateY += event.clientY - this.lastPointerY
    this.lastPointerX = event.clientX
    this.lastPointerY = event.clientY
    this.applyTransform()
  }

  pointerUp(event) {
    if (!this.dragging) return

    this.endDrag()
    if (this.viewportTarget.hasPointerCapture(event.pointerId)) {
      this.viewportTarget.releasePointerCapture(event.pointerId)
    }
  }

  endDrag() {
    this.dragging = false
    if (this.hasViewportTarget) {
      this.viewportTarget.classList.remove("nesting-preview--dragging")
    }
  }

  applyTransform() {
    if (!this.hasCanvasTarget) return

    this.canvasTarget.style.transform = `translate(${this.translateX}px, ${this.translateY}px) scale(${this.scale})`
  }
}
