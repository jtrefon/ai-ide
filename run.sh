#!/bin/bash

# run.sh - Unified build and run script for osx-ide

PROJECT_NAME="osx-ide"
SCHEME="osx-ide"
DERIVED_DATA_PATH_APP="./.build"
DERIVED_DATA_PATH_TEST="./.build-tests"

prepare_derived_data_packages() {
    local derived_data_path=$1
    xcodebuild -resolvePackageDependencies \
        -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -derivedDataPath "$derived_data_path" >/dev/null
}

collect_descendant_pids() {
    local root_pid=$1
    local children
    children=$(pgrep -P "$root_pid" || true)
    for child_pid in $children; do
        echo "$child_pid"
        collect_descendant_pids "$child_pid"
    done
}

collect_guarded_family_pids() {
    local root_pid=$1
    local root_pgid
    local derived_data_root
    root_pgid=$(ps -o pgid= -p "$root_pid" 2>/dev/null | awk '{print $1}')
    derived_data_root=$(cd "$DERIVED_DATA_PATH_TEST" 2>/dev/null && pwd -P)

    {
        echo "$root_pid"
        collect_descendant_pids "$root_pid"
        if [ -n "$root_pgid" ]; then
            ps -axo pid=,pgid=,comm= | awk -v pgid="$root_pgid" -v project_name="$PROJECT_NAME" -v derived_data_root="$derived_data_root" '
                function basename(path, parts, count) {
                    count = split(path, parts, "/")
                    return parts[count]
                }

                {
                    full_command = $3
                    command_name = basename(full_command)
                    is_project_process = 0
                    is_test_tool = 0
                    is_derived_data_app = 0

                    if (command_name == project_name ||
                        command_name == project_name "-Runner" ||
                        command_name == project_name "Tests" ||
                        command_name == project_name "HarnessTests") {
                        is_project_process = 1
                    }

                    if (command_name == "xcodebuild" || command_name == "xctest") {
                        is_test_tool = 1
                    }

                    if (derived_data_root != "" &&
                        index(full_command, derived_data_root) == 1 &&
                        is_project_process == 1) {
                        is_derived_data_app = 1
                    }

                    if (($2 == pgid && (is_test_tool == 1 || is_project_process == 1)) || is_derived_data_app == 1) {
                        print $1
                    }
                }
            '
        fi
    } | awk 'NF { if (!seen[$1]++) print $1 }'
}

describe_guarded_family() {
    local root_pid=$1
    local family_pids
    family_pids=$(collect_guarded_family_pids "$root_pid" | paste -sd, -)
    if [ -z "$family_pids" ]; then
        return
    fi

    ps -axo pid=,ppid=,pgid=,rss=,comm= | awk -v family_csv="$family_pids" '
        BEGIN {
            split(family_csv, pids, ",")
            for (pid_index in pids) {
                tracked[pids[pid_index]] = 1
            }
        }
        tracked[$1] {
            printf "%s(ppid=%s,pgid=%s,rss_mb=%d,comm=%s)", $1, $2, $3, int($4 / 1024), $5
        }
    ' | paste -sd';' -
}

sum_process_tree_rss_mb() {
    local root_pid=$1
    local rss_kb=0
    local pid

    for pid in $(collect_guarded_family_pids "$root_pid"); do
        local pid_rss
        pid_rss=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{s+=$1} END {print s+0}')
        rss_kb=$((rss_kb + pid_rss))
    done

    echo $((rss_kb / 1024))
}

kill_process_tree() {
    local root_pid=$1
    local pid

    for pid in $(collect_guarded_family_pids "$root_pid"); do
        kill -TERM "$pid" 2>/dev/null || true
    done

    sleep 2

    for pid in $(collect_guarded_family_pids "$root_pid"); do
        kill -KILL "$pid" 2>/dev/null || true
    done
}

run_with_memory_guard() {
    local rss_limit_gb=$1
    shift
    local rss_limit_mb=$((rss_limit_gb * 1024))
    local check_interval_seconds="${HARNESS_MEMORY_CHECK_INTERVAL_SECONDS:-1}"
    local status_file
    status_file=$(mktemp)

    "$@" &
    local guarded_pid=$!

    cleanup_guarded_processes() {
        if [ -n "$monitor_pid" ]; then
            kill "$monitor_pid" 2>/dev/null || true
            wait "$monitor_pid" 2>/dev/null || true
        fi
        if kill -0 "$guarded_pid" 2>/dev/null; then
            echo "[harness-memory] interruption detected, terminating harness process tree"
            kill_process_tree "$guarded_pid"
        fi
    }

    trap cleanup_guarded_processes INT TERM

    (
        while kill -0 "$guarded_pid" 2>/dev/null; do
            local rss_mb
            local family_description
            rss_mb=$(sum_process_tree_rss_mb "$guarded_pid")
            family_description=$(describe_guarded_family "$guarded_pid")
            echo "[harness-memory] pid=$guarded_pid rss_mb=$rss_mb limit_mb=$rss_limit_mb family=${family_description:-unavailable}"

            if [ "$rss_mb" -ge "$rss_limit_mb" ]; then
                echo "[harness-memory] limit exceeded, terminating harness test process tree"
                echo "killed" > "$status_file"
                kill_process_tree "$guarded_pid"
                break
            fi

            sleep "$check_interval_seconds"
        done
    ) &
    local monitor_pid=$!

    wait "$guarded_pid"
    local command_exit_code=$?
    trap - INT TERM
    kill "$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true

    if grep -q "killed" "$status_file" 2>/dev/null; then
        rm -f "$status_file"
        echo "[harness-memory] harness terminated due to memory guard (limit ${rss_limit_gb}GB)"
        return 99
    fi

    rm -f "$status_file"
    return "$command_exit_code"
}

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
    echo "  harness-online Run online production-parity harness suites"
    echo "         Examples: ./run.sh harness-online | ./run.sh harness-online AgenticHarnessTests"
    echo "  harness-offline Run offline-only harness suites"
    echo "         Examples: ./run.sh harness-offline | ./run.sh harness-offline OfflineModeHarnessTests"
    echo "  benchmark-offline Run offline inference benchmark harnesses"
    echo "         Examples: ./run.sh benchmark-offline | ./run.sh benchmark-offline sweep"
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
    local explicit_modules="${SWIFT_ENABLE_EXPLICIT_MODULES:-NO}"
    echo "Running unit tests..."
    prepare_derived_data_packages "$DERIVED_DATA_PATH_TEST"
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
                   SWIFT_ENABLE_EXPLICIT_MODULES="$explicit_modules" \
                   test -only-testing:osx-ideTests/"$suite" -skip-testing:osx-ideUITests -skip-testing:osx-ideHarnessTests
    else
        xcodebuild -project "$PROJECT_NAME.xcodeproj" \
                   -scheme "$SCHEME" \
                   -configuration Debug \
                   -derivedDataPath "$DERIVED_DATA_PATH_TEST" \
                   -destination 'platform=macOS' \
                   ENABLE_PREVIEWS=NO \
                   SWIFT_ENABLE_EXPLICIT_MODULES="$explicit_modules" \
                   test -only-testing:osx-ideTests -skip-testing:osx-ideUITests -skip-testing:osx-ideHarnessTests
    fi
}

run_harness() {
    local suite=$1
    local explicit_modules="${SWIFT_ENABLE_EXPLICIT_MODULES:-NO}"
    echo "Running headless harness tests..."
    prepare_derived_data_packages "$DERIVED_DATA_PATH_TEST"
    local harness_memory_limit_gb="${HARNESS_MAX_RSS_GB:-6}"
    echo "Harness memory guard enabled: ${harness_memory_limit_gb}GB limit"
    local harness_memory_limit_mb=$((harness_memory_limit_gb * 1024))
    local local_model_memory_limit_mb="${OSXIDE_LOCAL_MODEL_MAX_RSS_MB:-$((harness_memory_limit_mb - 512))}"
    echo "Local model in-process memory budget: ${local_model_memory_limit_mb}MB"
    local test_profile_dir
    test_profile_dir="${HARNESS_TEST_PROFILE_DIR:-$(pwd)/.build-tests/harness-test-profile}"
    mkdir -p "$test_profile_dir"
    echo "Harness test profile dir: $test_profile_dir"
    local online_harness_marker="$test_profile_dir/online-harness-enabled"
    if [ -n "$OSX_IDE_RUN_ONLINE_HARNESS" ]; then
        : > "$online_harness_marker"
    else
        rm -f "$online_harness_marker"
    fi
    local prompts_root_default
    prompts_root_default="$(pwd)/Prompts"
    local resolved_prompts_root=""
    
    # Build environment variables to pass to test runner
    # Using TEST_RUNNER_ENV_ prefix to pass env vars through xcodebuild to the test process
    local env_args=()
    local runtime_env_args=("OSX_IDE_PROMPTS_ROOT=$resolved_prompts_root" "OSXIDE_TEST_PROFILE_DIR=$test_profile_dir" "TEST_RUNNER_ENV_OSXIDE_TEST_PROFILE_DIR=$test_profile_dir" "OSXIDE_LOCAL_MODEL_MAX_RSS_MB=$local_model_memory_limit_mb")
    env_args+=("TEST_RUNNER_ENV_OSXIDE_LOCAL_MODEL_MAX_RSS_MB=$local_model_memory_limit_mb")
    if [ -n "$OSXIDE_ENABLE_PRODUCTION_PARITY_HARNESS" ]; then
        env_args+=("TEST_RUNNER_ENV_OSXIDE_ENABLE_PRODUCTION_PARITY_HARNESS=$OSXIDE_ENABLE_PRODUCTION_PARITY_HARNESS")
        echo "Production parity harness enabled"
    fi
    if [ -n "$HARNESS_MODEL_ID" ]; then
        env_args+=("TEST_RUNNER_ENV_HARNESS_MODEL_ID=$HARNESS_MODEL_ID")
        runtime_env_args+=("HARNESS_MODEL_ID=$HARNESS_MODEL_ID" "TEST_RUNNER_ENV_HARNESS_MODEL_ID=$HARNESS_MODEL_ID")
        echo "Using model: $HARNESS_MODEL_ID"
    fi
    if [ -n "$HARNESS_USE_OPENROUTER" ]; then
        env_args+=("TEST_RUNNER_ENV_HARNESS_USE_OPENROUTER=$HARNESS_USE_OPENROUTER")
        echo "Using OpenRouter: $HARNESS_USE_OPENROUTER"
    fi
    env_args+=("TEST_RUNNER_ENV_OSXIDE_TEST_PROFILE_DIR=$test_profile_dir")
    if [ -n "$OSX_IDE_RUN_ONLINE_HARNESS" ]; then
        env_args+=("TEST_RUNNER_ENV_OSX_IDE_RUN_ONLINE_HARNESS=$OSX_IDE_RUN_ONLINE_HARNESS")
        runtime_env_args+=("OSX_IDE_RUN_ONLINE_HARNESS=$OSX_IDE_RUN_ONLINE_HARNESS")
        echo "Online harness runtime enabled"
    fi
    if [ -n "$OSX_IDE_PROMPTS_ROOT" ]; then
        env_args+=("TEST_RUNNER_ENV_OSX_IDE_PROMPTS_ROOT=$OSX_IDE_PROMPTS_ROOT")
        resolved_prompts_root="$OSX_IDE_PROMPTS_ROOT"
        echo "Using prompt root from OSX_IDE_PROMPTS_ROOT: $OSX_IDE_PROMPTS_ROOT"
    elif [ -d "$prompts_root_default" ]; then
        env_args+=("TEST_RUNNER_ENV_OSX_IDE_PROMPTS_ROOT=$prompts_root_default")
        resolved_prompts_root="$prompts_root_default"
        echo "Using prompt root: $prompts_root_default"
    fi
    
    if [ -n "$suite" ]; then
        echo "Filtering by suite: $suite"
        # Do not change this to YES for online/provider-backed harnesses.
        # Parallel test execution floods the provider, triggers 429s, and risks account bans.
        run_with_memory_guard "$harness_memory_limit_gb" \
            env "${runtime_env_args[@]}" xcodebuild -project "$PROJECT_NAME.xcodeproj" \
                  -scheme "$SCHEME" \
                  -configuration Debug \
                  -derivedDataPath "$DERIVED_DATA_PATH_TEST" \
                  -destination 'platform=macOS' \
                  -parallel-testing-enabled NO \
                  ENABLE_PREVIEWS=NO \
                  SWIFT_ENABLE_EXPLICIT_MODULES="$explicit_modules" \
                  "${env_args[@]}" \
                  test -only-testing:osx-ideHarnessTests/"$suite" -skip-testing:osx-ideUITests -skip-testing:osx-ideTests
    else
        local skip_online_args=()
        if [ -z "$OSX_IDE_RUN_ONLINE_HARNESS" ]; then
            skip_online_args+=("-skip-testing:osx-ideHarnessTests/AgenticHarnessTests")
            skip_online_args+=("-skip-testing:osx-ideHarnessTests/RealServiceToolLoopTests")
            skip_online_args+=("-skip-testing:osx-ideHarnessTests/EdgeCaseScenariosTests")
        fi
        # Do not change this to YES for online/provider-backed harnesses.
        # Parallel test execution floods the provider, triggers 429s, and risks account bans.
        run_with_memory_guard "$harness_memory_limit_gb" \
            env "${runtime_env_args[@]}" xcodebuild -project "$PROJECT_NAME.xcodeproj" \
                  -scheme "$SCHEME" \
                  -configuration Debug \
                  -derivedDataPath "$DERIVED_DATA_PATH_TEST" \
                  -destination 'platform=macOS' \
                  -parallel-testing-enabled NO \
                  ENABLE_PREVIEWS=NO \
                  SWIFT_ENABLE_EXPLICIT_MODULES="$explicit_modules" \
                  "${env_args[@]}" \
                  "${skip_online_args[@]}" \
                  test \
                  -only-testing:osx-ideHarnessTests \
                  -skip-testing:osx-ideUITests \
                  -skip-testing:osx-ideTests
    fi
}

run_harness_online() {
    local suite=$1
    if [ -n "$suite" ]; then
        OSX_IDE_RUN_ONLINE_HARNESS=1 run_harness "$suite"
    else
        echo "Running online harness suites..."
        OSX_IDE_RUN_ONLINE_HARNESS=1 run_harness "AgenticHarnessTests"
        OSX_IDE_RUN_ONLINE_HARNESS=1 run_harness "RealServiceToolLoopTests"
        OSX_IDE_RUN_ONLINE_HARNESS=1 run_harness "TelemetryValidationTests"
        OSX_IDE_RUN_ONLINE_HARNESS=1 run_harness "EdgeCaseScenariosTests"
        OSX_IDE_RUN_ONLINE_HARNESS=1 run_harness "ToolLoopDropoutHarnessTests"
        OSX_IDE_RUN_ONLINE_HARNESS=1 run_harness "OrchestrationSnapshotHarnessTests"
        OSX_IDE_RUN_ONLINE_HARNESS=1 run_harness "IndexScopeHarnessTests"
    fi
}

run_harness_offline() {
    local suite=$1
    if [ -n "$suite" ]; then
        run_harness "$suite"
    else
        echo "Running offline harness suites..."
        run_harness "OfflineModeHarnessTests"
    fi
}

run_benchmark_offline() {
    local mode=$1
    case "$mode" in
        ""|"greeting")
            echo "Running offline greeting benchmark..."
            run_harness "OfflineModeHarnessTests/testOfflineHarnessInferenceBenchmarkSimpleGreeting"
            ;;
        "sweep")
            echo "Running offline parameter sweep benchmark..."
            run_harness "OfflineModeHarnessTests/testOfflineHarnessInferenceParameterSweepLongPrompt"
            ;;
        *)
            echo "Unknown offline benchmark mode: $mode"
            echo "Supported modes: greeting, sweep"
            return 1
            ;;
    esac
}

run_e2e() {
    local suite=$1
    local explicit_modules="${SWIFT_ENABLE_EXPLICIT_MODULES:-NO}"
    echo "Running UI tests..."
    prepare_derived_data_packages "$DERIVED_DATA_PATH_TEST"
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
                   SWIFT_ENABLE_EXPLICIT_MODULES="$explicit_modules" \
                   test -only-testing:osx-ideUITests/"$suite" -skip-testing:osx-ideTests
    else
        xcodebuild -project "$PROJECT_NAME.xcodeproj" \
                   -scheme "$SCHEME" \
                   -configuration Debug \
                   -derivedDataPath "$DERIVED_DATA_PATH_TEST" \
                   -destination 'platform=macOS' \
                   ENABLE_PREVIEWS=NO \
                   SWIFT_ENABLE_EXPLICIT_MODULES="$explicit_modules" \
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
    harness-online)
        run_harness_online "$2"
        ;;
    harness-offline)
        run_harness_offline "$2"
        ;;
    benchmark-offline)
        run_benchmark_offline "$2"
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
