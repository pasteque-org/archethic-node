defmodule Archethic.Contracts.Contract.StateTest do
  use ArchethicCase

  alias Archethic.Contracts.Contract.State

  describe "serialization/deserialization" do
    test "should serialize/deserialize" do
      state = complex_state()

      assert {^state, <<>>} = state |> State.serialize() |> State.deserialize()
    end
  end

  defp complex_state do
    data = %{
      "foo" => "bar",
      "nil" => nil,
      "int" => 42,
      "list" => [1, 2, 3],
      "emptystr" => "",
      "emptymap" => %{},
      "mapwithcomplexkeys" => %{1 => 1, [2, 3] => 4, %{} => 5, true => false},
      "nested" => %{"list" => [[4, false, [5, %{"hello" => "world"}], "6"], 23, []]}
    }

    State.wrap_data(data)
  end
end
