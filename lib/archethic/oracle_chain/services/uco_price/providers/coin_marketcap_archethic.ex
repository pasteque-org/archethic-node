defmodule Archethic.OracleChain.Services.UCOPrice.Providers.CoinMarketCapArchethic do
  @moduledoc false

  @behaviour Archethic.OracleChain.Services.UCOPrice.Providers.Impl

  alias Archethic.OracleChain.Services.UCOPrice.Providers.Impl

  require Logger

  @impl Impl
  @spec fetch(list(binary())) :: {:ok, %{required(String.t()) => any()}} | {:error, any()}
  def fetch(pairs) when is_list(pairs) do
    req =
      Req.new(
        url: "https://coinmarketcap.com/currencies/archethic/",
        connect_options: [timeout: 1000],
        receive_timeout: 2000,
        headers: %{
          "user-agent" =>
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.169 Safari/537.36",
          "accept" => "text/html",
          "accept-language" => "en-US,en;q=0.9,es;q=0.8",
          "upgrade-insecure-requests" => "1"
        }
      )

    returned_prices =
      Archethic.task_supervisors()
      |> Task.Supervisor.async_stream_nolink(
        pairs,
        fn pair ->
          req = Req.merge(req, headers: %{"Cookie" => "currency=#{pair}"})

          with {:ok, %Req.Response{status: 200, body: body}} <- Req.get(req),
               {:ok, document} <- Floki.parse_document(body) do
            price =
              Enum.reduce_while(extract_methods(), nil, fn extract_fn, acc ->
                try do
                  {:halt, extract_fn.(document)}
                rescue
                  _ ->
                    {:cont, acc}
                catch
                  _ ->
                    {:cont, acc}
                end
              end)

            if is_number(price) do
              {:ok, {pair, [price]}}
            else
              {:error, :not_a_number}
            end
          else
            {:ok, %Req.Response{status: status}} -> {:error, status}
            {:error, _} = e -> e
          end
        end
      )
      |> Stream.filter(&match?({:ok, {:ok, _}}, &1))
      |> Map.new(fn {:ok, {:ok, val}} -> val end)

    {:ok, returned_prices}
  end

  defp extract_methods do
    [
      &extract_method1/1,
      &extract_method2/1,
      &extract_method3/1,
      # if every other failed
      &fallback_error/1
    ]
  end

  defp extract_method1(document) do
    document
    |> Floki.find("div.priceTitle > div.priceValue > span")
    |> Floki.text()
    |> String.graphemes()
    |> Enum.filter(&(&1 in [".", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]))
    |> Enum.into("")
    |> String.to_float()
  end

  defp extract_method2(document) do
    regex = ~r/price today is (.+) with a/

    document
    |> Floki.find("meta[name=description]")
    |> Floki.attribute("content")
    |> Enum.join()
    |> then(&Regex.run(regex, &1, capture: :all_but_first))
    |> Enum.join()
    |> String.graphemes()
    |> Enum.filter(&(&1 in [".", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]))
    |> Enum.into("")
    |> String.to_float()
  end

  defp extract_method3(document) do
    document
    |> Floki.find("#__NEXT_DATA__")
    |> Floki.text(js: true)
    |> JSON.decode!()
    |> get_in(["props", "pageProps", "info", "statistics", "price"])
  end

  defp fallback_error(document) do
    path = "/tmp/coinmarketcap.html"

    case File.write(path, Floki.raw_html(document, pretty: true)) do
      :ok ->
        Logger.warning(
          "Coinmarketcap failed to be parsed, you may find the page we receive at #{path}"
        )

      {:error, _posix} ->
        Logger.warning("Coinmarketcap failed to be parsed")
    end

    throw("coinmarketcap failed to parse")
  end
end
