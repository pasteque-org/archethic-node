defmodule Archethic.UTXO.Loader do
  @moduledoc false

  use GenServer
  @vsn 1

  alias Archethic.UTXO
  alias Archethic.UTXO.DBLedger
  alias Archethic.UTXO.LoaderSupervisor
  alias Archethic.UTXO.MemoryLedger

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  def start_link(arg \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, arg, opts)
  end

  @doc """
  Ingest a new UTXO as input to the chain
  """
  @spec add_utxo(UnspentOutput.t(), binary()) :: :ok
  def add_utxo(utxo = %UnspentOutput{}, genesis_address) do
    genesis_address
    |> via_tuple()
    |> GenServer.call({:add_utxo, utxo, genesis_address}, :infinity)
  end

  @doc """
  Ingest a list of UTXO at once
  """
  @spec add_utxos(list(UnspentOutput.t()), binary()) :: :ok
  def add_utxos(utxos, genesis_address) do
    genesis_address
    |> via_tuple()
    |> GenServer.call({:add_utxos, utxos, genesis_address}, :infinity)
  end

  @doc """
  Ingest the transaction to consumed inputs and allocate the new unspent outputs
  """
  @spec consume_inputs(tx :: Transaction.t()) :: :ok
  def consume_inputs(%Transaction{
        validation_stamp: %ValidationStamp{
          ledger_operations: %LedgerOperations{consumed_inputs: [], unspent_outputs: []}
        }
      }),
      do: :ok

  def consume_inputs(
        tx = %Transaction{validation_stamp: %ValidationStamp{genesis_address: genesis_address}}
      ) do
    genesis_address
    |> via_tuple()
    |> GenServer.call({:consume_inputs, tx}, :infinity)
  end

  defp via_tuple(genesis_address) do
    {:via, PartitionSupervisor, {LoaderSupervisor, genesis_address}}
  end

  def init(_) do
    {:ok, %{}}
  end

  def handle_call(
        {:add_utxo, utxo = %UnspentOutput{}, genesis_address},
        _,
        state
      ) do
    DBLedger.append(genesis_address, utxo)
    MemoryLedger.add_chain_utxo(genesis_address, utxo)
    {:reply, :ok, state}
  end

  def handle_call({:add_utxos, utxos, genesis_address}, _, state) do
    DBLedger.append_list(genesis_address, utxos)
    Enum.each(utxos, &MemoryLedger.add_chain_utxo(genesis_address, &1))
    {:reply, :ok, state}
  end

  def handle_call(
        {:consume_inputs,
         %Transaction{
           address: transaction_address,
           validation_stamp:
             stamp = %ValidationStamp{
               ledger_operations: %LedgerOperations{consumed_inputs: consumed_inputs},
               genesis_address: genesis_address
             }
         }},
        _,
        state
      ) do
    transaction_unspent_outputs = stamp_unspent_outputs(stamp, transaction_address)

    new_unspent_outputs =
      genesis_address
      |> UTXO.stream_unspent_outputs()
      |> Stream.reject(&Enum.member?(consumed_inputs, &1))
      |> Stream.concat(transaction_unspent_outputs)
      |> Enum.uniq()

    # We compact all the unspent outputs into new ones, cleaning the previous unspent outputs
    DBLedger.flush(genesis_address, new_unspent_outputs)

    # We remove the consumed inputs from the memory ledger
    MemoryLedger.remove_consumed_inputs(genesis_address, consumed_inputs)

    # We try to re-insert the new unspent outputs into memory
    Enum.each(transaction_unspent_outputs, &MemoryLedger.add_chain_utxo(genesis_address, &1))

    {:reply, :ok, state}
  end

  defp stamp_unspent_outputs(
         %ValidationStamp{ledger_operations: %LedgerOperations{unspent_outputs: unspent_outputs}},
         transaction_address
       ) do
    Enum.filter(unspent_outputs, fn
      %UnspentOutput{from: ^transaction_address} -> true
      _ -> false
    end)
  end
end
