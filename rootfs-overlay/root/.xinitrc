#!/bin/sh
# .xinitrc — سطح مكتب بسيط: خلفية داكنة + طرفيتان + fluxbox

xsetroot -solid '#14212e' 2>/dev/null
xset -dpms 2>/dev/null
xset s off 2>/dev/null

xterm -fa Monospace -fs 10 -bg '#0d1117' -fg '#d6deeb' \
      -geometry 96x28+40+40 -title "naml: shell" &
xterm -fa Monospace -fs 10 -bg '#0d1117' -fg '#d6deeb' \
      -geometry 96x28+130+130 -title "naml: shell" &

exec fluxbox
