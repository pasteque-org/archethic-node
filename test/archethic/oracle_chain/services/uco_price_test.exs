defmodule Archethic.OracleChain.Services.UCOPriceTest do
  use ArchethicCase, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Archethic.OracleChain.ServiceCacheSupervisor
  alias Archethic.OracleChain.Services.UCOPrice

  setup :verify_on_exit!
  setup :set_mox_global

  describe "fetch/0" do
    test "should retrieve some data and build a map with the oracle name in it" do
      expect(MockUCOProvider1, :fetch, fn _ ->
        {:ok, %{"usd" => [0.12], "eur" => [0.20]}}
      end)

      expect(MockUCOProvider2, :fetch, fn _ ->
        {:ok, %{"usd" => [0.12], "eur" => [0.20]}}
      end)

      ServiceCacheSupervisor.start_link()

      Process.sleep(10)

      assert {:ok, %{"eur" => 0.20, "usd" => 0.12}} = UCOPrice.fetch()
    end

    test "should retrieve some data and build a map with the oracle name in it and keep the precision to 5" do
      expect(MockUCOProvider1, :fetch, fn _ ->
        {:ok, %{"usd" => [0.123454789], "eur" => [0.123456789]}}
      end)

      expect(MockUCOProvider2, :fetch, fn _ ->
        {:ok, %{"usd" => [0.123454789], "eur" => [0.123456789]}}
      end)

      ServiceCacheSupervisor.start_link()

      Process.sleep(10)

      assert {:ok, %{"eur" => 0.12345678, "usd" => 0.12345478}} = UCOPrice.fetch()
    end

    test "should handle a service timing out" do
      expect(MockUCOProvider1, :fetch, fn _ ->
        {:ok, %{"usd" => [0.20], "eur" => [0.20]}}
      end)

      expect(MockUCOProvider2, :fetch, fn _ ->
        :timer.sleep(5_000)
        {:ok, {:error, :error_message}}
      end)

      ServiceCacheSupervisor.start_link()

      Process.sleep(10)

      assert {:ok, %{"eur" => 0.20, "usd" => 0.20}} = UCOPrice.fetch()
    end

    test "should return the median value when multiple providers queried" do
      expect(MockUCOProvider1, :fetch, fn _ ->
        {:ok, %{"usd" => [0.20], "eur" => [0.10]}}
      end)

      expect(MockUCOProvider2, :fetch, fn _ ->
        {:ok, %{"usd" => [0.30], "eur" => [0.40]}}
      end)

      ServiceCacheSupervisor.start_link()

      Process.sleep(10)

      assert {:ok, %{"eur" => 0.25, "usd" => 0.25}} = UCOPrice.fetch()
    end

    test "should return an error if any service responded the request" do
      expect(MockUCOProvider1, :fetch, fn _ ->
        {:error, "error"}
      end)

      expect(MockUCOProvider2, :fetch, fn _ ->
        {:error, "reason"}
      end)

      ServiceCacheSupervisor.start_link()

      Process.sleep(10)

      assert {:error, "no data fetched from any service"} = UCOPrice.fetch()
    end
  end

  describe "verify/1" do
    test "should return true if the prices are the good one" do
      expect(MockUCOProvider1, :fetch, fn _ ->
        {:ok, %{"usd" => [0.20], "eur" => [0.10]}}
      end)

      expect(MockUCOProvider2, :fetch, fn _ ->
        {:ok, %{"usd" => [0.30], "eur" => [0.40]}}
      end)

      ServiceCacheSupervisor.start_link()

      Process.sleep(10)

      assert UCOPrice.verify?(%{"eur" => 0.25, "usd" => 0.25})
    end

    test "should return false if the prices have deviated" do
      expect(MockUCOProvider1, :fetch, fn _ ->
        {:ok, %{"usd" => [0.30], "eur" => [0.20]}}
      end)

      expect(MockUCOProvider2, :fetch, fn _ ->
        {:ok, %{"usd" => [0.40], "eur" => [0.50]}}
      end)

      ServiceCacheSupervisor.start_link()

      Process.sleep(10)

      refute UCOPrice.verify?(%{"eur" => 0.25, "usd" => 0.25})
    end
  end

  test "verify?/1 should return false when no data are returned from all providers" do
    expect(MockUCOProvider1, :fetch, fn _ ->
      {:error, ""}
    end)

    expect(MockUCOProvider2, :fetch, fn _ ->
      {:error, ""}
    end)

    ServiceCacheSupervisor.start_link()

    Process.sleep(10)

    {result, log} = with_log(fn -> UCOPrice.verify?(%{"eur" => 0.25, "usd" => 0.25}) end)
    assert result == false
    assert log =~ "Cannot fetch UCO price - reason: no data fetched from any service."
  end

  test "should report values even if a provider returns an error" do
    expect(MockUCOProvider1, :fetch, fn _ ->
      {:error, ""}
    end)

    expect(MockUCOProvider2, :fetch, fn _ ->
      {:ok, %{"eur" => [0.25], "usd" => [0.25]}}
    end)

    ServiceCacheSupervisor.start_link()

    Process.sleep(10)

    assert UCOPrice.verify?(%{"eur" => 0.25, "usd" => 0.25})
  end
end
