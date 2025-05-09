defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutputTest do
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.Utils

  use ArchethicCase
  import ArchethicCase

  doctest UnspentOutput

  describe "serialization/deserialization workflow" do
    test "should work for :uco" do
      input = %UnspentOutput{
        amount: Utils.to_bigint(130),
        type: :UCO,
        from: random_address(),
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert {^input, _} = input |> UnspentOutput.serialize() |> UnspentOutput.deserialize()
    end

    test "should work for :token" do
      input = %UnspentOutput{
        amount: Utils.to_bigint(1000),
        type: {:token, random_address(), 0},
        from: random_address(),
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert {^input, _} = input |> UnspentOutput.serialize() |> UnspentOutput.deserialize()
    end

    test "should work for :state" do
      input = %UnspentOutput{
        type: :state,
        from: random_address(),
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond),
        encoded_payload: :crypto.strong_rand_bytes(10)
      }

      assert {^input, _} = input |> UnspentOutput.serialize() |> UnspentOutput.deserialize()
    end

    test "should work for :call" do
      input = %UnspentOutput{
        type: :call,
        from: random_address(),
        timestamp: DateTime.utc_now() |> DateTime.truncate(:millisecond)
      }

      assert {^input, _} = input |> UnspentOutput.serialize() |> UnspentOutput.deserialize()
    end
  end
end
