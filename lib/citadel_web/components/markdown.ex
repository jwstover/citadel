defmodule CitadelWeb.Components.Markdown do
  @moduledoc """
  Shared markdown rendering utilities for the application.
  """

  use Phoenix.Component

  @doc """
  Converts markdown text to sanitized HTML.

  Uses MDEx with GitHub Flavored Markdown extensions including:
  - Strikethrough
  - Tables
  - Task lists
  - Autolinks
  - Footnotes

  The HTML is sanitized for security before being rendered.
  Falls back to plain text if parsing fails.

  ## Examples

      iex> to_markdown("# Hello")
      # Returns sanitized HTML
  """
  # sobelow_skip ["XSS.Raw"]
  def to_markdown(text) do
    # Note that you must pass the "unsafe: true" option to first generate the raw HTML
    # in order to sanitize it. https://hexdocs.pm/mdex/MDEx.html#module-sanitize
    MDEx.to_html(text,
      extension: [
        strikethrough: true,
        tagfilter: true,
        table: true,
        autolink: true,
        tasklist: true,
        footnotes: true,
        shortcodes: true
      ],
      parse: [
        smart: true,
        relaxed_tasklist_matching: true,
        relaxed_autolinks: true
      ],
      render: [
        github_pre_lang: true,
        unsafe: true
      ],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> case do
      {:ok, html} ->
        # Safe: HTML is sanitized by MDEx.to_html with default_sanitize_options() before being marked as safe
        Phoenix.HTML.raw(html)

      {:error, _} ->
        text
    end
  end
end
