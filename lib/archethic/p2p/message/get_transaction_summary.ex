defmodule Archethic.P2P.Message.GetTransactionSummary do
  @moduledoc """
  Represents a message to get a transaction summary from a transaction address
  """
  alias Archethic.Crypto
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.TransactionSummaryMessage
  alias Archethic.TransactionChain
  alias Archethic.Utils

  @enforce_keys [:address]
  defstruct [:address]

  @type t :: %__MODULE__{
          address: binary()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: TransactionSummaryMessage.t() | NotFound.t()
  def process(%__MODULE__{address: address}, _) do
    case TransactionChain.get_transaction_summary(address) do
      {:ok, summary} ->
        TransactionSummaryMessage.from_transaction_summary(summary)

      {:error, :not_found} ->
        %NotFound{}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address}) do
    <<address::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%__MODULE__{address: address}, rest}
  end
end
