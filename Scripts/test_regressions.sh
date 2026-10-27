#!/usr/bin/env bash
# Run focused tests with Command Line Tools; no XCTest/Xcode dependency.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BUILD=$(mktemp -d /tmp/rightclick-regression-build.XXXXXX)
trap 'rm -rf "$TEST_BUILD"' EXIT
: > "$TEST_BUILD/empty.modulemap"
cat > "$TEST_BUILD/overlay.yaml" <<EOF
{"version":0,"roots":[{"type":"file","name":"/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap","external-contents":"$TEST_BUILD/empty.modulemap"}]}
EOF
SOURCES=()
while IFS= read -r source; do SOURCES+=("$source"); done < <(find Sources/RightClickAssistant/Core -name '*.swift' -type f | sort)
swiftc -parse-as-library -sdk "$(xcrun --show-sdk-path)" -vfsoverlay "$TEST_BUILD/overlay.yaml" "${SOURCES[@]}" Tests/Standalone/Regression.swift -o "$TEST_BUILD/regression"
codesign --force --sign - --identifier local.rightclick.regression "$TEST_BUILD/regression"
cp "$TEST_BUILD/regression" "$TEST_BUILD/untrusted-client"
codesign --force --sign - --identifier local.rightclick.impostor "$TEST_BUILD/untrusted-client"
TEST_OUTPUT=$(mktemp -d /tmp/rightclick-regression-output.XXXXXX)
"$TEST_BUILD/regression" "$TEST_OUTPUT" "$(pwd)/Resources/Templates"
