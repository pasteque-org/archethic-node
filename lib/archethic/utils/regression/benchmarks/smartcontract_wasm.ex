defmodule Archethic.Utils.Regression.Benchmark.WasmSmartContractTrigger do
  @moduledoc """
  Benchmark for triggering WASM-based smart contracts.

  This benchmark measures the performance of triggering a pre-deployed WASM smart contract.
  It involves:
  1. Setting up seeds and funding them.
  2. Deploying a WASM smart contract (a counter).
  3. Repeatedly triggering an action (`inc`) on the contract from different seeds.
  4. Awaiting confirmation that the contract call has been processed using `SmartContractHelper`.

  The primary metric is the rate at which these trigger transactions can be processed.
  """

  @behaviour Archethic.Utils.Regression.Benchmark

  alias Archethic.Utils.Regression.Api
  alias Archethic.Utils.Regression.Benchmark.SeedHolder
  alias Archethic.Utils.Regression.Playbook.SmartContract
  alias ArchethicClient.Crypto
  alias ArchethicClient.Transaction
  alias ArchethicClient.TransactionData

  require Logger

  @wasm_binary "priv/regression/counter/contract.wasm"
  @wasm_manifest "priv/regression/counter/manifest.json"

  @doc """
  Sets up and runs the WASM smart contract trigger benchmark.
  """
  def plan(_node, _opts) do
    Logger.info("Starting Benchmark: Wasm SC Counter")

    {:ok, pid} =
      SeedHolder.start_link(seeds: Enum.map(0..25, fn _ -> :crypto.strong_rand_bytes(32) end))

    amount = 10

    contract_seed = :crypto.strong_rand_bytes(32)

    genesis_address = Crypto.derive_address(contract_seed, 0)

    [contract_seed | SeedHolder.get_seeds(pid)]
    |> Map.new(fn seed -> {seed, amount} end)
    |> Api.send_funds_to_seeds()

    contract = SmartContract.read_wasm_contract(@wasm_binary, @wasm_manifest)

    contract_address =
      %TransactionData{}
      |> TransactionData.set_contract(contract)
      |> SmartContract.deploy(contract_seed, Api.get_storage_nonce_public_key())

    {
      %{
        "Wasm SC trigger" => fn ->
          {trigger_seed, _} = SeedHolder.pop_seed(pid)

          tx =
            %TransactionData{}
            |> TransactionData.add_recipient(contract_address, "inc", %{"value" => 1})
            |> Transaction.build(:transfer, trigger_seed)

          {:ok, trigger_address} = SmartContract.trigger(tx, contract_address)

          await_no_more_calls(genesis_address, trigger_address)
        end
      },
      []
    }
  end

  # Waits until a contract has no more pending 'call' UTXOs from a specific trigger.
  # This function polls the `contract_address` via the provided `endpoint` every 200ms.
  # It checks for unspent outputs (UTXOs) of type "call" that originate from the
  # `trigger_address`. The function returns `:ok` once no such UTXOs are found,
  # indicating that previous contract calls from the trigger have likely been processed.
  # A debug message is logged during the waiting period.
  ## Parameters
  # `contract_address`: The binary address of the smart contract to monitor.
  # `trigger_address`: The binary address of the transaction/wallet that triggered the calls.
  defp await_no_more_calls(contract_address, trigger_address) do
    call_utxos =
      contract_address
      |> Api.get_unspent_outputs()
      |> Enum.filter(
        &(Map.get(&1, "type") == "call" && Map.get(&1, "from") == Base.encode16(trigger_address))
      )

    case call_utxos do
      [] ->
        :ok

      _ ->
        Logger.debug(
          "Waiting for contract call from #{Base.encode16(trigger_address)} on contract #{Base.encode16(contract_address)}"
        )

        Process.sleep(200)
        await_no_more_calls(contract_address, trigger_address)
    end
  end
end
