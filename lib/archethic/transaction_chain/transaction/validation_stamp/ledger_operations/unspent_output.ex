defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput do
  @moduledoc """
  Represents an unspent output from a transaction.
  """
  alias Archethic.Contracts.Contract.State
  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement.Type,
    as: TransactionMovementType

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @version 1

  defstruct [:amount, :from, :type, :timestamp, :encoded_payload, version: @version]

  @type utxo_type :: TransactionMovementType.t() | :state | :call

  @type t :: %__MODULE__{
          version: pos_integer(),
          amount: nil | non_neg_integer(),
          from: nil | Crypto.versioned_hash(),
          type: utxo_type(),
          timestamp: DateTime.t(),
          encoded_payload: nil | binary()
        }

  @doc """
  Return the type as a string (used in logs).
  """
  @spec type_to_str(utxo_type()) :: String.t()
  def type_to_str(:UCO), do: "UCO"
  def type_to_str(:state), do: "state"
  def type_to_str(:call), do: "call"

  def type_to_str({:token, token_address, 0}), do: "token(#{Base.encode16(token_address)})"

  def type_to_str({:token, token_address, token_id}),
    do: "nft(#{Base.encode16(token_address)}, #{token_id})"

  @doc """
  Serialize unspent output into binary format
  """
  @spec serialize(utxo :: t()) :: bitstring()
  def serialize(%__MODULE__{version: version, timestamp: timestamp, from: from} = utxo) do
    <<version::16, from::binary, DateTime.to_unix(timestamp, :millisecond)::64,
      serialize_type(utxo)::bitstring>>
  end

  defp serialize_type(%__MODULE__{type: :state, encoded_payload: encoded_payload}) do
    encoded_payload_size = encoded_payload |> bit_size() |> Utils.VarInt.from_value()
    <<1::8, encoded_payload_size::binary, encoded_payload::bitstring>>
  end

  defp serialize_type(%__MODULE__{type: :call}) do
    <<2::8>>
  end

  defp serialize_type(%__MODULE__{type: type, amount: amount}) do
    <<0::8, TransactionMovementType.serialize(type)::binary, VarInt.from_value(amount)::binary>>
  end

  @doc """
  Deserialize an encoded unspent output
  """
  @spec deserialize(data :: bitstring()) :: {t(), bitstring}
  def deserialize(<<version::16, rest::bitstring>>) do
    {from, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)

    utxo = %__MODULE__{
      version: version,
      from: from,
      timestamp: DateTime.from_unix!(timestamp, :millisecond)
    }

    {fields, rest} = deserialize_type(rest)

    {Map.merge(utxo, fields), rest}
  end

  defp deserialize_type(<<0::8, rest::bitstring>>) do
    {type, rest} = TransactionMovementType.deserialize(rest)
    {amount, rest} = VarInt.get_value(rest)

    {%{type: type, amount: amount}, rest}
  end

  defp deserialize_type(<<1::8, rest::bitstring>>) do
    {encoded_payload_size, rest} = Utils.VarInt.get_value(rest)
    <<encoded_payload::bitstring-size(encoded_payload_size), rest::bitstring>> = rest

    {%{type: :state, encoded_payload: encoded_payload}, rest}
  end

  defp deserialize_type(<<2::8, rest::bitstring>>) do
    {%{type: :call}, rest}
  end

  @doc """
  Build %UnspentOutput struct from map

  ## Examples

      iex> %{
      ...>   from:
      ...>     <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...>       159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>   amount: 1_050_000_000,
      ...>   type: :UCO,
      ...>   timestamp: ~U[2022-10-11 07:27:22.815Z],
      ...>   version: 1
      ...> }
      ...> |> UnspentOutput.cast()
      %UnspentOutput{
        from:
          <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194, 159,
            19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 1_050_000_000,
        type: :UCO,
        timestamp: ~U[2022-10-11 07:27:22.815Z],
        version: 1
      }

      iex> %{
      ...>   from:
      ...>     <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...>       159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>   amount: 1_050_000_000,
      ...>   type:
      ...>     {:token,
      ...>      <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...>        197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>, 0}
      ...> }
      ...> |> UnspentOutput.cast()
      %UnspentOutput{
        from:
          <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194, 159,
            19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 1_050_000_000,
        type:
          {:token,
           <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74, 197,
             46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>, 0},
        timestamp: nil,
        version: 1
      }
  """
  @spec cast(map()) :: __MODULE__.t()
  def cast(%{} = unspent_output) do
    %__MODULE__{
      version: Map.get(unspent_output, :version, @version),
      from: Map.get(unspent_output, :from),
      encoded_payload: Map.get(unspent_output, :encoded_payload),
      amount: Map.get(unspent_output, :amount),
      type: Map.get(unspent_output, :type),
      timestamp: Map.get(unspent_output, :timestamp)
    }
  end

  @doc """
  Convert %UnspentOutput{} Struct to a Map

  ## Examples

      iex> %UnspentOutput{
      ...>   from:
      ...>     <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...>       159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>   amount: 1_050_000_000,
      ...>   type: :UCO,
      ...>   timestamp: ~U[2022-10-11 07:27:22.815Z],
      ...>   version: 1
      ...> }
      ...> |> UnspentOutput.to_map()
      %{
        from:
          <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194, 159,
            19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 1_050_000_000,
        type: "UCO",
        timestamp: ~U[2022-10-11 07:27:22.815Z],
        version: 1
      }

      iex> %UnspentOutput{
      ...>   from:
      ...>     <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194,
      ...>       159, 19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
      ...>   amount: 1_050_000_000,
      ...>   type:
      ...>     {:token,
      ...>      <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74,
      ...>        197, 46, 99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>, 0},
      ...>   version: 1
      ...> }
      ...> |> UnspentOutput.to_map()
      %{
        from:
          <<0, 0, 214, 107, 17, 107, 227, 11, 17, 43, 204, 48, 78, 129, 145, 126, 45, 68, 194, 159,
            19, 92, 240, 29, 37, 105, 183, 232, 56, 42, 163, 236, 251, 186>>,
        amount: 1_050_000_000,
        type: "token",
        token_address:
          <<0, 49, 101, 72, 154, 152, 3, 174, 47, 2, 35, 7, 92, 122, 206, 185, 71, 140, 74, 197, 46,
            99, 117, 89, 96, 100, 20, 0, 34, 181, 215, 143, 175>>,
        token_id: 0,
        timestamp: nil,
        version: 1
      }
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{version: version, from: from, timestamp: timestamp} = utxo) do
    utxo
    |> map_type()
    |> Map.merge(%{
      version: version,
      from: from,
      timestamp: timestamp
    })
  end

  defp map_type(%__MODULE__{amount: amount, type: :UCO}) do
    %{amount: amount, type: "UCO"}
  end

  defp map_type(%__MODULE__{amount: amount, type: {:token, token_address, token_id}}) do
    %{
      amount: amount,
      type: "token",
      token_address: token_address,
      token_id: token_id
    }
  end

  defp map_type(%__MODULE__{type: :state, encoded_payload: encoded_payload}) do
    %{
      type: "state",
      state: encoded_payload |> State.deserialize() |> elem(0)
    }
  end

  defp map_type(%__MODULE__{type: :call}) do
    %{type: "call"}
  end

  @doc """
  Return a hash of the utxo
  Used for cheap comparaison
  """
  @spec hash(utxo :: t()) :: binary()
  def hash(utxo) do
    utxo |> serialize() |> Utils.wrap_binary() |> then(&:crypto.hash(:sha256, &1))
  end

  @doc """
  Compare two UnspentOutput
  This function is usefull when using Enum.sort(utxos, {:asc, UnspentOutput})
  """
  @spec compare(utxo1 :: t(), utxo2 :: t()) :: :lt | :gt | :eq
  def compare(utxo1, utxo2) when utxo1 == utxo2, do: :eq

  def compare(
        %__MODULE__{
          version: version1,
          timestamp: timestamp1,
          from: from1,
          type: type1,
          encoded_payload: encoded_payload1
        },
        %__MODULE__{
          version: version2,
          timestamp: timestamp2,
          from: from2,
          type: type2,
          encoded_payload: encoded_payload2
        }
      ) do
    with :eq <- compare_version(version1, version2),
         :eq <- compare_time(timestamp1, timestamp2),
         :eq <- compare_from(from1, from2),
         :eq <- compare_type(type1, type2) do
      compare_encoded_payload(encoded_payload1, encoded_payload2)
    end
  end

  defp compare_version(version1, version2) when version1 == version2, do: :eq
  defp compare_version(version1, version2) when version1 < version2, do: :lt
  defp compare_version(_, _), do: :gt

  defp compare_time(time1, time2), do: DateTime.compare(time1, time2)

  defp compare_from(from1, from2) when from1 == from2, do: :eq
  defp compare_from(from1, from2) when from1 < from2, do: :lt
  defp compare_from(_, _), do: :gt

  # state => call => UCO => token (address => id)
  defp compare_type(type1, type2) when type1 == type2, do: :eq
  defp compare_type(:state, _), do: :lt
  defp compare_type(_, :state), do: :gt
  defp compare_type(:call, _), do: :lt
  defp compare_type(_, :call), do: :gt
  defp compare_type(:UCO, _), do: :lt
  defp compare_type(_, :UCO), do: :gt
  defp compare_type({:token, addr1, _}, {:token, addr2, _}) when addr1 < addr2, do: :lt
  defp compare_type({:token, addr1, _}, {:token, addr2, _}) when addr1 > addr2, do: :gt
  defp compare_type({:token, _, id1}, {:token, _, id2}) when id1 < id2, do: :lt
  defp compare_type(_, _), do: :gt

  defp compare_encoded_payload(p1, p2) when p1 < p2, do: :lt
  defp compare_encoded_payload(p1, p2) when p1 > p2, do: :gt
  defp compare_encoded_payload(_, _), do: :eq
end
