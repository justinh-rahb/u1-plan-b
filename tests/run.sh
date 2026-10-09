#!/bin/sh
# Regression tests for files/bin/paxx-ab-run and paxx-ab-flipback, run against fake updateEngine,
# upfileUnpack, curl, df and reboot (no printer, no eMMC, no root, no network). Every fake logs its
# arguments to one file, so each test asserts on exactly what would have touched the device.
# The fakes are written out as shell source, so their $ must not expand here.
# shellcheck disable=SC2016
set -eu

# The shell the scripts under test run in: TEST_SH=dash or TEST_SH="busybox ash" to match the printer.
TEST_SH="${TEST_SH:-sh}"

HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/../files/bin/paxx-ab-run"
FLIPBACK="$HERE/../files/bin/paxx-ab-flipback"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

CALLS="$WORK/calls"
URL="https://github.com/paxx12/SnapmakerU1/releases/download/v1.6.0-paxx12-22/U1_extended_1.6.0-paxx12-22_upgrade.bin"
PAYLOAD="$WORK/payload.bin"
printf 'fake paxx upgrade package\n' > "$PAYLOAD"

mkdir "$WORK/bin"
fake() {
  name="$1"
  shift
  {
    echo '#!/bin/sh'
    echo "echo \"$name \$*\" >> \"$CALLS\""
    for line in "$@"; do echo "$line"; done
  } > "$WORK/bin/$name"
  chmod +x "$WORK/bin/$name"
}
# curl: the Moonraker query prints $FAKE_PRINT_STATE as Moonraker would; a download copies PAYLOAD.
fake curl \
  'case "$*" in *print_stats*) [ -n "${FAKE_PRINT_STATE:-}" ] || exit 7' \
  '  echo "{\"result\": {\"status\": {\"print_stats\": {\"state\": \"$FAKE_PRINT_STATE\"}}}}"; exit 0 ;; esac' \
  'out=""; while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done' \
  "cp \"$PAYLOAD\" \"\$out\""
fake upfileUnpack \
  'while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done' \
  '[ -n "${FAKE_NO_UPDATE_IMG:-}" ] && exit 0' \
  'mkdir -p "$out" && echo img > "$out/update.img"'
fake updateEngine '[ -n "${FAKE_UPDATE_FAIL:-}" ] && case "$*" in *--update*) exit 1 ;; esac; exit 0'
fake df 'echo "Filesystem 1K-blocks Used Available Use% Mounted"; echo "/dev/x 9 9 ${FAKE_FREE_KB:-9000000} 1% /userdata"'
fake reboot
fake sleep
# The device has sha256sum (BusyBox); macOS only has shasum.
if ! command -v sha256sum > /dev/null 2>&1; then
  printf '#!/bin/sh\nexec shasum -a 256 "$@"\n' > "$WORK/bin/sha256sum"
  chmod +x "$WORK/bin/sha256sum"
fi
PATH="$WORK/bin:$PATH"
export PATH

SHA="$(sha256sum "$PAYLOAD" | awk '{ print $1 }')"
BAD_SHA="0000000000000000000000000000000000000000000000000000000000000000"

reset() {
  rm -rf "$WORK/oem" "$WORK/state" "$WORK/userdata"
  mkdir -p "$WORK/oem"
  : > "$WORK/oem/.debug"
  : > "$WORK/oem/.printer_data"
  : > "$CALLS"
  echo "console=ttyFIQ0 android_slotsufix=_a rootwait" > "$WORK/cmdline"
  PAXX_AB_CMDLINE="$WORK/cmdline" PAXX_AB_OEM="$WORK/oem" PAXX_AB_WORK="$WORK/userdata/.paxx-ab"
  PAXX_AB_STATE="$WORK/state" PAXX_AB_MOONRAKER_WAIT=10 FAKE_PRINT_STATE=standby
  export PAXX_AB_CMDLINE PAXX_AB_OEM PAXX_AB_WORK PAXX_AB_STATE PAXX_AB_MOONRAKER_WAIT FAKE_PRINT_STATE
  unset FAKE_NO_UPDATE_IMG FAKE_UPDATE_FAIL FAKE_FREE_KB
}
run() { $TEST_SH "$RUN" "$@" > "$WORK/out" 2>&1; }
called() { grep -q "^$1" "$CALLS"; }
refuses() {
  why="$1"
  shift
  if run "$@"; then fail "$why: ran instead of refusing"; fi
  called "updateEngine" && fail "$why: updateEngine was called"
  called "reboot" && fail "$why: reboot was called"
  return 0
}

# 1. flash on slot _a: downloads, writes with the stock command, clears the stock flags, reboots.
reset
run flash "$URL" "$SHA" || fail "flash failed: $(cat "$WORK/out")"
grep -q "^updateEngine --image_url=$WORK/userdata/.paxx-ab/unpack/update.img --update$" "$CALLS" \
  || fail "updateEngine not called as systemUpgrade.sh does: $(cat "$CALLS")"
called reboot || fail "no reboot after a successful write"
if [ -e "$WORK/oem/.debug" ] || [ -e "$WORK/oem/.printer_data" ]; then
  fail "stock pre-activate flags not cleared"
fi
[ "$(cat "$WORK/state/written-$SHA")" = "_b" ] || fail "done marker missing or not slot _b"
[ ! -e "$WORK/userdata/.paxx-ab" ] || fail "work dir left behind"
grep -q "will write slot _b" "$WORK/out" || fail "slot _a did not target _b"

# 2. The same package at the next boot: nothing at all runs.
: > "$CALLS"
run flash "$URL" "$SHA" || fail "second run failed"
[ ! -s "$CALLS" ] || fail "second run called tools: $(cat "$CALLS")"

# 3. slot _b (the other spelling) targets _a.
reset
echo "androidboot.slot_suffix=_b" > "$WORK/cmdline"
run flash "$URL" "$SHA" || fail "flash from _b failed"
[ "$(cat "$WORK/state/written-$SHA")" = "_a" ] || fail "slot _b did not target _a"

# 4. dry-run downloads and checks, writes nothing, reboots nothing, leaves the flags alone.
reset
run dry-run "$URL" "$SHA" || fail "dry run failed: $(cat "$WORK/out")"
called updateEngine && fail "dry run called updateEngine"
called reboot && fail "dry run rebooted"
[ -e "$WORK/oem/.debug" ] || fail "dry run removed .debug"
[ ! -e "$WORK/state/written-$SHA" ] || fail "dry run wrote the done marker"
grep -q "would run: updateEngine" "$WORK/out" || fail "dry run did not say what it would do"

# 5. Refusals before anything touches the device.
reset; refuses "bad mode" go "$URL" "$SHA"
reset; refuses "non-paxx URL" flash "https://example.com/U1_extended_x_upgrade.bin" "$SHA"
reset; refuses "URL with shell characters" flash "${URL%.bin};reboot_upgrade.bin" "$SHA"
reset; refuses "short sha" flash "$URL" "abc"
reset; refuses "non-hex sha" flash "$URL" "$(echo "$SHA" | sed 's/./z/')"
reset; echo "console=ttyFIQ0" > "$WORK/cmdline"; refuses "no slot suffix" flash "$URL" "$SHA"
reset; FAKE_PRINT_STATE=printing; refuses "printing" flash "$URL" "$SHA"
reset; FAKE_PRINT_STATE=paused; refuses "paused" flash "$URL" "$SHA"
reset; FAKE_PRINT_STATE=""; refuses "Moonraker down" flash "$URL" "$SHA"
reset; FAKE_FREE_KB=1000; export FAKE_FREE_KB; refuses "low disk" flash "$URL" "$SHA"
reset; refuses "sha mismatch" flash "$URL" "$BAD_SHA"
[ ! -e "$WORK/userdata/.paxx-ab" ] || fail "sha mismatch left the download behind"
reset; FAKE_NO_UPDATE_IMG=1; export FAKE_NO_UPDATE_IMG; refuses "no update.img" flash "$URL" "$SHA"

# 6. updateEngine fails: no reboot, no marker, flags untouched.
reset
FAKE_UPDATE_FAIL=1
export FAKE_UPDATE_FAIL
if run flash "$URL" "$SHA"; then fail "updateEngine failure reported success"; fi
called reboot && fail "rebooted after updateEngine failed"
[ ! -e "$WORK/state/written-$SHA" ] || fail "done marker written after updateEngine failed"
[ -e "$WORK/oem/.debug" ] || fail ".debug removed after updateEngine failed"

# 7. flipback needs --yes, then flips with the stock command and reboots.
reset
if $TEST_SH "$FLIPBACK" > /dev/null 2>&1; then fail "flipback ran without --yes"; fi
[ ! -s "$CALLS" ] || fail "flipback without --yes called tools"
$TEST_SH "$FLIPBACK" --yes > /dev/null 2>&1 || fail "flipback --yes failed"
called "updateEngine --misc=other" || fail "flipback did not run updateEngine --misc=other"
called reboot || fail "flipback did not reboot"
reset
echo "console=ttyFIQ0" > "$WORK/cmdline"
if $TEST_SH "$FLIPBACK" --yes > /dev/null 2>&1; then fail "flipback ran without a slot suffix"; fi

echo "All paxx-ab tests passed."
