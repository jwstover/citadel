defmodule CitadelWeb.LandingLiveTest do
  use CitadelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "mount/3 - unauthenticated user" do
    test "renders landing page" do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Citadel"
      assert html =~ "AI-Powered"
    end

    test "displays hero section with CTAs" do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s|a[href="/register"]|, "Get Started")
      assert has_element?(view, ~s|a[href="#features"]|)
    end

    test "displays features section" do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Features"
      assert html =~ "AI-Powered Organization"
      assert html =~ "Natural Language Input"
      assert html =~ "Team Workspaces"
      assert html =~ "Smart Subtasks"
      assert html =~ "AI Chat Assistant"
    end

    test "displays pricing section" do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Pricing"
      assert html =~ "Free"
      assert html =~ "Pro"
      assert html =~ "$0"
      assert html =~ "$12"
    end

    test "displays footer with links" do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Terms of Service"
      assert html =~ "Privacy Policy"
      assert html =~ "Contact"
    end

    test "shows sign in and get started buttons in header" do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s|header a[href="/sign-in"]|, "Sign In")
      assert has_element?(view, ~s|header a[href="/register"]|, "Get Started")
    end
  end

  describe "mount/3 - authenticated user" do
    setup :register_and_log_in_user

    test "renders landing page for authenticated users", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Citadel"
      assert html =~ "AI-Powered"
    end

    test "shows dashboard button instead of get started in header", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s|header a[href="/dashboard"]|, "Dashboard")
      refute has_element?(view, ~s|header a[href="/register"]|, "Get Started")
      refute has_element?(view, ~s|header a[href="/sign-in"]|, "Sign In")
    end

    test "shows dashboard button in hero section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s|section a[href="/dashboard"]|, "Dashboard")
    end
  end

  describe "navigation" do
    test "nav links have correct hrefs" do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s|a[href="#features"]|, "Features")
      assert has_element?(view, ~s|a[href="#pricing"]|, "Pricing")
    end

    test "sections have correct ids for anchor navigation" do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s|section#features|)
      assert has_element?(view, ~s|section#pricing|)
    end
  end

  describe "page title" do
    test "sets appropriate page title" do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "AI-Powered Task Management"
    end
  end
end
