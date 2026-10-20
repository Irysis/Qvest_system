#!/usr/bin/env bash
#==============================================================================
# test_hook_fastpath_equivalence.sh — 훅 빠른 길(WP4 2026-10-20)의 판정 불변 계약
#
# 배경: Write·Edit·Bash 마다 도는 PreToolUse/PostToolUse 훅 8종이 경로를 판정하기 전에 파이썬을 1~3회 띄웠다
#   (실측 10-17~20: 훅 16,192회 · 도구 호출당 대기 합 80분). 빠른 길 = 원문 입력에 그 훅의 차단 낱말이 없으면
#   파이썬 없이 '{}'. 각 훅 머리 주석에 '원문에 낱말이 없으면 어떤 파싱 결과로도 차단될 수 없다' 증명이 있다.
#   끄기 = QVEST_HOOK_FASTPATH=0 → 원래 경로(바이트 그대로). 이 검사는 켬/끔을 같은 입력에 맞대 본다.
#
# 검증 축 (훅 사본을 샌드박스에서 실 구동 — 로직 재현 아님 · /tmp 로그 경로만 샌드박스로 돌린 사본):
#   E  등가 — 사례 52건 × (켬 vs 끔): stdout · 종료 코드 · 부수효과 로그(시각 가림) · 발화 원장 행(시각 가림) 전부 같다
#      (실전 전사 표본 2,545쌍 · 경계 사례 423쌍의 구판 대 신판 차분 검사는 WP4 커밋 기록에 — 이 검사는 상설 축소판)
#   V  위반 주입 — 차단돼야 할 입력(보호 경로 · \u 이스케이프 · 줄 이음 · 잘린 JSON · 무인 레인 기억 경로 · 잘못된 UTF-8)이
#      켬에서도 차단
#   P  양성 대조 — 무해 입력에서 켬 = 파이썬 0회 · 끔 = 1회 이상(스파이 해석기) → 빠른 길이 실제로 걸린다(지연 기전 실재)
#   M  뮤테이션 — 빠른 길을 약하게 만든 사본(낱말 · \u · 줄 이음 · CR 절 · 해독기 · Rule 3 게이트 공유 · 패턴 파생 ·
#      오버레이 추출의 줄 경계)은 E/V 가 잡는다(13종)
#   ★동기화 의무: 훅에 새 차단 규칙을 넣으면 그 훅의 빠른 길 조건도 넓혀야 한다(backtest = TARGET_PATTERN ·
#     legacy = LEGACY_PATTERNS · safety_guard Rule 3 = _QSG_RULE3 는 정의 하나에서 파생돼 자동으로 따라간다).
#     규칙의 양성 대조 검사는 빠른 길이 켜진 채(기본값)로 돈다 — 조건이 낡으면 그 양성 대조가 빨강이 된다.
#
# 요약 규약: 마지막 줄 {"test":"hook_fastpath_equivalence","pass":N,"fail":N,"total":N,"skipped":N,"skips":[…]}
#==============================================================================
set -u

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_HOOKS="$(cd "$_SELF_DIR/../../02_Infrastructure/hooks" 2>/dev/null && pwd)"
PY="${QVEST_PY:-}"; PY="${PY//\\//}"
[ -n "$PY" ] && [ -x "$PY" ] || PY="C:/Users/99922/AppData/Local/Programs/Python/Python312/python.exe"
if [ -z "$SRC_HOOKS" ] || [ ! -x "$PY" ]; then
  echo "FATAL: hooks 디렉터리 또는 python 부재 (hooks='$SRC_HOOKS' py='$PY')"
  echo '{"test":"hook_fastpath_equivalence","pass":0,"fail":1,"total":1}'
  exit 1
fi

PASS=0; FAIL=0; SKIP=0; SKIPS=""
ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1  ($2)"; }
skip() { SKIP=$((SKIP+1)); echo "  SKIP  $1  ($2)"; SKIPS="${SKIPS:+$SKIPS,}{\"axis\":\"$1\",\"reason\":\"$2\",\"missing\":\"$3\"}"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/cases" "$T/runs" "$T/fx"
# ── 훅 사본: /tmp/ 로그 경로만 샌드박스로(켬·끔 모두 같은 사본 → 비교 공정 · 운영 /tmp 로그 무오염) ──
mk_hooks() { # $1 = 대상 디렉터리
  mkdir -p "$1"
  cp "$SRC_HOOKS"/*.sh "$1"/
  local f; for f in "$1"/*.sh; do sed -i 's#/tmp/#${QVEST_FP_TMP}/#g' "$f"; done
}
H="$T/hooks"; mk_hooks "$H"

# ── 스파이 해석기: 호출 1회 = 줄 1개 → 실제 python 으로 exec ──────────────────
SPY="$T/spy_python.sh"
printf '#!/usr/bin/env bash\necho call >> "${QVEST_FP_SPY_LOG:-/dev/null}"\nexec "%s" "$@"\n' "$PY" > "$SPY"
chmod +x "$SPY"

# ── 오버레이 .R 픽스처 (PostToolUse 는 디스크의 파일 내용을 본다) ───────────────
printf 'sig <- d[Date < p$anchor_date]\nx <- apply_gate(sig)\n' > "$T/fx/ov_anti.R"
printf '# 오버레이 신호\nsig <- d[Date < cutoff]\n' > "$T/fx/ov_soft.R"
printf 'apply_gate Date < anchor_date\n' > "$T/fx/ov_doc.md"
FXM="$(cygpath -m "$T/fx")"

# ── 사례: <id>|<hook>|<기대 판정 A/B>|<env(공백 구분 K=V · 없으면 ->> ─────────
"$PY" - "$T/cases" "$FXM" <<'PYEOF'
import json, os, sys
out, fx = sys.argv[1], sys.argv[2]
def J(o): return json.dumps(o, ensure_ascii=False, separators=(",", ":"))
def hi(tool, ti, ev="PreToolUse", extra=None):
    d = {"session_id": "fp-test", "transcript_path": "C:\\x\\t.jsonl", "cwd": "C:\\x", "permission_mode": "acceptEdits",
         "hook_event_name": ev, "tool_name": tool, "tool_input": ti, "tool_use_id": "toolu_fp"}
    if extra: d.update(extra)
    return J(d)
W = "C:\\Users\\99922\\OneDrive\\Quant_Module_Moltbot\\"
C = []
def add(cid, hook, exp, raw, env="-"):
    C.append((cid, hook, exp, env))
    open(os.path.join(out, cid + ".json"), "wb").write(raw if isinstance(raw, bytes) else raw.encode("utf-8"))
# safety_guard
add("s_allow_write", "safety_guard", "A", hi("Write", {"file_path": W + "04_Research\\x.R", "content": "x <- 1\n"}))
add("s_allow_bash", "safety_guard", "A", hi("Bash", {"command": "git status --short && ls -la", "description": "d"}))
add("s_allow_kr", "safety_guard", "A", hi("Write", {"file_path": W + "04_Research\\한글 경로\\메모.md", "content": "한글 \"q\" \\ \t"}))
add("s_allow_fp_escapes", "safety_guard", "A", hi("Write", {"file_path": "C:\\Q\\a\"b\\t\\c/d\te\nf.R", "content": "x"}))
add("s_allow_lit_kr", "safety_guard", "A", hi("Edit", {"file_path": W + "01_Literature\\Korea_Research\\p.md", "old_string": "a", "new_string": "b"}))
add("s_allow_invalid", "safety_guard", "A", '{"tool_name":"Bash","tool_input":{"command":"ls -la"')
add("s_allow_empty", "safety_guard", "A", "")
add("s_allow_dup", "safety_guard", "A", '{"tool_name":"Write","tool_name":"Bash","tool_input":{"command":"ls"}}')
add("s_block_prod_write", "safety_guard", "B", hi("Write", {"file_path": W + "05_Production\\x.R", "content": "a"}))
add("s_block_lit_edit", "safety_guard", "B", hi("Edit", {"file_path": W + "01_Literature\\p.md", "old_string": "a", "new_string": "b"}))
add("s_block_cp_prod", "safety_guard", "B", hi("Bash", {"command": "cp a.R 05_Production/a.R"}))
add("s_block_norm", "safety_guard", "B", hi("Bash", {"command": "Rscript -e 'normalizePath(\"x\")'"}))
add("s_block_cont_split", "safety_guard", "B", hi("Bash", {"command": "cp a.R 05_Produ\\\nction/a.R"}))
add("s_block_u_escape", "safety_guard", "B", '{"tool_name":"Bash","tool_input":{"command":"cp a \\u0030\\u0035_Production/x"}}')
add("s_block_invalid_prod", "safety_guard", "B", '{"tool_name":"Bash","tool_input":{"command":"cp a 05_Production/x"')
add("s_block_lane_memory", "safety_guard", "B", hi("Write", {"file_path": "C:\\Users\\x\\.claude\\projects\\p\\memory\\a.md", "content": "a"}), "QVEST_UNATTENDED_LANE=1")
# telegram_direct_call_guard
add("t_allow", "telegram_direct_call_guard", "A", hi("Bash", {"command": "Rscript -e 'cat(1)'"}))
add("t_allow_brief", "telegram_direct_call_guard", "A", hi("Bash", {"command": "Rscript -e \"tg_agent_brief('q','t',list()); tg_send('x')\""}))
add("t_deny_direct", "telegram_direct_call_guard", "B", hi("Bash", {"command": "Rscript -e \"tg_send('hi')\""}))
add("t_deny_u", "telegram_direct_call_guard", "B", '{"tool_name":"Bash","tool_input":{"command":"Rscript -e \\"tg\\u005fsend(1)\\""}}')
# legacy_write_block
add("l_allow", "legacy_write_block", "A", hi("Write", {"file_path": "C:/Q/x.R", "content": "a"}))
add("l_allow_invalid", "legacy_write_block", "A", '{"tool_name":"Write","tool_input":{"file_path":"C:/Q/x.R"')
add("l_block_v55", "legacy_write_block", "B", hi("Write", {"file_path": "C:/Q/_archive_v55/x.R", "content": "a"}))
add("l_block_u", "legacy_write_block", "B", '{"tool_name":"Write","tool_input":{"file_path":"C:/Q/_archive_\\u0076\\u0035\\u0035/x.R","content":"a"}}')
add("l_block_invalid", "legacy_write_block", "B", '{"tool_name":"Write","tool_input":{"file_path":"C:/Q/_archive_v55/x.R"')
add("l_block_two_seg", "legacy_write_block", "B", hi("Edit", {"file_path": "C:/Q/legacy/v55/x.R", "old_string": "a", "new_string": "b"}))
add("l_allow_near_miss", "legacy_write_block", "A", hi("Write", {"file_path": "C:/Q/legacy/v56/x.R", "content": "v55 is mentioned"}))
# book_write_guard
add("b_allow", "book_write_guard", "A", hi("Write", {"file_path": "C:/Q/06_registry_other.json", "content": "{}"}))
add("b_block_bslash", "book_write_guard", "B", hi("Write", {"file_path": W + "06_Registry\\book\\book_registry.json", "content": "{}"}))
add("b_block_escslash", "book_write_guard", "B", '{"tool_name":"Write","tool_input":{"file_path":"06_Registry\\/book\\/x.json","content":"a"}}')
add("b_block_state", "book_write_guard", "B", hi("Edit", {"file_path": "C:/Q/qepm/mailbox/governor/book_state.json", "old_string": "a", "new_string": "b"}))
add("b_block_u", "book_write_guard", "B", '{"tool_name":"Write","tool_input":{"file_path":"\\u0030\\u0036_Registry/book/x.json","content":"a"}}')
# discovery_graduation_gate
add("d_allow", "discovery_graduation_gate", "A", hi("Write", {"file_path": "q/WT-D20990101_001/request.json", "content": "{}"}))
add("d_block_wtp", "discovery_graduation_gate", "B", hi("Write", {"file_path": "qepm/mailbox/worktask/WT-P20990101_001/request.json", "content": J({"wt_type": "deployment", "discovery_of": "WT-D20990101_001"})}))
add("d_block_u", "discovery_graduation_gate", "B", '{"tool_name":"Write","tool_input":{"file_path":"q/WT\\u002dP1/request.json","content":"{\\"wt_type\\":\\"deployment\\",\\"discovery_of\\":\\"X\\"}"}}')
add("d_block_invalid", "discovery_graduation_gate", "B", '{"tool_name":"Write","tool_input":{"file_path":"q/WT-P1/request.json"')
# worktask_constraint_enforcer
add("w_allow", "worktask_constraint_enforcer", "A", hi("Write", {"file_path": "q/opt.json", "content": J({"target_weights": {"A": 2}})}))
add("w_block_26", "worktask_constraint_enforcer", "B", hi("Write", {"file_path": "q/WT-P20990101_001/optimization_package.json", "content": J({"target_weights": {"A%02d" % i: 1.0 / 26 for i in range(26)}})}))
add("w_block_u", "worktask_constraint_enforcer", "B", '{"tool_name":"Write","tool_input":{"file_path":"q/WT-P20990101_001/optimization\\u005fpackage.json","content":"{\\"target_weights\\":{\\"A\\":2}}"}}')
# backtest_contract_audit
add("c_allow", "backtest_contract_audit", "A", hi("Write", {"file_path": "C:/Q/x/metrics.csv", "content": "a"}))
add("c_target_no_rds", "backtest_contract_audit", "A", hi("Write", {"file_path": "C:/Q/qepm/registry/backtest_registry.csv", "content": "a"}))
add("c_block_rds", "backtest_contract_audit", "B", hi("Write", {"file_path": "C:/Q/qepm/registry/backtest_registry.csv", "content": "a"}), "FP_RDS=1")
# 잘못된 UTF-8 바이트가 섞인 원문 — 빠른 길(bash 정규식)이 그래도 대상 낱말을 찾아 원래 경로로 넘기는가
add("c_block_bad_utf8", "backtest_contract_audit", "B", b'{"tool_name":"Write","tool_input":{"file_path":"C:/Q/\xff\xfe/backtest_registry.csv","content":"\xc3"}}', "FP_RDS=1")
# overlay_pit_grep (PostToolUse · 판정은 항상 A · 차이는 로그로 잰다)
for nm in ("ov_anti.R", "ov_soft.R", "ov_doc.md"):
    p = fx + "/" + nm
    add("o_" + nm.replace(".", "_"), "overlay_pit_grep", "A", hi("Edit", {"file_path": p, "old_string": "a", "new_string": "b"}, "PostToolUse", {"tool_response": {"filePath": p}}))
add("o_bslash_anti", "overlay_pit_grep", "A", hi("Edit", {"file_path": (fx + "/ov_anti.R").replace("/", "\\"), "old_string": "a"}, "PostToolUse"))
add("o_cr_tail", "overlay_pit_grep", "A", '{"tool_name":"Edit","tool_input":{"file_path":"' + fx + '/ov_anti.R\r","old_string":"a"}}')
# 추출 등가(구판 grep 줄 단위 · 첫 일치) — 키와 콜론이 줄로 갈린 원문 · 같은 키 2회(첫 것이 이긴다) · 공백/탭 콜론 · 멀티바이트 로케일(구판 경로)
add("o_split_line", "overlay_pit_grep", "A", '{"tool_name":"Edit","tool_input":{"file_path"\n:"' + fx + '/ov_anti.R","old_string":"a"}}')
add("o_twice_first_wins", "overlay_pit_grep", "A", '{"tool_name":"Edit","tool_input":{"file_path":"' + fx + '/ov_doc.md"},"tool_response":{"file_path":"' + fx + '/ov_anti.R"}}')
add("o_ws_colon", "overlay_pit_grep", "A", '{"tool_name":"Edit","tool_input":{"file_path" :\t "' + fx + '/ov_anti.R","old_string":"a"}}')
add("o_utf8_locale", "overlay_pit_grep", "A", hi("Edit", {"file_path": fx + "/ov_soft.R", "old_string": "a"}, "PostToolUse"), "LANG=C.UTF-8")
with open(os.path.join(out, "_index.txt"), "w", encoding="utf-8", newline="\n") as f:
    for cid, hook, exp, env in C:
        f.write("%s|%s|%s|%s\n" % (cid, hook, exp, env))
PYEOF

# 백테스트 차단 픽스처(최근 bt_result.rds · integrity=FAIL) — Rscript 가 있어야 만든다
RDS=""
if command -v Rscript >/dev/null 2>&1; then
  Rscript -e "saveRDS(list(manifest = list(integrity_status = 'FAIL')), '$(cygpath -m "$T/fx/bt_result.rds")')" >/dev/null 2>&1 && RDS="$T/fx/bt_result.rds"
fi

norm() { sed -E 's/\[[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}([+-][0-9]{2}:?[0-9]{2})?\]/[TS]/g; s/"timestamp":"[^"]*"/"timestamp":"TS"/g' "$@" 2>/dev/null; }

run_case() { # $1=hooks_dir $2=hook $3=case_id $4=fast(0|1) $5=outdir $6=env-spec
  local hd="$1" hk="$2" cid="$3" fast="$4" o="$5" envs="$6" e=()
  rm -rf "$o"; mkdir -p "$o/tmp" "$o/proj/qepm/observability"
  if [ "$envs" != "-" ]; then read -r -a e <<< "$envs"; fi
  local rds_on=0 kv; for kv in ${e[@]+"${e[@]}"}; do [ "$kv" = "FP_RDS=1" ] && rds_on=1; done
  if [ "$rds_on" = 1 ] && [ -n "$RDS" ]; then mkdir -p "$o/proj/04_Research/strategies/s1"; cp "$RDS" "$o/proj/04_Research/strategies/s1/bt_result.rds"; fi
  local pw; pw="$(cygpath -m "$o/proj")"
  ( cd "$o/proj" && env -u QVEST_UNATTENDED_LANE -u QVEST_CLEAN_LANE -u QVEST_ARM_GEN -u QVEST_DESIGN_LANE \
      -u QVEST_SKIP_BACKTEST_CONTRACT_AUDIT -u QVEST_SKIP_OVERLAY_PIT \
      CLAUDE_PROJECT_DIR="$pw" QM_ROOT="$pw" QVEST_FP_TMP="$o/tmp" QVEST_HOOK_FASTPATH="$fast" \
      QVEST_PY_BIN="$SPY" QVEST_PY="$SPY" QVEST_FP_SPY_LOG="$o/spy.log" ${e[@]+"${e[@]}"} \
      bash "$hd/$hk.sh" < "$T/cases/$cid.json" > "$o/stdout" 2> "$o/stderr"; echo $? > "$o/rc" )
}
fingerprint() { # $1=outdir → 판정·부수효과 지문(시각 가림 · 실행 디렉터리 경로 가림)
  local o="$1" om f
  om="$(cygpath -m "$o")"
  printf 'stdout=%s\nrc=%s\n' "$(cat "$o/stdout" 2>/dev/null)" "$(cat "$o/rc" 2>/dev/null)"
  for f in "$o"/tmp/*; do [ -f "$f" ] && { printf -- '--%s\n' "$(basename "$f")"; norm "$f" | sed -e "s#$o#<O>#g" -e "s#$om#<O>#g"; }; done
  printf -- '--ledger\n'; norm "$o/proj/qepm/observability/events.jsonl"
}
verdict() { case "$(cat "$1/stdout" 2>/dev/null)" in *'"block"'*|*'"deny"'*) echo B ;; '{}') echo A ;; *) echo "?" ;; esac; }
spy_n() { [ -f "$1/spy.log" ] && wc -l < "$1/spy.log" | tr -d ' ' || echo 0; }

echo "=== test_hook_fastpath_equivalence (빠른 길 판정 불변) ==="
NC=0
while IFS='|' read -r cid hook exp envs; do
  [ -n "$cid" ] || continue
  NC=$((NC+1))
  if [ "$envs" = "FP_RDS=1" ] && [ -z "$RDS" ]; then skip "V[$cid]" "Rscript 부재 — bt_result.rds 픽스처 생성 불가" "Rscript"; continue; fi
  run_case "$H" "$hook" "$cid" 1 "$T/runs/$cid.on" "$envs"
  run_case "$H" "$hook" "$cid" 0 "$T/runs/$cid.off" "$envs"
  fon="$(fingerprint "$T/runs/$cid.on")"; foff="$(fingerprint "$T/runs/$cid.off")"
  if [ "$fon" = "$foff" ]; then ok "E[$hook/$cid] 켬=끔 (판정·로그·원장)"
  else bad "E[$hook/$cid] 켬=끔" "$(diff <(printf '%s\n' "$foff") <(printf '%s\n' "$fon") | head -4 | tr '\n' '|')"; fi
  v="$(verdict "$T/runs/$cid.on")"
  if [ "$v" = "$exp" ]; then ok "V[$hook/$cid] 판정=$exp"; else bad "V[$hook/$cid] 판정" "expect=$exp actual=$v out=$(head -c 120 "$T/runs/$cid.on/stdout")"; fi
done < "$T/cases/_index.txt"
[ "$NC" -ge 40 ] && ok "E 사례 수 ≥ 40 ($NC)" || bad "E 사례 수" "$NC"

# ── P 양성 대조: 무해 입력 · 켬 = 파이썬 0회 / 끔 = 1회 이상 ─────────────────
for pair in s_allow_write:safety_guard s_allow_bash:safety_guard t_allow:telegram_direct_call_guard l_allow:legacy_write_block \
            b_allow:book_write_guard d_allow:discovery_graduation_gate w_allow:worktask_constraint_enforcer; do
  cid="${pair%%:*}"; hook="${pair##*:}"
  non="$(spy_n "$T/runs/$cid.on")"; noff="$(spy_n "$T/runs/$cid.off")"
  if [ "$non" = "0" ] && [ "$noff" -ge 1 ] 2>/dev/null; then ok "P[$hook] 빠른 길 실재 — 켬 python 0회 · 끔 ${noff}회"
  else bad "P[$hook] 빠른 길 실재" "켬=${non} 끔=${noff} (켬 0 · 끔 ≥1 이어야)"; fi
done

# ── M 뮤테이션: 빠른 길을 일부러 약하게 만든 사본 → E/V 가 잡아야 한다 ──────────
mutate() { # $1=id $2=hook $3=case $4=sed-expr  → 변이 사본에서 켬 실행이 기준(끔)과 갈려야 PASS
  local id="$1" hk="$2" cid="$3" ex="$4" md="$T/mut_$1"
  mk_hooks "$md"
  sed -i "$ex" "$md/$hk.sh"
  if cmp -s "$H/$hk.sh" "$md/$hk.sh"; then bad "M[$id] 변이 적용" "치환 0건 — 빠른 길 문구가 바뀌었으면 이 검사를 갱신할 것"; return; fi
  local envs; envs="$(grep "^$cid|" "$T/cases/_index.txt" | cut -d'|' -f4)"
  if [ "$envs" = "FP_RDS=1" ] && [ -z "$RDS" ]; then skip "M[$id]" "Rscript 부재" "Rscript"; return; fi
  run_case "$md" "$hk" "$cid" 1 "$T/runs/$cid.mut_$id" "${envs:--}"
  if [ "$(fingerprint "$T/runs/$cid.mut_$id")" != "$(fingerprint "$T/runs/$cid.off")" ]; then ok "M[$id] 약화 사본을 $cid 가 검출"
  else bad "M[$id] 약화 사본 미검출" "$cid 의 켬/끔 지문이 같다 — 이 사례는 그 절을 재지 못한다"; fi
}
mutate sg_token  safety_guard                 s_block_cp_prod    's/\*05_Production\*|//'
mutate sg_lane   safety_guard                 s_block_lane_memory 's/ && \[ "\$_QSG_RULE3" != "1" \]; then$/; then/'
mutate sg_u      safety_guard                 s_block_u_escape   "s/|\\*'\\\\u'\\*|/|/"
mutate sg_cont   safety_guard                 s_block_cont_split "s/|\\*'\\\\\\\\\\\\n'\\*//"
mutate sg_decode safety_guard                 s_allow_fp_escapes '/^  _Q1=/ s#/\\\\}"$#/}"#'
mutate tg_token  telegram_direct_call_guard   t_deny_direct      's/\*tg_send\*|//'
mutate lw_derive legacy_write_block           l_block_v55        's/\[ "\$all" = 1 \] && return 0/:/'
mutate bw_token  book_write_guard             b_block_bslash     's/\*06_Registry\*|//'
mutate dg_token  discovery_graduation_gate    d_block_wtp        's/\*WT-P\*|//'
mutate wc_token  worktask_constraint_enforcer w_block_26         's/\*optimization_package\*|//'
mutate bt_derive backtest_contract_audit      c_block_rds        's/^_bca_may_target() {.*}$/_bca_may_target() { return 1; }/'
mutate ov_cr     overlay_pit_grep             o_cr_tail          "s/|\\*\\.R\\\$'\\\\r'\\*//"
mutate ov_ws     overlay_pit_grep             o_split_line       's/\[ \\t\\v\\f\]\*:\[ \\t\\v\\f\]\*/[[:space:]]*:[[:space:]]*/'

echo ""
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
echo "{\"test\":\"hook_fastpath_equivalence\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL)),\"skipped\":$SKIP,\"skips\":[${SKIPS}]}"
[ "$FAIL" -eq 0 ] || exit 1
