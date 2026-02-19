import Sortable from "../../vendor/sortable.js"

const TaskDragDrop = {
  mounted() {
    this.initSortables()
  },

  updated() {
    this.destroySortables()
    this.initSortables()
  },

  destroyed() {
    this.destroySortables()
  },

  initSortables() {
    this.sortables = []

    // Find all dropzones (one per task state)
    const dropzones = this.el.querySelectorAll("[data-dropzone]")

    dropzones.forEach((dropzone) => {
      const sortable = new Sortable(dropzone, {
        group: "tasks", // Allow dragging between all dropzones
        animation: 150,
        handle: ".task-drag-handle", // Only drag from handle
        draggable: ".task-item", // Only these elements are draggable
        ghostClass: "opacity-50",

        onEnd: (evt) => {
          // Get the task ID from the dragged element
          const taskId = evt.item.dataset.taskId

          // Get the new state ID from the dropzone
          const newStateId = evt.to.dataset.stateId

          // Get the old state ID from the previous dropzone
          const oldStateId = evt.from.dataset.stateId

          // Only send event if the state actually changed
          if (oldStateId !== newStateId) {
            // Move element back to original position - LiveView will handle the actual DOM update
            // This prevents duplicates from Sortable moving the element AND LiveView inserting it
            evt.from.insertBefore(evt.item, evt.from.children[evt.oldIndex])

            this.pushEventTo(this.el, "task-moved", {
              task_id: taskId,
              new_state_id: newStateId
            })
          }
        }
      })

      this.sortables.push(sortable)
    })
  },

  destroySortables() {
    if (this.sortables) {
      this.sortables.forEach(sortable => sortable.destroy())
      this.sortables = []
    }
  }
}

export default TaskDragDrop
