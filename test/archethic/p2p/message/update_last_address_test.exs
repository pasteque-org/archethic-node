defmodule Archethic.P2P.Message.UpdateLastAddressTest do
  @moduledoc false

  use ArchethicCase

  import ArchethicCase

  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.UpdateLastAddress

  describe "serialization" do
    test "should serialize and deserialize message" do
      address = random_address()

      message = %UpdateLastAddress{address: address}
      assert message == message |> Message.encode() |> Message.decode() |> elem(0)
    end
  end
end
