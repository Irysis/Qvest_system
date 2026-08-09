## m4 — m3 의 두 결함 수리 후 실측 재판독
##  ①CI 인쇄: delta_ir_ci 는 **리스트**($lo/$hi)인데 [1]/[2] 로 찍어 available=TRUE→1.0, block=12→12.0
##    이 CI 로 인쇄됐다. 계약은 정상. ★리스트를 벡터처럼 색인하면 **그럴듯한 숫자**가 나온다
##    (오류가 아니라 오답 — r-portability 금칙⑥과 같은 계통).
##  ②subsample_null 이 예외 없이 NULL 반환 = 침묵. 반환 구조를 실측해 원인을 본다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[m4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
source("02_Infrastructure/contracts/subsample_null.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
inc <- bm_load_incumbent(); inc[, m := mi(date)]
INV <- readRDS(file.path(OUT,"s1_inventory.rds")); TGT <- "STR_1698_WT008_M08_Swap"; RATE <- 0.3562
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)[1]
U <- as.data.table(read_parquet(f1)); dc <- names(U)[which(tolower(names(U)) %in% c("date","ym"))[1]]
U[, .dd := as.Date(as.character(get(dc)))]
MO <- U[!is.na(.dd)][order(.dd)][, .(rss = last(Regime_Score_smooth)), by=.(m = mi(.dd))]
LB <- data.table(m = MO$m + 1L, on = MO$rss >= quantile(MO$rss, 1-RATE, na.rm=TRUE))[!is.na(on)]
j <- which(INV$names == TGT)[1]
X <- merge(inc[, .(m, date, benchmark_ret)], INV$ser[[j]][, .(m, r)], by="m")[order(m)]
W <- merge(X, LB, by="m")[order(m)]
W[, sw := c(0L, abs(diff(as.integer(on))))]
W[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]

say("=== ① ΔIR CI 정정 판독 (계약 원본 필드) ===")
o <- bm_delta_ir(W[, .(date, ret_net = rp)], weight=0.20, incumbent=inc, bootstrap=TRUE, B_boot=3000)
ci <- o$delta_ir_ci
say("  ΔIR 점추정 **%+.4f** · block %d · n_boot %d", o$delta_ir, ci$block, ci$n_boot)
say("  90%% CI [**%+.4f**, **%+.4f**] · se %.4f", ci$lo, ci$hi, ci$se)
say("  P(ΔIR >= 0.05) = **%.1f%%** · P(ΔIR > 0) = %.1f%%", 100*ci$p_above_threshold, 100*ci$p_above_zero)
say("  ★verdict_ci = **%s**", o$verdict_ci)
say("  ⇒ 점추정은 문턱 위(%+.4f > 0.05)이나 CI 하단 %+.4f 가 0 아래 — **통과 주장 불가**", o$delta_ir, ci$lo)
say("  ★계약 자체 경고문이 정확히 이 경우를 예고: 문턱은 표본 해상도 아래에 있다")

say("=== ② subsample_null 침묵 원인 ===")
nl <- subsample_null(x = W$r, y = W$benchmark_ret, subset = W$on, stat = function(a,b) cor(a,b), n_draw = 1000)
say("  반환 class=%s · NULL여부=%s · 필드=%s", class(nl)[1], is.null(nl), paste(names(nl), collapse=","))
if (!is.null(nl)) {
  say("  observed %+.4f · null_mean %+.4f · 백분위 %.1f%% · inside=%s",
      nl$observed, nl$null_mean, 100*nl$percentile, nl$inside)
  say("  ★m3 이 침묵한 이유 = if(!is.null(nl)) 가 아니라 **say() 인자에서 nl$inside 가 논리형이라**")
  say("     sprintf(\"%%s\", logical) 은 정상이므로 — 실제 원인 재확인 필요")
}
say("=== ③ 서열 재확인 (정정된 자로) ===")
run <- function(on_vec) { V <- copy(W); V[, on := on_vec]
  V[, sw := c(0L, abs(diff(as.integer(on))))]; V[, rp := ifelse(on, r, benchmark_ret) - sw*15/1e4]
  bm_delta_ir(V[, .(date, ret_net=rp)], weight=0.20, incumbent=inc, bootstrap=FALSE)$delta_ir }
say("  ΔIR: high %+.4f · 무처리 %+.4f",
    run(W$on), bm_delta_ir(X[, .(date, ret_net=r)], weight=0.20, incumbent=inc, bootstrap=FALSE)$delta_ir)
say("=== m4 완료 ===")
