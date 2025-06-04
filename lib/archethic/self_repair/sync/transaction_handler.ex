defmodule Archethic.SelfRepair.Sync.TransactionHandler do
  @moduledoc false

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Node
  alias Archethic.Replication
  alias Archethic.SelfRepair
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Utils

  require Logger

  @doc """
  Determine if the transaction should be downloaded by the local node.

  Verify firstly the chain storage nodes election.
  If not successful, perform storage nodes election based on the transaction movements.
  """
  @spec download_transaction?(ReplicationAttestation.t(), list(Node.t())) :: boolean()
  def download_transaction?(
        %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address: address,
            type: type,
            genesis_address: genesis_address,
            movements_addresses: movements_addresses
          }
        },
        node_list
      ) do
    node_key = Crypto.first_node_public_key()

    if Election.chain_storage_node?(address, type, node_key, node_list) or
         Election.chain_storage_node?(genesis_address, node_key, node_list) do
      not TransactionChain.transaction_exists?(address)
    else
      io_node?(movements_addresses, node_key, node_list) and
        not TransactionChain.transaction_exists?(address, :io)
    end
  end

  @doc """
  Download a transaction from closest storage nodes and ensure the transaction
  is the same than the one in the replication attestation
  """
  @spec download_transaction_data(
          attestation :: ReplicationAttestation.t(),
          download_nodes :: list(Node.t()),
          node_key :: Crypto.key(),
          previous_summary_time :: DateTime.t()
        ) :: {transaction :: Transaction.t(), transaction_inputs :: list(TransactionInput.t())}
  def download_transaction_data(
        %ReplicationAttestation{
          transaction_summary:
            %TransactionSummary{address: address, type: type} = expected_summary
        },
        node_list,
        node_key,
        previous_summary_time
      ) do
    Logger.info("Synchronize missed transaction",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )

    storage_nodes =
      address
      |> Election.chain_storage_nodes_with_type(type, node_list)
      |> Election.get_synchronized_nodes_before(previous_summary_time)
      |> Enum.reject(&(&1.first_public_key == node_key))

    node_list = P2P.distinct_nodes([P2P.get_node_info() | node_list])

    if_result =
      if Election.chain_storage_node?(address, type, node_key, node_list) do
        Task.await_many(
          [
            Task.async(fn -> download_transaction(expected_summary, storage_nodes) end),
            Task.async(fn ->
              address |> TransactionChain.fetch_inputs(storage_nodes) |> Enum.to_list()
            end)
          ],
          Message.get_max_timeout() + 100
        )
      else
        [download_transaction(expected_summary, storage_nodes), []]
      end

    then(if_result, fn
      [{:ok, tx}, inputs] ->
        {tx, inputs}

      [{_, reason}, _] ->
        raise SelfRepair.Error,
          function: "download_transaction_data",
          message: "Cannot fetch the transaction to sync because of #{inspect(reason)}",
          address: address
    end)
  catch
    # catch timeout of Task.await_many
    :exit, _ ->
      raise SelfRepair.Error,
        function: "download_transaction_data",
        message: "Cannot fetch the transaction to sync because of timeout",
        address: address
  end

  defp download_transaction(
         %TransactionSummary{address: address} = expected_summary,
         storage_nodes
       ) do
    acceptance_resolver = fn
      %Transaction{} = tx ->
        # TODO:
        # we can add a verification to ensure the proof of integrity is the right one
        # using the previous transaction and hence asserting the TransactionSummary.validation_stamp_checksum
        # in order to remove malicious node given false transaction's data

        TransactionSummary.from_transaction(tx) == expected_summary

      _ ->
        false
    end

    TransactionChain.fetch_transaction(address, storage_nodes,
      search_mode: :remote,
      timeout: Message.get_max_timeout(),
      acceptance_resolver: acceptance_resolver
    )
  end

  @spec process_transaction_data(
          attestation :: ReplicationAttestation.t(),
          transaction :: Transaction.t(),
          inputs :: list(TransactionInput.t()),
          download_nodes :: list(Node.t()),
          node_key :: Crypto.key()
        ) :: :ok
  def process_transaction_data(
        %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            genesis_address: genesis_address,
            movements_addresses: movements_addresses
          }
        } = attestation,
        %Transaction{address: address, type: type} = tx,
        inputs,
        node_list,
        node_key
      ) do
    verify_attestation(attestation)

    node_list = P2P.distinct_nodes([P2P.get_node_info() | node_list])

    cond do
      Election.chain_storage_node?(address, type, node_key, node_list) ->
        Replication.sync_transaction_chain(tx, node_list, self_repair?: true)
        TransactionChain.write_inputs(address, inputs)

      Election.chain_storage_node?(genesis_address, node_key, node_list) ->
        Replication.sync_transaction_chain(tx, node_list, self_repair?: true)

      io_node?(movements_addresses, node_key, node_list) ->
        Replication.synchronize_io_transaction(tx, self_repair?: true, download_nodes: node_list)

      true ->
        :ok
    end
  end

  defp io_node?(addresses, node_public_key, nodes),
    do: addresses |> Election.io_storage_nodes(nodes) |> Utils.key_in_node_list?(node_public_key)

  defp verify_attestation(attestation) do
    cond do
      not ReplicationAttestation.reached_threshold?(attestation) ->
        Logger.error("Threshold error in self repair on attestation #{inspect(attestation)}")

        raise SelfRepair.Error,
          function: "verify_attestation",
          message: "Threshold error in self repair on attestation #{inspect(attestation)}"

      :ok != ReplicationAttestation.validate(attestation) ->
        raise SelfRepair.Error,
          function: "verify_attestation",
          message: "Confirmation error in self repair on attestation #{inspect(attestation)}"

      true ->
        :ok
    end
  end
end
