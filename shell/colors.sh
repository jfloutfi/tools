#!/bin/zsh
# colors.sh - preview all 256 terminal colors in zsh

for i in {0..255}; do
  print -Pn "%F{$i}$i%f "
done
echo
