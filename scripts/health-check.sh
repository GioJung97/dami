#!/bin/zsh
# What the owner can't see: counters, app errors, crashes, database health. Reads only, and prints no dictated text.
domain=com.localflow.app
db="$HOME/Library/Application Support/LocalFlow/LocalFlow.sqlite"

echo "== Failures by kind and day"
defaults read $domain healthCounts 2>/dev/null || echo "none"

echo "== Dictations that pasted nothing, by reason, length and day (real silence counts too)"
echo "   empty = Whisper returned nothing; retry.* = what a Retry or Paste anyway led to"
defaults read $domain dropCountsByDay 2>/dev/null || echo "none"

echo "== Before v0.3.1: no day, and empty results counted as hallucination"
defaults read $domain dropCounts 2>/dev/null || echo "none"

echo "== App errors in the system log (only reaches back so far)"
/usr/bin/log show --last 7d --style compact \
    --predicate 'subsystem == "com.localflow.app" AND messageType == error' 2>/dev/null \
    | grep -v '^Timestamp' | cut -c1-160

echo "== Crash reports"
ls -lt "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | grep -i localflow | awk '{print $6, $7, $8, $9}'

echo "== Database"
/usr/bin/sqlite3 -readonly "$db" "PRAGMA quick_check; SELECT count(*) || ' dictations' FROM dictation;" 2>&1 | cut -c1-160
