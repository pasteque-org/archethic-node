defmodule Archethic.SelfRepair.Sync do
  @moduledoc false

  alias __MODULE__.TransactionHandler
  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Subset.P2PSampling
  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryAggregate
  alias Archethic.Crypto
  alias Archethic.DB
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Node
  alias Archethic.PubSub
  alias Archethic.SelfRepair
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Utils

  require Logger

  @bootstrap_info_last_sync_date_key "last_sync_time"

  @doc """
  Return the last synchronization date from the previous cycle of self repair

  If there are not previous stored date:
  - Try to the first enrollment date of the listed nodes
  - Otherwise take the current date
  """
  @spec last_sync_date() :: DateTime.t() | nil
  def last_sync_date do
    case DB.get_bootstrap_info(@bootstrap_info_last_sync_date_key) do
      nil ->
        Logger.info("Not previous synchronization date")
        Logger.info("We are using the default one")
        default_last_sync_date()

      timestamp ->
        date =
          timestamp
          |> String.to_integer()
          |> DateTime.from_unix!()

        Logger.info("Last synchronization date #{DateTime.to_string(date)}")
        date
    end
  end

  defp default_last_sync_date do
    case P2P.list_nodes() do
      [] ->
        nil

      nodes ->
        %Node{enrollment_date: enrollment_date} =
          nodes
          |> Enum.reject(&(&1.enrollment_date == nil))
          |> Enum.sort_by(& &1.enrollment_date, {:asc, DateTime})
          |> Enum.at(0)

        Logger.info(
          "We are taking the first node's enrollment date - #{DateTime.to_string(enrollment_date)}"
        )

        enrollment_date
    end
  end

  @doc """
  Persist the last sync date
  """
  @spec store_last_sync_date(DateTime.t()) :: :ok
  def store_last_sync_date(%DateTime{} = date) do
    timestamp =
      date
      |> DateTime.to_unix()
      |> Integer.to_string()

    DB.set_bootstrap_info(@bootstrap_info_last_sync_date_key, timestamp)

    Logger.info("Last sync date updated: #{DateTime.to_string(date)}")
  end

  @doc """
  Retrieve missing transactions from the missing beacon chain slots
  since the last sync date provided

  Beacon chain pools are retrieved from the given latest synchronization
  date including all the beacon subsets (i.e <<0>>, <<1>>, etc.)

  Once retrieved, the transactions are downloaded and stored if not exists locally
  """
  @spec load_missed_transactions(last_sync_date :: DateTime.t(), download_nodes :: list(Node.t())) ::
          :ok | {:error, :unreachable_nodes}
  def load_missed_transactions(last_sync_date, download_nodes) do
    last_summary_time = BeaconChain.previous_summary_time(DateTime.utc_now())

    if DateTime.after?(last_summary_time, last_sync_date) do
      Logger.info(
        "Fetch missed transactions from last sync date: #{DateTime.to_string(last_sync_date)}"
      )

      do_load_missed_transactions(last_sync_date, last_summary_time, download_nodes)
    else
      Logger.info("Already synchronized for #{DateTime.to_string(last_sync_date)}")

      # We skip the self-repair because the last synchronization time have been already synchronized
      :ok
    end
  end

  defp do_load_missed_transactions(last_sync_date, last_summary_time, download_nodes) do
    start = System.monotonic_time()

    # Process first the old aggregates
    last_sync_date
    |> fetch_summaries_aggregates(last_summary_time, download_nodes)
    |> Enum.each(&process_summary_aggregate(&1, download_nodes))

    # Then process the last one to have the last P2P view
    last_aggregate = BeaconChain.fetch_and_aggregate_summaries(last_summary_time, download_nodes)
    ensure_download_last_aggregate(last_aggregate, download_nodes)

    last_aggregate
    |> aggregate_with_local_summaries(last_summary_time)
    |> verify_attestations_threshold()
    |> process_summary_aggregate(download_nodes)

    :telemetry.execute([:archethic, :self_repair], %{duration: System.monotonic_time() - start})
    Archethic.Bootstrap.NetworkConstraints.persist_genesis_address()
  end

  defp fetch_summaries_aggregates(last_sync_date, last_summary_time, download_nodes) do
    dates =
      last_sync_date
      |> BeaconChain.next_summary_dates()
      # Take only the previous summaries before the last one
      |> Stream.take_while(&DateTime.before?(&1, last_summary_time))

    # Fetch the beacon summaries aggregate
    Archethic.task_supervisors()
    |> Task.Supervisor.async_stream(
      dates,
      fn date ->
        Logger.debug("Fetch summary aggregate for #{date}")

        storage_nodes =
          date
          |> Crypto.derive_beacon_aggregate_address()
          |> Election.chain_storage_nodes(download_nodes)

        BeaconChain.fetch_summaries_aggregate(date, storage_nodes)
      end,
      max_concurrency: 2
    )
    |> Stream.filter(fn
      {:ok, {:ok, %SummaryAggregate{}}} ->
        true

      {:ok, {:error, :not_exists}} ->
        false

      {:ok, _} ->
        raise SelfRepair.Error,
          function: "fetch_summaries_aggregates",
          message: "Previous summary aggregate not fetched"
    end)
    |> Stream.map(fn {:ok, {:ok, aggregate}} -> aggregate end)
  end

  defp ensure_download_last_aggregate(last_aggregate, download_nodes) do
    # Make sure the last beacon aggregate have been synchronized
    # from remote nodes to avoid self-repair to be acknowledged if those
    # cannot be reached
    # If number of authorized node is <= 2 and current node is part of it
    # we accept the self repair as the other node may be unavailable and so
    # we need to do the self even if no other node respond
    with true <- P2P.authorized_node?(),
         true <- length(download_nodes) <= 2 do
      :ok
    else
      _ ->
        if SummaryAggregate.empty?(last_aggregate) do
          raise SelfRepair.Error,
            function: "ensure_download_last_aggregate",
            message: "Last aggregate not fetched"
        end

        :ok
    end
  end

  defp aggregate_with_local_summaries(summary_aggregate, last_summary_time) do
    BeaconChain.list_subsets()
    |> Task.async_stream(fn subset ->
      summary_address = Crypto.derive_beacon_chain_address(subset, last_summary_time, true)
      BeaconChain.get_summary(summary_address)
    end)
    |> Enum.reduce(summary_aggregate, fn
      {:ok, {:ok, %Summary{} = summary}}, acc ->
        SummaryAggregate.add_summary(acc, summary)

      _, acc ->
        acc
    end)
    |> SummaryAggregate.aggregate()
  end

  defp verify_attestations_threshold(summary_aggregate) do
    {filtered_summary_aggregate, refused_attestations} =
      SummaryAggregate.filter_reached_threshold(summary_aggregate)

    postpone_refused_attestations(refused_attestations)

    filtered_summary_aggregate
  end

  defp postpone_refused_attestations(attestations) do
    slot_time = BeaconChain.next_slot(DateTime.utc_now())
    nodes = P2P.authorized_and_available_nodes(slot_time)

    Enum.each(
      attestations,
      fn %ReplicationAttestation{
           transaction_summary: %TransactionSummary{address: address, type: type},
           confirmations: confirmations
         } = attestation ->
        # Postpone only if we are the current beacon slot node
        # (otherwise all nodes would postpone as the self repair is run on all nodes)
        slot_node? =
          address
          |> BeaconChain.subset_from_address()
          |> Election.beacon_storage_nodes(slot_time, nodes)
          |> Utils.key_in_node_list?(Crypto.first_node_public_key())

        if slot_node? do
          Logger.debug(
            "Attestation postponed to next summary with #{length(confirmations)} confirmations",
            transaction_address: Base.encode16(address),
            transaction_type: type
          )

          # Notification will be catched by subset and add the attestation in current Slot
          PubSub.notify_replication_attestation(attestation)
        end
      end
    )
  end

  @doc """
  Process beacon summary to synchronize the transactions involving.

  Each transactions from the beacon summary will be analyzed to determine
  if the node is a storage node for this transaction. If so, it will download the
  transaction from the closest storage nodes and replicate it locally.

  The P2P view will also be updated if some node information are inside the beacon chain to determine
  the readiness or the availability of a node.

  Also, the  number of transaction received and the fees burned during the beacon summary interval will be stored.

  At the end of the execution, the summaries aggregate will persisted locally if the node is member of the shard of the summary
  """
  @spec process_summary_aggregate(SummaryAggregate.t(), list(Node.t())) :: :ok
  def process_summary_aggregate(
        %SummaryAggregate{
          summary_time: summary_time,
          replication_attestations: attestations,
          p2p_availabilities: p2p_availabilities,
          availability_adding_time: availability_adding_time
        } = aggregate,
        download_nodes
      ) do
    start_time = System.monotonic_time()

    nb_transactions = process_replication_attestations(attestations, download_nodes)

    :telemetry.execute(
      [:archethic, :self_repair, :process_aggregate],
      %{duration: System.monotonic_time() - start_time},
      %{nb_transactions: nb_transactions}
    )

    availability_update = DateTime.add(summary_time, availability_adding_time)

    previous_available_nodes = P2P.authorized_and_available_nodes()

    p2p_availabilities
    |> Enum.reduce(%{}, fn {subset,
                            %{
                              node_availabilities: node_availabilities,
                              node_average_availabilities: node_average_availabilities,
                              end_of_node_synchronizations: end_of_node_synchronizations,
                              network_patches: network_patches
                            }},
                           acc ->
      sync_node(end_of_node_synchronizations)

      reduce_p2p_availabilities(
        subset,
        summary_time,
        node_availabilities,
        node_average_availabilities,
        network_patches,
        acc
      )
    end)
    |> Enum.map(&update_availabilities(&1, availability_update))
    |> DB.register_p2p_summary()

    new_available_nodes = P2P.authorized_and_available_nodes(availability_update)

    if Archethic.up?() do
      SelfRepair.start_notifier(
        previous_available_nodes,
        new_available_nodes,
        availability_update
      )
    end

    update_statistics(summary_time, attestations)

    store_aggregate(aggregate, new_available_nodes)
    store_last_sync_date(summary_time)
  end

  @doc """
  Downloads and stores the transactions missed, returns the count of transactions synchronized
  """
  @spec process_replication_attestations(
          replication_attestations :: list(ReplicationAttestation.t()),
          download_nodes :: list(Node.t())
        ) :: integer()
  def process_replication_attestations(replication_attestations, download_nodes) do
    nodes_including_self = P2P.distinct_nodes([P2P.get_node_info() | download_nodes])

    replication_attestations
    |> Enum.filter(&TransactionHandler.download_transaction?(&1, nodes_including_self))
    |> Enum.sort_by(& &1.transaction_summary.timestamp, {:asc, DateTime})
    |> then(fn filtered_attestations ->
      synchronize_transactions(filtered_attestations, download_nodes)
      length(filtered_attestations)
    end)
  end

  defp synchronize_transactions([], _), do: :ok

  defp synchronize_transactions(attestations, download_nodes) do
    Logger.info("Need to synchronize #{Enum.count(attestations)} transactions")
    Logger.debug("Transaction to sync #{inspect(attestations)}")

    node_key = Crypto.first_node_public_key()
    previous_summary_time = BeaconChain.previous_summary_time(DateTime.utc_now())

    Archethic.task_supervisors()
    |> Task.Supervisor.async_stream(
      attestations,
      fn attestation ->
        {tx, inputs} =
          TransactionHandler.download_transaction_data(
            attestation,
            download_nodes,
            node_key,
            previous_summary_time
          )

        {attestation, tx, inputs}
      end,
      max_concurrency: System.schedulers_online() * 2,
      timeout: Message.get_max_timeout() + 2000
    )
    |> Enum.each(fn {:ok, {attestation, tx, inputs}} ->
      :ok =
        TransactionHandler.process_transaction_data(
          attestation,
          tx,
          inputs,
          download_nodes,
          node_key
        )
    end)
  end

  defp sync_node(end_of_node_synchronizations) do
    Enum.each(end_of_node_synchronizations, fn public_key ->
      P2P.set_node_globally_synced(public_key)
    end)
  end

  defp reduce_p2p_availabilities(
         subset,
         time,
         node_availabilities,
         node_average_availabilities,
         network_patches,
         acc
       ) do
    node_list = Enum.filter(P2P.list_nodes(), &(DateTime.diff(&1.enrollment_date, time) <= 0))

    subset_node_list = P2PSampling.list_nodes_to_sample(subset, node_list)

    node_availabilities
    |> Utils.bitstring_to_integer_list()
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {available_bit, index}, acc ->
      node = Enum.at(subset_node_list, index)
      avg_availability = Enum.at(node_average_availabilities, index)
      network_patch = Enum.at(network_patches, index, node.geo_patch)
      available? = available_bit == 1 and node.synced?

      Map.put(acc, node, %{
        available?: available?,
        average_availability: avg_availability,
        network_patch: network_patch
      })
    end)
  end

  defp update_availabilities(
         {%Node{first_public_key: node_key},
          %{
            available?: available?,
            average_availability: avg_availability,
            network_patch: network_patch
          }},
         availability_update
       ) do
    if available? do
      P2P.set_node_globally_available(node_key, availability_update)
    else
      P2P.set_node_globally_unavailable(node_key, availability_update)
      P2P.set_node_globally_unsynced(node_key)
    end

    P2P.set_node_average_availability(node_key, avg_availability)
    P2P.update_node_network_patch(node_key, network_patch)

    %Node{availability_update: availability_update} = P2P.get_node_info!(node_key)

    {node_key, available?, avg_availability, availability_update, network_patch}
  end

  defp update_statistics(date, []) do
    tps = DB.get_latest_tps()
    DB.register_stats(date, tps, 0, 0)
  end

  defp update_statistics(date, attestations) do
    nb_transactions = length(attestations)

    previous_summary_time =
      date
      |> Utils.truncate_datetime()
      |> BeaconChain.previous_summary_time()

    nb_seconds = abs(DateTime.diff(previous_summary_time, date))
    tps = nb_transactions / nb_seconds

    acc = 0

    burned_fees =
      Enum.reduce(attestations, acc, fn %ReplicationAttestation{
                                          transaction_summary: %TransactionSummary{fee: fee}
                                        },
                                        acc ->
        acc + fee
      end)

    DB.register_stats(date, tps, nb_transactions, burned_fees)

    Logger.info(
      "TPS #{tps} on #{Utils.time_to_string(date)} with #{nb_transactions} transactions"
    )

    Logger.info("Burned fees #{burned_fees} on #{Utils.time_to_string(date)}")

    PubSub.notify_new_tps(tps, nb_transactions)
  end

  defp store_aggregate(%SummaryAggregate{summary_time: summary_time} = aggregate, new_nodes) do
    node_list = P2P.distinct_nodes([P2P.get_node_info() | new_nodes])

    should_store? =
      summary_time
      |> Crypto.derive_beacon_aggregate_address()
      |> Election.chain_storage_nodes(node_list)
      |> Utils.key_in_node_list?(Crypto.first_node_public_key())

    if should_store? do
      BeaconChain.write_summaries_aggregate(aggregate)
      Logger.info("Summary written to disk for #{summary_time}")
    else
      :ok
    end
  end
end
