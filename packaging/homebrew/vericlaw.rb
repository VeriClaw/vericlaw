# typed: false
# frozen_string_literal: true

class Vericlaw < Formula
  desc "Formally verified AI agent runtime built with Ada/SPARK"
  homepage "https://github.com/vericlaw/vericlaw"
  version "0.1.0"
  license "Apache-2.0"
  # Pre-built binaries — no source compilation required
  bottle :unneeded

  on_macos do
    on_arm do
      url "https://github.com/vericlaw/vericlaw/releases/download/v#{version}/vericlaw-v#{version}-macos-universal.tar.gz"
      sha256 "PLACEHOLDER_SHA256_MACOS_ARM64"
    end
    on_intel do
      url "https://github.com/vericlaw/vericlaw/releases/download/v#{version}/vericlaw-v#{version}-macos-universal.tar.gz"
      sha256 "PLACEHOLDER_SHA256_MACOS_X86_64"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/vericlaw/vericlaw/releases/download/v#{version}/vericlaw-v#{version}-linux-aarch64.tar.gz"
      sha256 "PLACEHOLDER_SHA256_LINUX_AARCH64"
    end
    on_intel do
      url "https://github.com/vericlaw/vericlaw/releases/download/v#{version}/vericlaw-v#{version}-linux-x86_64.tar.gz"
      sha256 "PLACEHOLDER_SHA256_LINUX_X86_64"
    end
  end

  def install
    bin.install "vericlaw"
  end

  def caveats
    <<~EOS
      To get started:
        vericlaw init          # Create config file
        vericlaw doctor        # Verify installation
        vericlaw agent         # Start agent
      
      Configuration: ~/.vericlaw/config/agent.json
      Documentation: https://github.com/vericlaw/vericlaw#readme

      Note: Homebrew requires 64-bit ARM (aarch64). For 32-bit ARM
      (Raspberry Pi 2/3 with Raspbian), use the install script:
        curl -fsSL https://get.vericlaw.dev | sh
    EOS
  end

  test do
    assert_match "vericlaw", shell_output("#{bin}/vericlaw --version")
  end
end
