defmodule Archethic.Mining.MaliciousDetection do
  @moduledoc """
  Provide a process to detect the malicious nodes when the
  atomic commitment has not been reached.
  """

  use Task

  alias Archethic.Mining.ValidationContext

  @spec start_link(ValidationContext.t()) :: {:ok, pid()}
  def start_link(%ValidationContext{} = context) do
    Task.start_link(__MODULE__, :run, [context])
  end

  def run(%ValidationContext{} = _context) do
    # TODO: Implement the algorithm
  end
end
