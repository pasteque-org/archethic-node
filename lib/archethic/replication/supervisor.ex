defmodule Archethic.Replication.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Replication.TransactionPool

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    children = [
      TransactionPool
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
