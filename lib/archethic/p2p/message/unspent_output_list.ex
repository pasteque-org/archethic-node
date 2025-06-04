defmodule Archethic.P2P.Message.UnspentOutputList do
  @moduledoc """
  Represents a message with a list of unspent outputs
  """
  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.Utils.VarInt

  defstruct [:last_chain_sync_date, unspent_outputs: [], more?: false, offset: nil]

  @type t :: %__MODULE__{
          unspent_outputs: list(UnspentOutput.t()),
          more?: boolean(),
          offset: Crypto.sha256() | nil,
          last_chain_sync_date: DateTime.t()
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        unspent_outputs: unspent_outputs,
        more?: more?,
        offset: offset,
        last_chain_sync_date: last_chain_sync_date
      }) do
    unspent_outputs_bin =
      unspent_outputs
      |> Stream.map(&UnspentOutput.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_unspent_outputs_length =
      unspent_outputs
      |> Enum.count()
      |> VarInt.from_value()

    more_bit = if more?, do: 1, else: 0

    offset_bin = if is_nil(offset), do: <<0::1>>, else: <<1::1, offset::binary>>

    <<encoded_unspent_outputs_length::binary, unspent_outputs_bin::bitstring, more_bit::1,
      offset_bin::bitstring, DateTime.to_unix(last_chain_sync_date, :millisecond)::64>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {nb_unspent_outputs, rest} = VarInt.get_value(rest)

    {unspent_outputs, <<more_bit::1, rest::bitstring>>} =
      deserialize_unspent_output_list(rest, nb_unspent_outputs, [])

    more? = more_bit == 1

    {offset, <<last_chain_sync_date::64, rest::bitstring>>} =
      case rest do
        <<0::1, rest::bitstring>> -> {nil, rest}
        <<1::1, offset::binary-size(32), rest::bitstring>> -> {offset, rest}
      end

    {%__MODULE__{
       unspent_outputs: unspent_outputs,
       more?: more?,
       offset: offset,
       last_chain_sync_date: DateTime.from_unix!(last_chain_sync_date, :millisecond)
     }, rest}
  end

  defp deserialize_unspent_output_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_unspent_output_list(rest, nb_unspent_outputs, acc)
       when length(acc) == nb_unspent_outputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_unspent_output_list(rest, nb_unspent_outputs, acc) do
    {unspent_output, rest} = UnspentOutput.deserialize(rest)

    deserialize_unspent_output_list(rest, nb_unspent_outputs, [unspent_output | acc])
  end
end
