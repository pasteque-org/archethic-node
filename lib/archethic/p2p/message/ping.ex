defmodule Archethic.P2P.Message.Ping do
  @moduledoc """
  Represents a message using to test node availability
  """

  alias Archethic.Crypto
  alias Archethic.P2P.Message.Ok

  defstruct []

  @type t :: %__MODULE__{}

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{}, _), do: %Ok{}

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{}), do: <<>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::binary>>), do: {%__MODULE__{}, rest}
end
