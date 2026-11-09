defmodule Bonfire.UI.Groups.GroupHeroCompactBrowserTest do
  @moduledoc "The toggle folds and unfolds the hero. Run with HOSTNAME=localhost and matching SERVER_PORT/PUBLIC_PORT values so the browser URL and socket origin use the test server."
  use ExUnit.Case, async: false

  alias Wallaby.{Browser, Query}
  require Browser
  alias Bonfire.Common.Repo

  @moduletag :ui
  @moduletag :browser
  if System.get_env("PHX_SERVER") not in ~w(yes true 1),
    do: @moduletag(skip: "Run with just test-ui-browser and a free SERVER_PORT")

  @endpoint Application.compile_env!(:bonfire, :endpoint_module)

  @password "group-hero-compact-password"

  @hero "[data-id=group_hero]"
  @toggle "[data-role=group-hero-toggle]"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok = Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    {:ok, _} = Application.ensure_all_started(:wallaby)
    {:ok, session} = Wallaby.start_session()
    on_exit(fn -> Wallaby.end_session(session) end)

    account = Bonfire.Me.Fake.fake_account!(%{credential: %{password: @password}})
    user = Bonfire.Me.Fake.fake_user!(account)

    %{session: Browser.resize_window(session, 1440, 1000), user: user}
  end

  test "a member's toggle shows the full hero, and hides it again", %{session: session, user: user} do
    group =
      Bonfire.Classify.Simulate.fake_group!(Bonfire.Me.Fake.fake_user!(), %{
        name: "Compact walkers",
        membership: "open",
        visibility: "global"
      })

    assert {:ok, _} = Bonfire.Classify.Categories.join_and_follow_group(user, group)

    session
    |> sign_in(user)
    |> Browser.visit(@endpoint.url() <> "/group/#{group.character.username}")
    |> Browser.assert_has(Query.css(".phx-connected #{@hero}[data-compact]"))
    |> assert_folded(true, "control: the details start folded")
    |> Browser.click(Query.css(@toggle))
    |> Browser.assert_has(Query.css("#{@toggle}[aria-expanded=true]"))
    |> assert_folded(false, "the toggle unfolds the details")
    |> Browser.click(Query.css(@toggle))
    |> assert_folded(true, "the toggle folds them again")
  end

  # folded: zero height and inert, polled through the 300ms transition
  defp assert_folded(session, expected, message, tries \\ 20) do
    result = folded(session)

    cond do
      result == expected ->
        session

      tries > 1 ->
        Process.sleep(100)
        assert_folded(session, expected, message, tries - 1)

      true ->
        flunk("#{message}: expected folded? to be #{expected}, got #{inspect(result)}")
    end
  end

  defp folded(session) do
    Browser.execute_script(
      session,
      """
      const details = document.querySelector(arguments[0]);
      if (!details) return null;
      return details.getBoundingClientRect().height < 1 && details.hasAttribute('inert');
      """,
      ["#{@hero} [data-role=group-hero-details]"],
      &send(self(), {:folded, &1})
    )

    receive do
      {:folded, result} -> result
    end
  end

  defp sign_in(session, user) do
    session
    |> Browser.visit(@endpoint.url() <> "/login")
    |> Browser.fill_in(Query.fillable_field("login_fields[email_or_username]"),
      with: user.character.username
    )
    |> Browser.fill_in(Query.fillable_field("login_fields[password]"), with: @password)
    |> Browser.click(Query.css("#login_submit_btn"))
    |> Browser.assert_has(Query.css(".phx-connected #sidebar-feeds-link"))
  end
end
