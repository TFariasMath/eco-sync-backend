defmodule EcoSyncBackend.ScannerTest do
  use ExUnit.Case, async: true
  alias EcoSyncBackend.Scanner

  test "scan_content detects common secrets" do
    content = """
    AWS_KEY=AKIAIOSFODNN7EXAMPLE
    GITHUB_TOKEN=ghp_EXAMPLE1234567890abcdef
    STRIPE_KEY=sk_test_EXAMPLE1234567890ab
    GOOGLE_API=AIzaSyEXAMPLE1234567890abcdef
    """

    findings = Scanner.scan_content(content)

    assert length(findings) >= 1
    assert Enum.any?(findings, fn f -> f.secret_type == "AWS Access Key ID" end)
  end

  test "scan_content detects generic password patterns" do
    content = "password = 'superSecret123456'"
    findings = Scanner.scan_content(content)

    assert length(findings) == 1
    assert List.first(findings).secret_type == "Generic API/Secret Key"
  end

  test "scan_content returns empty list when no secrets found" do
    content = "this is a normal file without secrets"
    assert Scanner.scan_content(content) == []
  end
end
