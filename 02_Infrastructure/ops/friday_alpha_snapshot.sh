#!/bin/bash
#==============================================================================
# Friday Alpha Snapshot — 주간 Alpha 스냅샷 (v54 Freeze Period)
#
# 매주 금요일 18:00 KST 실행. v54 Freeze 해제 후에도 유지 가능.
#
# 기능:
#   1. portfolio_gap_vector.json → 현 SR/CAGR/MDD/gap 추출
#   2. Governor rev count (outbox rev 파일 수)
#   3. S0 hit rate (최근 7일 APPROVE/REVISE/REJECT 비율)
#   4. 텔레그램 발송 (이모지 + 한글 + 섹션 포맷)
#   5. JSON 스냅샷 저장: 06_Registry/snapshots/friday_alpha_snapshot_YYYY-MM-DD.json
#
# 사용법:
#   bash friday_alpha_snapshot.sh             # 정상 실행 (텔레그램 발송)
#   FRIDAY_SNAPSHOT_DRYRUN=1 bash friday_alpha_snapshot.sh  # dry-run (발송 skip)
#
# crontab 제안 (Q-Lead 승인 필요):
#   0 9 * * 5 cd /mnt/c/Users/User/OneDrive/바탕\ 화면/Quant_Module_Moltbot && bash 02_Infrastructure/ops/friday_alpha_snapshot.sh >> /tmp/friday_snapshot.log 2>&1
#   (UTC 09:00 = KST 18:00 금요일)
#
# 관련: CLAUDE.md v54 Freeze Period, 00_Lawbook/v54_freeze_period_enforcement.md
#==============================================================================

set -euo pipefail

PROJ=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
if [ -z "$PROJ" ]; then
  echo "ERROR: 프로젝트 루트를 찾을 수 없습니다."
  exit 1
fi

DRYRUN="${FRIDAY_SNAPSHOT_DRYRUN:-0}"
TODAY_KST=$(TZ="Asia/Seoul" date +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
SNAPSHOT_DIR="$PROJ/06_Registry/snapshots"
SNAPSHOT_FILE="$SNAPSHOT_DIR/friday_alpha_snapshot_${TODAY_KST}.json"

mkdir -p "$SNAPSHOT_DIR"

echo "=== Friday Alpha Snapshot: $TODAY_KST ==="
echo "DRYRUN=$DRYRUN"

# ══════════════════════════════════════════════════════════════════════
# 1. Portfolio Gap Vector 추출
# ══════════════════════════════════════════════════════════════════════
GAP_JSON="$PROJ/.cache/portfolio_gap_vector.json"
SR="N/A"; CAGR="N/A"; MDD="N/A"; GAP_SR="N/A"; GAP_CAGR="N/A"; GAP_MDD="N/A"

if [ -f "$GAP_JSON" ]; then
  eval "$(python3 -c "
import json, sys
try:
  d = json.load(open('$GAP_JSON'))
  curr = d.get('current', {})
  gap = d.get('gap', {})
  print(f'SR={curr.get(\"sharpe\", \"N/A\")}')
  print(f'CAGR={curr.get(\"cagr\", \"N/A\")}')
  print(f'MDD={curr.get(\"mdd\", \"N/A\")}')
  print(f'GAP_SR={gap.get(\"sharpe\", \"N/A\")}')
  print(f'GAP_CAGR={gap.get(\"cagr\", \"N/A\")}')
  print(f'GAP_MDD={gap.get(\"mdd\", \"N/A\")}')
except Exception as e:
  print(f'# gap_vector parse error: {e}', file=sys.stderr)
" 2>/dev/null)" || true
  echo "Portfolio: SR=$SR CAGR=$CAGR MDD=$MDD"
else
  echo "WARNING: portfolio_gap_vector.json 없음"
fi

# ══════════════════════════════════════════════════════════════════════
# 2. Governor Rev Count
# ══════════════════════════════════════════════════════════════════════
GOV_OUTBOX="$PROJ/qepm/mailbox/governor/outbox"
GOV_REV_COUNT=0
GOV_REV_TOTAL=0
FREEZE_START="2026-04-18"

if [ -d "$GOV_OUTBOX" ]; then
  GOV_REV_TOTAL=$(find "$GOV_OUTBOX" -maxdepth 1 -name "*rev*" -type f 2>/dev/null | wc -l)
  # Freeze 기간 내 생성된 rev만 카운트 (mtime 기반)
  GOV_REV_COUNT=$(find "$GOV_OUTBOX" -maxdepth 1 -name "*rev*" -type f -newermt "$FREEZE_START" 2>/dev/null | wc -l || echo 0)
fi
echo "Governor: total_revs=$GOV_REV_TOTAL freeze_period_revs=$GOV_REV_COUNT"

# ══════════════════════════════════════════════════════════════════════
# 3. S0 Hit Rate (최근 7일)
# ══════════════════════════════════════════════════════════════════════
ARTIFACTS="$PROJ/stage_artifacts"
S0_APPROVE=0; S0_REVISE=0; S0_REJECT=0; S0_TOTAL=0; S0_HIT_RATE="N/A"

if [ -d "$ARTIFACTS" ]; then
  # 최근 7일 이내 S0_VERDICT 파일
  CUTOFF=$(date -d "7 days ago" +%s 2>/dev/null || date -v-7d +%s 2>/dev/null || echo 0)

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    MTIME=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    if [ "$MTIME" -ge "$CUTOFF" ] 2>/dev/null; then
      VERDICT=$(python3 -c "
import json, sys
try:
  d = json.load(open('$f'))
  print(d.get('verdict', d.get('decision', 'UNKNOWN')).upper())
except: print('UNKNOWN')
" 2>/dev/null || echo "UNKNOWN")
      case "$VERDICT" in
        *APPROVE*) S0_APPROVE=$((S0_APPROVE + 1)) ;;
        *REVISE*)  S0_REVISE=$((S0_REVISE + 1)) ;;
        *REJECT*)  S0_REJECT=$((S0_REJECT + 1)) ;;
      esac
      S0_TOTAL=$((S0_TOTAL + 1))
    fi
  done < <(find "$ARTIFACTS" -maxdepth 1 -name "S0_VERDICT_*.json" -type f 2>/dev/null)

  if [ "$S0_TOTAL" -gt 0 ]; then
    S0_HIT_RATE=$(python3 -c "print(f'{$S0_APPROVE/$S0_TOTAL*100:.1f}%')" 2>/dev/null || echo "N/A")
  fi
fi
echo "S0 Hit Rate: $S0_APPROVE/$S0_TOTAL approve ($S0_HIT_RATE), revise=$S0_REVISE, reject=$S0_REJECT"

# ══════════════════════════════════════════════════════════════════════
# 4. Freeze 준수 상태
# ══════════════════════════════════════════════════════════════════════
FREEZE_VIOLATIONS=$(cat /tmp/v54_freeze_guard.log 2>/dev/null | grep -c "BLOCK" || echo 0)
FREEZE_OVERRIDES=$(cat /tmp/v54_freeze_guard.log 2>/dev/null | grep -c "OVERRIDE" || echo 0)

echo "Freeze: blocks=$FREEZE_VIOLATIONS overrides=$FREEZE_OVERRIDES"

# ══════════════════════════════════════════════════════════════════════
# 5. JSON 스냅샷 저장
# ══════════════════════════════════════════════════════════════════════
python3 -c "
import json, sys
snapshot = {
    'date': '$TODAY_KST',
    'freeze_period': {
        'start': '2026-04-18',
        'end': '2026-05-15',
        'violations_blocked': $FREEZE_VIOLATIONS,
        'overrides_approved': $FREEZE_OVERRIDES
    },
    'portfolio': {
        'sharpe': '$SR',
        'cagr': '$CAGR',
        'mdd': '$MDD',
        'gap_sharpe': '$GAP_SR',
        'gap_cagr': '$GAP_CAGR',
        'gap_mdd': '$GAP_MDD'
    },
    'governor': {
        'total_revs': $GOV_REV_TOTAL,
        'freeze_period_revs': $GOV_REV_COUNT
    },
    's0_hit_rate': {
        'period_days': 7,
        'total': $S0_TOTAL,
        'approve': $S0_APPROVE,
        'revise': $S0_REVISE,
        'reject': $S0_REJECT,
        'hit_rate': '$S0_HIT_RATE'
    },
    'freeze_target': {
        'sr_threshold': 1.50,
        'current_sr': '$SR',
        'status': 'ON_TRACK' if '$SR' != 'N/A' and float('$SR') >= 1.30 else 'AT_RISK' if '$SR' != 'N/A' else 'NO_DATA'
    }
}
with open('$SNAPSHOT_FILE', 'w') as f:
    json.dump(snapshot, f, indent=2, ensure_ascii=False)
print(f'Snapshot saved: $SNAPSHOT_FILE')
" 2>/dev/null || echo "WARNING: JSON 스냅샷 저장 실패"

# ══════════════════════════════════════════════════════════════════════
# 6. 텔레그램 발송
# ══════════════════════════════════════════════════════════════════════
if [ "$DRYRUN" = "1" ]; then
  echo "[DRYRUN] 텔레그램 발송 skip"
else
  # Freeze 해제 조건 달성 여부 판단
  FREEZE_STATUS_EMOJI="--"
  FREEZE_STATUS_TEXT="데이터 없음"
  if [ "$SR" != "N/A" ]; then
    IS_ON_TRACK=$(python3 -c "print('yes' if float('$SR') >= 1.30 else 'no')" 2>/dev/null || echo "no")
    if [ "$IS_ON_TRACK" = "yes" ]; then
      FREEZE_STATUS_EMOJI="[ON TRACK]"
      FREEZE_STATUS_TEXT="경로 유지"
    else
      FREEZE_STATUS_EMOJI="[AT RISK]"
      FREEZE_STATUS_TEXT="주의 필요"
    fi
  fi

  MSG="[Q-Lead] Friday Alpha Snapshot
${TODAY_KST}

=== Portfolio Status ===
SR: ${SR} (gap: ${GAP_SR})
CAGR: ${CAGR} (gap: ${GAP_CAGR})
MDD: ${MDD} (gap: ${GAP_MDD})

=== Governor Rev ===
Total: ${GOV_REV_TOTAL} | Freeze: ${GOV_REV_COUNT}

=== S0 Hit Rate (7d) ===
${S0_APPROVE}/${S0_TOTAL} APPROVE (${S0_HIT_RATE})
REVISE: ${S0_REVISE} | REJECT: ${S0_REJECT}

=== v54 Freeze ===
Block: ${FREEZE_VIOLATIONS} | Override: ${FREEZE_OVERRIDES}
Target: SR >= 1.50
Status: ${FREEZE_STATUS_EMOJI} ${FREEZE_STATUS_TEXT}"

  # R을 통한 텔레그램 발송
  cd "$PROJ" && Rscript -e "
    tryCatch({
      source('02_Infrastructure/telegram/telegram_notify.R')
      msg <- readLines(textConnection(commandArgs(trailingOnly=TRUE)[1]))
      tg_send(paste(msg, collapse='\n'))
      cat('Telegram sent successfully\n')
    }, error = function(e) {
      cat(sprintf('Telegram send failed: %s\n', e\$message))
    })
  " "$MSG" 2>/dev/null || echo "WARNING: 텔레그램 발송 실패 (R 오류)"
fi

echo "=== Friday Alpha Snapshot 완료 ==="
exit 0
