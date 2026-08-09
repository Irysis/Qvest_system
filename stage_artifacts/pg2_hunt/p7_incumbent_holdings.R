## p7 — PG2 는 무엇을 들고 있나 (직교 후보를 싸게 좁히는 기준 만들기)
## 논리: ΔIR 은 직교성에서만 온다. 슬리브가 PG2 와 **같은 종목을 같은 달에** 들면 active 가 겹친다.
##   ⇒ 보유 겹침률(overlap) 이 낮은 재료가 사전적으로 유리하다. ΔIR 전수 측정보다 훨씬 싸다.
## ★단 겹침률은 **대리 지표**다 — 진짜 판정은 ΔIR. 여기서는 (겹침률, ΔIR) 관계를 실측해
##   대리 지표가 쓸 만한지 자체를 검정한다(양방향).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p7] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

H <- fread(file.path(ROOT,
  "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results/04_holdings.csv"))
say("=== 1. PG2 보유 실측 ===")
say("  컬럼: %s", paste(names(H), collapse=", "))
dc <- names(H)[which(tolower(names(H)) %in% c("date","period"))[1]]
tc <- names(H)[which(tolower(names(H)) %in% c("ticker","code","symbol"))[1]]
wc <- names(H)[which(tolower(names(H)) %in% c("weight","w","target_weight"))[1]]
H <- H[, .(date = as.Date(get(dc)), Ticker = as.character(get(tc)),
           w = if (!is.na(wc)) as.numeric(get(wc)) else NA_real_)]
H <- H[!is.na(Ticker) & Ticker != ""]
say("  %d행 · %d개월 · %d고유종목 · 월평균 %.1f종목",
    nrow(H), uniqueN(H$date), uniqueN(H$Ticker), nrow(H)/uniqueN(H$date))
say("  최다 보유 종목 상위 10 (보유 개월수):")
top <- H[, .(months = .N, avg_w = mean(w, na.rm=TRUE)), by = Ticker][order(-months)][1:10]
for (i in 1:nrow(top)) say("    %-10s %3d개월 (%.1f%%) · 평균비중 %.3f",
   top$Ticker[i], top$months[i], 100*top$months[i]/uniqueN(H$date), top$avg_w[i])
say("  ★보유 집중도: 상위 10종목이 전체 보유-월의 %.1f%%", 100*sum(top$months)/nrow(H))
H[, m := mi(date)]

say("=== 2. 후보 슬리브들의 보유 겹침률 + ΔIR 동시 측정 (대리 지표 검정) ===")
A <- readRDS(file.path(OUT, "factor_long.rds"))
M <- readRDS(file.path(OUT, "mkt.rds"))
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
inc <- bm_load_incumbent()
FN <- sort(unique(A$Factor_Name))
## 계열이 골고루 섞이도록 등간격 24개 표본 (샤드와 무관 — 워크플로와 중복돼도 교차확인 가치)
sel <- FN[round(seq(1, length(FN), length.out = 24))]
say("  표본 %d재료 (전체 %d 중 등간격)", length(sel), length(FN))
say("  %-28s %7s %8s %8s %9s", "factor", "겹침률", "상관", "슬리브IR", "ΔIR(0.20)")
rows <- list()
for (f in sel) {
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id=f, strategy_id=f,
        diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt))), error = function(e) NULL)
  if (is.null(r)) { say("  %-28s ERROR", f); next }
  HD <- as.data.table(r$holdings)
  hdc <- names(HD)[which(tolower(names(HD)) %in% c("date","period"))[1]]
  htc <- names(HD)[which(tolower(names(HD)) %in% c("ticker","code"))[1]]
  ovl <- NA_real_
  if (!is.na(hdc) && !is.na(htc)) {
    HD <- HD[, .(m = mi(as.Date(get(hdc))) + 2L, Ticker = as.character(get(htc)))]
    J <- merge(HD, H[, .(m, Ticker, inc = TRUE)], by = c("m","Ticker"), all.x = TRUE)
    ovl <- mean(!is.na(J$inc))
  }
  o <- bm_delta_ir(as.data.table(r$period_returns)[, .(date, ret_net)], weight = 0.20, incumbent = inc)
  if (is.null(o$delta_ir) || is.na(o$delta_ir)) { say("  %-28s %s", f, o$status); next }
  say("  %-28s %6.1f%% %+8.3f %+8.3f %+9.4f", substr(f,1,28), 100*ovl,
      o$correlation_with_incumbent, o$sleeve_standalone_ir, o$delta_ir)
  rows[[length(rows)+1L]] <- data.table(factor=f, overlap=ovl, cor=o$correlation_with_incumbent,
    sleeve_ir=o$sleeve_standalone_ir, dIR=o$delta_ir, n=o$n_overlap)
}
D <- rbindlist(rows)
say("=== 3. ★대리 지표가 쓸 만한가 (양방향 검정) ===")
say("  n=%d 측정", nrow(D))
say("  겹침률 범위 %.1f%% ~ %.1f%% (중앙 %.1f%%)", 100*min(D$overlap,na.rm=TRUE),
    100*max(D$overlap,na.rm=TRUE), 100*median(D$overlap,na.rm=TRUE))
say("  cor(겹침률, ΔIR)     = %+.3f  ← 음수여야 대리 지표로 유효",
    cor(D$overlap, D$dIR, use="complete.obs"))
say("  cor(상관, ΔIR)       = %+.3f  ← 강한 음수여야 기전 정합",
    cor(D$cor, D$dIR, use="complete.obs"))
say("  cor(슬리브IR, ΔIR)   = %+.3f", cor(D$sleeve_ir, D$dIR, use="complete.obs"))
say("  cor(겹침률, 상관)     = %+.3f  ← 겹침률이 상관의 대리인가",
    cor(D$overlap, D$cor, use="complete.obs"))
say("=== 4. 이 표본의 ΔIR 분포 (전수 사냥 결과의 사전 추정) ===")
say("  중앙 %+.4f · 1사분위 %+.4f · 3사분위 %+.4f · 최대 %+.4f",
    median(D$dIR), quantile(D$dIR,.25), quantile(D$dIR,.75), max(D$dIR))
say("  ★양수 %d/%d (%.1f%%) · **>=0.05 통과 %d/%d (%.1f%%)**",
    sum(D$dIR>0), nrow(D), 100*mean(D$dIR>0), sum(D$dIR>=0.05), nrow(D), 100*mean(D$dIR>=0.05))
if (any(D$dIR >= 0.05)) {
  say("  통과분:")
  for (i in which(D$dIR >= 0.05)) say("    %-28s ΔIR %+.4f · 상관 %+.3f · 슬리브IR %+.3f",
    substr(D$factor[i],1,28), D$dIR[i], D$cor[i], D$sleeve_ir[i])
}
fwrite(D, file.path(OUT, "p7_overlap.csv")); saveRDS(list(H=H, D=D), file.path(OUT,"p7.rds"))
say("=== p7 완료 ===")
