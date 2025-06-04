defmodule Archethic.OracleChain.MemTableLoaderTest do
  use ArchethicCase

  alias Archethic.OracleChain.MemTable
  alias Archethic.OracleChain.MemTableLoader
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  describe "load_transaction/1" do
    test "should load an oracle transaction into the mem table" do
      assert :ok =
               MemTableLoader.load_transaction(%Transaction{
                 type: :oracle,
                 data: %TransactionData{
                   content: JSON.encode!(%{"uco" => %{"eur" => 0.02}})
                 },
                 validation_stamp: %ValidationStamp{
                   timestamp: DateTime.utc_now()
                 }
               })

      assert {:ok, %{"eur" => 0.02}, _} =
               MemTable.get_oracle_data("uco", DateTime.add(DateTime.utc_now(), 1000))
    end

    test "should load an oracle summary transaction and the related changes" do
      assert :ok =
               MemTableLoader.load_transaction(%Transaction{
                 type: :oracle_summary,
                 data: %TransactionData{
                   content:
                     JSON.encode!(%{
                       "1614677930" => %{"uco" => %{"eur" => 0.02}},
                       "1614677925" => %{"uco" => %{"eur" => 0.07}}
                     })
                 }
               })

      assert {:ok, %{"eur" => 0.07}, _} =
               MemTable.get_oracle_data("uco", DateTime.from_unix!(1_614_677_927))
    end
  end
end
