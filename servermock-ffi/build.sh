#!/bin/bash
set -e

BUILD_MODE="debug"
for arg in "$@"; do
    case $arg in
        --release)
            BUILD_MODE="release"
            shift
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--release]"
            exit 1
            ;;
    esac
done

OS=$(uname -s)
case "$OS" in
    Linux*)
        LIB_NAME="libgreener_servermock.so"
        ;;
    Darwin*)
        LIB_NAME="libgreener_servermock.dylib"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        LIB_NAME="greener_servermock.dll"
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

if [ "$BUILD_MODE" = "release" ]; then
    go build -ldflags="-s -w" -trimpath -buildmode=c-shared -o "$LIB_NAME" .
else
    go build -buildmode=c-shared -o "$LIB_NAME" .
fi

mkdir -p include/greener_servermock

if [ -f "libgreener_servermock.h" ]; then
    mv libgreener_servermock.h include/greener_servermock/greener_servermock.h
elif [ -f "greener_servermock.h" ]; then
    mv greener_servermock.h include/greener_servermock/greener_servermock.h
fi

if [ "$OS" = "Darwin" ]; then
    install_name_tool -id @rpath/libgreener_servermock.dylib libgreener_servermock.dylib
fi

if [[ "$OS" =~ ^(MINGW|MSYS|CYGWIN) ]] && [ -f "greener_servermock.dll.lib" ]; then
    mv greener_servermock.dll.lib greener_servermock.lib
fi
