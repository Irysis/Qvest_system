#!/usr/bin/env bash
#==============================================================================
# test_cleaner_distill.sh — 무인 증류 레인 검사 (2026-09-05 신설)
#
# 무엇을 재나: 이 레인에서 **되돌릴 수 없는 축은 삭제 집행 하나**다(digest·DIST 초안·
#   L-code 는 덧쓰기이고 되돌릴 수 있다). 그래서 검사의 본체는 삭제 가드이고,
#   **양방향**으로 잰다 — 지워야 할 것이 지워지는가(양성 대조) + 지우면 안 되는 것이
#   거부되는가(위반 주입). 한 방향만 재면 "가드가 전부 거부한다"(=레인 사망)와
#   "가드가 정확하다"가 겉보기 같다.
#
# 격리: QVEST_CD_ROOT 로 임시 root 를 쓴다 — QM_ROOT 로는 자식 R 프로세스를 격리할 수
#   없다(~/.Renviron 이 이긴다, 2026-09-04 실측). 운영 원장·pending 은 손대지 않는다.
#
# 실행: bash 08_Tests/ops/test_cleaner_distill.sh
#==============================================================================
set -uo pipefail
REPO="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
LIB="$REPO/02_Infrastructure/ops/cleaner_distill_lib.R"
T="$(mktemp -d 2>/dev/null || echo "/tmp/cdtest_$$")"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1  ($2)"; }
cleanup(){ rm -rf "$T" 2>/dev/null; }
trap cleanup EXIT

echo "=== cleaner_distill 검사 (격리 root=$T) ==="

# ── 픽스처 ────────────────────────────────────────────────────────────────────
mkdir -p "$T/.cache" "$T/06_Registry" "$T/05_Production" "$T/02_Infrastructure/ops" \
         "$T/04_Research/01_reports/weekly" "$T/.claude/skills"
git -C "$T" init -q 2>/dev/null
git -C "$T" config user.email t@t.t 2>/dev/null; git -C "$T" config user.name t 2>/dev/null

cp "$REPO/06_Registry/cleaner_protected_paths.json" "$T/06_Registry/"

cat > "$T/06_Registry/reinforce_auto_config.json" <<'EOF'
{"schema":"test","enabled":true,
 "cleaner_distill":{"enabled":true,"max_drafts":2,"ignore_reinforce_claim":true},
 "llm":{"model":"opus","effort":"high","lanes":{}}}
EOF

cat > "$T/.cache/cleaner_pending.json" <<'EOF'
{"schema":"cleaner_pending_v2","week_of":"2026-W36","status":"awaiting_distill",
 "distill_status":"pending","distill_owner":null,"distill_claimed_at":null,
 "sweep_deleted_n":3,
 "inventory":{"stage_artifacts_new":{"n":2},"new_lcodes":{"n":1},"git_log_7d":{"n_commits":5}},
 "axiom_candidates":{"n_pending":91,"activated_axioms":[],"held_axioms":[]}}
EOF

cat > "$T/06_Registry/distilled_knowledge.json" <<'EOF'
{"schema_version":"t","entries":[
 {"dist_id":"DIST-T-001","status":"pending_5axis","n_supporting":3,"polarity":"negative",
  "family":"f","research_mode":"m","type":"empirical","statement_draft":"draft one",
  "supporting_l_codes":["L-T-1"],"created_at":"2026-07-08","expiry":"2026-10-16"},
 {"dist_id":"DIST-T-002","status":"pending_5axis","n_supporting":1,"polarity":"positive",
  "family":"f","research_mode":"m","type":"empirical","statement_draft":"draft two",
  "supporting_l_codes":[],"created_at":"2026-07-09","expiry":"2026-10-16"},
 {"dist_id":"DIST-T-003","status":"quarantined_evidence","n_supporting":9,"statement_draft":"tainted"}]}
EOF

cat > "$T/.cache/lcode_corpus.json" <<'EOF'
{"schema_version":"t","lcodes":[{"l_code":"L-T-1","lesson_text":"기존 교훈 본문","grade":"C","metric_type":"backtested"}]}
EOF

# 삭제 후보 5종 — 각각 다른 축을 시험한다
mkdir -p "$T/02_Infrastructure/ops"
echo "dead code"                 > "$T/02_Infrastructure/ops/_dead_scratch.R"   # ① 지워져야 함
echo "referenced helper"         > "$T/02_Infrastructure/ops/_used_helper.R"    # ② 참조 잔존 → 거부
echo "source('_used_helper.R')"  > "$T/02_Infrastructure/ops/consumer.R"        #    (②의 참조처)
echo "prod artifact"             > "$T/05_Production/_prod_junk.R"              # ③ 보호구역 → 거부
echo "fresh file"                > "$T/02_Infrastructure/ops/_fresh.R"          # ④ 24h 내 → 거부
echo "skill"                     > "$T/.claude/skills/_x.md"                    # ⑤ 하네스 보호 → 거부
# ①②③⑤ 를 과거 시각으로 — ④만 방금 만든 그대로 둔다
for f in "$T/02_Infrastructure/ops/_dead_scratch.R" "$T/02_Infrastructure/ops/_used_helper.R" \
         "$T/05_Production/_prod_junk.R" "$T/.claude/skills/_x.md"; do
  touch -d "10 days ago" "$f" 2>/dev/null || touch -t 202608200900 "$f"
done
git -C "$T" add -A >/dev/null 2>&1; git -C "$T" commit -qm fixture >/dev/null 2>&1

cat > "$T/06_Registry/hygiene_report.json" <<'EOF'
{"generated_at":"2026-09-05","warnings":{
 "root_unauthorized":[],
 "infra_underscore":["02_Infrastructure/ops/_dead_scratch.R","02_Infrastructure/ops/_used_helper.R","02_Infrastructure/ops/_fresh.R"],
 "misplaced_outputs":[]}}
EOF

export QVEST_CD_ROOT="$T"
export QVEST_CD_JLOG="$T/.cache/test_jlog.jsonl"

# ── A. gate ───────────────────────────────────────────────────────────────────
echo "-- A. gate"
OUT="$(Rscript "$LIB" gate 2>&1)"; RC=$?
[ "$RC" = "0" ] && ok "A1 착수 가능(go) rc=0" || ng "A1 착수 가능" "rc=$RC $OUT"

# 위반 주입 — kill switch 를 끄면 반드시 물러나야 한다
"$REPO/.venv_qvest_ml/Scripts/python.exe" - "$T" <<'PY'
import io,json,sys
p=sys.argv[1]+'/06_Registry/reinforce_auto_config.json'
d=json.loads(io.open(p,'rb').read().decode('utf-8')); d['cleaner_distill']['enabled']=False
io.open(p,'w',encoding='utf-8',newline='\n').write(json.dumps(d,ensure_ascii=False))
PY
Rscript "$LIB" gate >/dev/null 2>&1; RC=$?
[ "$RC" = "12" ] && ok "A2 kill switch 발화(rc=12)" || ng "A2 kill switch" "rc=$RC (12 기대)"
"$REPO/.venv_qvest_ml/Scripts/python.exe" - "$T" <<'PY'
import io,json,sys
p=sys.argv[1]+'/06_Registry/reinforce_auto_config.json'
d=json.loads(io.open(p,'rb').read().decode('utf-8')); d['cleaner_distill']['enabled']=True
io.open(p,'w',encoding='utf-8',newline='\n').write(json.dumps(d,ensure_ascii=False))
PY

# 위반 주입 — 이미 증류된 주는 다시 돌면 안 된다
cp "$T/.cache/cleaner_pending.json" "$T/.cache/_pending.bak"
"$REPO/.venv_qvest_ml/Scripts/python.exe" - "$T" <<'PY'
import io,json,sys
p=sys.argv[1]+'/.cache/cleaner_pending.json'
d=json.loads(io.open(p,'rb').read().decode('utf-8')); d['distill_status']='done'
io.open(p,'w',encoding='utf-8',newline='\n').write(json.dumps(d,ensure_ascii=False))
PY
Rscript "$LIB" gate >/dev/null 2>&1; RC=$?
[ "$RC" = "10" ] && ok "A3 이미 증류된 주 재실행 차단(rc=10)" || ng "A3 재실행 차단" "rc=$RC (10 기대)"
cp "$T/.cache/_pending.bak" "$T/.cache/cleaner_pending.json"

# 위반 주입 — 보호 목록이 깨지면 삭제가 꺼져야 한다(빈 기본값 금지)
mv "$T/06_Registry/cleaner_protected_paths.json" "$T/06_Registry/_pp.bak"
Rscript "$LIB" materials "$T/.cache/mat_broken.txt" >/dev/null 2>&1
grep -q "삭제는 전면 금지" "$T/.cache/mat_broken.txt" 2>/dev/null \
  && ok "A4 보호목록 부재 → 삭제 전면 금지 표기" || ng "A4 보호목록 부재" "재료에 금지 문구 없음"
mv "$T/06_Registry/_pp.bak" "$T/06_Registry/cleaner_protected_paths.json"

# ── B. materials ──────────────────────────────────────────────────────────────
echo "-- B. materials"
Rscript "$LIB" materials "$T/.cache/mat.txt" >/dev/null 2>&1
M="$T/.cache/mat.txt"
[ -s "$M" ] && ok "B1 재료 생성" || ng "B1 재료 생성" "빈 파일"
grep -q "DIST-T-001" "$M" && ok "B2 supporting 상위 후보 포함" || ng "B2 후보" "DIST-T-001 없음"
grep -q "DIST-T-003" "$M" && ng "B3 격리 카드 제외" "quarantined 가 후보에 실렸다" || ok "B3 격리 카드 제외"
grep -q "L-T-1" "$M" && ok "B4 supporting L-code 본문 동반" || ng "B4 L-code 본문" "corpus 조회 실패"
grep -q "_dead_scratch.R" "$M" && ok "B5 삭제 후보 표면" || ng "B5 삭제 후보" "후보 미표면"
grep -q "_used_helper.R" "$M" && grep -q "참조처" "$M" \
  && ok "B6 참조수·참조처 동반(에이전트가 사실을 본다)" || ng "B6 참조 사실" "참조 정보 없음"

# ── C. apply — 삭제 가드 양방향 (이 검사의 본체) ──────────────────────────────
echo "-- C. apply 삭제 가드"
cat > "$T/04_Research/01_reports/weekly/weekly_digest_20260905.md" <<'EOF'
# 주간 digest (픽스처)
이 파일은 검사용이며 500바이트를 넘겨 digest 실재 검증을 통과하기 위한 본문이다.
증류 레인은 digest 가 없으면 release 하지 않는다 — 그 경로도 아래에서 따로 잰다.
실측만 인용한다는 규약은 여기서 검사 대상이 아니다(형식 검증은 기계, 내용은 에이전트).
반복 문장을 넣어 크기를 채운다. 반복 문장을 넣어 크기를 채운다. 반복 문장을 넣어 크기를 채운다.
반복 문장을 넣어 크기를 채운다. 반복 문장을 넣어 크기를 채운다. 반복 문장을 넣어 크기를 채운다.
반복 문장을 넣어 크기를 채운다. 반복 문장을 넣어 크기를 채운다. 반복 문장을 넣어 크기를 채운다.
EOF

cat > "$T/.cache/result.json" <<'EOF'
{"schema":"cleaner_distill_v1","week_of":"2026-W36",
 "digest_path":"04_Research/01_reports/weekly/weekly_digest_20260905.md",
 "dist_drafts":[],"lcodes":[],
 "deletions":[
   {"path":"02_Infrastructure/ops/_dead_scratch.R","reason":"참조 0 죽은 스크래치"},
   {"path":"02_Infrastructure/ops/_used_helper.R","reason":"에이전트가 참조 없다고 잘못 판단"},
   {"path":"05_Production/_prod_junk.R","reason":"보호구역인데 골랐다"},
   {"path":"02_Infrastructure/ops/_fresh.R","reason":"방금 수정된 파일을 골랐다"},
   {"path":".claude/skills/_x.md","reason":"하네스를 골랐다"},
   {"path":"../../../etc/passwd","reason":"경로 탈출 시도"}],
 "deferred":[]}
EOF

Rscript "$LIB" apply "$T/.cache/result.json" >"$T/.cache/apply.out" 2>&1; ARC=$?
MAN="$T/06_Registry/distill_manifest_$(date +%Y%m%d).json"
[ "$ARC" = "0" ] && ok "C0 apply rc=0 (digest 통과)" || ng "C0 apply rc" "rc=$ARC $(tail -3 "$T/.cache/apply.out")"
[ -s "$MAN" ] && ok "C1 distill manifest 기록" || ng "C1 manifest" "미생성"

chk(){ "$REPO/.venv_qvest_ml/Scripts/python.exe" - "$MAN" "$1" "$2" <<'PY'
import io,json,sys
m=json.loads(io.open(sys.argv[1],'rb').read().decode('utf-8'))
key,path=sys.argv[2],sys.argv[3]
print('YES' if any(x.get('path')==path for x in (m.get(key) or [])) else 'NO')
PY
}

# 양성 대조 — 진짜 죽은 파일은 실제로 지워져야 한다
[ ! -f "$T/02_Infrastructure/ops/_dead_scratch.R" ] \
  && ok "C2 [양성] 참조0 죽은 파일 실삭제" || ng "C2 양성 대조" "안 지워졌다 = 가드가 전부 거부(레인 사망)"
[ "$(chk deleted 02_Infrastructure/ops/_dead_scratch.R)" = "YES" ] \
  && ok "C3 [양성] 매니페스트 deleted 기록" || ng "C3 매니페스트" "기록 누락"

# 위반 주입 4종 — 전부 거부되고 파일이 남아야 한다
for pair in "02_Infrastructure/ops/_used_helper.R:참조잔존" \
            "05_Production/_prod_junk.R:보호구역" \
            "02_Infrastructure/ops/_fresh.R:24h내수정" \
            ".claude/skills/_x.md:하네스보호"; do
  p="${pair%%:*}"; why="${pair##*:}"
  if [ -e "$T/$p" ] && [ "$(chk rejected "$p")" = "YES" ]; then ok "C4 [주입] $why 거부 + 파일 잔존"
  else ng "C4 [주입] $why" "파일존재=$([ -e "$T/$p" ] && echo y || echo n) 거부기록=$(chk rejected "$p")"; fi
done
[ "$(chk rejected ../../../etc/passwd)" = "YES" ] \
  && ok "C5 [주입] 경로 탈출 거부" || ng "C5 경로 탈출" "거부 기록 없음"

# DRY — 가드는 전부 통과하되 집행만 안 해야 한다(스윕의 QVEST_CLEANER_DRY 관례 승계).
#   ★"dry 라서 아무것도 안 지웠다" 와 "가드가 거부했다" 는 다른 사건이다 — deleted 에 실리되
#     파일이 남아 있어야 그 둘이 구분된다.
echo "-- D. DRY 집행 억제"
echo "dead again" > "$T/02_Infrastructure/ops/_dead_scratch.R"
touch -d "10 days ago" "$T/02_Infrastructure/ops/_dead_scratch.R" 2>/dev/null || touch -t 202608200900 "$T/02_Infrastructure/ops/_dead_scratch.R"
QVEST_CLEANER_DRY=1 Rscript "$LIB" apply "$T/.cache/result.json" >/dev/null 2>&1
if [ -f "$T/02_Infrastructure/ops/_dead_scratch.R" ] && [ "$(chk deleted 02_Infrastructure/ops/_dead_scratch.R)" = "YES" ]; then
  ok "D1 [DRY] 가드 통과 기록되되 파일은 잔존"
else
  ng "D1 DRY" "파일존재=$([ -f "$T/02_Infrastructure/ops/_dead_scratch.R" ] && echo y || echo n) deleted기록=$(chk deleted 02_Infrastructure/ops/_dead_scratch.R)"
fi

# digest 부재 경로 — release 되면 안 되므로 rc≠0
cat > "$T/.cache/result_nodigest.json" <<'EOF'
{"schema":"cleaner_distill_v1","week_of":"2026-W36",
 "digest_path":"04_Research/01_reports/weekly/does_not_exist.md",
 "dist_drafts":[],"lcodes":[],"deletions":[],"deferred":[]}
EOF
Rscript "$LIB" apply "$T/.cache/result_nodigest.json" >/dev/null 2>&1; RC=$?
[ "$RC" != "0" ] && ok "C6 [주입] digest 부재 → rc≠0 (release 안 됨, 재시도)" \
                 || ng "C6 digest 부재" "rc=0 으로 통과했다"

# ── E. 역방향 충돌 가드 (reinforce_auto_tick.sh) ──────────────────────────────
#   증류 게이트는 "강화 중이면 증류 연기" 를 하는데, 그 반대(증류 중 강화 착수)도 막혀야 한다
#   — 둘 다 L-code 원장·distilled_knowledge.json 을 쓴다. **양방향**: 진행 중이면 양보하고,
#   아니면 양보하지 않아야 한다. 한 방향만 재면 "항상 양보"(=강화 정지)를 못 구분한다.
echo "-- E. 역방향 가드 (증류 중 강화 착수 차단)"
TICK="$REPO/02_Infrastructure/ops/reinforce_auto_tick.sh"
if [ -f "$TICK" ]; then
  ET="$T/tickroot"; mkdir -p "$ET/.cache/scheduler_logs"
  NOWTS="$(date '+%Y-%m-%d %H:%M:%S')"
  mkfix(){ cat > "$ET/.cache/cleaner_pending.json" <<EOF
{"distill_status":"$1","distill_owner":"$2","distill_claimed_at":"$3"}
EOF
}
  # E1 진행 중(신선) → 양보
  mkfix in_progress auto_distill "$NOWTS"
  QM_ROOT="$ET" bash "$TICK" >/dev/null 2>&1
  grep -q "halt_distill_active" "$ET/.cache/scheduler_logs/reinforce_auto_$(date +%Y%m%d).log" 2>/dev/null \
    && ok "E1 [양성] 증류 진행 중 → 강화 tick 양보" || ng "E1 양보" "halt_distill_active 미기록"
  # E2 완료 → 양보하지 않음 (항상 양보 = 강화 정지와 구분)
  rm -f "$ET/.cache/scheduler_logs/"*.log
  mkfix done auto_distill "$NOWTS"
  QM_ROOT="$ET" bash "$TICK" >/dev/null 2>&1
  grep -q "halt_distill_active" "$ET/.cache/scheduler_logs/reinforce_auto_$(date +%Y%m%d).log" 2>/dev/null \
    && ng "E2 [주입] 증류 완료면 양보 안 함" "done 인데 양보했다 = 강화 영구 정지" \
    || ok "E2 [주입] 증류 완료 → 양보 안 함"
  # E3 stale claim(1h 초과) → 양보하지 않음 (죽은 레인이 강화를 6h 세우면 안 된다)
  rm -f "$ET/.cache/scheduler_logs/"*.log
  mkfix in_progress auto_distill "$(date -d '3 hours ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '2020-01-01 00:00:00')"
  QM_ROOT="$ET" bash "$TICK" >/dev/null 2>&1
  grep -q "halt_distill_active" "$ET/.cache/scheduler_logs/reinforce_auto_$(date +%Y%m%d).log" 2>/dev/null \
    && ng "E3 [주입] stale claim 은 양보 안 함" "3h 된 claim 에 양보했다" \
    || ok "E3 [주입] stale claim(>1h) → 양보 안 함"
  # E4 다른 owner(세션 /cleaner)면 양보 안 함 — 세션 증류는 원장을 그렇게 쓰지 않는다
  rm -f "$ET/.cache/scheduler_logs/"*.log
  mkfix in_progress session_main "$NOWTS"
  QM_ROOT="$ET" bash "$TICK" >/dev/null 2>&1
  grep -q "halt_distill_active" "$ET/.cache/scheduler_logs/reinforce_auto_$(date +%Y%m%d).log" 2>/dev/null \
    && ng "E4 [주입] owner 한정" "auto_distill 이 아닌데 양보했다" || ok "E4 [주입] owner=auto_distill 한정"
else
  echo "  SKIP  E (reinforce_auto_tick.sh 없음)"
fi

echo ""
echo "=== 결과: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = "0" ] || exit 1
