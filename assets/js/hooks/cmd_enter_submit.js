const CmdEnterSubmit = {
  mounted() {
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault()
        this.el.closest("form").requestSubmit()
      }
    })
  },
}

export default CmdEnterSubmit
