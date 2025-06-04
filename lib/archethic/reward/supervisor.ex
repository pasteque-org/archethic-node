defmodule Archethic.Reward.Supervisor do
  @moduledoc false

  use Supervisor

  alias Archethic.Reward.MemTables.RewardTokens
  alias Archethic.Reward.MemTablesLoader
  alias Archethic.Reward.Scheduler
  alias Archethic.Utils

  @spec start_link(any) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: Archethic.RewardSupervisor)
  end

  def init(_) do
    children = [
      {Scheduler, Application.get_env(:archethic, Scheduler)},
      RewardTokens,
      MemTablesLoader
    ]

    Supervisor.init(Utils.configurable_children(children), strategy: :rest_for_one)
  end
end
