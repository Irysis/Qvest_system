#!/usr/bin/env Rscript
# FQ-017 post-processing: charts (sweep + best-arm standard-3) + L-code emit + telegram + FQ update.
# Reads measured results from disk (paired.csv / scenarios.csv). Rebuilds ONLY best-arm period_returns
# for visualization (deterministic; judgment numbers come from the CSVs — no re-measurement of verdict).
suppressMessages({ library(data.table); library(jsonlite) })
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(root)
OUT <- file.path(root, "stage_artifacts/m1_overlay_drain")
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||all(is.na(a))) b else a

Sys.setenv(QVEST_DRAIN_NORUN = "1")
source("02_Infrastructure/regime/overlay_candidate_drain.R")   # weighted_screen_bt
source("02_Infrastructure/telegram/tg_chart_pack.R")
source("02_Infrastructure/axiom/lcode_emit.R")
# PerformanceAnalytics masks graphics::legend (diff formals -> 'argument 4 matches multiple formal args').
# tg_chart_pack.R calls bare legend(); force the base one in globalenv so it resolves first (local, no infra edit).
legend <- graphics::legend

paired <- fread(file.path(OUT, "paired.csv"))
scen   <- fread(file.path(OUT, "scenarios.csv"))
cat("[disk] paired + scenarios loaded (no re-measurement of verdict)\n")

# ---- rebuild best-arm (LARGE_tilt) period_returns for standard-3 chart ----
ym2date <- function(ym) as.Date(sprintf("%d-%02d-01", ym %/% 100L, ym %% 100L))
KAPPA <- 0.30; COST_BPS <- 15
P <- as.data.table(readRDS("stage_artifacts/WT_D20260711_002/signal_panel.rds"))
P <- P[is.finite(z1) & is.finite(Ret_1m) & is.finite(BM_Ret)]
returns_dt <- unique(P[, .(Date = ym2date(ym), Ticker, Ret_1m)])
bench_dt   <- unique(P[, .(Date = ym2date(ym), BM_Ret)])
De <- P[, .SD[frank(-adv20, ties.method="first") <= 25], by = ym]   # LARGE tier
w_tilt <- De[, .(Date = ym2date(ym), Ticker, w = exp(-KAPPA * pmax(pmin(z1,3),-3)))]
w_tilt[, w := w / sum(w), by = Date]
best <- weighted_screen_bt(w_tilt, returns_dt, bench_dt, cost_bps_oneway = COST_BPS,
                           run_id = "LARGE_tilt", strategy_id = "LARGE_tilt")
pr_best <- as.data.table(best$period_returns)   # date, ret_net, benchmark_ret

# ---- chart 1: scenario-ranking sweep (paired NW-t across 4 overlay arms; hline 2.0) ----
sweep_png <- tg_chart_sweep(
  labels = paired$arm, values = round(paired$paired_nw_t_lag3, 3),
  out_dir = OUT, title = "FQ-017 m1 오버레이 — 시나리오별 증분 NW-t (base 대비)",
  value_label = "paired NW-t (lag3)", hline = 2.0, hline_label = "합격선 2.0",
  highlight = "LARGE_tilt", filename = "m1_overlay_sweep.png")

# ---- chart 2-4: best-arm (LARGE_tilt) standard 3 ----
mnote <- sprintf("LARGE_tilt · capw_PORT_t %.2f · paired NW-t %.2f(<2.0) · +%.0fbps/yr · net15bps",
                 scen[arm=="LARGE_tilt", capw_PORT_t], paired[arm=="LARGE_tilt", paired_nw_t_lag3],
                 paired[arm=="LARGE_tilt", mean_d_ann_bps])
std3 <- tg_chart_pack(pr_best, out_dir = OUT,
                      title = "FQ-017 m1 오버레이 최선안 (LARGE_tilt)",
                      metrics_note = mnote, prefix = "m1_best_")
charts <- c(sweep_png, std3)
charts <- charts[file.exists(charts)]
cat("[charts] generated:", length(charts), "\n"); print(basename(charts))

# ---- L-code emit (return is a PATH STRING — no $ access; construction_type EXPLICIT) ----
lc <- emit_lcode(
  mode = "alpha_research",
  strategy_id = "FQ-017_m1_overlay_drain",
  grade = "F",                         # overlay fails the 2.0 paired-NW-t bar (screen-tier disposition)
  metric_type = "canonical_screen",    # contract-grade screen via weighted_screen_bt (canonical_screen_bt generalization); sub-authoritative
  construction_type = "overlay_stock_exclusion_tilt",   # cross-sectional stock-level; NOT overlay_regime
  selection_type = "chain",
  record_type = "performance",
  portfolio_alpha_t = round(paired[arm=="LARGE_tilt", paired_nw_t_lag3], 3),  # best PAIRED incremental NW-t (labeled below)
  oos_months = 169,
  core_reference = paste("Phase A L-AR-20260712_152759 (m1 TEXT_READABILITY_FEATURE -> OVERLAY_CANDIDATE) /",
                         "prereg.sha256 b93e48f2 / weighted_screen_bt contract primitive"),
  mechanism_hypothesis = paste("공시 난독화 m1(문장길이·Size무관 실신호)을 book 종목단 exclusion/tilt 오버레이로 소비 시",
                               "한계 기여 검증. 캐리어 STR_1715 종목단 보유이력 부재(bt_result$holdings 0행)+대형tier signal-dead+",
                               "드레인러너 오버레이=시장스칼라 -> dual-tier(LARGE 캐리어유사·BROAD m1국소) base에서 계약프리미티브로 실측"),
  falsification_attempts = paste("PIT 4종 전통과: assert_overlay_pit HARD PASS / lag1 스트레스 무붕괴(느린 연간신호) /",
                                 "strict-PIT A/B 인플레 -20~-22%(현재가 오히려 보수적=look-ahead 아님) /",
                                 "IC(-z1,fwd_excess) +2.80 PIT정상방향. paired NW-t 4암 전부 <2.0(최대 LARGE_tilt 1.27)"),
  lesson_text = paste0(
    "m1(문장길이 난독화) OVERLAY_CANDIDATE 드레인 = 종목단 exclusion/tilt 오버레이로 소비해도 한계기여 무의미(합격선 미달). ",
    "paired 증분 NW-t(lag3, base 대비): LARGE(캐리어유사 top-25 유동성) excl 0.75/tilt 1.27(+74bps/yr) · ",
    "BROAD(m1 국소 EW ~294종) excl 0.15(+7bps/yr≈0)/tilt 0.88 — 전부 2.0 미달. ",
    "★ portfolio_alpha_t 필드값 1.27 = 최선안 LARGE_tilt의 '증분 paired NW-t'이지 절대 book PORT_t 아님(오독 주의). ",
    "BROAD_base 자체가 capw_PORT_t 1.52(소형 size premium)인데 m1 오버레이 증분은 ~0 -> m1 신호는 이미 소형 tier 수익에 흡수됨(cap-tier 트랩 재확인). ",
    "BROAD 증분 oos_v2 음수(base -0.05·excl -0.11)=한계효과도 post-2017 감쇠. ",
    "PIT 4종 clean(동월누출 없음). 07-10 드레인 16/16 survivor 0 prior 확증(m1은 crisis-clipping 아닌 종목단 quality형이나 결론 동일). ",
    "판정: SCREEN_TIER 유지 — m1은 feature로 보존(다른 전략 보조), 오버레이 자본기여 자격 없음."),
  tags = c("text_alpha","non_return","screen_tier","overlay_candidate","cap_tier_trap","m1_sentence_len","fq_017"))
cat("[emit] result:", paste(unlist(lc), collapse=" | "), "\n")

# ---- Telegram v7 (agent=Alpha; charts=; kv=; easy explanation + verdict plaintext) ----
source("02_Infrastructure/telegram/telegram_notify.R")
tg <- tg_agent_brief(
  agent = "Alpha",
  title = "FQ-017 공시 난독화(문장길이) 오버레이 드레인 — 합격선 미달, 보조 신호로 보존",
  sections = list(
    list(type="bullet", emoji="📖", heading="쉬운 설명",
         items=c(
           "질문: '읽기 어려운 공시=나쁜 주식'(문장길이 m1)을 기존 포트폴리오에 덧씌우면 성과가 좋아지나?",
           "방법: 난독 최악 종목을 빼거나(exclusion) 비중을 낮추는(tilt) 오버레이를 계약 백테로 14년치 실측",
           "결과: 4가지 방식 모두 base 대비 통계적 개선이 미미(증분 t값 최대 1.27, 합격선 2.0 미달)",
           "이유: 이 신호는 소형주에 몰려 있어 대형주 book에는 힘이 없고, 소형 book에선 이미 크기효과에 흡수됨")),
    list(type="kv", emoji="📊", heading="핵심 실측 (기저 대비 증분 t값, 순비용 15bps 차감)",
         kv=list(
           "대형tier 제외(캐리어유사)"="증분t 0.75 (+102bps/년) — 미달",
           "대형tier 비중조정(최선안)"="증분t 1.27 (+74bps/년) — 미달, 방향만 양(+)",
           "소형tier 제외(m1 국소)"="증분t 0.15 (+7bps/년) — 사실상 0",
           "소형tier 비중조정"="증분t 0.88 (+19bps/년) — 미달",
           "소형 기저 자체 초과수익t"="1.52 = 소형 크기효과(오버레이 몫 아님)")),
    list(type="bullet", emoji="🛡️", heading="PIT 4종 검증 (07-06 재발방지)",
         items=c(
           "assert_overlay_pit HARD 통과 (신호 컷오프 ≤ 홀딩월 시작, 1개월+ 여유)",
           "lag1 스트레스: 붕괴 없음 (느린 연간 신호 — 동월 누출 아님)",
           "strict-PIT A/B: 인플레 -20~-22% (현재 타이밍이 오히려 보수적 = look-ahead 아님)",
           "방향 IC(-z1, 초과수익) +2.80 (명료할수록 초과수익 ↑ = PIT 정상)")),
    list(type="bullet", emoji="⚖️", heading="판정 평문",
         items=c(
           "판정: 오버레이 자본기여 자격 없음 — 이 신호로 book에 비중을 바꾸지 않습니다",
           "보존: m1(문장길이)은 Size-무관 실신호로 feature 보존(다른 전략 보조 재료)",
           "교훈: 소형 국소 신호는 대형 book엔 무력, 소형 book엔 이미 크기효과에 흡수 = cap-tier 트랩 재확인",
           "정직 prior 확증: 07-10 오버레이 드레인 16/16 미달과 동일 결론(기전은 다르나)")),
    list(type="bullet", emoji="➡️", heading="산출·다음",
         items=c(
           "산출: stage_artifacts/m1_overlay_drain/ (결과·paired·차트·challenge_note)",
           "L-code 적립(alpha_research) · FQ-017 status=measured",
           "다음: 비-return 원천(insider 등) — m1은 소진, 보존만"))
  ),
  charts = charts, force = TRUE)
cat("[tg] ok =", isTRUE(tg$ok), "\n")

writeLines(unlist(lc)[1], file.path(OUT, "lcode_id.txt"))
cat("[done] post-processing complete\n")
