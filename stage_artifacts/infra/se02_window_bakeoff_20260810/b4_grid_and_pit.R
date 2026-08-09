#==============================================================================
# b4_grid_and_pit.R — 창 × guard 격자 민감도 + guard 적용 PIT 재확인
#
# b3 이 두 가지를 드러냈다:
#  (1) 결함은 **둘**이다 — ①창이 위치-기반(인접 행) ②stale 종목에 date_rank==1
#      을 그대로 적용(끝점 동일 → 창 무관 구조적 0). 저장 실측: 배출 ~1164행 중
#      live(<=31d) 는 ~608행 ⇒ 절반 가까이가 커버리지 끊긴 종목.
#  (2) 내가 고정한 K2/K3 에 **집계수준이 미지정**이었다:
#      K2 = frac_zero <= 0.20 을 "월별 중앙값"으로 볼지 "전 월"로 볼지,
#      K3 = "죽은 달 0" 에 커버리지 개시기(n<=9종목) 를 포함할지.
#      ⇒ 여기서 두 읽기 모두 산출해 **양쪽 다 보고**한다(사후 재단 금지).
#
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/se02_window_bakeoff_20260810")
CD   <- file.path(ROOT, ".cache/consensus"); FDB <- file.path(ROOT, ".cache/factor_db")
TOL  <- 1e-12
LAGS <- c(21L, 35L, 63L, 91L, 126L, 252L)
MIN_XSEC <- 20L   # factor_db_builder.R:673 .winsorize_raw 의 자체 문턱과 동일

rd <- function(m) { h <- as.data.table(read_parquet(file.path(CD, paste0(m,".parquet"))))
  h[, Date := as.Date(Date)]; h <- h[!is.na(get(m)), .(Ticker, Date, value = get(m))]
  setorderv(h, c("Ticker","Date")); h[] }
E <- rd("eps_1y")
E[, prev_v := shift(value), by = Ticker]
E[, ccum := cumsum(as.integer(!is.na(prev_v) & abs(value - prev_v) > TOL)), by = Ticker]
E[, obs_date := Date]; setkeyv(E, c("Ticker","Date"))

led <- fread(file.path(FDB, "emission_ledger.csv"))
yms <- sort(unique(led[Factor_Name == "SE02_Consensus_Revision", ym]))
me <- function(ym){ y<-as.integer(substr(ym,1,4)); m<-as.integer(substr(ym,5,6))
  (if(m==12L) as.Date(sprintf("%d-01-01",y+1L)) else as.Date(sprintf("%d-%02d-01",y,m+1L)))-1L }
SIG <- data.table(ym=yms, sig=as.Date(vapply(as.character(yms), function(z) as.numeric(me(z)),0), origin="1970-01-01"))
TK <- unique(E$Ticker)
mkQ <- function(off){ q<-CJ(Ticker=TK, i=seq_len(nrow(SIG)))
  q[, sig:=SIG$sig[i]][, ym:=SIG$ym[i]][, Date:=sig-off][, i:=NULL]
  setkeyv(q,c("Ticker","Date")); q[] }

CUR <- E[mkQ(0L), roll=TRUE][!is.na(obs_date),
   .(Ticker, ym, sig, v_now=value, d_now=obs_date, cc_now=ccum)]
LGL <- lapply(LAGS, function(L) E[mkQ(L), roll=TRUE][!is.na(obs_date),
   .(Ticker, ym, v_lag=value, d_lag=obs_date, cc_lag=ccum)])
names(LGL) <- sprintf("L%d", LAGS)

GUARDS <- list(none = NULL, distinct_endpoint = -1L, stale21 = 21L, stale31 = 31L,
               stale63 = 63L, stale92 = 92L)

grid <- list()
for (gn in names(GUARDS)) {
  g <- GUARDS[[gn]]
  for (lab in names(LGL)) {
    J <- merge(CUR, LGL[[lab]], by = c("Ticker","ym"))
    d <- J[!is.na(v_now) & !is.na(v_lag) & abs(v_lag) > 1e-6]
    if (identical(g, -1L))      d <- d[d_lag < d_now]                 # 끝점 상이만 요구
    else if (!is.null(g))       d <- d[as.integer(sig - d_now) <= g]  # liveness
    d[, se := (v_now - v_lag)/abs(v_lag)]; d <- d[is.finite(se)]
    if (!nrow(d)) next
    pm <- d[, .(n = .N, frac_zero = mean(abs(se) < TOL),
                q01 = as.numeric(quantile(se,.01)), q99 = as.numeric(quantile(se,.99)),
                rev_med = as.numeric(median(cc_now - cc_lag)),
                frac_rev_ge1 = mean((cc_now - cc_lag) >= 1L),
                frac_same_end = mean(d_now == d_lag)), by = .(ym, sig)]
    pm[, mon := substr(as.character(ym), 5, 6)]
    grid[[length(grid)+1L]] <- pm[, .(
      guard = gn, arm = lab, n_months = .N, n_med = as.numeric(median(n)),
      fz_p50 = median(frac_zero), fz_p90 = as.numeric(quantile(frac_zero,.90)),
      fz_max = max(frac_zero),
      n_mo_fz_gt20 = sum(frac_zero > 0.20), n_mo_fz_gt50 = sum(frac_zero > 0.50),
      n_dead_all = sum(abs(q99-q01) < TOL),
      n_dead_usable = sum(abs(q99-q01) < TOL & n >= MIN_XSEC),
      n_mo_below_minxsec = sum(n < MIN_XSEC),
      rev_med = median(rev_med), frac_rev_ge1_p50 = median(frac_rev_ge1),
      frac_same_end_p50 = median(frac_same_end),
      fz_mar = median(frac_zero[mon == "03"]), fz_apr = median(frac_zero[mon == "04"]))]
  }
  cat(sprintf("  guard=%s done\n", gn))
}
G <- rbindlist(grid)
fwrite(G, file.path(OUT, "b4_grid.csv"))

cat("\n================= 창 x guard 격자 =================\n")
for (gn in names(GUARDS)) {
  cat(sprintf("\n--- guard = %s ---\n", gn))
  print(G[guard == gn, .(arm, n_med, fz_p50, fz_p90, fz_max, n_mo_fz_gt20,
                          n_dead_all, n_dead_usable, rev_med, frac_same_end_p50,
                          fz_mar, fz_apr)])
}

#==============================================================================
# PIT 재확인 (guard 적용 모집단에서) — b1 P3/P4 는 stale 오염 모집단이었다
#==============================================================================
V1 <- rd("eps_chg_1m"); setnames(V1,"value","vendor_1m"); V1[, obs_date:=Date]; setkeyv(V1,c("Ticker","Date"))
V3 <- rd("eps_chg_3m"); setnames(V3,"value","vendor_3m"); V3[, obs_date:=Date]; setkeyv(V3,c("Ticker","Date"))
VN1 <- V1[mkQ(0L), roll=TRUE][!is.na(obs_date) & as.integer(sig-obs_date) <= 31L, .(Ticker, ym, vendor_1m)]
VN3 <- V3[mkQ(0L), roll=TRUE][!is.na(obs_date) & as.integer(sig-obs_date) <= 31L, .(Ticker, ym, vendor_3m)]
CURG <- CUR[as.integer(sig - d_now) <= 31L]

pit <- list()
for (lab in names(LGL)) {
  J <- merge(CURG, LGL[[lab]], by=c("Ticker","ym"))
  d <- J[!is.na(v_now) & !is.na(v_lag) & abs(v_lag) > 1e-6]
  d[, se := (v_now - v_lag)/abs(v_lag)]; d <- d[is.finite(se)]
  a <- merge(d, VN1, by=c("Ticker","ym")); b <- merge(d, VN3, by=c("Ticker","ym"))
  r1 <- a[, .(rho = if(.N>30L && sd(se)>TOL && sd(vendor_1m,na.rm=TRUE)>TOL)
    suppressWarnings(cor(se,vendor_1m,method="spearman",use="complete.obs")) else NA_real_), by=ym]
  r3 <- b[, .(rho = if(.N>30L && sd(se)>TOL && sd(vendor_3m,na.rm=TRUE)>TOL)
    suppressWarnings(cor(se,vendor_3m,method="spearman",use="complete.obs")) else NA_real_), by=ym]
  pit[[length(pit)+1L]] <- data.table(arm=lab,
    rho_v1m_p50=median(r1$rho,na.rm=TRUE), rho_v1m_p95=as.numeric(quantile(r1$rho,.95,na.rm=TRUE)),
    rho_v1m_max=max(r1$rho,na.rm=TRUE),
    rho_v3m_p50=median(r3$rho,na.rm=TRUE), rho_v3m_p95=as.numeric(quantile(r3$rho,.95,na.rm=TRUE)),
    rho_v3m_max=max(r3$rho,na.rm=TRUE))
}
PIT <- rbindlist(pit)
cat("\n== K5 비중복 (guard 적용) — 벤더 자체 개정률 대비 rank 상관 ==\n"); print(PIT)
fwrite(PIT, file.path(OUT, "b4_k5_nonredundancy.csv"))

# lag1 스트레스 (same-day 노출) — guard 모집단
SIG2 <- copy(SIG); SIG2[, sig := sig - 1L]
mkQ2 <- function(off){ q<-CJ(Ticker=TK, i=seq_len(nrow(SIG2)))
  q[, sig:=SIG2$sig[i]][, ym:=SIG2$ym[i]][, Date:=sig-off][, i:=NULL]
  setkeyv(q,c("Ticker","Date")); q[] }
CUR2 <- E[mkQ2(0L), roll=TRUE][!is.na(obs_date), .(Ticker, ym, sig, v_now=value, d_now=obs_date)]
CUR2 <- CUR2[as.integer(sig-d_now) <= 31L]
ls_ <- list()
for (L in c(21L, 63L, 126L)) {
  lab <- sprintf("L%d", L)
  A <- merge(CURG, LGL[[lab]], by=c("Ticker","ym"))
  A <- A[!is.na(v_lag) & abs(v_lag)>1e-6][, .(Ticker, ym, se0=(v_now-v_lag)/abs(v_lag), d_now)]
  LG2 <- E[mkQ2(L), roll=TRUE][!is.na(obs_date), .(Ticker, ym, v_lag=value)]
  B <- merge(CUR2, LG2, by=c("Ticker","ym"))
  B <- B[!is.na(v_lag) & abs(v_lag)>1e-6][, .(Ticker, ym, se1=(v_now-v_lag)/abs(v_lag))]
  J <- merge(A, B, by=c("Ticker","ym"))
  J <- J[is.finite(se0) & is.finite(se1)]
  pmn <- J[, .(n=.N, rho = if(.N>30L && sd(se0)>TOL && sd(se1)>TOL)
    suppressWarnings(cor(se0,se1,method="spearman")) else NA_real_,
    frac_ident = mean(abs(se0-se1) < TOL),
    frac_sameday_anchor = mean(d_now == sig)), by=ym]
  ls_[[length(ls_)+1L]] <- data.table(arm=lab, rho_p50=median(pmn$rho,na.rm=TRUE),
    rho_p05=as.numeric(quantile(pmn$rho,.05,na.rm=TRUE)),
    frac_ident_p50=median(pmn$frac_ident), sameday_p50=median(pmn$frac_sameday_anchor))
}
LS <- rbindlist(ls_)
cat("\n== PIT lag1 스트레스 (sig_d vs sig_d-1, guard 모집단) ==\n"); print(LS)
fwrite(LS, file.path(OUT, "b4_pit_lag1.csv"))

cat("\n[b4 완료]\n")
