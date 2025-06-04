defmodule Archethic.P2P.Message.BeaconSummaryList do
  @moduledoc """
  Represents a message with a list of beacon summaries
  """

  alias Archethic.BeaconChain.Summary
  alias Archethic.Utils.VarInt

  defstruct summaries: []

  @type t :: %__MODULE__{
          summaries: list(Summary.t())
        }

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{summaries: summaries}) do
    summaries_bin =
      summaries
      |> Stream.map(&Summary.serialize/1)
      |> Enum.to_list()
      |> :erlang.list_to_bitstring()

    encoded_summaries_length = summaries |> Enum.count() |> VarInt.from_value()

    <<encoded_summaries_length::binary, summaries_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {nb_summaries, rest} = VarInt.get_value(rest)
    {summaries, rest} = deserialize_summaries(rest, nb_summaries, [])

    {
      %__MODULE__{summaries: summaries},
      rest
    }
  end

  defp deserialize_summaries(rest, 0, _), do: {[], rest}

  defp deserialize_summaries(rest, nb_summaries, acc) when nb_summaries == length(acc),
    do: {Enum.reverse(acc), rest}

  defp deserialize_summaries(rest, nb_summaries, acc) do
    {summary, rest} = Summary.deserialize(rest)
    deserialize_summaries(rest, nb_summaries, [summary | acc])
  end
end
