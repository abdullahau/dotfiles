#!/usr/bin/env bash
# Volume/brightness OSD: (re)start xob reading from /tmp/xobpipe.
# Kills the previous pipeline first so i3 restarts don't pile up copies.
pkill -x xob
pkill -f '^tail -f /tmp/xobpipe$'
[ -p /tmp/xobpipe ] || { rm -f /tmp/xobpipe; mkfifo /tmp/xobpipe; }
exec sh -c 'tail -f /tmp/xobpipe | xob -t 2170'
