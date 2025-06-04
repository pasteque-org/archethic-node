defmodule Archethic.BeaconChain.ReplicationAttestationTest do
  use ArchethicCase

  import ArchethicCase

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.TransactionFactory

  doctest ReplicationAttestation

  test "symmetric serialization" do
    attestation = %ReplicationAttestation{
      version: 1,
      transaction_summary: %TransactionSummary{
        address: random_address(),
        type: :transfer,
        timestamp: ~U[2022-01-27 09:14:22.000Z],
        fee: 10_000_000,
        validation_stamp_checksum: :crypto.strong_rand_bytes(32),
        genesis_address: random_address()
      }
    }

    assert {^attestation, _} =
             attestation
             |> ReplicationAttestation.serialize()
             |> ReplicationAttestation.deserialize()
  end

  describe "reached_threshold?/1" do
    setup do
      # Create 10 nodes on last summary
      Enum.each(0..9, fn i ->
        P2P.add_and_connect_node(%Node{
          ip: {88, 130, 19, i},
          port: 3000 + i,
          last_public_key: random_public_key(),
          first_public_key: random_public_key(),
          geo_patch: "AAA",
          available?: true,
          authorized?: true,
          authorization_date: DateTime.add(DateTime.utc_now(), -1, :hour),
          enrollment_date: DateTime.add(DateTime.utc_now(), -2, :hour)
        })
      end)

      # Add two node in the current summary
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        last_public_key: random_public_key(),
        first_public_key: random_public_key(),
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        enrollment_date: DateTime.utc_now()
      })

      # Add two node in the current summary
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 2},
        port: 3001,
        last_public_key: random_public_key(),
        first_public_key: random_public_key(),
        geo_patch: "AAA",
        available?: true,
        authorized?: true,
        authorization_date: DateTime.utc_now(),
        enrollment_date: DateTime.utc_now()
      })
    end

    test "should return true if attestation reached threshold" do
      # First Replication with enough threshold
      attestation = %ReplicationAttestation{
        transaction_summary: %TransactionSummary{
          timestamp: DateTime.add(DateTime.utc_now(), -1, :hour)
        },
        confirmations: Enum.map(0..9, &{&1, "signature#{&1}"})
      }

      assert ReplicationAttestation.reached_threshold?(attestation)

      # Second Replication without enough threshold
      attestation = %ReplicationAttestation{
        transaction_summary: %TransactionSummary{
          timestamp: DateTime.add(DateTime.utc_now(), -1, :hour)
        },
        confirmations: Enum.map(0..2, &{&1, "signature#{&1}"})
      }

      assert ReplicationAttestation.reached_threshold?(attestation)
    end

    test "should return false if attestation do not reach threshold" do
      # First Replication with enough threshold
      attestation = %ReplicationAttestation{
        transaction_summary: %TransactionSummary{
          timestamp: DateTime.utc_now()
        },
        confirmations: Enum.map(0..9, &{&1, "signature#{&1}"})
      }

      assert ReplicationAttestation.reached_threshold?(attestation)

      # Second Replication without enough threshold
      attestation = %ReplicationAttestation{
        transaction_summary: %TransactionSummary{
          timestamp: DateTime.utc_now()
        },
        confirmations: Enum.map(0..2, &{&1, "signature#{&1}"})
      }

      refute ReplicationAttestation.reached_threshold?(attestation)
    end
  end

  describe "valid_attestation" do
    test "should return :ok if attestation is valid with good nodes signatures" do
      # Create 11 nodes on last summary
      nodes_keypair =
        Enum.map(0..10, fn i ->
          node_keypair = Crypto.derive_keypair("node_seed#{i}", 1)

          P2P.add_and_connect_node(%Node{
            ip: {88, 130, 19, i},
            port: 3000 + i,
            last_public_key: elem(node_keypair, 0),
            first_public_key: elem(node_keypair, 0),
            geo_patch: "BBB",
            network_patch: "BBB",
            available?: true,
            authorized?: true,
            authorization_date: DateTime.add(DateTime.utc_now(), -1, :hour),
            enrollment_date: DateTime.add(DateTime.utc_now(), -2, :hour)
          })

          node_keypair
        end)

      P2P.add_and_connect_node(%Node{
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        authorized?: true,
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorization_date: DateTime.add(DateTime.utc_now(), -1, :hour),
        enrollment_date: DateTime.add(DateTime.utc_now(), -2, :hour)
      })

      tx_timestamp = DateTime.add(DateTime.utc_now(), -59, :minute)

      TransactionFactory.create_valid_transaction([], timestamp: tx_timestamp)

      tx_summary =
        %TransactionSummary{address: tx_address} =
        []
        |> TransactionFactory.create_valid_transaction(timestamp: tx_timestamp)
        |> TransactionSummary.from_transaction()

      elected_storage_nodes =
        Election.chain_storage_nodes(tx_address, P2P.authorized_and_available_nodes(tx_timestamp))

      attestation = %ReplicationAttestation{
        transaction_summary: tx_summary,
        confirmations:
          Enum.map(0..(length(elected_storage_nodes) - 1), fn i ->
            %Node{first_public_key: node_key} = Enum.at(elected_storage_nodes, i)
            create_confirmation(node_key, nodes_keypair, tx_summary, tx_timestamp)
          end)
      }

      assert :ok == ReplicationAttestation.validate(attestation)
    end

    test "should return error if attestation has invalid signature" do
      # Create 11 nodes on last summary
      nodes_keypair =
        Enum.map(0..10, fn i ->
          node_keypair = Crypto.derive_keypair("node_seed#{i}", 1)

          P2P.add_and_connect_node(%Node{
            ip: {88, 130, 19, i},
            port: 3000 + i,
            last_public_key: elem(node_keypair, 0),
            first_public_key: elem(node_keypair, 0),
            geo_patch: "BBB",
            network_patch: "BBB",
            available?: true,
            authorized?: true,
            authorization_date: DateTime.add(DateTime.utc_now(), -1, :hour),
            enrollment_date: DateTime.add(DateTime.utc_now(), -2, :hour)
          })

          node_keypair
        end)

      P2P.add_and_connect_node(%Node{
        first_public_key: Crypto.first_node_public_key(),
        last_public_key: Crypto.last_node_public_key(),
        authorized?: true,
        available?: true,
        geo_patch: "AAA",
        network_patch: "AAA",
        authorization_date: DateTime.add(DateTime.utc_now(), -1, :hour),
        enrollment_date: DateTime.add(DateTime.utc_now(), -2, :hour)
      })

      tx_timestamp = DateTime.add(DateTime.utc_now(), -59, :minute)

      TransactionFactory.create_valid_transaction([], timestamp: tx_timestamp)

      tx_summary =
        %TransactionSummary{address: tx_address} =
        []
        |> TransactionFactory.create_valid_transaction(timestamp: tx_timestamp)
        |> TransactionSummary.from_transaction()

      elected_storage_nodes =
        Election.chain_storage_nodes(tx_address, P2P.authorized_and_available_nodes(tx_timestamp))

      %Node{first_public_key: node_key} =
        Enum.at(elected_storage_nodes, length(elected_storage_nodes) - 1)

      modified_tx_summary = %{tx_summary | fee: tx_summary.fee + 1}

      invalid_confirmation =
        create_confirmation(node_key, nodes_keypair, modified_tx_summary, tx_timestamp)

      attestation = %ReplicationAttestation{
        transaction_summary: tx_summary,
        confirmations:
          0..(length(elected_storage_nodes) - 2)
          |> Enum.map(fn i ->
            %Node{first_public_key: node_key} = Enum.at(elected_storage_nodes, i)
            create_confirmation(node_key, nodes_keypair, tx_summary, tx_timestamp)
          end)
          |> Enum.concat([invalid_confirmation])
      }

      assert {:error, :invalid_confirmations_signatures} ==
               ReplicationAttestation.validate(attestation)
    end

    defp create_confirmation(node_key, nodes_keypair, tx_summary, tx_timestamp) do
      signature =
        if node_key == Crypto.first_node_public_key() do
          tx_summary |> TransactionSummary.serialize() |> Crypto.sign_with_first_node_key()
        else
          {_, node_private_key} = Enum.find(nodes_keypair, &match?({^node_key, _}, &1))
          tx_summary |> TransactionSummary.serialize() |> Crypto.sign(node_private_key)
        end

      index = ReplicationAttestation.get_node_index(node_key, tx_timestamp)

      {index, signature}
    end
  end
end
