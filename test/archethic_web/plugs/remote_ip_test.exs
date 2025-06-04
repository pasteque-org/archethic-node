defmodule ArchethicWeb.Plugs.RemoteIPTest do
  use ArchethicWeb.ConnCase, async: true

  alias ArchethicWeb.Plugs.RemoteIP

  describe "Plug should get first x-forwarded remote ip " do
    test "should modify remote ip if x-forwarded header exists", %{conn: conn} do
      assert conn.remote_ip == {127, 0, 0, 1}

      conn = put_req_header(conn, "x-forwarded-for", "122.15.183.19,93.5.9.0")

      conn = RemoteIP.call(conn, [])

      assert conn.remote_ip == {122, 15, 183, 19}
    end

    test "should not modifiy remote ip if x-forwarded header is empty", %{conn: conn} do
      assert conn.remote_ip == {127, 0, 0, 1}

      conn = RemoteIP.call(conn, [])

      assert conn.remote_ip == {127, 0, 0, 1}
    end
  end
end
