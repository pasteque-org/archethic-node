defmodule Archethic.Utils.Regression.Playbook.SmartContract.WasmCounter do
  @moduledoc """
  This contract is triggered by transactions
  It starts with content=0 and the number will increment for each transaction received
  """

  alias ArchethicClient.Crypto
  alias ArchethicClient.TransactionData
  alias Archethic.Utils.Regression.Api
  alias ArchethicClient.TransactionData.Recipient
  alias Archethic.Utils.Regression.Playbook.SmartContract

  require Logger

  def play(storage_nonce_pubkey) do
    Logger.info("============== CONTRACT: WASM COUNTER ==============")
    contract_seed = SmartContract.random_seed()
    nb_transactions = 100

    triggers_seeds = Enum.map(1..nb_transactions, fn _ -> SmartContract.random_seed() end)

    initial_funds =
      Enum.reduce(triggers_seeds, %{contract_seed => 10}, fn seed, acc ->
        Map.put(acc, seed, 10)
      end)

    Api.send_funds_to_seeds(initial_funds)

    genesis_address = Crypto.derive_address(contract_seed, 0)
    contract_address = deploy_contract(contract_seed, storage_nonce_pubkey)

    results = trigger_contracts(triggers_seeds, contract_address, nb_transactions)

    handle_results(results, genesis_address, nb_transactions)
  end

  defp deploy_contract(contract_seed, storage_nonce_pubkey) do
    SmartContract.deploy(
      contract_seed,
      TransactionData.set_contract(
        %TransactionData{},
        SmartContract.read_wasm_contract(
          "lib/archethic/utils/regression/playbooks/smart_contract/wasm_counter.wasm",
          "lib/archethic/utils/regression/playbooks/smart_contract/wasm_counter.manifest.json"
        )
      ),
      storage_nonce_pubkey
    )
  end

  defp trigger_contracts(triggers_seeds, contract_address, nb_transactions) do
    Enum.map(1..nb_transactions, fn i ->
      Task.async(fn -> trigger_contract(i, triggers_seeds, contract_address) end)
    end)
    |> Task.await_many(:infinity)
  end

  defp trigger_contract(i, triggers_seeds, contract_address) do
    seed = Enum.at(triggers_seeds, i - 1)

    case seed do
      nil ->
        Logger.error("Trigger failed: Could not get seed for index #{i - 1}")
        :error

      valid_seed ->
        trigger_with_seed(valid_seed, contract_address)
    end
  end

  defp trigger_with_seed(valid_seed, contract_address) do
    case SmartContract.trigger(valid_seed, contract_address,
           recipients: [
             %Recipient{action: "inc", address: contract_address, args: %{}}
           ]
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Trigger failed with reason: #{inspect(reason)}")
        :error
    end
  end

  defp handle_results(results, genesis_address, nb_transactions) do
    if Enum.any?(results, &(&1 == :error)) do
      :error
    else
      SmartContract.await_no_more_calls(genesis_address)

      case Api.get_unspent_outputs(genesis_address) do
        [%{"state" => %{"counter" => ^nb_transactions}} | _] ->
          Logger.info("Smart contract 'counter' content has been incremented successfully")

        [%{"state" => %{"counter" => count}} | _] ->
          Logger.error("Smart contract 'counter' content is not as expected: #{count}")

        results ->
          Logger.error("Houston, we have a problem: #{inspect(results)}")
      end
    end
  end
end
