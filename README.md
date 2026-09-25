# Atbang: Triage Your GitHub Notifications with Claude

Atbang is a free and open-source macOS menu bar app that sorts your unread GitHub notifications by priority with Claude AI. It reads the recent conversation of every pull request and issue, and the report of every security advisory, works out who is waiting on whom, and gives each thread a priority and a one-line summary, so open-source maintainers can clear their GitHub inbox without opening every thread.

<p align="center"><img src="demo.png" alt="Atbang, a macOS menu bar app triaging GitHub notifications with Claude" width="360"></p>

## Features

- A priority for every unread notification, `!!!`, `!!` or `!`, with a one-line summary where the people involved stand out as `@mentions`.
- A More… link for a longer explanation of what happened last and who should act next.
- Mark as Done straight from the list, with the checkmark that appears on hover or from the right-click menu.
- Grouping by priority or by repository in one click.
- The unread count in the menu bar, which can be hidden.
- A choice of Claude model, Haiku, Sonnet, Opus or Fable, and a refresh interval from 1 minute to 1 hour.
- A cache that only asks Claude again when a thread has new activity.
- A native macOS 26 interface with Liquid Glass, in light and dark mode.

## How it prioritizes

For each notification, Atbang fetches the thread from GitHub and reads its recent conversation: the description, the last 30 comments and the last 20 reviews with their inline comments. It also computes facts it doesn't leave to the model, like the state of the pull request, who wrote last, whether a review was requested from you, the CI status, merge conflicts, new commits since your review and whether someone mentioned you since you last replied. Claude reads both and picks a priority.

`!!!` means someone is waiting on you: a review requested from you directly, a question you haven't answered, feedback on your own pull request, or a security advisory assigned to you that is still in triage. `!!` is worth a look without anyone being blocked, like activity on your pull request, a review requested from one of your teams, or failing CI on your pull request. `!` is for information, like a thread you're only subscribed to, a question addressed to someone else, a merged pull request, or a thread where you spoke last.

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

Atbang lands in your Applications folder and runs in the menu bar. It checks both tools when it starts and tells you what's missing. You can also download `Atbang-<version>.zip` from the [releases](https://github.com/alexandre-daubois/atbang/releases) and move `Atbang.app` to your Applications folder yourself.

## Update and uninstall

```sh
brew upgrade --cask alexandre-daubois/tap/atbang
brew uninstall --cask --zap alexandre-daubois/tap/atbang
```

`--zap` also removes the cache and the settings.

## Privacy and security

Atbang is signed with a Developer ID and notarized by Apple. It only reads from GitHub, with one exception: marking a thread as done when you ask for it. It uses the token of the GitHub CLI, keeps it in memory and only ever sends it to `api.github.com`. Claude runs through `claude -p` without any tool, MCP server or settings, the text of a thread is handed over as untrusted data that Claude summarizes but never obeys, and its answer is checked against a strict JSON schema before being displayed as plain text.

## Build from source

```sh
swift test
./scripts/bundle.sh
```

The script builds a universal `build/Atbang.app` and zips it for release.

## License

MIT
