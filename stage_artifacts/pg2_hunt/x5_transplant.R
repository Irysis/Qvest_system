## x5 — ★★ON월 직교성 기전의 **이식 검정**: 계약+mega_spread 가 특이 쌍인가, 일반 기전인가
## x2 확립: 계약 신호는 국면 ON 월에서만 북과 직교(ON rho 0.186 vs 무작위 0.399, 백분위 0%),
##   전체로는 무작위와 구분 안 됨(0.369 vs 0.378). ⇒ 라벨이 **직교 구간을 고르는 선택기**.
## 질문: 다른 (라벨, 재료) 쌍도 같은 일을 하는가?
##
## ★사전등록 (측정 전 고정):
##  - 라벨 후보 3종 **사전 고정**: mega_spread(FQ-191) · unified Category · regime_jump JM_State
##    + 무작위 라벨(같은 발화율) 대조. **재료별로 라벨을 고르지 않는다**(사후선택 순환 회피).
##  - 1급 = **ON월 rho 가 같은 라벨의 무작위-신호 분포 5% 아래인가** (x2 와 동일 기준)
##  - argmax 금지 · 전 셀 보고 · PIT: 라벨은 **월말 값 → 익월 적용**(홀딩월 시작 전 정보만)
##  - 검정력: 라벨별 ON 월수가 다르므로 셀마다 병기. ON<12 면 판정 불가로 표기
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[x5] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
A   <- readRDS(file.path(OUT,"factor_long.rds"))
M   <- readRDS(file.path(OUT,"mkt.rds")); ret <- as.data.table(M$ret)[!is.na(Ret_1m)]

## ── 라벨 구성 (월말 값 → **익월 적용** = 홀딩월 시작 전 정보) ────────────────
mklab <- function(dt, col) {
  d <- as.data.table(dt)
  dc <- names(d)[which(tolower(names(d)) %in% c("date","ym"))[1]]
  d[, .dd := as.Date(as.character(get(dc)))]
  d <- d[!is.na(.dd)][order(.dd)]
  mo <- d[, .(v = last(get(col))), by = .(m = mi(.dd))]      # 월말 값
  mo[, m_apply := m + 1L]                                    # ★익월 적용 (PIT)
  v <- mo$v
  lv <- if (is.numeric(v)) (v > median(v, na.rm=TRUE)) else (v == names(sort(table(v), decreasing=TRUE))[1])
  data.table(m = mo$m_apply, on = as.logical(lv))[!is.na(on)]
}
LABS <- list()
f1 <- list.files(".", pattern="^unified_regime_signal_daily\\.parquet$", recursive=TRUE, full.names=TRUE)
if (length(f1)) LABS[["unified_Category"]] <- mklab(read_parquet(f1[1]), "Category")
f2 <- list.files(".", pattern="^regime_jump_daily\\.parquet$", recursive=TRUE, full.names=TRUE)
if (length(f2)) LABS[["jump_JM_State"]] <- mklab(read_parquet(f2[1]), "JM_State")
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LABS[["mega_spread"]] <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))

say("=== 라벨 인벤토리 (PG2 창 정렬 후) ===")
for (k in names(LABS)) {
  L <- LABS[[k]][m %in% inc$m]
  rl <- rle(as.integer(L$on[order(L$m)]))
  say("  %-18s %3d개월 · ON %3d (%.1f%%) · 에피소드 %d",
      k, nrow(L), sum(L$on), 100*mean(L$on), sum(rl$values == 1L))
  LABS[[k]] <- L
}

## ── 재료 (x3 와 동일 집합 — 재료 선택도 고정) ────────────────────────────────
TB <- fread(file.path(OUT,"c6_full_table.csv"))
top <- TB[is.finite(short_best)][order(short_best)][1:4, factor]
set.seed(7); rnd <- sample(setdiff(unique(A$Factor_Name), top), 4)
FS <- c(top, rnd)
say("=== 재료 %d종 (근접4 + 무작위4) ===", length(FS))

act_of <- function(f) {
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
        cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id=f, strategy_id=f,
        diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt))), error=function(e) NULL)
  if (is.null(r)) return(NULL)
  PR <- as.data.table(r$period_returns)[, .(date, ret_net)]
  PR[, m := mi(date) + 2L]
  merge(PR, inc[, .(m, inc_act = active, inc_bm = benchmark_ret)], by="m")[, a_s := ret_net - inc_bm][]
}
say("=== ★셀 전수 (ON월 rho · 전체 rho · 무작위라벨 대조) ===")
say("  %-24s %-18s %5s %8s %8s %9s %8s", "factor","label","ON","ON rho","전체 rho","무작위중앙","백분위")
set.seed(20260809)
rows <- list()
for (f in FS) {
  X <- act_of(f); if (is.null(X) || nrow(X) < 24) next
  r_all <- cor(X$a_s, X$inc_act)
  for (k in names(LABS)) {
    Z <- merge(X, LABS[[k]], by = "m")
    on <- Z[on %in% TRUE]
    if (nrow(on) < 12L) { say("  %-24s %-18s %5d (ON<12 판정불가)", substr(f,1,24), k, nrow(on)); next }
    r_on <- cor(on$a_s, on$inc_act)
    ## 무작위 라벨 대조: 같은 발화율·같은 월수
    kk <- nrow(on); nn <- nrow(Z)
    rr <- vapply(seq_len(60L), function(i) {
      idx <- sample.int(nn, kk); cor(Z$a_s[idx], Z$inc_act[idx]) }, numeric(1))
    rr <- rr[is.finite(rr)]
    say("  %-24s %-18s %5d %+8.3f %+8.3f %+9.3f %7.0f%%",
        substr(f,1,24), k, kk, r_on, r_all, median(rr), 100*mean(rr < r_on))
    rows[[length(rows)+1L]] <- data.table(factor=f, grp=if (f %in% top) "근접" else "무작위",
      label=k, n_on=kk, r_on=r_on, r_all=r_all, rnd_med=median(rr),
      pct=100*mean(rr < r_on), beats = mean(rr < r_on) < 0.05)
  }
}
R <- rbindlist(rows, fill=TRUE)
say("=== ★판정 ===")
say("  측정 셀 %d개 (재료 %d x 라벨 %d)", nrow(R), uniqueN(R$factor), uniqueN(R$label))
say("  ★1급 통과(ON rho 가 무작위 5% 아래): **%d/%d (%.1f%%)**",
    sum(R$beats), nrow(R), 100*mean(R$beats))
say("  대조 기준 = 계약+mega_spread: ON rho +0.186 · 백분위 **0%%**")
say("  라벨별 통과율:")
for (k in unique(R$label)) { s <- R[label==k]
  say("    %-18s %d/%d · ON rho 중앙 %+.3f · 백분위 중앙 %.0f%%", k, sum(s$beats), nrow(s),
      median(s$r_on), median(s$pct)) }
say("  재료군별: 근접 %d/%d · 무작위 %d/%d",
    sum(R[grp=="근접", beats]), nrow(R[grp=="근접"]),
    sum(R[grp=="무작위", beats]), nrow(R[grp=="무작위"]))
say("  ⇒ %s", if (sum(R$beats) == 0)
  "★★어떤 (라벨,재료) 쌍도 계약+mega_spread 를 재현하지 못한다 — **특이 쌍**(이식 불가)" else
  sprintf("★%d 셀이 재현 — 기전이 일부 이식된다. 다만 다중검정(%d셀)에서 %.1f%% 는 우연 기대 5%% 대비 확인 필요",
          sum(R$beats), nrow(R), 100*mean(R$beats)))
say("  ⚠다중검정: %d셀 중 우연히 5%% 아래일 기대 = %.1f셀", nrow(R), 0.05*nrow(R))
fwrite(R, file.path(OUT,"x5_transplant.csv"))
say("=== x5 완료 ===")
