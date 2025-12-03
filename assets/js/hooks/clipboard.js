const Clipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      const targetSelector = this.el.dataset.clipboardTarget
      const targetEl = document.querySelector(targetSelector)

      if (targetEl) {
        const text = targetEl.value || targetEl.textContent
        navigator.clipboard.writeText(text).then(() => {
          const originalText = this.el.innerHTML
          this.el.innerHTML = this.el.innerHTML.replace("Copy", "Copied!")
          setTimeout(() => {
            this.el.innerHTML = originalText
          }, 2000)
        })
      }
    })
  }
}

export default Clipboard
