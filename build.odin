package main

import "core:fmt"
import "core:os"

LANGUAGE_TOOLS_COLLECTION :: "-collection:language_tools=./language_tools/src"

main :: proc() {
    if len(os.args) < 2 {
        print_usage()
        os.exit(1)
    }

    switch os.args[1] {
    case "check":
        check_packages()

    case "test":
        run_tests()

    case "fmt":
        format()

    case "all":
        format()
        check_packages()
        run_tests()

    case:
        print_usage()
        os.exit(1)
    }
}

print_usage :: proc() {
    fmt.println("Usage: odin run build.odin -file -- <command>")
    fmt.println("")
    fmt.println("Commands:")
    fmt.println("  fmt      Format source files")
    fmt.println("  check    Check project packages")
    fmt.println("  test     Run tests")
    fmt.println("  all      Format files, check packages, and run tests")
}

format :: proc() {
    fmt.println("Formatting source files...")

    run_command([]string{"odinfmt", "-w", "src"})

    fmt.println("Formatting complete.")
}

check_packages :: proc() {
    fmt.println("Checking project packages...")

    run_command([]string{
        "odin",
        "check",
        "src",
        "-no-entry-point",
        LANGUAGE_TOOLS_COLLECTION,
    })

    fmt.println("Package checks passed.")
}

run_tests :: proc() {
    fmt.println("Running tests...")

    run_command([]string{
        "odin",
        "test",
        "src",
        LANGUAGE_TOOLS_COLLECTION,
    })

    fmt.println("Tests passed.")
}

run_command :: proc(command: []string) {
    process, err := os.process_start(
        os.Process_Desc {
            command = command,
            stdin = os.stdin,
            stdout = os.stdout,
            stderr = os.stderr,
        },
    )

    if err != nil {
        fmt.println("Failed to start command:", command)
        os.exit(1)
    }

    state, wait_err := os.process_wait(process)

    if wait_err != nil {
        fmt.println("Failed waiting for command:", command)
        os.exit(1)
    }

    if !state.success || state.exit_code != 0 {
        fmt.println("Command failed:", command)
        os.exit(1)
    }
}
