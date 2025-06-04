defmodule Archethic.P2P.Message.TransactionSummaryList do
  @moduledoc """
  Represents a message with a list of transaction summary
  """
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  defstruct transaction_summaries: []

  @type t() :: %__MODULE__{
          transaction_summaries: list(TransactionSummary.t())
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction_summaries: transaction_summaries}) do
    transaction_summaries_bin =
      transaction_summaries
      |> Enum.map(&TransactionSummary.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_transaction_summaries_len = transaction_summaries |> length() |> VarInt.from_value()

    <<encoded_transaction_summaries_len::binary, transaction_summaries_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {nb_transaction_summaries, rest} = VarInt.get_value(rest)

    {transaction_summaries, rest} =
      Utils.deserialize_transaction_summaries(rest, nb_transaction_summaries, [])

    {
      %__MODULE__{
        transaction_summaries: transaction_summaries
      },
      rest
    }
  end
end
