import { Editor, rootCtx, defaultValueCtx, editorViewOptionsCtx } from "@milkdown/kit/core"
import { commonmark } from "@milkdown/kit/preset/commonmark"
import { gfm } from "@milkdown/kit/preset/gfm"
import { listener, listenerCtx } from "@milkdown/kit/plugin/listener"
import { history } from "@milkdown/kit/plugin/history"
import "@milkdown/kit/prose/view/style/prosemirror.css"

const MilkdownEditor = {
  editor: null,
  saveTimeout: null,
  editable: null,

  async mounted() {
    const content = this.el.dataset.content || ""
    const readonly = this.el.dataset.readonly === "true"
    this.editable = { current: !readonly }

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
      })
      .use(commonmark)
      .use(gfm)
      .use(listener)
      .use(history)
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
