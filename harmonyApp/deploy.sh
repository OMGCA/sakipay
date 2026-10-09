#!/usr/bin/env bash
#
# Build, install and launch the Sakipay HAP on a connected HarmonyOS
# device/emulator — with a guard against the wedged-hdc failure mode.
#
# Why this exists
# ---------------
# `hdc` can end up in a state where `hdc shell` keeps working but every file
# transfer hangs forever. DevEco Studio reports that as
# "Push Hap Timeout.: executeRemoteCommand timed out after 600000ms" after ten
# minutes, which looks like a signing problem but is not: the HAP is signed
# correctly, the bytes simply never move. This script probes the transfer
# channel first, restarts the hdc server when it is wedged, installs with a
# timeout, and only then surfaces an error.
#
# Usage
# -----
#   ./deploy.sh                     # build, install, launch
#   ./deploy.sh 127.0.0.1:5555      # target a specific device
#   ./deploy.sh --skip-build        # install the HAP that is already built
#   ./deploy.sh --uninstall         # uninstall before installing
#   DEPLOY_REBOOT=1 ./deploy.sh     # reboot the device if recovery fails
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DEVECO_HOME="${DEVECO_STUDIO_HOME:-/Applications/DevEco-Studio.app/Contents}"
HDC="${HDC_BIN:-$DEVECO_HOME/sdk/default/openharmony/toolchains/hdc}"
HVIGORW="${HVIGORW_BIN:-$DEVECO_HOME/tools/hvigor/bin/hvigorw}"
export NODE_HOME="${NODE_HOME:-$DEVECO_HOME/tools/node}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_HOME/sdk}"
export PATH="$NODE_HOME/bin:$PATH"

BUNDLE="com.xiatstudio.sakipay"
ABILITY="MainAbility"
HAP="$SCRIPT_DIR/main/build/default/outputs/default/main-default-signed.hap"
UNSIGNED_HAP="$SCRIPT_DIR/main/build/default/outputs/default/main-default-unsigned.hap"

PROBE_TIMEOUT="${DEPLOY_PROBE_TIMEOUT:-20}"
INSTALL_TIMEOUT="${DEPLOY_INSTALL_TIMEOUT:-180}"
BUILD_TIMEOUT="${DEPLOY_BUILD_TIMEOUT:-900}"

TARGET=""
SKIP_BUILD=0
DO_UNINSTALL=0

for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=1 ;;
    --uninstall)  DO_UNINSTALL=1 ;;
    -h|--help)
      sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *)  TARGET="$arg" ;;
  esac
done

log()  { printf '\033[1;34m[deploy]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[deploy]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[deploy]\033[0m %s\n' "$*" >&2; }

# Run a command with a wall-clock limit. Returns 124 when it had to be killed.
timeout_cmd() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

require_tools() {
  [ -x "$HDC" ] || { fail "hdc not found at $HDC (set HDC_BIN)"; exit 1; }
  [ -x "$HVIGORW" ] || { fail "hvigorw not found at $HVIGORW (set HVIGORW_BIN)"; exit 1; }
}

# Connected (not "Offline") targets, one connect key per line.
# `hdc list targets -v` is tab separated and the state column has moved
# between hdc releases, so find the state by value rather than by index.
connected_targets() {
  "$HDC" list targets -v 2>/dev/null \
    | awk -F'\t' '{
        state = ""
        for (i = 2; i <= NF; i++) {
          if ($i == "Connected" || $i == "Offline" || $i == "Unauthorized") {
            state = $i
            break
          }
        }
        if (state == "Connected") print $1
      }'
}

resolve_target() {
  if [ -n "$TARGET" ]; then
    return 0
  fi
  TARGET="$(connected_targets | head -n 1)"
  if [ -z "$TARGET" ]; then
    fail "no connected device found."
    warn "Start the emulator in DevEco Studio (Device Manager) or plug in a"
    warn "device, then re-run. \`$HDC list targets -v\` shows what hdc sees."
    exit 1
  fi
}

# The whole point of this script: prove the file channel moves bytes.
probe_transfer() {
  local probe_file rc=0
  probe_file="$(mktemp "${TMPDIR:-/tmp}/hdc-probe.XXXXXX")"
  printf 'hdc-probe' > "$probe_file"
  timeout_cmd "$PROBE_TIMEOUT" \
    "$HDC" -t "$TARGET" file send "$probe_file" /data/local/tmp/.hdc_probe \
    >/dev/null 2>&1 || rc=$?
  rm -f "$probe_file"
  [ "$rc" -eq 0 ]
}

diagnose() {
  warn "hdc client/server/target versions:"
  "$HDC" -v 2>&1 | sed 's/^/      /' || true
  "$HDC" checkserver 2>&1 | sed 's/^/      /' || true
  "$HDC" list targets -v 2>&1 | sed 's/^/      /' || true
}

# Drop the wedged server, bring it back, and re-attach TCP targets (the
# emulator is always TCP: 127.0.0.1:5555).
recover_transfer() {
  local tcp_targets
  tcp_targets="$(connected_targets | grep -E '^[0-9.]+:[0-9]+$' || true)"

  log "restarting the hdc server"
  "$HDC" kill >/dev/null 2>&1 || true
  sleep 2
  "$HDC" start >/dev/null 2>&1 || true
  sleep 2

  local target
  for target in $tcp_targets; do
    log "reconnecting $target"
    "$HDC" tconn "$target" >/dev/null 2>&1 || true
  done
  if [ -z "$tcp_targets" ]; then
    "$HDC" list targets >/dev/null 2>&1 || true
  fi

  # Give the device a moment to re-enumerate before probing again.
  local waited=0
  while [ "$waited" -lt 20 ]; do
    connected_targets | grep -qx "$TARGET" && break
    sleep 2
    waited=$((waited + 2))
  done

  if probe_transfer; then
    log "file transfer recovered"
    return 0
  fi

  if [ "${DEPLOY_REBOOT:-0}" = "1" ]; then
    warn "recovery failed — rebooting $TARGET"
    "$HDC" -t "$TARGET" target boot >/dev/null 2>&1 || true
    local waited2=0
    while [ "$waited2" -lt 120 ]; do
      sleep 5
      waited2=$((waited2 + 5))
      "$HDC" tconn "$TARGET" >/dev/null 2>&1 || true
      if timeout_cmd "$PROBE_TIMEOUT" \
           "$HDC" -t "$TARGET" file send /etc/hosts /data/local/tmp/.hdc_probe \
           >/dev/null 2>&1; then
        log "file transfer recovered after reboot"
        return 0
      fi
    done
  fi

  return 1
}

ensure_transfer() {
  log "probing the file transfer channel ($TARGET)"
  if probe_transfer; then
    return 0
  fi

  warn "hdc file transfer is wedged — shell still works, pushes hang forever."
  warn "This is what DevEco Studio reports as \"Push Hap Timeout\"."
  recover_transfer && return 0

  diagnose
  fail "could not restore hdc file transfer."
  warn "The HAP is *not* the problem — rebuild/re-signing will not help."
  warn "Cold-boot the emulator (DevEco Device Manager, or restart the AVD),"
  warn "then re-run. Or retry with DEPLOY_REBOOT=1 to reboot it from here."
  exit 1
}

build_hap() {
  if [ "$SKIP_BUILD" = "1" ]; then
    log "skipping build (--skip-build)"
    return 0
  fi
  log "building the HAP (assembleHap)"
  if ! timeout_cmd "$BUILD_TIMEOUT" "$HVIGORW" assembleHap --no-daemon; then
    fail "build failed or exceeded ${BUILD_TIMEOUT}s"
    exit 1
  fi
}

verify_signature() {
  local sign_tool="$DEVECO_HOME/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"
  [ -f "$HAP" ] || { fail "signed HAP missing: $HAP"; exit 1; }
  [ -f "$sign_tool" ] || return 0
  log "verifying the HAP signature"
  # hap-sign-tool refuses to write to a path that already exists and still
  # exits 0 on failure, so use fresh paths and match its output instead of $?.
  local out_dir out
  out_dir="$(mktemp -d "${TMPDIR:-/tmp}/sakipay-sign.XXXXXX")"
  out="$(java -jar "$sign_tool" verify-app -inFile "$HAP" \
           -outCertChain "$out_dir/cert.cer" -outProfile "$out_dir/profile.p7b" 2>&1 || true)"
  rm -rf "$out_dir"
  case "$out" in
    *"verify-app success"*) log "signature OK" ;;
    *)
      warn "signature verification failed — check the signingConfig in build-profile.json5"
      printf '%s\n' "$out" | grep -i -E "error|fail" | head -5 | sed 's/^/      /' || true
      ;;
  esac
}

install_hap() {
  if [ "$DO_UNINSTALL" = "1" ]; then
    log "uninstalling $BUNDLE"
    "$HDC" -t "$TARGET" uninstall "$BUNDLE" >/dev/null 2>&1 || true
  fi

  log "installing $(basename "$HAP")"
  local rc=0
  timeout_cmd "$INSTALL_TIMEOUT" \
    "$HDC" -t "$TARGET" install -r "$HAP" || rc=$?

  if [ "$rc" -eq 124 ]; then
    fail "install timed out after ${INSTALL_TIMEOUT}s (the push never finished)."
    warn "That is the wedged-hdc symptom, not a signing failure. Re-run this"
    warn "script — it will restart the hdc server — or cold-boot the emulator."
    exit 1
  fi
  if [ "$rc" -ne 0 ]; then
    fail "install failed (exit $rc)"
    if [ -f "$UNSIGNED_HAP" ]; then
      warn "unsigned HAP kept at: $UNSIGNED_HAP"
    fi
    exit 1
  fi
}

launch_app() {
  log "launching $BUNDLE/$ABILITY"
  local out
  out="$("$HDC" -t "$TARGET" shell "aa start -a $ABILITY -b $BUNDLE" 2>&1 || true)"
  printf '%s\n' "$out"
  case "$out" in
    *"start ability successfully"*) ;;
    *) warn "the app did not report a successful start — check the device screen" ;;
  esac
}

require_tools
resolve_target
log "target: $TARGET"
ensure_transfer
build_hap
verify_signature
install_hap
launch_app
log "done"
