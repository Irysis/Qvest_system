#!/usr/bin/env bash
# test_qvest_machine.sh — qvest_machine.sh 메인 우선 게이트 · 동기화 안정 판정 검사 (2026-11-01)
# 축: 역할 · main/secondary 게이트 판정 · 생존 신호(jobs 목록 포함) · local/잘못된 period · done 기록 · settled
#   (양성 대조 = 속성 마스크 주입 · 충돌 사본 주입 · 대량 삭제 주입 — 발화가 실증돼야 방어선으로 센다)
# 상태 디렉터리 · 설정 · 저장소는 전부 임시 폴더 — 공유 트리(.cache/machine)에 쓰지 않는다.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
QM="$HERE/../../02_Infrastructure/ops/machine/qvest_machine.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
ng() { fail=$((fail + 1)); echo "FAIL $1"; }
expect() { [ "$2" = "$3" ] && ok "$1" || ng "$1 (want=$2 got=$3)"; }

export QVEST_MACHINE_DIR="$T/m" QVEST_MACHINE_CONF="$T/machines.conf" QVEST_JOBS_DIR="$T/jobs"
export QVEST_GATE_SETTLE_SEC=0 QVEST_GATE_GRACE_SEC=0 QVEST_GATE_WAKE_SEC=0
unset QVEST_MACHINE_ROLE QVEST_GATE_FORCE QVEST_SETTLE_CHECK QVEST_SETTLE_ATTR_MASK QVEST_SETTLE_MAX_DELETED
printf 'machine MAINPC main\nmachine LAPTOP secondary\nperiod JobLocal local\n' > "$T/machines.conf"
mkdir -p "$T/jobs"; : > "$T/jobs/JobA.cmd"; : > "$T/jobs/JobN.cmd"
qm() { bash "$QM" "$@" >/dev/null 2>&1; echo $?; }
as() { local h="$1"; shift; QVEST_HOST="$h" bash "$QM" "$@" >/dev/null 2>&1; echo $?; }

# 0. 카나리아 — 검사 대상이 실제로 도는가 (죽은 검사기의 rc 가 기대값과 겹치지 않게 먼저 끊는다)
if [ "$(QVEST_HOST=MAINPC bash "$QM" role 2>/dev/null)" != "main" ]; then
  echo '{"pass":0,"fail":1,"preflight":"role_canary"}'; exit 1
fi

# 1. 역할
expect role_main      main      "$(QVEST_HOST=mainpc bash "$QM" role)"
expect role_listed    secondary "$(QVEST_HOST=LAPTOP bash "$QM" role)"
expect role_unlisted  secondary "$(QVEST_HOST=OTHER bash "$QM" role)"
expect role_override  main      "$(QVEST_HOST=OTHER QVEST_MACHINE_ROLE=main bash "$QM" role)"

# 2. main — 표식 없으면 실행 + 표식, 다른 기계 표식 있으면 건너뜀
expect main_run       0  "$(as MAINPC gate JobA day)"
[ -f "$T/m/runs/JobA__$(date +%Y-%m-%d)__MAINPC.txt" ] && ok main_claim_written || ng main_claim_written
expect sec_after_main 10 "$(as LAPTOP gate JobA day)"
expect sec_absent_run 0  "$(as LAPTOP gate JobB day)"
expect main_after_sec 10 "$(as MAINPC gate JobB day)"
expect main_rerun_own 0  "$(as MAINPC gate JobA day)"

# 3. 생존 신호 — main 만 쓴다, period=none 은 메인이 맡으면 건너뜀
expect hb_refuse_sec  2  "$(as LAPTOP heartbeat)"
expect hb_main        0  "$(as MAINPC heartbeat)"
grep -q 'jobs=JobA,JobN' "$T/m/heartbeat_main.txt" && ok hb_jobs_listed || ng hb_jobs_listed
expect none_covered   10 "$(as LAPTOP gate JobN none)"
expect none_not_job   0  "$(as LAPTOP gate JobZ none)"
expect keyed_unclaimed_alive 0 "$(as LAPTOP gate JobA week)"
sed -i "s/epoch=[0-9]*/epoch=$(( $(date +%s) - 5000 ))/" "$T/m/heartbeat_main.txt"
expect none_stale     0  "$(as LAPTOP gate JobN none)"
# 메인이 방금 깨어남(생존 신호 오래됨) → woke 갱신
as MAINPC heartbeat >/dev/null
w="$(sed -n 's/.*woke=\([0-9]*\).*/\1/p' "$T/m/heartbeat_main.txt")"; e="$(sed -n 's/.*epoch=\([0-9]*\).*/\1/p' "$T/m/heartbeat_main.txt")"
expect hb_woke_reset  "$e" "$w"

# 4. local · 잘못된 period · 강제
expect local_main     0  "$(as MAINPC gate JobLocal day)"
expect local_sec      0  "$(as LAPTOP gate JobLocal day)"
ls "$T/m/runs/" | grep -q '^JobLocal__' && ng local_no_claim || ok local_no_claim
expect bad_period     0  "$(as LAPTOP gate JobQ fortnight)"
expect force_sec      0  "$(QVEST_GATE_FORCE=1 QVEST_HOST=LAPTOP bash "$QM" gate JobA day >/dev/null 2>&1; echo $?)"

# 5. done — 표식에 끝 기록
as MAINPC done JobA day 7 >/dev/null
grep -q 'rc=7' "$T/m/runs/JobA__$(date +%Y-%m-%d)__MAINPC.txt" && ok done_appended || ng done_appended

# 6. settled — 정상 / 속성 마스크 주입(ARCHIVE 0x20 = 새 파일 기본 속성) / 충돌 사본 / 대량 삭제
R="$T/repo"; mkdir -p "$R"
( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
  && for i in 1 2 3; do echo "$i" > "f$i.txt"; done && git add . && git commit -qm init ) >/dev/null 2>&1
expect settled_clean  0 "$(qm settled "$R")"
expect settled_mask   1 "$(QVEST_SETTLE_ATTR_MASK=0x20 bash "$QM" settled "$R" >/dev/null 2>&1; echo $?)"
b="$(git -C "$R" branch --show-current)"
cp "$R/.git/refs/heads/$b" "$R/.git/refs/heads/$b-Laptop-2"
expect settled_conflict 1 "$(qm settled "$R")"
rm -f "$R/.git/refs/heads/$b-Laptop-2"
cp "$R/.git/index" "$R/.git/index-MainPC"
expect settled_conflict_top 1 "$(qm settled "$R")"
rm -f "$R/.git/index-MainPC"
rm -f "$R/f1.txt" "$R/f2.txt"
expect settled_deleted_over 1 "$(QVEST_SETTLE_MAX_DELETED=1 bash "$QM" settled "$R" >/dev/null 2>&1; echo $?)"
expect settled_deleted_ok   0 "$(qm settled "$R")"
expect settled_off          0 "$(QVEST_SETTLE_CHECK=0 QVEST_SETTLE_ATTR_MASK=0x20 bash "$QM" settled "$R" >/dev/null 2>&1; echo $?)"
echo "migration test" > "$T/m/hold_TESTPC"
expect settled_hold         1 "$(QVEST_HOST=TESTPC bash "$QM" settled "$R" >/dev/null 2>&1; echo $?)"
expect settled_hold_other   0 "$(QVEST_HOST=OTHERPC bash "$QM" settled "$R" >/dev/null 2>&1; echo $?)"
rm -f "$T/m/hold_TESTPC"; mkdir -p "$R/.cache/machine"; echo x > "$R/.cache/machine/hold_TESTPC"
expect settled_hold_repo    1 "$(QVEST_HOST=TESTPC bash "$QM" settled "$R" >/dev/null 2>&1; echo $?)"

echo "{\"pass\":$pass,\"fail\":$fail}"
[ "$fail" -eq 0 ]
