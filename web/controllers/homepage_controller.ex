defmodule App.HomepageController do
  use App.Web, :controller
  alias App.Resources, as: R
  alias App.Search
  import App.SubmitController, only: [submit: 2]

  def index(conn, _params) do
    session = get_session conn, :lm_session
    resources = "resource"
      |> R.all_query
      |> R.get_resources("resource", session)
      |> R.sort_priority

    render conn, "index.html", content: get_content(),
                 tags: R.get_tags(), resources: resources
  end

  def show(conn, params = %{
      "category" => %{"add_your_own" => cat_suggestion},
      "audience" => %{"add_your_own" => aud_suggestion},
      "content" => %{"add_your_own" => con_suggestion}
    }
  ) when (cat_suggestion <> aud_suggestion <> con_suggestion) != ""  do
    conn
    |> submit(%{"tag_suggestion" => [cat_suggestion, aud_suggestion, con_suggestion]})
    |> redirect(to: homepage_path(conn, :show, params))
  end
  def show(conn, params) do
    prepend = fn(a, b) -> b <> a end
    query_string =
      params
        |> Map.take(["audience", "content", "category"])
        |> create_query_string
        |> prepend.("?")

    redirect(conn, to: homepage_path(conn, :filtered_show) <> query_string)
  end

  def filtered_show(conn, params) when params == %{}, do: index(conn, params)
  def filtered_show(conn, params) do
    filters = params
      |> check_empty
      |> Enum.map(&create_filters/1)
      |> Map.new

    selected_tags = filters
      |> Enum.reduce([], fn {type, tags}, acc ->
        case type do
          "q" -> acc
          _ -> acc ++ tags
        end
      end)
      |> Enum.filter(&(!String.starts_with?(&1, "all-")))

    session = get_session conn, "lm_session"
    all_resources =
      filters
      |> R.get_all_filtered_resources(session)
      |> filter_search(params["q"])

    render conn, "index.html",
      content: get_content(), tags: R.get_tags(),
      resources: all_resources, selected_tags: selected_tags, query: params["q"]
  end

  def create_filters({tag_type, tags}) do
     {tag_type, String.split(tags, ",")}
   end

  def check_empty(params) do
    params
    |> Enum.filter_map(fn
        {"", _} -> nil
        _ -> true
      end, fn
        {name, ""} -> {name, "all-#{name}"}
        {name, tags} -> {name, tags}
      end)
  end

  def get_content do
    [:body, :footer, :alpha, :alphatext, :lookingfor,
     :filter_label_1, :filter_label_2, :filter_label_3,
     :assessment_text, :crisis_text]
    |> R.get_content
    |> Map.merge(%{hero_image_url: R.get_image_url("hero_image", "home")})
  end

  def create_query_string(params) do
    params
    |> Enum.map(fn {tag_type, tag} ->
      {tag_type,
       tag
       |> Enum.reduce("", fn({t, bool}, a) ->
           if bool == "true" do
             "#{a}#{t},"
           else
             a
           end
         end)
       |> String.trim(",")
       |> remove_all_type_tags(tag_type)}
    end)
    |> URI.encode_query
  end

  def remove_all_type_tags(str, type) do
    type_tag_string = "all-#{type}"
    if str != type_tag_string do
      str
      |> String.replace(type_tag_string, "")
      |> String.trim(",")
    end
  end

  def search(conn, %{"query" => %{"q" => q}} = params) do
    query = URI.decode_query(params["query"]["query_string"])
    query_string =
      case Map.get(query, "q") do
        nil -> "?" <> URI.encode_query(q: q) <> "&" <> params["query"]["query_string"]
        _ -> "?" <> URI.encode_query(Map.update!(query, "q", fn _ -> q end))
      end

    redirect(conn, to: homepage_path(conn, :filtered_show) <> query_string)
  end

  def filter_search(resources, nil), do: resources
  def filter_search(resources, query) do
    Enum.filter(resources, &(Search.find_matches &1, Search.split_text query))
  end
end
