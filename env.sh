#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  env.sh -- source this in every shell that needs Flutter.
#
#      source <(curl -fsSL .../env.sh)          # if you only have the repo:
#      source /path/to/flutter-bootstrap/env.sh
#
#  What it sets:
#      PATH       -> the Flutter SDK (auto-detects where setup.sh put it)
#      PUB_CACHE  -> /var/tmp/pub-cache, i.e. OUTSIDE the workspace, so the
#                    agent snapshot stays small and pub re-downloads are
#                    instant within a session
#
#  Also defines tiny helpers (use them or ignore them):
#      fb_check  [project_dir]   pub get + analyze + test, summarised
#      fb_doctor                 flutter doctor -v
#      fb_web    [project_dir]   build web into build/web
# ---------------------------------------------------------------------------

# --- locate the SDK -------------------------------------------------------
# Order matters: an explicit $FLUTTER_ROOT wins, then the roots setup.sh
# prefers. Nothing under $HOME on purpose -- a 2.5 GB SDK in the agent
# workspace would be captured by the next snapshot.
for _cand in "${FLUTTER_ROOT:-}" /var/tmp/flutter /usr/local/flutter \
             /opt/flutter /tmp/flutter; do
  [ -n "$_cand" ] && [ -x "$_cand/bin/flutter" ] && { export FLUTTER_ROOT="$_cand"; break; }
done
if [ -z "${FLUTTER_ROOT:-}" ] || [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  echo "env.sh: no Flutter SDK found. Run setup.sh first:" >&2
  echo "        bash <(curl -fsSL https://raw.githubusercontent.com/Keshab1997/flutter-bootstrap/main/setup.sh)" >&2
  return 1 2>/dev/null || exit 1
fi

export PATH="$FLUTTER_ROOT/bin:$PATH"
export PUB_CACHE="${PUB_CACHE:-/var/tmp/pub-cache}"
mkdir -p "$PUB_CACHE" 2>/dev/null || true

# --- helpers --------------------------------------------------------------
fb_check() {
  local dir="${1:-.}"
  local sdk_req
  sdk_req=$(sed -n 's/^ *sdk: *//p' "$dir/pubspec.yaml" 2>/dev/null | head -1)
  [ -n "$sdk_req" ] && echo "pubspec sdk constraint : $sdk_req   (installed: $(dart --version 2>&1 | sed 's/.*Dart //;s/ .*//'))"
  ( cd "$dir" || return 1
    echo "== pub get =="; flutter pub get      2>&1 | tail -3
    echo "== analyze =="; flutter analyze      2>&1 | tail -5
    echo "== test    =="; flutter test        2>&1 | tail -5
  )
}

fb_doctor() { flutter doctor -v; }

fb_web() {
  local dir="${1:-.}"; shift 2>/dev/null || true
  ( cd "$dir" && flutter build web "$@" )
}

# --- quick status line ----------------------------------------------------
flutter --version 2>/dev/null | head -1 | sed 's/^/flutter-bootstrap: /'
