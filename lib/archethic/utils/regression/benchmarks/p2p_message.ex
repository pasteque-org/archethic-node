defmodule Archethic.Utils.Regression.Benchmark.P2PMessage do
  @moduledoc """
  Defines a benchmark suite for measuring P2P message latency and node stability.

  This benchmark tests the performance and resource usage (specifically, Erlang process count)
  of a target node when handling common P2P requests:
  - `GetTransaction`
  - `GetTransactionChain`
  - `GetUnspentOutputs`

  It establishes a direct P2P connection to the node and measures the response time
  for each request type. It also monitors the node's process count before and after
  each scenario run to detect potential resource leaks.
  """

  @behaviour Archethic.Utils.Regression.Benchmark

  alias Archethic.Bootstrap.NetworkInit
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils
  alias Archethic.Utils.Regression.Benchmark
  alias ArchethicClient.Crypto

  require Logger

  @impl Benchmark
  @doc """
  Prepares and configures the P2P message benchmark
  """
  @spec plan(String.t(), Keyword.t()) :: {map(), Keyword.t()}
  def plan(node, _opts) do
    p2p_port = Application.get_env(:archethic, Archethic.P2P.Listener)[:port]

    %URI{host: host} = URI.parse(node)
    {:ok, addr} = host |> to_charlist() |> :inet.getaddr(:inet)

    {public_key, private_key} =
      Crypto.generate_deterministic_keypair(
        :crypto.strong_rand_bytes(32),
        curve: :secp256r1
      )

    {:ok, conn_pid} =
      __MODULE__.Connection.start_link(
        addr: addr,
        port: p2p_port,
        public_key: public_key,
        private_key: private_key
      )

    bench_plan = %{
      "GetTransaction" => fn _ ->
        %Transaction{} =
          __MODULE__.Connection.send_message(conn_pid, %GetTransaction{
            address: get_first_tx_address()
          })
      end,
      "GetTransactionChain" => fn _ ->
        %TransactionList{} =
          __MODULE__.Connection.send_message(conn_pid, %GetTransactionChain{
            address: get_first_tx_address()
          })
      end,
      "GetUnspentOutputs" => fn _ ->
        %UnspentOutputList{} =
          __MODULE__.Connection.send_message(conn_pid, %GetUnspentOutputs{
            address: get_first_tx_address()
          })
      end
    }

    bench_opts = [
      before_scenario: fn _ -> get_vm_status(node) end,
      after_scenario: fn before ->
        now = get_vm_status(node)

        Enum.each([{"vm_system_counts_process_count", 35}], fn {metric, delta} ->
          before_value = Map.get(before, metric, 0)
          now_value = Map.get(now, metric, 0)

          Logger.info("Checking #{metric} #{before_value} vs #{now_value}")

          if before_value + delta - now_value < 0 do
            raise RuntimeError,
              message: "leak of #{metric} is detected (#{before_value} + #{delta} < #{now_value})"
          end
        end)
      end
    ]

    {bench_plan, bench_opts}
  end

  # Private helper to fetch VM metrics from the target node via the HTTP /metrics endpoint.
  # Used by the before/after scenario hooks to check process count stability.
  defp get_vm_status(node) do
    case Req.get(base_url: node, url: "metrics") do
      {:ok, %Req.Response{status: 200, body: body}} ->
        body
        |> String.split("\n")
        |> Enum.filter(&String.starts_with?(&1, "vm_"))
        |> Enum.reduce(%{}, &parse_vm_metric/2)

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Unexpected status #{status} from /metrics")
        %{}

      {:error, reason} ->
        Logger.warning("Failed to get VM status from /metrics: #{inspect(reason)}")
        %{}
    end
  end

  # Parses a VM metric line and updates the accumulator if valid.
  defp parse_vm_metric(kv, acc) do
    case String.split(kv) do
      [k, v_str] ->
        case Integer.parse(v_str) do
          {val, ""} -> Map.put(acc, k, val)
          _ -> acc
        end

      _ ->
        acc
    end
  end

  # Private helper to retrieve the first transaction address from the application configuration.
  # The address is used as a known target for the P2P requests.
  defp get_first_tx_address do
    :archethic
    |> Application.get_env(NetworkInit)
    |> Keyword.fetch!(:genesis_seed)
    |> Crypto.derive_address(1)
  end

  defmodule Connection do
    @moduledoc """
    Internal GenServer responsible for managing the P2P TCP connection.

    It handles connecting to the target node, sending encoded/signed/encrypted
    P2P messages, and receiving/decrypting/decoding the responses.
    It correlates requests and responses using a unique `request_id`.
    """

    use GenServer

    alias Archethic.P2P.Message
    alias Archethic.P2P.MessageEnvelop
    alias ArchethicClient.Crypto

    @vsn 1

    @doc """
    Starts the Connection GenServer.
    Arguments are passed to `init/1`.
    """
    def start_link(arg) do
      GenServer.start_link(__MODULE__, arg)
    end

    @doc """
    Sends a P2P message synchronously via this GenServer.

    This is the main interface used by the benchmark scenarios.
    It sends a `{:send_message, message}` request to the GenServer
    and waits for a reply delivered via `handle_info/2` -> `GenServer.reply/2`.
    """
    def send_message(pid, message) do
      GenServer.call(pid, {:send_message, message})
    end

    @impl GenServer
    @doc """
    Initializes the GenServer state.
    """
    def init(arg) do
      addr = Keyword.get(arg, :addr)
      port = Keyword.get(arg, :port)
      public_key = Keyword.get(arg, :public_key)
      private_key = Keyword.get(arg, :private_key)

      {:ok, socket} = :gen_tcp.connect(addr, port, [:binary, active: true, packet: 4])

      {:ok,
       %{
         socket: socket,
         messages: %{},
         request_id: 0,
         public_key: public_key,
         private_key: private_key
       }}
    end

    @impl GenServer
    @doc """
    Handles synchronous `:send_message` requests.
    """
    def handle_call(
          {:send_message, msg},
          from,
          %{
            socket: socket,
            public_key: public_key,
            private_key: private_key,
            request_id: request_id
          } = state
        ) do
      envelop =
        MessageEnvelop.encode(%MessageEnvelop{
          message: msg,
          message_id: request_id,
          sender_public_key: public_key,
          signature: msg |> Message.encode() |> Utils.wrap_binary() |> Crypto.sign(private_key)
        })

      :gen_tcp.send(socket, envelop)

      new_state =
        state
        |> Map.update!(:request_id, &(&1 + 1))
        |> Map.update!(:messages, &Map.put(&1, request_id, from))

      {:noreply, new_state}
    end

    @impl GenServer
    @doc """
    Handles incoming TCP data containing P2P responses.
    """
    def handle_info({:tcp, _, data}, %{private_key: private_key, messages: messages} = state) do
      {msg_id, encrypted_message} = MessageEnvelop.decode_raw_message(data)

      msg =
        encrypted_message
        |> Crypto.ec_decrypt!(private_key)
        |> Message.decode()
        |> elem(0)

      case Map.pop(messages, msg_id) do
        {nil, _} ->
          {:noreply, state}

        {from, messages} ->
          GenServer.reply(from, msg)
          {:noreply, %{state | messages: messages}}
      end
    end
  end
end
