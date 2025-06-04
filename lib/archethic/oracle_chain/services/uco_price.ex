defmodule Archethic.OracleChain.Services.UCOPrice do
  @moduledoc """
  Define Oracle behaviors to support UCO Price feed oracle
  """

  @behaviour Archethic.OracleChain.Services.Impl

  alias Archethic.OracleChain.Services.Impl
  alias Archethic.OracleChain.Services.ProviderCacheSupervisor
  alias Archethic.Utils

  require Logger

  @pairs ["usd", "eur"]

  @impl Impl
  def cache_child_spec do
    Supervisor.child_spec({ProviderCacheSupervisor, providers: providers(), fetch_args: @pairs},
      id: CacheSupervisor
    )
  end

  def providers do
    :archethic |> Application.get_env(__MODULE__) |> Keyword.fetch!(:providers)
  end

  @impl Impl
  @spec fetch() :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  def fetch do
    # retrieve prices from configured providers and filter results marked as errors
    # Here stream looks like : [%{"eur"=>[0.44], "usd"=[0.32]}, ..., %{"eur"=>[0.42, 0.43], "usd"=[0.35]}]
    prices =
      providers()
      |> ProviderCacheSupervisor.get_values()
      |> Enum.reduce(%{}, &agregate_providers_data/2)
      |> Enum.reduce(%{}, fn {currency, values}, acc ->
        # Truncate price to 8 decimals
        price = values |> Utils.median() |> Utils.to_bigint() |> Utils.from_bigint()

        Map.put(acc, currency, price)
      end)

    if prices == %{} do
      {:error, "no data fetched from any service"}
    else
      {:ok, prices}
    end
  end

  defp agregate_providers_data(provider_results, acc) do
    Enum.reduce(provider_results, acc, fn
      {currency, values}, acc when values != [] ->
        Map.update(acc, String.downcase(currency), values, fn
          previous_values ->
            previous_values ++ values
        end)

      _, acc ->
        acc
    end)
  end

  @impl Impl
  @spec verify?(%{required(String.t()) => any()}) :: boolean
  def verify?(%{} = prices_prior) do
    case fetch() do
      {:error, reason} ->
        Logger.error("Cannot fetch UCO price - reason: #{reason}.")
        false

      {:ok, prices_now} ->
        Enum.all?(@pairs, fn pair ->
          compare_price(
            Map.fetch!(prices_prior, pair),
            Map.get(prices_now, pair, Map.get(prices_prior, pair, 0.0))
          )
        end)
    end
  end

  defp compare_price(price_prior, price_now) do
    deviation_threshold = 0.01

    deviation =
      [price_prior, price_now]
      |> Utils.standard_deviation()
      |> Float.round(3)

    if deviation < deviation_threshold do
      true
    else
      Logger.warning(
        "UCO price deviated from #{deviation} % - previous price: #{price_prior} - new price: #{price_now} "
      )

      false
    end
  end

  @impl Impl
  @spec parse_data(map()) :: {:ok, map()} | :error
  def parse_data(service_data) when is_map(service_data) do
    valid? =
      Enum.all?(service_data, fn
        {key, val} when key in @pairs and is_float(val) -> true
        _ -> false
      end)

    if valid?, do: {:ok, service_data}, else: :error
  end

  def parse_data(_), do: {:error, :invalid_data}
end
