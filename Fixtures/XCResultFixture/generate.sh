#!/bin/bash
set -euo pipefail

fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$fixture_dir/../.." && pwd)"

if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [output-directory]"
    echo "Default: <repo>/output/xcresult-fixtures"
    echo "Override the simulator with FIXTURE_DESTINATION (an xcodebuild destination)."
    exit 0
fi
if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [output-directory]" >&2
    exit 2
fi

output_dir="${1:-$repo_dir/output/xcresult-fixtures}"
destination="${FIXTURE_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

# Preserve existing fixtures, including bundles from interrupted or unsuccessful runs.
for plan in Baseline Mixed; do
    if [[ -e "$output_dir/$plan.xcresult" || -e "$output_dir/$plan.log" ]]; then
        echo "Output already exists for $plan. Choose a fresh output directory." >&2
        exit 2
    fi
done

for plan in Baseline Mixed; do
    echo "Generating $plan.xcresult on $destination (full log: $output_dir/$plan.log)"
    test_command=(xcodebuild test
        -project "$fixture_dir/XCResultFixture.xcodeproj"
        -scheme XCResultFixture
        -testPlan "$plan"
        -destination "$destination"
        -derivedDataPath "$output_dir/DerivedData"
        -resultBundlePath "$output_dir/$plan.xcresult"
        -parallel-testing-enabled NO
        -collect-test-diagnostics never)
    if [[ "$plan" == Mixed ]]; then
        test_command+=(-retry-tests-on-failure -test-iterations 2 -test-repetition-relaunch-enabled NO)
    fi
    status=0
    "${test_command[@]}" > "$output_dir/$plan.log" 2>&1 || status=$?

    if [[ ( "$plan" == Baseline && "$status" != 0 ) || ( "$plan" == Mixed && "$status" != 65 ) ]]; then
        echo "Unexpected xcodebuild status $status for $plan. See $output_dir/$plan.log" >&2
        tail -n 35 "$output_dir/$plan.log" >&2
        exit 1
    fi

    # Exit 65 can also mean a broken build or a simulator problem. Validate the actual
    # test identities, outcomes, retries, and payloads before accepting a mixed run.
    python3 "$fixture_dir/verify.py" "$output_dir/$plan.xcresult" "$plan"
done

echo "Verified fixture bundles: $output_dir/Baseline.xcresult and $output_dir/Mixed.xcresult"
