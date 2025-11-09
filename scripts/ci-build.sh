#!/usr/bin/env bash

set -e

mkdir -p /output

if [ -z "$TARGETS" ]; then
    nix build
    cp -r result/* /output/
    rm -f result
else
    for target in $TARGETS; do
        nix build ".#$target"
        mkdir -p /output/$target
        cp -r result/* /output/$target/
        rm -f result
    done
fi
