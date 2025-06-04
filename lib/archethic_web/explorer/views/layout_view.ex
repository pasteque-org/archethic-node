defmodule ArchethicWeb.Explorer.LayoutView do
  @moduledoc false
  use ArchethicWeb.Explorer, :view

  def faucet? do
    :archethic
    |> Application.get_env(ArchethicWeb.Explorer.FaucetController)
    |> Keyword.get(:enabled, false)
  end
end
