# Atbang: Triage Your GitHub Notifications with Claude

Atbang is a free and open-source macOS menu bar app that sorts your unread GitHub notifications by priority with Claude AI. Every pull request, issue, review request, mention and security advisory gets a one-line summary and a priority, `!!!` when someone is waiting on you, `!!` when it's worth a look and `!` when it's just for information, so open-source maintainers can clear their GitHub inbox without opening every thread.

<p align="center"><img src="demo.png" alt="Atbang, a macOS menu bar app triaging GitHub notifications with Claude" width="360"></p>

## Install

Atbang needs macOS 26 Tahoe or later. Homebrew adds the tap and installs the GitHub CLI along the way:

```sh
brew install --cask alexandre-daubois/tap/atbang
```

If the tap was already there, for Ember for instance, run `brew update` first so Homebrew sees Atbang. Then sign in to GitHub and install Claude Code if you haven't yet:

```sh
gh auth login
curl -fsSL https://claude.ai/install.sh | bash
claude auth login
```

Atbang lands in your Applications folder and runs in the menu bar. It checks both tools when it starts and tells you what's missing.

## Update and uninstall

```sh
brew upgrade --cask alexandre-daubois/tap/atbang
brew uninstall --cask --zap alexandre-daubois/tap/atbang
```

`--zap` also removes the cache and the settings.

Atbang only reads your GitHub notifications, except when you mark a thread as done. It isn't notarized yet, so the cask removes its quarantine flag.
