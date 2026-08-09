## x3 — ★"계약 공시를 낸 회사" 유니버스가 **일반 필터**인가 (신호 기반 선별에도 적용되는가)
## x1 발견: 무작위 25종목의 IR 이 전체유니버스 -0.289 → 계약유니버스 **+0.062** (유니버스 효과 +0.351).
## 그러나 이는 **무작위 선별**에서만 확인됐다. 신호 기반 선별에도 같은 이득이 붙는가?
## ★필수 대조: 계약 유니버스는 월평균 61종목이라 **집중도 자체**가 다르다.
##   ⇒ 같은 크기(61종목)의 **무작위 유니버스** 대조가 없으면 '희소 유니버스 효과' 와 구분 불가.
## ★PG2 holdings.csv 가 0행이라 북 종목 직접 필터링은 불가(칩 task_be236d0c) — 슬리브 수준에서 잰다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[x3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

inc <- bm_load_incumbent()
A   <- readRDS(file.path(OUT,"factor_long.rds"))
M   <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]

## 계약 유니버스(월별 공시 발생 종목)
B <- "04_Research/method_frontier/fq002_contract_magnitude"
R0 <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R0$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
CU <- unique(merge(me, PA[,.(ym,Ticker)], by="ym", allow.cartesian=TRUE)[, .(Date, Ticker)])
sz <- CU[, .(k = .N), by = Date]
say("=== 입력 실측 ===")
say("  계약 유니버스 %d개월 · 월평균 **%.1f종목** · [%d, %d]",
    uniqueN(CU$Date), mean(sz$k), min(sz$k), max(sz$k))
say("  전체 유니버스 월평균 %.0f종목", nrow(ret[Date %in% CU$Date])/uniqueN(CU$Date))
say("  ★계약 창(%s ~ %s)으로 전 arm 을 맞춘다 — 창 차이를 효과로 오독 방지",
    min(CU$Date), max(CU$Date))

meas <- function(S, parked = TRUE) {
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id="F", strategy_id="F",
        diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt))), error=function(e) NULL)
  if (is.null(r)) return(NULL)
  PR <- as.data.table(r$period_returns)
  if (parked) {
    X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
    if (nrow(X) < 12) return(NULL)
    X[, sw := c(0L, abs(diff(as.integer(regime))))]
    X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
    PR <- X[, .(date, ret_net = r2)]
  } else PR <- PR[, .(date, ret_net)]
  o <- bm_delta_ir(PR, weight = 0.20, incumbent = inc, bootstrap = FALSE)
  if (is.null(o$delta_ir)) return(NULL)
  c(rho = o$correlation_with_incumbent, ir = o$sleeve_standalone_ir, d = o$delta_ir, n = o$n_overlap)
}

## 대상: 근접 상위 + 무작위 — 창을 계약 창으로 제한
TB <- fread(file.path(OUT,"c6_full_table.csv"))
top <- TB[is.finite(short_best)][order(short_best)][1:6, factor]
set.seed(7); rnd <- sample(setdiff(unique(A$Factor_Name), top), 6)
FS <- c(top, rnd)
say("=== 대상 %d재료 (근접 6 + 무작위 6) ===", length(FS))

say("=== ★3-arm 비교 (전부 계약 창 %d개월 · parked) ===", uniqueN(CU$Date))
say("  A=전체유니버스 · B=계약유니버스 필터 · C=같은크기 무작위유니버스(대조)")
say("  %-26s %-7s %7s %7s %8s | %-7s %7s %7s %8s | %-7s %7s",
    "factor","A rho","A IR","A ΔIR","", "B rho","B IR","B ΔIR","", "C rho","C IR")
rows <- list()
for (f in FS) {
  S0 <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  S0 <- S0[Date %in% CU$Date]                                  # 창 정합
  a <- meas(S0)
  b <- meas(merge(S0, CU, by = c("Date","Ticker")))             # 계약 유니버스로 제한
  ## C: 같은 월별 크기의 무작위 유니버스
  RU <- merge(unique(S0[, .(Date, Ticker)]), sz, by="Date")
  RU <- RU[, .SD[sample(.N, min(k[1], .N))], by = Date][, .(Date, Ticker)]
  cc <- meas(merge(S0, RU, by = c("Date","Ticker")))
  if (is.null(a) || is.null(b)) next
  say("  %-26s %+7.3f %+7.3f %+8.4f | %+7.3f %+7.3f %+8.4f | %s",
      substr(f,1,26), a["rho"], a["ir"], a["d"], b["rho"], b["ir"], b["d"],
      if (is.null(cc)) "   (실패)" else sprintf("%+7.3f %+7.3f", cc["rho"], cc["ir"]))
  rows[[length(rows)+1L]] <- data.table(factor=f, grp=if (f %in% top) "근접" else "무작위",
    a_rho=a["rho"], a_ir=a["ir"], a_d=a["d"], b_rho=b["rho"], b_ir=b["ir"], b_d=b["d"],
    c_rho=if (is.null(cc)) NA_real_ else cc["rho"], c_ir=if (is.null(cc)) NA_real_ else cc["ir"],
    c_d=if (is.null(cc)) NA_real_ else cc["d"])
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★판정 ===")
say("  1) 계약 필터(B) vs 전체(A): IR 변화 중앙 **%+.3f** · 개선 %d/%d · ΔIR 변화 중앙 %+.4f",
    median(R$b_ir - R$a_ir), sum(R$b_ir > R$a_ir), nrow(R), median(R$b_d - R$a_d))
tt <- tryCatch(t.test(R$b_ir, R$a_ir, paired=TRUE), error=function(e) NULL)
if (!is.null(tt)) say("     paired t %+.3f · p %.4f", tt$statistic, tt$p.value)
say("  2) ★같은크기 무작위(C) vs 전체(A): IR 변화 중앙 %+.3f · 개선 %d/%d",
    median(R$c_ir - R$a_ir, na.rm=TRUE), sum(R$c_ir > R$a_ir, na.rm=TRUE), sum(is.finite(R$c_ir)))
say("     ⇒ C 가 B 와 비슷하면 이득은 **희소 유니버스 효과**이지 '계약 공시' 정보가 아니다")
say("  3) ★계약 고유분 (B − C): IR 중앙 **%+.3f** · B>C 인 재료 %d/%d",
    median(R$b_ir - R$c_ir, na.rm=TRUE), sum(R$b_ir > R$c_ir, na.rm=TRUE), sum(is.finite(R$c_ir)))
t2 <- tryCatch(t.test(R$b_ir, R$c_ir, paired=TRUE), error=function(e) NULL)
if (!is.null(t2)) say("     paired t %+.3f · p %.4f", t2$statistic, t2$p.value)
say("  4) 근접군 vs 무작위군에서 효과가 다른가")
for (g in c("근접","무작위")) {
  s <- R[grp == g]
  say("     [%s] B−A IR %+.3f · B−C IR %+.3f", g, median(s$b_ir - s$a_ir), median(s$b_ir - s$c_ir, na.rm=TRUE))
}
say("  5) B arm 최고 ΔIR %+.4f (%s) — 문턱 0.05 대비 %s",
    max(R$b_d, na.rm=TRUE), R[which.max(b_d), factor],
    if (max(R$b_d, na.rm=TRUE) >= 0.05) "★통과" else "미달")
fwrite(R, file.path(OUT,"x3_filter.csv"))
say("=== x3 완료 ===")
