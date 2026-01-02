#!/bin/bash

# run.sh - Unified build and run script for osx-ide

PROJECT_NAME="osx-ide"
SCHEME="osx-ide"
DERIVED_DATA_PATH="./.build"

show_help() {
    echo "Usage: ./run.sh [command]"
    echo ""
    echo "Commands:"
    echo "  app    Build and launch the application"
    echo "  build  Build the application"
    echo "  test   Run unit tests"
    echo "  e2e    Run UI (end-to-end) tests"
    echo "  clean  Clean build artifacts"
    echo "  help   Show this help message"
}

build_app() {
    echo "Building $PROJECT_NAME..."
    xcodebuild -project "$PROJECT_NAME.xcodeproj" \
               -scheme "$SCHEME" \
               -configuration Debug \
               -derivedDataPath "$DERIVED_DATA_PATH" \
               build
}

launch_app() {
    # Find the app bundle in derived data
    APP_PATH=$(find "$DERIVED_DATA_PATH" -name "$PROJECT_NAME.app" -type d | head -n 1)
    
    if [ -z "$APP_PATH" ]; then
        echo "Error: Could not find built application. Please run './run.sh build' first."
        exit 1
    fi

    echo "Launching $APP_PATH..."
    open "$APP_PATH"
}

run_tests() {
    echo "Running unit tests..."
    xcodebuild -project "$PROJECT_NAME.xcodeproj" \
               -scheme "$SCHEME" \
               -configuration Debug \
               -derivedDataPath "$DERIVED_DATA_PATH" \
               -destination 'platform=macOS' \
               test -only-testing:osx-ideTests
}

run_e2e() {
    echo "Running UI tests..."
    xcodebuild -project "$PROJECT_NAME.xcodeproj" \
               -scheme "$SCHEME" \
               -configuration Debug \
               -derivedDataPath "$DERIVED_DATA_PATH" \
               -destination 'platform=macOS' \
               test -only-testing:osx-ideUITests
}

clean() {
    echo "Cleaning build artifacts..."
    rm -rf "$DERIVED_DATA_PATH"
    xcodebuild -project "$PROJECT_NAME.xcodeproj" -scheme "$SCHEME" clean
}

COMMAND=$1

case "$COMMAND" in
    app)
        build_app
        if [ $? -eq 0 ]; then
            launch_app
        fi
        ;;
    build)
        build_app
        ;;
    test)
        run_tests
        ;;
    e2e)
        run_e2e
        ;;
    clean)
        clean
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        if [ -z "$COMMAND" ]; then
            show_help
        else
            echo "Unknown command: $COMMAND"
            show_help
            exit 1
        fi
        ;;
esac
