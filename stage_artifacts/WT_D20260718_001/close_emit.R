# close_emit.R — WT_D20260718_001 라운드 종료 계약 + infra L-code 적립
#   close_round(capability_established) 마커 발행 + emit_lcode(record_type=infra).
#   실행: Rscript stage_artifacts/WT_D20260718_001/close_emit.R
root <- Sys.getenv("QM_ROOT", "")
if (!nzchar(root) || !dir.exists(root)) root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)

NEXT_PROBES <- c(
  "stale in_progress claim(>6h, 크래시 세션)의 bootstrap 가시성 배선 — 현재 자동 steal은 되나 '증류가 막혀 있다'는 표면이 없어 조용히 재점유될 뿐. bootstrap WARN(distill_status=in_progress ∧ claimed_at>stale)로 노출",
  "타 공유상태 소비자의 동일 2-pass 경합 감사 — stage_artifacts/paper_recharge/daily.lock · morning_steps 큐 등 메인+스폰 병행 소비 지점 점검 → 2번째 사례 확인 시 cleaner_claim 패턴 일반화(공용 claim 헬퍼)")

# ── 1) close_round ────────────────────────────────────────────────────────────
source(file.path(root, "02_Infrastructure", "contracts", "close_round.R"))
rec <- close_round(
  round_id = "WT-D20260718_001",
  verdict_type = "capability_established",
  mechanism_diagnosis = paste(
    "W29 2-pass 중복실행의 근인 = cleaner_pending.json이 status(awaiting_distill→distilled)만 가져",
    "증류 '진행 중' 중간상태를 표현 못 함 → 메인 세션과 스폰 Cleaner(task#89)가 둘 다 awaiting_distill을",
    "보고 동시 착수. distill_status(pending/in_progress/done) 선점 필드 + atomic claim(mutex-dir 직렬화",
    "+ temp/rename 원자쓰기 + 6h stale 재점유)으로 착수를 직렬화해 원천 차단."),
  next_probes = NEXT_PROBES,
  consumer_surfaces = c(
    "cleaner SKILL §0.2 (착수 claim + ⑤ release + 2-pass 병합 fallback)",
    "weekly_cleaner_sweep.R 생성자 (cleaner_pending_v2 + distill_* 초기화)",
    "bootstrap status 마커 (불변 — distill_status가 그 사이 in_progress 표현)"),
  frontier_update = "chip 등재: stale-claim bootstrap 가시성 배선 (ops 후속, alpha frontier 아님)",
  layer = "infra/ops (엔진 위생 — 병렬 소비 직렬화)",
  evidence_refs = c(
    "02_Infrastructure/ops/cleaner_claim.R",
    "02_Infrastructure/ops/weekly_cleaner_sweep.R (step[4] cleaner_pending_v2)",
    ".claude/skills/cleaner/SKILL.md §0.2",
    "stage_artifacts/WT_D20260718_001/smoke_test_claim_result.json (17/17 PASS)"))

# ── 2) emit_lcode (infra record — metric_type=unavailable, 성과 아님) ─────────────
source(file.path(root, "02_Infrastructure", "axiom", "lcode_emit.R"))
lc <- emit_lcode(
  mode = "qepm_legacy",  # infra_process 캐치올 (선례 L-167 qepm_legacy infra_process)
  strategy_id = "CLEANER_DISTILL_CLAIM_PROTOCOL",
  grade = "",            # record_type=infra → grade 면제
  record_type = "infra",
  metric_type = "unavailable",
  construction_type = "structural_limit",  # 추론 폴백(single_factor) 회피 — infra라 검증 면제
  core_reference = "W29 next_probe #4 (2026-07-18 도훈 mandate)",
  lesson_text = paste(
    "Cleaner 증류 2-pass 중복실행 방지 = cleaner_pending.json에 distill_status(pending/in_progress/done)",
    "+ distill_owner + distill_claimed_at 선점 필드 추가하고 cleaner_claim.R(atomic claim: mutex-dir",
    "직렬화 + temp/rename 원자쓰기 + 6h stale 재점유 + v1 하위호환)로 착수를 직렬화. status는 bootstrap",
    "마커용 불변 — distill_status가 그 사이 in_progress 중간상태를 담아 두 소비자 동시 착수를 차단.",
    "스모크 17/17 PASS (2회 claim 시 2번째 in_progress 감지 등). 07-06 병렬 중복실행 사고의 ops 재발방지."),
  mechanism_hypothesis = paste(
    "동시성 경합의 근인은 공유 상태에 '점유 중' 표현이 없는 것 — 착수 직렬화 프리미티브(claim)로 해소.",
    "지속 소유권은 JSON distill_status에, 짧은 read-check-write 임계구역만 mutex-dir로 원자화."),
  tags = c("infra_process", "cleaner", "continuity", "concurrency", "distill_claim"),
  metrics = list(next_probe = NEXT_PROBES,
                 smoke_result = "17/17 PASS",
                 files = c("02_Infrastructure/ops/cleaner_claim.R",
                           "02_Infrastructure/ops/weekly_cleaner_sweep.R",
                           ".claude/skills/cleaner/SKILL.md")))

cat(sprintf("\n[close_emit] round_closure verdict=%s · L-code=%s\n",
            rec$verdict_type, if (is.character(lc)) lc else "(emit 반환 확인)"))
