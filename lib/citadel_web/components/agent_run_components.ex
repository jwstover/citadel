defmodule CitadelWeb.AgentRunComponents do
  @moduledoc false
  use Phoenix.Component

  import CitadelWeb.CoreComponents

  attr :event, :map, required: true

  def stream_event(%{event: %{type: :assistant}} = assigns) do
    ~H"""
    <div class="space-y-3">
      <div :for={block <- @event.blocks} class="flex gap-2">
        <.assistant_block block={block} />
      </div>
    </div>
    """
  end

  def stream_event(%{event: %{type: :tool_result}} = assigns) do
    ~H"""
    <div class="space-y-2">
      <div :for={result <- @event.results}>
        <.tool_result_block result={result} />
      </div>
    </div>
    """
  end

  def stream_event(%{event: %{type: :result}} = assigns) do
    ~H"""
    <div class="rounded-lg bg-base-200 border border-base-300 p-3 text-sm">
      <div class="flex items-center gap-2 text-base-content/70">
        <.icon name="hero-flag" class="size-4 shrink-0" />
        <span class="font-medium">
          {result_label(@event)}
        </span>
      </div>
      <div
        :if={@event[:duration_ms]}
        class="mt-1.5 flex flex-wrap gap-x-4 gap-y-1 text-xs text-base-content/50"
      >
        <span>{format_duration(@event.duration_ms)}</span>
        <span :if={@event[:num_turns]}>{@event.num_turns} turns</span>
        <span :if={@event[:total_cost_usd]}>{"$#{Float.round(@event.total_cost_usd, 4)}"}</span>
      </div>
    </div>
    """
  end

  def stream_event(%{event: %{type: :system}} = assigns) do
    ~H"""
    <div class="flex items-center gap-2 rounded-lg bg-base-200 border border-base-300 p-3 text-xs text-base-content/50">
      <.icon name="hero-cog-6-tooth" class="size-4 shrink-0" />
      <span>Session started</span>
      <span :if={@event[:model]} class="font-mono">{@event.model}</span>
    </div>
    """
  end

  def stream_event(%{event: %{type: type}} = assigns) when type in [:error, :unknown] do
    ~H"""
    <div class="rounded-lg bg-base-300/50 p-3">
      <pre
        class="text-xs text-base-content/40 whitespace-pre-wrap break-all font-mono"
        phx-no-curly-interpolation
      ><%= format_raw(@event) %></pre>
    </div>
    """
  end

  def stream_event(assigns) do
    ~H"""
    <div class="rounded-lg bg-base-300/50 p-3">
      <pre
        class="text-xs text-base-content/40 whitespace-pre-wrap break-all font-mono"
        phx-no-curly-interpolation
      ><%= format_raw(@event) %></pre>
    </div>
    """
  end

  attr :block, :map, required: true

  defp assistant_block(%{block: %{type: :text}} = assigns) do
    ~H"""
    <div class="flex gap-2.5 min-w-0">
      <.icon name="hero-chat-bubble-left" class="size-4 shrink-0 mt-0.5 text-base-content/50" />
      <div class="prose prose-sm prose-invert max-w-none text-base-content whitespace-pre-wrap break-words min-w-0">
        {@block.text}
      </div>
    </div>
    """
  end

  defp assistant_block(%{block: %{type: :tool_use}} = assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-200 p-3 w-full">
      <div class="flex items-center gap-2">
        <.icon name="hero-wrench" class="size-4 shrink-0 text-info" />
        <span class="font-mono text-sm font-semibold text-info">{@block.tool}</span>
        <span class="text-xs text-base-content/40">calling tool</span>
      </div>
      <div :if={@block[:input] && @block.input != %{}} class="mt-2">
        <pre
          class="text-xs text-base-content/50 whitespace-pre-wrap break-all font-mono bg-base-300/50 rounded p-2 overflow-x-auto"
          phx-no-curly-interpolation
        ><%= format_json(@block.input) %></pre>
      </div>
    </div>
    """
  end

  defp assistant_block(assigns) do
    ~H"""
    <div class="rounded-lg bg-base-300/50 p-2">
      <pre
        class="text-xs text-base-content/40 whitespace-pre-wrap break-all font-mono"
        phx-no-curly-interpolation
      ><%= format_raw(@block) %></pre>
    </div>
    """
  end

  attr :result, :map, required: true

  defp tool_result_block(%{result: %{type: :tool_result}} = assigns) do
    ~H"""
    <details class="rounded-lg border border-base-300 bg-base-200 group">
      <summary class="flex items-center gap-2 p-3 cursor-pointer select-none list-none [&::-webkit-details-marker]:hidden">
        <.icon
          name="hero-chevron-right"
          class="size-3.5 shrink-0 text-base-content/40 transition-transform group-open:rotate-90"
        />
        <.icon
          name="hero-document-check"
          class={
            if @result[:is_error],
              do: "size-4 shrink-0 text-error",
              else: "size-4 shrink-0 text-success"
          }
        />
        <span class="text-sm font-medium text-base-content/70">
          {if @result[:is_error], do: "Error", else: "Result"}
        </span>
      </summary>
      <div class="border-t border-base-300 p-3">
        <pre
          class="text-xs text-base-content/60 whitespace-pre-wrap break-all font-mono max-h-96 overflow-y-auto"
          phx-no-curly-interpolation
        ><%= format_tool_content(@result[:content]) %></pre>
      </div>
    </details>
    """
  end

  defp tool_result_block(assigns) do
    ~H"""
    <div class="rounded-lg bg-base-300/50 p-2">
      <pre
        class="text-xs text-base-content/40 whitespace-pre-wrap break-all font-mono"
        phx-no-curly-interpolation
      ><%= format_raw(@result) %></pre>
    </div>
    """
  end

  defp result_label(%{subtype: "success"}), do: "Completed successfully"
  defp result_label(%{is_error: true}), do: "Completed with error"
  defp result_label(%{stop_reason: reason}) when is_binary(reason), do: "Finished — #{reason}"
  defp result_label(_), do: "Finished"

  defp format_duration(ms) when is_number(ms) and ms >= 60_000 do
    minutes = div(ms, 60_000)
    seconds = div(rem(ms, 60_000), 1000)
    "#{minutes}m #{seconds}s"
  end

  defp format_duration(ms) when is_number(ms) do
    seconds = Float.round(ms / 1000, 1)
    "#{seconds}s"
  end

  defp format_duration(_), do: ""

  defp format_json(input) when is_map(input) do
    case Jason.encode(input, pretty: true) do
      {:ok, json} -> json
      _ -> inspect(input)
    end
  end

  defp format_json(input), do: inspect(input)

  defp format_tool_content(content) when is_binary(content), do: content
  defp format_tool_content(content) when is_list(content), do: Enum.join(content, "\n")
  defp format_tool_content(content) when is_map(content), do: format_json(content)
  defp format_tool_content(nil), do: "(no content)"
  defp format_tool_content(content), do: inspect(content)

  defp format_raw(%{raw: raw}) when is_binary(raw), do: raw
  defp format_raw(%{raw: raw}) when is_map(raw), do: format_json(raw)
  defp format_raw(data) when is_map(data), do: format_json(data)
  defp format_raw(data), do: inspect(data)
end
