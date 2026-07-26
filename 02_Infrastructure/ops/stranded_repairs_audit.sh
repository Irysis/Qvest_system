#!/usr/bin/env bash
# stranded_repairs_audit.sh — 좌초 수리(stranded repair) 감사기
#
# 목적: 병렬 세션 worktree에 갇혀 main에 도달하지 못한 수리를 탐지·분류·등재한다.
#   근본: bootstrap 전문에 git 점검이 0건이라 "수리는 됐는데 worktree에 갇힘" 상태가 안 보였음.
#   동일 패턴 실사고 2건 — benchmark date32 writer(미커밋 6일 방치) · lcode_harvester family 수리
#   (메모리에 '미병합=게이트'로 기록). 감지 장치 부재가 공통 근본원인.
#
# bootstrap §4h(부팅 시점 WARN)의 상위 버전:
#   §4h  = 존재/개수만 · 세션 시작 때만 · 무인 시간대 방치 못 잡음
#   본 스크립트 = 파일 단위 triage(a/b/c) + 레지스트리 영속화 + 텔레그램 경보 + prune 후보
#
# triage 분류 (worktree 로컬 변경의 '추가 라인'이 main 파일에 존재하는가):
#   (a) merged_upstream — 전량 존재. worktree는 stale 사본. 안전하게 정리 가능
#   (b) lost           — 전무. main에 없는 진짜 유실 ★조치 필요
#   (c) partial        — 일부만. 별도 경로 반영 또는 충돌 — 수동 확인
#
# 읽기 전용: worktree에 절대 쓰지 않는다(status/diff/rev-list/log만). 타 세션 작업 무간섭.
#
# 사용:
#   bash 02_Infrastructure/ops/stranded_repairs_audit.sh              # 감사 + JSON + 텔레그램(조건부)
#   bash 02_Infrastructure/ops/stranded_repairs_audit.sh --no-telegram
#   bash 02_Infrastructure/ops/stranded_repairs_audit.sh --quiet      # JSON만, stdout 최소
#
# 산출: 06_Registry/stranded_repairs.json
# 2026-07-25 신규 (도훈 승인 next_probe ②③)

set -uo pipefail

PROJECT="${QM_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
cd "$PROJECT" 2>/dev/null || { echo "[stranded] PROJECT 해석 실패: $PROJECT" >&2; exit 0; }

OUT="$PROJECT/06_Registry/stranded_repairs.json"
STALE_DAYS="${STRANDED_STALE_DAYS:-3}"
MAIN_REF="${STRANDED_MAIN_REF:-main}"
MAX_LINES_PER_FILE=200          # triage 대조 상한 (대용량 diff 방어)
DO_TG=1; QUIET=0; DO_PRUNE=0
for a in "$@"; do
  case "$a" in
    --no-telegram) DO_TG=0 ;;
    --quiet)       QUIET=1 ;;
    --prune)       DO_PRUNE=1 ;;
  esac
done
say() { [ "$QUIET" -eq 1 ] || echo "$@"; }
# hb = heartbeat: --quiet 여도 반드시 남긴다. 무인 로그가 비면 "돌긴 했나"를 답할 수 없고,
#      그건 본 스크립트가 고치려는 문제(침묵 실패)와 같은 부류다.
hb()  { echo "[$(date '+%F %T')] $*"; }

command -v git >/dev/null 2>&1 || { echo "[stranded] git 없음 — skip" >&2; exit 0; }
git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1 || { echo "[stranded] git repo 아님 — skip" >&2; exit 0; }

TMP="$(mktemp -d 2>/dev/null || echo /tmp/stranded_$$)"; mkdir -p "$TMP"
cleanup() { rm -rf "$TMP" 2>/dev/null || true; }
trap cleanup EXIT

jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' -e 's/\r//g'; }

# ── 정규화: 선행/후행 공백 제거 + 빈 줄·주석기호단독 제외 (형식 차이로 인한 오탐 축소)
norm() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -vE '^$|^#$|^//$' ; }

# ── 파일 1건 triage: 추가 라인 중 main 파일에 없는 개수 산출
#    stdout: "<추가라인수> <미존재수>"
triage_file() {
  local wt="$1" f="$2"
  git -C "$wt" diff -- "$f" 2>/dev/null \
    | grep '^+' | grep -v '^+++' | sed 's/^+//' | norm \
    | head -n "$MAX_LINES_PER_FILE" | sort -u > "$TMP/added.txt"
  local tot; tot=$(wc -l < "$TMP/added.txt" | tr -d ' ')
  if [ "${tot:-0}" -eq 0 ]; then echo "0 0"; return; fi
  if [ -f "$PROJECT/$f" ]; then
    norm < "$PROJECT/$f" | sort -u > "$TMP/target.txt"
  else
    : > "$TMP/target.txt"
  fi
  local missing; missing=$(comm -23 "$TMP/added.txt" "$TMP/target.txt" 2>/dev/null | wc -l | tr -d ' ')
  echo "$tot ${missing:-0}"
}

verdict_of() {   # $1=tot $2=missing
  if   [ "$1" -eq 0 ];      then echo "deletion_only"; return; fi
  if   [ "$2" -eq 0 ];      then echo "merged_upstream"; return; fi
  if   [ "$2" -eq "$1" ];   then echo "lost"; return; fi
  # 80%+ 미존재 = 사실상 유실 (partial 안에서 '1줄 다름'과 '20/22 없음'을 구분)
  if [ $(( $2 * 100 / $1 )) -ge 80 ]; then echo "mostly_lost"; else echo "partial"; fi
}

NOW_S=$(date +%s)
N_WT=0; N_DIRTY=0; N_AHEAD=0; N_STALE=0; N_LOST=0; N_PARTIAL=0; N_PRUNE=0
WT_JSON=""; PRUNE_JSON=""; LOST_SUMMARY=""
: > "$TMP/touched.txt"   # "<path>\t<branch>" — 동시 수정 충돌 탐지용

while IFS='|' read -r wt br; do
  [ -z "${wt:-}" ] && continue
  case "$wt" in *worktrees*) ;; *) continue ;; esac
  [ -d "$wt" ] || continue
  N_WT=$((N_WT + 1))
  sb="${br#refs/heads/}"
  # ★라벨은 브랜치명이 아니라 **worktree 디렉터리명**을 쓴다.
  #   실측(2026-07-26): frosty-torvalds-5e24f0 디렉터리가 claude/angry-bhabha-b50a41 브랜치를
  #   체크아웃한 상태였고, 브랜치명으로 라벨링하니 "존재하지 않는 worktree"로 보고돼
  #   소멸한 유령처럼 보였다. 디렉터리와 브랜치는 이름이 다를 수 있다 — 한 이름으로 두 정체성을
  #   가리키지 말 것(오늘 반복 적발한 계통).
  short="$(basename "$wt")"
  brshort="$(basename "$sb")"

  ahead=$(git -C "$PROJECT" rev-list --count "${MAIN_REF}..${sb}" 2>/dev/null || echo 0)
  ct=$(git -C "$PROJECT" log -1 --format=%ct "$sb" 2>/dev/null || echo 0)
  age=-1; [ "${ct:-0}" -gt 0 ] && age=$(( (NOW_S - ct) / 86400 ))

  git -C "$wt" --no-optional-locks status --porcelain 2>/dev/null > "$TMP/st.txt" || : > "$TMP/st.txt"
  dirty=$(wc -l < "$TMP/st.txt" | tr -d ' ')

  [ "${ahead:-0}" -gt 0 ] 2>/dev/null && N_AHEAD=$((N_AHEAD + 1))
  [ "${dirty:-0}" -gt 0 ] 2>/dev/null && N_DIRTY=$((N_DIRTY + 1))
  is_stale=0
  if [ "${dirty:-0}" -gt 0 ] 2>/dev/null && [ "${age:-0}" -ge "$STALE_DAYS" ] 2>/dev/null; then
    is_stale=1; N_STALE=$((N_STALE + 1))
  fi

  # ③ prune 후보: 클린 ∧ 미병합 0 → 안전 제거 대상 (자동 제거 안 함 — 후보 보고만)
  if [ "${dirty:-0}" -eq 0 ] 2>/dev/null && [ "${ahead:-0}" -eq 0 ] 2>/dev/null; then
    N_PRUNE=$((N_PRUNE + 1))
    printf '%s\t%s\n' "$wt" "$sb" >> "$TMP/prune.txt"
    [ -n "$PRUNE_JSON" ] && PRUNE_JSON="$PRUNE_JSON,"
    PRUNE_JSON="$PRUNE_JSON
      {\"branch\":\"$(jesc "$sb")\",\"path\":\"$(jesc "$wt")\",\"age_days\":$age}"
  fi

  # ── 파일 단위 triage
  FILES_JSON=""; wt_lost=0; wt_partial=0
  while read -r code path; do
    [ -z "${path:-}" ] && continue
    case "$code" in
      "??")   # untracked — main 존재/동일 여부로 판정
        if [ ! -e "$PROJECT/$path" ]; then v="lost"; tot=1; miss=1
        elif diff -q "$PROJECT/$path" "$wt/$path" >/dev/null 2>&1; then v="merged_upstream"; tot=1; miss=0
        else v="partial"; tot=1; miss=1; fi
        ;;
      D|*D*)  v="deletion_only"; tot=0; miss=0 ;;
      *)
        read -r tot miss <<< "$(triage_file "$wt" "$path")"
        v="$(verdict_of "${tot:-0}" "${miss:-0}")"
        ;;
    esac
    case "$v" in
      lost|mostly_lost) wt_lost=$((wt_lost + 1)); N_LOST=$((N_LOST + 1)) ;;
      partial)          wt_partial=$((wt_partial + 1)); N_PARTIAL=$((N_PARTIAL + 1)) ;;
    esac
    printf '%s\t%s\n' "$path" "$short" >> "$TMP/touched.txt"
    [ -n "$FILES_JSON" ] && FILES_JSON="$FILES_JSON,"
    FILES_JSON="$FILES_JSON
        {\"path\":\"$(jesc "$path")\",\"state\":\"$(jesc "$code")\",\"added_lines\":${tot:-0},\"missing_in_main\":${miss:-0},\"verdict\":\"$v\"}"
  done < <(awk '{c=$1; $1=""; sub(/^ /,""); print c" "$0}' "$TMP/st.txt")

  # 미병합 커밋이 건드린 파일도 충돌 후보에 포함 (커밋됐어도 main엔 없으므로 동일 위험)
  if [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
    git -C "$PROJECT" diff --name-only "${MAIN_REF}...${sb}" 2>/dev/null \
      | while read -r cf; do [ -n "$cf" ] && printf '%s\t%s\n' "$cf" "$short" >> "$TMP/touched.txt"; done
  fi

  if [ "$wt_lost" -gt 0 ]; then
    LOST_SUMMARY="${LOST_SUMMARY}${short}(${wt_lost}건·${age}일) "
  fi

  if [ "${dirty:-0}" -gt 0 ] 2>/dev/null || [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
    [ -n "$WT_JSON" ] && WT_JSON="$WT_JSON,"
    WT_JSON="$WT_JSON
    {
      \"worktree\":\"$(jesc "$short")\",
      \"branch\":\"$(jesc "$sb")\",
      \"path\":\"$(jesc "$wt")\",
      \"ahead_of_main\":${ahead:-0},
      \"dirty_files\":${dirty:-0},
      \"last_commit_age_days\":$age,
      \"stale\":$([ "$is_stale" -eq 1 ] && echo true || echo false),
      \"lost\":$wt_lost,
      \"partial\":$wt_partial,
      \"files\":[${FILES_JSON}
      ]
    }"
    say "  $([ "$is_stale" -eq 1 ] && echo '[방치' || echo '[활동') ${age}d] $short — 미커밋 ${dirty} / 미병합 ${ahead} / 유실 ${wt_lost} / 부분 ${wt_partial}"
  fi
done < <(git -C "$PROJECT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{w=$2} /^branch /{print w"|"$2}')

# ── 동시 수정 충돌 탐지: 2개 이상 worktree가 같은 파일을 main 밖에서 건드리는 중
#    병합 순서를 정하지 않으면 뒤에 병합되는 쪽이 앞을 덮거나 충돌한다.
COLL_JSON=""; N_COLL=0; COLL_SUMMARY=""
if [ -s "$TMP/touched.txt" ]; then
  sort -u "$TMP/touched.txt" | awk -F'\t' '{a[$1]=a[$1]" "$2; n[$1]++} END{for(p in n) if(n[p]>1) print p"\t"n[p]"\t"a[p]}' \
    | sort > "$TMP/coll.txt"
  while IFS=$'\t' read -r cpath cnt brs; do
    [ -z "${cpath:-}" ] && continue
    N_COLL=$((N_COLL + 1))
    BR_JSON=""
    for b in $brs; do
      [ -n "$BR_JSON" ] && BR_JSON="$BR_JSON,"
      BR_JSON="$BR_JSON\"$(jesc "$b")\""
    done
    [ -n "$COLL_JSON" ] && COLL_JSON="$COLL_JSON,"
    COLL_JSON="$COLL_JSON
      {\"path\":\"$(jesc "$cpath")\",\"worktree_count\":$cnt,\"branches\":[$BR_JSON]}"
    COLL_SUMMARY="${COLL_SUMMARY}$(basename "$cpath")(${cnt}) "
  done < "$TMP/coll.txt"
fi
[ "$N_COLL" -gt 0 ] && say "  ★ 동시 수정 충돌 후보 ${N_COLL}건: ${COLL_SUMMARY}"

# ── 레지스트리 기록
mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<JSON
{
  "_doc": "좌초 수리 감사 — worktree에 갇혀 main에 도달하지 못한 수리 탐지. 생성기 02_Infrastructure/ops/stranded_repairs_audit.sh. verdict: merged_upstream=worktree가 stale 사본(정리 가능) / lost=main에 전무(조치 필요) / mostly_lost=80%+ 미존재(사실상 유실) / partial=일부만 반영(수동 확인) / deletion_only=삭제만. collisions=2개 이상 worktree가 같은 파일을 main 밖에서 수정 중(병합 순서 결정 필요).",
  "generated_at": "$(date '+%Y-%m-%d %H:%M:%S')",
  "main_ref": "$(jesc "$MAIN_REF")",
  "stale_threshold_days": $STALE_DAYS,
  "summary": {
    "worktrees_total": $N_WT,
    "with_uncommitted": $N_DIRTY,
    "with_unmerged": $N_AHEAD,
    "stale_over_threshold": $N_STALE,
    "files_lost": $N_LOST,
    "files_partial": $N_PARTIAL,
    "collisions": $N_COLL,
    "prune_candidates": $N_PRUNE
  },
  "worktrees": [${WT_JSON}
  ],
  "collisions": [${COLL_JSON}
  ],
  "prune_candidates": [${PRUNE_JSON}
  ]
}
JSON

say ""
hb "worktree ${N_WT} · 미커밋 ${N_DIRTY} · 미병합 ${N_AHEAD} · ${STALE_DAYS}일+ 방치 ${N_STALE} | 유실 ${N_LOST} · 부분 ${N_PARTIAL} · 충돌 ${N_COLL} · prune후보 ${N_PRUNE}"
[ "$N_LOST" -gt 0 ] && hb "★ 유실 대상: ${LOST_SUMMARY}"
[ "$N_COLL" -gt 0 ] && hb "★ 동시수정 충돌: ${COLL_SUMMARY}"
say "[stranded] → $OUT"

# ── ③ worktree 생명주기: prune 후보 정리 (--prune 명시 시에만 실제 제거)
#    조건: 미커밋 0 ∧ 미병합 0 (= 작업이 전부 main에 있음). git worktree remove 는 dirty면 자체 거부 = 2중 안전.
#    자동 실행 금지 — 활동 중 세션의 worktree를 지우면 그 세션이 깨진다. 반드시 수동 판단.
if [ "$DO_PRUNE" -eq 1 ]; then
  if [ ! -s "$TMP/prune.txt" ]; then
    say "[stranded] prune: 후보 없음"
  else
    say ""
    say "[stranded] prune 실행 — 후보 ${N_PRUNE}건 (미커밋 0 ∧ 미병합 0)"
    PRUNED=0; PFAIL=0
    while IFS=$'\t' read -r pwt pbr; do
      [ -z "${pwt:-}" ] && continue
      if git -C "$PROJECT" worktree remove "$pwt" 2>"$TMP/prune_err.txt"; then
        PRUNED=$((PRUNED + 1)); say "    제거: $(basename "$pbr")"
      else
        PFAIL=$((PFAIL + 1)); say "    실패: $(basename "$pbr") — $(head -1 "$TMP/prune_err.txt" 2>/dev/null)"
      fi
    done < "$TMP/prune.txt"
    git -C "$PROJECT" worktree prune 2>/dev/null || true
    say "[stranded] prune 완료 — 제거 ${PRUNED} / 실패 ${PFAIL}"
  fi
else
  [ "$N_PRUNE" -gt 0 ] && say "[stranded] prune 후보 ${N_PRUNE}건 — 제거하려면 --prune (자동 실행 안 함)"
fi

# ── 텔레그램 경보: 유실 또는 충돌 후보가 있을 때. 같은 날 1회 스로틀.
if [ "$DO_TG" -eq 1 ] && { [ "$N_LOST" -gt 0 ] || [ "$N_COLL" -gt 0 ]; }; then
  TODAY=$(date +%Y%m%d)
  MARK="$PROJECT/.cache/stranded_alert_${TODAY}.marker"
  if [ -f "$MARK" ]; then
    say "[stranded] 텔레그램 skip — 오늘 이미 발송 (스로틀)"
  else
    RS_BIN="$(command -v Rscript || true)"
    if [ -z "$RS_BIN" ]; then
      say "[stranded] 텔레그램 skip — Rscript 없음 (레지스트리는 기록됨)"
    else
      mkdir -p "$PROJECT/.cache"
      printf 'generated=%s\nlost=%s\nstale=%s\n' "$(date '+%F %T')" "$N_LOST" "$N_STALE" > "$MARK"
      RFILE="$TMP/_tg_stranded.R"
      cat > "$RFILE" <<RS
suppressWarnings(suppressMessages({
  root <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
  source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R"))
}))
invisible(tryCatch(tg_agent_brief(
  agent = "Q-Lead",
  title = "좌초 수리 경보 — worktree 미반영 감지",
  relaxed = TRUE, force = TRUE,
  lock_scope = "stranded_repairs_${TODAY}",
  sections = list(
    list(type = "summary", emoji = "\U0001F6A8",
         body = "병렬 세션 worktree에 갇혀 main에 도달하지 못한 수리가 ${N_LOST}건 감지됐습니다. 세션이 끝나면 유실됩니다."),
    list(type = "bullet", emoji = "\U0001F4A1", heading = "쉬운 설명",
         items = c("다른 작업 공간에서 고친 코드가 본진에 합쳐지지 않은 상태입니다",
                   "같은 사고가 과거 2번 있었고 둘 다 일주일 가까이 방치됐습니다",
                   "판정이 유실이면 본진에 그 내용이 아예 없다는 뜻입니다")),
    list(type = "kv", emoji = "\U0001F4CB", heading = "상세",
         kv = list("유실 파일" = "${N_LOST}",
                   "부분 반영" = "${N_PARTIAL}",
                   "방치 worktree" = "${N_STALE}",
                   "대상" = "${LOST_SUMMARY}",
                   "레지스트리" = "06_Registry/stranded_repairs.json"))
  )
), error = function(e) cat("tg fail:", conditionMessage(e), "\n")))
RS
      "$RS_BIN" "$RFILE" >/dev/null 2>&1 && say "[stranded] 텔레그램 발송 시도 완료" || say "[stranded] 텔레그램 실패 (마커·레지스트리는 보존)"
    fi
  fi
fi

exit 0
