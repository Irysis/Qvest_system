#!/usr/bin/env bash
# test_stranded_triage.sh — 좌초 수리 triage 재분류 계약 (2026-08-08 신설)
#
# 왜: 2026-08-08 좌초 경보 "유실 36건" 중 **진짜 미도달은 7건**이었다.
#   · 26건 = append-only 원장(events.jsonl 등)의 세션별 분기 — 설계상 합쳐지지 않음
#   ·  3건(+파일 단위로는 19 항목) = main 이 이미 **상위판으로 교체**한 구판
#   구판 triage 는 "이 줄들이 main 에 있나"만 물어서 **방향 개념이 없었다** — 통합이 성공해
#   main 이 좋아질수록 경보가 커지는 역신호였다.
#
# ★이 검사기의 존재 이유: 위 수리는 경보를 **줄이는** 수리다. 줄어든 것과 죽은 것은
#   겉보기가 같다. T1(양성 대조)과 T5/T6(돌연변이)이 본체 — 진짜 유실이 여전히 잡히는지,
#   면제 규칙이 실제로 일을 하는지를 각각 실증한다.
#
# 방식: 임시 git 저장소 + 실제 worktree 를 만들어 **원본 스크립트를 그대로 구동**한다
#   (사본 검사는 원본과 갈린다). QM_ROOT 로 대상 트리를 지정 — 스크립트 resolver 1순위.
set -uo pipefail

_SELF="${BASH_SOURCE[0]:-$0}"; _SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
MARKER_REL="02_Infrastructure/hooks/qvest_hook_router.py"
PROJ=""
for c in "$_SELF_DIR/../.." "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$PWD"; do
  [ -n "$c" ] && [ -f "${c//\\//}/$MARKER_REL" ] && { PROJ="$(cd "${c//\\//}" && pwd)"; break; }
done
[ -n "$PROJ" ] || { echo "PROJECT_ROOT 해석 실패" >&2
  echo '{"test":"stranded_triage","pass":0,"fail":1,"total":1,"preflight":"no_root"}'; exit 1; }
AUDIT="$PROJ/02_Infrastructure/ops/stranded_repairs_audit.sh"
[ -f "$AUDIT" ] || { echo "원본 없음: $AUDIT" >&2
  echo '{"test":"stranded_triage","pass":0,"fail":1,"total":1,"preflight":"no_src"}'; exit 1; }

TMP="$(mktemp -d)"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP" 2>/dev/null' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"
        else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }

# ── 픽스처: main 저장소 + worktree 1개 ────────────────────────────────────────
build_fixture() {
  R="$TMP/repo"
  # 재빌드 시 **worktree 디렉터리까지** 지운다 — 남아 있으면 `git worktree add` 가 실패해
  # 픽스처가 조용히 안 만들어지고, 그 결과가 'ABSENT' = 판정 실패와 구분 안 되는 출력이 된다.
  chmod -R u+w "$R" "$TMP/worktrees" 2>/dev/null
  rm -rf "$R" "$TMP/worktrees"
  mkdir -p "$R/qepm/observability" "$R/02_Infrastructure/hooks" "$R/src"
  git -C "$R" init -q -b main 2>/dev/null
  git -C "$R" config user.email t@t; git -C "$R" config user.name t
  touch "$R/$MARKER_REL"
  printf 'base\n'            > "$R/src/genuine.txt"     # main 이 이후 손대지 않을 파일
  printf 'base\n'            > "$R/src/superseded.txt"  # main 이 이후 앞서 나갈 파일
  printf '{"e":0}\n'         > "$R/qepm/observability/events.jsonl"
  git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm base >/dev/null 2>&1

  # ★경로에 literal 'worktrees' 가 있어야 감사기가 대상으로 잡는다(원본 :95 필터)
  W="$TMP/worktrees/wt1"; mkdir -p "$TMP/worktrees"
  git -C "$R" worktree add -q -b feat "$W" >/dev/null 2>&1

  # worktree 쪽 변경 (커밋하지 않음 = 좌초 상태)
  printf 'base\nGENUINE_REPAIR_LINE\n'       > "$W/src/genuine.txt"
  printf 'base\nOLD_DRAFT_LINE\n'            > "$W/src/superseded.txt"
  printf '{"e":0}\n{"e":"wt-session"}\n'     > "$W/qepm/observability/events.jsonl"
  printf 'brand new file\n'                  > "$W/src/newfile.txt"    # main 에 아예 없음
  printf 'raw run log\n'                     > "$W/src/_runlog.txt"    # 파생 스크래치
  printf 'x <- 1\n'                          > "$W/src/_helper.R"      # ★_ 접두이나 **소스**
  printf 'old registry\n'                    > "$W/src/reg.json.bak_20260802"
  sleep 1

  # ★두 번째 worktree — 충돌 판정을 **공허하지 않게** 만든다.
  #   worktree 1개짜리 픽스처에서는 어떤 경로도 충돌일 수 없어 "충돌 0" 이 항상 참이 된다
  #   (발굴 조건이 통과를 보장하면 그 검증은 없는 것과 같다 — 공허한 게이트 함정).
  #   같은 두 경로를 건드리게 해서 lost 접점만 충돌로 세는지 본다.
  W2="$TMP/worktrees/wt2"
  git -C "$R" worktree add -q -b feat2 "$W2" >/dev/null 2>&1
  printf 'base\nGENUINE_REPAIR_LINE_B\n'     > "$W2/src/genuine.txt"     # lost 접점 ×2 → 충돌
  printf 'base\nOLD_DRAFT_LINE_B\n'          > "$W2/src/superseded.txt"  # 상위판 접점 ×2 → 충돌 아님
  sleep 1

  # main 이 그 파일에서 **앞서 나간다** (구판 줄을 더 나은 줄로 교체 후 커밋)
  printf 'base\nBETTER_CONSOLIDATED_LINE\n'  > "$R/src/superseded.txt"
  git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm advance >/dev/null 2>&1
  # main 자신의 원장 append (두 계열이 갈린다)
  printf '{"e":0}\n{"e":"main-session"}\n'   > "$R/qepm/observability/events.jsonl"
}

# verdict_of <repo> <path> → 그 경로의 verdict
verdict_of_path() {
  "$PYX" -c "
import json,io,sys
d=json.load(io.open(sys.argv[1],encoding='utf-8'))
for w in d.get('worktrees',[]):
    for f in w.get('files',[]):
        if f['path']==sys.argv[2]: print(f['verdict']); raise SystemExit
print('ABSENT')" "$1/06_Registry/stranded_repairs.json" "$2" 2>/dev/null
}
PYX=""
for c in "${QVEST_PY:-}" "$PROJ/.venv_qvest_ml/Scripts/python.exe" \
         "/c/Users/99922/AppData/Local/Programs/Python/Python312/python.exe"; do
  [ -n "$c" ] && [ -x "$c" ] && "$c" -c 'import json' >/dev/null 2>&1 && { PYX="$c"; break; }
done
[ -n "$PYX" ] || { echo "python 해석 실패" >&2
  echo '{"test":"stranded_triage","pass":0,"fail":1,"total":1,"preflight":"no_python"}'; exit 1; }

run_audit() {   # $1=스크립트 경로(돌연변이 주입용)
  ( cd "$R" && QM_ROOT="$R" CLAUDE_PROJECT_DIR="$R" \
      bash "${1:-$AUDIT}" --no-telegram --quiet ) >/dev/null 2>&1
}

echo "== 좌초 triage 재분류 계약 =="
build_fixture
run_audit

# ── T1 양성 대조 ★본체: main 이 손대지 않은 진짜 미도달 수리는 반드시 유실로 남는다.
#    면제 규칙 2종이 이걸 삼키면 경보 전체가 무의미해진다.
chk "T1 main 미갱신 + 줄 부재 → lost 유지(양성 대조)" "lost" "$(verdict_of_path "$R" src/genuine.txt)"
# ── T2 main 에 아예 없는 신규 파일도 유실로 남는다 (nostalgic-borg 7건이 이 부류)
chk "T2 main 에 부재한 신규 파일 → lost 유지"          "lost" "$(verdict_of_path "$R" src/newfile.txt)"
# ── T3 원장 분기는 수리가 아니다
chk "T3 append-only 원장 → ledger_divergence"          "ledger_divergence" "$(verdict_of_path "$R" qepm/observability/events.jsonl)"
# ── T4 main 이 앞서 나간 경로는 교체이지 유실이 아니다
chk "T4 main 이 이후 커밋으로 앞서감 → superseded_upstream" "superseded_upstream" "$(verdict_of_path "$R" src/superseded.txt)"

# ── T4b/T4c 파생 스크래치는 수리가 아니다 — 단, 제외는 **부류**로 좁게 건다
chk "T4b _접두 원로그(.txt) → scratch_artifact"        "scratch_artifact" "$(verdict_of_path "$R" src/_runlog.txt)"
chk "T4c .bak 백업 → scratch_artifact"                 "scratch_artifact" "$(verdict_of_path "$R" src/reg.json.bak_20260802)"
# ★경계 대조: `_` 접두라도 **소스**(.R/.py/.sh)는 private 모듈일 수 있다(storage §56) → 제외 금지
chk "T4d _접두여도 .R 소스는 lost 유지(제외 경계)"      "lost" "$(verdict_of_path "$R" src/_helper.R)"

# ── T4e 충돌은 **조치 대상 접점만** — 상위판/원장 접점은 병합할 것이 없으므로 충돌이 아니다
#    2 worktree 가 genuine.txt(lost)와 superseded.txt(상위판) 둘 다 건드린다 →
#    충돌은 **정확히 genuine.txt 1건**이어야 한다(공허 통과 방지: 0 도 2 도 오답).
COLLS=$("$PYX" -c "
import json,io,sys
d=json.load(io.open(sys.argv[1],encoding='utf-8'))
print('%d:%s'%(d['summary']['collisions'], ','.join(sorted(c['path'] for c in d.get('collisions',[])))))" \
  "$R/06_Registry/stranded_repairs.json" 2>/dev/null)
chk "T4e 충돌 = 조치 대상 접점만(상위판 접점 제외)" "1:src/genuine.txt" "${COLLS:-X}"

# ── T5/T6 돌연변이 ★면제 규칙이 실제로 일을 하는지: 무력화하면 T3/T4 가 유실로 뒤집혀야 한다.
sed 's|^LEDGER_RE=.*|LEDGER_RE="^__never_matches__$"|' "$AUDIT" > "$TMP/mut_ledger.sh"
build_fixture; run_audit "$TMP/mut_ledger.sh"
chk "T5 돌연변이(원장 규칙 제거) → T3 이 유실로 뒤집힘" "lost" "$(verdict_of_path "$R" qepm/observability/events.jsonl)"

sed 's|v="superseded_upstream"|v="$v"|' "$AUDIT" > "$TMP/mut_super.sh"
build_fixture; run_audit "$TMP/mut_super.sh"
chk "T6 돌연변이(교체 판정 제거) → T4 가 유실로 뒤집힘" "lost" "$(verdict_of_path "$R" src/superseded.txt)"

# ── T7 재분류 후에도 양성 대조는 살아 있다(돌연변이 없이 재확인 = 순서 의존 배제)
build_fixture; run_audit
chk "T7 재실행 후에도 T1 유지(멱등)"                   "lost" "$(verdict_of_path "$R" src/genuine.txt)"

TOTAL=$((PASS+FAIL))
echo "  ── $PASS/$TOTAL pass"
printf '{"test":"stranded_triage","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ]
