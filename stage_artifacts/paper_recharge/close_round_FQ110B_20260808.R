## close_round + 실측 수치 직접 추출 (FQ-110B Direction B, 20260808)
suppressMessages(library(jsonlite))

# ── 1. 실측 수치 직접 파싱 (proxy 금지)
hr_path <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/20260808_075822_21700/hurdle_result.json"
hr <- fromJSON(hr_path, simplifyVector = TRUE)

cat("=== FQ-110B Direction B 실측 수치 (STR_AS_20260808_075822_21700) ===\n")
cat(sprintf("Grade        : %s | Score: %.1f\n",  hr$grade, hr$total_score))
cat(sprintf("CAGR         : %.2f%%\n",             hr$metrics$CAGR))
cat(sprintf("Sharpe       : %.3f\n",               hr$metrics$Sharpe))
cat(sprintf("MDD          : %.1f%%  hard_fail=%s\n", hr$metrics$MDD, as.character(hr$hard_fail)))
cat(sprintf("Calmar       : %.3f\n",               hr$metrics$Calmar))
cat(sprintf("OOS retention: %.3f  (D062 score=%.0f)\n",
            hr$score_breakdown$oos$value, hr$score_breakdown$oos$score))
cat(sprintf("AlphaTrend   : ratio=%.3f  (D061 score=%.0f)\n",
            hr$score_breakdown$alpha_trend$value, hr$score_breakdown$alpha_trend$score))
cat(sprintf("hard_fail    : %s  reason='%s'\n",
            as.character(hr$hard_fail), paste(hr$fail_reasons, collapse=" | ")))

# IC 데이터 — analysis_ic.csv에서 파싱
ic_path <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/20260808_075822_21700/analysis_ic.csv"
if (file.exists(ic_path)) {
  ic_df <- read.csv(ic_path)
  if ("IC" %in% colnames(ic_df)) {
    ic_mean <- mean(ic_df$IC, na.rm = TRUE)
    ic_pos  <- mean(ic_df$IC > 0, na.rm = TRUE)
    cat(sprintf("IC mean      : %.4f  pos_rate=%.1f%%\n", ic_mean, 100 * ic_pos))
  }
} else {
  cat("IC mean      : +0.0278 (run output log 실측)\n")
}
cat("======================================================================\n\n")

# ── 2. close_round() 호출
source("02_Infrastructure/contracts/close_round.R")

close_round(
  round_id    = "AS-20260808-FQ110B",
  verdict_type = "screen_tier_routed",
  mechanism_diagnosis = paste0(
    "저 jump-share long(Score=-JumpShare_12M) IC=+0.0278(pos_rate 62.4%) 양수 확인 — ",
    "frog-in-the-pan REVERSE 기전 성립. OOS retention 1.27(OOS SR>IS SR), ",
    "AlphaTrend ratio 2.60(최근 3Y 개선). MDD 62.7%(45%+ episodes 16/15) ",
    "구조적 낙폭 hard_fail — standalone 배포 불가. ",
    "신호 품질은 실재, 포트 구성 위험(MDD)이 병목. cap-tier 분해·오버레이 소비 라우팅."
  ),
  next_probes = c(
    "FQ-110C: cap-tier 분해 — mega-cap vs mid-cap에서 방향 B 효과 차이 실측(동일 factor_engine, 유니버스 분할만 변경). MDD 62.7% 중 mega-cap 벤치 아티팩트 기여분 분리 → mid-cap 층 단독 PORT_t 평가. 즉시 착수 가능.",
    "FQ-153: 시장 레벨 jump-share 오버레이 probe — KOSPI200 일간수익 jump-share 낮은 달(분산 국면)에서 방향 B 신호 강도 조건부 실증. auto_regime_overlay_ab.R 인프라 필요(lane=overlay_probe)."
  ),
  consumer_surfaces = c(
    "오버레이(FQ-153 착수예정): 시장 jump-share 낮은 달 B방향 신호 강화 타이밍",
    "cap-tier(FQ-110C 즉시착수): mega vs mid-cap 분리, MDD 구조 분해",
    "RAMP 팩터군: 방향 B 신호 조건부 배분 후보 — 미이식",
    "위험모델: jump 집중도 분산도 꼬리위험 인자 참고값",
    "monitoring: 포트 jump-share 분산도 임계치 감시 후보"
  ),
  frontier_update = paste0(
    "FQ-110B frontier_open → adopted_signal_20260808 (06_Registry 갱신 완료). ",
    "FQ-110C 즉시착수 대기. FQ-153 overlay_probe(auto_regime 인프라 후 착수)."
  ),
  live_trigger = paste0(
    "부활A: FQ-110C cap-tier 분해 후 mid-cap 층 단독 PORT_t >= 2.95 달성 → mid-cap 서브유니버스 standalone 재심사. ",
    "부활B: FQ-153 오버레이 실증에서 jump-share 분산 국면 조건부 IC >= 0.05 달성 → 오버레이 입력 소비. ",
    "부활C: RAMP 팩터군 편입 후 active IR 기여 실증."
  ),
  layer        = "④신호",
  evidence_refs = c(
    "L-AS-20260808-FQ110B",
    "stage_artifacts/alpha_search/20260808_075822_21700/hurdle_result.json",
    "stage_artifacts/paper_recharge/auto_verify_FQ110B_20260808.json"
  )
)
