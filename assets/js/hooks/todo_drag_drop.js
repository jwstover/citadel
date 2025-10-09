import Sortable from "../../vendor/sortable.js"

const TodoDragDrop = {
  mounted() {
    this.sortables = []

    // Find all dropzones (one per todo state)
    const dropzones = this.el.querySelectorAll("[data-dropzone]")

    dropzones.forEach((dropzone) => {
      const sortable = new Sortable(dropzone, {
        group: "todos", // Allow dragging between all dropzones
        animation: 150,
        handle: ".todo-drag-handle", // Only drag from handle
        draggable: ".todo-item", // Only these elements are draggable
        ghostClass: "opacity-50",

        onEnd: (evt) => {
          // Get the todo ID from the dragged element
          const todoId = evt.item.dataset.todoId

          // Get the new state ID from the dropzone
          const newStateId = evt.to.dataset.stateId

          // Get the old state ID from the previous dropzone
          const oldStateId = evt.from.dataset.stateId

          // Only send event if the state actually changed
          if (oldStateId !== newStateId) {
            this.pushEvent("todo-moved", {
              todo_id: todoId,
              new_state_id: newStateId
            })
          }
        }
      })

      this.sortables.push(sortable)
    })
  },

  destroyed() {
    // Clean up Sortable instances
    this.sortables.forEach(sortable => sortable.destroy())
    this.sortables = []
  }
}

export default TodoDragDrop
