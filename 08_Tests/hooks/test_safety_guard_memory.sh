#!/usr/bin/env bash
#==============================================================================
# test_safety_guard_memory.sh — P0-M1 Rule 3: 무인 레인 기억 쓰기 차단 (2026-09-24)
#
# 재는 것 (양방향 + 돌연변이):
#   A. 무인 표식(QVEST_UNATTENDED_LANE=1) + 기억 경로 Write/Edit → block (경로 표기 4종 · .. 우회)
#   B. 무인 표식 + Bash 우회 — 직접 · 글롭 · 문자열 결합(따옴표·변수·백슬래시) · find · 파이썬/R/PS 한 줄 → block
#   C. 무인 표식 + 정당 경로(memory_inbox · 저장소 · 상대 글롭 · 02_Infrastructure/memory) → pass (과잉 차단 없음)
#   D. 표식 없음(대화형) → 기억 경로 쓰기도 pass (Q 세션의 기억 쓰기는 정상 경로)
#   E. Read/Glob 입력 → 두 상태 모두 '{}' (이 훅의 범위 밖 도구에 부작용 없음)
#   F. 기존 Rule 1/2(05_Production · 01_Literature · normalizePath) 회귀 — 두 상태 모두 불변
#   G. fail-closed — 파싱 불능 + 기억 흔적: 무인이면 block · 평시면 '{}'
#   H. 돌연변이 — 규칙을 하나씩 꺼 낸 사본에서 해당 사례가 뚫린다(판별력)
#   I. 등록 — settings.json 에 safety_guard.sh 가 PreToolUse Write|Edit · Bash 로 걸려 있다(읽기만)
#   J. (R3R 2026-09-25 · 결정 R3R-D2-MULTILINE) 여러 줄 명령 — bash 의미대로. (한 줄, 여러 줄·줄 이음·CRLF·CR) 쌍.
#      대칭 쌍: Rule 3(글롭·cd·find 가 둘째 줄) · Rule 2(05_Production 쓰기가 줄 이음으로 갈림 — J7 · 낱말째 갈림 J10
#      `05_Produ\<개행>ction`) · CR 단독(J8)·normalizePath(J9) · 통과 쌍(K — inbox·무해·표식 없음)
#      비대칭 쌍 J6(D2): 개행 = 명령 경계 — `cp a b ; echo 05_Production` 한 줄 판은 종전대로 block,
#      `cp a b<개행>echo 05_Production` 여러 줄 판은 두 명령이라 pass(Rule 2 가 개행을 건너 잇지 않는다)
#      J-red: 수리 전 훅(QVEST_SG_BASE_HOOK)은 여러 줄 판이 한 줄 판과 다르게 새는 것을 실증
#      H: oneline_off(정규화 전부) · nl_semi_off(Rule 3 개행→' ; ') · linecont_off(줄 이음 제거) 는 새고,
#         nlbound_off(Rule 2 가 개행을 ' ; ' 로 잇는 초판)는 J6 여러 줄 판을 막는다 — 네 방향 판별력
# 격리: 훅과 _shared_parse.sh 를 임시 루트로 복사해 CLAUDE_PROJECT_DIR·QM_ROOT 를 그 루트로 두고
#   QVEST_EVENT_LEDGER=0 — 운영 events.jsonl 에 한 줄도 쓰지 않는다.
# 대상 훅 교체: QVEST_SG_HOOK=<경로> (스테이징 판 검증용)
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
SRC_HOOK="${QVEST_SG_HOOK:-$ROOT/02_Infrastructure/hooks/safety_guard.sh}"
SRC_PARSE="${QVEST_SG_PARSE:-$ROOT/02_Infrastructure/hooks/_shared_parse.sh}"
SETTINGS="${QVEST_SG_SETTINGS:-$ROOT/.claude/settings.json}"
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"; [ -x "$PY" ] || PY=python
P=0; F=0
ok(){ P=$((P+1)); printf '  OK    %s\n' "$1"; }
ng(){ F=$((F+1)); printf '  FAIL  %s — %s\n' "$1" "${2:-}"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SBX="$T/root"; mkdir -p "$SBX/02_Infrastructure/hooks" "$T/cases" "$T/mut"
cp "$SRC_HOOK" "$SBX/02_Infrastructure/hooks/safety_guard.sh"
cp "$SRC_PARSE" "$SBX/02_Infrastructure/hooks/_shared_parse.sh"
HOOK="$SBX/02_Infrastructure/hooks/safety_guard.sh"

fire(){ # $1=env(1|0) $2=json 파일 [$3=훅 경로]
  local h="${3:-$HOOK}"
  if [ "$1" = "1" ]; then
    env QVEST_UNATTENDED_LANE=1 CLAUDE_PROJECT_DIR="$SBX" QM_ROOT="$SBX" QVEST_EVENT_LEDGER=0 bash "$h" < "$2" 2>/dev/null
  else
    env -u QVEST_UNATTENDED_LANE CLAUDE_PROJECT_DIR="$SBX" QM_ROOT="$SBX" QVEST_EVENT_LEDGER=0 bash "$h" < "$2" 2>/dev/null
  fi
}
verdict(){ case "$1" in *'"decision":"block"'*) echo block ;; '{}') echo pass ;; *) echo "odd:$1" ;; esac; }

# ── 사례 생성 — JSON 은 파이썬이 만든다(셸 이스케이프가 백슬래시를 먹는 사고 방지) ─────────
"$PY" - "$T/cases" <<'PYEOF'
import io, json, os, sys
out = sys.argv[1]
home = os.path.expanduser('~')                       # C:\Users\<user>
hw = home                                            # 윈도 표기
hf = home.replace('\\', '/')                         # C:/Users/<user>
hg = '/' + hf[0].lower() + hf[2:] if hf[1:2] == ':' else hf   # /c/Users/<user>
slug = 'C--Users-99922-OneDrive-Quant-Module-Moltbot'
repo = 'C:\\Users\\99922\\OneDrive\\Quant_Module_Moltbot'
memw = hw + '\\.claude\\projects\\' + slug + '\\memory'
rows = []
def W(cid, fp, content='x'):
    return cid, {'tool_name': 'Write', 'tool_input': {'file_path': fp, 'content': content}}
def E(cid, fp):
    return cid, {'tool_name': 'Edit', 'tool_input': {'file_path': fp, 'old_string': 'a', 'new_string': 'b'}}
def B(cid, cmd):
    return cid, {'tool_name': 'Bash', 'tool_input': {'command': cmd, 'description': 't'}}
def R(cid, fp):
    return cid, {'tool_name': 'Read', 'tool_input': {'file_path': fp}}
def G(cid, pat, path):
    return cid, {'tool_name': 'Glob', 'tool_input': {'pattern': pat, 'path': path}}
cases = {
  # A. 기억 경로 Write/Edit (무인 → block)
  'A1': W('A1', memw + '\\feedback-x-20260924.md'),
  'A2': W('A2', hf + '/.claude/projects/' + slug + '/memory/project-y.md'),
  'A3': W('A3', hg + '/.claude/projects/' + slug + '/memory/MEMORY.md'),
  'A4': E('A4', memw + '\\MEMORY.md'),
  'A5': W('A5', repo.replace('\\', '/') + '/../../.claude/projects/' + slug + '/memory/z.md'),
  'A6': W('A6', hf + '/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot--claude-worktrees-x/memory/w.md'),
  # B. Bash 우회 (무인 → block)
  'B1': B('B1', 'echo "- [x](x.md)" >> ~/.claude/projects/' + slug + '/memory/MEMORY.md'),
  'B2': B('B2', 'cp card.md ~/.c*/p*/*/m*/'),
  'B3': B('B3', 'cp card.md ' + hg + '/.cl*/proj*/*/mem*/card.md'),
  'B4': B('B4', 'echo x > "' + hg + '/.cla""ude/projects/C--x/mem""ory/a.md"'),
  'B5': B('B5', 'A=' + hg + '/.cl; B=aude; echo x > "${A}${B}/projects/C--x/memory/a.md"'),
  'B6': B('B6', 'echo x > ~/.cla\\ude/pro\\jects/x/mem\\ory/a.md'),
  'B7': B('B7', "find ~ -name 'MEMORY.md' -exec sed -i 's/a/b/' {} +"),
  'B8': B('B8', "find $HOME -type f -name '*.md' -newer /tmp/x -exec touch {} +"),
  'B9': B('B9', "find / -maxdepth 6 -name '*.md' -delete"),
  'B10': B('B10', 'find ' + hg + "/.claude -name '*.md' -exec cp /tmp/n.md {} \\;"),
  'B11': B('B11', "python -c \"open(r'" + memw + "\\a.md','w').write('x')\""),
  'B12': B('B12', 'powershell -c "Set-Content $env:USERPROFILE\\.claude\\projects\\X\\memory\\a.md x"'),
  'B13': B('B13', 'Rscript -e \'writeLines("x", file.path(Sys.getenv("HOME"), ".claude", "projects", "C--X", "memory", "a.md"))\''),
  'B14': B('B14', 'cd ~ && cp n.md .c*/p*/*/m*/'),
  'B15': B('B15', 'cd "$HOME/.claude" && touch probe.txt'),
  # C. 정당 경로 (무인 → pass)
  'C1': W('C1', repo + '\\06_Registry\\memory_inbox\\20260924_replication_arxiv-note.md'),
  'C2': W('C2', repo + '\\04_Research\\strategies\\STR_X\\engine.R'),
  'C3': B('C3', 'ls *.R'),
  'C4': B('C4', "find . -name '*.R' -newer x"),
  'C5': B('C5', 'Rscript 02_Infrastructure/memory/lcode_corpus_rebuild.R'),
  'C6': B('C6', 'cat .claude/rules/pit.md'),
  'C7': B('C7', 'echo "x" > 06_Registry/memory_inbox/20260924_rp_note.md'),
  'C8': B('C8', 'git log --oneline | head -5'),
  'C9': B('C9', 'rm -rf /tmp/qm_x/*'),
  'C10': B('C10', 'ls ' + repo.replace('\\', '/') + '/04_Research/*'),
  'C11': B('C11', 'grep -rn "memory_inbox" 06_Registry'),
  'C12': W('C12', repo + '\\.claude\\skills\\cleaner\\SKILL.md'),
  # E. 범위 밖 도구
  'E1': R('E1', memw + '\\MEMORY.md'),
  'E2': G('E2', '**/*.md', memw),
  # F. 기존 규칙 회귀 (두 상태 모두 block)
  'F1': W('F1', repo + '\\05_Production\\x.R'),
  'F2': B('F2', 'cp x.R 05_Production/'),
  'F3': B('F3', 'Rscript -e "normalizePath(\'.\')"'),
  'F4': W('F4', repo + '\\01_Literature\\a.pdf'),
  'F5': W('F5', repo + '\\01_Literature\\Korea_Research\\note.md'),
  # J. (R3R) 여러 줄 = 한 줄 — s = 한 줄 판 · m = 여러 줄 판(개행·CRLF·CR·줄 이음). 같은 판정이어야 한다
  'J1s': B('J1s', 'echo hi; cp n.md ~/.c*/p*/*/m*/'),
  'J1m': B('J1m', 'echo hi\ncp n.md ~/.c*/p*/*/m*/'),
  'J2s': B('J2s', 'cd ~ ; cp n.md .c*/p*/*/m*/'),
  'J2m': B('J2m', 'cd ~\ncp n.md .c*/p*/*/m*/'),
  'J3s': B('J3s', 'true; cd "$HOME/.claude" && touch probe.txt'),
  'J3m': B('J3m', 'true\ncd "$HOME/.claude" && touch probe.txt'),
  'J4s': B('J4s', "true ; find ~ -name 'x.md' -delete"),
  'J4m': B('J4m', "true\r\nfind ~ -name 'x.md' -delete"),
  'J5s': B('J5s', 'cp n.md ~/.c*/p*/*/m*/'),
  'J5m': B('J5m', 'cp n.md \\\n~/.c*/p*/*/m*/'),
  'J6s': B('J6s', 'cp x.R /tmp/a ; echo 05_Production'),
  'J6m': B('J6m', 'cp x.R /tmp/a\necho 05_Production'),
  'J7s': B('J7s', 'cp x.R   05_Production/'),
  'J7m': B('J7m', 'cp x.R \\\n  05_Production/'),
  'J8s': B('J8s', 'cp x.R /tmp/a ; echo 05_Production'),
  'J8m': B('J8m', 'cp x.R /tmp/a\recho 05_Production'),
  'J9s': B('J9s', "x=1 ; Rscript -e 'normalizePath(\".\")'"),
  'J9m': B('J9m', "x=1\nRscript -e 'normalizePath(\".\")'"),
  'K1s': B('K1s', 'cd /tmp ; ls *.R'),
  'K1m': B('K1m', 'cd /tmp\nls *.R'),
  'K2s': B('K2s', 'ls 05_Production ; echo done'),
  'K2m': B('K2m', 'ls 05_Production\necho done'),
  'K3s': B('K3s', "cat > 06_Registry/memory_inbox/20260925_rf_note.md <<'EOF' ; - 교훈 ; EOF"),
  'K3m': B('K3m', "cat > 06_Registry/memory_inbox/20260925_rf_note.md <<'EOF'\n- 교훈\nEOF"),
  'K4s': B('K4s', 'echo aecho b'),
  'K4m': B('K4m', 'echo a\\\necho b'),
  # (D2) 보호 낱말이 줄 이음으로 갈린 쓰기 — bash 는 줄 이음을 지워 한 낱말로 잇는다(R3R 검증 MS03 생존 지적)
  'J10s': B('J10s', 'cp x.R 05_Production/'),
  'J10m': B('J10m', 'cp x.R 05_Produ\\\nction/'),
}
man = []
for cid, (c, obj) in cases.items():
    io.open(os.path.join(out, cid + '.json'), 'w', encoding='utf-8', newline='').write(json.dumps(obj, ensure_ascii=False))
    man.append(cid)
# G. fail-closed — 깨진 JSON (의도적으로 무효)
io.open(os.path.join(out, 'G1.json'), 'w', encoding='utf-8', newline='').write('{"tool_name":"Write","tool_input":{"file_path":"C:\\Users\\u\\.claude\\projects\\X\\memory\\a.md"')
io.open(os.path.join(out, 'G2.json'), 'w', encoding='utf-8', newline='').write('{"tool_name":"Write","tool_input":{"file_path":"C:/x/05_Production/a.R"')
io.open(os.path.join(out, 'G3.json'), 'w', encoding='utf-8', newline='').write('{"tool_name":"Bash","tool_input":{"command":"ls repo/04_Research"')
print(len(man) + 3)
PYEOF

C="$T/cases"
# B16 — 상대 이동(cd ../..)으로 홈에 닿은 뒤 상대 글롭: 훅 cwd($T)에서 홈까지의 상대 경로를 실측해 만든다
REL="$("$PY" -c "import os,sys;print(os.path.relpath(os.path.expanduser('~'), sys.argv[1]).replace(os.sep,'/'))" "$(cygpath -w "$T" 2>/dev/null || echo "$T")" 2>/dev/null | tr -d '\r')"
B16=""
case "$REL" in ..*) B16=B16
  "$PY" -c "import io,json,sys;io.open(sys.argv[1],'w',encoding='utf-8').write(json.dumps({'tool_name':'Bash','tool_input':{'command':'cd '+sys.argv[2]+' && cp n.md .c*/p*/*/m*/'}}))" "$(cygpath -w "$C/B16.json" 2>/dev/null || echo "$C/B16.json")" "$REL" ;;
esac
echo "=== test_safety_guard_memory (훅: $SRC_HOOK) ==="

echo "--- A/B. 무인 표식 + 기억 쓰기 → block ---"
for id in A1 A2 A3 A4 A5 A6 B1 B2 B3 B4 B5 B6 B7 B8 B9 B10 B11 B12 B13 B14 B15 $B16; do
  o="$(cd "$T" && fire 1 "$C/$id.json")"; v="$(verdict "$o")"
  [ "$v" = block ] && ok "$id block ($(printf '%s' "$o" | sed -n 's/.*P0-M1 \([a-z_]*\)\].*/\1/p'))" || ng "$id 무인 기억 쓰기가 통과" "$o"
done
[ -n "$B16" ] || echo "  (B16 생략 — 임시 디렉터리가 홈 아래가 아니다: REL=$REL)"
echo "--- C. 무인 표식 + 정당 경로 → pass(과잉 차단 없음) ---"
for id in C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12; do
  o="$(fire 1 "$C/$id.json")"; v="$(verdict "$o")"
  [ "$v" = pass ] && ok "$id pass" || ng "$id 정당 경로를 막았다" "$o"
done
echo "--- D. 표식 없음 → 기억 경로도 pass ---"
for id in A1 A2 A3 A4 A5 A6 B1 B2 B3 B4 B5 B6 B7 B8 B9 B10 B11 B12 B13 B14 B15 $B16 C1 C3; do
  o="$(cd "$T" && fire 0 "$C/$id.json")"; v="$(verdict "$o")"
  [ "$v" = pass ] && ok "$id 평시 pass" || ng "$id 평시에 발화했다(대화형 세션 오차단)" "$o"
done
echo "--- E. 범위 밖 도구(Read/Glob) — 두 상태 모두 '{}' ---"
for id in E1 E2; do for e in 1 0; do
  o="$(fire $e "$C/$id.json")"
  [ "$o" = '{}' ] && ok "$id env=$e '{}'" || ng "$id env=$e" "$o"
done; done
echo "--- F. 기존 Rule 1/2 회귀 ---"
for id in F1 F2 F3 F4; do for e in 1 0; do
  o="$(fire $e "$C/$id.json")"
  [ "$(verdict "$o")" = block ] && ok "$id env=$e block(기존 규칙)" || ng "$id env=$e 기존 차단이 풀렸다" "$o"
done; done
for e in 1 0; do o="$(fire $e "$C/F5.json")"; [ "$o" = '{}' ] && ok "F5 env=$e Korea_Research 예외 유지" || ng "F5 env=$e" "$o"; done
echo "--- G. fail-closed ---"
o="$(fire 1 "$C/G1.json")"; [ "$(verdict "$o")" = block ] && ok "G1 무인 + 판별불능 + 기억 흔적 → block" || ng "G1" "$o"
o="$(fire 0 "$C/G1.json")"; [ "$o" = '{}' ] && ok "G1' 평시 + 판별불능 + 기억 흔적 → '{}'(종전 거동)" || ng "G1'" "$o"
for e in 1 0; do o="$(fire $e "$C/G2.json")"; [ "$(verdict "$o")" = block ] && ok "G2 env=$e 판별불능 + 05_Production → block(종전)" || ng "G2 env=$e" "$o"; done
for e in 1 0; do o="$(fire $e "$C/G3.json")"; [ "$o" = '{}' ] && ok "G3 env=$e 판별불능 + 무해 → '{}'" || ng "G3 env=$e" "$o"; done

echo "--- J. (R3R·D2) 여러 줄 명령 — bash 의미대로(줄 이음 = 잇는다 · 개행 = 명령 경계) ---"
# 대칭 쌍 기대: J1~J5 = Rule 3(무인 block · 평시 pass) · J7~J10 = Rule 2(두 상태 block) · K1~K4 = 통과(두 상태 pass)
jexp(){ case "$1" in J[1-5]) [ "$2" = 1 ] && echo block || echo pass ;; J[7-9]|J10) echo block ;; K*) echo pass ;; esac; }
for pr in J1 J2 J3 J4 J5 J7 J8 J9 J10 K1 K2 K3 K4; do for e in 1 0; do
  vs="$(verdict "$(cd "$T" && fire $e "$C/${pr}s.json")")"; vm="$(verdict "$(cd "$T" && fire $e "$C/${pr}m.json")")"; want="$(jexp "$pr" "$e")"
  [ "$vs" = "$vm" ] && [ "$vm" = "$want" ] && ok "$pr env=$e 한 줄=$vs · 여러 줄=$vm (기대 $want)" || ng "$pr env=$e 대칭 깨짐" "한 줄=$vs 여러 줄=$vm 기대=$want"
done; done
# J6(D2 비대칭 쌍) — 개행으로 갈린 두 명령: 한 줄 판(' ; ')은 종전 Rule 2 그대로 block · 여러 줄 판은 개행 = 명령 경계라 pass
for e in 1 0; do
  vs="$(verdict "$(cd "$T" && fire $e "$C/J6s.json")")"; vm="$(verdict "$(cd "$T" && fire $e "$C/J6m.json")")"
  [ "$vs" = block ] && [ "$vm" = pass ] && ok "J6 env=$e 한 줄=block · 여러 줄=pass (개행 = 명령 경계 · D2)" || ng "J6 env=$e 개행 경계" "한 줄=$vs 여러 줄=$vm 기대=block/pass"
done
if [ -n "${QVEST_SG_BASE_HOOK:-}" ] && [ -f "$QVEST_SG_BASE_HOOK" ]; then
  bh="$T/basehook/02_Infrastructure/hooks"; mkdir -p "$bh"; cp "$QVEST_SG_BASE_HOOK" "$bh/safety_guard.sh"; cp "$SRC_PARSE" "$bh/_shared_parse.sh"
  asym=""; for pr in J1 J2 J3 J4 J5 J7 J10; do   # J8(CR 단독)·J9 는 구판도 한 줄로 읽었다 · J6 여러 줄 pass 는 D2 의 기대(결함 아님)
    vs="$(verdict "$(cd "$T" && fire 1 "$C/${pr}s.json" "$bh/safety_guard.sh")")"; vm="$(verdict "$(cd "$T" && fire 1 "$C/${pr}m.json" "$bh/safety_guard.sh")")"
    [ "$vs" = block ] && [ "$vm" = pass ] && asym="$asym $pr"
  done
  [ "$asym" = " J1 J2 J3 J4 J5 J7 J10" ] && ok "J-red 수리 전 훅 — 한 줄 판은 막고 여러 줄 판은 통과(7쌍 비대칭 = 결함 실증)" || ng "J-red 수리 전 비대칭 전제" "비대칭 쌍=[${asym# }]"
else echo "  (J-red 생략 — QVEST_SG_BASE_HOOK 미지정)"; fi

echo "--- H. 돌연변이 — 규칙을 끄면 해당 사례가 뚫린다 ---"
mut(){ # $1=이름 $2=sed 식 → 사본 경로 출력
  local m="$T/mut/$1/02_Infrastructure/hooks"; mkdir -p "$m"
  cp "$SRC_PARSE" "$m/_shared_parse.sh"; sed "$2" "$HOOK" > "$m/safety_guard.sh"; printf '%s' "$m/safety_guard.sh"
}
chk_mut(){ # $1=이름 $2=훅 $3.. = 뚫려야 할 사례
  local name="$1" h="$2" id o leaked=""; shift 2
  if cmp -s "$h" "$HOOK"; then ng "H $name" "돌연변이 sed 가 아무것도 바꾸지 못했다(좌표 낡음)"; return; fi
  for id in "$@"; do o="$(fire 1 "$C/$id.json" "$h")"; [ "$(verdict "$o")" = pass ] && leaked="$leaked $id"; done
  [ "$leaked" = " $*" ] && ok "H $name — 끄면 뚫린다:$leaked" || ng "H $name 판별력" "뚫린 사례=[${leaked# }] 기대=[$*]"
}
chk_mut rule3_off  "$(mut rule3_off 's/if _qmem_file_hit "\$FILE_PATH"; then _qmem_block; fi/:/; s/if _qmem_cmd_hit "\$COMMAND"; then _qmem_block; fi/:/')" A1 A3 B1 B4
chk_mut glob_off   "$(mut glob_off 's/_QMEM_WHY="glob"; return 0/:/')" B2 B3 B14
chk_mut cd_off     "$(mut cd_off 's/_QMEM_WHY="cd"; return 0/:/')" B15
chk_mut find_off   "$(mut find_off 's/_QMEM_WHY="find"; return 0/:/g')" B8 B9 B10
chk_mut unescape_off "$(mut unescape_off 's/if \[ "\$v" = 1 \]; then c="\${c\/\/\\\\\/\/}"; else c="\${c\/\/\\\\\/}"; fi/c="${c\/\/\\\\\/\/}"/')" B6
chk_mut path_off   "$(mut path_off 's/_QMEM_WHY="path"; return 0/:/')" A1 A2 A3 A4 A5 A6
chk_mut oneline_off "$(mut oneline_off 's/^  _Q1="\$s"$/  _Q1="$1"/')" J1m J2m J3m J4m J5m J7m J10m
# (D2) 정규화 두 층을 따로 끈다 — Rule 3 의 개행→' ; ' 만 끄면 둘째 줄 우회가 · 줄 이음 제거만 끄면 Rule 2 줄 이음 쓰기가 샌다
chk_mut nl_semi_off "$(mut nl_semi_off 's/^  s="\${s\/\/\$......\/ ; }".*$/  :/')" J1m J2m J3m J4m
chk_mut linecont_off "$(mut linecont_off 's/^  s="\${s\/\/\$........\/}"; s="\${s\/\/\$......\/}"$/  :/')" J7m J10m
# (D2) Rule 2 가 개행을 ' ; ' 로 잇게 되돌린 사본(R3R 초판) → J6 여러 줄 판(개행으로 갈린 두 명령)이 막힌다(J6 이 잡는다)
hnl="$(mut nlbound_off 's/^  _qsg_join "\$COMMAND"/  _qsg_oneline "$COMMAND"/')"
if cmp -s "$hnl" "$HOOK"; then ng "H nlbound_off" "sed 무변화"; else
  o0="$(fire 0 "$C/J6m.json" "$hnl")"; o1="$(fire 1 "$C/J6m.json" "$hnl")"
  [ "$(verdict "$o0")" = block ] && [ "$(verdict "$o1")" = block ] && ok "H nlbound_off — 개행을 이으면 J6 여러 줄 판이 막힌다(J6 이 잡는다)" || ng "H nlbound_off 판별력" "env0=$o0 env1=$o1"; fi
# 표식 게이트를 뒤집은 사본 → 평시 기억 쓰기가 막힌다(D 절의 판별력)
hinv="$(mut gate_inv 's/if \[ "\${QVEST_UNATTENDED_LANE:-}" = "1" \]; then$/if [ "${QVEST_UNATTENDED_LANE:-}" != "1" ]; then/')"
if cmp -s "$hinv" "$HOOK"; then ng "H gate_inv" "sed 무변화"; else
  o="$(fire 0 "$C/A1.json" "$hinv")"; [ "$(verdict "$o")" = block ] && ok "H gate_inv — 게이트를 뒤집으면 평시 쓰기가 막힌다(D 절이 잡는다)" || ng "H gate_inv" "$o"; fi

echo "--- I. 등록(읽기만) ---"
REG="$("$PY" -c "
import io,json,sys
d=json.load(io.open(sys.argv[1],encoding='utf-8'))
m=set()
for g in d.get('hooks',{}).get('PreToolUse',[]):
    if any('safety_guard.sh' in (h.get('command') or '') for h in g.get('hooks',[])): m.add(g.get('matcher'))
print(' '.join(sorted(m)))" "$SETTINGS" 2>/dev/null | tr -d '\r')"
case " $REG " in *" Bash "*) ok "I1 Bash 등록" ;; *) ng "I1 Bash 미등록" "$REG" ;; esac
case " $REG " in *" Write|Edit "*) ok "I2 Write|Edit 등록" ;; *) ng "I2 Write|Edit 미등록" "$REG" ;; esac

echo
echo "합계: 통과 $P · 실패 $F"
echo "{\"test\":\"safety_guard_memory\",\"pass\":$P,\"fail\":$F,\"total\":$((P+F))}"
[ "$F" -eq 0 ]
