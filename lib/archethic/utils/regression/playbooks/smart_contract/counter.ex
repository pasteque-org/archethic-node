defmodule Archethic.Utils.Regression.Playbook.SmartContract.Counter do
  @moduledoc """
  This contract is triggered by transactions.
  It starts with content=0 and increments the counter for each transaction received.
  """

  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.Regression.Playbook.SmartContract
  alias ArchethicClient.Crypto
  alias ArchethicClient.Transaction
  alias ArchethicClient.TransactionData

  require Logger

  @wasm_binary "priv/regression/counter/contract.wasm"
  @wasm_manifest "priv/regression/counter/manifest.json"
  @nb_transactions 100
  @initial_seed_balance 10

  def play(storage_nonce_pubkey) do
    Logger.info("============== CONTRACT: WASM COUNTER ==============")

    contract_seed = SmartContract.random_seed()
    triggers_seeds = generate_trigger_seeds(@nb_transactions)

    initial_funds = prepare_initial_funds(triggers_seeds, contract_seed, @initial_seed_balance)
    Api.send_funds_to_seeds(initial_funds)

    genesis_address = Crypto.derive_address(contract_seed, 0)
    contract_address = deploy_contract(contract_seed, storage_nonce_pubkey)

    results = execute_triggers(triggers_seeds, contract_address)

    evaluate_results(results, genesis_address)
  end

  defp generate_trigger_seeds(n), do: Enum.map(1..n, fn _ -> SmartContract.random_seed() end)

  defp prepare_initial_funds(seeds, contract_seed, amount) do
    Enum.reduce(seeds, %{contract_seed => amount}, fn seed, acc ->
      Map.put(acc, seed, amount)
    end)
  end

  defp deploy_contract(contract_seed, storage_nonce_pubkey) do
    contract = SmartContract.read_wasm_contract(@wasm_binary, @wasm_manifest)

    %TransactionData{}
    |> TransactionData.set_contract(contract)
    |> SmartContract.deploy(contract_seed, storage_nonce_pubkey)
  end

  defp execute_triggers(seeds, contract_address) do
    seeds
    |> Task.async_stream(
      fn seed -> trigger_with_seed(seed, contract_address) end,
      max_concurrency: System.schedulers_online(),
      timeout: :infinity
    )
    |> Enum.map(fn
      {:ok, result} ->
        result

      {:exit, reason} ->
        Logger.error("Trigger task crashed: #{inspect(reason)}")
        :error
    end)
  end

  defp trigger_with_seed(seed, contract_address) do
    tx =
      %TransactionData{}
      |> TransactionData.add_recipient(contract_address, "inc", %{"value" => 1})
      |> Transaction.build(:transfer, seed)

    case SmartContract.trigger(tx, contract_address) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Trigger failed with reason: #{inspect(reason)}")
        :error
    end
  end

  defp evaluate_results(results, genesis_address) do
    if Enum.any?(results, &(&1 == :error)) do
      :error
    else
      SmartContract.await_no_more_calls(genesis_address)

      case Api.get_unspent_outputs(genesis_address) do
        [%{"state" => %{"data" => %{"counter" => @nb_transactions}}} | _] ->
          Logger.info("Smart contract 'counter' incremented successfully.")

        [%{"state" => %{"state" => %{"counter" => count}}} | _] ->
          Logger.error("Unexpected counter value: #{count} (expected #{@nb_transactions})")

        other ->
          Logger.error("Unexpected contract result: #{inspect(other)}")
      end
    end
  end
end
