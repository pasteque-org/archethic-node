defmodule Archethic.Reward.MemTablesLoader do
  @moduledoc false

  use GenServer

  alias Archethic.Reward.MemTables.RewardTokens
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  @vsn 1

  @query_fields [:address, :type]

  @required_type :mint_rewards
  # server
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    :ok = load_table()
    {:ok, %{}}
  end

  def load_table do
    @required_type
    |> TransactionChain.list_transactions_by_type(@query_fields)
    |> Enum.each(&load_transaction/1)

    :ok
  end

  # api
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{address: address, type: @required_type}) do
    RewardTokens.add_reward_token_address(address)
  end

  def load_transaction(%Transaction{address: _address, type: _}) do
    :ok
  end

  def reload_memtables do
    :ok = load_table()
  end
end
