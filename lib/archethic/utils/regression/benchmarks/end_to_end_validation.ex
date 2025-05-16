defmodule Archethic.Utils.Regression.Benchmark.EndToEndValidation do
  @moduledoc """
  Defines a benchmark suite for measuring end-to-end UCO transfer transaction performance.

  This benchmark simulates sending UCO transfer transactions and measures the time
  from sending the transaction via the HTTP API until its confirmation (replication)
  by the network.

  It utilizes a pool of pre-funded addresses (`SeedHolder`) and runs transfers
  in parallel to simulate concurrent load.
  """

  require Logger

  alias Archethic.Utils.Regression.Benchmark.SeedHolder
  alias Archethic.Utils.Regression.Benchmark

  alias ArchethicClient.Crypto
  alias ArchethicClient.TransactionData
  alias ArchethicClient.Transaction
  alias Archethic.Utils.Regression.Api
  @behaviour Benchmark

  @impl Benchmark
  @doc """
  Prepares and configures the end-to-end UCO transfer benchmark.
  """
  def plan(_node, _opts) do
    Logger.info("EndToEndValidation - Starting Benchmark: Transactions Per Seconds")

    seeds =
      Enum.map(0..99, fn _ ->
        :crypto.strong_rand_bytes(32)
      end)

    {:ok, pid} = SeedHolder.start_link(seeds: seeds)

    amount_to_fund = 100
    amount_to_transfer = 10

    pid
    |> SeedHolder.get_seeds()
    |> Map.new(&{&1, amount_to_fund})
    |> Api.send_funds_to_seeds()

    {
      %{
        "UCO Transfer single recipient" => fn ->
          recipient_seed = SeedHolder.get_random_seed(pid)
          uco_transfer_single_recipient(pid, recipient_seed, amount_to_transfer)
        end
      },
      [parallel: 4]
    }
  end

  # Function private helper to build the TransactionData for a UCO transfer.
  defp build_uco_transfer_data(recipient_address, amount_to_transfer) do
    %TransactionData{}
    |> TransactionData.add_uco_transfer(recipient_address, amount_to_transfer)
  end

  # Private helper function executing a single UCO transfer operation for the benchmark.
  # This function is called repeatedly by Benchee.
  defp uco_transfer_single_recipient(pid, recipient_seed, amount_to_transfer) do
    {sender_seed, index} = SeedHolder.pop_seed(pid)

    tx =
      Crypto.derive_address(recipient_seed, 0)
      |> build_uco_transfer_data(amount_to_transfer)
      |> Transaction.build(:transfer, sender_seed)

    case ArchethicClient.send_transaction(tx) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "EndToEndValiation - UCO transfer failed: #{inspect(reason)}"
    end

    SeedHolder.put_seed(pid, sender_seed, index)
    tx.address
  end
end
