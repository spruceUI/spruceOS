#!/bin/sh
# changeCmd for the in-game menu entry toggles: rewrite RetroArch/igm_items.json.
# A hand-edited order survives: entries turned off are dropped, entries turned
# on go in after the nearest entry that comes before them in the default order.
# Resume is always first and Exit always last.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ITEMS_FILE="${IGM_ITEMS_FILE:-/mnt/SDCARD/RetroArch/igm_items.json}"
SPRUCE_CFG="${SPRUCE_CFG:-/mnt/SDCARD/Saves/spruce/spruce-config.json}"

igm_items_write() {
    _cur='null'
    [ -f "$ITEMS_FILE" ] && _cur="$(jq -c '.items // null' "$ITEMS_FILE" 2>/dev/null)"
    [ -n "$_cur" ] || _cur='null'

    jq -n --argjson cur "$_cur" --slurpfile cfg "$SPRUCE_CFG" '
        [["resume","igmResume"], ["save","igmSave"], ["load","igmLoad"],
         ["ff_speed","igmFfSpeed"], ["reset","igmReset"],
         ["retroarch","igmRetroarch"], ["exit","igmExit"],
         ["disc","igmDisc"], ["screenshot","igmScreenshot"],
         ["undo_save","igmUndoSave"], ["undo_load","igmUndoLoad"],
         ["show_fps","igmShowFps"], ["mute","igmMute"],
         ["rewind","igmRewind"], ["shader","igmShader"]] as $map
        | [$map[][0]] as $canon
        | ($cfg[0].menuOptions."In-Game Menu Settings" // {}) as $opts
        | [$map[] | select(($opts[.[1]].selected // "True") == "True") | .[0]] as $on
        | (if ($cur | type) == "array" and ($cur | length) > 0 then $cur
           else ["resume","save","load","reset","retroarch","exit"] end) as $base
        | def has($a; $x): any($a[]; . == $x);
          def pos($x): $canon | to_entries | map(select(.value == $x)) | .[0].key;
          [$base[] | select(has($on; .))] as $kept
        | reduce ($on[] | select(has($kept; .) | not)) as $add ($kept;
            . as $r
            | ([range(0; $r | length) | select(pos($r[.]) < pos($add))] | last) as $p
            | if $p == null then [$add] + $r else $r[:$p + 1] + [$add] + $r[$p + 1:] end)
        | ([.[] | select(. == "resume")] + [.[] | select(. != "resume" and . != "exit")]
           + [.[] | select(. == "exit")])
        | {items: (if length == 0 then ["resume"] else . end)}
    ' > "$ITEMS_FILE.tmp" && mv -f "$ITEMS_FILE.tmp" "$ITEMS_FILE"
}

if [ "$1" = "--now" ]; then
    igm_items_write
else
    ( igm_items_write ) </dev/null >/dev/null 2>&1 &
fi
