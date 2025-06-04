defmodule Archethic.Utils.Regression.Playbook.SmartContract.DeterministicBalance do
  @moduledoc """
  This contract is triggered by transactions.
  It logs each balance update for every transaction received.
  """

  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.Regression.Playbook.SmartContract
  alias ArchethicClient.Crypto
  alias ArchethicClient.Transaction
  alias ArchethicClient.TransactionData

  require Logger

  @wasm_binary "priv/regression/deterministic_balance/contract.wasm"
  @wasm_manifest "priv/regression/deterministic_balance/manifest.json"
  @nb_transactions 100
  @initial_seed_balance 505
  @cost_per_transaction 5

  def play(storage_nonce_pubkey) do
    Logger.info("============== CONTRACT: DETERMINISTIC BALANCE =============")

    contract_seed = SmartContract.random_seed()
    triggers_seeds = generate_trigger_seeds(@nb_transactions)

    initial_funds = prepare_initial_funds(triggers_seeds, contract_seed, @initial_seed_balance)
    Api.send_funds_to_seeds(initial_funds)

    contract_address = deploy_contract(contract_seed, storage_nonce_pubkey)
    genesis_address = Crypto.derive_address(contract_seed, 0)

    execute_triggers(triggers_seeds, contract_address, genesis_address)

    verify_contract_balance(contract_address)
  end

  defp generate_trigger_seeds(n), do: Enum.map(1..n, fn _ -> SmartContract.random_seed() end)

  defp prepare_initial_funds(seeds, contract_seed, amount) do
    Enum.reduce(seeds, %{contract_seed => amount}, fn seed, acc ->
      Map.put(acc, seed, 15)
    end)
  end

  defp deploy_contract(contract_seed, storage_nonce_pubkey) do
    contract = SmartContract.read_wasm_contract(@wasm_binary, @wasm_manifest)

    %TransactionData{}
    |> TransactionData.set_contract(contract)
    |> TransactionData.set_content(Integer.to_string(@initial_seed_balance))
    |> SmartContract.deploy(contract_seed, storage_nonce_pubkey)
  end

  defp execute_triggers(seeds, contract_address, genesis_address) do
    seeds
    |> Task.async_stream(
      fn seed -> trigger_with_seed(seed, contract_address) end,
      max_concurrency: length(seeds),
      timeout: :infinity
    )
    |> Stream.run()

    SmartContract.await_no_more_calls(genesis_address)
  end

  defp trigger_with_seed(seed, contract_address) do
    tx =
      %TransactionData{}
      |> TransactionData.add_recipient(contract_address, "processTransaction")
      |> Transaction.build(:transfer, seed)

    case SmartContract.trigger(tx, contract_address) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Trigger failed with reason: #{inspect(reason)}")
        :error
    end
  end

  defp verify_contract_balance(contract_address) do
    case Api.get_last_transaction(contract_address) do
      %{"data" => %{"content" => balance_str}} ->
        logged_balance = balance_str |> Float.parse() |> elem(0) |> Float.ceil()
        expected = compute_expected_balance()

        if logged_balance == expected do
          Logger.info("Smart contract 'deterministic balance' has been updated successfully")
          :ok
        else
          Logger.error("Balance mismatch: got #{logged_balance}, expected #{expected}")
          :ok
        end

      other ->
        Logger.error("Unexpected contract result: #{inspect(other)}")
        :error
    end
  end

  defp compute_expected_balance do
    @initial_seed_balance - @cost_per_transaction -
      (@nb_transactions - 1) * (10 - @cost_per_transaction)
  end
end
