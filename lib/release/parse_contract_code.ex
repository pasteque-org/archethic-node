defmodule Archethic.Release.ParseContractCode do
  @moduledoc false

  use Distillery.Releases.Appup.Transform

  alias Archethic.Contracts.Loader

  def up(:archethic, _v1, _v2, instructions, _opts), do: add_contract_reparse(instructions)

  def up(_, _, _, instructions, _), do: instructions

  def down(_, _, _, instructions, _), do: instructions

  defp add_contract_reparse(instructions) do
    call_instruction = {:apply, {Loader, :reparse_workers_contract, []}}

    Enum.concat(instructions, [call_instruction])
  end
end
