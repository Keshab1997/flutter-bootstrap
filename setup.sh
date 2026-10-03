#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  flutter-bootstrap : install Flutter into a fresh AI-agent sandbox in ~60s.
#
#  WHY THIS EXISTS
#    A new sandbox has no Flutter SDK, and anything installed outside the
#    workspace is gone next session. Rather than teach every agent the same
#    seven-step install, they clone this repo and run this script.
#
#  WHAT IT DOES NOT DO
#    No credentials. No tokens. No secrets. Nothing is downloaded from anywhere
#    except Google's official Flutter release storage, and the archive is
#    sha256-verified against the official release manifest before extraction.
#
#  USAGE
#    bash setup.sh                       # latest stable, auto-picked root
#    bash setup.sh --version 3.47.6      # pin a version
#    bash setup.sh --root /var/tmp/flutter
#    bash setup.sh --precache web,linux  # also warm engine artifacts
#    bash setup.sh --deep-verify         # extra: create+analyze+test a probe app
#    bash setup.sh --quiet --json        # agent-friendly output
#    bash setup.sh --no-swap             # don't add swap on low-RAM boxes
#
#  Idempotent: if a working Flutter is already present it exits in <1s.
# ---------------------------------------------------------------------------
set -euo pipefail

VERSION="${FLUTTER_VERSION:-latest}"
EXPLICIT_ROOT="${FLUTTER_ROOT:-}"
PRECACHE=""
DEEP_VERIFY=0
QUIET=0
JSON=0
SWAP=1
RELEASES_URL="https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"
BASE_URL="https://storage.googleapis.com/flutter_infra_release/releases"
# Used only if the release manifest cannot be fetched.
FALLBACK_VERSION="3.47.6"
FALLBACK_SHA="f1631b9c2c8b3529323db412b0d1beacf4a748f8783b0d7cf599a8fd5f461675"
# Roots are tried in order. All of them live OUTSIDE the agent workspace
# (/home/user) on purpose: the SDK is 2.5 GB and must never enter a snapshot.
ROOT_CANDIDATES="${FB_ROOT_CANDIDATES:-/var/tmp/flutter /usr/local/flutter /opt/flutter /tmp/flutter}"
START=$(date +%s)

while [ $# -gt 0 ]; do
  case "$1" in
    --version)     VERSION="$2"; shift 2 ;;
    --root)        EXPLICIT_ROOT="$2"; shift 2 ;;
    --precache)    PRECACHE="$2"; shift 2 ;;
    --deep-verify) DEEP_VERIFY=1; shift ;;
    --no-swap)     SWAP=0; shift ;;
    --quiet|-q)    QUIET=1; shift ;;
    --json)        JSON=1; QUIET=1; shift ;;
    -h|--help)     sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done

say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
step() { [ "$QUIET" = 1 ] || printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*" >&2; }
die()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

valid_root() { [ -n "${1:-}" ] && [ -x "$1/bin/flutter" ] && "$1/bin/flutter" --version >/dev/null 2>&1; }

# Create a throwaway project and analyze + test it. Used by --deep-verify on
# both the fresh-install path and the already-installed fast path.
deep_verify() {
  step "deep verify: create a project, then analyze + test it"
  local probe="${TMPDIR:-/var/tmp}/fb-probe.$$"
  rm -rf "$probe"
  "$FLUTTER_ROOT/bin/flutter" create --template=app --project-name fb_probe "$probe" >/dev/null 2>&1 \
    || die "flutter create failed"
  ( cd "$probe" && "$FLUTTER_ROOT/bin/flutter" analyze 2>&1 | tail -2 | sed 's/^/  /' )
  ( cd "$probe" && "$FLUTTER_ROOT/bin/flutter" test    2>&1 | tail -2 | sed 's/^/  /' )
  rm -rf "$probe"
  echo "ok"
}

# Probe a candidate install root for real usability. Some sandboxes mount
# directories that look writable but reject rename() with EBUSY (and /opt can
# be effectively read-only even with sudo), so we test instead of assuming.
probe_root() {
  local root="$1" parent p
  parent="$(dirname "$root")"
  [ -d "$parent" ] || return 1
  if [ ! -w "$parent" ] || { [ -e "$root" ] && [ ! -w "$root" ]; }; then
    have sudo || return 1
    sudo -n true 2>/dev/null || return 1
    sudo mkdir -p "$root" 2>/dev/null || return 1
    sudo chown "$(id -u):$(id -g)" "$root" 2>/dev/null || return 1
  fi
  mkdir -p "$root" 2>/dev/null || return 1
  [ -w "$root" ] || return 1
  p="$root/.fb-probe.$$"
  mkdir -p "$p/a" 2>/dev/null || { rm -rf "$p"; return 1; }
  touch "$p/a/f" 2>/dev/null || { rm -rf "$p"; return 1; }
  mv "$p/a" "$p/b" 2>/dev/null || { rm -rf "$p"; return 1; }   # rename must work
  rm -rf "$p"
  return 0
}

# A symlink in /usr/local/bin means plain `flutter`/`dart` work in EVERY new
# shell -- including each separate agent bash call -- with no PATH fiddling.
# Also repairs a stale symlink left over from an SDK at a different root.
link_bins() {
  local bin_dir b ok
  for bin_dir in /usr/local/bin "$HOME/.local/bin"; do
    [ -d "$bin_dir" ] || continue
    if [ -w "$bin_dir" ] || { have sudo && sudo -n true 2>/dev/null && sudo test -w "$bin_dir" 2>/dev/null; }; then
      ok=1
      for b in flutter dart; do
        [ "$(readlink -f "$bin_dir/$b" 2>/dev/null)" = "$FLUTTER_ROOT/bin/$b" ] && continue
        if [ -w "$bin_dir" ]; then ln -sf "$FLUTTER_ROOT/bin/$b" "$bin_dir/$b" || ok=0
        else sudo ln -sf "$FLUTTER_ROOT/bin/$b" "$bin_dir/$b" || ok=0; fi
      done
      [ "$ok" = 1 ] && { say "  linked: $bin_dir/flutter -> $FLUTTER_ROOT/bin/flutter"; return 0; }
    fi
  done
  return 1
}

# --------------------------------------------------------------------------
# 0. fast path -- already installed anywhere we know about?
# --------------------------------------------------------------------------
watch_list="$ROOT_CANDIDATES"
[ -n "$EXPLICIT_ROOT" ] && watch_list="$EXPLICIT_ROOT"
for cand in $watch_list; do
  if valid_root "$cand"; then
    FLUTTER_ROOT="$cand"
    VER=$("$cand/bin/flutter" --version 2>/dev/null | head -1)
    say "already installed: $VER"
    say "  root : $FLUTTER_ROOT"
    export FLUTTER_ROOT
    if [ "$(readlink -f /usr/local/bin/flutter 2>/dev/null)" != "$FLUTTER_ROOT/bin/flutter" ]; then
      say "  repairing stale symlink in /usr/local/bin"
      link_bins >/dev/null 2>&1 || warn "could not repair the /usr/local/bin symlink"
    fi
    [ "$DEEP_VERIFY" = 1 ] && deep_verify >/dev/null
    [ "$JSON" = 1 ] && printf '{"status":"already-installed","path":"%s","version":"%s","seconds":%s}\n' \
      "$FLUTTER_ROOT" "$(printf '%s' "$VER" | sed 's/Flutter //;s/ .*//')" "$(( $(date +%s) - START ))"
    exit 0
  fi
done

step "flutter-bootstrap"

# --------------------------------------------------------------------------
# 1. prerequisites
# --------------------------------------------------------------------------
have curl || die "curl not found"
have tar  || die "tar not found"
have xz   || warn "xz not found -- extraction will be slower"

MEM_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
CPUS=$(nproc 2>/dev/null || echo 1)
say "  cpu: ${CPUS} core(s)   ram: ${MEM_MB} MB"

if [ "$MEM_MB" -lt 2800 ] && [ "$SWAP" = 1 ] \
   && [ "$(awk '/SwapTotal/{print $2}' /proc/meminfo)" = "0" ]; then
  step "adding 2 GB swap (tight RAM; prevents OOM during pub get / test)"
  if sudo -n true 2>/dev/null; then
    if sudo fallocate -l 2G /swapfile 2>/dev/null && sudo chmod 600 /swapfile \
       && sudo mkswap /swapfile >/dev/null 2>&1 && sudo swapon /swapfile 2>/dev/null; then
      say "  swap: 2 GB on (/swapfile)"
    else
      warn "swap setup failed (not fatal)"
    fi
  else
    warn "no passwordless sudo -- skipping swap"
  fi
fi

# --------------------------------------------------------------------------
# 2. choose an install root
# --------------------------------------------------------------------------
if [ -n "$EXPLICIT_ROOT" ]; then
  root_candidates="$EXPLICIT_ROOT"
else
  root_candidates="$ROOT_CANDIDATES"
fi

FLUTTER_ROOT=""
for cand in $root_candidates; do
  if probe_root "$cand"; then FLUTTER_ROOT="$cand"; break; fi
  warn "root not usable: $cand (not writable / rename blocked)"
done
[ -n "$FLUTTER_ROOT" ] || die "no usable install root.
  Tried : $root_candidates
  Why   : the path (or its parent) is not writable, or the filesystem there
          rejects rename() -- some sandboxes make /opt effectively read-only.
  Fix   : let the script auto-pick a good root:   bash setup.sh
          or name a writable one yourself:        bash setup.sh --root /var/tmp/flutter
  Avoid \$HOME: this SDK is 2.5 GB and would bloat the agent workspace."
say "  root: $FLUTTER_ROOT"

DL_DIR="${TMPDIR:-/var/tmp}/fb-dl"
mkdir -p "$DL_DIR" || die "cannot create download cache: $DL_DIR"

# --------------------------------------------------------------------------
# 3. resolve version + expected sha256 from the official manifest
# --------------------------------------------------------------------------
RESOLVED=""
if MANIFEST=$(curl -fsSL --max-time 40 "$RELEASES_URL" 2>/dev/null); then
  RESOLVED=$(printf '%s' "$MANIFEST" | VERSION="$VERSION" python3 -c '
import json, os, sys
want = os.environ["VERSION"]
d = json.load(sys.stdin)
rel = [r for r in d["releases"] if "linux" in r["archive"]]
if want == "latest":
    h = d["current_release"]["stable"]
    pick = [r for r in rel if r["hash"] == h and r["channel"] == "stable"]
else:
    pick = [r for r in rel if r.get("version") == want]
if not pick:
    sys.exit(1)
r = pick[0]
print(r["version"], r["archive"], r.get("sha256", ""))
' 2>/dev/null) || RESOLVED=""
fi

if [ -n "$RESOLVED" ]; then
  set -- $RESOLVED
  RES_VERSION="$1"; ARCHIVE="$2"; SHA="${3:-}"
else
  warn "could not read the release manifest -- falling back to built-in ${FALLBACK_VERSION}"
  RES_VERSION="$FALLBACK_VERSION"; ARCHIVE="stable/linux/flutter_linux_${FALLBACK_VERSION}-stable.tar.xz"; SHA="$FALLBACK_SHA"
fi
say "  version: Flutter $RES_VERSION"

# --------------------------------------------------------------------------
# 4. download + sha256 verification
# --------------------------------------------------------------------------
TARBALL="$DL_DIR/flutter-${RES_VERSION}.tar.xz"
if [ -f "$TARBALL" ] && [ -n "$SHA" ] && [ "$(sha256sum "$TARBALL" | cut -d' ' -f1)" = "$SHA" ]; then
  say "  cached tarball verified, skipping download"
else
  step "downloading $RES_VERSION ($BASE_URL/$ARCHIVE)"
  rm -f "$TARBALL"
  curl -fL --retry 3 --retry-delay 2 --max-time 900 --progress-bar \
       -o "$TARBALL" "$BASE_URL/$ARCHIVE" || die "download failed"
  say "  $(du -h "$TARBALL" | cut -f1) downloaded"
fi

if [ -n "$SHA" ]; then
  step "verifying sha256"
  ACTUAL=$(sha256sum "$TARBALL" | cut -d' ' -f1)
  [ "$ACTUAL" = "$SHA" ] || die "sha256 mismatch -- archive is corrupt or tampered with.
  expected: $SHA
  actual  : $ACTUAL
  Delete $TARBALL and re-run."
  say "  ok  ${SHA:0:16}..."
else
  warn "manifest gave no sha256 -- integrity unverified"
fi

# --------------------------------------------------------------------------
# 5. extract straight into the root (no cross-directory move: some sandboxes
#    reject rename() with EBUSY, and staging elsewhere costs 2.5 GB of copying)
# --------------------------------------------------------------------------
step "extracting to $FLUTTER_ROOT (about 30-40 s)"
find "$FLUTTER_ROOT" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
if ! tar -xf "$TARBALL" -C "$FLUTTER_ROOT" --strip-components=1; then
  rm -rf "$FLUTTER_ROOT"
  die "extraction failed; $FLUTTER_ROOT cleaned up"
fi
[ -x "$FLUTTER_ROOT/bin/flutter" ] || die "unexpected archive layout (no bin/flutter)"
say "  installed $(du -sh "$FLUTTER_ROOT" | cut -f1)"

# --------------------------------------------------------------------------
# 6. environment for this shell and for every future one
# --------------------------------------------------------------------------
export FLUTTER_ROOT
export PATH="$FLUTTER_ROOT/bin:$PATH"
export PUB_CACHE="${PUB_CACHE:-/var/tmp/pub-cache}"   # caches stay out of $HOME
mkdir -p "$PUB_CACHE" 2>/dev/null || true

step "configuring"
git config --global --add safe.directory "$FLUTTER_ROOT" 2>/dev/null || true
flutter --disable-analytics >/dev/null 2>&1 || true
flutter config --no-analytics >/dev/null 2>&1 || true
flutter config --enable-web   >/dev/null 2>&1 || true

LINKED=0
link_bins && LINKED=1 || warn "could not link into /usr/local/bin -- use: export PATH=$FLUTTER_ROOT/bin:\$PATH"

# --------------------------------------------------------------------------
# 7. verify
# --------------------------------------------------------------------------
step "verify"
VER_OUT=$("$FLUTTER_ROOT/bin/flutter" --version 2>&1) || die "flutter --version failed:
$VER_OUT"
printf '%s\n' "$VER_OUT" | sed 's/^/  /'
say "  $("$FLUTTER_ROOT/bin/dart" --version 2>&1)"

PROBE_STATUS="skipped"
if [ -n "$PRECACHE" ]; then
  step "precache: $PRECACHE"
  # shellcheck disable=SC2086
  "$FLUTTER_ROOT/bin/flutter" precache $(printf '%s' "$PRECACHE" | tr ',' ' ' | sed 's/[^ ]*/--&/g') 2>&1 | tail -3 | sed 's/^/  /' || warn "precache failed (not fatal)"
fi

if [ "$DEEP_VERIFY" = 1 ]; then
  PROBE_STATUS=$(deep_verify) || die "deep verify failed"
  [ "$PROBE_STATUS" = "ok" ] || PROBE_STATUS="failed"
fi

ELAPSED=$(( $(date +%s) - START ))
step "done in ${ELAPSED}s"
say ""
say "  version : $RES_VERSION"
say "  root    : $FLUTTER_ROOT"
if [ "$LINKED" = 1 ]; then
  say "  usage   : flutter <cmd>            (already on PATH via /usr/local/bin)"
else
  say "  usage   : export PATH=$FLUTTER_ROOT/bin:\$PATH"
fi
say "  helper  : source env.sh            (sets PATH + PUB_CACHE + fb_* helpers)"
say "  next    : cd <project> && flutter pub get && flutter analyze && flutter test"
say ""

if [ "$JSON" = 1 ]; then
  printf '{"status":"installed","version":"%s","path":"%s","seconds":%s,"pub_cache":"%s","linked":%s,"deep_verify":"%s"}\n' \
    "$RES_VERSION" "$FLUTTER_ROOT" "$ELAPSED" "$PUB_CACHE" "$LINKED" "$PROBE_STATUS"
fi
