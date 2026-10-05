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
run $C/common/Utils.brs $C/common/Tracks.brs $C/common/Playback.brs $C/common/Subtitles.brs $C/common/Categories.brs $C/common/Helper.brs $C/common/Motion.brs tests/utils_test.brs
run $C/common/Utils.brs tests/fake_registry.brs $C/common/Progress.brs $C/common/Categories.brs $C/common/Tracks.brs $C/common/Helper.brs $C/tasks/XtreamParse.brs $C/tasks/SearchIndex.brs tests/parse_test.brs
out=$(node tests/sync_test.mjs 2>&1)
echo "$out"
echo "$out" | grep -q "^ALL PASSED" || status=1
exit $status
