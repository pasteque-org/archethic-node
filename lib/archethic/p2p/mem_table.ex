defmodule Archethic.P2P.MemTable do
  @moduledoc false

  @discovery_table :archethic_node_discovery
  @nodes_key_lookup_table :archethic_node_keys
  @authorized_nodes_table :archethic_authorized_nodes

  alias Archethic.DB.EmbeddedImpl.P2PView
  alias Archethic.Crypto

  alias Archethic.P2P.Node
  alias Archethic.P2P.P2PView

  alias Archethic.PubSub

  use GenServer
  @vsn 1

  require Logger

  @discovery_index_position [
    first_public_key: 1,
    last_public_key: 2,
    ip: 3,
    port: 4,
    http_port: 5,
    # geo_patch: 6,
    network_patch: 7,
    # average_availability: 8,
    enrollment_date: 9,
    transport: 10,
    reward_address: 11,
    last_address: 12,
    origin_public_key: 13,
    synced?: 14,
    last_update_date: 15,
    # available?: 16,
    availability_update: 17,
    mining_public_key: 18
  ]

  # TODO integrate p2pview to take its data into account
  # TODO remove p2pview properties from @authorized_nodes_table
  # TODO update ets tables on migration
  # TODO update ets table on MemTableLoader load
  # TODO update ets table on p2p.nodeconfig.config

  @doc """
  Initialize the memory tables for the P2P view
  """
  @spec start_link([]) :: {:ok, pid()}
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    :ets.new(@discovery_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@authorized_nodes_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@nodes_key_lookup_table, [:set, :named_table, :public, read_concurrency: true])

    Logger.info("Initialize InMemory P2P view")

    P2PView.start_link()

    {:ok, []}
  end

  @doc """
  Add a node into the P2P view.

  If a node already exists with the first public key, the P2P information will be updated.
  """
  @spec add_node(Node.t()) :: :ok
  def add_node(
        node = %Node{
          first_public_key: first_public_key,
          last_public_key: last_public_key,
          authorized?: authorized?,
          authorization_date: authorization_date
        }
      ) do
    if node_exists?(first_public_key) do
      update_p2p_discovery(node)
      Logger.info("Node update", node: Base.encode16(first_public_key))
      Logger.debug("Update info: #{inspect(node)}", node: Base.encode16(first_public_key))
    else
      insert_p2p_discovery(node)
      insert_p2p_view(node)
      Logger.info("Node joining", node: Base.encode16(first_public_key))
      Logger.debug("Node info: #{inspect(node)}", node: Base.encode16(first_public_key))
    end

    index_node_public_keys(first_public_key, last_public_key)

    if authorized? do
      authorize_node(first_public_key, authorization_date)
    end

    notify_node_update(first_public_key, DateTime.utc_now())

    :ok
  end

  defp node_exists?(public_key) do
    :ets.member(@discovery_table, public_key)
  end

  defp insert_p2p_view(%Node{
         first_public_key: first_public_key,
         geo_patch: geo_patch,
         # TODO Utiliser geo_patch_update ?
         #  geo_patch_update: geo_patch_update,
         average_availability: average_availability,
         available?: available?,
         #  availability_update: availability_update,
         enrollment_date: enrollment_date
       }) do
    P2PView.add_node(
      %P2PView{
        geo_patch: geo_patch,
        available?: available?,
        avg_availability: average_availability
      },
      enrollment_date,
      &node_index_at_timestamp(first_public_key, &1)
    )
  end

  defp insert_p2p_discovery(%Node{
         first_public_key: first_public_key,
         last_public_key: last_public_key,
         mining_public_key: mining_public_key,
         ip: ip,
         port: port,
         http_port: http_port,
         network_patch: network_patch,
         enrollment_date: enrollment_date,
         synced?: synced?,
         transport: transport,
         reward_address: reward_address,
         last_address: last_address,
         origin_public_key: origin_public_key,
         last_update_date: last_update_date,
         availability_update: availability_update
       }) do
    :ets.insert(
      @discovery_table,
      {first_public_key, last_public_key, ip, port, http_port, nil, network_patch, nil,
       enrollment_date, transport, reward_address, last_address, origin_public_key, synced?,
       last_update_date, nil, availability_update, mining_public_key}
    )
  end

  def update_geo_patch(
        first_public_key,
        geo_patch,
        geo_patch_update
      ) do
    P2PView.update_node(
      [
        geo_patch: geo_patch
      ],
      geo_patch_update,
      &node_index_at_timestamp(first_public_key, &1)
    )
  end

  # defp get_p2p_view(first_public_key, timestamp) do
  #   P2PView.get_p2p_view(timestamp, node_index_at_timestamp(first_public_key, timestamp))
  # end

  defp update_p2p_discovery(%Node{
         first_public_key: first_public_key,
         last_public_key: last_public_key,
         mining_public_key: mining_public_key,
         ip: ip,
         port: port,
         http_port: http_port,
         network_patch: network_patch,
         enrollment_date: enrollment_date,
         synced?: synced?,
         transport: transport,
         reward_address: reward_address,
         last_address: last_address,
         origin_public_key: origin_public_key,
         last_update_date: timestamp,
         availability_update: availability_update
       }) do
    changes = [
      {Keyword.fetch!(@discovery_index_position, :last_public_key), last_public_key},
      {Keyword.fetch!(@discovery_index_position, :reward_address), reward_address},
      {Keyword.fetch!(@discovery_index_position, :last_address), last_address},
      {Keyword.fetch!(@discovery_index_position, :origin_public_key), origin_public_key},
      {Keyword.fetch!(@discovery_index_position, :ip), ip},
      {Keyword.fetch!(@discovery_index_position, :port), port},
      {Keyword.fetch!(@discovery_index_position, :http_port), http_port},
      {Keyword.fetch!(@discovery_index_position, :transport), transport},
      {Keyword.fetch!(@discovery_index_position, :last_update_date), timestamp},
      {Keyword.fetch!(@discovery_index_position, :mining_public_key), mining_public_key}
    ]

    changes =
      if network_patch != nil do
        [{Keyword.fetch!(@discovery_index_position, :network_patch), network_patch} | changes]
      else
        changes
      end

    changes =
      if availability_update != nil do
        [
          {Keyword.fetch!(@discovery_index_position, :availability_update), availability_update}
          | changes
        ]
      else
        changes
      end

    changes =
      if enrollment_date != nil do
        [
          {Keyword.fetch!(@discovery_index_position, :enrollment_date), enrollment_date}
          | changes
        ]
      else
        changes
      end

    changes =
      if synced? != nil do
        [{Keyword.fetch!(@discovery_index_position, :synced?), synced?} | changes]
      else
        changes
      end

    :ets.update_element(@discovery_table, first_public_key, changes)
  end

  defp index_node_public_keys(first_public_key, last_public_key) do
    true = :ets.insert(@nodes_key_lookup_table, {last_public_key, first_public_key})
  end

  @doc """
  Retrieve the node entry by its first public key by default otherwise perform
  a lookup to retrieved it by the last key.
  """
  @spec get_node(public_key :: Crypto.key(), timestamp :: DateTime.t()) ::
          {:ok, Node.t()} | {:error, :not_found}
  def get_node(key, timestamp) do
    # IO.inspect(timestamp, label: "timestamp")

    # |> IO.inspect(label: "first_public_key"),
    with first_public_key <- get_first_node_key(key),
         [res] <- :ets.lookup(@discovery_table, first_public_key),
         {:ok, node} <- cast_node(res, timestamp),
         node <- set_node_authorization(node) do
      {:ok, node}
    else
      _ ->
        {:error, :not_found}
    end
  end

  @spec get_node!(public_key :: Crypto.key(), timestamp :: DateTime.t()) :: Node.t() | no_return()
  def get_node!(key, timestamp) do
    case get_node(key, timestamp) do
      {:ok, node} ->
        node

      {:error, :not_found} ->
        raise ArgumentError, "Node not found for key: #{Base.encode16(key)}"
    end
  end

  @doc """
  List the P2P nodes
  """
  # TODO add date en parametre. retourner tout les noeuds ou enrollment_date < date
  @spec list_nodes() :: list(Node.t())
  def list_nodes do
    :ets.foldl(
      fn entry, acc ->
        with {:ok, node} <- cast_node(entry, DateTime.utc_now()),
             node <- set_node_authorization(node) do
          [node | acc]
        else
          _ -> acc
        end
      end,
      [],
      @discovery_table
    )
  end

  @doc """
  List the authorized nodes
  """
  @spec authorized_nodes(timestamp :: DateTime.t()) :: list(Node.t())
  def authorized_nodes(timestamp) do
    :ets.foldl(
      fn {key, authorization_date}, acc ->
        with [res] <- :ets.lookup(@discovery_table, key),
             {:ok, node} <- cast_node(res, timestamp),
             node <- Node.authorize(node, authorization_date) do
          [node | acc]
        else
          _ -> acc
        end
      end,
      [],
      @authorized_nodes_table
    )
  end

  @doc """
  List the nodes which are globally available
  """
  @spec available_nodes(timestamp :: DateTime.t()) :: list(Node.t())
  def available_nodes(timestamp) do
    summary = P2PView.get_summary(timestamp)
    # |> Enum.filter(fn p2pview -> p2pView.available? == true end)
    # |> Enum.map(fn p2pview ->
    #   :ets.lookup_element(@discovery_table, p2pview.)
    # end)
    :ets.foldl(
      fn
        res, acc ->
          with {:ok, node} <- cast_node(res, timestamp, summary),
               node <- set_node_authorization(node),
               true <- node.available? do
            [node | acc]
          else
            _ -> acc
          end
      end,
      [],
      @discovery_table
    )

    # |> IO.inspect(name: 'discovery table')
  end

  @spec cast_node(node_tuple :: tuple(), timestamp :: DateTime.t(), p2p_summary :: [P2PView.t()]) ::
          {:ok, Node.t()} | {:error, :not_found}
  defp cast_node(node_tuple, timestamp, p2p_summary) do
    first_public_key =
      elem(node_tuple, Keyword.fetch!(@discovery_index_position, :first_public_key) - 1)

    case node_index_at_timestamp(first_public_key, timestamp) do
      nil ->
        {:error, :not_found}

      node_index ->
        p2pview =
          p2p_summary
          |> Enum.at(node_index)

        node =
          node_tuple
          |> Node.cast(p2pview)

        {:ok, node}
    end
  end

  @spec cast_node(node_tuple :: tuple(), timestamp :: DateTime.t()) ::
          {:ok, Node.t()} | {:error, :not_found}
  defp cast_node(node_tuple, timestamp) do
    cast_node(node_tuple, timestamp, P2PView.get_summary(timestamp))
  end

  @doc """
  List all the node first public keys
  """
  @spec list_node_first_public_keys() :: list(Crypto.key())
  def list_node_first_public_keys do
    ets_table_keys(@discovery_table)
  end

  @doc """
  List the authorized node public keys
  """
  @spec list_authorized_public_keys() :: list(Crypto.key())
  def list_authorized_public_keys do
    ets_table_keys(@authorized_nodes_table)
  end

  @doc """
  Mark the node as authorized.
  """
  @spec authorize_node(first_public_key :: Crypto.key(), date :: DateTime.t()) ::
          :ok
  def authorize_node(first_public_key, date)
      when is_binary(first_public_key) do
    Logger.info("New authorized node", node: Base.encode16(first_public_key), date: date)

    if !:ets.member(@authorized_nodes_table, first_public_key) do
      true = :ets.insert(@authorized_nodes_table, {first_public_key, date})
      # TODO When called from add_node, notify_update_node is called two times
      notify_node_update(first_public_key, date)
    end
  end

  @doc """
  Reset the authorized nodes
  """
  @spec unauthorize_node(first_publid_key :: Crypto.key(), date :: DateTime.t()) :: :ok
  def unauthorize_node(first_public_key, date)
      when is_binary(first_public_key) do
    true = :ets.delete(@authorized_nodes_table, first_public_key)
    Logger.info("Unauthorized node", node: Base.encode16(first_public_key))
    notify_node_update(first_public_key, date)
    :ok
  end

  @doc """
  Return the first public key from a node key

  If the given key is the first one, it will returns
  Otherwise a lookup table is used to match the last key from the first key
  """
  @spec get_first_node_key(Crypto.key()) :: Crypto.key()
  def get_first_node_key(key) when is_binary(key) do
    case :ets.lookup(@nodes_key_lookup_table, key) do
      [] ->
        key

      [{_, first_key}] ->
        first_key
    end
  end

  @doc """
  Mark the node as globally available
  """
  @spec set_node_available(Crypto.key(), DateTime.t()) :: :ok
  def set_node_available(first_public_key, availability_update)
      when is_binary(first_public_key) do
    Logger.info("Node globally available",
      node: Base.encode16(first_public_key),
      date: availability_update
    )

    P2PView.update_node(
      [available?: true],
      availability_update,
      &node_index_at_timestamp(first_public_key, &1)
    )

    notify_node_update(first_public_key, availability_update)

    :ok
  end

  defp node_index_at_timestamp(first_public_key, timestamp) do
    :ets.select(
      @discovery_table,
      [
        {
          {:"$1", :_, :_, :_, :_, :_, :_, :_, :"$2", :_, :_, :_, :_, :_, :_, :_, :_, :_},
          [],
          [{{:"$1", :"$2"}}]
        }
      ]
    )
    # |> IO.inspect(label: 'discovery table')
    |> Enum.filter(fn {_, enrollment_date} ->
      DateTime.compare(DateTime.truncate(enrollment_date, :second), timestamp) != :gt
    end)
    # |> IO.inspect(label: 'discovery table - filtered #{timestamp}')
    |> Enum.map(fn {first_public_key, _} -> first_public_key end)
    |> Enum.sort()
    |> Enum.find_index(fn node_first_public_key -> node_first_public_key == first_public_key end)

    # |> IO.inspect(label: 'discovery table - index found #{Base.encode16(first_public_key)}')
  end

  @doc """
  Mark the node globally unavailable
  """
  @spec set_node_unavailable(Crypto.key(), DateTime.t()) :: :ok
  def set_node_unavailable(first_public_key, availability_update)
      when is_binary(first_public_key) do
    Logger.info("Node globally unavailable", node: Base.encode16(first_public_key))

    P2PView.update_node(
      [available?: false],
      availability_update,
      &node_index_at_timestamp(first_public_key, &1)
    )

    notify_node_update(first_public_key, availability_update)

    :ok
  end

  @doc """
  Mark the node synced
  """
  @spec set_node_synced(Crypto.key()) :: :ok
  def set_node_synced(first_public_key) when is_binary(first_public_key) do
    synced_pos = Keyword.fetch!(@discovery_index_position, :synced?)
    :ets.update_element(@discovery_table, first_public_key, {synced_pos, true})
    Logger.info("Node synced", node: Base.encode16(first_public_key))
    notify_node_update(first_public_key, DateTime.utc_now())
    :ok
  end

  @doc """
  Mark the node unsynced
  """
  @spec set_node_unsynced(Crypto.key()) :: :ok
  def set_node_unsynced(first_public_key) when is_binary(first_public_key) do
    synced_pos = Keyword.fetch!(@discovery_index_position, :synced?)
    :ets.update_element(@discovery_table, first_public_key, {synced_pos, false})
    Logger.info("Node unsynced", node: Base.encode16(first_public_key))
    notify_node_update(first_public_key, DateTime.utc_now())
    :ok
  end

  @doc """
  Update the average availability of the node and reset the history
  """
  @spec update_node_average_availability(
          first_public_key :: Crypto.key(),
          average_availability :: float(),
          timestamp :: DateTime.t()
        ) :: :ok
  def update_node_average_availability(first_public_key, avg_availability, timestamp)
      when is_binary(first_public_key) and is_float(avg_availability) do
    # avg_availability_pos = Keyword.fetch!(@discovery_index_position, :average_availability)

    P2PView.update_node(
      [avg_availability: avg_availability],
      timestamp,
      &node_index_at_timestamp(first_public_key, &1)
    )

    # true =
    #   :ets.update_element(@discovery_table, first_public_key, [
    #     {avg_availability_pos, avg_availability}
    #   ])

    Logger.info("New average availability: #{avg_availability}}",
      node: Base.encode16(first_public_key)
    )

    notify_node_update(first_public_key, timestamp)
    :ok
  end

  @doc """
  Update the network patch
  """
  @spec update_node_network_patch(first_public_key :: Crypto.key(), network_patch :: binary()) ::
          :ok
  def update_node_network_patch(first_public_key, patch)
      when is_binary(first_public_key) and is_binary(patch) do
    tuple_pos = Keyword.fetch!(@discovery_index_position, :network_patch)
    true = :ets.update_element(@discovery_table, first_public_key, [{tuple_pos, patch}])
    Logger.info("New network patch: #{patch}}", node: Base.encode16(first_public_key))
    notify_node_update(first_public_key, DateTime.utc_now())
    :ok
  end

  def set_node_authorization(node = %Node{first_public_key: first_public_key}) do
    case :ets.lookup(@authorized_nodes_table, first_public_key) do
      [] ->
        Node.remove_authorization(node)

      [{_, authorization_date}] ->
        Node.authorize(node, authorization_date)
    end
  end

  defp ets_table_keys(table_name) do
    first_key = :ets.first(table_name)
    ets_table_keys(table_name, first_key, [first_key])
  end

  defp ets_table_keys(_table_name, :"$end_of_table", [:"$end_of_table" | acc]) do
    acc
  end

  defp ets_table_keys(table_name, key, acc) do
    next_key = :ets.next(table_name, key)
    ets_table_keys(table_name, next_key, [next_key | acc])
  end

  defp notify_node_update(public_key, timestamp) do
    node = get_node!(public_key, timestamp)
    delay = DateTime.diff(timestamp, DateTime.utc_now())

    if delay > 0 do
      :timer.apply_after(
        delay,
        PubSub,
        :notify_node_update,
        [node]
      )
    else
      PubSub.notify_node_update(node)
    end
  end
end
