defmodule EcoSyncBackend.Scanner do
  @moduledoc """
  Módulo para la detección de secretos y patrones sensibles usando Regex.
  """

  @patterns %{
    "AWS Access Key ID" => ~r/AKIA[0-9A-Z]{16}/i,
    "AWS Secret Access Key" => ~r/SECRET_?[A-Z0-9]{20,40}/i,
    "GitHub Personal Access Token" => ~r/ghp_[a-zA-Z0-9]{36}/,
    "Slack Webhook URL" => ~r/https:\/\/hooks\.slack\.com\/services\/T[a-zA-Z0-9_]+\/B[a-zA-Z0-9_]+\/[a-zA-Z0-9_]+/,
    "Stripe API Key" => ~r/sk_live_[0-9a-zA-Z]{24}/i,
    "Google API Key" => ~r/AIza[0-9A-Za-z-_]{35}/,
    "Generic API/Secret Key" => ~r/(api[_-]?key|secret[_-]?key|password|auth[_-]?token)[\s:=]+['"]([a-zA-Z0-9]{16,})['"]/i
  }

  def scan_content(content) do
    lines = String.split(content, ["\n", "\r\n"])
    
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      @patterns
      |> Enum.filter(fn {_name, regex} -> Regex.run(regex, line) end)
      |> Enum.map(fn {name, _regex} ->
        %{secret_type: name, line_number: line_num}
      end)
    end)
  end
end
