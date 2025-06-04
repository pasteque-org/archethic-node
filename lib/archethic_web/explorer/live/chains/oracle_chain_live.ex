defmodule ArchethicWeb.Explorer.OracleChainLive do
  @moduledoc false

  use ArchethicWeb.Explorer, :live_view

  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.PubSub
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias ArchethicWeb.Explorer.Components.TransactionsList

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction_by_type(:oracle)
      PubSub.register_to_new_transaction_by_type(:oracle_summary)
    end

    next_summary_date = OracleChain.next_summary_date(DateTime.utc_now())

    uco_prices = OracleChain.get_uco_price(DateTime.utc_now())

    oracle_dates =
      case Enum.to_list(get_oracle_dates()) do
        [] ->
          [next_summary_date]

        dates ->
          [next_summary_date | dates]
      end

    new_assign =
      socket
      |> assign(:last_oracle_data, %{uco: uco_prices})
      |> assign(:dates, oracle_dates)
      |> assign(:current_date_page, 1)
      |> assign(:transactions, list_transactions_by_date(next_summary_date))
      |> assign(:uco_price_now, OracleChain.get_uco_price(DateTime.utc_now()))

    {:ok, new_assign}
  end

  def handle_params(%{"page" => page}, _uri, %{assigns: %{dates: dates}} = socket) do
    case Integer.parse(page) do
      {number, ""} when number > 0 ->
        if number > length(dates) do
          {:noreply,
           push_navigate(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => 1}))}
        else
          transactions =
            dates
            |> Enum.at(number - 1)
            |> list_transactions_by_date()

          new_assign =
            socket
            |> assign(:current_date_page, number)
            |> assign(:transactions, transactions)

          {:noreply, new_assign}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_params(%{}, _, socket) do
    {:noreply, socket}
  end

  def handle_event("goto", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  def handle_info(
        {:new_transaction, address, :oracle, timestamp},
        %{assigns: %{current_date_page: current_page} = assigns} = socket
      ) do
    uco_prices = OracleChain.get_uco_price(timestamp)

    new_assign = assign(socket, :last_oracle_data, %{uco: uco_prices})

    if current_page == 1 do
      # Only update the transaction listed when you are on the first page
      new_assign =
        if Map.get(assigns, :summary_passed?) do
          new_assign
          |> assign(:transactions, [%{address: address, type: :oracle, timestamp: timestamp}])
          |> assign(:summary_passed?, false)
        else
          update(
            new_assign,
            :transactions,
            &[%{address: address, type: :oracle, timestamp: timestamp} | &1]
          )
        end

      {:noreply, new_assign}
    else
      {:noreply, new_assign}
    end
  end

  def handle_info(
        {:new_transaction, address, :oracle_summary, timestamp},
        %{assigns: %{current_date_page: current_page}} = socket
      ) do
    if current_page == 1 do
      # Only update the oracle summary when you are on the first page
      new_assign =
        socket
        |> update(:dates, &[OracleChain.next_summary_date(timestamp) | &1])
        |> update(
          :transactions,
          &[
            %{address: address, type: :oracle_summary, timestamp: timestamp} | &1
          ]
        )
        |> assign(:summary_passed?, true)

      {:noreply, new_assign}
    else
      {:noreply, socket}
    end
  end

  defp get_oracle_dates do
    %Node{enrollment_date: enrollment_date} =
      P2P.list_nodes() |> Enum.sort_by(& &1.enrollment_date, {:asc, DateTime}) |> Enum.at(0)

    enrollment_date
    |> OracleChain.summary_dates()
    |> Enum.sort({:desc, DateTime})
  end

  defp list_transactions_by_date(%DateTime{} = date) do
    date
    |> Crypto.derive_oracle_address(0)
    |> TransactionChain.get([
      :address,
      :type,
      validation_stamp: [:genesis_address, :timestamp, ledger_operations: [:fee]]
    ])
    |> Enum.map(fn %Transaction{
                     address: address,
                     type: type,
                     validation_stamp: %ValidationStamp{
                       genesis_address: genesis_address,
                       timestamp: timestamp,
                       ledger_operations: %LedgerOperations{fee: fee}
                     }
                   } ->
      %{
        address: address,
        type: type,
        timestamp: timestamp,
        fee: fee,
        genesis_address: genesis_address
      }
    end)
    |> Enum.reverse()
  end

  defp list_transactions_by_date(nil), do: []
end
