defmodule Archethic.Utils.Regression do
  @moduledoc """
  Run some regression test to ensure the right behavior of the system
  """
  require Logger

  alias Archethic.Utils

  alias Archethic.Utils.Regression.Playbook.UCO
  alias Archethic.Utils.Regression.Playbook.SmartContract
  alias Archethic.Utils.Regression.Benchmark.WasmSmartContractTrigger
  alias Archethic.Utils.Regression.Benchmark.EndToEndValidation
  alias Archethic.Utils.Regression.Benchmark.P2PMessage

  @playbooks [UCO, SmartContract]
  @benchmarks [
    P2PMessage,
    WasmSmartContractTrigger,
    EndToEndValidation
  ]

  def run_playbooks(node, opts \\ []) do
    Logger.debug("Running playbooks on #{inspect(node)} with #{inspect(opts)}")

    Enum.each(@playbooks, fn playbook ->
      playbook.play!(node, opts)
      Process.sleep(100)
    end)
  end

  def run_benchmarks(node, opts \\ []) do
    Logger.debug("Running benchmarks on #{inspect(node)} with #{inspect(opts)}")

    tag = Time.utc_now() |> Time.truncate(:second) |> Time.to_string()

    benchmarks_to_run = get_benchmarks_to_run(opts)

    if Enum.empty?(benchmarks_to_run),
      do: Logger.warn("No benchmarks to run"),
      else: Enum.each(benchmarks_to_run, &run_benchmark(&1, node, opts, tag))
  end

  # Helper function to determine which benchmarks to run
  defp get_benchmarks_to_run(opts) do
    case Keyword.get(opts, :only, []) do
      [] -> @benchmarks
      benchmark_names -> filter_benchmarks_by_names(benchmark_names)
    end
  end

  # Helper function to filter benchmarks by name
  defp filter_benchmarks_by_names(benchmark_names) do
    benchmark_map =
      Map.new(@benchmarks, fn benchmark -> {benchmark_name(benchmark), benchmark} end)

    Enum.reduce(benchmark_names, [], fn name, acc ->
      case Map.get(benchmark_map, name) do
        nil ->
          Logger.warn("Unknown benchmark: #{name}")
          acc

        benchmark ->
          [benchmark | acc]
      end
    end)
    |> Enum.reverse()
  end

  # Helper function to run a single benchmark
  defp run_benchmark(benchmark, node, opts, tag) do
    Logger.info("Running benchmark #{benchmark}")
    save = Utils.mut_dir("#{benchmark}.benchee")
    save_opts = [title: benchmark, save: [path: save, tag: tag], load: save]
    {bench_plan, bench_opts} = benchmark.plan(node, opts)

    Benchee.run(bench_plan, Keyword.merge(save_opts, bench_opts))
  end

  # Helper to get a standardized benchmark name
  defp benchmark_name(benchmark) when is_atom(benchmark) do
    benchmark |> Atom.to_string() |> String.split(".") |> List.last()
  end

  def get_metrics(host, port, range) do
    Logger.debug("Collecting metrics for last #{range} seconds")

    base_url = "http://#{host}:#{port}"

    with {:ok, %Req.Response{body: %{"status" => "success", "data" => metrics}}} <-
           Req.get(url: "#{base_url}/api/v1/label/__name__/values"),
         {:ok, data} <- collect_metrics(base_url, metrics, range) do
      {:ok, data}
    else
      {:ok, %Req.Response{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_metric(metric, range, resolution \\ 5),
    do: "/api/v1/query?query=#{metric}[#{range}s:#{resolution}s]"

  defp collect_metrics(base_url, metrics, range, acc \\ [])
  defp collect_metrics(_base_url, [], _range, acc), do: {:ok, acc}

  defp collect_metrics(base_url, [m | metrics], range, acc) do
    url = "#{base_url}#{query_metric(m, range)}"

    case Req.get(url: url) do
      {:ok, %Req.Response{body: %{"status" => "success", "data" => %{"result" => data}}}} ->
        collect_metrics(base_url, metrics, range, [data | acc])

      {:ok, %Req.Response{body: body}} ->
        {:error, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @node_up_timeout 5 * 60 * 1000

  def nodes_up?(nodes) do
    nodes
    |> Task.async_stream(&node_up?/1, ordered: false, timeout: @node_up_timeout)
    |> Enum.into([])
    |> Enum.all?(&(&1 == {:ok, true}))
  end

  def node_up?(node, start \\ System.monotonic_time(:millisecond), timeout \\ 5 * 60_000)

  def node_up?(node, start, timeout) do
    Logger.debug("Ensure #{inspect(node)} are up and ready")

    case Req.get(base_url: node, url: "up") do
      {:ok, %Req.Response{body: "up"}} ->
        true

      {:ok, _} ->
        Process.sleep(250)
        node_up?(node, start, timeout)

      {:error, _} ->
        Process.sleep(500)

        if System.monotonic_time(:millisecond) - start < timeout do
          node_up?(node, start, timeout)
        else
          false
        end
    end
  end
end
