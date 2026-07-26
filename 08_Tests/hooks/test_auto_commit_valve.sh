#!/usr/bin/env bash
#==============================================================================
# test_auto_commit_valve.sh — auto_commit_on_stop.sh 대량-신규 격리 밸브 v2 검증
#
# 배경(2026-07-26): v1 밸브(NEW>100 → 코어경로만)가 누적 untracked 백로그를 재는
#   측정 결함으로 영구 개방(CORE_ONLY_STAGED 171회) → git reset이 M/D까지 쓸어
#   코어 밖 전부가 영구 미커밋. v2 = 디렉터리-단위 A-only 격리로 재설계.
#
# 검증 축 (sandbox git repo에서 훅 전체를 실 구동 — 로직 재현이 아니라 실물 실행):
#   T1  단일-디렉터리 bulk → 그 디렉터리 A만 격리, M/D + 소량 A는 커밋, 원장 기록
#   T2  확산형(총량>문턱, 단일-dir 집중 없음) → 격리 없이 전량 커밋 (v1 과잉처벌 제거 확인)
#   T3  ★이빨: 문턱 무력화(=100000) 시 T1과 같은 입력이 전량 커밋 —
#       T1의 '격리됨' assertion이 밸브 기전에서 나온 것임을 실증 (죽은 검사 방지)
#   T4  secret abort 보존 — 추적 파일에 토큰 패턴 주입 시 커밋 0 (회귀 방지)
#   T5  문턱 이하 → 전량 커밋 + 원장 부재
#   T6  원장 자동 소등 — 격리 후 수동 드레인 → 다음 훅 실행에서 원장 제거
#
# 요약 규약: 마지막 줄 {"test":"auto_commit_valve","pass":N,"fail":N,"total":N}
#==============================================================================
set -u

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$_SELF_DIR/../../02_Infrastructure/hooks/auto_commit_on_stop.sh"
if [ ! -f "$HOOK" ]; then
  echo "FATAL: hook 부재: $HOOK"
  echo '{"test":"auto_commit_valve","pass":0,"fail":1,"total":1}'
  exit 1
fi

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1  ($2)"; }
chk()  { # chk <이름> <기대> <실제>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expect=$2 actual=$3"; fi
}

SANDBOXES=()
cleanup() { for s in ${SANDBOXES[@]+"${SANDBOXES[@]}"}; do rm -rf "$s" 2>/dev/null || true; done; }
trap cleanup EXIT

new_repo() { # stdout = sandbox 경로. 추적 파일 2 + base 커밋 + .cache(.gitignore로 실환경 미러)
  local sb; sb=$(mktemp -d)
  SANDBOXES+=("$sb")
  git -C "$sb" init -q
  git -C "$sb" config user.email "test@qvest.local"
  git -C "$sb" config user.name  "valve-test"
  git -C "$sb" config commit.gpgsign false
  echo ".cache/" > "$sb/.gitignore"          # 실저장소 정합: .cache는 비추적
  echo "base1" > "$sb/tracked1.txt"; echo "base2" > "$sb/tracked2.txt"
  git -C "$sb" add -A; git -C "$sb" commit -qm "base"
  mkdir -p "$sb/.cache" "$sb.meta"           # 훅 부산물(log/marker/stderr)은 repo 밖 .meta로
  SANDBOXES+=("$sb.meta")
  printf '%s' "$sb"
}

run_hook() { # $1=sandbox [$2=threshold override]
  # ★env 경유 필수: `${thr:+VAR=x} cmd` 꼴은 확장 결과가 할당-워드로 인식되지 않아
  #   (assignment는 파싱 시점 리터럴이어야 함) 훅이 아예 실행되지 않는다 — 초판 T3 실측.
  local sb="$1" thr="${2:-}"
  echo '{}' | env QVEST_AC_PROJECT="$sb" QVEST_AC_LOG="$sb.meta/ac.log" \
    QVEST_AC_MARKER="$sb.meta/ac.marker" QVEST_SKIP_AUTO_COMMIT=0 \
    ${thr:+QVEST_AC_BULK_THRESHOLD="$thr"} bash "$HOOK" 2>>"$sb.meta/ac.stderr"
}

n_commits()    { git -C "$1" rev-list --count HEAD 2>/dev/null; }
n_untracked()  { git -C "$1" status --porcelain -uall | grep -c '^??' || true; }   # -uall: 디렉터리 접힘 방지
n_untr_under() { git -C "$1" status --porcelain -uall | grep -c "^?? $2" || true; }
in_head()      { git -C "$1" show --name-status --format="" HEAD | grep -c "$2" || true; }

mk_bulk_shape() { # T1/T3 공용 입력: bulk/ 120 A + small/ 3 A + tracked1 M + tracked2 D
  local sb="$1"
  mkdir -p "$sb/bulk" "$sb/small"
  for i in $(seq 1 120); do echo "$i" > "$sb/bulk/f$i.json"; done
  for i in 1 2 3; do echo "$i" > "$sb/small/s$i.txt"; done
  echo "modified" >> "$sb/tracked1.txt"
  rm -f "$sb/tracked2.txt"
}

echo "=== test_auto_commit_valve (밸브 v2) ==="

# ── T1. 단일-디렉터리 bulk 격리 ──────────────────────────────────────────────
SB=$(new_repo); mk_bulk_shape "$SB"
OUT=$(run_hook "$SB")
chk "T1 커밋 발생 (base+1)"            "2"   "$(n_commits "$SB")"
chk "T1 M(tracked1) 커밋됨"            "1"   "$(in_head "$SB" 'tracked1')"
chk "T1 D(tracked2) 커밋됨"            "1"   "$(in_head "$SB" 'tracked2')"
chk "T1 소량 A(small/) 커밋됨"          "3"   "$(in_head "$SB" 'small/')"
chk "T1 bulk/ 커밋 제외"               "0"   "$(in_head "$SB" 'bulk/')"
chk "T1 bulk/ 120건 untracked 잔존"    "120" "$(n_untr_under "$SB" 'bulk/')"
if [ -f "$SB/.cache/auto_commit_quarantine.json" ] && grep -q '"dir":"bulk"' "$SB/.cache/auto_commit_quarantine.json" \
   && grep -q '"n_new":120' "$SB/.cache/auto_commit_quarantine.json"; then
  ok "T1 원장 기록 (bulk, 120)"
else
  bad "T1 원장 기록 (bulk, 120)" "ledger=$(cat "$SB/.cache/auto_commit_quarantine.json" 2>/dev/null | head -c 200)"
fi
case "$OUT" in *QUARANTINE*) ok "T1 additionalContext에 격리 표기" ;; *) bad "T1 additionalContext에 격리 표기" "out=${OUT:0:120}" ;; esac
T1_SB="$SB"   # T6에서 재사용

# ── T2. 확산형 유기 산출 = 격리 없음 ─────────────────────────────────────────
SB=$(new_repo)
for d in $(seq 1 12); do mkdir -p "$SB/dir$d"; for i in $(seq 1 10); do echo x > "$SB/dir$d/f$i.txt"; done; done
run_hook "$SB" > /dev/null
chk "T2 확산형 120A 전량 커밋"          "2" "$(n_commits "$SB")"
chk "T2 untracked 잔존 0"              "0" "$(n_untracked "$SB")"
chk "T2 원장 부재"                     "no" "$([ -f "$SB/.cache/auto_commit_quarantine.json" ] && echo yes || echo no)"

# ── T3. ★이빨 — 문턱 무력화 시 같은 입력이 전량 커밋 ─────────────────────────
SB=$(new_repo); mk_bulk_shape "$SB"
run_hook "$SB" 100000 > /dev/null
chk "T3 이빨: 밸브 off 시 bulk/ 커밋됨" "120" "$(in_head "$SB" 'bulk/')"
chk "T3 이빨: untracked 0"             "0"   "$(n_untracked "$SB")"

# ── T4. secret abort 보존 ────────────────────────────────────────────────────
SB=$(new_repo)
# 토큰을 소스에 리터럴로 남기지 않도록 런타임 조립 (저장소 secret 스캔 자기-오염 방지)
FAKE_TOKEN="bot123456789"":A""$(printf 'x%.0s' $(seq 1 40))"
echo "tg = \"$FAKE_TOKEN\"" >> "$SB/tracked1.txt"
OUT=$(run_hook "$SB")
chk "T4 secret 시 커밋 0"              "1" "$(n_commits "$SB")"
case "$OUT" in *Secret*|*SECRET*) ok "T4 additionalContext에 secret 경고" ;; *) bad "T4 additionalContext에 secret 경고" "out=${OUT:0:120}" ;; esac

# ── T5. 문턱 이하 전량 커밋 + 원장 부재 ──────────────────────────────────────
SB=$(new_repo)
mkdir -p "$SB/few"; for i in 1 2 3 4 5; do echo x > "$SB/few/f$i.txt"; done
echo mod >> "$SB/tracked1.txt"
run_hook "$SB" > /dev/null
chk "T5 소량 전량 커밋"                "2" "$(n_commits "$SB")"
chk "T5 untracked 0"                   "0" "$(n_untracked "$SB")"
chk "T5 원장 부재"                     "no" "$([ -f "$SB/.cache/auto_commit_quarantine.json" ] && echo yes || echo no)"

# ── T6. 원장 자동 소등 — 드레인 후 다음 실행에서 제거 ────────────────────────
git -C "$T1_SB" add bulk/ && git -C "$T1_SB" commit -qm "drain"
echo "post-drain" >> "$T1_SB/tracked1.txt"
run_hook "$T1_SB" > /dev/null
chk "T6 드레인 후 원장 자동 제거"       "no" "$([ -f "$T1_SB/.cache/auto_commit_quarantine.json" ] && echo yes || echo no)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"auto_commit_valve\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
