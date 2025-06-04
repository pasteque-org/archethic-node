defmodule Archethic.Contracts.Interpreter.Library.Common.HttpImpl do
  @moduledoc """
  Http client for the Smart Contracts.
  Implements AEIP-20.
  """

  @behaviour Archethic.Contracts.Interpreter.Library.Common.Http

  use Archethic.Tag

  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Library.Common.Http

  @threshold 256 * 1024
  @timeout Application.compile_env(:archethic, [__MODULE__, :timeout], 2_000)
  @supported_schemes Application.compile_env(
                       :archethic,
                       [__MODULE__, :supported_schemes],
                       ["https"]
                     )
  # we use the transport_opts to be able to test (MIX_ENV=test) with self signed certificates
  @conn_opts [
    transport_opts:
      :archethic |> Application.compile_env(__MODULE__, []) |> Keyword.get(:transport_opts, [])
  ]

  @tag [:io]
  @impl Http
  def request(uri, method \\ "GET", headers \\ %{}, body \\ nil, throw_on_error \\ true)

  def request(url, method, headers, body, throw_on_error) do
    [%{"url" => url, "method" => method, "headers" => headers, "body" => body}]
    |> request_many(throw_on_error)
    |> List.first()
  end

  @tag [:io]
  @impl Http
  def request_many(requests, throw_on_err \\ true)

  def request_many(requests, true) do
    with :ok <- validate_multiple_calls(),
         :ok <- validate_nb_requests(requests),
         requests = set_request_default(requests),
         tasks = Enum.map(requests, &do_request/1),
         results = await_tasks_result(requests, tasks),
         {:ok, results} <- validate_results(results, true) do
      results
    else
      error -> raise Library.Error, message: format_error_message(error)
    end
  end

  def request_many(requests, false) do
    case validate_multiple_calls() do
      {:error, :multiple_calls} ->
        Enum.map(requests, fn _ -> %{"status" => -4005} end)

      :ok ->
        {requests_to_handle, requests_not_handled} = Enum.split(requests, 5)

        tasks =
          requests_to_handle
          |> set_request_default()
          |> Enum.map(&do_request/1)

        {:ok, results} =
          requests_to_handle
          |> await_tasks_result(tasks)
          |> validate_results(false)

        transform_results(
          results ++ Enum.map(requests_not_handled, &{:error, :max_nb_requests, &1})
        )
    end
  end

  defp transform_results(results) do
    Enum.map(results, fn
      {:ok, result} ->
        result

      {:error, :max_nb_requests, _} ->
        %{"status" => -4003}

      {:error, :threshold_reached, _} ->
        %{"status" => -4002}

      {:error, :timeout, _} ->
        %{"status" => -4001}

      {:error, :not_supported_scheme, _} ->
        %{"status" => -4004}

      {:error, _, _} ->
        %{"status" => -4000}
    end)
  end

  defp validate_multiple_calls do
    if Process.get(:smart_contract_http_request_called) do
      {:error, :multiple_calls}
    else
      Process.put(:smart_contract_http_request_called, true)
      :ok
    end
  end

  defp validate_nb_requests(requests) when length(requests) <= 5, do: :ok
  defp validate_nb_requests(_), do: {:error, :max_nb_requests}

  defp set_request_default(requests) do
    default_request = %{"url" => nil, "method" => "GET", "headers" => %{}, "body" => nil}
    Enum.map(requests, &Map.merge(default_request, &1))
  end

  # -------------- #
  defp do_request(
         %{"url" => url, "method" => method, "headers" => headers, "body" => request_body} =
           request
       ) do
    Task.Supervisor.async_nolink(Archethic.task_supervisors(), fn ->
      with {:ok, uri, method} <- validate_request(url, method, headers, request_body),
           {:ok, _} = res <- execute_request(method, uri, headers, request_body) do
        res
      else
        {:error, reason} -> {:error, reason, request}
      end
    end)
  end

  # -------------- #
  defp validate_request(url, method, headers, body) do
    with {:ok, uri} <- validate_url(url),
         {:ok, method} <- validate_method(method),
         :ok <- validate_body(body),
         :ok <- validate_scheme(uri.scheme),
         :ok <- validate_headers(headers) do
      {:ok, uri, method}
    end
  end

  defp validate_url(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, uri} -> {:ok, uri}
      _ -> {:error, :invalid_url}
    end
  end

  defp validate_url(_url), do: {:error, :invalid_url}

  # -------------- #
  defp validate_method(method) when method in ["GET", "POST", "PUT", "DELETE", "PATCH"],
    do: {:ok, method |> String.downcase() |> String.to_existing_atom()}

  defp validate_method(_method), do: {:error, :invalid_method}

  # -------------- #
  defp validate_headers(headers) when is_map(headers) do
    if Enum.all?(headers, &valid_header?/1), do: :ok, else: {:error, :invalid_headers}
  end

  defp valid_header?({key, value}) when is_binary(key) and is_binary(value), do: true
  defp valid_header?(_), do: false

  # -------------- #
  defp validate_body(body) when is_binary(body) or is_nil(body), do: :ok
  defp validate_body(_), do: {:error, :invalid_body}

  # -------------- #
  defp validate_scheme(scheme) when scheme in @supported_schemes, do: :ok
  defp validate_scheme(_), do: {:error, :not_supported_scheme}

  # -------------- #
  defp execute_request(method, uri, headers, request_body) do
    req_opts = [
      method: method,
      url: URI.to_string(uri),
      headers: headers,
      body: request_body,
      connect_options: @conn_opts,
      into: &stream_response/2,
      decode_body: false
    ]

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: response_body} = resp} ->
        if Req.Response.get_private(resp, :archethic_threshold?, false),
          do: {:error, :threshold_reached},
          else: {:ok, %{"status" => status, "body" => response_body}}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end

  defp stream_response({:data, data}, {req, resp}) do
    resp_size = Req.Response.get_private(resp, :archethic_resp_size, 0)
    new_resp_size = resp_size + byte_size(data)

    if new_resp_size > @threshold do
      {:halt, {req, Req.Response.put_private(resp, :archethic_threshold?, true)}}
    else
      resp =
        Req.Response.put_private(
          %{resp | body: resp.body <> data},
          :archethic_resp_size,
          new_resp_size
        )

      {:cont, {req, resp}}
    end
  end

  defp await_tasks_result(requests, tasks) do
    tasks
    |> Task.yield_many(@timeout)
    |> Enum.zip(requests)
    |> Enum.map(fn {{task, res}, request} ->
      case res do
        nil ->
          Task.shutdown(task, :brutal_kill)
          {:error, :timeout, request}

        {:exit, _reason} ->
          {:error, :task_exited, request}

        {:ok, res} ->
          res
      end
    end)
  end

  defp validate_results(results, true) do
    # count the number of bytes to be able to send a error too large
    # this is sub optimal because miners might still download threshold N times before returning the error
    # TODO: improve this
    results
    |> Enum.reduce_while({:ok, 0, []}, fn
      {:ok, result}, {:ok, total_bytes, acc} ->
        bytes = result |> Map.get("body", "") |> byte_size()
        new_total_bytes = total_bytes + bytes

        if new_total_bytes > @threshold do
          {:halt, {:error, :threshold_reached, %{}}}
        else
          {:cont, {:ok, new_total_bytes, [result | acc]}}
        end

      error, _acc ->
        {:halt, error}
    end)
    |> then(fn
      {:ok, _, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end)
  end

  defp validate_results(results, false) do
    # count the number of bytes to be able to send a error too large
    # this is sub optimal because miners might still download threshold N times before returning the error
    # TODO: improve this
    results
    |> Enum.reduce_while({0, []}, fn
      {:ok, result}, {total_bytes, acc} ->
        bytes = result |> Map.get("body", "") |> byte_size()
        new_total_bytes = total_bytes + bytes

        if new_total_bytes > @threshold do
          {:halt, {:error, :threshold_reached, %{}}}
        else
          {:cont, {new_total_bytes, [{:ok, result} | acc]}}
        end

      error, {total_bytes, acc} ->
        {:cont, {total_bytes, [error | acc]}}
    end)
    |> then(fn
      {:error, :threshold_reached, %{}} ->
        # when threshold_reached we apply this error to all requests
        {:ok, Enum.map(results, fn _ -> {:error, :threshold_reached, %{}} end)}

      {_bytes, acc} ->
        {:ok, Enum.reverse(acc)}
    end)
  end

  # -------------- #
  defp format_error_message({:error, :multiple_calls}),
    do: "Http module got called more than once"

  defp format_error_message({:error, :max_nb_requests}),
    do: "Http.request_many was called with too many requests"

  defp format_error_message({:error, :invalid_url, %{"url" => url}}),
    do: "Http module received invalid url, got #{inspect(url)}"

  defp format_error_message({:error, :invalid_method, %{"method" => method}}),
    do: "Http module received invalid method, got #{inspect(method)}"

  defp format_error_message({:error, :invalid_headers, %{"headers" => headers}}),
    do: "Http module was called with invalid headers, got #{inspect(headers)}"

  defp format_error_message({:error, :invalid_body, %{"body" => body}}),
    do: "Http module was called with invalid body, got #{inspect(body)}"

  defp format_error_message({:error, :threshold_reached, _}),
    do: "Http response is bigger than threshold"

  defp format_error_message({:error, :not_supported_scheme, %{"url" => url}}),
    do:
      "Http request was called with an invalid scheme for #{inspect(url)}, " <>
        "supported scheme are #{Enum.join(@supported_schemes, ", ")}"

  defp format_error_message({:error, :timeout, %{"url" => url}}),
    do: "Http request timed out for url #{inspect(url)}"

  defp format_error_message({:error, _, %{"url" => url}}),
    do: "Http request failed for url #{inspect(url)}"
end
