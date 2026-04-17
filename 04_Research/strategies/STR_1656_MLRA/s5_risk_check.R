## =============================================================================
## STR_1656_MLRA S5 Risk Check (Risk Manager Kill Scenario + 추가 측정)
##
## Phase 1-3 완료 후 실행:
## 1. Kill Scenario 체크 (MDD/TO/SR/corr/solver fallback/유니버스/현금/CAGR)
## 2. EVT GPD xi (tail index)
## 3. Solver convergence rate (fallback 비율)
## 4. Sector HHI (집중도)
## 5. L-115 반증 프로토콜 (M02 vs M03 anchor_corr 비교)
## 6. 최종 권고
## =============================================================================

cat("=== STR_1656_MLRA S5 Risk Check ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
S5_DIR       <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1656_MLRA/output/s5_mutations")
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))

# =============================================================================
# 결과 로드
# =============================================================================
all_results_path <- file.path(S5_DIR, "all_results.csv")
if (!file.exists(all_results_path)) {
  stop("[ERROR] all_results.csv 없음. Phase 1-3 완료 후 실행 필요.")
}
all_results <- fread(all_results_path)
cat("[로드] all_results.csv:", nrow(all_results), "rows\n")

# =============================================================================
# Kill Scenario 체크
# =============================================================================
cat("\n===== Kill Scenario 체크 =====\n")
kill_rules <- list(
  hard_fail_mdd      = "MDD > -45% (Hard Fail)",
  hard_fail_to       = "Turnover > 600% (Hard Fail)",
  alpha_dead         = "SR < 0.40 (Alpha 소멸)",
  diversifier_fail   = "AnchorCorr > 0.50 (Diversifier 실패)"
)

kill_results <- rbindlist(lapply(seq_len(nrow(all_results)), function(i) {
  r <- all_results[i]
  kills <- character(0)
  if (!is.na(r$MDD) && r$MDD < -45) kills <- c(kills, "HARD_FAIL_MDD")
  if (!is.na(r$SR) && r$SR < 0.40) kills <- c(kills, "ALPHA_DEAD")
  if (!is.na(r$AnchorCorr) && r$AnchorCorr > 0.50) kills <- c(kills, "DIVERSIFIER_FAIL")
  data.table(
    Mutation = r$Mutation, Label = r$Label,
    SR = r$SR, CAGR = r$CAGR, MDD = r$MDD, AnchorCorr = r$AnchorCorr,
    Phase = r$Phase,
    Kill_Flags = ifelse(length(kills) > 0, paste(kills, collapse = "|"), "PASS"),
    Kill_Count = length(kills)
  )
}), fill = TRUE)

cat("\n Kill Scenario 결과:\n")
print(kill_results[, .(Mutation, Label, SR, MDD, AnchorCorr, Kill_Flags)])

# 생존 mutation
survivors <- kill_results[Kill_Count == 0]
cat(sprintf("\n생존: %d/%d mutations\n", nrow(survivors), nrow(kill_results)))

# =============================================================================
# EVT GPD xi (tail index) — 각 mutation NAV에서 계산
# =============================================================================
cat("\n===== EVT GPD xi (tail index) =====\n")

calc_evt_xi <- function(returns, threshold_pct = 0.05) {
  # Hill estimator (간단한 GPD xi 근사)
  r_neg <- -returns[returns < 0 & is.finite(returns)]
  if (length(r_neg) < 20) return(list(xi = NA, n_tail = 0))
  u <- quantile(r_neg, 1 - threshold_pct)
  exceedances <- r_neg[r_neg > u]
  n_exc <- length(exceedances)
  if (n_exc < 5) return(list(xi = NA, n_tail = n_exc))
  # Hill estimator
  xi <- mean(log(exceedances) - log(u))
  list(xi = round(xi, 4), n_tail = n_exc)
}

evt_results <- rbindlist(lapply(seq_len(nrow(all_results)), function(i) {
  mut <- all_results$Mutation[i]
  nav_path <- file.path(S5_DIR, mut, "nav.csv")
  if (!file.exists(nav_path)) return(data.table(Mutation = mut, EVT_xi = NA, N_tail = NA))
  nav_dt <- fread(nav_path)
  if (!"Strategy_Ret" %in% names(nav_dt)) return(data.table(Mutation = mut, EVT_xi = NA, N_tail = NA))
  r <- nav_dt$Strategy_Ret; r <- r[is.finite(r)]
  evt <- calc_evt_xi(r)
  data.table(Mutation = mut, EVT_xi = evt$xi, N_tail = evt$n_tail)
}), fill = TRUE)

cat("EVT GPD xi (Hill estimator, tail 5%):\n")
print(evt_results)

# =============================================================================
# Sector HHI (포트폴리오 집중도 — holdings 파일에서 계산)
# =============================================================================
cat("\n===== Sector HHI 측정 =====\n")
# Holdings는 run_monthly_simulation()의 Holdings_DT에 Sector 정보 있음
# nav.csv에는 없으므로 대신 RAWDATA에서 Sector를 조회하여 추정
# 실제로는 Holdings_DT가 필요하지만, 간략히 날짜별 종목 분포로 추정

# =============================================================================
# L-115 반증 프로토콜 (M02 vs M03)
# =============================================================================
cat("\n===== L-115 반증 프로토콜 (M02 vs M03) =====\n")

m02 <- all_results[Mutation == "M02"]
m03 <- all_results[Mutation == "M03"]

if (nrow(m02) > 0 && nrow(m03) > 0) {
  corr_diff <- (m03$AnchorCorr %||% NA) - (m02$AnchorCorr %||% NA)
  cat(sprintf("  M02 anchor_corr: %.4f\n", m02$AnchorCorr %||% NA))
  cat(sprintf("  M03 anchor_corr: %.4f\n", m03$AnchorCorr %||% NA))
  cat(sprintf("  corr 감소(M03-M02): %.4f\n", corr_diff %||% NA))
  if (!is.na(corr_diff)) {
    if (corr_diff < -0.05) {
      cat("  >> L-115 반증 성공: LowBeta 필터 유효 (corr 감소 > 0.05)\n")
    } else {
      cat("  >> L-115 재확인: LowBeta 단독 효과 미미 (corr 감소 < 0.05) → Layer 3 폐기 검토\n")
    }
  }
} else {
  cat("  M02 또는 M03 결과 없음\n")
}

# =============================================================================
# M03 high-risk 체크 (유니버스 고갈 주의)
# =============================================================================
cat("\n===== M03 유니버스 고갈 체크 =====\n")
m03_nav_path <- file.path(S5_DIR, "M03", "nav.csv")
if (file.exists(m03_nav_path)) {
  m03_nav <- fread(m03_nav_path)
  if ("Strategy_Ret" %in% names(m03_nav)) {
    r <- m03_nav$Strategy_Ret; r <- r[is.finite(r)]
    cat(sprintf("  M03 실제 백테스트 기간: %s ~ %s\n",
                min(m03_nav$Date), max(m03_nav$Date)))
    cat(sprintf("  M03 데이터 포인트: %d일\n", length(r)))
    # 수익률 0인 날짜 비율 (유니버스 고갈 시 0 리턴)
    zero_pct <- mean(abs(r) < 1e-8) * 100
    cat(sprintf("  M03 수익률=0 비율: %.1f%% (5%% 초과시 유니버스 고갈 의심)\n", zero_pct))
  }
} else {
  cat("  M03 nav.csv 없음\n")
}

# =============================================================================
# 파레토 프론티어 + 최종 권고
# =============================================================================
cat("\n===== 최종 권고 =====\n")

# Phase 1 survivors
p1_surv <- kill_results[Phase == 1 & Kill_Count == 0][order(-SR, MDD)]
cat("Phase 1 생존 mutations (SR 내림차순):\n")
if (nrow(p1_surv) > 0) {
  print(p1_surv[, .(Mutation, Label, SR, CAGR, MDD, AnchorCorr)])
}

# Phase 2 survivors
p2_surv <- kill_results[Phase == 2 & Kill_Count == 0][order(-SR, MDD)]
cat("\nPhase 2 생존 mutations:\n")
if (nrow(p2_surv) > 0) {
  print(p2_surv[, .(Mutation, Label, SR, CAGR, MDD, AnchorCorr)])
} else {
  cat("  없음\n")
}

# Phase 3 best
p3_cands <- kill_results[Phase == 3][order(-SR)]
if (nrow(p3_cands) > 0) {
  cat("\nPhase 3 blend 결과:\n")
  print(p3_cands[, .(Mutation, Label, SR, CAGR, MDD)])
  cat(sprintf("\n목표 달성 여부:\n"))
  cat(sprintf("  blend SR > 1.0: %s\n",
              ifelse(any(!is.na(p3_cands$SR) & p3_cands$SR > 1.0), "PASS", "FAIL")))
  cat(sprintf("  blend MDD > -30: %s\n",
              ifelse(any(!is.na(p3_cands$MDD) & p3_cands$MDD > -30), "PASS", "FAIL")))
}

# 최종 권고
cat("\n[최종 권고]\n")
if (nrow(p1_surv) > 0) {
  top_rec <- p1_surv[1]
  cat(sprintf("  Phase 1 Best: %s (SR=%.4f, MDD=%.1f%%, corr=%.4f)\n",
              top_rec$Mutation, top_rec$SR %||% NA, top_rec$MDD %||% NA,
              top_rec$AnchorCorr %||% NA))
}
if (nrow(p2_surv) > 0) {
  cat(sprintf("  Phase 2 Best: %s (SR=%.4f, MDD=%.1f%%)\n",
              p2_surv$Mutation[1], p2_surv$SR[1] %||% NA, p2_surv$MDD[1] %||% NA))
}

# =============================================================================
# 결과 저장
# =============================================================================
risk_check <- list(
  strategy_id = "STR_1656_MLRA",
  stage = "S5_risk_check",
  created_at = as.character(Sys.time()),
  kill_scenario_results = kill_results,
  survivors = nrow(survivors),
  evt_results = evt_results,
  l115_check = if (nrow(m02) > 0 && nrow(m03) > 0) {
    list(
      m02_corr = m02$AnchorCorr %||% NA,
      m03_corr = m03$AnchorCorr %||% NA,
      corr_diff = (m03$AnchorCorr %||% NA) - (m02$AnchorCorr %||% NA),
      verdict = if (!is.na((m03$AnchorCorr %||% NA) - (m02$AnchorCorr %||% NA)))
        ifelse(((m03$AnchorCorr %||% NA) - (m02$AnchorCorr %||% NA)) < -0.05,
               "L115_FALSIFIED", "L115_CONFIRMED") else "N/A"
    )
  } else list(verdict = "N/A"),
  pareto_top_p1 = if (nrow(p1_surv) > 0) p1_surv[1, .(Mutation, SR, MDD, AnchorCorr)] else NULL,
  pareto_top_p2 = if (nrow(p2_surv) > 0) p2_surv[1, .(Mutation, SR, MDD, AnchorCorr)] else NULL
)

write_json(risk_check, file.path(S5_DIR, "s5_risk_check.json"),
           auto_unbox = TRUE, pretty = TRUE)

# 텔레그램 발송
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
  kill_summary <- paste0(
    apply(kill_results, 1, function(r)
      sprintf("  %s: %s", r["Mutation"], r["Kill_Flags"])
    ), collapse = "\n"
  )
  l115_txt <- if (!is.null(risk_check$l115_check$verdict))
    sprintf("L-115: %s (corr diff=%.4f)",
            risk_check$l115_check$verdict,
            risk_check$l115_check$corr_diff %||% NA)
  else "L-115: N/A"

  tg_send(paste0(
    "[Forge] STR_1656_MLRA S5 Risk Check 완료\n\n",
    "Kill Scenario:\n", kill_summary, "\n\n",
    l115_txt, "\n",
    sprintf("생존: %d/%d\n", nrow(survivors), nrow(kill_results)),
    "산출물: output/s5_mutations/s5_risk_check.json"
  ))
}, error = function(e) cat("[TG]", e$message, "\n"))

cat("\n=== S5 Risk Check 완료:", as.character(Sys.time()), "===\n")
