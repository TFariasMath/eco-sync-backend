defmodule EcoSyncBackend.OSINTScanner do
  @moduledoc """
  Escáner OSINT para enumeración de nombres de usuario en múltiples plataformas.
  Detecta cuentas potencialmente olvidadas para reducir la basura digital.
  """
  require Logger

  @type platform_result :: %{
          platform: String.t(),
          found: boolean(),
          url: String.t(),
          delete_url: String.t(),
          estimated_co2_grams: non_neg_integer()
        }

  @type osint_result :: %{
          username: String.t(),
          platforms: [platform_result()],
          total_co2_grams: non_neg_integer()
        }

  @platforms %{
    "GitHub" => {"https://github.com/{}", "https://github.com/settings/admin", 120},
    "Reddit" => {"https://www.reddit.com/user/{}", "https://www.reddit.com/prefs/deactivate", 80},
    "Twitter/X" => {"https://twitter.com/{}", "https://twitter.com/settings/deactivate", 90},
    "Instagram" =>
      {"https://www.instagram.com/{}/",
       "https://www.instagram.com/accounts/remove/request/permanent/", 150},
    "Pinterest" =>
      {"https://www.pinterest.com/{}/", "https://www.pinterest.com/settings/account-settings",
       110},
    "Spotify" =>
      {"https://open.spotify.com/user/{}", "https://support.spotify.com/close-account/", 60},
    "HackerNews" => {"https://news.ycombinator.com/user?id={}", "mailto:hn@ycombinator.com", 10},
    "Patreon" => {"https://www.patreon.com/{}", "https://www.patreon.com/settings/account", 40},
    "Vimeo" => {"https://vimeo.com/{}", "https://vimeo.com/settings/account", 130},
    "SoundCloud" => {"https://soundcloud.com/{}", "https://soundcloud.com/settings/account", 140},
    "Blogger" =>
      {"https://{}.blogspot.com", "https://support.google.com/blogger/answer/41387", 30},
    "Medium" => {"https://medium.com/@{}", "https://medium.com/me/settings/account", 50},
    "Dev.to" => {"https://dev.to/{}", "https://dev.to/settings/account", 20},
    "GitLab" => {"https://gitlab.com/{}", "https://gitlab.com/-/profile/account", 115},
    "BitBucket" => {"https://bitbucket.org/{}/", "https://bitbucket.org/account/settings/", 100},
    "Wattpad" => {"https://www.wattpad.com/user/{}", "https://www.wattpad.com/user_close", 70},
    "Flickr" =>
      {"https://www.flickr.com/people/{}/", "https://www.flickr.com/account/delete", 160},
    "DeviantArt" =>
      {"https://www.deviantart.com/{}", "https://www.deviantart.com/settings/deactivation", 125}
  }

  @doc """
  Escanea de forma paralela todas las plataformas buscando el nombre de usuario.
  """
  @spec scan_username(String.t()) :: osint_result()
  def scan_username(username) do
    Logger.info("Iniciando escaneo OSINT para usuario: #{username}")

    # Task.async_stream permite concurrencia masiva y controlada
    results =
      @platforms
      |> Task.async_stream(
        fn {name, {url_template, delete_url, co2}} ->
          check_platform(name, username, url_template, delete_url, co2)
        end, max_concurrency: 10, timeout: 5000)
      |> Enum.reduce([], fn
        {:ok, {:found, account}}, acc -> [account | acc]
        _, acc -> acc
      end)
      |> Enum.sort_by(& &1.platform)

    total_co2 = Enum.reduce(results, 0, fn acc, res -> res + acc.estimated_co2_grams end)

    %{
      username: username,
      accounts_found: length(results),
      total_co2_grams: total_co2,
      platforms: results
    }
  end

  defp check_platform(name, username, url_template, delete_url, co2) do
    url = String.replace(url_template, "{}", username)
    headers = [{"user-agent", user_agent()}]

    # Usamos Req para verificar la existencia (Status 200)
    case Req.get(url, headers: headers, follow_redirects: true, retry: false) do
      {:ok, %{status: 200}} ->
        {:found,
         %{
           platform: name,
           profile_url: url,
           delete_url: delete_url,
           estimated_co2_grams: co2,
           status: "found"
         }}

      _ ->
        :not_found
    end
  end

  defp user_agent do
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  end
end
