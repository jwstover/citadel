const MilkdownEditor = {
  editor: null,
  saveTimeout: null,
  editable: null,

  async mounted() {
    const content = this.el.dataset.content || ""
    const readonly = this.el.dataset.readonly === "true"
    this.editable = { current: !readonly }

    // Dynamic imports - Milkdown is only loaded when this hook mounts
    const [
      { Editor, rootCtx, defaultValueCtx, editorViewOptionsCtx },
      { commonmark },
      { gfm },
      { listener, listenerCtx },
      { history },
      { highlight, highlightPluginConfig },
      { createParser },
      { common, createLowlight },
      { default: elixir },
      { $prose },
      { Plugin, PluginKey }
    ] = await Promise.all([
      import("@milkdown/kit/core"),
      import("@milkdown/kit/preset/commonmark"),
      import("@milkdown/kit/preset/gfm"),
      import("@milkdown/kit/plugin/listener"),
      import("@milkdown/kit/plugin/history"),
      import("@milkdown/plugin-highlight"),
      import("@milkdown/plugin-highlight/lowlight"),
      import("lowlight"),
      import("highlight.js/lib/languages/elixir"),
      import("@milkdown/kit/utils"),
      import("@milkdown/kit/prose/state")
    ])

    // Import CSS
    await import("@milkdown/kit/prose/view/style/prosemirror.css")

    const lowlight = createLowlight(common)
    lowlight.register("elixir", elixir)
    const parser = createParser(lowlight)

    // Plugin to make links clickable
    const clickableLinkPlugin = $prose(() => {
      return new Plugin({
        key: new PluginKey("clickable-links"),
        props: {
          handleClick(view, pos, event) {
            const target = event.target
            if (target.tagName === "A" && target.href) {
              event.preventDefault()
              window.open(target.href, "_blank", "noopener,noreferrer")
              return true
            }
            return false
          }
        }
      })
    })

    this.editor = await Editor.make()
      .config((ctx) => {
        ctx.set(rootCtx, this.el)
        ctx.set(defaultValueCtx, content)
        ctx.update(editorViewOptionsCtx, (prev) => ({
          ...prev,
          editable: () => this.editable.current,
        }))
        ctx.get(listenerCtx).markdownUpdated((ctx, markdown, prevMarkdown) => {
          if (this.editable.current && markdown !== prevMarkdown) {
            this.debouncedSave(markdown)
          }
        })
        ctx.set(highlightPluginConfig.key, { parser })
      })
      .use(commonmark)
      .use(gfm)
      .use(listener)
      .use(history)
      .use(highlight)
      .use(clickableLinkPlugin)
      .create()
  },

  debouncedSave(content) {
    clearTimeout(this.saveTimeout)
    this.saveTimeout = setTimeout(() => {
      this.pushEvent("save-description", { content })
    }, 1000)
  },

  async destroyed() {
    clearTimeout(this.saveTimeout)
    if (this.editor) {
      await this.editor.destroy()
      this.editor = null
    }
  }
}

export default MilkdownEditor
