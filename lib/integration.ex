defmodule Bonfire.UI.Groups.Integration do
  alias Bonfire.Common.Config
  alias Bonfire.Common.Utils
  import Untangle

  def repo, do: Config.repo()
end
