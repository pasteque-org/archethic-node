defmodule Archethic.Utils.Regression.Playbook.SmartContract.Throw do
  @moduledoc false

  alias ArchethicClient.Transaction
  alias ArchethicClient.TransactionData
  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.Regression.Playbook.SmartContract

  @wasm_binary "priv/regression/hello_world/contract.wasm"
  @wasm_manifest "priv/regression/hello_world/manifest.json"

  require Logger

  def play(storage_nonce_pubkey) do
    Logger.info("============== CONTRACT: THROW ==============")
    contract_seed = SmartContract.random_seed()
    trigger_seed = SmartContract.random_seed()

    Api.send_funds_to_seeds(%{contract_seed => 10, trigger_seed => 10})

    contract = SmartContract.read_wasm_contract(@wasm_binary, @wasm_manifest)

    contract_address =
      %TransactionData{}
      |> TransactionData.set_contract(contract)
      |> SmartContract.deploy(contract_seed, storage_nonce_pubkey)

    with :ok <- trigger_valid_tx(trigger_seed, contract_address),
         :ok <- trigger_invalid_tx(trigger_seed, contract_address),
         :ok <- call_valid_function(contract_address) do
      call_invalid_function(contract_address)
    end
  end

  defp trigger_valid_tx(trigger_seed, contract_address) do
    tx =
      %TransactionData{}
      |> TransactionData.add_recipient(contract_address, "processTransaction", %{
        "param" => "Hello"
      })
      |> Transaction.build(:transfer, trigger_seed)

    case SmartContract.trigger(tx, contract_address, wait: true) do
      {:ok, _} ->
        last_tx = Api.get_last_transaction(contract_address)

        case last_tx["data"]["content"] do
          "World" ->
            Logger.info("Smart contract 'throw' content has been updated successfully")
            :ok

          content ->
            Logger.error("Smart contract 'throw' content is not as expected: #{content}")

            :error
        end

      {:error, _} ->
        Logger.error("Trigger tx on smart contract throw has failed")
        :error
    end
  end

  defp trigger_invalid_tx(trigger_seed, contract_address) do
    tx =
      %TransactionData{}
      |> TransactionData.add_recipient(contract_address, "processTransaction", %{
        "param" => "invalid"
      })
      |> Transaction.build(:transfer, trigger_seed)

    case SmartContract.trigger(tx, contract_address) do
      {:ok, _tx_address} ->
        Logger.error(
          "Trigger tx on smart contract throw succeeded while it should be refused by condition"
        )

        :error

      {:error, :timeout} ->
        Logger.error("Trigger tx on smart contract throw timed out")
        :error

      {:error, error} ->
        if trigger_invalid_tx_expected_validation_error?(error) do
          Logger.info("Trigger tx on smart contract throw has been refused as expected")
          :ok
        else
          Logger.error(
            "Trigger tx on smart contract throw has been refused with invalid reason: #{inspect(error)}"
          )

          :error
        end
    end
  end

  defp trigger_invalid_tx_expected_validation_error?(%ArchethicClient.ValidationError{
         code: -31003,
         message: "Invalid recipients execution",
         data: %{"message" => msg}
       })
       when is_binary(msg),
       do: String.contains?(msg, "Expected \"Hello\"")

  defp trigger_invalid_tx_expected_validation_error?(_), do: false

  defp call_valid_function(contract_address) do
    case ArchethicClient.call_contract_function(
           Base.encode16(contract_address),
           "getPublicValue",
           %{"param" => "Hello"}
         ) do
      {:ok, "World"} ->
        Logger.info("Call valid function returned expected result")
        :ok

      {_, res} ->
        Logger.error("Call valid function returned unexpected response: #{inspect(res)}")
        :error
    end
  end

  defp call_invalid_function(contract_address) do
    case ArchethicClient.call_contract_function(
           Base.encode16(contract_address),
           "getPublicValue",
           %{"param" => "Holla"}
         ) do
      {:error, error} ->
        if call_invalid_function_expected_validation_error?(error) do
          Logger.info("Call invalid function returned expected result")
          :ok
        else
          Logger.error("Call invalid function returned unexpected error: #{inspect(error)}")
          :error
        end

      {:ok, res} ->
        Logger.error("Call invalid function unexpectedly succeeded with result: #{inspect(res)}")
        :error
    end
  end

  defp call_invalid_function_expected_validation_error?(%ArchethicClient.RPCError{
         code: 202,
         message: "There was an error while executing the function",
         data: data
       }) do
    String.contains?(data, "Expected \\\"Hello\\\"")
  end

  defp call_invalid_function_expected_validation_error?(_), do: false
end
