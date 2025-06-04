defmodule Archethic.P2P.ListenerProtocol do
  @moduledoc false
  # ListenerProtocol handles Incoming new messages from other nodes and
  # no response is processed here.
  # Connection modules handles this nodes request get messages and
  # then its response is processed.

  @behaviour :ranch_protocol

  alias Archethic.Crypto
  alias Archethic.P2P
  alias Archethic.P2P.Client.Connection
  alias Archethic.P2P.Message
  alias Archethic.P2P.MessageEnvelop
  alias Archethic.Utils

  require Logger

  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [{ref, transport, opts}])
    {:ok, pid}
  end

  def init({ref, transport, opts}) do
    {:ok, socket} = :ranch.handshake(ref)
    :ok = transport.setopts(socket, opts)

    {:ok, {ip, port}} = :inet.peername(socket)

    :gen_server.enter_loop(__MODULE__, [], %{
      socket: socket,
      transport: transport,
      ip: ip,
      port: port
    })
  end

  def handle_info({ref, :stop}, %{transport: transport, socket: socket, ip: ip} = state)
      when is_reference(ref) do
    if node_ip?(ip), do: Logger.error("Stopping listener (ip: #{:inet.ntoa(ip)})")
    transport.close(socket)
    {:stop, :normal, state}
  end

  def handle_info({ref, :ok}, state) when is_reference(ref) do
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, %{ip: ip} = state) do
    if reason != :normal && node_ip?(ip),
      do: Logger.error("handle_message crashed for reason: #{inspect(reason)}")

    {:noreply, state}
  end

  def handle_info({_transport, socket, "hb"}, %{transport: transport} = state) do
    :inet.setopts(socket, active: :once)

    Task.Supervisor.start_child(Archethic.task_supervisors(), fn ->
      transport.send(socket, "hb")
    end)

    {:noreply, state}
  end

  def handle_info({_transport, socket, err}, %{transport: transport, ip: ip} = state)
      when is_atom(err) do
    if node_ip?(ip) do
      Logger.error("Received an error from tcp listener (ip: #{:inet.ntoa(ip)}): #{inspect(err)}")
    end

    transport.close(socket)
    {:stop, :normal, state}
  end

  def handle_info({_transport, socket, msg}, %{transport: transport, ip: ip} = state) do
    :inet.setopts(socket, active: :once)

    Task.Supervisor.async_nolink(Archethic.task_supervisors(), fn ->
      handle_message(msg, transport, socket, ip)
    end)

    {:noreply, state}
  end

  def handle_info({_transport_closed, _socket}, %{ip: ip, port: port} = state) do
    Logger.warning("Incoming connection closed #{:inet.ntoa(ip)}:#{port}")
    {:stop, :normal, state}
  end

  defp handle_message(msg, transport, socket, ip) do
    case decode_msg(msg) do
      {:ok,
       %MessageEnvelop{
         message_id: message_id,
         message: message,
         sender_public_key: sender_pkey,
         signature: signature,
         decrypted_raw_message: decrypted_raw_message
       }} ->
        valid_signature? =
          Crypto.verify?(
            signature,
            decrypted_raw_message,
            sender_pkey
          )

        if valid_signature? do
          # we may attempt to wakeup a connection that offline
          Connection.wake_up(sender_pkey)

          message
          |> process_msg(sender_pkey)
          |> encode_response(message_id, sender_pkey)
          |> reply(transport, socket, message)

          :ok
        else
          if node_ip?(ip) do
            Logger.error("Received a message with an invalid signature",
              node: Base.encode16(sender_pkey)
            )
          end

          :stop
        end

      {:error, reason} ->
        if node_ip?(ip) do
          Logger.error(reason)
        end

        :stop
    end
  end

  # msg is the bytes coming from TCP
  # message is the struct
  defp decode_msg(msg) do
    start_decode_time = System.monotonic_time()

    msg
    |> MessageEnvelop.decode()
    |> then(fn %MessageEnvelop{message: message} = res ->
      :telemetry.execute(
        [:archethic, :p2p, :decode_message],
        %{duration: System.monotonic_time() - start_decode_time},
        %{message: Message.name(message)}
      )

      {:ok, res}
    end)
  rescue
    err ->
      {:error, Exception.format(:error, err, __STACKTRACE__)}
  end

  defp process_msg(message, sender_pkey) do
    start_processing_time = System.monotonic_time()

    message
    |> Message.process(sender_pkey)
    |> tap(fn _ ->
      :telemetry.execute(
        [:archethic, :p2p, :handle_message],
        %{
          duration: System.monotonic_time() - start_processing_time
        },
        %{message: Message.name(message)}
      )
    end)
  end

  defp encode_response(response, message_id, sender_pkey) do
    start_encode_time = System.monotonic_time()

    response_signature =
      response
      |> Message.encode()
      |> Utils.wrap_binary()
      |> Crypto.sign_with_first_node_key()

    %MessageEnvelop{
      message: response,
      message_id: message_id,
      sender_public_key: Crypto.first_node_public_key(),
      signature: response_signature
    }
    |> MessageEnvelop.encode(sender_pkey)
    |> tap(fn _ ->
      :telemetry.execute(
        [:archethic, :p2p, :encode_message],
        %{duration: System.monotonic_time() - start_encode_time},
        %{message: Message.name(response)}
      )
    end)
  end

  defp reply(encoded_response, transport, socket, message) do
    start_sending_time = System.monotonic_time()

    socket
    |> transport.send(encoded_response)
    |> tap(fn _ ->
      :telemetry.execute(
        [:archethic, :p2p, :transport_sending_message],
        %{duration: System.monotonic_time() - start_sending_time},
        %{message: Message.name(message)}
      )
    end)
  end

  defp node_ip?(ip) do
    P2P.list_nodes() |> Enum.map(& &1.ip) |> Enum.member?(ip)
  end
end
