defmodule ArchethicWeb.DNSLinkRouter do
  @moduledoc """
  Catch dns link redirection for AEWeb and call WebHostingController
  """

  @behaviour Plug

  alias ArchethicWeb.AEWeb.Domain
  alias ArchethicWeb.AEWeb.WebHostingController

  def init(opts), do: opts

  def call(%Plug.Conn{host: host, method: "GET", path_info: url_path} = conn, _) do
    case get_dnslink_address(host) do
      {:ok, address} ->
        WebHostingController.web_hosting(conn, %{"address" => address, "url_path" => url_path})

      _ ->
        throw("No DNSLink defined")
    end
  end

  def call(_conn, _), do: throw("No DNSLink defined")

  defp get_dnslink_address(host) do
    if is_ip_address?(host), do: {:error, :ip_address}, else: Domain.lookup_dnslink_address(host)
  end

  defp is_ip_address?(host),
    do: match?({:ok, _ip}, host |> String.to_charlist() |> :inet.parse_address())
end
