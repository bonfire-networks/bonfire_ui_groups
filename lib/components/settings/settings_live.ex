defmodule Bonfire.UI.Groups.SettingsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any, default: nil
  prop tab_id, :any, default: nil
  prop category, :any, required: true
  prop flash, :map, default: %{}
  prop permalink, :any, required: true
  prop object_boundary, :any, default: nil
  prop boundary_preset, :any, default: nil
  prop group_member_count, :integer, default: nil
  prop moderators, :list, default: []
  prop group_membership_slug, :string, default: nil
  prop group_visibility_slug, :string, default: nil


  @doc "Resolves the heading from the extension-configured settings navigation."
  def page_title(selected_tab) do
    Config.get([:ui, :group, :settings, :navigation], [])[tab(selected_tab)] || l("Group settings")
  end

  @doc "Resolves the configured settings component once per render."
  def render(assigns) do
    assigns
    |> assign(:settings_component, tab_component(assigns.tab_id || assigns.selected_tab))
    |> render_sface()
  end

  def tab(selected_tab) do
    case maybe_to_atom(selected_tab) do
      tab when is_atom(tab) -> tab
      _ -> :timeline
    end
  end

  @doc "Resolves dedicated settings pages while keeping extension-configured sections available."
  def tab_component(selected_tab) do
    default = Bonfire.UI.Groups.Settings.GeneralLive
    tab_section = Config.get([:ui, :group, :settings, :sections], [])[tab(selected_tab)]

    if not is_nil(tab_section) and is_atom(tab_section) and module_enabled?(tab_section) do
      tab_section
    else
      default
    end
  end
end
