defmodule Farside.Router do
  @index Application.fetch_env!(:farside, :index)
  @route Application.fetch_env!(:farside, :route)

  use Plug.Router

  plug(Farside.Throttle)
  plug(:match)
  plug(:dispatch)

  def get_query_params(conn) do
    cond do
      String.length(conn.query_string) > 0 ->
        "?#{conn.query_string}"

      true ->
        ""
    end
  end

  match "/" do
    resp =
      EEx.eval_file(
        @index,
        last_updated: Farside.get_last_updated(),
        services: Farside.get_services_map()
      )

    send_resp(conn, 200, resp)
  end

  match "/_/:service/*glob" do
    r_path = String.slice(conn.request_path, 2..-1)

    resp =
      EEx.eval_file(
        @route,
        instance_url: "#{r_path}#{get_query_params(conn)}"
      )

    send_resp(conn, 200, resp)
  end

  match "/:service/*glob" do
    service_name = cond do
      service =~ "http" ->
        List.first(glob)
      true ->
        service
    end

    path = cond do
      service_name != service ->
        Enum.join(Enum.slice(glob, 1..-1), "/")
      true ->
        Enum.join(glob, "/")
    end

    instance = cond do
      conn.assigns[:throttle] != nil ->
        Farside.get_service(service_name)
        |> Farside.last_instance
        |> Farside.amend_instance(service_name, path)
      true ->
        Farside.get_service(service_name)
        |> Farside.pick_instance
        |> Farside.amend_instance(service_name, path)
    end

    # Redirect to the available instance
    conn
    |> Plug.Conn.resp(:found, "")
    |> Plug.Conn.put_resp_header(
      "location",
      "#{instance}/#{path}#{get_query_params(conn)}"
    )
  end
end
