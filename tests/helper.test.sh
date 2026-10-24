#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin" "$fixture_dir/state" "$fixture_dir/config/hypr"

cat >"$fixture_dir/config/hypr/hyprsunset.conf" <<'CONF'
# Original user Night Light configuration.
profile {
    time = 07:00
    identity = true
}
CONF

cat >"$fixture_dir/config/hypr/monitors.lua" <<'LUA'
local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1
hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
LUA

cat >"$fixture_dir/monitors.json" <<'JSON'
[
  {"name":"eDP-1","description":"Internal","make":"BOE","model":"Panel","serial":"ABC","disabled":false,"focused":true,"width":1920,"height":1200,"refreshRate":60.001,"x":0,"y":0,"scale":1,"transform":0,"mirrorOf":"none","availableModes":["1920x1200@60.001","1280x800@60"]},
  {"name":"DP-1","description":"Desk","make":"Dell","model":"U2723QE","serial":"XYZ","disabled":false,"focused":false,"width":3840,"height":2160,"refreshRate":60,"x":1920,"y":0,"scale":2,"transform":0,"mirrorOf":"none","availableModes":["3840x2160@60","2560x1440@60"]}
]
JSON

cat >"$fixture_dir/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == -j && ${2:-} == monitors ]]; then
  cat "$TEST_MONITORS"
  exit 0
fi

if [[ ${1:-} == reload ]]; then
  exit 0
fi

if [[ ${1:-} == hyprsunset && ${2:-} == temperature ]]; then
  if [[ -n ${3:-} ]]; then printf '%s\n' "$3" >"$TEST_NIGHT_TEMP"; fi
  printf 'Temperature: %s K\n' "$(<"$TEST_NIGHT_TEMP")"
  exit 0
fi

if [[ ${1:-} == eval ]]; then
  expression=${2:-}
  printf '%s\n' "$expression" >>"$TEST_CALLS"

  if [[ -f $TEST_PAUSE_NEXT_EVAL ]]; then
    rm -f "$TEST_PAUSE_NEXT_EVAL"
    : >"$TEST_EVAL_STARTED"
    while [[ -f $TEST_HOLD_EVAL ]]; do sleep 0.01; done
  fi

  if [[ -f $TEST_FAIL_NEXT_EVAL ]]; then
    rm -f "$TEST_FAIL_NEXT_EVAL"
    exit 1
  fi

  if [[ -f $TEST_FAIL_EVAL_AT ]]; then
    fail_at=$(<"$TEST_FAIL_EVAL_AT")
    if (( fail_at <= 1 )); then
      rm -f "$TEST_FAIL_EVAL_AT"
      exit 1
    fi
    printf '%s\n' "$((fail_at - 1))" >"$TEST_FAIL_EVAL_AT"
  fi

  if [[ -f $TEST_IGNORE_EVALS ]]; then
    remaining=$(<"$TEST_IGNORE_EVALS")
    if (( remaining > 0 )); then
      printf '%s\n' "$((remaining - 1))" >"$TEST_IGNORE_EVALS"
      exit 0
    fi
  fi

  [[ $expression =~ output[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]] || exit 1
  name=${BASH_REMATCH[1]}
  tmp="$TEST_MONITORS.tmp"

  if [[ $expression == *"disabled = true"* ]]; then
    jq --arg name "$name" 'map(if .name == $name then .disabled = true else . end)' \
      "$TEST_MONITORS" >"$tmp"
  else
    [[ $expression =~ mode[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]] || exit 1
    mode=${BASH_REMATCH[1]}
    [[ $mode =~ ^([0-9]+)x([0-9]+)@([0-9.]+)$ ]] || exit 1
    width=${BASH_REMATCH[1]}
    height=${BASH_REMATCH[2]}
    refresh=${BASH_REMATCH[3]}
    if [[ $expression =~ position[[:space:]]*=[[:space:]]*\"(-?[0-9]+)x(-?[0-9]+)\" ]]; then
      x=${BASH_REMATCH[1]}
      y=${BASH_REMATCH[2]}
    elif [[ $expression == *'position = "auto"'* ]]; then
      x=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .x' "$TEST_MONITORS")
      y=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .y' "$TEST_MONITORS")
    else
      exit 1
    fi
    [[ $expression =~ scale[[:space:]]*=[[:space:]]*([0-9.]+) ]] || exit 1
    scale=${BASH_REMATCH[1]}
    [[ $expression =~ transform[[:space:]]*=[[:space:]]*([0-7]) ]] || exit 1
    transform=${BASH_REMATCH[1]}
    mirror=none
    if [[ $expression =~ mirror[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
      mirror=${BASH_REMATCH[1]}
    fi
    jq --arg name "$name" --arg mirror "$mirror" \
      --argjson width "$width" --argjson height "$height" --argjson refresh "$refresh" \
      --argjson x "$x" --argjson y "$y" --argjson scale "$scale" --argjson transform "$transform" '
      map(if .name == $name then
        .disabled = false
        | .width = $width | .height = $height | .refreshRate = $refresh
        | .x = $x | .y = $y | .scale = $scale | .transform = $transform
        | .mirrorOf = $mirror
      else . end)' "$TEST_MONITORS" >"$tmp"
  fi
  mv "$tmp" "$TEST_MONITORS"
  exit 0
fi

exit 1
SH

cat >"$fixture_dir/bin/systemd-run" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_SYSTEMD_CALLS"
if [[ -f $TEST_FAIL_NEXT_SYSTEMD_RUN ]]; then
  rm -f "$TEST_FAIL_NEXT_SYSTEMD_RUN"
  exit 1
fi
exit 0
SH

cat >"$fixture_dir/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_SYSTEMCTL_CALLS"
exit 0
SH

cat >"$fixture_dir/bin/pkill" <<'SH'
#!/usr/bin/env bash
exit 0
SH

cat >"$fixture_dir/bin/omarchy-brightness-display" <<'SH'
#!/usr/bin/env bash
case ${2:-} in
  eDP-1) echo 61 ;;
  DP-1) echo 72 ;;
  *) exit 1 ;;
esac
SH

cat >"$fixture_dir/bin/omarchy-hyprland-monitor-laptop" <<'SH'
#!/usr/bin/env bash
echo eDP-1
SH

chmod +x "$fixture_dir/bin/"*

export PATH="$fixture_dir/bin:$PATH"
export XDG_STATE_HOME="$fixture_dir/state"
export XDG_CONFIG_HOME="$fixture_dir/config"
export DISPLAY_MANAGER_SETTINGS_FILE="$fixture_dir/config/plugin-settings.json"
export TEST_MONITORS="$fixture_dir/monitors.json"
export TEST_CALLS="$fixture_dir/calls"
export TEST_SYSTEMD_CALLS="$fixture_dir/systemd-calls"
export TEST_SYSTEMCTL_CALLS="$fixture_dir/systemctl-calls"
export TEST_FAIL_NEXT_EVAL="$fixture_dir/fail-next-eval"
export TEST_FAIL_EVAL_AT="$fixture_dir/fail-eval-at"
export TEST_IGNORE_EVALS="$fixture_dir/ignore-evals"
export TEST_FAIL_NEXT_SYSTEMD_RUN="$fixture_dir/fail-next-systemd-run"
export TEST_PAUSE_NEXT_EVAL="$fixture_dir/pause-next-eval"
export TEST_EVAL_STARTED="$fixture_dir/eval-started"
export TEST_HOLD_EVAL="$fixture_dir/hold-eval"
export TEST_NIGHT_TEMP="$fixture_dir/night-temperature"
export DISPLAY_MANAGER_SETTLE_SECONDS=0
helper="$project_dir/bin/display-manager"
printf '6500\n' >"$TEST_NIGHT_TEMP"

state=$($helper state)
jq -e 'length == 2 and .[0].fingerprint == "BOE|Panel|ABC" and .[1].scale == 2' <<<"$state" >/dev/null
[[ $($helper topology) == '"BOE|Panel|ABC::Dell|U2723QE|XYZ"' ]]
$helper brightness-state | jq -e '
  length == 2
  and .[0] == {name:"eDP-1",available:true,value:61}
  and .[1] == {name:"DP-1",available:true,value:72}' >/dev/null

$helper night-light-schedule-state | jq -e '
  .enabled == false and .start == "20:00" and .end == "07:00" and .temperature == 4000' >/dev/null
mkdir -p "$XDG_STATE_HOME/omarchy-display-settings"
printf '%s\n' '{"enabled":false,"start":"19:30","end":"06:30","temperature":3800}' \
  >"$XDG_STATE_HOME/omarchy-display-settings/night-light-schedule.json"
$helper night-light-schedule-state | jq -e '
  .enabled == false and .start == "19:30" and .end == "06:30" and .temperature == 3800' >/dev/null
$helper night-light-set 4000 | jq -e '.ok == true and .enabled == true and .temperature == 4000' >/dev/null
[[ $(<"$TEST_NIGHT_TEMP") == 4000 ]]
$helper night-light-set 1600 | jq -e '.ok == true and .enabled == true and .temperature == 1600' >/dev/null
[[ $(<"$TEST_NIGHT_TEMP") == 1600 ]]
$helper night-light-set 6500 | jq -e '.ok == true and .enabled == false and .temperature == 6500' >/dev/null
if $helper night-light-set 1500 >/dev/null 2>&1; then
  echo "Expected a below-minimum Night Light temperature to fail" >&2
  exit 1
fi
if $helper night-light-set 7000 >/dev/null 2>&1; then
  echo "Expected an invalid Night Light temperature to fail" >&2
  exit 1
fi
original_sunset=$(sha256sum "$XDG_CONFIG_HOME/hypr/hyprsunset.conf" | cut -d' ' -f1)
schedule='{"enabled":true,"start":"21:30","end":"06:45","temperature":1600}'
$helper night-light-schedule-set "$schedule" | jq -e '
  .enabled == true and .start == "21:30" and .end == "06:45" and .temperature == 1600' >/dev/null
[[ ! -e $XDG_STATE_HOME/omarchy-display-settings/night-light-schedule.json ]]
jq -e '.version == 1 and .nightLight.schedule == {
  enabled:true,start:"21:30",end:"06:45",temperature:1600
}' "$DISPLAY_MANAGER_SETTINGS_FILE" >/dev/null
grep -Fqx '    time = 21:30' "$XDG_CONFIG_HOME/hypr/hyprsunset.conf"
grep -Fqx '    time = 06:45' "$XDG_CONFIG_HOME/hypr/hyprsunset.conf"
grep -Fqx '    temperature = 1600' "$XDG_CONFIG_HOME/hypr/hyprsunset.conf"
[[ -f $XDG_CONFIG_HOME/hypr/hyprsunset.conf.pre-display-settings ]]
grep -Fqx -- '--user enable hyprsunset.service' "$TEST_SYSTEMCTL_CALLS"
grep -Fqx -- '--user reset-failed hyprsunset.service' "$TEST_SYSTEMCTL_CALLS"
grep -Fqx -- '--user restart hyprsunset.service' "$TEST_SYSTEMCTL_CALLS"
$helper night-light-schedule-set '{"enabled":false,"start":"21:30","end":"06:45","temperature":1600}' >/dev/null
[[ $(sha256sum "$XDG_CONFIG_HOME/hypr/hyprsunset.conf" | cut -d' ' -f1) == "$original_sunset" ]]
grep -Fqx -- '--user disable --now hyprsunset.service' "$TEST_SYSTEMCTL_CALLS"

config=$(jq -c '[.[0] + {x:1920,transform:1,mode:"1920x1200@60.001Hz"}, .[1] + {x:0}]' <<<"$state")
touch "$TEST_PAUSE_NEXT_EVAL" "$TEST_HOLD_EVAL"
$helper preview "$config" >"$fixture_dir/preview-result" &
preview_pid=$!
for _ in {1..100}; do
  [[ -f $TEST_EVAL_STARTED ]] && break
  sleep 0.01
done
[[ -f $TEST_EVAL_STARTED ]]
$helper profiles-match >"$fixture_dir/pending-match-result" &
match_pid=$!
sleep 0.1
kill -0 "$match_pid"
rm -f "$TEST_HOLD_EVAL"
wait "$preview_pid"
wait "$match_pid"
preview_result=$(<"$fixture_dir/preview-result")
jq -e '.ok == true and .timeout == 20' <<<"$preview_result" >/dev/null
jq -e '.ok == true and .matched == false and .pending == true' "$fixture_dir/pending-match-result" >/dev/null
grep -q '^hl.monitor({ output = "eDP-1", mode = "1920x1200@60.001", position = "1920x0", scale = 1, transform = 1 })$' "$TEST_CALLS"
grep -q '^--user --quiet --unit=omarchy-display-settings-rollback --on-active=20s .*display-manager rollback$' "$TEST_SYSTEMD_CALLS"
$helper state | jq -e '.[0].x == 1920 and .[0].transform == 1 and .[1].x == 0' >/dev/null
$helper confirm >/dev/null

scale_config=$(jq -c '.[0].scale = 1.25' <<<"$config")
$helper preview "$scale_config" >/dev/null
$helper state | jq -e '.[0].scale == 1.25' >/dev/null
grep -q '^hl.monitor({ output = "eDP-1", mode = "1920x1200@60.001", position = "auto", scale = 1.25, transform = 1 })$' "$TEST_CALLS"
$helper confirm >/dev/null
grep -Fqx -- '-- Display Settings uses the verified per-display rules below.' "$XDG_CONFIG_HOME/hypr/monitors.lua"
grep -Fqx -- '-- hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })' "$XDG_CONFIG_HOME/hypr/monitors.lua"
grep -Fqx -- '-- BEGIN Omarchy Display Settings managed monitor rules' "$XDG_CONFIG_HOME/hypr/monitors.lua"
grep -Fqx -- 'hl.monitor({ output = "eDP-1", mode = "1920x1200@60.001", position = "1920x0", scale = 1.25, transform = 1 })' "$XDG_CONFIG_HOME/hypr/monitors.lua"
grep -q '^local omarchy_monitor_scale = 1$' "$XDG_CONFIG_HOME/hypr/monitors.lua"
[[ -f $XDG_CONFIG_HOME/hypr/monitors.lua.pre-display-settings ]]
rules_inode=$(stat -c %i "$XDG_CONFIG_HOME/hypr/monitors.lua")
$helper confirm >/dev/null
[[ $(stat -c %i "$XDG_CONFIG_HOME/hypr/monitors.lua") == "$rules_inode" ]]

$helper profiles-save Default "$config" true >/dev/null
$helper profiles-list | jq -e '.profiles | length == 1 and .[0].name == "Default" and .[0].automatic == true' >/dev/null

jq '.[1].serial = "XYZ-DOCK-2"' "$TEST_MONITORS" >"$fixture_dir/next-topology.json"
mv "$fixture_dir/next-topology.json" "$TEST_MONITORS"
second_state=$($helper state)
$helper profiles-save Default "$second_state" true >/dev/null
$helper profiles-list | jq -e '
  .profiles | length == 2
  and all(.[]; .name == "Default" and .automatic == true)
  and ([.[].topology] | unique | length) == 2' >/dev/null
calls_before=$(wc -l <"$TEST_CALLS")
$helper profiles-match | jq -e '.matched == false and .unchanged == true and .name == "Default"' >/dev/null
[[ $(wc -l <"$TEST_CALLS") == "$calls_before" ]]
jq '.[0].transform = 0' "$TEST_MONITORS" >"$fixture_dir/drifted-topology.json"
mv "$fixture_dir/drifted-topology.json" "$TEST_MONITORS"
$helper profiles-match | jq -e '.matched == true and .name == "Default"' >/dev/null
$helper state | jq -e '.[0].transform == 1' >/dev/null

bad_profile=$(jq -c '.[0].transform = 2' <<<"$second_state")
$helper profiles-save Default "$bad_profile" true >/dev/null
before_match=$(sha256sum "$TEST_MONITORS" | cut -d' ' -f1)
printf '2\n' >"$TEST_IGNORE_EVALS"
if $helper profiles-match >/dev/null 2>&1; then
  echo "Expected a rejected automatic profile to fail" >&2
  exit 1
fi
after_match=$(sha256sum "$TEST_MONITORS" | cut -d' ' -f1)
[[ $before_match == "$after_match" ]]

$helper profiles-delete Default | jq -e '.profiles | length == 0' >/dev/null

for invalid in \
  '[]' \
  "$(jq -c '.[1].name = .[0].name' <<<"$second_state")" \
  "$(jq -c '.[1].x = 2000' <<<"$second_state")" \
  "$(jq -c '.[1].x = 4000' <<<"$second_state")" \
  "$(jq -c '.[0].mirror = .[0].name' <<<"$second_state")" \
  "$(jq -c '.[0].mirror = "missing"' <<<"$second_state")"; do
  if $helper preview "$invalid" >/dev/null 2>&1; then
    echo "Expected invalid configuration to fail" >&2
    exit 1
  fi
done

rejected=$(jq -c '.[0].y += 100 | .[0].transform = 3' <<<"$second_state")
printf '2\n' >"$TEST_IGNORE_EVALS"
if $helper preview "$rejected" >/dev/null 2>&1; then
  echo "Expected unapplied position and transform to fail verification" >&2
  exit 1
fi
[[ ! -e $XDG_STATE_HOME/omarchy-display-settings/pending.json ]]

printf '2\n' >"$TEST_IGNORE_EVALS"
printf '3\n' >"$TEST_FAIL_EVAL_AT"
if recovery_error=$($helper preview "$rejected" 2>&1); then
  echo "Expected a failed recovery attempt to be reported" >&2
  exit 1
fi
jq -e '.error | contains("recovery snapshot remains")' <<<"$recovery_error" >/dev/null
[[ -e $XDG_STATE_HOME/omarchy-display-settings/pending.json ]]
rm -f "$XDG_STATE_HOME/omarchy-display-settings/pending.json"

touch "$TEST_FAIL_NEXT_EVAL"
if $helper preview "$second_state" >/dev/null 2>&1; then
  echo "Expected a compositor command failure to roll back" >&2
  exit 1
fi
[[ ! -e $XDG_STATE_HOME/omarchy-display-settings/pending.json ]]

scheduled_failure=$(jq -c '.[0].transform = 2' <<<"$second_state")
touch "$TEST_FAIL_NEXT_SYSTEMD_RUN"
if $helper preview "$scheduled_failure" >/dev/null 2>&1; then
  echo "Expected a rollback scheduling failure to restore the snapshot" >&2
  exit 1
fi
$helper state | jq -e '.[0].transform == 1' >/dev/null
[[ ! -e $XDG_STATE_HOME/omarchy-display-settings/pending.json ]]

mirror_config=$(jq -c '.[0].mirror = .[1].name' <<<"$second_state")
$helper preview "$mirror_config" >/dev/null
$helper state | jq -e '.[0].mirror == "DP-1"' >/dev/null
$helper revert >/dev/null
$helper state | jq -e '.[0].mirror == ""' >/dev/null

auto_before=$($helper state)
auto_config=$(jq -c '.[0].transform = 2' <<<"$auto_before")
$helper apply "$auto_config" | jq -e '.ok == true and .undo == true' >/dev/null
$helper state | jq -e '.[0].transform == 2' >/dev/null
$helper undo-state | jq -e '.available == true' >/dev/null
$helper profiles-list | jq -e '.profiles | any(.name == "Default" and .automatic == true)' >/dev/null
$helper undo | jq -e '.ok == true' >/dev/null
$helper state | jq -e '.[0].transform == 1' >/dev/null
$helper undo-state | jq -e '.available == false' >/dev/null

echo "display-manager helper tests passed"
