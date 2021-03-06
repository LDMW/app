defmodule App.LikesControllerTest do
  use App.ConnCase, async: false

  alias Plug.Conn
  alias App.Likes

  @article_id "10"
  test "POST /like/#{@article_id} - existing article", %{conn: conn} do
    conn =
      conn
        |> Conn.put_resp_cookie("lm_session", String.duplicate("asdf", 8))
        |> post(likes_path(conn, :like, @article_id))

    %Likes{like_value: like_value} = Repo.get_by Likes, article_id: @article_id

    assert like_value == 1
    assert redirected_to(conn) == "/"
  end

  test "POST /dislike/#{@article_id} - existing article", %{conn: conn} do
    conn =
      conn
        |> Conn.put_resp_cookie("lm_session", String.duplicate("asdf", 8))
        |> post(likes_path(conn, :dislike, @article_id))

    %Likes{like_value: like_value} = Repo.get_by Likes, article_id: @article_id

    assert like_value == -1
    assert redirected_to(conn) == "/"
  end

  test "multiple likes for an article", %{conn: conn} do
    conn =
      conn
      |> post(likes_path(conn, :like, @article_id))
      |> post(likes_path(conn, :dislike, @article_id))

    %Likes{like_value: like_value} = Repo.get_by Likes, article_id: @article_id

    assert like_value == -1
    assert redirected_to(conn) == "/"
  end

  test "POST /dislike/#{@article_id} - article with referrer", %{conn: conn} do
    url1 = "http://localhost:4000"
    url2 = "/filter?issue=insomnia&reason=&content=subscription"
    url = url1 <> url2
    conn =
      conn
        |> Conn.put_resp_cookie("lm_session", String.duplicate("asdf", 8))

        |> Conn.put_req_header("referer", url)
        |> post(likes_path(conn, :dislike, @article_id))

    %Likes{like_value: like_value} = Repo.get_by Likes, article_id: @article_id

    assert like_value == -1
    assert redirected_to(conn) == url2
  end

  test "POST /like/#{@article_id} - json request", %{conn: conn} do
    conn =
      conn
        |> Conn.put_resp_cookie("lm_session", String.duplicate("asdf", 8))
        |> Conn.put_req_header("accept", "application/json")
        |> post(likes_path(conn, :like, @article_id))

    assert json_response(conn, 200)
  end

  test "POST /like/#{@article_id} - twice should remove", %{conn: conn} do
    conn =
      conn
        |> Conn.put_resp_cookie("lm_session", String.duplicate("asdf", 8))
        |> post(likes_path(conn, :like, @article_id))
        |> post(likes_path(conn, :like, @article_id))

    refute Repo.get_by Likes, article_id: @article_id
    assert redirected_to(conn) == "/"
  end
end
