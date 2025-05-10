defmodule Archethic.UTXO do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.UTXO.DBLedger
  alias Archethic.UTXO.Loader
  alias Archethic.UTXO.MemoryLedger

  require Logger

  @type balance :: %{
          uco: amount :: pos_integer(),
          token: %{
            {address :: binary(), token_id :: non_neg_integer()} => amount :: pos_integer()
          }
        }

  @type load_opts :: [
          resolved_addresses: %{(address :: binary()) => genesis :: binary()},
          download_nodes: list(Node.t()),
          skip_consume_inputs?: boolean(),
          skip_verify_consumed?: boolean()
        ]

  @spec load_transaction(tx :: Transaction.t(), opts :: load_opts()) :: :ok
  def load_transaction(tx, opts \\ []) do
    download_nodes = Keyword.get(opts, :download_nodes, P2P.authorized_and_available_nodes())
    authorized_nodes = [P2P.get_node_info() | download_nodes] |> P2P.distinct_nodes()
    skip_consume_inputs? = Keyword.get(opts, :skip_consume_inputs?, false)
    skip_verify_consumed? = Keyword.get(opts, :skip_verify_consumed?, false)

    node_public_key = Crypto.first_node_public_key()

    # Ingest all the movements and recipients to fill up the UTXO list
    tx
    |> get_unspent_outputs_to_ingest(node_public_key, authorized_nodes, skip_verify_consumed?)
    |> Enum.each(fn {to, utxos} -> Loader.add_utxos(utxos, to) end)

    # Consume the transaction to update the unspent outputs from the consumed inputs
    unless skip_consume_inputs?, do: Loader.consume_inputs(tx)

    Logger.info("Loaded into in memory UTXO tables",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )
  end

  defp get_unspent_outputs_to_ingest(
         %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{transaction_movements: []},
             recipients: []
           }
         },
         _,
         _,
         _
       ),
       do: %{}

  defp get_unspent_outputs_to_ingest(
         %Transaction{
           address: address,
           validation_stamp: %ValidationStamp{
             timestamp: timestamp,
             ledger_operations: %LedgerOperations{transaction_movements: transaction_movements},
             recipients: recipients
           }
         },
         node_public_key,
         authorized_nodes,
         skip_verify_consumed?
       ) do
    utxos_by_genesis =
      transaction_movements
      |> Enum.reduce(%{}, fn %TransactionMovement{to: to, amount: amount, type: type}, acc ->
        utxo = %UnspentOutput{from: address, amount: amount, timestamp: timestamp, type: type}

        with true <- Election.chain_storage_node?(to, node_public_key, authorized_nodes),
             false <- not skip_verify_consumed? and utxo_consumed?(to, utxo) do
          Map.update(acc, to, [utxo], &[utxo | &1])
        else
          _ -> acc
        end
      end)

    Enum.reduce(recipients, utxos_by_genesis, fn recipient, acc ->
      utxo = %UnspentOutput{from: address, type: :call, timestamp: timestamp}

      with true <- Election.chain_storage_node?(recipient, node_public_key, authorized_nodes),
           false <- not skip_verify_consumed? and utxo_consumed?(recipient, utxo) do
        Map.update(acc, recipient, [utxo], &[utxo | &1])
      else
        _ -> acc
      end
    end)
  end

  defp utxo_consumed?(genesis_address, utxo = %UnspentOutput{timestamp: utxo_timestamp}) do
    {_, last_timestamp} = TransactionChain.get_last_address(genesis_address)

    if DateTime.compare(last_timestamp, utxo_timestamp) == :gt do
      genesis_address
      |> TransactionChain.list_chain_addresses()
      |> Stream.filter(fn {_, timestamp} -> DateTime.compare(timestamp, utxo_timestamp) == :gt end)
      |> Stream.map(fn {address, _} -> get_tx_consumed_inputs(address) end)
      |> Enum.any?(fn
        {:ok, consumed_inputs} -> Enum.member?(consumed_inputs, utxo)
        :error -> false
      end)
    else
      false
    end
  end

  defp get_tx_consumed_inputs(address) do
    fields = [validation_stamp: [ledger_operations: [:consumed_inputs]]]

    case TransactionChain.get_transaction(address, fields) do
      {:ok,
       %Transaction{
         validation_stamp: %ValidationStamp{
           ledger_operations: %LedgerOperations{
             consumed_inputs: consumed_inputs
           }
         }
       }} ->
        {:ok, consumed_inputs}

      {:error, _} ->
        :error
    end
  end

  @doc """
  Returns the list of all the inputs which have not been consumed for the given chain's address
  """
  @spec stream_unspent_outputs(binary()) :: list(UnspentOutput.t())
  def stream_unspent_outputs(address) do
    if MemoryLedger.threshold_reached?(address),
      do: DBLedger.stream(address),
      else: MemoryLedger.get_unspent_outputs(address)
  end

  @doc """
  Returns the balance for an address using the unspent outputs

  ## Examples

      iex> [
      ...>   %UnspentOutput{from: "@Alice10", type: :UCO, amount: 100_000_000},
      ...>   %UnspentOutput{from: "@Bob5", type: {:token, "MyToken", 0}, amount: 300_000_000},
      ...>   %UnspentOutput{from: "@Charlie5", type: :call},
      ...>   %UnspentOutput{from: "@Tom5", type: :state}
      ...> ]
      ...> |> UTXO.get_balance()
      %{
        uco: 100_000_000,
        token: %{
          {"MyToken", 0} => 300_000_000
        }
      }
  """
  @spec get_balance(Enumerable.t() | list(UnspentOutput.t())) :: balance()
  def get_balance(unspent_outputs) do
    Enum.reduce(unspent_outputs, %{uco: 0, token: %{}}, fn
      %UnspentOutput{type: :UCO, amount: amount}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %UnspentOutput{type: {:token, token_address, token_id}, amount: amount}, acc ->
        update_in(acc, [:token, Access.key({token_address, token_id}, 0)], &(&1 + amount))

      _, acc ->
        acc
    end)
  end
end
