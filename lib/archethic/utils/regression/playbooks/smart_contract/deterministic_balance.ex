defmodule Archethic.Utils.Regression.Playbook.SmartContract.DeterministicBalance do
  @moduledoc """
  This contract is triggered by transactions.
  It logs each balance update for every transaction received.
  """

  alias ArchethicClient.TransactionData
  alias ArchethicClient.TransactionData.Recipient
  alias ArchethicClient.TransactionData.Ledger
  alias ArchethicClient.TransactionData.Ledger.UCOLedger
  alias ArchethicClient.TransactionData.Ledger.UCOLedger.Transfer, as: UCOTransfer
  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.Regression.Playbook.SmartContract

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

    execute_triggers(triggers_seeds, contract_address)

    verify_contract_balance(contract_address)
  end

  defp generate_trigger_seeds(n),
    do: Enum.map(1..n, fn _ -> SmartContract.random_seed() end)

  defp prepare_initial_funds(seeds, contract_seed, amount) do
    Enum.reduce(seeds, %{contract_seed => amount}, fn seed, acc ->
      Map.put(acc, seed, amount)
    end)
  end

  defp deploy_contract(contract_seed, storage_nonce_pubkey) do
    contract = SmartContract.read_wasm_contract(@wasm_binary, @wasm_manifest)

    %TransactionData{}
    |> TransactionData.set_contract(contract)
    |> TransactionData.set_content(Integer.to_string(@initial_seed_balance))
    |> SmartContract.deploy(contract_seed, storage_nonce_pubkey)
  end

  defp execute_triggers(seeds, contract_address) do
    seeds
    |> Enum.with_index(1)
    |> Enum.map(fn {seed, i} ->
      Task.async(fn -> trigger_contract(i, seed, contract_address) end)
    end)
    |> Task.await_many(:infinity)
  end

  defp trigger_contract(index, seed, contract_address) do
    if is_nil(seed) do
      Logger.error("Trigger failed: Missing seed at index #{index - 1}")
      :error
    else
      trigger_with_seed(seed, contract_address)
    end
  end

  defp trigger_with_seed(seed, contract_address) do
    ledger = %Ledger{
      uco: %UCOLedger{
        transfers: [%UCOTransfer{to: contract_address, amount: Archethic.Utils.to_bigint(10)}]
      }
    }

    SmartContract.trigger(seed, contract_address,
      opts: [ledger: ledger],
      recipients: [
        %Recipient{action: "processTransaction", address: contract_address, args: %{}}
      ]
    )
    |> case do
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
    505.0 - @cost_per_transaction +
      (@nb_transactions - 1) * (@initial_seed_balance - @cost_per_transaction)
  end
end
