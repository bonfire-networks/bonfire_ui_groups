defmodule Bonfire.UI.Groups.GroupLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(%{"id" => id} = params, session, socket) when id != "" do
    with {:ok, socket} <-
           undead_mount(socket, fn ->
             Bonfire.Classify.LiveHandler.mounted(params, session, socket)
           end) do
      if e(assigns(socket), :type, nil) == :topic do
        {:ok, assign(socket, page: "topic", showing_within: :topic)}
      else
        {:ok, assign(socket, page: "group", showing_within: :group)}
      end
    end
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> redirect_to("/groups")}
  end

  def handle_params(params, uri, socket) do
    {:noreply, socket} = Bonfire.Classify.LiveHandler.handle_params(params, uri, socket)
    {:noreply, maybe_patch_to_canonical_topic_url(socket, uri)}
  end

  # A topic reached via a non-canonical URL (e.g. the feed's `/&<topic_id>` group link) is
  # normalised in place to `/<group>/topic/<topic>` — same LiveView, so `push_patch` reuses the
  # already-loaded data (no remount). Usernames are preferred over ids when available.
  # `replace: true` so the non-canonical URL doesn't linger in the history stack, where
  # going back to it would just re-patch forward (back button trap).
  defp maybe_patch_to_canonical_topic_url(socket, uri) do
    category = e(assigns(socket), :category, nil)
    group = e(category, :parent_category, nil)

    # `:type` is the assign (defaults to `:topic` when the field is nil), matching the template
    if e(assigns(socket), :type, nil) == :topic and not is_nil(group) do
      topic_slug = e(category, :character, :username, nil) || id(category)
      canonical = path(group) <> "/topic/" <> topic_slug

      if URI.parse(uri).path != canonical,
        do: push_patch(socket, to: canonical, replace: true),
        else: socket
    else
      socket
    end
  end

  def tab(selected_tab) do
    case maybe_to_atom(selected_tab) do
      tab when is_atom(tab) -> tab
      _ -> :timeline
    end
    |> debug(selected_tab)
  end

  def tab_component(selected_tab) do
    default = nil
    tab_section = Config.get([:ui, :group, :sections], [])[tab(selected_tab)]

    if not is_nil(tab_section) and is_atom(tab_section) and module_enabled?(tab_section) do
      debug(tab_section, "ok")
      tab_section
    else
      debug("default")
      default
    end
  end
end
