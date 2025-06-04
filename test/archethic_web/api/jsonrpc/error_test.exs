defmodule ArchethicWeb.API.JsonRPC.ErrorTest do
  use ArchethicCase

  alias ArchethicWeb.API.JsonRPC.Error

  describe "get_error" do
    test "should return a structure according to JSON RPC specification" do
      assert :parse_error |> Error.get_error() |> respect_json_rpc?()
      assert {:invalid_request, []} |> Error.get_error() |> respect_json_rpc?()
      assert {:invalid_method, ""} |> Error.get_error() |> respect_json_rpc?()
      assert {:invalid_method_params, []} |> Error.get_error() |> respect_json_rpc?()
      assert {:internal_error, ""} |> Error.get_error() |> respect_json_rpc?()

      assert {:custom_error, :transaction_exists, ""}
             |> Error.get_error()
             |> respect_json_rpc?()
    end

    test "should return Json RPC standard error code" do
      assert %{"code" => -32_700} = Error.get_error(:parse_error)
      assert %{"code" => -32_600} = Error.get_error({:invalid_request, []})
      assert %{"code" => -32_601} = Error.get_error({:invalid_method, ""})
      assert %{"code" => -32_602} = Error.get_error({:invalid_method_params, []})
      assert %{"code" => -32_603} = Error.get_error({:internal_error, ""})
    end

    test "should return custom error code for transaction context" do
      assert %{"code" => 103} = Error.get_error({:custom_error, :invalid_transaction, ""})
      assert %{"code" => 104} = Error.get_error({:custom_error, :transaction_not_exists, ""})
      assert %{"code" => 122} = Error.get_error({:custom_error, :transaction_exists, ""})
    end

    test "should return custom error code for smart contract context" do
      assert %{"code" => 203} = Error.get_error({:custom_error, :contract_failure, ""})
      assert %{"code" => 204} = Error.get_error({:custom_error, :no_recipients, ""})

      assert %{"code" => 206} =
               Error.get_error({:custom_error, :invalid_transaction_constraints, ""})

      assert %{"code" => 207} = Error.get_error({:custom_error, :invalid_inherit_constraints, ""})
      assert %{"code" => 208} = Error.get_error({:custom_error, :parsing_contract, ""})
      assert %{"code" => 250} = Error.get_error({:custom_error, :execution_raise, ""})
      assert %{"code" => 251} = Error.get_error({:custom_error, :function_is_private, ""})
      assert %{"code" => 252} = Error.get_error({:custom_error, :function_does_not_exist, ""})
    end
  end

  defp respect_json_rpc?(map) do
    map |> Map.keys() |> Enum.all?(&(&1 in ["code", "message", "data"]))
  end
end
