defmodule ArchethicWeb.AEWeb do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller, namespace: ArchethicWeb.AEWeb

      import Plug.Conn
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/archethic_web/aeweb/templates",
        namespace: ArchethicWeb.AEWeb

      import ArchethicWeb.WebUtils

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [view_module: 1]
      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Phoenix.Controller
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
