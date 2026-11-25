#!/bin/sh
# Uruchamia wszystkie testy (wymaga luajit; luacheck opcjonalnie)
set -e
cd "$(dirname "$0")"
luajit tests/test_logic.lua
luajit tests/test_sim.lua
if command -v luacheck >/dev/null; then luacheck fr_standing_start.lua; fi
