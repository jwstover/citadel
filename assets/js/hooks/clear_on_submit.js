const ClearOnSubmit = {
  mounted() {
    this.el.form.addEventListener("submit", () => {
      requestAnimationFrame(() => {
        this.el.value = ""
      })
    })
  }
}

export default ClearOnSubmit
