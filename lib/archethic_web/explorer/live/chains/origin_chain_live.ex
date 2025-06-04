defmodule ArchethicWeb.Explorer.OriginChainLive do
  @moduledoc false
  use ArchethicWeb.Explorer, :live_view

  alias Archethic.OracleChain
  alias Archethic.PubSub
  alias Archethic.SharedSecrets
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.Utils
  alias ArchethicWeb.Explorer.Components.TransactionsList
  alias ArchethicWeb.WebUtils
  alias Phoenix.LiveView

  @display_limit 10
  @txn_type :origin

  @spec mount(_parameters :: map(), _session :: map(), socket :: LiveView.Socket.t()) ::
          {:ok, LiveView.Socket.t()}
  def mount(_parameters, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction_by_type(@txn_type)
    end

    tx_count = TransactionChain.count_transactions_by_type(@txn_type)

    socket =
      socket
      |> assign(:tx_count, tx_count)
      |> assign(:nb_pages, WebUtils.total_pages(tx_count))
      |> assign(:current_page, 1)
      |> assign(:transactions, transactions_from_page(1, tx_count))
      |> assign(:uco_price_now, OracleChain.get_uco_price(DateTime.utc_now()))

    {:ok, socket}
  end

  @spec handle_params(_params :: map(), _uri :: binary(), socket :: LiveView.Socket.t()) ::
          {:noreply, LiveView.Socket.t()}
  def handle_params(
        %{"page" => page} = _params,
        _uri,
        %{assigns: %{nb_pages: nb_pages, tx_count: tx_count}} = socket
      ) do
    case Integer.parse(page) do
      {number, ""} when number < 1 and number > nb_pages ->
        {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => 1}))}

      {number, ""} when number >= 1 and number <= nb_pages ->
        socket =
          socket
          |> assign(:current_page, number)
          |> assign(:transactions, transactions_from_page(number, tx_count))

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  @spec handle_event(_event :: binary(), _params :: map(), socket :: LiveView.Socket.t()) ::
          {:noreply, LiveView.Socket.t()}
  def handle_event("prev_page" = _event, %{"page" => page} = _params, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_event("next_page" = _event, %{"page" => page} = _params, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  @spec handle_info(
          _msg ::
            {:new_transaction, address :: binary(), _type :: :origin, _timestamp :: DateTime.t()},
          socket :: LiveView.Socket.t()
        ) ::
          {:noreply, LiveView.Socket.t()}
  def handle_info(
        {:new_transaction, address, :origin, _timestamp} = _msg,
        %{assigns: %{current_page: current_page, tx_count: total_tx_count}} = socket
      ) do
    updated_socket =
      case current_page do
        1 ->
          socket
          |> assign(:tx_count, total_tx_count + 1)
          |> assign(:nb_pages, WebUtils.total_pages(total_tx_count + 1))
          |> assign(:current_page, 1)
          |> update(:transactions, fn tx_list ->
            Enum.take([display_data(address) | tx_list], @display_limit)
          end)

        _ ->
          socket
      end

    {:noreply, updated_socket}
  end

  @spec transactions_from_page(current_page :: non_neg_integer(), tx_count :: non_neg_integer()) ::
          list(map())
  def transactions_from_page(current_page, tx_count) do
    nb_drops = tx_count - current_page * @display_limit

    {nb_drops, display_limit} =
      if nb_drops < 0, do: {0, @display_limit + nb_drops}, else: {nb_drops, @display_limit}

    :origin
    |> TransactionChain.list_addresses_by_type()
    |> Stream.drop(nb_drops)
    |> Stream.take(display_limit)
    |> Stream.map(fn
      nil ->
        []

      address ->
        display_data(address)
    end)
    |> Enum.reverse()
  end

  defp display_data(address) do
    with {:ok,
          %Transaction{
            data: %TransactionData{content: content},
            validation_stamp: %ValidationStamp{
              timestamp: timestamp,
              genesis_address: genesis_address
            }
          }} <-
           TransactionChain.get_transaction(address,
             data: [:content],
             validation_stamp: [:timestamp, :genesis_address]
           ),
         {pb_key, _} <- Utils.deserialize_public_key(content) do
      family_id = SharedSecrets.origin_family_from_public_key(pb_key)

      %{
        address: address,
        type: @txn_type,
        timestamp: timestamp,
        family_of_origin: family_id,
        genesis_address: genesis_address
      }
    else
      _ -> []
    end
  end
end
