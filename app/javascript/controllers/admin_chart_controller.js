import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"
Chart.register(...registerables)

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    labels: Array,
    data: Array
  }

  connect() {
    this.chart = new Chart(this.canvasTarget, {
      type: "bar",
      data: {
        labels: this.labelsValue,
        datasets: [{
          label: "Eventos",
          data: this.dataValue,
          backgroundColor: "rgba(79, 70, 229, 0.6)",
          borderColor: "rgb(79, 70, 229)",
          borderWidth: 1
        }]
      },
      options: {
        indexAxis: "y",
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: false
          }
        },
        scales: {
          x: {
            beginAtZero: true,
            ticks: {
              precision: 0
            }
          }
        }
      }
    })
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
