defmodule Bonfire.UI.Groups.GroupSEOTest do
  @moduledoc """
  A group/topic profile page must emit meaningful SEO/social-card metadata (name, description) for
  guests, and must NOT crash by leaking a preloaded assoc (e.g. `:creator`, a `%Needle.Pointer{}`)
  into the meta tags — the failure mode before the Category `SEO.*.Build` impls + generic guard.

  SEO is only assigned on the guest, disconnected (dead) render — the one crawlers/unfurlers fetch —
  so this drives a plain guest `GET` (not a connected LiveView mount).
  """
  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  alias Bonfire.Classify.Simulate

  test "emits SEO meta with the group's name/description and no leaked struct" do
    account = fake_account!()
    me = fake_user!(account)

    group =
      Simulate.fake_group!(me, %{
        name: "Astronomy Club",
        summary: "We gather to look at the stars.",
        visibility: "nonfederated:discoverable",
        membership: "local:members",
        participation: "local:contributors"
      })

    html =
      build_conn()
      |> get(Bonfire.Common.URIs.path(group))
      |> html_response(200)

    assert html =~ ~s(property="og:title")
    assert html =~ "Astronomy Club"
    assert html =~ "We gather to look at the stars."

    # regression: the Category's preloaded `:creator` assoc must never reach the meta tags
    refute html =~ "Needle.Pointer"
  end
end
