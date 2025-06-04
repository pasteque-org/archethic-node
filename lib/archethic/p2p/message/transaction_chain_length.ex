defmodule Archethic.P2P.Message.TransactionChainLength do
  @moduledoc """
  Represents a message with the number of transactions from a chain
  """
  alias Archethic.Utils.VarInt

  defstruct [:length]

  @type t :: %__MODULE__{
          length: non_neg_integer()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{length: length}) do
    encoded_length = VarInt.from_value(length)
    <<encoded_length::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {length, rest} = VarInt.get_value(rest)

    {%__MODULE__{
       length: length
     }, rest}
  end
end
