#==============================================================================
# b5_fy1_rollover_and_lag1.R
#
# ★창 길이를 고르기 전에 반드시 확인할 구성 위험:
#   eps_1y = FY1 컨센서스 EPS. 한국 FY = 역년이므로 어느 시점에 FY1 이
#   "올해 → 내년" 으로 **롤오버**한다. 롤오버를 가로지르는 창의 차분은
#   개정(revision)이 아니라 **대상 회계연도가 바뀐 레벨 점프**다.
#   창이 길수록 롤오버를 품을 확률이 커지므로, 이 검사는 lag 선택에
#   직접 개입한다. P1 에서 4월이 전체 변경의 14.5% 로 최대였던 것이
#   개정 급증인지 롤오버인지 여기서 가른다.
#
#   판별: 롤오버면 (a) 특정 시기에 (b) 다수 종목이 동시에 (c) 같은 방향으로
#         (d) 큰 폭으로 움직인다. 개정이면 방향이 섞이고 폭이 작다.
#
# + b4 에서 실패한 lag1 스트레스 재실행 (sig 컬럼 누락 수정)
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/se02_window_bakeoff_20260810")
CD   <- file.path(ROOT, ".cache/consensus"); FDB <- file.path(ROOT, ".cache/factor_db")
TOL  <- 1e-12

rd <- function(m){ h <- as.data.table(read_parquet(file.path(CD, paste0(m,".parquet"))))
  h[, Date := as.Date(Date)]; h <- h[!is.na(get(m)), .(Ticker, Date, value = get(m))]
  setorderv(h, c("Ticker","Date")); h[] }
E <- rd("eps_1y")
E[, prev_v := shift(value), by = Ticker]
E[, chg := !is.na(prev_v) & abs(value - prev_v) > TOL]

#==============================================================================
# R1 — 변경 이벤트의 월별 성격 (개정인가 롤오버인가)
#==============================================================================
CH <- E[chg == TRUE & abs(prev_v) > 1e-8]
CH[, rel := (value - prev_v)/abs(prev_v)]
CH[, mon := substr(format(Date, "%m"), 1, 2)]
R1 <- CH[, .(n = .N,
             frac_pos   = mean(rel > 0),
             rel_med    = median(rel),
             absrel_med = median(abs(rel)),
             absrel_p90 = as.numeric(quantile(abs(rel), .90))), by = mon][order(mon)]
cat("== R1 월별 변경 이벤트 성격 (롤오버면 frac_pos 와 absrel 이 동시에 튄다) ==\n")
print(R1)
fwrite(R1, file.path(OUT, "b5_r1_change_by_month.csv"))

#==============================================================================
# R2 — 동시성: 하루에 몇 %의 (그 시점 live) 종목이 함께 바뀌는가
#      배치 롤오버면 특정 일자에 동시 변경률이 폭증한다.
#==============================================================================
live_by_date <- E[, .(n_live = .N), by = Date]
chg_by_date  <- E[chg == TRUE, .(n_chg = .N), by = Date]
BD <- merge(live_by_date, chg_by_date, by = "Date", all.x = TRUE)
BD[is.na(n_chg), n_chg := 0L]
BD[, frac := n_chg / n_live]
BD[, `:=`(mon = substr(format(Date, "%m"), 1, 2), yr = format(Date, "%Y"))]
R2 <- BD[, .(days = .N, frac_med = median(frac), frac_p95 = as.numeric(quantile(frac,.95)),
             frac_max = max(frac), n_days_gt30pct = sum(frac > 0.30)), by = mon][order(mon)]
cat("\n== R2 일별 동시 변경률의 월별 분포 ==\n"); print(R2)
fwrite(R2, file.path(OUT, "b5_r2_synchrony_by_month.csv"))
top <- BD[order(-frac)][1:15, .(Date, mon, n_live, n_chg, frac)]
cat("\n-- 동시 변경률 상위 15일 --\n"); print(top)
fwrite(BD[order(-frac)][1:200], file.path(OUT, "b5_r2_top_days.csv"))

#==============================================================================
# R3 — 큰 점프의 방향/시기: |rel| > 0.20 인 변경만 추려 월별 방향 편향
#      롤오버(성장 기대 반영)면 특정 월에 양(+) 편향이 강하게 나온다.
#==============================================================================
BIG <- CH[abs(rel) > 0.20]
R3 <- BIG[, .(n = .N, frac_pos = mean(rel > 0), rel_med = median(rel)), by = mon][order(mon)]
cat("\n== R3 큰 점프(|rel|>0.20) 의 월별 방향 ==\n"); print(R3)
fwrite(R3, file.path(OUT, "b5_r3_big_jumps.csv"))

#==============================================================================
# R4 — 직접 검사: 종목별로 '연 1회 대형 상향' 패턴이 있는가
#      FY1 롤오버면 종목당 매년 정확히 1회, 비슷한 시기에 큰 상향이 나온다.
#==============================================================================
BIG[, yr := format(Date, "%Y")]
per_ty <- BIG[rel > 0.20, .(n_big_up = .N, mons = paste(sort(unique(mon)), collapse="")),
              by = .(Ticker, yr)]
R4 <- data.table(
  n_ticker_years          = nrow(per_ty),
  frac_exactly_one_big_up = mean(per_ty$n_big_up == 1L),
  median_big_ups_per_yr   = median(per_ty$n_big_up))
cat("\n== R4 종목-연도당 대형 상향 횟수 (롤오버면 '정확히 1회' 비율이 높다) ==\n")
print(R4)
fwrite(R4, file.path(OUT, "b5_r4_annual_pattern.csv"))

#==============================================================================
# R5 — lag1 스트레스 재실행 (b4 실패분 수정) · guard 모집단
#==============================================================================
E[, ccum := cumsum(as.integer(chg)), by = Ticker]
E[, obs_date := Date]; setkeyv(E, c("Ticker","Date"))
led <- fread(file.path(FDB, "emission_ledger.csv"))
yms <- sort(unique(led[Factor_Name == "SE02_Consensus_Revision", ym]))
me <- function(ym){ y<-as.integer(substr(ym,1,4)); m<-as.integer(substr(ym,5,6))
  (if(m==12L) as.Date(sprintf("%d-01-01",y+1L)) else as.Date(sprintf("%d-%02d-01",y,m+1L)))-1L }
sigs <- as.Date(vapply(as.character(yms), function(z) as.numeric(me(z)), 0), origin="1970-01-01")
TK <- unique(E$Ticker)
mkQ <- function(anchor_vec, off){
  q <- CJ(Ticker = TK, i = seq_along(anchor_vec))
  q[, sig := anchor_vec[i]][, ym := yms[i]][, Date := sig - off][, i := NULL]
  setkeyv(q, c("Ticker","Date")); q[] }

pick <- function(anchor_vec, off) E[mkQ(anchor_vec, off), roll=TRUE][!is.na(obs_date)]
res <- list()
for (L in c(21L, 63L, 126L, 252L)) {
  mk <- function(av) {
    cu <- pick(av, 0L)[, .(Ticker, ym, sig, v_now=value, d_now=obs_date)]
    cu <- cu[as.integer(sig - d_now) <= 31L]
    lg <- pick(av, L)[, .(Ticker, ym, v_lag=value)]
    j  <- merge(cu, lg, by=c("Ticker","ym"))[!is.na(v_lag) & abs(v_lag) > 1e-6]
    j[, se := (v_now - v_lag)/abs(v_lag)][is.finite(se)]
  }
  A <- mk(sigs); B <- mk(sigs - 1L)
  J <- merge(A[, .(Ticker, ym, se0=se, d_now, sig)], B[, .(Ticker, ym, se1=se)], by=c("Ticker","ym"))
  pm <- J[, .(n=.N,
              rho = if (.N>30L && sd(se0)>TOL && sd(se1)>TOL)
                      suppressWarnings(cor(se0, se1, method="spearman")) else NA_real_,
              frac_ident = mean(abs(se0-se1) < TOL),
              sameday_anchor = mean(d_now == sig)), by=ym]
  res[[length(res)+1L]] <- data.table(arm=sprintf("L%d",L),
    rho_p50=median(pm$rho, na.rm=TRUE), rho_p05=as.numeric(quantile(pm$rho,.05,na.rm=TRUE)),
    rho_min=min(pm$rho, na.rm=TRUE),
    frac_ident_p50=median(pm$frac_ident), sameday_anchor_p50=median(pm$sameday_anchor))
}
R5 <- rbindlist(res)
cat("\n== R5 PIT lag1 스트레스 (sig_d vs sig_d-1, live<=31d) ==\n"); print(R5)
fwrite(R5, file.path(OUT, "b5_r5_lag1_stress.csv"))

cat("\n[b5 완료]\n")
