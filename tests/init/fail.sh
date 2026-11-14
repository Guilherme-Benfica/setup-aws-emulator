#!/usr/bin/env bash
# Used by the init test: a failing init script must fail the action.
echo "this init script fails on purpose"
exit 1
