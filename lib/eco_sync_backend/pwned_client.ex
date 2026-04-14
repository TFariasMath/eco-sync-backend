defmodule EcoSyncBackend.PwnedClient do
  @moduledoc """
  Cliente para la API de HaveIBeenPwned.
  Permite detectar si una cuenta de correo ha sido comprometida en filtraciones de datos.
  """
  require Logger

  @api_base "https://haveibeenpwned.com/api/v3"

  defstruct [:api_key, :req]

  @doc """
  Crea una nueva instancia del cliente. Requiere una API Key de HIBP.
  """
  def new(api_key \\ nil) do
    # Si no hay API key del sistema, intentamos obtenerla de env
    key = api_key || System.get_env("HIBP_API_KEY")
    
    headers = [
      {"user-agent", "EcoSync-Elixir/1.0"},
      {"accept", "application/json"}
    ]

    headers = if key, do: [{"hibp-api-key", key} | headers], else: headers

    req = Req.new(
      base_url: @api_base,
      headers: headers
    )

    %__MODULE__{api_key: key, req: req}
  end

  @doc """
  Consulta las filtraciones (breaches) asociadas a una cuenta o correo.
  Retorna una lista vacía si la cuenta está 'limpia' (Status 404).
  """
  def get_breaches_for_account(client, account) do
    url = "/breachedaccount/#{account}"
    
    case Req.get(client.req, url: url, params: [truncateResponse: false]) do
      {:ok, %{status: 200, body: body}} ->
        body
      
      {:ok, %{status: 404}} ->
        # 404 en HIBP significa que no hay filtraciones encontradas
        []
        
      {:ok, %{status: 401}} ->
        Logger.error("HIBP Auth Error: API Key invalida o faltante.")
        {:error, :unauthorized}
        
      {:ok, %{status: 429}} ->
        Logger.error("HIBP Rate Limit: Limite de peticiones excedido.")
        {:error, :rate_limit}

      {:ok, %{status: status, body: body}} ->
        Logger.error("HIBP API Error #{status}: #{inspect(body)}")
        {:error, status}

      {:error, reason} ->
        Logger.error("HIBP Connection Error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
