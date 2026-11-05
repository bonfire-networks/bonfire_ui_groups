defmodule Bonfire.UI.Groups.SensitiveNoticeLive do
  @moduledoc "Shows the group hero and a content warning in place of the feed of a group or topic marked sensitive, until \"Continue\", which is not remembered: every visit shows it again, to members and guests alike."
  use Bonfire.UI.Common.Web, :stateless_component

  slot header
end
