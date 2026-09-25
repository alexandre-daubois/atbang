# Atbang: triage your GitHub notifications with Claude

Atbang is a free, open-source macOS menu bar app that sorts your unread GitHub notifications by priority with Claude AI. It reads the recent conversation of each pull request and issue, and the report of each security advisory. Each thread gets a priority and a one-line summary of who waits on whom, so you can clear your GitHub inbox without opening the threads one by one.

<p align="center"><img src="demo.png" alt="Atbang, a macOS menu bar app triaging GitHub notifications with Claude" width="360"></p>

## Features

- A priority for each unread notification, `!!!`, `!!` or `!`, and a one-line summary that highlights the people involved as `@mentions`.
- A More… link for a longer explanation of what happened last and who should act next.
- Mark as Done from the list, with the checkmark on hover or the right-click menu.
- Grouping by priority or by repository in one click.
- The unread count in the menu bar, which you can hide.
- A choice of Claude model, Haiku, Sonnet, Opus or Fable, and a refresh interval from 1 minute to 1 hour.
- A cache that skips Claude for threads without new activity.
- A native macOS 26 interface with Liquid Glass, in light and dark mode.

## How it prioritizes

Atbang fetches the thread from GitHub and reads the description, the last 30 comments and the last 20 reviews with their inline comments. It computes some facts itself: the pull request state, who wrote last, whether someone requested your review, the CI status, merge conflicts, new commits since your review, and whether someone mentioned you since your last reply. Claude reads the conversation and these facts, then picks a priority.

`!!!` means someone waits on you: a review requested from you, a question you haven't answered, feedback on your own pull request, or a security advisory assigned to you and still in triage. `!!` deserves a look but blocks nobody, like activity on your pull request, a review requested from one of your teams, or failing CI on your pull request. `!` keeps you informed about a thread you follow without taking part, a question for someone else, a merged pull request, or a thread where you spoke last.

## Install

Atbang needs macOS 26 Tahoe or later. Homebrew adds the tap and installs the GitHub CLI along the way:

```sh
brew install --cask alexandre-daubois/tap/atbang
```

If you had already added the tap, run `brew update` first so Homebrew sees Atbang. Then sign in to GitHub and install Claude Code if you haven't yet:

```sh
gh auth login
curl -fsSL https://claude.ai/install.sh | bash
claude auth login
```

Atbang lands in your Applications folder and runs in the menu bar. It checks both tools when it starts and tells you what's missing. Without Homebrew, download `Atbang-<version>.zip` from the [releases](https://github.com/alexandre-daubois/atbang/releases) and move `Atbang.app` to your Applications folder.

## Update and uninstall

```sh
brew upgrade --cask alexandre-daubois/tap/atbang
brew uninstall --cask --zap alexandre-daubois/tap/atbang
```

`--zap` removes the cache and the settings along with the app.

## Privacy and security

Atbang carries a Developer ID signature and Apple notarizes each release. The app reads from GitHub and writes one thing, marking a thread as done when you ask. It takes the token of the GitHub CLI, keeps it in memory and sends it to `api.github.com` alone. `claude -p` runs without any tool, MCP server or settings. Atbang hands it the thread text as untrusted data, tells Claude to ignore any instruction inside, checks the answer against a strict JSON schema and displays it as plain text.

## License

MIT
