#!/bin/sh
# Deliberately holds shell $-syntax: locating must never render this file.
printf 'stamp:%s' "${1:-nobody}"
