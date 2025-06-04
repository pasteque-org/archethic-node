defmodule Mix.Tasks.Archethic.Nettools do
  @moduledoc """
  Supports networking tools using a command-line interface.

  ## Command line options

    * `-h`, `--help`  - show this help
    * `-p`, `--punch` - Attempt to open ports
    * `-i`, `--ip`    - Public IP

  ## Command line arguments
    * `punch` - args: []-> 30002 40002, list_of ports

  ## Example

  ```sh
  mix archethic.nettools -p
  mix archethic.nettools --punch
  mix archethic.nettools -p 30_000 40_000
  mix archethic.nettools -i
  mix archethic.nettools --ip
  ```

  """
  use Mix.Task

  alias Archethic.Networking

  require Logger

  @http_port "ARCHETHIC_HTTP_PORT" |> System.get_env("40000") |> String.to_integer()
  @p2p_port "ARCHETHIC_P2P_PORT" |> System.get_env("30002") |> String.to_integer()

  @impl Mix.Task
  def run(args) do
    parse_args(args)
  end

  def parse_args(args) do
    put_env()

    args
    |> OptionParser.parse(
      strict: [help: :boolean, punch: :boolean, ip: :boolean],
      aliases: [h: :help, p: :punch, i: :ip]
    )
    |> args_to_internal_representation()
  end

  # For switch --help or -h
  def args_to_internal_representation({[help: true], [], []}) do
    Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
  end

  # For switch --punch or -p Opens default http and p2p ports
  def args_to_internal_representation({[punch: true], [] = _port_list, _errors}) do
    Networking.PortForwarding.try_open_port(@http_port, true)
    Networking.PortForwarding.try_open_port(@p2p_port, true)
  end

  # For switch --punch or -p with custom ports
  def args_to_internal_representation({[punch: true], port_list, _errors}) do
    Enum.each(port_list, fn port ->
      port |> String.to_integer() |> Networking.PortForwarding.try_open_port(true)
    end)
  end

  # For switch --ip -i to get ip address
  def args_to_internal_representation({[ip: true], _, _}) do
    Networking.IPLookup.get_node_ip()
  end

  # For unknown switch exceute to help
  def args_to_internal_representation(_) do
    Mix.shell().cmd("mix help #{Mix.Task.task_name(__MODULE__)}")
  end

  def put_env,
    do: Application.put_env(:archethic, Networking.IPLookup, Networking.IPLookup.NATDiscovery)
end
