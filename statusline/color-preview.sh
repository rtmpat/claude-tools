#!/bin/bash
#
# color-preview.sh -- preview the accent colors available in context-bar.sh
# Part of: github.com/RTMPAT/claude-tools (statusline/)
#
# Prints a sample status segment in each theme so you can pick a COLOR value.
# Usage: bash color-preview.sh

C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'

# name:256-color-code -- mirrors the COLOR cases in context-bar.sh
themes=(
    "gray:245"
    "orange:173"
    "blue:74"
    "teal:66"
    "green:71"
    "lavender:139"
    "rose:132"
    "gold:136"
    "slate:60"
    "cyan:37"
)

printf 'Set COLOR="<name>" in context-bar.sh. Samples:\n\n'
for entry in "${themes[@]}"; do
    name="${entry%%:*}"
    code="${entry##*:}"
    accent="\033[38;5;${code}m"
    printf "  %-9s ${accent}claude-opus-4-7${C_GRAY} | 📁 my-project | 🔀 main${C_RESET}\n" "$name"
done
printf '\n'
