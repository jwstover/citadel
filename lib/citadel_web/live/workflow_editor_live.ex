defmodule CitadelWeb.WorkflowEditorLive do
  use CitadelWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_workspace={@current_workspace}
      workspaces={@workspaces}
      agents={@agents}
    >
      <div class="p-6">
        <h1 class="text-2xl font-bold mb-4">Workflow Editor</h1>
        <div
          id="workflow-editor"
          phx-hook="WorkflowEditor"
          phx-update="ignore"
          class="w-full h-[calc(100vh-12rem)]"
        >
        </div>
      </div>
    </Layouts.app>
    """
  end
end
