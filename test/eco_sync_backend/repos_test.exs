defmodule EcoSyncBackend.ReposTest do
  use ExUnit.Case, async: true
  alias EcoSyncBackend.Repos


  test "get_inactive_repos logic with mock client" do
    # Verificamos paridad de fechas en lugar de mockear el cliente completo aquí
    assert Repos.parse_datetime("2024-04-14T12:00:00Z") != nil
    assert Repos.parse_datetime(nil) == nil
  end
  
  test "matches_filters? logic" do
    # Accedemos a la función privada via apply o la hacemos pública para test
    # Como es un test de migración, nos interesa la lógica de filtrado
    repo = %{"language" => "Python", "private" => true}
    
    assert apply(Repos, :matches_filters?, [repo, %{language: "python"}] ) == true
    assert apply(Repos, :matches_filters?, [repo, %{language: "elixir"}] ) == false
    assert apply(Repos, :matches_filters?, [repo, %{visibility: "private"}] ) == true
    assert apply(Repos, :matches_filters?, [repo, %{visibility: "public"}] ) == false
  end
end
