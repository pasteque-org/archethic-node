defmodule Archethic.Utils.Regression do
  @moduledoc """
  Run some regression test to ensure the right behavior of the system
  """
  require Logger

  alias Archethic.Utils

  alias Archethic.Utils.Regression.Playbook.UCO
  alias Archethic.Utils.Regression.Playbook.SmartContract
  alias Archethic.Utils.WebClient
  alias Archethic.Utils.Regression.Benchmark.WasmSmartContractTrigger
  alias Archethic.Utils.Regression.Benchmark.EndToEndValidation
  alias Archethic.Utils.Regression.Benchmark.P2PMessage

  @playbooks [UCO, SmartContract]
  @benchmarks [
    WasmSmartContractTrigger,
    P2PMessage,
    EndToEndValidation
  ]

  def run_playbooks(nodes, opts \\ []) do
    Logger.debug("Running playbooks on #{inspect(nodes)} with #{inspect(opts)}")
    Application.ensure_all_started(:archethic_client)
    Application.put_env(:archethic_client, :base_url, "http://localhost:4000", persistent: false)

    Enum.each(@playbooks, fn playbook ->
      playbook.play!(nodes, opts)
      Process.sleep(100)
    end)
  end

  def run_benchmarks(nodes, opts \\ []) do
    Logger.debug("Running benchmarks on #{inspect(nodes)} with #{inspect(opts)}")
    Application.ensure_all_started(:archethic_client)
    Application.put_env(:archethic_client, :base_url, "http://localhost:4000", persistent: false)

    tag = Time.utc_now() |> Time.truncate(:second) |> Time.to_string()

    benchmarks_to_run = get_benchmarks_to_run(opts)

    if Enum.empty?(benchmarks_to_run) do
      Logger.warn("No benchmarks to run")
      :ok
    else
      Enum.each(benchmarks_to_run, fn benchmark ->
        run_benchmark(benchmark, nodes, opts, tag)
      end)
    end
  end

  # Helper function to determine which benchmarks to run
  defp get_benchmarks_to_run(opts) do
    case Keyword.get(opts, :only) do
      nil ->
        @benchmarks

      benchmark_names when is_list(benchmark_names) ->
        filter_benchmarks_by_names(benchmark_names)

      single_benchmark when is_binary(single_benchmark) or is_atom(single_benchmark) ->
        filter_single_benchmark(single_benchmark)
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

  # Helper function to filter a single benchmark by name
  defp filter_single_benchmark(single_benchmark) do
    benchmark_name = to_string(single_benchmark)

    case Enum.find(@benchmarks, fn benchmark -> benchmark_name(benchmark) == benchmark_name end) do
      nil ->
        Logger.warn("Unknown benchmark: #{benchmark_name}")
        []

      benchmark ->
        [benchmark]
    end
  end

  # Helper function to run a single benchmark
  defp run_benchmark(benchmark, nodes, opts, tag) do
    Logger.info("Running benchmark #{benchmark}")
    save = Utils.mut_dir("#{benchmark}.benchee")
    save_opts = [title: benchmark, save: [path: save, tag: tag], load: save]
    {bench_plan, bench_opts} = benchmark.plan(nodes, opts)

    Benchee.run(
      bench_plan,
      Keyword.merge(
        [formatters: [Benchee.Formatters.Console]],
        Keyword.merge(save_opts, bench_opts)
      )
    )
  end

  # Helper to get a standardized benchmark name
  defp benchmark_name(benchmark) when is_atom(benchmark) do
    benchmark
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
  end

  def get_metrics(host, port, range) do
    Logger.debug("Collecting metrics for last #{range} seconds")

    WebClient.with_connection(host, port, fn conn ->
      with {:ok, conn, %{"status" => "success", "data" => metrics}} <-
             WebClient.json(conn, "/api/v1/label/__name__/values"),
           {:ok, conn, data} <- collect_metrics(conn, metrics, range) do
        {:ok, conn, data}
      else
        {:error, conn, error} -> {:error, conn, error}
      end
    end)
  end

  defp query_metric(metric, range, resolution \\ 5),
    do: "/api/v1/query?query=#{metric}[#{range}s:#{resolution}s]"

  defp collect_metrics(conn, metrics, range, acc \\ [])
  defp collect_metrics(conn, [], _, acc), do: {:ok, conn, acc}

  defp collect_metrics(conn, [m | metrics], range, acc) do
    case WebClient.json(conn, query_metric(m, range)) do
      {:ok, conn, %{"status" => "success", "data" => %{"result" => data}}} ->
        collect_metrics(conn, metrics, range, [data | acc])

      {:error, conn, error} ->
        {:error, conn, error}
    end
  end

  @node_up_timeout 5 * 60 * 1000

  def nodes_up?(nodes) do
    Logger.debug("Ensure #{inspect(nodes)} are up and ready")

    nodes
    |> Task.async_stream(&node_up?/1, ordered: false, timeout: @node_up_timeout)
    |> Enum.into([])
    |> Enum.all?(&(&1 == {:ok, :ok}))
  end

  def node_up?(node, start \\ System.monotonic_time(:millisecond), timeout \\ 5 * 60_000)

  def node_up?(node, start, timeout) do
    port =
      if System.get_env("ARCHETHIC_NETWORK_TYPE") == "testnet" do
        40_000
      else
        Application.get_env(:archethic, ArchethicWeb.Endpoint)[:http][:port]
      end

    case WebClient.with_connection(node, port, &WebClient.request(&1, "GET", "/up")) do
      {:ok, ["up"]} ->
        :ok

      {:ok, _} ->
        Process.sleep(250)
        node_up?(node, start, timeout)

      {:error, _} ->
        Process.sleep(500)

        if System.monotonic_time(:millisecond) - start < timeout do
          node_up?(node, start, timeout)
        else
          {:error, :timeout}
        end
    end
  end
end
