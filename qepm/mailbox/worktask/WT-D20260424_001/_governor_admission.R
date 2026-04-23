# WT-D20260424_001 — Governor Admission (REJECT) + Lineage + Governance + Telegram
# Auto: 2026-04-24 (Pilot 3 RAPC)

suppressWarnings(suppressMessages({
  source("02_Infrastructure/telegram/telegram_notify.R")
  source("02_Infrastructure/worktask/lineage_utils.R")
  library(jsonlite)
  library(digest)
}))

TASK_ID <- "WT-D20260424_001"
WT_DIR  <- file.path("qepm/mailbox/worktask", TASK_ID)

# --- 1. GAP-2 HARD: lineage 기록 ----------------------------------------------
res_lin <- record_package_lineage(
  task_id           = TASK_ID,
  package_type      = "governor_admission",
  method_selected   = "REJECT_with_remediation_forward",
  input_file_paths  = c(
    file.path(WT_DIR, "judge_verdict.json"),
    "qepm/mailbox/governor/book_state.json"
  )
)
cat("[lineage] governor_admission appended\n")

# --- 2. governance_log append --------------------------------------------------
gov_path <- file.path(WT_DIR, "governance_log.json")
gov <- fromJSON(gov_path, simplifyVector = FALSE)
gov$events[[length(gov$events) + 1]] <- list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  agent = "governor",
  action = "GOVERNOR_ADMISSION",
  summary = "REJECT 확정 (Judge Grade F). Alpha 자산(RAPC) 보존, Optimizer 업그레이드 후 신규 WT-D로 재도전. book_state empty 유지.",
  objection_raised = TRUE,
  reason = "judge_pass=false (Gate C+D+E FAIL). MDD -44.59 경계 0.41pp 통과. AX-007 WARNING 재확인. Pilot 1/2/3 3연속 REJECT — Portfolio construction structural 한계.",
  targets_reviewed = list("judge_verdict", "book_state", "optimization_package", "alpha_package")
)
gov$events[[length(gov$events) + 1]] <- list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  agent = "q-lead",
  action = "PHASE_ADVANCE",
  summary = "JUDGE_FAILED -> GOVERNOR_REJECTED (WT closed, RAPC alpha 보존 → Task #26 신규 WT)"
)
write(toJSON(gov, pretty = TRUE, auto_unbox = TRUE), gov_path)
cat("[gov] governance_log updated\n")

# --- 3. status update ----------------------------------------------------------
st_path <- file.path(WT_DIR, "status.json")
st <- fromJSON(st_path, simplifyVector = FALSE)
st$status <- "GOVERNOR_REJECTED"
st$current_phase <- "GOVERNOR_REJECTED"
st$last_stage <- "governor_admission"
st$admission_verdict <- "REJECT"
st$deployment_allowed <- FALSE
st$positive_findings <- list("L-191_AVOIDED_VAL_GT_TRAIN", "RAPC_SIGNAL_VALIDATED")
st$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
write(toJSON(st, pretty = TRUE, auto_unbox = TRUE), st_path)
cat("[status] GOVERNOR_REJECTED\n")

# --- 4. Telegram (HARD — 이모지 + 섹션 구분 + Pilot 1~3 누적 표) --------------
msg <- paste0(
  "[Governor] WT-D20260424_001 Admission 심사 완료 (Pilot 3 RAPC)\n",
  "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n",
  "🚫 판정: REJECT (deployment_allowed=false)\n",
  "사유: Judge Grade F / Gate C+D+E FAIL / MDD 44.59 경계\n",
  "rule: judge_pass=false 단독으로 admission 차단\n",
  "\n",
  "🏆 [핵심 성과 — 기록 보존]\n",
  "  ✅ L-191 회피 실증: Val SR 0.317 > Train 0.275 (1.153x)\n",
  "     — Pilot 1/2 실패 원인(regime adaptation lag) 구조적 해결 증명\n",
  "  ✅ RAPC Alpha 유효: Harvey t=4.42 / ICIR 0.403 / VIF 1.006\n",
  "     — Alpha 자체는 통계적으로 validated (Gate A/B/F PASS)\n",
  "\n",
  "❌ [Gate FAIL 요약]\n",
  "  C Net Alpha .......... rank_ic 0.0318 (<0.04) / DSR 0.039 (<0.1)\n",
  "  D Crowding ........... Market 48% RF-R1 / ESBR+SUE family overlap\n",
  "  E Concentration ...... n=8 Grinold breadth / HHI 0.176 / max_w 0.20 binding 3 names\n",
  "  * MDD -44.59% hard_fail(-45%) 경계 0.41pp 여유 통과\n",
  "\n",
  "📊 [Pilot 1~3 누적 비교]\n",
  "  Pilot 1 Rate Hedge  (L-190): CAGR 8.72 / SR 0.413 / MDD -54.30 (hard_fail D+E)\n",
  "  Pilot 2 Macro Resid (L-191): CAGR 4.06 / SR 0.289 / MDD -44.03 (Val<Train 하자 C+D+F)\n",
  "  Pilot 3 RAPC        (L-192): CAGR 6.00 / SR 0.282 / MDD -44.59 (Val>Train 성공, breadth C+D+E)\n",
  "  → 공통 패턴: 3 Pilot 모두 8 names 집중 + MDD 40%+\n",
  "  → Alpha 차원은 누적 개선 (Pilot 3 L-191 회피 실증)\n",
  "  → Portfolio construction 차원이 root cause structural 한계\n",
  "\n",
  "📚 [Book 상태]\n",
  "  n_admitted: 0 (변화 없음)\n",
  "  3연속 REJECT 기록 (Pilot 1/2/3)\n",
  "  현 production 유지: STR_1631_SYN_05 80% + STR_1656_MLRA_M05 20%\n",
  "\n",
  "⚠️ [AX 공리]\n",
  "  AX-002 PASS / AX-007 WARNING 재확인 / AX-008 MET (3-source)\n",
  "\n",
  "🔧 [Remediation — Task #26 반영]\n",
  "  1. Optimizer min_names ≥ 15\n",
  "  2. HHI_cap ≤ 0.10\n",
  "  3. per-name bound [0, 0.10]\n",
  "  4. Alpha winsorization ±2σ (A140860 outlier 완화)\n",
  "  5. RAPC alpha 재사용 + Optimizer 업그레이드 후 신규 WT-D 재도전\n",
  "\n",
  "🎯 [다음 경로]\n",
  "  RAPC alpha 폐기 X → 신규 WT-D 번호로 Task #26 제약 하 재출발\n",
  "  Alpha 자산 보존 + Portfolio construction unlock 경로 확립\n",
  "\n",
  "📁 artifacts:\n",
  "  governor_admission: ", WT_DIR, "/governor_admission.json\n",
  "  book_state: qepm/mailbox/governor/book_state.json (v1.1)\n",
  "  L-192: qepm/memory/methodology_memory_v55_extensions.md"
)

ok <- tryCatch({
  tg_send(msg, parse_mode = "")
  TRUE
}, error = function(e) { cat("tg_send error:", conditionMessage(e), "\n"); FALSE })

cat("[governor] admission + lineage + governance + telegram complete (ok=", ok, ")\n", sep = "")
