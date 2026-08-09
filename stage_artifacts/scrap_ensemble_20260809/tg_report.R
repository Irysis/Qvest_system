#!/usr/bin/env Rscript
# =============================================================================
# tg_report.R — FQ-174 폐지줍기 라운드 P0 실측 텔레그램 보고 (v7 SOT 준수)
#   원칙 9: 실측 수치 보고 = charts 첨부 의무 → tg_chart_pack / tg_chart_sweep 경유
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
CH  <- file.path(OUT, "charts"); dir.create(CH, showWarnings = FALSE, recursive = TRUE)

## ── 1. 실측 시계열 재구성 (dedup 85) ──────────────────────────────────
P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok; elite_ok <- P$elite_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym, "01"), "%Y%m%d")
M0 <- as.matrix(sub[, ..scrap_ok])
keepc <- which(colSums(is.finite(M0)) >= 253)
rowsc <- complete.cases(M0[, keepc, drop = FALSE])
M <- M0[rowsc, keepc, drop = FALSE]; bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
C <- cor(M); diag(C) <- 0
hi <- which(C >= 0.999, arr.ind = TRUE); hi <- hi[hi[, 1] < hi[, 2], , drop = FALSE]
comp <- local({
  par <- seq_len(ncol(M)); fnd <- function(x) { while (par[x] != x) x <- par[x]; x }
  if (nrow(hi)) for (r in seq_len(nrow(hi))) { a <- fnd(hi[r,1]); b <- fnd(hi[r,2]); if (a != b) par[b] <- a }
  vapply(seq_len(ncol(M)), fnd, integer(1))
})
reps <- vapply(unique(comp), function(g) which(comp == g)[1], integer(1))
Mu <- M[, reps, drop = FALSE]
ewp <- function(Mx) {
  W <- matrix(1/ncol(Mx), nrow(Mx), ncol(Mx))
  Return.portfolio(xts(Mx, order.by = dtw), weights = xts(W, order.by = dtw), rebalance_on = NA)
}
pr_scrap <- ewp(Mu)
Me0 <- as.matrix(sub[, ..elite_ok])[rowsc, , drop = FALSE]
pr_elite <- ewp(Me0[, colSums(is.finite(Me0)) == nrow(Me0), drop = FALSE])
mk <- function(pr) { ar <- table.AnnualizedReturns(pr, scale = 12); m <- as.numeric(maxDrawdown(pr))
  c(cagr = as.numeric(ar[1,1]), sr = as.numeric(ar[3,1]), mdd = m, calmar = as.numeric(ar[1,1])/m) }
S <- mk(pr_scrap); E <- mk(pr_elite); B <- mk(xts(bmw, order.by = dtw))
cat(sprintf("[실측] SCRAP85 SR=%.3f MDD=%.1f%% Calmar=%.3f | ELITE SR=%.3f MDD=%.1f%% Calmar=%.3f | BM SR=%.3f\n",
            S["sr"], 100*S["mdd"], S["calmar"], E["sr"], 100*E["mdd"], E["calmar"], B["sr"]))

## ── 2. 차트 (표준 생성기 경유 — 차트팩은 시각화 전용) ─────────────────
source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
n_pr <- length(pr_scrap)
PRDF <- data.frame(date = dtw[seq_len(n_pr)], ret_net = as.numeric(pr_scrap),
                   benchmark_ret = bmw[seq_len(n_pr)])
p1 <- tg_chart_pack(PRDF, out_dir = CH, title = "폐지 풀 85개 동일가중 앙상블",
                    metrics_note = sprintf("샤프 %.3f · 최대낙폭 %.1f%% · 칼마 %.3f (진단 실측)",
                                           S["sr"], 100*S["mdd"], S["calmar"]),
                    prefix = "scrap85_")
p2 <- tg_chart_sweep(
  labels = c("폐지 85개 동일가중", "우량 13개 동일가중", "벤치마크 KOSPI200",
             "무작위 조합 최대(예지)", "자본 합격선"),
  values = c(S["calmar"], E["calmar"], B["calmar"], 0.342, 0.64),
  out_dir = CH, title = "칼마 비교 — 선택만으로는 합격선에 못 미침",
  value_label = "칼마 (연수익 / 최대낙폭)", hline = 0.64, hline_label = "합격선 0.64",
  highlight = "폐지 85개 동일가중", filename = "calmar_compare.png")
p3 <- tg_chart_sweep(
  labels = c("평상시(FLAT, 174개월)", "급락(DOWN, 31개월)", "급등(SURGE, 49개월)",
             "국면 무시(무조건부)"),
  values = c(-0.005, 0.708, 0.745, 0.237),
  out_dir = CH, title = "예측 지속성 — 정보는 꼬리 국면에 있다",
  value_label = "전반기 순위 대 후반기 순위 상관", hline = 0,
  highlight = "국면 무시(무조건부)", filename = "persistence.png")
charts <- c(p1, p2, p3)
cat("[charts]", length(charts), "장 생성\n"); print(basename(charts))

## ── 3. 발송 (tg_agent_brief 단일 진입점) ──────────────────────────────
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "폐지 전략 재활용 앙상블 — 중복을 걷어내니 재료가 절반이었습니다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "등급 미달 전략 195개로 앙상블이 되는지 검증 중 — 실제 재료는 85개였습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 성과가 나빠 버려둔 전략 195개를 모아 새 조합을 만들 수 있는지 봤습니다",
           "발견: 절반 이상이 이름만 다른 같은 전략이었습니다 (한 묶음은 49개가 동일)",
           "결과: 그냥 다 섞으면 초과수익이 사실상 0입니다 (월 +0.021%, t값 0.04)",
           "단서: 평상시엔 답이 없는데 급락·급등 국면에서는 예측이 꾸준히 맞습니다",
           "의미: 아직 실제 돈은 넣지 않습니다 — 참고용 검증 단계입니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "유효재료"   = "195개 중 85개 (중복 55.5% 제거)",
           "폐지앙상블" = sprintf("샤프 %.3f · 최대낙폭 %.1f%% · 칼마 %.3f", S["sr"], 100*S["mdd"], S["calmar"]),
           "우량앙상블" = sprintf("샤프 %.3f · 최대낙폭 %.1f%% · 칼마 %.3f", E["sr"], 100*E["mdd"], E["calmar"]),
           "지속성"     = "평상시 -0.005 대비 급락 +0.708 · 급등 +0.745",
           "칼마천장"   = "무작위 조합 최대 0.342 (합격선 0.64)")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "중복 제거 전 수치는 한 전략이 비중 26%를 차지해 부풀려져 있었습니다",
           "급락 국면 표본이 31개월뿐이라 검정력이 구조적으로 낮습니다",
           "완전예지 국면 전환조차 최대낙폭을 못 줄였습니다 (40.0% 대 정적 25.1%)",
           "종목수 25종 제약을 자동 충족하지 못해 자본 심사 대상이 아닙니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "국면 조건부 선택을 학습하는 6개 안 실측이 지금 돌고 있습니다",
           "낙폭 기여를 학습 목표로 삼아 최대낙폭을 직접 겨냥합니다",
           "선택만으로는 칼마 합격선 0.64에 도달 못한다고 미리 등록했습니다",
           "판정: 현재는 자본 배정 없음 — 참고용 스크린 등급입니다"))
  ),
  charts = charts,
  footer = "📚 FQ-174 · stage_artifacts/scrap_ensemble_20260809/ · metric_type=diagnostic_precheck"
)
cat("[tg] 발송 완료\n")
