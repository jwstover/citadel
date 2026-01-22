defmodule CitadelWeb.LegalLive.Privacy do
  use CitadelWeb, :live_view

  import CitadelWeb.Components.Markdown, only: [to_markdown: 1]

  @impl true
  def mount(_params, _session, socket) do
    content = read_legal_document("privacy.md")

    {:ok,
     socket
     |> assign(:page_title, "Privacy Policy")
     |> assign(:content, content)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.public flash={@flash}>
      <article class="prose prose-sm sm:prose lg:prose-lg max-w-none prose-headings:text-base-content prose-p:text-base-content prose-a:text-primary prose-strong:text-base-content prose-table:text-base-content">
        {@content}
      </article>
    </Layouts.public>
    """
  end

  defp read_legal_document(filename) do
    path = Application.app_dir(:citadel, "priv/static/legal/#{filename}")

    case File.read(path) do
      {:ok, content} -> to_markdown(content)
      {:error, _} -> "Document not found."
    end
  end
end
