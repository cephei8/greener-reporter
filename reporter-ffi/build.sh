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
        LIB_NAME="libgreener_reporter.so"
        ;;
    Darwin*)
        LIB_NAME="libgreener_reporter.dylib"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        LIB_NAME="greener_reporter.dll"
        ;;
    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

if [ "$BUILD_MODE" = "release" ]; then
    go build -ldflags="-s -w" -trimpath -buildmode=c-shared -o "$LIB_NAME" .
else
    go build -buildmode=c-shared -o "$LIB_NAME" .
fi

mkdir -p include/greener_reporter

if [ -f "libgreener_reporter.h" ]; then
    mv libgreener_reporter.h include/greener_reporter/greener_reporter.h
elif [ -f "greener_reporter.h" ]; then
    mv greener_reporter.h include/greener_reporter/greener_reporter.h
fi

if [ "$OS" = "Darwin" ]; then
    install_name_tool -id @rpath/libgreener_reporter.dylib libgreener_reporter.dylib
fi

if [[ "$OS" =~ ^(MINGW|MSYS|CYGWIN) ]] && [ -f "greener_reporter.dll.lib" ]; then
    mv greener_reporter.dll.lib greener_reporter.lib
fi
