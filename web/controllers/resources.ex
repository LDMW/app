defmodule App.Resources do
  @moduledoc """
  # Functions for querying CMS Database for resources
  """
  use App.Web, :controller

  alias App.{CMSRepo, Repo, Likes}

  def sort_priority(list),
    do: Enum.sort list, &(&1[:priority] <= &2[:priority])

  @doc """
  iex> handle_bold("<h1>Hello <b>World</b></h1><p>more <b>text</b> is <b>here</b></p>") == ~s(<h1>Hello <b class="nunito">World</b></h1><p>more <b class="segoe-bold">text</b> is <b class="segoe-bold">here</b></p>)
  true
  iex> handle_bold("<h1><b>Hello World</b></h1>") == ~s(<h1><b class="nunito">Hello World</b></h1>)
  true
  iex> handle_bold("<p><b>Hello World</b></p>") == ~s(<p><b class="segoe-bold">Hello World</b></p>)
  true
  """
  @nunito_tags 1..6 |> Enum.to_list |> Enum.map(&("h#{&1}"))
  @segio_tags ~w(p li)
  @tags Enum.join @nunito_tags ++ @segio_tags, "|"
  def handle_bold(string) when is_binary(string) do
    case String.contains? string, "<b>" do
      true ->
        "<(#{@tags})>(.*?(?=(?:<\/\\1>)))<\/\\1>"
          |> Regex.compile!
          |> Regex.scan(string)
          |> Enum.map(&(&1 |> List.delete_at(0) |> List.to_tuple))
          |> handle_bold
      _ -> string
    end
  end
  def handle_bold({tag, inner_html}) when tag in @nunito_tags,
    do: add_bold_class {tag, inner_html}, "nunito"
  def handle_bold({tag, inner_html}) when tag in @segio_tags,
    do: add_bold_class {tag, inner_html}, "segoe-bold"
  def handle_bold(list) when is_list(list),
    do: list |> Enum.map(&handle_bold/1) |> Enum.join
  def handle_bold(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, handle_bold(v)} end)
  def handle_bold(other)
    when not (is_list(other) or is_map(other) or is_binary(other)),
    do: other
  defp add_bold_class({tag, inner_html}, class),
    do: String.replace "<#{tag}>#{inner_html}</#{tag}>", "<b>", ~s(<b class="#{class}">)

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
    query
    |> CMSRepo.one
    |> handle_bold
  end

  def get_tags(type) do
    tag_query = from tag in "taggit_tag",
      full_join: h in ^"articles_#{type}tag",
      full_join: l in ^"resources_#{type}tag",
      where: h.tag_id == tag.id or l.tag_id == tag.id,
      select: tag.name,
      order_by: tag.id,
      distinct: tag.id

    CMSRepo.all tag_query
  end

  def get_all_filtered_resources(filter, session_id) do
    "resource"
    |> all_query
    |> get_resources("resource", session_id)
    |> Enum.filter(&filter_by_category(&1, filter))
    |> Enum.filter(&filter_tags(&1, filter))
    |> sort_priority
  end

  def filter_by_category(%{tags: %{"category" => category}}, filter),
    do: Enum.any? category, &(&1 in filter["category"])

  def filter_tags(%{tags: tags}, filter) do
    tags
    |> Map.delete("category")
    |> Enum.any?(fn {tag_type, tags} ->
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

  defp like_filter(map), do: map.value > 0
  defp dislike_filter(map), do: map.value < 0
  defp likes_count(query, filter),
    do: query |> Repo.all |> Enum.filter_map(filter, &(&1.value)) |> Enum.sum
  def get_all_likes(%{id: article_id} = map, lm_session) do
    likequery = from l in Likes,
            where: l.article_id == ^article_id,
            select: %{value: l.like_value, session_id: l.user_hash}
    likesdata = Repo.all likequery
    likes = likes_count(likequery, &like_filter/1)
    dislikes = likes_count(likequery, &dislike_filter/1)
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
