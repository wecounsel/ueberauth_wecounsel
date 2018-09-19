defmodule Ueberauth.Strategy.Wecounsel.OAuth do
  @moduledoc """
  OAuth2 for Wecounsel.

  Add `client_id` and `client_secret` to your configuration:

  config :ueberauth, Ueberauth.Strategy.Wecounsel.OAuth,
    client_id: System.get_env("WECOUNSEL_APP_ID"),
    client_secret: System.get_env("WECOUNSEL_APP_SECRET")
  """
  use OAuth2.Strategy

  alias OAuth2.Client
  alias OAuth2.Strategy.AuthCode

  def defaults() do
    [
      strategy: __MODULE__,
      site: "#{Application.get_env(:ueberauth_wecounsel, :base_url, "http://api.wecounsel.com")}",
      authorize_url:
        "#{Application.get_env(:ueberauth_wecounsel, :base_url, "http://api.wecounsel.com")}/oauth/authorize",
      token_url:
        "#{Application.get_env(:ueberauth_wecounsel, :base_url, "http://api.wecounsel.com")}/oauth/token"
    ]
  end

  @doc """
  Construct a client for requests to Wecounsel.

  This will be setup automatically for you in `Ueberauth.Strategy.Wecounsel`.

  These options are only useful for usage outside the normal callback phase of Ueberauth.
  """
  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Wecounsel.OAuth)

    opts =
      defaults()
      |> Keyword.merge(config)
      |> Keyword.merge(opts)

    Client.new(opts)
  end

  @doc """
  Provides the authorize url for the request phase of Ueberauth. No need to call this usually.
  """
  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client
    |> Client.authorize_url!(params)
  end

  def get(token, url, headers \\ [], opts \\ []) do
    [token: token]
    |> client
    |> put_param("client_secret", client().client_secret)
    |> Client.get(url, headers, opts)
  end

  def get_access_token(params \\ [], opts \\ []) do
    case opts |> client |> Client.get_token(params) do
      {:error, %{body: %{"error" => error, "error_description" => description}}} ->
        {:error, {error, description}}

      {:ok, %{token: %{access_token: nil} = token}} ->
        %{"error" => error, "error_description" => description} = token.other_params
        {:error, {error, description}}

      {:ok, %{token: token}} ->
        {:ok, token}
    end
  end

  # Strategy Callbacks

  def authorize_url(client, params) do
    AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    client
    |> put_param("client_secret", client.client_secret)
    |> put_header("Accept", "application/json")
    |> AuthCode.get_token(params, headers)
  end
end
