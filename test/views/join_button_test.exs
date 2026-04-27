defmodule Bonfire.UI.Groups.JoinButtonTest do
  @moduledoc "Pins that group_live.sface always passes membership_slug= to ProfileHeroFullLive."

  use Bonfire.UI.Groups.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  @moduletag :ui

  @sface_path Path.join(__DIR__, "../../lib/views/group/group_live.sface") |> Path.expand()

  test "every <ProfileHeroFullLive> in group_live.sface passes membership_slug" do
    source = File.read!(@sface_path)

    hero_blocks =
      Regex.scan(
        ~r/<StatefulComponent\b[^>]*?Bonfire\.UI\.Me\.ProfileHeroFullLive[\s\S]*?\/>/,
        source
      )

    assert length(hero_blocks) >= 1,
           "expected at least one <ProfileHeroFullLive> usage in #{@sface_path}"

    missing = for [block] <- hero_blocks, not (block =~ "membership_slug"), do: block

    assert missing == [],
           "ProfileHeroFullLive rendered without `membership_slug=` in #{@sface_path}:\n\n" <>
             Enum.join(missing, "\n\n--\n\n")
  end
end
