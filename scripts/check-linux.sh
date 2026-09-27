#!/bin/sh
# Compatibility entry point; the shared check script supports both backends.
set -eu
exec "$(dirname "$0")/check.sh"
