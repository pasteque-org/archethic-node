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
        timestamp: DateTime.utc_now(:millisecond)
      }

      assert {input, <<>>} ==
               input |> TransactionInput.serialize() |> TransactionInput.deserialize()
    end
  end
end
