defmodule Archethic.OracleChainTest do
  use ArchethicCase

  import Mox

  alias Archethic.OracleChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  test "valid_services_content?/1 should verify the oracle transaction's content correctness" do
    expect(MockUCOPrice, :verify?, fn _ -> true end)
    content = JSON.encode!(%{"uco" => %{"eur" => 0.20, "usd" => 0.12}})

    assert true == OracleChain.valid_services_content?(content)
  end

  test "valid_summary?/2 should validate the summary content" do
    last_update_at = DateTime.to_unix(DateTime.utc_now())

    content = JSON.encode!(%{last_update_at => %{"uco" => %{"eur" => 0.20, "usd" => 0.12}}})

    chain = [
      %Transaction{
        type: :oracle,
        data: %TransactionData{
          content: JSON.encode!(%{"uco" => %{"eur" => 0.20, "usd" => 0.12}})
        },
        validation_stamp: %ValidationStamp{
          timestamp: DateTime.from_unix!(last_update_at)
        }
      }
    ]

    expect(MockUCOPrice, :parse_data, fn _ ->
      {:ok, %{"eur" => 0.20, "usd" => 0.12}}
    end)

    assert true == OracleChain.valid_summary?(content, chain)
  end
end
