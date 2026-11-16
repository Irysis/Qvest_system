#!/usr/bin/env bash
#==============================================================================
# run_1116_locked.sh — 이음매 묶음(RAWDATA-7ROWS-CORPACTION-REQUERY-20261115)을 RAWDATA writer 잠금 아래 한 번에 (2026-11-16)
#   상장 전 행 삭제(RAWDATA-PRELISTING-EXCLUDE-20261116)와 판 원장 줄은 11-16 10:39 qw_login_chain.sh 가 이미 했다
#   (02_Infrastructure/data/rawdata_listing_cut.py --apply --backup · 원장 줄 = 진행 중) — 이 스크립트는 묶음만 싣는다.
#
# 순서(어느 단계든 실패하면 멈춘다):
#   ① 묶음 명세 재생성(적용 전 저장값 단정이 멈춤 장치 · 첫 행이 된 고정 2행은 SKIP_PINS)
#   ② 등록부에 묶음 6행 붙이기(값 변경 3 + 고정 3 · 기존 14행 그대로)
#   ③ seam_repair_locked.sh --apply(등록부 강제로 값 변경 3행 · 같은 잠금 보유자의 자손 = 배리어 self) — 실패하면 등록부를 ② 전 바이트로 되돌린다
# ★팩터 DB 재빌드가 도는 동안에는 돌리지 않는다(재빌드 도중 RAWDATA 가 바뀐다) — 1계층 세션과 시점을 맞춘 뒤.
# 사용: bash run_1116_locked.sh   (리프레시 잠금이 잡혀 있으면 시작하지 않는다 · 종료 10)
#==============================================================================
set -u
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
cd "$ROOT" || exit 1
PY=".venv_qvest_ml/Scripts/python.exe"
T="04_Research/01_reports/rawdata_prelisting_exclude_20261116/tools"
D2="04_Research/01_reports/rawdata_seam_20260330_repair_20261113/d2_fill"
REG="06_Registry/ret_fill_registry.json"
# shellcheck source=/dev/null
source 02_Infrastructure/ops/refresh_barrier.sh
rb_status
if [ "${RB_STATE:-}" = "held" ]; then rb_line; echo "[1116] 배리어 held — 적재 · 리프레시 · 다른 writer 중이라 시작하지 않는다"; exit 10; fi
rb_writer_acquire "seam_bundle_1116" || { echo "[1116] writer 잠금 획득 실패"; exit 11; }
trap 'rb_writer_release' EXIT
echo "[1116] writer 잠금 보유(pid $$) — $(date '+%F %T')"
step() { echo; echo "[1116] ── $1 — $(date '+%T')"; }

step "① 묶음 명세 재생성"
"$PY" -X utf8 "$D2/tools/bundle_1115_build.py" "$D2" || { echo "[1116] ① 실패 — 멈춤(무변경)"; exit 1; }

step "② 등록부에 묶음 6행"
REG_BAK="$(mktemp)"; cp "$REG" "$REG_BAK"
"$PY" -X utf8 "$T/registry_1116_apply.py" --apply || { echo "[1116] ② 실패 — 멈춤(무변경)"; exit 1; }

step "③ 이음매 묶음 적용(seam_repair_locked.sh --apply)"
bash 02_Infrastructure/data/seam_repair_locked.sh --apply
src=$?
if [ "$src" != "0" ] && [ "$src" != "3" ]; then
  cp "$REG_BAK" "$REG" && echo "[1116] ③ 실패 rc=$src — 등록부를 ② 전 바이트로 되돌렸다 · 멈춤"
  exit 1
fi
echo; echo "[1116] 끝 — 묶음 적용 rc=$src · 잠금 해제 $(date '+%F %T')"
