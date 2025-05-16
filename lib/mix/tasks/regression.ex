defmodule Mix.Tasks.Archethic.Regression do
  @shortdoc "Run regression utilities to benchmark and validate nodes"
  @bench false
  @validate false

  @moduledoc """
  This task validates and/or benchmarks a network of nodes.

  ## Command line options

    * `--help` - show this help
    * `--bench` - run benchmark "#{@bench}"
    * `--playbook` - run all playbooks, default "#{@validate}"
    * `--only BENCHMARK_NAME` - run only the specified benchmark(s), can be specified multiple times

  ## Example

  ```sh
  mix archethic.regression --bench localhost
  mix archethic.regression --bench "https://rpc-endpoint.net"
  ```

  """

  use Mix.Task

  alias Archethic.Utils.Regression

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:telemetry)
    Application.ensure_all_started(:req)
    Application.ensure_all_started(:archethic_client)

    case OptionParser.parse!(args,
           strict: [
             help: :boolean,
             bench: :boolean,
             playbook: :boolean,
             only: [:string, :keep]
           ]
         ) do
      {_, []} ->
        Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")

      {parsed, [node | _]} ->
        if parsed[:help] do
          Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
        else
          node = if node == "localhost", do: "http://localhost:4000", else: node

          true = Regression.node_up?(node)

          Application.put_env(:archethic_client, :base_url, node, persistent: false)

          # Extract benchmark names to run
          benchmark_opts = [only: Keyword.get_values(parsed, :only)]

          # Run benchmarks if requested
          if parsed[:bench] do
            Regression.run_benchmarks(node, benchmark_opts)
          end

          # Run playbooks if requested
          if parsed[:playbook] do
            Regression.run_playbooks(node)
          end

          :ok
        end
    end
  end
end
