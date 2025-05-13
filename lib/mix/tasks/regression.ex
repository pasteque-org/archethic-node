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
  ```

  """

  use Mix.Task

  alias Archethic.Utils.Regression

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:telemetry)

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

      {parsed, nodes} ->
        if parsed[:help] do
          Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
        else
          true = Regression.nodes_up?(nodes)

          # Extract benchmark names to run
          only_benchmarks =
            case Keyword.get_values(parsed, :only) do
              [] -> nil
              benchmarks -> benchmarks
            end

          benchmark_opts = if only_benchmarks, do: [only: only_benchmarks], else: []

          # Run benchmarks if requested
          if parsed[:bench] do
            Regression.run_benchmarks(nodes, benchmark_opts)
          end

          # Run playbooks if requested
          if parsed[:playbook] do
            Regression.run_playbooks(nodes)
          end

          :ok
        end
    end
  end
end
