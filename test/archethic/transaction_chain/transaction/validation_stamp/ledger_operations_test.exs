defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperationsTest do
  use ArchethicCase

  import ArchethicCase

  alias Archethic.Reward.MemTables.RewardTokens
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  doctest LedgerOperations

  setup do
    start_supervised!(RewardTokens)
    :ok
  end

  describe "serialization" do
    test "should be able to serialize and deserialize" do
      now = DateTime.utc_now(:millisecond)

      ops = %LedgerOperations{
        fee: 10_000_000,
        transaction_movements: [
          %TransactionMovement{version: 1, to: random_address(), amount: 102_000_000, type: :UCO}
        ],
        unspent_outputs: [
          %UnspentOutput{
            version: 1,
            from: random_address(),
            amount: 200_000_000,
            type: :UCO,
            timestamp: now
          }
        ],
        consumed_inputs: [
          %UnspentOutput{from: random_address(), amount: 200_000_000, type: :UCO, timestamp: now}
        ]
      }

      assert {^ops, <<>>} = ops |> LedgerOperations.serialize() |> LedgerOperations.deserialize()
    end
  end
end
