const AutoScroll = {
  mounted() {
    this.shouldAutoScroll = true
    this.el.addEventListener("scroll", () => {
      const { scrollTop, scrollHeight, clientHeight } = this.el
      this.shouldAutoScroll = scrollHeight - scrollTop - clientHeight < 50
    })
  },
  updated() {
    if (this.shouldAutoScroll) {
      this.el.scrollTop = this.el.scrollHeight
    }
  }
}

export default AutoScroll
