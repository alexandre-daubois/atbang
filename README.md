# Atbang

A macOS menu bar app that triages your unread GitHub notifications with Claude, so you see at a glance which ones need you (`!!!`), are worth a look (`!!`) or are just for information (`!`).

![Atbang](demo.png)

```sh
brew install --cask alexandre-daubois/tap/atbang
```

It needs macOS 26 or later, and the GitHub CLI and Claude Code both signed in (`gh auth login`, `claude auth login`). It only reads from GitHub, except when you mark a thread as done. The app isn't notarized yet, so the cask removes its quarantine flag.
