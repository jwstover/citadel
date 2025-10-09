defmodule CitadelWeb.Components.TodoComponents do
  @moduledoc false

  use CitadelWeb, :html

  def control_bar(assigns) do
    ~H"""
    <div class="flex p-2 pl-6 border-b border-base-300">
      <div>
        <.button class="btn btn-sm btn-neutral">
          <.icon name="hero-plus" class="size-4" /> New
        </.button>
      </div>
    </div>
    """
  end

  def todos_list(assigns) do
    ~H"""
    <div>
      <.todo />
      <.todo />
      <.todo />
      <.todo />
      <.todo />
    </div>
    """
  end

  def todo(assigns) do
    ~H"""
    <div class="flex flex-row justify-between pl-6 py-2 hover:bg-base-100">
      <div class="flex flex-row items-center gap-2">
        <input type="checkbox" class="checkbox checkbox-xs" name="todo_status" value="false" />
        <div class="text-neutral-content">T-1</div>
        <div>Implement basic todo functionality</div>
      </div>

      <div></div>
    </div>
    """
  end
end
