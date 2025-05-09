defmodule Archethic.Contracts.Contract.State do
  @moduledoc """
  Module to manipulate the contract state
  """

  @version 1
  defstruct [:data, version: @version]

  alias Archethic.Utils.TypedEncoding
  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  # 3 MB
  @max_compressed_state_size 3 * 1024 * 1024

  @type t() :: %__MODULE__{
          version: pos_integer(),
          data: map()
        }

  @type encoded() :: binary()

  @spec empty() :: t()
  def empty(), do: %__MODULE__{version: @version, data: %{}}

  @spec empty?(state :: t()) :: boolean()
  def empty?(%__MODULE__{data: data}) do
    %__MODULE__{data: empty_data} = empty()
    data == empty_data
  end

  @spec wrap_data(data :: map()) :: t()
  def wrap_data(data), do: %__MODULE__{version: @version, data: data}

  @spec valid_size?(encoded_state :: encoded()) :: boolean()
  def valid_size?(encoded_state), do: byte_size(encoded_state) <= @max_compressed_state_size

  @doc """
  Serialize the given state
  """
  @spec serialize(state :: t()) :: encoded()
  def serialize(%__MODULE__{version: version, data: data}) do
    encoded_payload =
      TypedEncoding.serialize(data, :compact) |> Utils.wrap_binary() |> :zlib.zip()

    encoded_payload_size = encoded_payload |> byte_size() |> VarInt.from_value()

    <<version::16, encoded_payload_size::binary, encoded_payload::binary>>
  end

  @doc """
  Deserialize the state
  """
  @spec deserialize(bitstring :: bitstring()) :: {t(), bitstring()}
  def deserialize(<<version::16, rest::bitstring>>) do
    {encoded_payload_size, rest} = VarInt.get_value(rest)

    <<encoded_payload::binary-size(encoded_payload_size), rest::bitstring>> = rest

    {data, _} = :zlib.unzip(encoded_payload) |> TypedEncoding.deserialize(:compact)

    {%__MODULE__{version: version, data: data}, rest}
  end
end
