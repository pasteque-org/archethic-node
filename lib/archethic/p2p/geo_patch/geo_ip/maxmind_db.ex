defmodule Archethic.P2P.GeoPatch.GeoIP.MaxMindDB do
  @moduledoc ~S"""
  A GenServer implementation for querying IP geolocation data from an
  in-memory MaxMindDB database.

  This module loads a GeoLite2 City database (`.mmdb` file) into memory
  upon initialization and provides an interface to retrieve latitude and
  longitude coordinates for a given IP address (both IPv4 and IPv6).

  It relies on the `MMDB2Decoder` library to parse the database and perform
  lookups.
  """

  alias Archethic.P2P.GeoPatch.GeoIP
  alias MMDB2Decoder

  use GenServer
  @vsn 1

  require Logger

  @behaviour GeoIP

  @doc ~S"""
  Starts the `MaxMindDB` GenServer.
  """
  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl GenServer
  def init(_) do
    Logger.info("Initialize InMemory MaxMindDB metadata...")

    database = File.read!(Application.app_dir(:archethic, "/priv/p2p/GeoLite2-City-2025-05-23.mmdb"))

    {:ok, meta, tree, data} = MMDB2Decoder.parse_database(database)
    IO.inspect({:ok, meta, tree, data})

    {:ok, {meta, tree, data}}
  end

  @doc ~S"""
  Retrieves the latitude and longitude for a given IP address.

  The IP address must be provided as a tuple, as parsed by `:inet.parse_address/1`.
  For example:
  - IPv4: `{192, 168, 1, 1}`
  - IPv6: `{8193, 3512, 0, 0, 0, 0, 0, 1}`

  Returns ` {latitude, longitude}` if the IP is found, or `{0.0, 0.0}`
  if the IP is not found or an error occurs during lookup.
  """
  @impl GeoIP
  def get_coordinates(ip) when is_tuple(ip) do
    GenServer.call(__MODULE__, {:get_coordinates, ip})
  end

  @impl GenServer
  def handle_call({:get_coordinates, ip}, _from, {meta, tree, data}) do
    case MMDB2Decoder.lookup(ip, meta, tree, data) do
      {:ok, %{"location" => %{"latitude" => lat, "longitude" => lon}}} ->
        {:reply, {lat, lon}, {meta, tree, data}}

      _ ->
        {:reply, {0.0, 0.0}, {meta, tree, data}}
    end
  end
end
