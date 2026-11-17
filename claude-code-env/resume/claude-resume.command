#!/bin/zsh
LOG=$HOME/Library/Logs/claude-resume.log
NP=$HOME/.claude/resume/next-prompt.txt
say() { echo "$(date '+%F %T') $*" >> "$LOG"; }
if pgrep -x claude >/dev/null; then say "이미 claude 실행 중 → 건너뜀"; exit 0; fi
i=0
until /usr/bin/curl -s -o /dev/null --max-time 4 https://api.anthropic.com || [ $i -ge 18 ]; do sleep 5; i=$((i+1)); done
cd "$HOME" || exit 1
/usr/bin/python3 - <<'PY' >> "$LOG" 2>&1
import json, os
p = os.path.expanduser('~/.claude.json')
try:
    d = json.load(open(p))
    pr = d.setdefault('projects', {}).setdefault(os.path.expanduser('~'), {})
    if not pr.get('hasTrustDialogAccepted'):
        pr['hasTrustDialogAccepted'] = True
        tmp = p + '.resume-tmp'
        json.dump(d, open(tmp, 'w'), indent=2); os.replace(tmp, p)
        print('신뢰 표시 켬')
except Exception as e:
    print('신뢰 표시 실패:', e)
PY
for sid in "$HOME"/.claude/resume/extra/*.sid(N); do
    id=$(tr -d " \n" < "$sid"); msg="${sid%.sid}.txt"; one="${sid%.sid}.command"
    { echo "#!/bin/zsh"; echo "cd \"$HOME\""; printf "exec \"%s\" --dangerously-skip-permissions --resume %q %q\n" "$HOME/.local/bin/claude" "$id" "$(cat "$msg" 2>/dev/null)"; } > "$one"; chmod +x "$one"
    mv -f "$sid" "$sid.used"; [ -f "$msg" ] && mv -f "$msg" "$msg.used"
    open -a Terminal "$one" && say "추가 세션 재개 $id"
done
NS=$HOME/.claude/resume/next-session.txt
if [ -s "$NP" ]; then
    P=$(cat "$NP"); mv -f "$NP" "$NP.used"
    if [ -s "$NS" ]; then
        S=$(tr -d " \n" < "$NS"); mv -f "$NS" "$NS.used"
        say "claude --resume $S 시작 (네트워크 대기 $((i*5))초, 첫 메시지 있음)"
        exec "$HOME/.local/bin/claude" --dangerously-skip-permissions --resume "$S" "$P"
    fi
    say "claude --continue 시작 (네트워크 대기 $((i*5))초, 첫 메시지 있음)"
    exec "$HOME/.local/bin/claude" --dangerously-skip-permissions --continue "$P"
fi
P="[자동 재개] 방금 재부팅됨. 직전 작업이 재부팅을 기다리던 중이었다면 메모리·노트의 '재부팅 뒤' 순서대로 확인부터 이어서 진행해. 기다리던 작업이 없으면 상태만 짧게 보고해."
say "claude --continue 시작 (네트워크 대기 $((i*5))초, 기본 재개 메시지)"
exec "$HOME/.local/bin/claude" --dangerously-skip-permissions --continue "$P"
