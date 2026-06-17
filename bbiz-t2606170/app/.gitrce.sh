#!/bin/bash
# shellcheck disable=SC1090,SC1091
# author https://github.com/lwmacct

set -o pipefail

__log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

__die() {
  __log "ERROR: $*"
  exit 1
}

__init_ssh() {
  _ssh_dir=/app/data/.ssh

  mkdir -p "$_ssh_dir"
  chmod 700 "$_ssh_dir"
  rm -rf /root/.ssh
  ln -s "$_ssh_dir" /root/.ssh

  touch "$_ssh_dir/config"
  chmod 600 "$_ssh_dir/config"
  grep -q '^StrictHostKeyChecking no$' "$_ssh_dir/config" || echo "StrictHostKeyChecking no" >>"$_ssh_dir/config"

  if [[ -f "$_ssh_dir/id_ed25519" && "${SSH_OVERWRITE:-0}" != "1" ]]; then return; fi
  if [[ -n "${SSH_SECRET_KEY:-}" ]]; then
    echo "$SSH_SECRET_KEY" | base64 -d >"$_ssh_dir/id_ed25519"
    chmod 600 "$_ssh_dir/id_ed25519"
    ssh-keygen -y -f "$_ssh_dir/id_ed25519" >"$_ssh_dir/id_ed25519.pub"
    chmod 644 "$_ssh_dir/id_ed25519.pub"
  elif [[ ! -f "$_ssh_dir/id_ed25519" ]]; then
    ssh-keygen -t ed25519 -N '' -f "$_ssh_dir/id_ed25519" -C 'lwmacct'
  fi
}

__clone_repo() {
  rm -rf /app/data/.gitrce
  mkdir -p /app/data
  git clone --depth=1 "$GIT_REMOTE_REPO" /app/data/.gitrce
}

__repo_ok() {
  [[ -d /app/data/.gitrce/.git ]] || return 1
  find /app/data/.gitrce/.git -maxdepth 3 -name '*.lock' -print0 | xargs -0 -r rm -f
  git -C /app/data/.gitrce fsck --full >/dev/null 2>&1 || return 1
  [[ "$(git -C /app/data/.gitrce remote get-url origin 2>/dev/null || true)" == "$GIT_REMOTE_REPO" ]]
}

__sync_repo() {
  _remote_ref=
  _branch_name=

  __repo_ok || __clone_repo || return 1
  git -C /app/data/.gitrce fetch --prune || return 1

  _remote_ref="$(
    git -C /app/data/.gitrce symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null ||
      git -C /app/data/.gitrce for-each-ref --format='%(refname:short)' refs/remotes/origin | awk '$0 != "origin/HEAD" {print; exit}'
  )"
  [[ -n "$_remote_ref" ]] || return 1
  _branch_name="${_remote_ref#origin/}"

  git -C /app/data/.gitrce checkout -B "$_branch_name" "$_remote_ref" || return 1
  git -C /app/data/.gitrce branch --set-upstream-to="$_remote_ref" "$_branch_name" || return 1
  git -C /app/data/.gitrce reset --hard "$_remote_ref" || return 1
  git -C /app/data/.gitrce clean -fd || return 1
}

__run_script() {
  _script_name="$1"
  _script_path="/app/data/.gitrce/boot/$_script_name.sh"

  [[ -f "$_script_path" ]] || __die "missing $_script_path"
  __log "running boot/$_script_name.sh"
  timeout "$INTERVAL_MIN" bash "$_script_path" >/dev/null 2>&1 &
  _script_pid=$!
}

__main() {
  export LANG=C.UTF-8
  INTERVAL_MIN="${INTERVAL_MIN:-500}"
  INTERVAL_MAX="${INTERVAL_MAX:-600}"
  ALLOW_NOT_LATEST="${ALLOW_NOT_LATEST:-1}"

  [[ -n "${GIT_REMOTE_REPO:-}" ]] || __die "GIT_REMOTE_REPO is empty"
  [[ "$INTERVAL_MIN" =~ ^[0-9]+$ && "$INTERVAL_MAX" =~ ^[0-9]+$ && "$INTERVAL_MIN" -le "$INTERVAL_MAX" ]] || __die "invalid interval"
  mkdir -p /app/data/logs
  ln -sfn /app/data/.gitrce /app/gitrce
  __init_ssh

  __sync_repo || [[ "$ALLOW_NOT_LATEST" == "1" && -f /app/data/.gitrce/boot/start.sh ]] || __die "sync failed"
  __run_script start

  while true; do
    if [[ -f /app/data/.gitrce/boot/env.sh ]]; then
      set -a
      source /app/data/.gitrce/boot/env.sh
      set +a
    fi
    _before_commit="$(git -C /app/data/.gitrce rev-parse HEAD 2>/dev/null || true)"
    if __sync_repo; then
      _after_commit="$(git -C /app/data/.gitrce rev-parse HEAD 2>/dev/null || true)"
      if [[ -n "$_before_commit" && "$_before_commit" != "$_after_commit" && -f /app/data/.gitrce/boot/update.sh ]]; then
        __run_script update
      fi
    elif [[ "$ALLOW_NOT_LATEST" != "1" ]]; then
      __die "sync failed"
    fi
    sleep "$(shuf -i "$INTERVAL_MIN-$INTERVAL_MAX" -n 1)"
  done
}

__main
