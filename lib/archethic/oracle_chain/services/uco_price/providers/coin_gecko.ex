defmodule Archethic.OracleChain.Services.UCOPrice.Providers.Coingecko do
  @moduledoc false

  @behaviour Archethic.OracleChain.Services.UCOPrice.Providers.Impl

  alias Archethic.OracleChain.Services.UCOPrice.Providers.Impl

  require Logger

  @impl Impl
  @spec fetch(list(binary())) :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  def fetch(pairs) when is_list(pairs) do
    pairs_str = Enum.join(pairs, ",")

    url = "https://api.coingecko.com/api/v3/simple/price?ids=archethic&vs_currencies=#{pairs_str}"
    req_opts = [connect_options: [timeout: 1000], receive_timeout: 2000]

    with {:ok, %Req.Response{status: 200, body: body}} <- Req.get(url, req_opts),
         {:ok, prices} <- Map.fetch(body, "archethic") do
      formatted_prices =
        Map.new(prices, fn {pair, price} -> {pair, [price]} end)

      {:ok, formatted_prices}
    else
      {:ok, %Req.Response{status: status}} -> {:error, status}
      {:error, _} = e -> e
    end
  end
end
