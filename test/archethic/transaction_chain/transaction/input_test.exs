defmodule Archethic.TransactionChain.TransactionInputTest do
  use ArchethicCase

  alias Archethic.TransactionChain.TransactionInput
  doctest TransactionInput

  describe "serialization/deserialization workflow" do
    test "should return the same transaction after serialization and deserialization" do
      input = %TransactionInput{
        amount: 1,
        type: :UCO,
        from: ArchethicCase.random_address(),
        spent?: true,
        timestamp: DateTime.utc_now()
      }

      revised_input = Map.update!(input, :timestamp, &DateTime.truncate(&1, :millisecond))

      assert {^revised_input, _} =
               revised_input |> TransactionInput.serialize() |> TransactionInput.deserialize()
    end
  end
end
