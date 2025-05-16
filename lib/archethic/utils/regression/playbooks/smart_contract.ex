defmodule Archethic.Utils.Regression.Playbook.SmartContract do
  @moduledoc """
  Play and verify smart contracts.
  """

  use Archethic.Utils.Regression.Playbook
  use Retry

  alias ArchethicClient.Crypto
  alias ArchethicClient.TransactionData
  alias ArchethicClient.Transaction
  alias ArchethicClient.TransactionData.Contract

  alias Archethic.Utils.Regression.Api

  alias __MODULE__.Counter
  alias __MODULE__.Throw
  alias __MODULE__.DeterministicBalance

  require Logger

  def play!(nodes, opts) do
    # TODO: add a debug opts (default: false)
    #       false: no logs + parallel execution
    #       true: logs + sequential execution

    Logger.info("Play smart contract transactions on #{inspect(nodes)} with #{inspect(opts)}")

    storage_nonce_pubkey = Api.get_storage_nonce_public_key()

    res = [
      {"Counter", Counter.play(storage_nonce_pubkey)},
      {"Throw", Throw.play(storage_nonce_pubkey)},
      {"DeterministicBalance", DeterministicBalance.play(storage_nonce_pubkey)}
    ]

    Enum.each(res, fn
      {name, :error} -> raise "#{name} failed"
      _ -> :ok
    end)

    :ok
  end

  @doc """
  Deploy a smart contract
  """
  @spec deploy(data :: TransactionData.t(), seed :: String.t(), storage_nonce_pubkey :: binary()) ::
          binary()
  def deploy(data, seed, storage_nonce_pubkey) do
    Logger.debug("DEPLOY: Deploying contract")

    # add the ownerships required for smart contract
    tx =
      data
      |> TransactionData.add_ownership(seed, [storage_nonce_pubkey])
      |> Transaction.build(:contract, seed)

    case ArchethicClient.send_transaction(tx) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Deploy contract failed: #{inspect(reason)}"
    end

    Logger.debug("DEPLOY: Deployed at #{Base.encode16(tx.address)}")

    tx.address
  end

  @doc """
  Loads a Wasm smart contract from files
  """
  @spec read_wasm_contract(
          bytecode_file :: binary(),
          manifest_file :: binary()
        ) :: Contract.t()
  def read_wasm_contract(bytecode_file, manifest_file) do
    %Contract{
      bytecode: File.read!(bytecode_file) |> :zlib.zip(),
      manifest: File.read!(manifest_file) |> Jason.decode!()
    }
  end

  @doc """
  Trigger a smart contract by sending a transaction from given seed
  By passing the [wait: true] flag, it will block until the contract produces a new transaction
  """
  @spec trigger(
          tx :: Transaction.t(),
          contract_address :: Crypto.address(),
          opts :: Keyword.t()
        ) :: {:ok, tx_address :: Crypto.address()} | {:error, reason :: Exception.t() | :timeout}
  def trigger(tx, contract_address, opts \\ []) do
    Logger.debug("TRIGGER: Sending trigger transaction")
    wait? = Keyword.get(opts, :wait, false)

    last_contract_address =
      if wait? do
        contract_address |> Api.get_last_transaction() |> Map.get("address") |> Base.decode16!()
      else
        nil
      end

    case ArchethicClient.send_transaction(tx) do
      :ok ->
        if Keyword.get(opts, :wait, false) do
          # wait until the contract produces a new transaction
          case wait_until_new_transaction(last_contract_address) do
            :ok -> {:ok, tx.address}
            :error -> {:error, :timeout}
          end
        else
          {:ok, tx.address}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def random_seed() do
    :crypto.strong_rand_bytes(32)
  end

  defp wait_until_new_transaction(address) do
    address_hex = Base.encode16(address)

    # retry every 500ms until 20 retries
    retry with: constant_backoff(500) |> Stream.take(20) do
      %{"address" => last_address_hex} = Api.get_last_transaction(address)

      if last_address_hex == address_hex do
        :error
      else
        :ok
      end
    after
      _ ->
        Logger.debug("TRIGGER: contract produced a new transaction")
        :ok
    else
      _ ->
        Logger.error("TRIGGER: TIMEOUT: contract did not produce a new transaction in time")
        :error
    end
  end

  def await_no_more_calls(contract_address) do
    call_utxos =
      contract_address
      |> Api.get_unspent_outputs()
      |> Enum.filter(&(Map.get(&1, "type") == "call"))

    case call_utxos do
      [] ->
        :ok

      calls ->
        Logger.debug(
          "Remaining calls #{length(calls)} on contract #{Base.encode16(contract_address)}"
        )

        Process.sleep(200)
        await_no_more_calls(contract_address)
    end
  end
end
