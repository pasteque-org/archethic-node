defmodule Archethic.OracleChain.MemTableLoader do
  @moduledoc false

  use GenServer

  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.OracleChain.MemTable
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  require Logger

  @vsn 1

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    last_summary_timestamp =
      :oracle_summary
      |> TransactionChain.list_transactions_by_type([
        :address,
        :type,
        data: [:content],
        validation_stamp: [:timestamp]
      ])
      |> Enum.reduce(
        nil,
        fn %Transaction{
             validation_stamp: %ValidationStamp{timestamp: last_summary_timestamp}
           } = tx,
           _acc ->
          load_transaction(tx, true)
          last_summary_timestamp
        end
      )

    load_last_oracle_chain(last_summary_timestamp)

    {:ok, []}
  end

  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(tx, from_db? \\ false)

  def load_transaction(
        %Transaction{
          address: address,
          type: :oracle,
          data: %TransactionData{content: content},
          validation_stamp: %ValidationStamp{timestamp: timestamp}
        },
        from_db?
      ) do
    Logger.info("Load transaction into oracle chain mem table",
      transaction_address: Base.encode16(address),
      transaction_type: :oracle
    )

    content
    |> JSON.decode!()
    |> tap(fn data ->
      if !from_db? do
        Absinthe.Subscription.publish(
          ArchethicWeb.Endpoint,
          %{
            services: data,
            timestamp: timestamp
          },
          oracle_update: "oracle-topic"
        )
      end
    end)
    |> Enum.each(fn {service, data} ->
      MemTable.add_oracle_data(service, data, timestamp)
    end)
  end

  def load_transaction(
        %Transaction{
          address: address,
          type: :oracle_summary,
          data: %TransactionData{content: content}
        },
        _from_db
      ) do
    Logger.info("Load transaction into oracle chain mem table",
      transaction_address: Base.encode16(address),
      transaction_type: :oracle_summary
    )

    content
    |> JSON.decode!()
    |> Enum.each(fn {timestamp, aggregated_data} ->
      Enum.each(aggregated_data, fn {service, data} ->
        {timestamp, _} = Integer.parse(timestamp)
        MemTable.add_oracle_data(service, data, DateTime.from_unix!(timestamp))
      end)
    end)
  end

  defp load_last_oracle_chain(nil), do: :ok

  defp load_last_oracle_chain(last_summary_timestamp) do
    last_summary_timestamp
    |> OracleChain.next_summary_date()
    |> Crypto.derive_oracle_address(0)
    |> TransactionChain.get_last_address()
    |> elem(0)
    |> TransactionChain.get([
      :address,
      :type,
      data: [:content],
      validation_stamp: [:timestamp]
    ])
    |> Enum.each(&load_transaction(&1, true))
  end
end
