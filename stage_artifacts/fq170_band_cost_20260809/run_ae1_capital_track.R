## AE1 — D03 D3~D4 직접 소비를 **계약 경로**로 자본 트랙 측정
## 사전등록(측정 전 고정, 이 주석이 정본):
##  AD1 gross(자기 top-25 대비) +10.279%p t 2.572. 이를 **절대 basis · net** 으로 전환한다.
##  ★proxy 손계산 금지(measurement-graduation §1) → canonical_screen_bt() 경유.
##  신호 변환: score = -|decile - 3.5| (D3/D4 가 최상위가 되도록). top_n=25, 15bps, liq 2e8.
##  ★AE2 다중검정 병기: 규칙은 9개 연속쌍 중 argmax 선택 = **selection operator**.
##    measurement-graduation §3 상 sweep 형에 해당할 개연 → DSR 게이트 대상 여부를 판정에 병기한다.
##    본 라운드는 selection_type="sweep" 로 **보수적 라벨**하고 n_trials=9 를 기록한다.
##   AF1 자격 후보: 절대 PORT_t >= 2.95 → 정식 dossier 경로
##   AF2 미달: PORT_t < 2.95 → 차등 소비 규칙 수준에서 수렴, 자본 트랙 닫힘
##  AF3 대조: D03 top-25(변환 없음) 도 같이 재서 '밴드가 상단보다 낫다' 를 절대 basis 에서 확인
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
cat("[p0_panels 구성]", paste(names(P), collapse=", "), "\n")
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)

bench <- NULL
for (nm in names(P)) {
  z <- try(as.data.table(P[[nm]]), silent=TRUE)
  if (!inherits(z,"try-error") && "BM_Ret" %in% names(z)) { bench <- z[, .(Date, BM_Ret)]; cat("[bench] p0_panels$", nm, "\n", sep=""); break }
}
if (is.null(bench)) {
  bp <- "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet"
  if (file.exists(bp)) { suppressPackageStartupMessages(library(arrow))
    z <- as.data.table(read_parquet(bp)); cat("[bench] pinned parquet:", paste(names(z), collapse=","), "\n")
    if ("BM_Ret" %in% names(z)) bench <- unique(z[, .(Date, BM_Ret)]) }
}
if (is.null(bench)) { cat("★벤치 미발견 — 절대 basis 측정 불가. 라운드 중단(계약 경로 필수).\n"); quit(status=0) }
bench <- unique(bench[!is.na(BM_Ret)])[order(Date)]
cat(sprintf("[bench 실측] %d개월 · %s ~ %s\n", nrow(bench), min(bench$Date), max(bench$Date)))

D <- B[!is.na(D03_EWMA)]
D <- merge(D, ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
D <- merge(D, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
D <- D[is.na(adv) | adv >= 2e8]
D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
D[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]

runs <- list(band_D3D4 = D[, .(Date, Ticker, score = -abs(q - 3.5))],
             top_plain = D[, .(Date, Ticker, score = D03_EWMA)])
res <- list()
for (nm in names(runs)) {
  r <- try(canonical_screen_bt(runs[[nm]], ret[, .(Date,Ticker,Ret_1m)], bench,
                               top_n = 25L, cost_bps_oneway = 15,
                               liq_dt = liq[, .(Date,Ticker,adv)], liq_min = 2e8,
                               run_id = paste0("AE1_", nm), strategy_id = paste0("AE1_", nm)),
           silent = TRUE)
  if (inherits(r, "try-error")) { cat(sprintf("[%s] 실행 실패: %s\n", nm, conditionMessage(attr(r,"condition")))); next }
  res[[nm]] <- r
  m <- r$metrics; bc <- r$benchmark_compare
  pt <- if (!is.null(bc) && "Portfolio_Alpha_t_NW_lag3" %in% rownames(as.data.frame(bc)))
          as.data.frame(bc)["Portfolio_Alpha_t_NW_lag3", 1] else NA_real_
  cat(sprintf("\n[%s] metric_type=%s\n", nm, r$manifest$metric_type %||% "?"))
  print(utils::head(as.data.frame(m), 12))
  cat(sprintf("  PORT_t(NW3) = %s\n", as.character(pt)))
}
saveRDS(res, file.path(OUT, "ae1_canonical_runs.rds"))
cat("\n★AE2 병기: 규칙 = 9 연속쌍 중 argmax 선택 → selection_type='sweep', n_trials=9 (보수적 라벨)\n")
cat("★자본 자격은 PORT_t>=2.95 ∧ oos_retention>=0.7 ∧ calmar>=0.64 동시 충족 시에만.\n")
