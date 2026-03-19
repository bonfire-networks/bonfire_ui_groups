defmodule Bonfire.UI.Groups.ConnCase do
  @moduledoc """
  Test case for bonfire_ui_groups tests that require a connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest

      import Bonfire.UI.Common.Testing.Helpers

      import Phoenix.LiveViewTest, except: [open_browser: 1, open_browser: 2]

      import PhoenixTest

      alias Bonfire.Me.Fake

      use Bonfire.Common.Utils
      use Bonfire.Common.Config
      use Bonfire.Common.Repo

      @endpoint Application.compile_env!(:bonfire, :endpoint_module)

      @moduletag :ui
    end
  end

  setup tags do
    Bonfire.Common.Test.Interactive.setup_test_repo(tags)

    {:ok, []}
  end
end
