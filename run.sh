#!/bin/bash

# run.sh - Unified build and run script for osx-ide

PROJECT_NAME="osx-ide"
SCHEME="osx-ide"
DERIVED_DATA_PATH_APP="./.build"
DERIVED_DATA_PATH_TEST="./.build-tests"

show_help() {
    echo "Usage: ./run.sh [command]"
    echo ""
    echo "Commands:"
    echo "  app    Build and launch the application"
    echo "  build  Build the application"
    echo "  test   Run unit tests [optional suite]"
    echo "         Examples: ./run.sh test | ./run.sh test JSONHighlighterTests | ./run.sh test json"
    echo "  harness Run headless harness tests (separate from CI test)"
    echo "         Examples: ./run.sh harness | ./run.sh harness ConversationSendCoordinatorTests"
    echo "  e2e    Run UI (end-to-end) tests [optional suite]"
    echo "         Examples: ./run.sh e2e | ./run.sh e2e TerminalEchoUITests | ./run.sh e2e json"
    echo "  clean  Clean build artifacts"
    echo "  help   Show this help message"
}

build_app() {
    echo "Building $PROJECT_NAME..."
    xcodebuild -project "$PROJECT_NAME.xcodeproj" \
               -scheme "$SCHEME" \
               -configuration Debug \
               -derivedDataPath "$DERIVED_DATA_PATH_APP" \
               build
}

launch_app() {
    # Find the app bundle in derived data
    APP_PATH=$(find "$DERIVED_DATA_PATH_APP" -name "$PROJECT_NAME.app" -type d | head -n 1)
    
    if [ -z "$APP_PATH" ]; then
        echo "Error: Could not find built application. Please run './run.sh build' first."
        exit 1
    fi

    echo "Launching $APP_PATH..."
    open "$APP_PATH"
}

run_tests() {
    local suite=$1
    echo "Running unit tests..."
    if [ -n "$suite" ]; then
        if [ "$suite" = "json" ]; then
            suite="JSONHighlighterTests"
        fi
        echo "Filtering by suite: $suite"
        xcodebuild -project "$PROJECT_NAME.xcodeproj" \
                   -scheme "$SCHEME" \
                   -configuration Debug \
                   -derivedDataPath "$DERIVED_DATA_PATH_TEST" \
                   -destination 'platform=macOS' \
                   ENABLE_PREVIEWS=NO \
                   test -only-testing:osx-ideTests/"$suite" -skip-testing:osx-ideUITests -skip-testing:osx-ideHarnessTests
    else
        xcodebuild -project "$PROJECT_NAME.xcodeproj" \
                   -scheme "$SCHEME" \
                   -configuration Debug \
                   -derivedDataPath "$DERIVED_DATA_PATH_TEST" \
                   -destination 'platform=macOS' \
                   ENABLE_PREVIEWS=NO \
                   test -only-testing:osx-ideTests -skip-testing:osx-ideUITests -skip-testing:osx-ideHarnessTests
    fi
}

run_harness() {
    local suite=$1
    echo "Running headless harness tests..."
    
    # Build environment variables to pass to test runner
    # Using TEST_RUNNER_ENV_ prefix to pass env vars through xcodebuild to the test process
    local env_args=()
    if [ -n "$OSXIDE_ENABLE_PRODUCTION_PARITY_HARNESS" ]; then
        env_args+=("TEST_RUNNER_ENV_OSXIDE_ENABLE_PRODUCTION_PARITY_HARNESS=$OSXIDE_ENABLE_PRODUCTION_PARITY_HARNESS")
        echo "Production parity harness enabled"
    fi
    if [ -n "$HARNESS_MODEL_ID" ]; then
        env_args+=("TEST_RUNNER_ENV_HARNESS_MODEL_ID=$HARNESS_MODEL_ID")
        echo "Using model: $HARNESS_MODEL_ID"
    fi
    if [ -n "$HARNESS_USE_OPENROUTER" ]; then
        env_args+=("TEST_RUNNER_ENV_HARNESS_USE_OPENROUTER=$HARNESS_USE_OPENROUTER")
        echo "Using OpenRouter: $HARNESS_USE_OPENROUTER"
    fi
    
    if [ -n "$suite" ]; then
        echo "Filtering by suite: $suite"
        xcodebuild -project "$PROJECT_NAME.xcodeproj" \
                  -scheme "$SCHEME" \
                  -configuration Debug \
                  -derivedDataPath "$DERIVED_DATA_PATH_TEST" \
                  -destination 'platform=macOS' \
                  ENABLE_PREVIEWS=NO \
                  "${env_args[@]}" \
                  test -only-testing:osx-ideHarnessTests/"$suite" -skip-testing:osx-ideUITests -skip-testing:osx-ideTests
    else
        xcodebuild -project "$PROJECT_NAME.xcodeproj" \
                  -scheme "$SCHEME" \
                  -configuration Debug \
                  -derivedDataPath "$DERIVED_DATA_PATH_TEST" \
                  -destination 'platform=macOS' \
                  ENABLE_PREVIEWS=NO \
                  "${env_args[@]}" \
                  test \
                  -only-testing:osx-ideHarnessTests \
                  -skip-testing:osx-ideUITests \
                  -skip-testing:osx-ideTests
    fi
}

run_e2e() {
    local suite=$1
    echo "Running UI tests..."
    if [ -n "$suite" ]; then
        if [ "$suite" = "json" ]; then
            suite="JSONHighlighterUITests"
        fi
        echo "Filtering by suite: $suite"
        xcodebuild -project "$PROJECT_NAME.xcodeproj" \
                   -scheme "$SCHEME" \
                   -configuration Debug \
                   -derivedDataPath "$DERIVED_DATA_PATH_TEST" \
                   -destination 'platform=macOS' \
                   ENABLE_PREVIEWS=NO \
                   test -only-testing:osx-ideUITests/"$suite" -skip-testing:osx-ideTests
    else
        xcodebuild -project "$PROJECT_NAME.xcodeproj" \
                   -scheme "$SCHEME" \
                   -configuration Debug \
                   -derivedDataPath "$DERIVED_DATA_PATH_TEST" \
                   -destination 'platform=macOS' \
                   ENABLE_PREVIEWS=NO \
                   test -only-testing:osx-ideUITests -skip-testing:osx-ideTests
    fi
}

clean() {
    echo "Cleaning build artifacts..."
    rm -rf "$DERIVED_DATA_PATH_APP" "$DERIVED_DATA_PATH_TEST"
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
        run_tests "$2"
        ;;
    harness)
        run_harness "$2"
        ;;
    e2e)
        run_e2e "$2"
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
