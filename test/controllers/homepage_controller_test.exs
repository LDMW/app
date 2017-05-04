defmodule App.HomepageControllerTest do
  use App.ConnCase

  test "GET /", %{conn: conn} do
    conn = get conn, "/"
    assert html_response(conn, 200) =~ "<!DOCTYPE html>"
  end

  test "lists all entries on index", %{conn: conn} do
    conn = get conn, homepage_path(conn, :index)
    assert html_response(conn, 200) =~ "sleep issues"
  end

  test "renders page not found when id is nonexistent", %{conn: conn} do
    params = %{"audience" => %{"aud" => "false"},
               "category" => %{"category" => "not_found"},
               "content" => %{"cont" => "false"}}
    conn = post conn, homepage_path(conn, :show, params)
    assert html_response(conn, 404)
  end
end
