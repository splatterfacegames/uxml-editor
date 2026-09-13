#!/usr/bin/env bash
set -euo pipefail

# The pinned @jethac/tools-frontend-stack dependency comes from the private
# splatterfacegames/jethaforge repository. Scope the credential to that
# repository only — never to all GitHub downloads — and never commit it.
# Same pattern as the rest of the fleet (see housecat).
#
# Prefer the read token when both are set: a stale deploy key must not
# short-circuit a valid token path.
if [[ -n "${UXML_EDITOR_SHARED_STACK_READ_TOKEN:-}" ]]; then
  # Drop checkout's broad repo-scoped GITHUB_TOKEN extraheader so the
  # jethaforge-scoped credential below is the only Authorization sent.
  git config --local --unset-all http.https://github.com/.extraheader || true
  authorization=$(printf 'x-access-token:%s' "$UXML_EDITOR_SHARED_STACK_READ_TOKEN" | base64 | tr -d '\r\n')
  echo "::add-mask::$authorization"
  for repository in https://github.com/splatterfacegames/jethaforge https://github.com/splatterfacegames/jethaforge.git; do
    git config --global "http.$repository.extraheader" "AUTHORIZATION: basic $authorization"
  done
  # Cover both dep spellings: the pinned spec is git+https, but rewrite any
  # ssh-style reference onto the authenticated HTTPS channel too.
  git config --global url.https://github.com/splatterfacegames/jethaforge.git.insteadOf \
    ssh://git@github.com/splatterfacegames/jethaforge.git
  git config --global --add url.https://github.com/splatterfacegames/jethaforge.git.insteadOf \
    git@github.com:splatterfacegames/jethaforge.git
  exit 0
fi

if [[ -n "${UXML_EDITOR_SHARED_STACK_DEPLOY_KEY:-}" ]]; then
  key_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/uxml-editor-shared-stack"
  if command -v cygpath >/dev/null 2>&1; then key_dir=$(cygpath -u "$key_dir"); fi
  mkdir -p "$key_dir"
  printf '%s\n' "$UXML_EDITOR_SHARED_STACK_DEPLOY_KEY" > "$key_dir/id_ed25519"
  chmod 600 "$key_dir/id_ed25519"
  # GitHub's published Ed25519 key, verified through https://api.github.com/meta.
  printf '%s\n' 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' > "$key_dir/known_hosts"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf "GIT_SSH_COMMAND=ssh -i '%s/id_ed25519' -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile='%s/known_hosts'\n" "$key_dir" "$key_dir" >> "$GITHUB_ENV"
  else
    export GIT_SSH_COMMAND="ssh -i '$key_dir/id_ed25519' -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile='$key_dir/known_hosts'"
  fi
  git config --global url.ssh://git@github.com/splatterfacegames/jethaforge.insteadOf \
    https://github.com/splatterfacegames/jethaforge
  git config --global --add url.ssh://git@github.com/splatterfacegames/jethaforge.insteadOf \
    https://github.com/splatterfacegames/jethaforge.git
  exit 0
fi

echo '::error::Set UXML_EDITOR_SHARED_STACK_DEPLOY_KEY to a read-only shared-stack deploy key, or UXML_EDITOR_SHARED_STACK_READ_TOKEN to a credential with Contents: read access to splatterfacegames/jethaforge.'
exit 1
