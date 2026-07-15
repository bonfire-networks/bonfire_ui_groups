# SEO/social-card metadata for group & topic (Category) profile pages, so that sharing a group to
# X, Mastodon, Slack, etc. shows its name, description and image instead of the generic instance
# defaults. Without these, a Category would fall through to phoenix_seo's `Any` fallback, which
# blindly shovels its loaded assocs (e.g. `:creator`) into the meta structs and crashes on render.
#
# The title/description/image extraction is shared with the generic path in `Bonfire.UI.Common.SEO`.
alias Bonfire.UI.Common.SEO, as: CommonSEO

defimpl SEO.Site.Build, for: Bonfire.Classify.Category do
  def build(category, _conn) do
    SEO.Site.build(
      title: CommonSEO.seo_title(category),
      description: CommonSEO.seo_description(category)
    )
  end
end

defimpl SEO.OpenGraph.Build, for: Bonfire.Classify.Category do
  def build(category, _conn) do
    SEO.OpenGraph.build(
      title: CommonSEO.seo_title(category),
      description: CommonSEO.seo_description(category),
      url: Bonfire.Common.URIs.canonical_url(category, preload_if_needed: false),
      image: CommonSEO.seo_image(category)
    )
  end
end

defimpl SEO.Twitter.Build, for: Bonfire.Classify.Category do
  def build(category, _conn) do
    image = CommonSEO.seo_image(category)

    SEO.Twitter.build(
      title: CommonSEO.seo_title(category),
      description: CommonSEO.seo_description(category),
      image: image,
      card: if(image, do: :summary_large_image, else: :summary)
    )
  end
end
