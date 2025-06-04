defmodule ArchethicWeb.Explorer do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller, namespace: ArchethicWeb.Explorer

      import Phoenix.LiveView.Controller
      import Plug.Conn

      alias ArchethicWeb.Router.Helpers, as: Routes
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/archethic_web/explorer/templates",
        namespace: ArchethicWeb.Explorer

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [view_module: 1]

      # Include shared imports and aliases for views
      unquote(view_helpers())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {ArchethicWeb.Explorer.LayoutView, :live}

      unquote(view_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(view_helpers())
    end
  end

  defp view_helpers do
    quote do
      use PhoenixHTMLHelpers

      import ArchethicWeb.WebUtils
      # Use all HTML functionality (forms, tags, etc)
      import Phoenix.HTML
      import Phoenix.HTML.Form

      # Import LiveView helpers (live_render, live_component, live_patch, etc)
      import Phoenix.LiveView.Helpers

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View

      alias ArchethicWeb.ExplorerRouter.Helpers, as: Routes
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Phoenix.LiveDashboard.Router
      import Phoenix.LiveView.Router
      import Plug.Conn
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
