defmodule WongiEngineWebui.Value.Atom do
  @moduledoc """
  An atom read from user input without creating it.

  In safe mode, atoms in facts and rule values are represented by this struct.
  Both sides go through the same reader, so they still match each other.
  """

  defstruct [:name]

  @type t() :: %__MODULE__{name: String.t()}
end
