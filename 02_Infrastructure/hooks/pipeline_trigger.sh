#!/bin/bash
#==============================================================================
# V7 Pipeline Trigger — Hook 기반 자동 파이프라인
# PostToolUse hook에서 호출. DONE 파일 감지 → 다음 에이전트 자동 스폰.
#
# 사용: Claude Code settings.json hooks에 등록
# {
#   "hooks": {
#     "PostToolUse": [{
#       "matcher": "Write|Bash",
#       "command": "bash 02_Infrastructure/pipeline_trigger.sh"
#     }]
#   }
# }
#==============================================================================

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
MAILBOX="$PROJECT_ROOT/qepm/mailbox"
LOG="/tmp/pipeline_trigger.log"

# Ensure processed/ directories exist
for agent_dir in "$MAILBOX"/*/; do
  mkdir -p "${agent_dir}processed" 2>/dev/null
done

# Clean up stale axiom lockfiles (24h+)
find /tmp -name "axiom_distill_trigger_*" -mmin +1440 -delete 2>/dev/null

# Archive Governor inbox DONE files (자동 정리)
for f in "$MAILBOX/q_lead/inbox/DONE_"*.json; do
  [ -f "$f" ] || continue
  mv "$f" "$MAILBOX/q_lead/processed/$(basename "$f")" 2>/dev/null
done

# Check if already processed (dedup)
is_already_processed() {
  local strategy="$1"
  local agent="$2"
  local proc_dir="$MAILBOX/$agent/processed"
  # Check if any DONE file for this strategy exists in processed/
  ls "$proc_dir/"*"${strategy}"* 2>/dev/null | head -1 | grep -q . && return 0
  return 1
}

# Archive a DONE file after triggering next stage
archive_done() {
  local f="$1"
  local processed_dir="$(dirname "$f")/../processed"
  mkdir -p "$processed_dir" 2>/dev/null
  mv "$f" "$processed_dir/$(basename "$f")" 2>/dev/null
}

# Scan all mailbox inboxes for new DONE files
scan_and_trigger() {
  local triggered=0

  # Scout DONE_S0 → Forge TODO_S1
  for f in "$MAILBOX/scout/inbox/DONE_S0_"*.json; do
    [ -f "$f" ] || continue
    local strategy=$(basename "$f" | sed 's/DONE_S0_//' | sed 's/.json//')
    local target="$MAILBOX/forge/inbox/TODO_S1_${strategy}.json"
    if [ ! -f "$target" ]; then
      cp "$f" "$target"
      echo "$(date +%H:%M:%S) TRIGGER: Scout DONE_S0 → Forge TODO_S1 ($strategy)" >> "$LOG"
      archive_done "$f"
      triggered=1
    fi
  done

  # Forge DONE_S1 → Forge TODO_S2 (동시 실행)
  for f in "$MAILBOX/forge/inbox/DONE_S1_"*.json; do
    [ -f "$f" ] || continue
    local strategy=$(basename "$f" | sed 's/DONE_S1_//' | sed 's/.json//')
    local target="$MAILBOX/forge/inbox/TODO_S2_${strategy}.json"
    if [ ! -f "$target" ]; then
      cp "$f" "$target"
      echo "$(date +%H:%M:%S) TRIGGER: Forge DONE_S1 → Forge TODO_S2 ($strategy)" >> "$LOG"
      archive_done "$f"
      triggered=1
    fi
  done

  # Forge DONE_S2 → Scout TODO_S3
  for f in "$MAILBOX/forge/inbox/DONE_S2_"*.json; do
    [ -f "$f" ] || continue
    local strategy=$(basename "$f" | sed 's/DONE_S2_//' | sed 's/.json//')
    local target="$MAILBOX/scout/inbox/TODO_S3_${strategy}.json"
    if [ ! -f "$target" ]; then
      cp "$f" "$target"
      echo "$(date +%H:%M:%S) TRIGGER: Forge DONE_S2 → Scout TODO_S3 ($strategy)" >> "$LOG"
      archive_done "$f"
      triggered=1
    fi
  done

  # Scout DONE_S3 → Forge TODO_S4
  for f in "$MAILBOX/scout/inbox/DONE_S3_"*.json; do
    [ -f "$f" ] || continue
    local strategy=$(basename "$f" | sed 's/DONE_S3_//' | sed 's/.json//')
    local target="$MAILBOX/forge/inbox/TODO_S4_${strategy}.json"
    if [ ! -f "$target" ]; then
      cp "$f" "$target"
      echo "$(date +%H:%M:%S) TRIGGER: Scout DONE_S3 → Forge TODO_S4 ($strategy)" >> "$LOG"
      archive_done "$f"
      triggered=1
    fi
  done

  # Forge DONE_S4 → sg_determine_role() 호출 → role 기반 라우팅
  for f in "$MAILBOX/forge/inbox/DONE_S4_"*.json; do
    [ -f "$f" ] || continue
    local strategy=$(basename "$f" | sed 's/DONE_S4_//' | sed 's/.json//')

    # sg_determine_role(): S2/S3/S4 artifact 경로 탐색 후 R 호출
    local strategy_dir=$(find "$PROJECT_ROOT/04_Research/strategies/" \
      -maxdepth 1 -name "*${strategy}*" -type d 2>/dev/null | head -1)

    local role="core_alpha"  # 기본값
    if [ -n "$strategy_dir" ]; then
      role=$(cd "$PROJECT_ROOT" && Rscript --no-save -e "
        suppressMessages({
          source('02_Infrastructure/config.R')
          source('02_Infrastructure/stage_gate_engine.R')
          library(jsonlite)
        })
        strat_dir <- '${strategy_dir}'
        # S2 artifact
        s2_path <- list.files(strat_dir, pattern='s2_profile.*\\.json', recursive=TRUE, full.names=TRUE)
        s2 <- if (length(s2_path) > 0) tryCatch(fromJSON(s2_path[1], simplifyVector=FALSE), error=function(e) list()) else list()
        # S3 artifact
        s3_path <- list.files(strat_dir, pattern='s3_orthogonality.*\\.json', recursive=TRUE, full.names=TRUE)
        s3 <- if (length(s3_path) > 0) tryCatch(fromJSON(s3_path[1], simplifyVector=FALSE), error=function(e) list()) else list()
        # S4 artifact (DONE_S4 파일 자체)
        s4 <- tryCatch(fromJSON('${f}', simplifyVector=FALSE), error=function(e) list())
        # sg_determine_role 호출
        role <- tryCatch(sg_determine_role(s2, s3, s4), error=function(e) 'core_alpha')
        cat(role, '\n')
      " 2>/dev/null | tail -1 | tr -d '[:space:]')
      [ -z "$role" ] && role="core_alpha"
    fi

    echo "$(date +%H:%M:%S) ROLE: $strategy → $role" >> "$LOG"

    # role 기반 라우팅
    local target=""
    local kospi_beat=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('kospi_beat', False))" 2>/dev/null)

    if [ "$role" = "defense" ]; then
      # Defense: 항상 S5 mutation (방어 구조 강화 우선)
      target="$MAILBOX/forge/inbox/TODO_S5_EXEC_${strategy}.json"
      python3 -c "
import json
with open('$f') as fp: d = json.load(fp)
d['role_label'] = 'defense'
with open('$f', 'w') as fp: json.dump(d, fp, indent=2)
" 2>/dev/null
    elif [ "$role" = "cash_allocation" ]; then
      # v55 Cash sleeve: S5 skip, PG2 allocation 직행 (팩터 아님, 배분 결정)
      target="$MAILBOX/governor/inbox/TODO_PG2_CASH_SLEEVE_${strategy}.json"
      python3 -c "
import json
with open('$f') as fp: d = json.load(fp)
d['role_label'] = 'cash_allocation'
d['v55_trail'] = 'standard'
d['admission_rule'] = 'v3.5.2 §1.4'
with open('$f', 'w') as fp: json.dump(d, fp, indent=2)
" 2>/dev/null
      echo "$(date +%H:%M:%S) TRIGGER v55: $strategy cash_allocation → TODO_PG2_CASH_SLEEVE (S5 skip)" >> "$LOG"
    elif [ "$role" = "regime_adaptive" ]; then
      # v55 Regime Adaptive: S5 mutation 필요 (switching_alpha + transition_cost 검증)
      target="$MAILBOX/forge/inbox/TODO_S5_EXEC_${strategy}.json"
      python3 -c "
import json
with open('$f') as fp: d = json.load(fp)
d['role_label'] = 'regime_adaptive'
d['v55_gate_items'] = ['switching_alpha>0.10', 'transition_cost<50bps', 'stability_36M>=0.60']
with open('$f', 'w') as fp: json.dump(d, fp, indent=2)
" 2>/dev/null
      echo "$(date +%H:%M:%S) TRIGGER v55: $strategy regime_adaptive → TODO_S5_EXEC" >> "$LOG"
    elif [ "$role" = "ml_predictive" ]; then
      # v55 ML Predictive: empirical-first gate 강화 (SR_OOS/IS + feature concentration + holdout)
      target="$MAILBOX/forge/inbox/TODO_S5_EXEC_${strategy}.json"
      python3 -c "
import json
with open('$f') as fp: d = json.load(fp)
d['role_label'] = 'ml_predictive'
d['v55_trail'] = 'ml_empirical_first'
d['v55_gate_items'] = ['SR_OOS_IS>=0.70', 'feature_concentration<0.4', 'holdout_12M_strict']
with open('$f', 'w') as fp: json.dump(d, fp, indent=2)
" 2>/dev/null
      echo "$(date +%H:%M:%S) TRIGGER v55: $strategy ml_predictive → TODO_S5_EXEC (empirical-first)" >> "$LOG"
    elif [ "$kospi_beat" = "True" ]; then
      # Core/Diversifier이고 KOSPI beat → S6 직행
      target="$MAILBOX/judge/inbox/TODO_S6_${strategy}.json"
    else
      # Core/Diversifier이고 KOSPI beat 미달 → S5 mutation
      target="$MAILBOX/forge/inbox/TODO_S5_EXEC_${strategy}.json"
    fi

    if [ ! -f "$target" ]; then
      # role_label을 target JSON에도 전파
      cp "$f" "$target"
      echo "$(date +%H:%M:%S) TRIGGER: Forge DONE_S4 → $(basename "$target") ($strategy, role=$role, kospi=$kospi_beat)" >> "$LOG"
      archive_done "$f"
      triggered=1
    fi
  done

  # Forge DONE_S5 → Judge TODO_S6 + Codex TODO_S6 (병렬 검증)
  for f in "$MAILBOX/forge/inbox/DONE_S5_"*.json; do
    [ -f "$f" ] || continue
    local strategy=$(basename "$f" | sed 's/DONE_S5_//' | sed 's/.json//')
    local judge_target="$MAILBOX/judge/inbox/TODO_S6_${strategy}.json"
    local codex_target="$MAILBOX/codex/inbox/TODO_S6_${strategy}.json"
    mkdir -p "$MAILBOX/codex/inbox" 2>/dev/null
    if [ ! -f "$judge_target" ]; then
      # v53 S2.7: Mutation Tracker 갱신 (S5 완료 시 점수 집계)
      QVEST_PROJECT_DIR="$PROJECT_ROOT" python3 "$PROJECT_ROOT/02_Infrastructure/validation/mutation_tracker.py" >> "$LOG" 2>&1 || true
      cp "$f" "$judge_target"
      cp "$f" "$codex_target"
      echo "$(date +%H:%M:%S) TRIGGER: Forge DONE_S5 → Judge+Codex TODO_S6 ($strategy)" >> "$LOG"
      archive_done "$f"
      triggered=1
    fi
  done

  # Judge DONE_S6 + Codex DONE_S6 → Judge TODO_S7 (양쪽 모두 완료 시)
  for f in "$MAILBOX/judge/inbox/DONE_S6_"*.json; do
    [ -f "$f" ] || continue
    local strategy=$(basename "$f" | sed 's/DONE_S6_//' | sed 's/.json//')
    local codex_done="$MAILBOX/codex/inbox/DONE_S6_${strategy}.json"
    local target="$MAILBOX/judge/inbox/TODO_S7_${strategy}.json"
    # Judge + Codex 양쪽 DONE 확인 후 S7 진행
    if [ ! -f "$target" ] && [ -f "$codex_done" ]; then
      cp "$f" "$target"
      echo "$(date +%H:%M:%S) TRIGGER: Judge+Codex DONE_S6 → Judge TODO_S7 ($strategy)" >> "$LOG"
      archive_done "$f"
      archive_done "$codex_done" 2>/dev/null
      triggered=1
    elif [ ! -f "$target" ] && [ ! -f "$codex_done" ]; then
      echo "$(date +%H:%M:%S) WAIT: Judge DONE_S6 but Codex pending ($strategy)" >> "$LOG"
    fi
  done

  # Judge DONE_S7 → Governor TODO_PG0 (Grade A/A_NOVEL/B만 통과)
  for f in "$MAILBOX/judge/inbox/DONE_S7_"*.json; do
    [ -f "$f" ] || continue
    local strategy=$(basename "$f" | sed 's/DONE_S7_//' | sed 's/.json//')
    local target="$MAILBOX/q_lead/inbox/TODO_PG0_${strategy}.json"
    if [ ! -f "$target" ]; then
      # Grade 체크: hurdle_result.json에서 grade 확인
      local strategy_dir=$(find "$PROJECT_ROOT/04_Research/strategies/" -maxdepth 1 -name "*${strategy}*" -type d 2>/dev/null | head -1)
      local grade=$(python3 -c "
import json, glob, sys
for p in glob.glob('${strategy_dir}/output*/hurdle_result.json'):
    try:
        d = json.load(open(p))
        v = d.get('verdict', d)
        print(v.get('grade', d.get('grade', 'F')))
        sys.exit(0)
    except: pass
print('F')
" 2>/dev/null)

      if [[ "$grade" == "A" || "$grade" == "A_NOVEL" || "$grade" == "A_CONDITIONAL" || "$grade" == "B" ]]; then
        cp "$f" "$target"
        echo "$(date +%H:%M:%S) TRIGGER: Judge DONE_S7 → Governor TODO_PG0 ($strategy, Grade=$grade)" >> "$LOG"
      else
        echo "$(date +%H:%M:%S) BLOCKED: $strategy Grade=$grade → ARCHIVE (PG 진입 거부)" >> "$LOG"
        mv "$f" "$(dirname "$f")/../processed/ARCHIVED_S7_${strategy}.json" 2>/dev/null
      fi
      archive_done "$f"
      triggered=1
    fi
  done

  # Governor DONE_PG2 → Axiom 부분 distill + PG0→S0 피드백 루프
  for f in "$MAILBOX/q_lead/inbox/DONE_PG2_"*.json; do
    [ -f "$f" ] || continue
    local strategy=$(basename "$f" | sed 's/DONE_PG2_//' | sed 's/.json//')
    local trigger_file="/tmp/axiom_partial_trigger_${strategy}"
    if [ ! -f "$trigger_file" ]; then
      touch "$trigger_file"
      echo "$(date +%H:%M:%S) TRIGGER: PG2 완료 — Axiom distill + gap→Scout ($strategy)" >> "$LOG"
      cd "$PROJECT_ROOT" && Rscript --no-save -e "
        suppressMessages({
          source('02_Infrastructure/config.R')
          source('02_Infrastructure/axiom_memory_interface.R')
          source('02_Infrastructure/portfolio_governor.R')
          library(jsonlite)
        })

        # 1. Axiom 부분 distill
        sg_sync_methodology_memory()

        # 2. PG0 gap 갱신
        gap <- pg0_gap_review('V7_ALLWEATHER_001')

        # 3. Scout에 gap TODO 생성 (PG0→S0 피드백 루프)
        scout_inbox <- file.path(PROJECT_ROOT, 'qepm/mailbox/scout/inbox')
        existing <- list.files(scout_inbox, 'TODO_S0_GAP_', full.names = TRUE)
        if (length(existing) == 0 && length(gap[['sleeve_needs']]) > 0) {
          todo <- list(
            task_type = 'S0_gap_directed',
            sleeve_needs = gap[['sleeve_needs']],
            gap = gap[['gap']],
            regime = gap[['regime_state']],
            instructions = sprintf(
              'PG2 완료 후 gap 재진단: %s 부족. CAGR %+.1f%%, SR %+.3f, MDD %+.1f%%. %s. 이 gap을 메우는 가설 1건 설계.',
              paste(gap[['sleeve_needs']], collapse='+'),
              gap[['gap']][['cagr_gap']] * 100, gap[['gap']][['sharpe_gap']], gap[['gap']][['mdd_gap']] * 100,
              gap[['regime_state']][['category']]
            ),
            created_at = as.character(Sys.time())
          )
          ts <- gsub('[- :]', '', as.character(Sys.time()))
          todo_path <- file.path(scout_inbox, sprintf('TODO_S0_GAP_%s.json', ts))
          write_json(todo, todo_path, auto_unbox = TRUE, pretty = TRUE)
          cat(sprintf('[Hook] PG2→S0 피드백: Scout TODO_S0_GAP 생성 (%s)\n', paste(gap[['sleeve_needs']], collapse='+')))
        }
        cat('[Axiom] Partial distill + gap update for $strategy\n')
      " >> "$LOG" 2>&1 &
      triggered=1
    fi
    archive_done "$f"
  done

  # Governor DONE_PG3 또는 DONE_ARCHIVE → 전체 Axiom distill (scan + promote)
  for f in "$MAILBOX/q_lead/inbox/DONE_PG3_"*.json "$MAILBOX/"*/inbox/DONE_ARCHIVE_*.json; do
    [ -f "$f" ] || continue
    local strategy=$(basename "$f" | sed 's/DONE_[A-Z0-9]*_//' | sed 's/.json//')
    local trigger_file="/tmp/axiom_distill_trigger_${strategy}"
    if [ ! -f "$trigger_file" ]; then
      # L-code 존재 체크 (없으면 distill 보류)
      local strategy_dir=$(find "$PROJECT_ROOT/04_Research/strategies/" -maxdepth 1 -name "*${strategy}*" -type d 2>/dev/null | head -1)
      local lcode_exists=$(find "$strategy_dir" -name "l_code_*.json" 2>/dev/null | head -1)
      if [ -z "$lcode_exists" ] && [ -n "$strategy_dir" ]; then
        echo "$(date +%H:%M:%S) AXIOM DEFER: $strategy — l_code 미존재, 다음 사이클 대기" >> "$LOG"
        continue
      fi
      touch "$trigger_file"
      echo "$(date +%H:%M:%S) TRIGGER: Axiom 전체 증류 — PG3 ($strategy)" >> "$LOG"
      cd "$PROJECT_ROOT" && Rscript -e "
        source('02_Infrastructure/axiom_memory_interface.R')
        sg_sync_methodology_memory()
        tryCatch({
          source('qepm/R/memory/r7_axiom.R')
          candidates <- scan_axiom_candidates()
          cat(sprintf('[Axiom] Full distill: %d candidates for $strategy\n', length(candidates)))
        }, error = function(e) cat('[Axiom] scan_axiom error:', e\$message, '\n'))
      " >> "$LOG" 2>&1 &
      triggered=1
    fi
    archive_done "$f"
  done

  return $triggered
}

# 실행 — v53 Fix #1: flock 직렬화 (중복 TRIGGER 차단)
LOCKFILE="/tmp/pipeline_trigger.lock"
exec 9>"$LOCKFILE" || exit 0
flock -n 9 || { echo "$(date +%H:%M:%S) SKIP: another trigger running" >> "$LOG"; exit 0; }
scan_and_trigger
