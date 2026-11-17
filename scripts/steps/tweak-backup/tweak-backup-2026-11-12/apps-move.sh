#!/bin/bash
for a in Messages FaceTime; do
  src="/Users/user/removed-system-apps/$a.app"; dst="/Applications/$a.app"
  [ -d "$src" ] && [ ! -e "$dst" ] && mv "$src" "$dst" && echo "moved $a"
done
