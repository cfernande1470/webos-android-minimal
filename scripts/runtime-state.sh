#!/bin/sh

runtime_state_file() {
  printf '%s\n' "${SIDE:?}/run/runtime.state"
}

runtime_timeline_file() {
  printf '%s\n' "${SIDE:?}/run/runtime.timeline"
}

runtime_state_write() {
  phase="$1"
  shift

  mkdir -p "${SIDE:?}/run"

  state_file="$(runtime_state_file)"
  timeline_file="$(runtime_timeline_file)"
  tmp="$state_file.tmp.$$"

  {
    printf 'phase=%s\n' "$phase"
    printf 'updated_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    while [ "$#" -gt 0 ]; do
      printf '%s\n' "$1"
      shift
    done
  } > "$tmp"

  mv "$tmp" "$state_file"

  {
    printf '%s phase=%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$phase"
    while [ "$#" -gt 0 ]; do
      printf ' %s' "$1"
      shift
    done
    printf '\n'
  } >> "$timeline_file"
}

runtime_state_read() {
  cat "$(runtime_state_file)" 2>/dev/null || true
}
