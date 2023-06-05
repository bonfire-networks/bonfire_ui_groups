defmodule Bonfire.UI.Groups.SettingsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any, default: nil
  prop tab_id, :any, default: nil
  prop category, :any, required: true
  prop permalink, :any, required: true
  prop object_boundary, :any, default: nil
  prop boundary_preset, :any, default: nil

  def tab(selected_tab) do
    case maybe_to_atom(selected_tab) do
      tab when is_atom(tab) -> tab
      _ -> :timeline
    end
    |> debug(selected_tab)
  end

  def tab_component(selected_tab) do
    default = Bonfire.UI.Groups.Settings.GeneralLive
    tab_section = Config.get([:ui, :group, :settings, :sections, tab(selected_tab)])

    if not is_nil(tab_section) and is_atom(tab_section) and module_enabled?(tab_section) do
      debug(tab_section, "ok")
      tab_section
    else
      debug("default")
      default
    end
  end
end
