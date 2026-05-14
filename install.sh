#!/usr/bin/env bash
# Symlink the tracked dotfiles into $HOME.
# Existing files are backed up to <name>.backup.<timestamp>.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

FILES=(.zshrc .zshenv .zprofile .vimrc .gitconfig)

for f in "${FILES[@]}"; do
  src="$DIR/$f"
  dest="$HOME/$f"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "backing up $dest -> $dest.backup.$STAMP"
    mv "$dest" "$dest.backup.$STAMP"
  elif [ -L "$dest" ]; then
    rm "$dest"
  fi
  ln -s "$src" "$dest"
  echo "linked $f"
done

if [ ! -f "$HOME/.zshrc.local" ]; then
  cp "$DIR/.zshrc.local.example" "$HOME/.zshrc.local"
  echo "created ~/.zshrc.local from example — fill in your secrets there"
fi

echo "done. open a new shell or run: source ~/.zshrc"
