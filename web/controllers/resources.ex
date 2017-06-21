defmodule App.Resources do
  @moduledoc """
  # Functions for querying CMS Database for resources
  """
  use App.Web, :controller

  alias App.Likes

  @bucket_name Application.get_env :app, :bucket_name

  def sort_priority(list),
    do: Enum.sort list, &(&1[:priority] <= &2[:priority])

  @doc """
    iex> get_content(:alphatext) =~ "Take part in our ALPHA"
    true
    iex> get_content([:body, :footer]).body =~ "London Minds"
    true
    iex> get_content([:body, :footer]).footer =~ ""
    true
    iex> get_content(:alphatext, "feedback") =~ ""
    true
  """
  def get_content(content), do: get_content(content, "home")
  def get_content(content, view) when is_binary(view) do
    tuple = case view do
      "home" -> {"/home/", "home_homepage"}
      _ -> {"/home/#{view}/", "#{view}_#{view}page"}
    end
    get_content(content, tuple)
  end
  def get_content(content, {url_path, table_name})
    when is_list(content) or is_atom(content)
    do
    query = from page in "wagtailcore_page",
              where: page.url_path == ^url_path,
              join: h in ^table_name,
              where: h.page_ptr_id == page.id
    query = case is_atom(content) do
      true -> from [_page, h] in query, select: field(h, ^content)
      false -> from [_page, h] in query, select: map(h, ^content)
    end

    CMSRepo.one query
  end

  def get_image_url(col_name, view) do
    image_id = "#{col_name}_id"
      |> String.to_atom
      |> get_content(view)
    url = "wagtailimages_image"
      |> where([image], image.id == ^image_id)
      |> select([image], image.file)
      |> CMSRepo.one

    "https://s3.amazonaws.com/#{@bucket_name}/#{url}"
  end

  def get_tags do
    tag_query = from tag in "taggit_tag",
      full_join: rc in ^"resources_categorytag",
      full_join: ra in ^"resources_audiencetag",
      full_join: rco in ^"resources_contenttag",
      where: rc.tag_id == tag.id or ra.tag_id == tag.id or rco.tag_id == tag.id,
      select: %{
        category: rc.tag_id, audience: ra.tag_id,
        content: rco.tag_id, name: tag.name, id: tag.id
      },
      order_by: tag.id,
      distinct: tag.id

    tag_query
    |> CMSRepo.all
    |> Enum.reduce(%{}, fn %{
        audience: aud, category: cat, content: con, id: id, name: name
      }, acc ->
      cond do
        aud == id -> Map.merge acc,
          %{audience: Map.get(acc, :audience, []) ++ [name]}
        cat == id -> Map.merge acc,
          %{category: Map.get(acc, :category, []) ++ [name]}
        con == id -> Map.merge acc,
          %{content: Map.get(acc, :content, []) ++ [name]}
      end
    end)
  end

  def get_all_filtered_resources(filter, session_id) do
    "resource"
    |> all_query
    |> get_resources("resource", session_id)
    |> Enum.filter(&filter_by_category(&1, filter))
    |> Enum.filter(&filter_tags(&1, filter))
    |> sort_priority
  end

  def filter_by_category(
    %{tags: %{"category" => category}},
    %{"category" => categories}), do: Enum.any? category, &(&1 in categories)
  def filter_by_category(_params, _filter), do: true

  def filter_tags(%{tags: tags}, filter) do
    tags
    |> Map.delete("category")
    |> Enum.any?(fn {tag_type, tags} ->
      !Map.has_key?(filter, tag_type) ||
      Enum.any? tags, &(&1 in filter[tag_type])
    end)
  end

  def all_query(type) do
    from r in "#{type}s_#{type}page",
      select: %{
        id: r.page_ptr_id,
        heading: r.heading,
        url: r.resource_url,
        body: r.body,
        video: r.video_url,
        priority: r.priority
      }
  end

  def get_resources(query, type, lm_session) do
    query
      |> CMSRepo.all
      |> Enum.map(&get_all_tags(&1, type))
      |> Enum.map(&get_all_likes(&1, lm_session))
  end

  def get_single_resource(conn, id) do
    session = get_session conn, :lm_session

    query = from r in "resources_resourcepage",
      where: r.page_ptr_id == ^String.to_integer(id),
      select: %{
        id: r.page_ptr_id,
        heading: r.heading,
        url: r.resource_url,
        body: r.body,
        video: r.video_url,
        priority: r.priority
      }

    query
    |> CMSRepo.one
    |> get_all_tags("resource")
    |> get_all_likes(session)
  end

  defp likes_count(data, filter),
    do: data |> Enum.filter_map(filter, &(&1.value)) |> Enum.sum

  def get_all_likes(%{id: article_id} = map, lm_session) do
    likequery = from l in Likes,
            where: l.article_id == ^article_id,
            select: %{value: l.like_value, session_id: l.user_hash}

    likesdata = Repo.all likequery

    likes = likes_count(likesdata, &(&1.value > 0))
    dislikes = likes_count(likesdata, &(&1.value < 0))

    liked = case Enum.find likesdata, &(&1.session_id == lm_session) do
      nil -> "none"
      %{value: value} -> value
    end

    Map.merge map, %{likes: likes, dislikes: dislikes, liked: liked}
  end

  def get_all_tags(resource, type) do
    tags =
      ["category", "audience", "content"]
        |> Enum.map(&create_query(&1, resource, type))
        |> Enum.map(fn {type, query} -> {type, CMSRepo.all(query)} end)
        |> Enum.map(&add_all_filter/1)
        |> Map.new
    Map.merge(%{tags: tags}, resource)
  end

  def add_all_filter({type, list}),
    do: {type, list ++ ["all-#{type}"]}

  def create_query(tag_type, resource, type) do
    query = from t in "taggit_tag",
      left_join: tt in ^"#{type}s_#{tag_type}tag",
      where: t.id == tt.tag_id,
      where: ^resource.id == tt.content_object_id,
      select: t.name,
      distinct: t.name

    {tag_type, query}
  end
end
