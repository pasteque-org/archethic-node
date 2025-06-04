defmodule Archethic.P2P.MessageId do
  @moduledoc """
  Provide functions to encode or decode a message according to it's type
  """

  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryAggregate
  alias Archethic.P2P.Message.AcknowledgeStorage
  alias Archethic.P2P.Message.AddMiningContext
  alias Archethic.P2P.Message.AddressList
  alias Archethic.P2P.Message.BeaconSummaryList
  alias Archethic.P2P.Message.BeaconUpdate
  alias Archethic.P2P.Message.BootstrappingNodes
  alias Archethic.P2P.Message.CrossValidate
  alias Archethic.P2P.Message.CrossValidationDone
  alias Archethic.P2P.Message.CurrentReplicationAttestations
  alias Archethic.P2P.Message.DashboardData
  alias Archethic.P2P.Message.EncryptedStorageNonce
  alias Archethic.P2P.Message.Error
  alias Archethic.P2P.Message.FirstPublicKey
  alias Archethic.P2P.Message.FirstTransactionAddress
  alias Archethic.P2P.Message.GenesisAddress
  alias Archethic.P2P.Message.GetBeaconSummaries
  alias Archethic.P2P.Message.GetBeaconSummariesAggregate
  alias Archethic.P2P.Message.GetBeaconSummary
  alias Archethic.P2P.Message.GetBootstrappingNodes
  alias Archethic.P2P.Message.GetCurrentReplicationAttestations
  alias Archethic.P2P.Message.GetCurrentSummaries
  alias Archethic.P2P.Message.GetDashboardData
  alias Archethic.P2P.Message.GetFirstPublicKey
  alias Archethic.P2P.Message.GetFirstTransactionAddress
  alias Archethic.P2P.Message.GetGenesisAddress
  alias Archethic.P2P.Message.GetLastTransaction
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.GetNetworkStats
  alias Archethic.P2P.Message.GetNextAddresses
  alias Archethic.P2P.Message.GetStorageNonce
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetTransactionChainLength
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.GetTransactionSummary
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.ListNodes
  alias Archethic.P2P.Message.NetworkStats
  alias Archethic.P2P.Message.NewBeaconSlot
  alias Archethic.P2P.Message.NewTransaction
  alias Archethic.P2P.Message.NodeList
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.NotifyEndOfNodeSync
  alias Archethic.P2P.Message.NotifyLastTransactionAddress
  alias Archethic.P2P.Message.NotifyPreviousChain
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Ping
  alias Archethic.P2P.Message.ProofOfReplicationDone
  alias Archethic.P2P.Message.ProofOfValidationDone
  alias Archethic.P2P.Message.RegisterBeaconUpdates
  alias Archethic.P2P.Message.ReplicatePendingTransactionChain
  alias Archethic.P2P.Message.ReplicateTransaction
  alias Archethic.P2P.Message.ReplicationAttestationMessage
  alias Archethic.P2P.Message.ReplicationSignatureDone
  alias Archethic.P2P.Message.RequestChainLock
  alias Archethic.P2P.Message.RequestReplicationSignature
  alias Archethic.P2P.Message.ShardRepair
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.StartMining
  alias Archethic.P2P.Message.TransactionChainLength
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Message.TransactionSummaryList
  alias Archethic.P2P.Message.TransactionSummaryMessage
  alias Archethic.P2P.Message.UnlockChain
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Message.UpdateLastAddress
  alias Archethic.P2P.Message.ValidateSmartContractCall
  alias Archethic.P2P.Message.ValidateTransaction
  alias Archethic.P2P.Message.ValidationError
  alias Archethic.TransactionChain.Transaction

  @message_ids %{
    # Requests
    GetBootstrappingNodes => 0,
    GetStorageNonce => 1,
    ListNodes => 2,
    GetTransaction => 3,
    GetTransactionChain => 4,
    GetUnspentOutputs => 5,
    NewTransaction => 6,
    StartMining => 7,
    AddMiningContext => 8,
    CrossValidate => 9,
    CrossValidationDone => 10,
    ValidateSmartContractCall => 11,
    ReplicateTransaction => 12,
    AcknowledgeStorage => 13,
    NotifyEndOfNodeSync => 14,
    GetLastTransaction => 15,
    RequestReplicationSignature => 16,
    GetTransactionInputs => 17,
    GetTransactionChainLength => 18,
    RequestChainLock => 19,
    GetFirstPublicKey => 20,
    GetLastTransactionAddress => 21,
    NotifyLastTransactionAddress => 22,
    GetTransactionSummary => 23,
    GetFirstTransactionAddress => 24,
    Ping => 25,
    GetBeaconSummary => 26,
    NewBeaconSlot => 27,
    GetBeaconSummaries => 28,
    RegisterBeaconUpdates => 29,
    ReplicationAttestationMessage => 30,
    GetGenesisAddress => 31,
    GetCurrentSummaries => 32,
    GetBeaconSummariesAggregate => 33,
    NotifyPreviousChain => 34,
    GetNextAddresses => 35,
    ValidateTransaction => 36,
    ReplicatePendingTransactionChain => 37,
    ProofOfValidationDone => 38,
    GetNetworkStats => 39,
    GetDashboardData => 40,
    UnlockChain => 41,
    GetCurrentReplicationAttestations => 42,
    UpdateLastAddress => 43,
    ProofOfReplicationDone => 44,
    ReplicationSignatureDone => 45,

    # Responses
    DashboardData => 225,
    SmartContractCallValidation => 226,
    NetworkStats => 227,
    FirstTransactionAddress => 228,
    AddressList => 229,
    ShardRepair => 230,
    SummaryAggregate => 231,
    TransactionSummaryList => 232,
    # Message number 233 is available
    ValidationError => 234,
    GenesisAddress => 235,
    BeaconUpdate => 236,
    BeaconSummaryList => 237,
    Error => 238,
    TransactionSummaryMessage => 239,
    Summary => 240,
    LastTransactionAddress => 241,
    FirstPublicKey => 242,
    CurrentReplicationAttestations => 243,
    TransactionInputList => 244,
    TransactionChainLength => 245,
    BootstrappingNodes => 246,
    EncryptedStorageNonce => 247,
    # Message number 248 is available
    NodeList => 249,
    UnspentOutputList => 250,
    TransactionList => 251,
    Transaction => 252,
    NotFound => 253,
    Ok => 254
  }

  # Compiled macro functions looks like (for each message):
  #
  # def decode(<<25::8, rest::bitstring>>) do
  #   Ping.deserialize(rest)
  # end
  #
  # def encode(msg = %Ping{}) do
  #   <<25::8, Ping.serialize(msg)::bitstring>>
  # end

  defmacro __before_compile__(_env) do
    Enum.map(@message_ids, fn {msg, msg_id} ->
      quote do
        def decode(<<unquote(msg_id)::8, rest::bitstring>>) do
          unquote(msg).deserialize(rest)
        end

        def encode(%unquote(msg){} = msg) do
          <<unquote(msg_id)::8, unquote(msg).serialize(msg)::bitstring>>
        end
      end
    end)
  end
end
