# Atbang: triage your GitHub notifications with Claude

Atbang is a free and open-source macOS menu bar app that sorts your unread GitHub notifications by priority with Claude AI. Every pull request, issue, review request, mention and security advisory gets a one-line summary and a priority, `!!!` when someone is waiting on you, `!!` when it's worth a look and `!` when it's just for information, so open-source maintainers can clear their GitHub inbox without opening every thread.

<p align="center"><img src="demo.png" alt="Atbang, a macOS menu bar app triaging GitHub notifications with Claude" width="360"></p>

## Install

```sh
brew install --cask alexandre-daubois/tap/atbang
```

Atbang needs macOS 26 Tahoe or later, the GitHub CLI (`gh auth login`) and Claude Code (`claude auth login`). It only reads your GitHub notifications, except when you mark a thread as done, and the cask removes the quarantine flag because the app isn't notarized yet.
