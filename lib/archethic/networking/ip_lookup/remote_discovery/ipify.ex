defmodule Archethic.Networking.IPLookup.RemoteDiscovery.IPIFY do
  @moduledoc """
  Module provides external IP address of the node identified by IPIFY service.
  """

  @behaviour Archethic.Networking.IPLookup.Impl

  alias Archethic.Networking.IPLookup.Impl

  @impl Impl
  @spec get_node_ip() ::
          {:ok, :inet.ip_address()} | {:error, :not_recognizable_ip} | {:error, any()}
  def get_node_ip do
    with {:ok, %Req.Response{status: 200, body: inet_addr}} <- Req.get("http://api.ipify.org"),
         {:ok, ip} <- :inet.parse_address(inet_addr) do
      {:ok, ip}
    else
      {:error, :einval} -> {:error, :not_recognizable_ip}
      {:error, _} = e -> e
    end
  end
end
