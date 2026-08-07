# =============================================================================
# run_FQ110.R — FQ-110 JumpShare_12M alpha-search 실행 스크립트
# =============================================================================
# 양방향 테스트:
#   방향A (+score): 높은 jump_share → positive (jump momentum)
#   방향B (-score): 낮은 jump_share → positive (frog-in-the-pan)
# 두 방향의 IC 확인 후 우세 방향 결정
# =============================================================================

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source(file.path(PROJECT_ROOT, "02_Infrastructure/alpha_search/run_alpha_search.R"))

FE_PATH <- file.path(PROJECT_ROOT,
  "stage_artifacts/alpha_search_FQ110/factor_engine_JumpShare.R")

# ---- 방향A: +score (jump momentum — 집중형이 강한 신호) ---------------------
cat("\n========== FQ-110 방향A: JumpShare+ (jump momentum) ==========\n")
res_A <- run_alpha_search(
  strategy_name      = "FQ110_JumpShare_A",
  strategy_idea      = paste0(
    "FQ-110: 12M 창 상위-5 |일간수익| 비중(jump_share) 직접 팩터화. ",
    "방향A(+): 높은 집중도 = 강한 모멘텀 신호. ",
    "frog-in-the-pan 기전 양방향 실증."
  ),
  factor_engine_path = FE_PATH,
  n_holdings         = 25L,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = FALSE   # 방향 결정 후 최종만 발송
)
cat(sprintf("[FQ110-A] grade=%s score=%.1f pass=%s\n",
    res_A$grade, res_A$score, res_A$pass))
cat(sprintf("[FQ110-A] excess_cagr=%.2f%%\n", res_A$excess_cagr * 100))

# ---- 방향B: -score (frog-in-the-pan — 분산형이 지속 성과) -------------------
cat("\n========== FQ-110 방향B: JumpShare- (frog-in-the-pan) ==========\n")

# 방향B용 factor_engine: Score = -JumpShare (낮을수록 매수)
FE_PATH_B <- file.path(PROJECT_ROOT,
  "stage_artifacts/alpha_search_FQ110/factor_engine_JumpShare_B.R")

writeLines(c(
  '# factor_engine_JumpShare_B.R — 방향B: Score = -JumpShare (낮을수록 매수)',
  'source("stage_artifacts/alpha_search_FQ110/factor_engine_JumpShare.R")',
  '# FACTORS already computed above with Score = JumpShare',
  '# Reverse direction: frog-in-the-pan (낮은 jump_share = 분산 = 지속)',
  'FACTORS[, Score := -Score]',
  'cat(sprintf("[factor_engine_JumpShare_B] Score reversed. median=%.4f\\n", median(FACTORS$Score, na.rm=TRUE)))'
), FE_PATH_B)

res_B <- run_alpha_search(
  strategy_name      = "FQ110_JumpShare_B",
  strategy_idea      = paste0(
    "FQ-110: 12M 창 상위-5 |일간수익| 비중(jump_share) 역방향. ",
    "방향B(-): 낮은 집중도 = frog-in-the-pan(소리 없이 오른 주식). ",
    "분산형 점진 상승이 지속 성과를 내는지 실증."
  ),
  factor_engine_path = FE_PATH_B,
  n_holdings         = 25L,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = FALSE
)
cat(sprintf("[FQ110-B] grade=%s score=%.1f pass=%s\n",
    res_B$grade, res_B$score, res_B$pass))
cat(sprintf("[FQ110-B] excess_cagr=%.2f%%\n", res_B$excess_cagr * 100))

# ---- 방향 결정 및 최종 발송 -------------------------------------------------
cat("\n========== 방향 비교 ==========\n")
cat(sprintf("A(+, jump_momentum): grade=%s score=%.1f excess_cagr=%.2f%%\n",
    res_A$grade, res_A$score, res_A$excess_cagr * 100))
cat(sprintf("B(-, frog_in_pan):   grade=%s score=%.1f excess_cagr=%.2f%%\n",
    res_B$grade, res_B$score, res_B$excess_cagr * 100))

# 우세 방향: score 기준
if (res_A$score >= res_B$score) {
  winner <- "A"
  res_win <- res_A
  direction_label <- "jump_momentum (+score)"
} else {
  winner <- "B"
  res_win <- res_B
  direction_label <- "frog_in_pan (-score)"
}
cat(sprintf("우세 방향: %s (%s)\n", winner, direction_label))

# ---- 결과를 파일로 저장 -------------------------------------------------------
OUT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/alpha_search_FQ110")
result_summary <- list(
  fq_id          = "FQ-110",
  run_date       = format(Sys.time(), "%Y%m%d_%H%M%S"),
  direction_A    = list(
    grade = res_A$grade, score = res_A$score, pass = res_A$pass,
    excess_cagr = res_A$excess_cagr,
    strategy_id = res_A$strategy_id,
    out_dir = res_A$out_dir
  ),
  direction_B    = list(
    grade = res_B$grade, score = res_B$score, pass = res_B$pass,
    excess_cagr = res_B$excess_cagr,
    strategy_id = res_B$strategy_id,
    out_dir = res_B$out_dir
  ),
  winner         = winner,
  direction_label = direction_label,
  winning_grade  = res_win$grade,
  winning_score  = res_win$score
)

library(jsonlite)
write_json(result_summary, file.path(OUT_DIR, "fq110_result_summary.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat("[FQ110] result_summary saved.\n")

# ---- 텔레그램 발송 (우세 방향 결과) -----------------------------------------
# 메트릭 추출
library(data.table)
hurdle <- res_win$hurdle_result
notable <- res_win$notable

port_t    <- hurdle$metrics$port_t
oos_ret   <- hurdle$metrics$oos_retention
calmar    <- hurdle$metrics$calmar
sr        <- hurdle$metrics$sr
cagr      <- hurdle$metrics$cagr
mdd       <- hurdle$metrics$mdd
turnover  <- hurdle$metrics$turnover
excess_c  <- res_win$excess_cagr * 100

gate_decision <- ifelse(res_win$pass, "ADOPT", "QUARANTINE")

source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

# IC 방향 및 기전 판단
ic_direction_text <- if (winner == "A") {
  "jump_share 높을수록(집중형) 수익 우위 — jump momentum 기전"
} else {
  "jump_share 낮을수록(분산형) 수익 우위 — frog-in-the-pan 기전"
}

mechanism_diag <- if (winner == "A") {
  "수익 집중형(소수 날 급등) 주식이 모멘텀 연장 — 점프 탄성 기전 실증"
} else {
  "수익 분산형(조용히 꾸준히 오른) 주식의 지속성 — frog-in-the-pan 기전 실증"
}

grade_explain <- switch(res_win$grade,
  "A" = "Grade A: 자본 투입 후보 — 관리자(도훈) 수동 승인 대기",
  "B" = "Grade B: 스크리닝 통과 — 추가 정교화 여지",
  "C" = "Grade C: 신호는 있으나 자본 투입 기준 미달 — 참고용 보관",
  "D" = "Grade D: 약한 신호 — QUARANTINE",
  "F" = "Grade F: 신호 없음 — QUARANTINE"
)

tg_agent_brief(
  agent  = "AlphaSearch",
  title  = paste0("FQ-110 JumpShare_12M jump-share 팩터 검증 완료 (20260807)"),
  sections = list(
    list(type = "summary",
         body = paste0(
           "12개월 창에서 수익이 소수 날짜에 집중되는 정도를 팩터로 직접 측정했습니다. ",
           "우세 방향: ", direction_label, ". 판정: ", gate_decision, "."
         )),
    list(type = "bullet", emoji = "\U0001f4d6", heading = "\EC\89\AC\EC\9A\B4 \EC\84\A4\EB\AA\85",
         items = c(
           paste0("\EC\8B\9C\EB\8F\84: 12\EA\B0\9C\EC\9B\94 \EC\B0\BD\EC\97\90\EC\84\9C \EA\B0\80\EC\9E\A5 \ED\81\B0 |",
                  "\EC\9D\BC\EA\B0\84\EC\88\98\EC\9D\B5\EB\A5\A0| 5\EA\B1\B4\EC\9D\98 \ED\95\A9\EA\B3\84\EB\A5\BC ",
                  "\EC\A0\84\EC\B2\B4 \EC\88\98\EC\9D\B5 \ED\95\A9\EA\B3\84\EB\A1\9C \EB\82\98\EB\88\88 \EB\B9\84\EC\9C\A8\EB\A1\9C 20\EB\85\84 \EB\AA\A8\EC\9D\98\EC\9A\B4\EC\9A\A9"),
           paste0("\EB\B0\A9\EB\B2\95: K200+KQ150 \EC\9C\A0\EB\8B\88\EB\B2\84\EC\8A\A4\EB\A1\9C 2005~\ED\98\84\EC\9E\AC \EB\B0\B1\ED\85\8C\EC\8A\A4\ED\8C\85 (25\EC\A2\85\EB\AA\A9 \EA\B7\A0\EB\93\B1\EB\B9\84\EC\A4\91)"),
           paste0("\EA\B2\B0\EA\B3\BC: \EC\9A\B0\EC\84\B8 \EB\B0\A9\ED\96\A5(", direction_label, ") ",
                  "grade=", res_win$grade, " | PORT_t=", round(port_t, 2),
                  " (2.95 \EA\B8\B0\EC\A4\80)"),
           paste0("\EC\9D\98\EB\AF\B8: ", gate_explain(gate_decision))
         )),
    list(type = "kv", emoji = "\U0001f4ca", heading = "\ED\95\B5\EC\8B\AC \EC\88\98\EC\B9\98",
         kv = list(
           "\EB\93\B1\EA\B8\89"              = res_win$grade,
           "\EC\A2\85\ED\95\A9\EC\A0\90\EC\88\98"       = round(res_win$score, 1),
           "PORT_t(\EB\8B\A4\EC\A4\91\EA\B2\80\EC\A0\95)"  = round(port_t, 3),
           "OOS\EC\9C\A0\EC\A7\80\EC\9C\A8"   = round(oos_ret, 3),
           "\EC\B9\BC\EB\A7\88\EB\B9\84\EC\9C\A8"          = round(calmar, 3),
           "\EC\83\A4\ED\94\84\EC\A7\80\EC\88\98"           = round(sr, 3),
           "\EC\97\B0\EB\B3\B5\EB\A6\AC\EC\88\98\EC\9D\B5\EB\A5\A0"     = paste0(round(cagr * 100, 2), "%"),
           "\EC\B4\88\EA\B3\BC\EC\88\98\EC\9D\B5(vs BM)"    = paste0(round(excess_c, 2), "pp"),
           "\EC\B5\9C\EB\8C\80\EB\82\99\ED\8F\AD"           = paste0(round(mdd * 100, 2), "%"),
           "\ED\9A\8C\EC\A0\84\EC\9C\A8"            = paste0(round(turnover * 100, 1), "%/yr")
         )),
    list(type = "bullet", emoji = "\U0001f9ea", heading = "IC \EB\B0\A9\ED\96\A5 \EA\B2\80\EC\A6\9D",
         items = c(
           paste0("\EB\B0\A9\ED\96\A5A(jump_momentum+): grade=", res_A$grade,
                  " score=", round(res_A$score, 1),
                  " excess=", round(res_A$excess_cagr * 100, 2), "pp"),
           paste0("\EB\B0\A9\ED\96\A5B(frog_in_pan-): grade=", res_B$grade,
                  " score=", round(res_B$score, 1),
                  " excess=", round(res_B$excess_cagr * 100, 2), "pp"),
           paste0("\EC\8B\A4\EC\A6\9D \EA\B8\B0\EC\A0\84: ", ic_direction_text),
           paste0("\EA\B8\B0\EC\A0\84 \EC\A7\84\EB\8B\A8: ", mechanism_diag)
         )),
    list(type = "bullet", emoji = "\U0001f6a9", heading = "\EC\A3\BC\EC\9D\98",
         items = c(
           paste0("\ED\9A\8C\EC\A0\84\EC\9C\A8 \EC\A3\BC\EC\9D\98: ", round(turnover * 100, 1),
                  "%/yr — PATHQ \EA\B3\204\EC\97\B4 \EB\8C\200\EB\B9\84 \ED\99\95\EC\9D\B8 \ED\95\84\EC\9A\94"),
           paste0("OOS\EC\9C\A0\EC\A7\80\EC\9C\A8 ", round(oos_ret, 3),
                  " (0.7 \EC\9D\B4\EC\83\81 \ED\95\A9\EA\B2\A9 / 0.5 \EB\AF\B8\EB\A7\8C \EB\B6\88\ED\95\A9\EA\B2\A9)"),
           paste0("\EA\B3\214\EC\82\B0 \EB\B9\84\EC\9A\A9: frollapply 252\EC\9D\BC window — \EB\8B\A4\EC\88\98 \EC\A2\205\EB\AA\A9\EC\97\90\EC\84\9C \EC\8B\A4\ED\96\89 \EC\8B\9C\EA\B0\84 \EB\A1\B1")
         )),
    list(type = "bullet", emoji = "➡️", heading = "\EB\8B\A4\EC\9D\8C",
         items = c(
           paste0("\EB\8B\A4\EC\9D\8C \ED\83\90\EC\83\89 1: cap-tier \EB\B6\84\ED\95\B4 (MEGA vs MID) \EB\B3\204 jump_share \EC\B0\A8\EB\B3\84 \ED\99\95\EC\9D\B8 (FQ-111 \EB\93\B1\EC\9E\AC \EA\B6\8C\EA\B3\A0)"),
           paste0("\EB\8B\A4\EC\9D\8C \ED\83\90\EC\83\89 2: jump_share\xb7\xb4 \EC\88\98\EC\9D\B5\EB\A5\A0 \EC\9E\90\EA\B8\B0\EC\83\81\EA\B4\80(T_RetAutoCorr FQ-094) ",
                  "\EC\A1\B0\ED\95\A9 \EC\8B\A4\EC\A6\9D — \EB\91\90 \EC\8B\A0\ED\98\B8\EA\B0\80 \EB\8F\85\EB\A6\BD\EC\A0\81\EC\9D\B4\EB\A9\B4 \EB\B3\B5\ED\95\A9 \EA\B0\80\EB\8A\A5\EC\84\B1")
         ))
  ),
  charts = res_win$charts,
  relaxed = TRUE,
  force = TRUE
)

cat("[FQ110] Telegram sent.\n")
cat(sprintf("[FQ110] gate_decision=%s | grade=%s | PORT_t=%.3f | oos=%.3f | calmar=%.3f\n",
    gate_decision, res_win$grade, port_t, oos_ret, calmar))
cat(sprintf("[FQ110] winner_direction=%s | mechanism=%s\n", winner, mechanism_diag))

# 결과 저장 (done 파일 append는 별도 스크립트)
saveRDS(list(res_A = res_A, res_B = res_B, winner = winner,
             res_win = res_win, gate_decision = gate_decision,
             mechanism_diag = mechanism_diag),
        file.path(OUT_DIR, "fq110_run_results.rds"))
cat("[FQ110] RDS saved.\n")

# ---- 헬퍼 함수 ---------------------------------------------------------------
gate_explain <- function(gd) {
  if (gd == "ADOPT") "\EC\8B\A4\EC\A0\9C \EC\9E\90\EB\B3\B8 \EB\B0\B0\EC\A0\95 \ED\9B\84\EB\B3\B4 (\EC\B5\9C\EC\A2\85 \EC\8A\B9\EC\9D\B8\EC\9D\80 \EB\8F\84\ED\9B\88 \EC\88\98\EB\8F\99)"
  else "\EC\8B\A0\ED\98\B8\EB\8A\94 \EC\9E\88\EC\A7\80\EB\A7\8C \EC\9E\90\EB\B3\B8 \ED\88\AC\EC\9E\85 \EA\B8\B0\EC\A4\80 \EB\AF\B8\EB\8B\AC \EB\98\220\EB\8A\94 \EC\8B\A0\ED\98\B8 \EB\B6\80\EC\9E\AC \xEB\A1\9C QUARANTINE"
}
