#!/usr/bin/env bash
# Install or run the latest signed xctestreport release.
#
#   curl -fsSL https://github.com/lapfelix/xctestreport/releases/latest/download/install.sh | bash
#   curl -fsSL https://github.com/lapfelix/xctestreport/releases/latest/download/install.sh | bash -s -- --run App.xcresult report
#
# Options:
#   --run <args...>     Run the release from a per-version cache instead of installing it.
#   --prefix <dir>      Install into <dir>/bin (default: ~/.local).
#   --version <tag>     Use a specific release tag such as v1.0.42 (default: latest).
#
# Every download is checked against SHA256SUMS, whose SSH signature must match the key
# pinned below. When the GitHub CLI is signed in, the archive's build provenance is also
# verified with `gh attestation verify`.
set -euo pipefail

main() {
  local repo="lapfelix/xctestreport"
  local base_url="${XCTESTREPORT_RELEASE_BASE_URL:-https://github.com/$repo/releases}"
  local archive="xctestreport-macos-universal.tar.gz"
  local allowed_signers='xctestreport-release namespaces="xctestreport-release" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFYDfH8iTJncqXEVKGzsJ8IwpzIJEamolv5tmtR7vtN/'
  local prefix="${XCTESTREPORT_PREFIX:-$HOME/.local}"
  local tag="${XCTESTREPORT_VERSION:-}"
  local cache_root="${XCTESTREPORT_CACHE_DIR:-$HOME/Library/Caches/xctestreport}"
  local run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run) run=1; shift; break ;;
      --prefix) prefix="${2:?--prefix needs a directory}"; shift 2 ;;
      --version) tag="${2:?--version needs a tag}"; shift 2 ;;
      -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//'; return 0 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done

  [[ "$(uname -s)" == Darwin ]] || fail "xctestreport releases are built for macOS."

  if [[ -z "$tag" ]]; then
    tag="$(latest_tag "$base_url")" || true
    if [[ -z "$tag" ]]; then
      # Offline: fall back to the newest release already cached.
      if [[ $run -eq 1 ]] && tag="$(newest_cached "$cache_root")" && [[ -n "$tag" ]]; then
        note "Could not reach GitHub; using cached $tag."
      else
        fail "Could not determine the latest release from $base_url."
      fi
    fi
  fi
  [[ "$tag" =~ ^v[0-9A-Za-z.+-]+$ ]] || fail "Unexpected release tag: $tag"

  local package_dir="$cache_root/$tag/xctestreport"
  if [[ ! -x "$package_dir/xctestreport" ]]; then
    download_verified "$base_url/download/$tag" "$archive" "$allowed_signers" "$repo" "$cache_root/$tag"
  fi

  if [[ $run -eq 1 ]]; then
    exec "$package_dir/xctestreport" "$@"
  fi

  mkdir -p "$prefix/bin"
  local bundle
  for bundle in "$package_dir"/*.bundle; do
    rm -rf "${prefix:?}/bin/$(basename "$bundle")"
    cp -R "$bundle" "$prefix/bin/"
  done
  install -m 755 "$package_dir/xctestreport" "$prefix/bin/xctestreport"
  note "Installed xctestreport $tag in $prefix/bin."
  case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) note "Add $prefix/bin to PATH, for example: echo 'export PATH=\"$prefix/bin:\$PATH\"' >> ~/.zshrc" ;;
  esac
}

latest_tag() {
  local url
  url="$(curl -fsLI -o /dev/null -w '%{url_effective}' "$1/latest")" || return 1
  [[ "$url" == */tag/* ]] || return 1
  printf '%s\n' "${url##*/tag/}"
}

newest_cached() {
  [[ -d "$1" ]] || return 1
  find "$1" -mindepth 1 -maxdepth 1 -type d -name 'v*' -exec test -x '{}/xctestreport/xctestreport' ';' -print \
    | sed 's|.*/||' | sort -V | tail -n 1
}

download_verified() {
  local url="$1" archive="$2" allowed_signers="$3" repo="$4" destination="$5"
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/xctestreport-download.XXXXXX")"
  DOWNLOAD_DIR="$work"
  trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

  note "Downloading xctestreport ${url##*/}..."
  local file
  for file in "$archive" SHA256SUMS SHA256SUMS.sig; do
    curl -fsSL --retry 3 -o "$work/$file" "$url/$file" || fail "Could not download $url/$file"
  done

  printf '%s\n' "$allowed_signers" > "$work/allowed_signers"
  /usr/bin/ssh-keygen -Y verify -f "$work/allowed_signers" -I xctestreport-release -n xctestreport-release \
    -s "$work/SHA256SUMS.sig" < "$work/SHA256SUMS" > /dev/null 2>&1 \
    || fail "SHA256SUMS does not carry a valid xctestreport release signature."

  local expected actual
  expected="$(awk -v name="$archive" '$2 == name || $2 == "*" name { print $1 }' "$work/SHA256SUMS")"
  actual="$(/usr/bin/shasum -a 256 "$work/$archive" | awk '{ print $1 }')"
  [[ -n "$expected" && "$expected" == "$actual" ]] || fail "Checksum mismatch for $archive."

  if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
    gh attestation verify "$work/$archive" --repo "$repo" > /dev/null \
      || fail "GitHub build provenance verification failed for $archive."
    note "Verified signature, checksum and GitHub build provenance."
  else
    note "Verified signature and checksum."
  fi

  mkdir -p "$work/extract"
  tar -xzf "$work/$archive" -C "$work/extract"
  [[ -x "$work/extract/xctestreport/xctestreport" ]] || fail "The archive has no xctestreport executable."
  rm -rf "$destination"
  mkdir -p "$(dirname "$destination")"
  mv "$work/extract" "$destination"
  rm -rf "$work"
}

note() { printf 'xctestreport: %s\n' "$*" >&2; }
fail() { note "$*"; exit 1; }

# Run only after bash has read the whole script, so `curl | bash` never executes a partial download.
main "$@"
