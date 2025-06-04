defmodule Archethic.P2P.Message.GetDashboardDataTest do
  @moduledoc false

  use ExUnit.Case

  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.GetDashboardData

  test "encode decode since=nil" do
    msg = %GetDashboardData{since: nil}

    assert {^msg, <<>>} =
             msg
             |> Message.encode()
             |> Message.decode()
  end

  test "encode decode since=datetime" do
    msg = %GetDashboardData{since: DateTime.utc_now(:second)}

    assert {^msg, <<>>} =
             msg
             |> Message.encode()
             |> Message.decode()
  end
end
