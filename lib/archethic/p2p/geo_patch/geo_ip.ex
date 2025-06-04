defmodule Archethic.P2P.GeoPatch.GeoIP do
  @moduledoc false

  use Knigge, otp_app: :archethic, default: __MODULE__.MaxMindDB

  @callback get_coordinates(:inet.ip_address()) :: {latitude :: float(), longitude :: float()}
end
