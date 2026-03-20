defmodule CitadelWeb.PreferencesLive.ModelConfigSectionTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Citadel.Generator

  alias Citadel.Tasks

  describe "empty state" do
    setup :register_and_log_in_user

    test "shows empty state message when no configs exist", %{conn: conn, workspace: workspace} do
      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ "Model Configuration"
      assert html =~ "No model configurations yet."
      assert html =~ "Agents will use system defaults."
    end

    test "shows Add Configuration button", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert has_element?(view, ~s|[phx-click="show-config-form"]|)
    end
  end

  describe "listing configs" do
    setup :register_and_log_in_user

    test "displays existing model configs", %{conn: conn, user: user, workspace: workspace} do
      generate(
        model_config(
          [name: "Fast Draft", provider: :anthropic, model: "claude-sonnet-4-20250514"],
          actor: user,
          tenant: workspace.id
        )
      )

      {:ok, _view, html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert html =~ "Fast Draft"
      assert html =~ "Anthropic"
      assert html =~ "claude-sonnet-4-20250514"
    end

    test "shows default star icon for default config", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      config =
        generate(
          model_config([name: "Default Config"],
            actor: user,
            tenant: workspace.id
          )
        )

      Tasks.set_model_config_default!(config, actor: user, tenant: workspace.id)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      assert has_element?(view, ~s|.text-warning .hero-star-solid|) ||
               render(view) =~ "hero-star-solid"
    end
  end

  describe "create config" do
    setup :register_and_log_in_user

    test "clicking Add opens the form", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      html =
        view
        |> element(~s|[phx-click="show-config-form"]|)
        |> render_click()

      assert html =~ "New Configuration"
      assert has_element?(view, "#model-config-form")
    end

    test "submitting the form creates a config", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      view
      |> element(~s|[phx-click="show-config-form"]|)
      |> render_click()

      html =
        view
        |> form("#model-config-form", %{
          form: %{
            name: "My Config",
            provider: "anthropic",
            model: "claude-sonnet-4-20250514",
            temperature: "0.5"
          }
        })
        |> render_submit()

      assert html =~ "My Config"
      assert html =~ "claude-sonnet-4-20250514"
      refute has_element?(view, "#model-config-form")
    end

    test "canceling the form hides it", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      view
      |> element(~s|[phx-click="show-config-form"]|)
      |> render_click()

      assert has_element?(view, "#model-config-form")

      view
      |> element(~s|[phx-click="cancel-config-form"]|)
      |> render_click()

      refute has_element?(view, "#model-config-form")
    end
  end

  describe "edit config" do
    setup :register_and_log_in_user

    test "clicking edit opens form with existing values", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      config =
        generate(
          model_config([name: "Edit Me", model: "gpt-4o"],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      html =
        view
        |> element(~s|[phx-click="edit-config"][phx-value-id="#{config.id}"]|)
        |> render_click()

      assert html =~ "Edit Configuration"
      assert has_element?(view, "#model-config-form")
    end

    test "submitting edit updates the config", %{conn: conn, user: user, workspace: workspace} do
      config =
        generate(
          model_config([name: "Old Name", model: "gpt-4o", provider: :openai],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      view
      |> element(~s|[phx-click="edit-config"][phx-value-id="#{config.id}"]|)
      |> render_click()

      html =
        view
        |> form("#model-config-form", %{
          form: %{name: "New Name"}
        })
        |> render_submit()

      assert html =~ "New Name"
    end
  end

  describe "delete config" do
    setup :register_and_log_in_user

    test "clicking delete shows confirmation modal", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      config =
        generate(
          model_config([name: "Delete Me"],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      html =
        view
        |> element(~s|[phx-click="confirm-delete-config"][phx-value-id="#{config.id}"]|)
        |> render_click()

      assert html =~ "Delete Model Configuration"
      assert html =~ "Are you sure"
    end

    test "confirming delete removes the config", %{conn: conn, user: user, workspace: workspace} do
      config =
        generate(
          model_config([name: "Gone Soon"],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      view
      |> element(~s|[phx-click="confirm-delete-config"][phx-value-id="#{config.id}"]|)
      |> render_click()

      html =
        view
        |> element(~s|[phx-click="delete-config"]|)
        |> render_click()

      refute html =~ "Gone Soon"
    end

    test "canceling delete closes the modal", %{conn: conn, user: user, workspace: workspace} do
      config =
        generate(
          model_config([name: "Still Here"],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      view
      |> element(~s|[phx-click="confirm-delete-config"][phx-value-id="#{config.id}"]|)
      |> render_click()

      html =
        view
        |> element(~s|button.btn-ghost:not(.btn-circle)[phx-click="cancel-delete-config"]|)
        |> render_click()

      assert html =~ "Still Here"
      refute html =~ "Are you sure"
    end
  end

  describe "set default" do
    setup :register_and_log_in_user

    test "clicking star sets config as default", %{conn: conn, user: user, workspace: workspace} do
      config =
        generate(
          model_config([name: "Make Default"],
            actor: user,
            tenant: workspace.id
          )
        )

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      view
      |> element(~s|[phx-click="toggle-default"][phx-value-id="#{config.id}"]|)
      |> render_click()

      updated = Tasks.get_model_config!(config.id, actor: user, tenant: workspace.id)
      assert updated.is_default == true
    end

    test "setting a new default unsets the previous one", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      config1 =
        generate(
          model_config([name: "Config 1"],
            actor: user,
            tenant: workspace.id
          )
        )

      config2 =
        generate(
          model_config([name: "Config 2"],
            actor: user,
            tenant: workspace.id
          )
        )

      Tasks.set_model_config_default!(config1, actor: user, tenant: workspace.id)

      {:ok, view, _html} = live(conn, ~p"/preferences/workspace/#{workspace.id}")

      view
      |> element(~s|[phx-click="toggle-default"][phx-value-id="#{config2.id}"]|)
      |> render_click()

      updated1 = Tasks.get_model_config!(config1.id, actor: user, tenant: workspace.id)
      updated2 = Tasks.get_model_config!(config2.id, actor: user, tenant: workspace.id)

      assert updated1.is_default == false
      assert updated2.is_default == true
    end
  end
end
