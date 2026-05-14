# dotfiles

Shared zsh / vim / git config for the team.

## What's in here

| File | Purpose |
|---|---|
| `.zshrc` | Prompt, PATH, git helpers (`git up`, `git stack`, `cb`, `gph`, `gbd`), aliases |
| `.zshenv` | Loads cargo env early |
| `.zprofile` | Homebrew shellenv |
| `.vimrc` | Vim config (uses pathogen — install separately if you want plugins) |
| `.gitconfig` | git-lfs filters + name/email placeholders (edit before using) |
| `.zshrc.local.example` | Template for machine-local secrets |
| `install.sh` | Symlinks the above into `$HOME`, backing up existing files |

## Install

```sh
git clone <repo-url> ~/dotfiles
cd ~/dotfiles
./install.sh
```

Then edit `~/.gitconfig` to set your name/email, and put any API tokens in `~/.zshrc.local` (gitignored).

## Required tools

The git helpers in `.zshrc` assume these are installed:

- [`fzf`](https://github.com/junegunn/fzf) — fuzzy picker for `gbd`, `cb`
- [`gh`](https://cli.github.com) — GitHub CLI for PR-aware `git up`, `cb`, `gph`
- [`pyenv`](https://github.com/pyenv/pyenv) + `pyenv-virtualenv` — sourced unconditionally; remove those lines if you don't use it
- [`bun`](https://bun.sh), [`nvm`](https://github.com/nvm-sh/nvm) — sourced if installed

## The custom git workflow

- `git stack <name>` — create a branch and record its parent
- `git up` — fast-forward every branch in the stack from main down to current
- `gph` — push current branch and open a PR (base = recorded parent or main)
- `cb` — visual fzf branch picker that draws the stack tree
- `gbd` — fuzzy-pick local branches to delete
