defmodule WongiEngineWebui.Builder.Error do
  @moduledoc "Raised when a spec field can't be turned into a value."

  defexception [:path, :message]
end
