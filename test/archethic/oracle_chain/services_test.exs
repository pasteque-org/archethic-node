defmodule Archethic.OracleChain.ServicesTest do
  use ExUnit.Case

  import Mox

  alias Archethic.OracleChain.Services

  describe "fetch_new_data/1" do
    test "should return the new data when no previous content" do
      expect(MockUCOPrice, :fetch, fn ->
        {:ok, %{"eur" => 0.20, "usd" => 0.12}}
      end)

      assert %{uco: %{"eur" => 0.20, "usd" => 0.12}} = Services.fetch_new_data()
    end

    test "should not return the new data when the previous content is the same" do
      expect(MockUCOPrice, :fetch, fn ->
        {:ok, %{"eur" => 0.20, "usd" => 0.12}}
      end)

      assert %{} = Services.fetch_new_data(%{uco: %{"eur" => 0.20, "usd" => 0.12}})
    end

    test "should return the new data when the previous content is not the same" do
      expect(MockUCOPrice, :fetch, fn ->
        {:ok, %{"eur" => 0.20, "usd" => 0.12}}
      end)

      assert %{uco: %{"eur" => 0.20, "usd" => 0.12}} =
               Services.fetch_new_data(%{"uco" => %{"eur" => 0.19, "usd" => 0.15}})
    end

    test "should return not return new data when the service return an error" do
      expect(MockUCOPrice, :fetch, fn ->
        {:error, "error reason"}
      end)

      assert %{} = Services.fetch_new_data(%{"uco" => %{"eur" => 0.19, "usd" => 0.15}})
    end

    test "should return not return new data when the service return an empty map" do
      expect(MockUCOPrice, :fetch, fn ->
        {:ok, %{}}
      end)

      assert %{} = Services.fetch_new_data(%{"uco" => %{"eur" => 0.19, "usd" => 0.15}})
    end
  end

  test "verify_correctness?/1 should true when the data is correct" do
    expect(MockUCOPrice, :verify?, fn _ ->
      true
    end)

    assert Services.verify_correctness?(%{"uco" => %{"eur" => 0.20, "usd" => 0.12}})
  end
end
