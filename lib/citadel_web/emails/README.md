# Email Templates

This directory contains MJML email templates using the `mjml_eex` library. All emails use a shared layout for consistent branding.

## Directory Structure

```
lib/citadel_web/emails/
├── README.md
├── base_layout.ex              # Layout module (header + footer)
├── base_layout.mjml.eex        # Layout template
├── workspace_invitation.ex     # Example email module
└── workspace_invitation.mjml.eex
```

## Adding a New Email

### 1. Create the MJML Template

Create `lib/citadel_web/emails/my_email.mjml.eex`:

```mjml
<mj-section background-color="#ffffff" padding="30px">
  <mj-column>
    <mj-text font-size="22px" font-weight="bold" color="#1a1a1a">
      <%= @title %>
    </mj-text>

    <mj-text padding-top="20px">
      <%= @body_text %>
    </mj-text>

    <mj-button href="<%= @action_url %>" padding-top="24px">
      <%= @action_text %>
    </mj-button>
  </mj-column>
</mj-section>
```

Note: Only include the content sections. The `<mjml>`, `<mj-head>`, and `<mj-body>` tags are provided by the layout.

### 2. Create the Template Module

Create `lib/citadel_web/emails/my_email.ex`:

```elixir
defmodule CitadelWeb.Emails.MyEmail do
  @moduledoc """
  MJML template for [describe the email purpose].
  """
  use MjmlEEx,
    mjml_template: "my_email.mjml.eex",
    layout: CitadelWeb.Emails.BaseLayout
end
```

### 3. Add the Composition Function

Add a function to `lib/citadel/emails.ex`:

```elixir
alias CitadelWeb.Emails.MyEmail, as: MyEmailTemplate

def my_email(recipient, params) do
  app_url = CitadelWeb.Endpoint.url()

  html_body =
    MyEmailTemplate.render(
      title: params.title,
      body_text: params.body_text,
      action_url: params.action_url,
      action_text: params.action_text,
      app_url: app_url  # Required by layout for footer link
    )

  new()
  |> to({nil, recipient})
  |> from(@from_address)
  |> subject(params.subject)
  |> html_body(html_body)
  |> text_body(my_email_text_body(params))
end
```

## Design System

The base layout defines these default styles:

| Element | Value |
|---------|-------|
| Primary color | `#3b82f6` (blue) |
| Text color | `#333333` |
| Muted text | `#666666` / `#999999` |
| Background | `#f4f4f5` (light gray) |
| Font family | System font stack |
| Button radius | `6px` |

## Layout Assigns

The base layout requires these assigns:

- `@app_url` - The application URL for the footer link (use `CitadelWeb.Endpoint.url()`)
- `@inner_content` - Automatically injected by mjml_eex

## Common MJML Components

```mjml
<!-- Text -->
<mj-text>Your text here</mj-text>

<!-- Button -->
<mj-button href="<%= @url %>">Click Me</mj-button>

<!-- Divider -->
<mj-divider border-color="#e5e5e5" />

<!-- Image -->
<mj-image src="<%= @image_url %>" alt="Description" />

<!-- Spacer -->
<mj-spacer height="20px" />
```

## Testing

Emails are viewable at `/dev/mailbox` in development. The Swoosh local adapter captures all sent emails.

## Resources

- [MJML Documentation](https://documentation.mjml.io/)
- [mjml_eex GitHub](https://github.com/akoutmos/mjml_eex)
