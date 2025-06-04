defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutputTest do
  use ArchethicCase

  import ArchethicCase

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.Utils

  doctest UnspentOutput

  describe "serialization/deserialization workflow" do
    test "should work for :uco" do
      input = %UnspentOutput{
        amount: Utils.to_bigint(130),
        type: :UCO,
        from: random_address(),
        timestamp: DateTime.utc_now(:millisecond)
      }

      assert {^input, _} = input |> UnspentOutput.serialize() |> UnspentOutput.deserialize()
    end

    test "should work for :token" do
      input = %UnspentOutput{
        amount: Utils.to_bigint(1000),
        type: {:token, random_address(), 0},
        from: random_address(),
        timestamp: DateTime.utc_now(:millisecond)
      }

      assert {^input, _} = input |> UnspentOutput.serialize() |> UnspentOutput.deserialize()
    end

    test "should work for :state" do
      input = %UnspentOutput{
        type: :state,
        from: random_address(),
        timestamp: DateTime.utc_now(:millisecond),
        encoded_payload: :crypto.strong_rand_bytes(10)
      }

      assert {^input, _} = input |> UnspentOutput.serialize() |> UnspentOutput.deserialize()
    end

    test "should work for :call" do
      input = %UnspentOutput{
        type: :call,
        from: random_address(),
        timestamp: DateTime.utc_now(:millisecond)
      }

      assert {^input, _} = input |> UnspentOutput.serialize() |> UnspentOutput.deserialize()
    end
  end
end
