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
run $C/common/Utils.brs tests/fake_registry.brs $C/common/Progress.brs $C/common/Categories.brs $C/common/Tracks.brs $C/common/Helper.brs $C/common/Taste.brs $C/common/MyList.brs $C/tasks/XtreamParse.brs $C/tasks/SearchIndex.brs tests/parse_test.brs
# Objects a Roku only allows on the main thread and in tasks crash the app when a screen
# creates one (0.5.7 to 0.5.9 froze on roFileSystem). Screens, items, the scene, the
# intro and the shared files they include must not create them.
render=$(grep -n -i -E 'CreateObject\("(roFileSystem|roUrlTransfer|roStreamSocket|roDataGramSocket|roChannelStore|roAudioPlayer)"' $C/MainScene.brs $C/Intro.brs $C/screens/*.brs $C/items/*.brs $C/common/*.brs)
if [ -n "$render" ]; then
  echo "FAIL task-only objects made on the render thread:"
  echo "$render"
  status=1
else
  echo "ALL PASSED (render thread uses no task-only objects)"
fi
out=$(node tests/sync_test.mjs 2>&1)
echo "$out"
echo "$out" | grep -q "^ALL PASSED" || status=1
exit $status
