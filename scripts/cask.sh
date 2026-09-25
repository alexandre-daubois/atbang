#!/bin/sh
set -eu

cat <<CASK
cask "atbang" do
  version "$1"
  sha256 "$2"

  url "https://github.com/alexandre-daubois/atbang/releases/download/v#{version}/Atbang-#{version}.zip"
  name "Atbang"
  desc "Menu bar app that triages GitHub and GitLab notifications with Claude"
  homepage "https://github.com/alexandre-daubois/atbang"

  depends_on formula: "gh"
  depends_on macos: :tahoe

  app "Atbang.app"

  zap trash: [
    "~/Library/Caches/Atbang",
    "~/Library/Preferences/dev.daubois.Atbang.plist",
  ]
end
CASK
