# ─── PATH / toolchains ────────────────────────────────────────────────
export PATH="/opt/homebrew/opt/node@20/bin:$PATH"
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/usr/local/opt/node@20/bin:$PATH"

# Android SDK
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home

# Bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# pyenv
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# Composer (PHP)
export PATH="$PATH:$HOME/.composer/vendor/bin"

# fzf
source <(fzf --zsh)

# uv (cargo-installed binaries)
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# ─── Secrets (loaded from ~/.zshrc.local — see README) ────────────────
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

# ─── Prompt ───────────────────────────────────────────────────────────
function parse_git_branch() {
    git branch 2> /dev/null | sed -n -e 's/^\* \(.*\)/[\1]/p'
}

COLOR_DEF='%f'           # Reset color
COLOR_USR='%F{243}'      # Gray
COLOR_DIR='%F{197}'      # Pink/Red
COLOR_GIT='%F{39}'       # Blue

setopt PROMPT_SUBST
export PROMPT='${COLOR_USR}%n ${COLOR_DIR}%~ ${COLOR_GIT}$(parse_git_branch)${COLOR_DEF} $ '

# Shift+Arrow → jump to start/end of line
bindkey "^[[1;2D" beginning-of-line
bindkey "^[[1;2C" end-of-line

# ─── Git helpers ──────────────────────────────────────────────────────
# `git up`: walk the PR stack from main down to current branch, fast-forward
# each one. Needs `gh`. Records parents via `branch.<name>.parent` config (set
# by `git stack`) when there's no open PR yet.
_git_up() {
  if ! command git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "git up: uncommitted changes, commit or stash first" && return 1
  fi
  local current
  current=$(command git symbolic-ref --short HEAD) || return 1
  if [ "$current" = "main" ]; then
    command git pull --ff-only origin main
    return
  fi

  local -a chain
  chain=("$current")
  local cursor="$current" base depth=0
  while [ "$cursor" != "main" ]; do
    if (( depth++ > 20 )); then
      echo "git up: chain too deep (cycle?), aborting" && return 1
    fi
    base=$(gh pr list --head "$cursor" --state open --json baseRefName --jq '.[0].baseRefName' 2>/dev/null)
    if [ -z "$base" ]; then
      base=$(command git config "branch.$cursor.parent" 2>/dev/null)
    fi
    if [ -z "$base" ]; then
      if [ "$cursor" = "$current" ]; then
        base="main"
      else
        echo "git up: no parent for $cursor (no open PR, no branch.$cursor.parent)" && return 1
      fi
    fi
    chain=("$base" "${chain[@]}")
    cursor="$base"
  done

  echo "git up: ${(j: -> :)chain}"
  command git fetch origin || return 1
  command git checkout "${chain[1]}" && command git merge --ff-only "origin/${chain[1]}" || return 1
  local i parent child
  for ((i = 1; i < ${#chain[@]}; i++)); do
    parent="${chain[$i]}"
    child="${chain[$((i + 1))]}"
    command git checkout "$child" || return 1
    if command git rev-parse --verify --quiet "refs/remotes/origin/$child" >/dev/null; then
      command git merge --ff-only "origin/$child" || {
        echo "git up: $child has diverged from origin/$child — resolve manually"
        return 1
      }
    fi
    command git merge --no-edit "$parent" || {
      echo "git up: merge conflicts in $child (merging $parent) — resolve, push, then re-run git up"
      return 1
    }
    command git push origin head || return 1
  done
}

# `git stack <name>`: create a new branch that records its parent, so `git up`
# and `cb` can reconstruct the stack later.
_git_stack() {
  if [ -z "$1" ]; then
    echo "git stack: usage: git stack <branch-name>" >&2
    return 1
  fi
  local parent new
  parent=$(command git symbolic-ref --short HEAD) || return 1
  new="$1"
  command git checkout -b "$new" || return 1
  command git config "branch.$new.parent" "$parent"
  echo "git stack: created $new off $parent (parent recorded in branch.$new.parent)"
}

git() {
  case "$1" in
    up)    shift; _git_up "$@" ;;
    stack) shift; _git_stack "$@" ;;
    *)     command git "$@" ;;
  esac
}

# `gbd`: fuzzy-pick recent local branches and delete them
gbd() {
  local branches branch
  branches=$(git for-each-ref --count=30 --sort=-committerdate refs/heads/ --format="%(refname:short)") &&
  branch=$(echo "$branches" | fzf --multi ) &&
  git branch -D $(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")
}

# `cb`: visual branch picker that renders the PR/parent tree from main
_cb_render_tree() {
  local node=$1 prefix=$2 connector=$3 child_prefix=$4 current=$5
  local marker
  [ "$node" = "$current" ] && marker="*" || marker=" "
  echo "$marker ${prefix}${connector}${node}"
  local -a kids
  kids=(${=__cb_children[$node]})
  local n=${#kids[@]} i kid kc kcp
  for ((i = 1; i <= n; i++)); do
    kid=$kids[$i]
    if (( i == n )); then
      kc="└── "; kcp="    "
    else
      kc="├── "; kcp="│   "
    fi
    _cb_render_tree "$kid" "${prefix}${child_prefix}" "$kc" "$kcp" "$current"
  done
}

# If BRANCH is checked out in another worktree, print that worktree path.
_cb_worktree_for_branch() {
  local branch=$1 path=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) path=${line#worktree } ;;
      branch\ refs/heads/*)
        if [ "${line#branch refs/heads/}" = "$branch" ]; then
          print -r -- "$path"
          return 0
        fi
        ;;
      "") path="" ;;
    esac
  done < <(command git worktree list --porcelain 2>/dev/null)
  return 1
}

# Checkout BRANCH here. If another worktree holds it, detach that worktree at
# the same commit (no file loss) and then take the branch locally.
_cb_checkout() {
  local branch=$1
  local err
  if err=$(command git checkout "$branch" 2>&1); then
    return 0
  fi
  if [[ "$err" != *"already used by worktree"* ]]; then
    print -r -- "$err" >&2
    return 1
  fi

  local wt here
  wt=$(_cb_worktree_for_branch "$branch")
  if [ -z "$wt" ]; then
    wt=${err##*worktree at \'}
    wt=${wt%%\'*}
  fi
  here=$(command git rev-parse --show-toplevel 2>/dev/null)
  if [ -z "$wt" ] || [ ! -d "$wt" ] || [ "$wt" = "$here" ]; then
    print -r -- "$err" >&2
    return 1
  fi

  print -r -- "Branch '$branch' is checked out in $wt — detaching that worktree, then checking out here."
  if ! command git -C "$wt" switch --detach >/dev/null; then
    print -r -- "Failed to detach worktree at $wt" >&2
    return 1
  fi
  command git checkout "$branch"
}

unalias cb 2>/dev/null
cb() {
  local current
  current=$(command git symbolic-ref --short HEAD 2>/dev/null)

  local -a branches
  branches=(${(f)"$(command git for-each-ref --format='%(refname:short)' refs/heads/)"})

  typeset -A pr_base
  local pr_lines head base
  pr_lines=$(gh pr list --state open --limit 200 --json headRefName,baseRefName --jq '.[] | "\(.headRefName) \(.baseRefName)"' 2>/dev/null)
  while IFS=' ' read -r head base; do
    [ -n "$head" ] && pr_base[$head]=$base
  done <<< "$pr_lines"

  typeset -gA __cb_children
  __cb_children=()

  local b p
  for b in $branches; do
    [ "$b" = "main" ] && continue
    p="${pr_base[$b]}"
    [ -z "$p" ] && p=$(command git config "branch.$b.parent" 2>/dev/null)
    [ -z "$p" ] && p="main"
    if [ "$p" != "main" ] && [[ " ${branches[*]} " != *" $p "* ]]; then
      p="main"
    fi
    __cb_children[$p]+=" $b"
  done

  local tree selection branch
  tree=$(_cb_render_tree "main" "" "" "" "$current")
  selection=$(print -r -- "$tree" | fzf --ansi --reverse)
  [ -z "$selection" ] && return
  branch=$(print -r -- "$selection" | sed -E 's/^[* ] //; s/.*── //' | xargs)
  [ -n "$branch" ] && _cb_checkout "$branch"
}

# `gph`: push current branch and open a PR if one doesn't exist yet
unalias gph 2>/dev/null
gph() {
  command git push origin head || return 1
  local branch
  branch=$(command git symbolic-ref --short HEAD) || return 1
  [ "$branch" = "main" ] && return 0
  if [ -n "$(gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null)" ]; then
    return 0
  fi
  local base
  base=$(command git config "branch.$branch.parent" 2>/dev/null)
  [ -z "$base" ] && base="main"
  echo "gph: opening PR for $branch (base: $base)"
  gh pr create --base "$base"
}

# ─── Aliases ──────────────────────────────────────────────────────────
alias gco="git checkout"
alias gcob="git checkout -b"
alias gpo="git pull origin"
alias gcam='git add -A && git commit -m'
alias hotfix='git add -A && git commit -m "$1" && git push origin head'
