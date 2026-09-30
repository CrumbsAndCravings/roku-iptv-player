#!/bin/sh
# Runs the off-device BrightScript tests. Exits non-zero if any check fails.
BRS=node_modules/.bin/brs
C=src/components

run() {
  out=$("$BRS" --root tests "$@" 2>&1)
  echo "$out"
  echo "$out" | grep -q "^ALL PASSED" || status=1
}

status=0
run $C/common/Utils.brs $C/common/Tracks.brs tests/utils_test.brs
run $C/common/Utils.brs tests/fake_registry.brs $C/common/Progress.brs $C/tasks/XtreamParse.brs tests/parse_test.brs
exit $status
