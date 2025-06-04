defmodule Archethic.P2P.Message do
  @moduledoc """
  Provide functions to encode and decode P2P messages using a custom binary protocol
  """

  alias __MODULE__.AcknowledgeStorage
  alias __MODULE__.AddMiningContext
  alias __MODULE__.AddressList
  alias __MODULE__.BeaconSummaryList
  alias __MODULE__.BeaconUpdate
  alias __MODULE__.BootstrappingNodes
  alias __MODULE__.CrossValidate
  alias __MODULE__.CrossValidationDone
  alias __MODULE__.CurrentReplicationAttestations
  alias __MODULE__.DashboardData
  alias __MODULE__.EncryptedStorageNonce
  alias __MODULE__.Error
  alias __MODULE__.FirstPublicKey
  alias __MODULE__.FirstTransactionAddress
  alias __MODULE__.GenesisAddress
  alias __MODULE__.GetBeaconSummaries
  alias __MODULE__.GetBeaconSummariesAggregate
  alias __MODULE__.GetBeaconSummary
  alias __MODULE__.GetBootstrappingNodes
  alias __MODULE__.GetCurrentReplicationAttestations
  alias __MODULE__.GetCurrentSummaries
  alias __MODULE__.GetDashboardData
  alias __MODULE__.GetFirstTransactionAddress
  alias __MODULE__.GetGenesisAddress
  alias __MODULE__.GetLastTransaction
  alias __MODULE__.GetLastTransactionAddress
  alias __MODULE__.GetNetworkStats
  alias __MODULE__.GetNextAddresses
  alias __MODULE__.GetStorageNonce
  alias __MODULE__.GetTransaction
  alias __MODULE__.GetTransactionChain
  alias __MODULE__.GetTransactionChainLength
  alias __MODULE__.GetTransactionInputs
  alias __MODULE__.GetTransactionSummary
  alias __MODULE__.GetUnspentOutputs
  alias __MODULE__.LastTransactionAddress
  alias __MODULE__.ListNodes
  alias __MODULE__.NetworkStats
  alias __MODULE__.NewBeaconSlot
  alias __MODULE__.NewTransaction
  alias __MODULE__.NodeList
  alias __MODULE__.NotFound
  alias __MODULE__.NotifyEndOfNodeSync
  alias __MODULE__.NotifyLastTransactionAddress
  alias __MODULE__.NotifyPreviousChain
  alias __MODULE__.Ok
  alias __MODULE__.Ping
  alias __MODULE__.ProofOfReplicationDone
  alias __MODULE__.ProofOfValidationDone
  alias __MODULE__.RegisterBeaconUpdates
  alias __MODULE__.ReplicatePendingTransactionChain
  alias __MODULE__.ReplicateTransaction
  alias __MODULE__.ReplicationAttestationMessage
  alias __MODULE__.ReplicationSignatureDone
  alias __MODULE__.RequestChainLock
  alias __MODULE__.RequestReplicationSignature
  alias __MODULE__.ShardRepair
  alias __MODULE__.SmartContractCallValidation
  alias __MODULE__.StartMining
  alias __MODULE__.TransactionChainLength
  alias __MODULE__.TransactionInputList
  alias __MODULE__.TransactionList
  alias __MODULE__.TransactionSummaryList
  alias __MODULE__.TransactionSummaryMessage
  alias __MODULE__.UnlockChain
  alias __MODULE__.UnspentOutputList
  alias __MODULE__.UpdateLastAddress
  alias __MODULE__.ValidateSmartContractCall
  alias __MODULE__.ValidateTransaction
  alias __MODULE__.ValidationError
  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryAggregate
  alias Archethic.Crypto
  alias Archethic.P2P.MessageId
  alias Archethic.TransactionChain.Transaction

  require Logger

  @type t :: request() | response()

  @type request ::
          GetBootstrappingNodes.t()
          | GetStorageNonce.t()
          | ListNodes.t()
          | GetTransaction.t()
          | GetTransactionChain.t()
          | GetUnspentOutputs.t()
          | NewTransaction.t()
          | StartMining.t()
          | AddMiningContext.t()
          | CrossValidate.t()
          | CrossValidationDone.t()
          | ReplicateTransaction.t()
          | GetLastTransaction.t()
          | GetTransactionInputs.t()
          | GetTransactionChainLength.t()
          | GetFirstTransactionAddress.t()
          | FirstTransactionAddress.t()
          | NotifyEndOfNodeSync.t()
          | GetLastTransactionAddress.t()
          | NotifyLastTransactionAddress.t()
          | Ping.t()
          | GetBeaconSummary.t()
          | NewBeaconSlot.t()
          | GetBeaconSummaries.t()
          | RegisterBeaconUpdates.t()
          | BeaconUpdate.t()
          | TransactionSummaryMessage.t()
          | ReplicationAttestationMessage.t()
          | GetGenesisAddress.t()
          | ValidationError.t()
          | GetCurrentSummaries.t()
          | GetCurrentReplicationAttestations.t()
          | GetBeaconSummariesAggregate.t()
          | NotifyPreviousChain.t()
          | ShardRepair.t()
          | GetNextAddresses.t()
          | ValidateTransaction.t()
          | ReplicatePendingTransactionChain.t()
          | AcknowledgeStorage.t()
          | GetTransactionSummary.t()
          | GetNetworkStats.t()
          | ValidateSmartContractCall.t()
          | GetDashboardData.t()
          | RequestChainLock.t()
          | UnlockChain.t()
          | UpdateLastAddress.t()
          | ProofOfValidationDone.t()
          | RequestReplicationSignature.t()
          | ProofOfReplicationDone.t()
          | ReplicationSignatureDone.t()

  @type response ::
          Ok.t()
          | NotFound.t()
          | TransactionList.t()
          | Transaction.t()
          | NodeList.t()
          | UnspentOutputList.t()
          | EncryptedStorageNonce.t()
          | BootstrappingNodes.t()
          | TransactionSummaryMessage.t()
          | LastTransactionAddress.t()
          | FirstPublicKey.t()
          | TransactionChainLength.t()
          | TransactionInputList.t()
          | TransactionSummaryList.t()
          | Error.t()
          | Summary.t()
          | BeaconSummaryList.t()
          | GenesisAddress.t()
          | SummaryAggregate.t()
          | AddressList.t()
          | NetworkStats.t()
          | SmartContractCallValidation.t()
          | DashboardData.t()
          | CurrentReplicationAttestations.t()

  @floor_upload_speed Application.compile_env!(:archethic, [__MODULE__, :floor_upload_speed])
  @content_max_size Application.compile_env!(:archethic, :transaction_data_content_max_size)

  @before_compile MessageId

  @doc """
  Extract the Message Struct name
  """
  @spec name(t()) :: String.t()
  def name(message) when is_struct(message) do
    message.__struct__
    |> Module.split()
    |> List.last()
  end

  @doc """
  Return timeout depending of message type
  """
  @spec get_timeout(__MODULE__.t()) :: non_neg_integer()
  def get_timeout(%GetTransaction{}), do: get_max_timeout()
  def get_timeout(%GetLastTransaction{}), do: get_max_timeout()
  def get_timeout(%NewTransaction{}), do: get_max_timeout()
  def get_timeout(%StartMining{}), do: get_max_timeout()
  def get_timeout(%ReplicateTransaction{}), do: get_max_timeout()
  def get_timeout(%ValidateTransaction{}), do: get_max_timeout()

  def get_timeout(%GetTransactionChain{}) do
    # As we use 10 transaction in the pagination we can estimate the max time
    get_max_timeout() * 10
  end

  #  def get_timeout(%GetBeaconSummaries{addresses: addresses}) do
  #    # We can expect high beacon summary where a transaction replication will contains a single UCO transfer
  #    # CALC: Tx address +  recipient address + tx type + tx timestamp + storage node public key + signature * 200 (max storage nodes)
  #    beacon_summary_high_estimation_bytes = 34 + 34 + 1 + 8 + (8 + 34 + 34 * 200)
  #    length(addresses) * trunc(beacon_summary_high_estimation_bytes / @floor_upload_speed * 1000)
  #  end

  def get_timeout(_), do: 3_000

  @doc """
  Return the maximum timeout for a full sized transaction
  """
  @spec get_max_timeout() :: non_neg_integer()
  def get_max_timeout do
    trunc(@content_max_size / @floor_upload_speed * 1_000)
  end

  @doc """
  Decode an encoded message
  """
  @spec decode(bitstring()) :: {t(), bitstring}
  def decode(<<255::8>>), do: raise("255 message type is reserved for stream EOF")

  @doc """
  Handle a P2P message by processing it and return list of responses to be streamed back to the client
  """
  @spec process(request(), Crypto.key()) :: response()
  def process(msg, key), do: msg.__struct__.process(msg, key)
end
