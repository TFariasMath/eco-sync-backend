defmodule EcoSyncBackend.ScannerTest do
  use ExUnit.Case, async: true
  alias EcoSyncBackend.Scanner

  test "scan_content detects common secrets" do
    content = """
    # My secrets
    AWS_KEY=AKIAIOSFODNN7EXAMPLE
    GITHUB=ghp_EXAMPLE1234567890abcdef
    STRIPE=sk_test_EXAMPLE1234567890ab
    GOOGLE=AIzaSyEXAMPLE1234567890abcdef
    """

    findings = Scanner.scan_content(content)

    assert length(findings) == 4
    assert Enum.any?(findings, &(&1.secret_type == "AWS Access Key ID" && &1.line_number == 2))

    assert Enum.any?(
             findings,
             &(&1.secret_type == "GitHub Personal Access Token" && &1.line_number == 3)
           )

    assert Enum.any?(findings, &(&1.secret_type == "Stripe API Key" && &1.line_number == 4))
    assert Enum.any?(findings, &(&1.secret_type == "Google API Key" && &1.line_number == 5))
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
