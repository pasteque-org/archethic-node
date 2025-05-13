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

  alias ArchethicClient
  alias ArchethicClient.Crypto
  alias ArchethicClient.TransactionData
  alias ArchethicClient.Transaction

  @behaviour Benchmark

  @unit_uco 100_000_000
  @faucet_seed Application.compile_env!(:archethic, [
                 ArchethicWeb.Explorer.FaucetController,
                 :seed
               ])

  @impl Benchmark
  @doc """
  Prepares and configures the end-to-end UCO transfer benchmark.

  This function is called by the `Benchee` runner. It:
  1. Sets up the API endpoint for the target node.
  2. Starts a WebSocket client for replication confirmation.
  3. Generates a pool of test seeds.
  4. Starts the `SeedHolder` GenServer to manage the seeds.
  5. Pre-funds the addresses derived from the seeds using the Faucet via the API.
  6. Returns the benchmark configuration for `Benchee`, defining the scenario
     (`"UCO Transfer single recipient"`) and the parallel execution options.
  """
  def plan([_nodes], _opts) do
    Logger.info(
      "EndToEndValidation - Starting Benchmark: Transactions Per Seconds at #{Application.get_env(:archethic_client, :base_url)}"
    )

    seeds =
      Enum.map(0..99, fn _ ->
        :crypto.strong_rand_bytes(32)
      end)

    {:ok, pid} = SeedHolder.start_link(seeds: seeds)

    amount_to_fund = 100 * @unit_uco
    amount_to_transfer = 1 * @unit_uco

    funding_seeds_map =
      SeedHolder.get_seeds(pid)
      |> Enum.map(fn seed ->
        addr = Crypto.derive_address(seed, 0)
        {addr, amount_to_fund}
      end)
      |> Map.new()

    funding_tx =
      Enum.reduce(funding_seeds_map, %TransactionData{}, fn {address, amount}, acc ->
        acc
        |> TransactionData.add_uco_transfer(address, amount)
      end)
      |> Transaction.build(:transfer, @faucet_seed)

    case ArchethicClient.send_transaction(funding_tx) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("EndToEndValidation - Funding transaction failed: #{inspect(reason)}")
        # Decide if we should raise here or allow benchmark to proceed partially/fail later
        raise "EndToEndValidation - Funding transaction failed: #{inspect(reason)}"
    end

    Logger.info("EndToEndValidation - Pre-funded #{map_size(funding_seeds_map)} addresses.")

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

    {recipient_pub_key, _} = Crypto.derive_keypair(recipient_seed, 0)
    recipient_address = Crypto.derive_public_key_address(recipient_pub_key)

    tx_data = build_uco_transfer_data(recipient_address, amount_to_transfer)

    # --- Manually fetch sender chain index for transfer transaction ---
    {sender_pub_key, _} = Crypto.derive_keypair(sender_seed, 0)
    sender_address = Crypto.derive_public_key_address(sender_pub_key)
    sender_address_hex = Base.encode16(sender_address)

    sender_chain_index =
      case ArchethicClient.get_chain_index(sender_address_hex) do
        {:ok, index} -> index
        {:error, reason} -> raise "Failed to fetch chain index: #{inspect(reason)}"
      end

    # --- End manual fetch ---

    tx = Transaction.build(tx_data, :transfer, sender_seed, index: sender_chain_index)

    ArchethicClient.send_transaction(tx)

    SeedHolder.put_seed(pid, sender_seed, index)
    tx.address
  end
end
