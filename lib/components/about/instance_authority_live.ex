defmodule Bonfire.UI.Groups.InstanceAuthorityLive do
  @moduledoc "The line under a group's moderators saying the instance hosting the group has authority over it too, with a link to the instance's rules. Only for groups hosted here: a mirror's admins and rules are elsewhere."
  use Bonfire.UI.Common.Web, :stateless_component

  prop category, :any, required: true

  @doc "The name of this instance, as its footer shows it."
  def instance_name,
    do: Config.get([:ui, :theme, :instance_name]) || Bonfire.Common.URIs.base_domain()

  def rules_path do
    "/conduct"
  end
end
