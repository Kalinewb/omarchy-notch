#!/bin/bash
# Sourced by dev/check.sh and dev/leftovers.sh.
#
# leftovers <dir>: one "pid command" line for every process that was started with
# TMPDIR=<dir> in its environment. check.sh gives each run a private TMPDIR, so
# what carries it after a suite has ended was started by that suite (a test
# notch, its inotifywait children, a stub that outlived its test), never by the
# live shell or another job.
leftovers() {
  local dir=$1 p
  for p in /proc/[0-9]*; do
    p=${p#/proc/}
    [[ $p == $$ || $p == "${BASHPID:-}" ]] && continue
    # Not readable: another user's, or already gone.
    { tr '\0' '\n' <"/proc/$p/environ" | grep -qxF "TMPDIR=$dir"; } 2>/dev/null || continue
    echo "$p $(tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | cut -c1-100)"
  done
}
