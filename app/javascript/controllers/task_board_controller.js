import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["column"]

  dragStart(event) {
    const card = event.target.closest("[data-task-id]")
    if (!card) return
    event.dataTransfer.setData("text/plain", card.dataset.taskId)
    event.dataTransfer.effectAllowed = "move"
    card.classList.add("dragging")
    card.closest(".task-column")?.classList.add("source-column")
  }

  dragEnd(event) {
    const card = event.target.closest("[data-task-id]")
    if (!card) return
    card.classList.remove("dragging")
    card.closest(".task-column")?.classList.remove("source-column")
    this.columnTargets.forEach(col => col.classList.remove("drag-over"))
  }

  dragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dragEnter(event) {
    event.preventDefault()
    const col = event.currentTarget
    col.classList.add("drag-over")
  }

  dragLeave(event) {
    const col = event.currentTarget
    if (!col.contains(event.relatedTarget)) {
      col.classList.remove("drag-over")
    }
  }

  drop(event) {
    event.preventDefault()
    const col = event.currentTarget
    col.classList.remove("drag-over")

    const taskId = event.dataTransfer.getData("text/plain")
    if (!taskId) return

    const newStatus = col.dataset.status
    if (!newStatus) return

    const form = new FormData()
    form.append("task[status]", newStatus)

    fetch(`/tasks/${taskId}`, {
      method: "PATCH",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      },
      body: form
    }).then(response => response.text()).then(html => {
      Turbo.renderStreamMessage(html)
    })
  }
}
