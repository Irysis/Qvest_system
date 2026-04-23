# WT-D20260424_001 — Judge Gate A~F Telegram + Governance + Lineage
# Auto: 2026-04-24

suppressWarnings(suppressMessages({
  source("02_Infrastructure/telegram/telegram_notify.R")
  library(jsonlite)
}))

# --- 1. governance_log append --------------------------------------------------
gov_path <- "qepm/mailbox/worktask/WT-D20260424_001/governance_log.json"
gov <- fromJSON(gov_path, simplifyVector = FALSE)
gov$events[[length(gov$events) + 1]] <- list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  agent = "judge",
  action = "JUDGE_VERDICT",
  summary = "Gate A~F 심사 완료 — GRADE_F / DISCARD_WITH_IMPROVEMENTS. A/B/F PASS, C/D/E FAIL. L-192 적립.",
  objection_raised = TRUE,
  reason = "Gate C (rank_ic 0.0318<0.04 + DSR 0.039<0.1) + Gate D (Market 48% + earnings_surprise family overlap) + Gate E (n=8 Grinold breadth)",
  targets_reviewed = list("alpha_package", "risk_package", "optimization_package", "backtest_result")
)
gov$events[[length(gov$events) + 1]] <- list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  agent = "q-lead",
  action = "PHASE_ADVANCE",
  summary = "FORGE_DONE -> JUDGE_DONE (GRADE_F, DISCARD_WITH_IMPROVEMENTS)"
)
write(toJSON(gov, pretty = TRUE, auto_unbox = TRUE), gov_path)
cat("[gov] updated\n")

# --- 2. artifact_lineage append (judge_verdict entry) --------------------------
lin_path <- "qepm/mailbox/worktask/WT-D20260424_001/artifact_lineage.json"
lin <- fromJSON(lin_path, simplifyVector = FALSE)

verdict_file <- "qepm/mailbox/worktask/WT-D20260424_001/judge_verdict.json"
file_hash <- digest::digest(file = verdict_file, algo = "sha256")

lin$entries[[length(lin$entries) + 1]] <- list(
  task_id = "WT-D20260424_001",
  package_type = "judge_verdict",
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  git_commit = tryCatch(system("git rev-parse HEAD", intern = TRUE), error = function(e) NA),
  git_dirty = TRUE,
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  r_packages = list(jsonlite = as.character(packageVersion("jsonlite")),
                    digest = as.character(packageVersion("digest"))),
  random_seed = 20260424L,
  input_hashes = list(
    backtest_summary = digest::digest(file = "qepm/mailbox/worktask/WT-D20260424_001/judge_ready/backtest_summary.json", algo = "sha256"),
    integration_audit = digest::digest(file = "qepm/mailbox/worktask/WT-D20260424_001/judge_ready/integration_audit.json", algo = "sha256")
  ),
  method_selected = "gate_a_to_f_v61",
  file_path = verdict_file,
  file_hash_sha256 = file_hash
)
lin$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
write(toJSON(lin, pretty = TRUE, auto_unbox = TRUE), lin_path)
cat("[lineage] updated (judge_verdict hash=", substr(file_hash, 1, 10), "...)\n", sep = "")

# --- 3. status update ----------------------------------------------------------
st_path <- "qepm/mailbox/worktask/WT-D20260424_001/status.json"
st <- fromJSON(st_path, simplifyVector = FALSE)
st$status <- "JUDGE_DONE"
st$last_stage <- "judge_verdict"
st$verdict <- "GRADE_F"
st$disposition <- "DISCARD_WITH_IMPROVEMENTS"
st$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
write(toJSON(st, pretty = TRUE, auto_unbox = TRUE), st_path)
cat("[status] JUDGE_DONE\n")

# --- 4. Telegram --------------------------------------------------------------
msg <- paste0(
  "[Judge] WT-D20260424_001 Gate A~F 심사 완료\n",
  "━━━━━━━━━━━━━━━━━━━━━━━\n",
  "판정: GRADE_F (DISCARD_WITH_IMPROVEMENTS)\n",
  "전략: Pilot 3 RAPC (ESBR+SUE+Accrual)\n",
  "옵티마이저: MVO_lam2_psi0.3, 8 names\n",
  "\n",
  "[Gate 심사 결과]\n",
  "  A PIT 무결 ............ PASS\n",
  "  B Package 격리 ........ PASS\n",
  "  C Net Alpha ........... FAIL (rank_ic 0.0318 / DSR 0.039)\n",
  "  D Crowding / Family ... FAIL (Market 48% + ESBR/SUE overlap)\n",
  "  E Concentration ....... FAIL (n=8, HHI 0.176, Grinold 한계)\n",
  "  F Drift / Regime ...... PASS (Val SR 0.317 > Train 0.275)\n",
  "\n",
  "[핵심 성과]\n",
  "  * Val > Train SR 실증 — L-191 Val<Train 메커니즘 회피 성공\n",
  "  * VIF 1.006~1.01 / TDC 0.04~0.17 / cond=1.0 무결\n",
  "  * Turnover 46.9%/yr 낮음 (cost 효율)\n",
  "\n",
  "[핵심 약점]\n",
  "  * Grinold breadth 한계 재발 (Pilot 1/2/3 공통)\n",
  "  * MDD -44.59% 경계 통과 (hard_fail -45% 0.41pp 여유)\n",
  "  * A140860 alpha=3.0 outlier 과집중 (cap 0.20 binding)\n",
  "\n",
  "[Pilot 누적 비교]\n",
  "  Pilot 1 L-190 Rate Hedge  : CAGR 8.72 / SR 0.413 / MDD -54.30 (hard_fail)\n",
  "  Pilot 2 L-191 Macro Resid : CAGR 4.06 / SR 0.289 / MDD -44.03 (Val<Train)\n",
  "  Pilot 3 RAPC (현 Task)    : CAGR 6.00 / SR 0.282 / MDD -44.59 (breadth 한계)\n",
  "  -> 3 Pilot 모두 8 names 집중 공통 / Alpha 개선은 있으나 Portfolio 차원 structural 한계\n",
  "\n",
  "[AX 공리]\n",
  "  AX-002 PASS / AX-007 WARNING 실증 재확인 / AX-008 PASS (2-source)\n",
  "\n",
  "[L-192 적립]\n",
  "  core_reference: Bernard-Thomas 1989 PEAD + Sloan 1996 Accruals + Grinold 1989 breadth\n",
  "  관련: L-190 / L-191 / L-119 / L-122 / AX-007\n",
  "\n",
  "[다음 조치 — Task #26]\n",
  "  1. Optimizer 제약 강화: min_names>=15 + HHI_cap<=0.10 + bound[0, 0.10]\n",
  "  2. Alpha winsorization +/-2sigma (A140860 outlier 완화)\n",
  "  3. RAPC alpha 재사용 + 제약 업그레이드 하 재백테스트\n",
  "  4. Earnings-surprise family empirical redundancy test\n",
  "\n",
  "verdict: qepm/mailbox/worktask/WT-D20260424_001/judge_verdict.json\n",
  "L-192: qepm/memory/methodology_memory_v55_extensions.md (Section 6)"
)

ok <- tryCatch({
  tg_send(msg, parse_mode = "")
  TRUE
}, error = function(e) { cat("tg_send error:", conditionMessage(e), "\n"); FALSE })

if (ok) {
  tryCatch(tg_send_photo("qepm/mailbox/worktask/WT-D20260424_001/backtest_result/equity_curve.png",
                         caption = "[Judge] Pilot 3 RAPC equity curve — GRADE_F (breadth 한계)"),
           error = function(e) cat("photo equity err:", conditionMessage(e), "\n"))
  tryCatch(tg_send_photo("qepm/mailbox/worktask/WT-D20260424_001/backtest_result/annual_returns.png",
                         caption = "[Judge] Pilot 3 RAPC annual returns"),
           error = function(e) cat("photo annual err:", conditionMessage(e), "\n"))
}

cat("[judge] telegram + governance + lineage complete\n")
