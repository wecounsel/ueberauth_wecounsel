defmodule Ueberauth.Strategy.Wecounsel do
  @moduledoc """
  Wecounsel Strategy for Überauth.
  """

  use Ueberauth.Strategy, uid_field: :sub, default_scope: "email", hd: nil

  alias OAuth2.Error
  alias OAuth2.Response
  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra
  alias Ueberauth.Strategy.Wecounsel.OAuth

  @doc """
  Handles initial request for Wecounsel authentication.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    opts =
      [scope: scopes]
      |> with_optional(:hd, conn)
      |> with_optional(:approval_prompt, conn)
      |> with_optional(:access_type, conn)
      |> with_param(:access_type, conn)
      |> with_param(:prompt, conn)
      |> with_param(:state, conn)
      |> Keyword.put(:redirect_uri, callback_url(conn))

    redirect!(conn, OAuth.authorize_url!(opts))
  end

  @doc """
  Handles the callback from Wecounsel.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    params = [code: code]
    opts = [redirect_uri: callback_url(conn)]

    case OAuth.get_access_token(params, opts) do
      {:ok, token} ->
        fetch_user(conn, token)

      {:error, {error_code, error_description}} ->
        set_errors!(conn, [error(error_code, error_description)])
    end
  end

  @doc false
  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc false
  def handle_cleanup!(conn) do
    conn
    |> put_private(:wecounsel_user, nil)
    |> put_private(:wecounsel_token, nil)
  end

  @doc """
  Fetches the uid field from the response.
  """
  def uid(conn) do
    uid_field =
      conn
      |> option(:uid_field)
      |> to_string

    conn.private.wecounsel_user[uid_field]
  end

  @doc """
  Includes the credentials from the wecounsel response.
  """
  def credentials(conn) do
    token = conn.private.wecounsel_token
    scope_string = token.other_params["scope"] || ""
    scopes = String.split(scope_string, ",")

    %Credentials{
      expires: present?(token.expires_at),
      expires_at: token.expires_at,
      scopes: scopes,
      token_type: Map.get(token, :token_type),
      refresh_token: token.refresh_token,
      token: token.access_token
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.wecounsel_user

    %Info{
      email: user["email"],
      first_name: user["first_name"],
      last_name: user["last_name"],
      urls: %{
        profile: user["profile"],
        website: user["hd"]
      }
    }
  end

  @doc """
  Stores the raw information (including the token) obtained from the wecounsel callback.
  """
  def extra(conn) do
    user = conn.private.wecounsel_user

    %Extra{
      raw_info: %{
        token: conn.private.wecounsel_token,
        user: conn.private.wecounsel_user,
        user_type: user["user_type"],
        wecounsel_user_id: user["id"]
      }
    }
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :wecounsel_token, token)

    # userinfo_endpoint
    path =
      "#{Application.get_env(:ueberauth_wecounsel, :base_url, "http://api.wecounsel.com")}/oauth/me.json"

    resp = OAuth.get(token, path)

    case resp do
      {:ok, %Response{status_code: 401, body: _body}} ->
        set_errors!(conn, [error("token", "unauthorized")])

      {:ok, %Response{status_code: status_code, body: user}} when status_code in 200..399 ->
        put_private(conn, :wecounsel_user, user)

      {:error, %Response{status_code: status_code}} ->
        set_errors!(conn, [error("OAuth2", status_code)])

      {:error, %Error{reason: reason}} ->
        set_errors!(conn, [error("OAuth2", reason)])
    end
  end

  defp with_param(opts, key, conn) do
    if value = conn.params[to_string(key)], do: Keyword.put(opts, key, value), else: opts
  end

  defp with_optional(opts, key, conn) do
    if option(conn, key), do: Keyword.put(opts, key, option(conn, key)), else: opts
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end

  defp present?(nil), do: false
  defp present?(false), do: false
  defp present?(_), do: true
end
