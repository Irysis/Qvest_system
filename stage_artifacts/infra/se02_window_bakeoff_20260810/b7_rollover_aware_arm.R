#==============================================================================
# b7_rollover_aware_arm.R — 롤오버-인지 창의 실측 (합성안 검증)
#
# b5/b6 확정: FY1 레벨 계열은 매년 4월 초 롤오버(동시변경 lift 10~19x,
#   상향 편향, 중앙 +28~44%). 창이 롤오버를 가로지르면 차분은 개정이 아니라
#   기준연도 교체다. 단순 달력 lag 은 L 이 길수록 오염 월수가 늘어난다
#   (L21:0 · L35:1 · L63:2 · L91:3 · L126:4 · L252:8).
#   반대로 L 이 짧을수록 영값 팽창이 심하다. ⇒ 순수 lag 로는 양립 불가.
#
# 합성안: **롤오버-인지 창**
#   basis_start = sig 이하에서 가장 최근의 "동시 변경일"(live 종목의 >=50% 가
#                 같은 날 변경) = 현재 FY1 기준이 시작된 날. sig 이하만 보므로 PIT 안전.
#   anchor = max(sig - L, basis_start) 위치의 관측.
#            (sig - L 이 basis_start 보다 이르면 basis_start 이후 **첫** 관측)
#   ⇒ 두 끝점이 항상 같은 회계연도 기준 위에 있다.
#
# 검증 지표에 **월별 중앙값**을 추가한다 — 오염 arm 은 4/5월 중앙값이 크게
#   양(+)으로 튀어야 하고, 수리 arm 은 평월과 비슷해야 한다(위반 주입의 역방향).
#
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/se02_window_bakeoff_20260810")
CD   <- file.path(ROOT, ".cache/consensus"); FDB <- file.path(ROOT, ".cache/factor_db")
TOL  <- 1e-12; GUARD <- 31L; MIN_XSEC <- 20L
LAGS <- c(21L, 63L, 126L)

rd <- function(m){ h <- as.data.table(read_parquet(file.path(CD, paste0(m,".parquet"))))
  h[, Date := as.Date(Date)]; h <- h[!is.na(get(m)), .(Ticker, Date, value = get(m))]
  setorderv(h, c("Ticker","Date")); h[] }
E <- rd("eps_1y")
E[, prev_v := shift(value), by = Ticker]
E[, chg := !is.na(prev_v) & abs(value - prev_v) > TOL]
E[, ccum := cumsum(as.integer(chg)), by = Ticker]
E[, obs_date := Date]

#-- basis_start 후보: live 종목의 >=50% 가 같은 날 변경한 날 -------------------
lv <- E[, .(n_live = .N), by = Date]; cg <- E[chg == TRUE, .(n_chg = .N), by = Date]
bd <- merge(lv, cg, by = "Date", all.x = TRUE); bd[is.na(n_chg), n_chg := 0L]
bd[, frac := n_chg/n_live]
ROLL <- sort(bd[frac >= 0.50 & n_live >= 50L, Date])
cat(sprintf("동시변경일(>=50%%) %d개 감지: %s\n", length(ROLL),
            paste(format(head(ROLL, 30)), collapse = " ")))
if (!length(ROLL)) stop("[STOP] 롤오버일 0건 — 0은 결론이 아니라 정지 신호")
cat(sprintf("  월 분포: %s\n", paste(capture.output(print(table(substr(format(ROLL,"%m"),1,2)))), collapse=" | ")))

setkeyv(E, c("Ticker","Date"))
led <- fread(file.path(FDB, "emission_ledger.csv"))
yms <- sort(unique(led[Factor_Name == "SE02_Consensus_Revision", ym]))
me <- function(ym){ y<-as.integer(substr(ym,1,4)); m<-as.integer(substr(ym,5,6))
  (if(m==12L) as.Date(sprintf("%d-01-01",y+1L)) else as.Date(sprintf("%d-%02d-01",y,m+1L)))-1L }
sigs <- as.Date(vapply(as.character(yms), function(z) as.numeric(me(z)),0), origin="1970-01-01")
basis_start <- as.Date(vapply(sigs, function(s){
  k <- ROLL[ROLL <= s]; if (!length(k)) NA_real_ else as.numeric(max(k)) }, 0), origin="1970-01-01")
SIG <- data.table(ym = yms, sig = sigs, basis = basis_start)
cat(sprintf("basis_start 결측 월 %d개 (초기 구간)\n", sum(is.na(SIG$basis))))

TK <- unique(E$Ticker)
mkQ <- function(dates){ q <- CJ(Ticker = TK, i = seq_len(nrow(SIG)))
  q[, sig := SIG$sig[i]][, ym := SIG$ym[i]][, Date := dates[i]][, i := NULL]
  setkeyv(q, c("Ticker","Date")); q[] }

CUR <- E[mkQ(SIG$sig), roll = TRUE][!is.na(obs_date),
        .(Ticker, ym, sig, v_now = value, d_now = obs_date, cc_now = ccum)]
CUR <- CUR[as.integer(sig - d_now) <= GUARD]          # liveness guard

evaluate <- function(J, lab) {
  d <- J[!is.na(v_now) & !is.na(v_lag) & abs(v_lag) > 1e-6]
  d[, se := (v_now - v_lag)/abs(v_lag)]; d <- d[is.finite(se)]
  if (!nrow(d)) return(NULL)
  pm <- d[, .(n = .N, frac_zero = mean(abs(se) < TOL),
              q01 = as.numeric(quantile(se,.01)), q99 = as.numeric(quantile(se,.99)),
              se_med = median(se),
              rev_med = as.numeric(median(cc_now - cc_lag)),
              frac_rev_ge1 = mean((cc_now - cc_lag) >= 1L),
              span_med = as.numeric(median(as.integer(d_now - d_lag)))), by = .(ym, sig)]
  pm[, mon := substr(as.character(ym), 5, 6)]
  list(pm = pm, agg = pm[, .(arm = lab, n_months = .N, n_med = as.numeric(median(n)),
      fz_p50 = median(frac_zero), fz_p90 = as.numeric(quantile(frac_zero,.90)),
      n_mo_fz_gt20 = sum(frac_zero > 0.20),
      n_dead_usable = sum(abs(q99-q01) < TOL & n >= MIN_XSEC),
      rev_med = median(rev_med), frac_rev_ge1_p50 = median(frac_rev_ge1),
      span_med = median(span_med),
      se_med_apr = median(se_med[mon == "04"]), se_med_may = median(se_med[mon == "05"]),
      se_med_oth = median(se_med[!(mon %in% c("04","05"))]),
      fz_mar = median(frac_zero[mon == "03"]))])
}

out <- list(); pms <- list()
for (L in LAGS) {
  # (a) 순수 달력 lag
  LGa <- E[mkQ(SIG$sig - L), roll = TRUE][!is.na(obs_date),
          .(Ticker, ym, v_lag = value, d_lag = obs_date, cc_lag = ccum)]
  ra <- evaluate(merge(CUR, LGa, by = c("Ticker","ym")), sprintf("L%d_plain", L))
  # (b) 롤오버-인지: target = max(sig-L, basis) · basis 이전이면 basis 이후 첫 관측
  tgt <- pmax(SIG$sig - L, SIG$basis, na.rm = FALSE)
  tgt[is.na(tgt)] <- (SIG$sig - L)[is.na(tgt)]
  back <- E[mkQ(tgt), roll = TRUE][!is.na(obs_date),
          .(Ticker, ym, v_lag = value, d_lag = obs_date, cc_lag = ccum)]
  fwd  <- E[mkQ(tgt), roll = -Inf][!is.na(obs_date),
          .(Ticker, ym, v_f = value, d_f = obs_date, cc_f = ccum)]
  bb <- merge(back, fwd, by = c("Ticker","ym"), all = TRUE)
  bb <- merge(bb, SIG[, .(ym, basis)], by = "ym")
  # 후방 관측이 basis 이전이면(= 구 회계연도 기준) basis 이후 첫 관측으로 교체
  bb[, use_fwd := !is.na(basis) & (is.na(d_lag) | d_lag < basis)]
  bb[use_fwd == TRUE, `:=`(v_lag = v_f, d_lag = d_f, cc_lag = cc_f)]
  bb <- bb[!is.na(v_lag) & !is.na(d_lag)]
  rb <- evaluate(merge(CUR, bb[, .(Ticker, ym, v_lag, d_lag, cc_lag)], by = c("Ticker","ym")),
                 sprintf("L%d_rollaware", L))
  for (r in list(ra, rb)) if (!is.null(r)) { out[[length(out)+1L]] <- r$agg; pms[[length(pms)+1L]] <- r$pm[, arm := r$agg$arm] }
  cat(sprintf("  L%d done\n", L))
}
A <- rbindlist(out)
fwrite(A, file.path(OUT, "b7_rollover_aware_summary.csv"))
fwrite(rbindlist(pms), file.path(OUT, "b7_permonth.csv"))

cat("\n============ 롤오버-인지 vs 순수 lag ============\n")
print(A[, .(arm, n_med, fz_p50, n_mo_fz_gt20, n_dead_usable, rev_med, frac_rev_ge1_p50, span_med)])
cat("\n-- ★롤오버 오염 지표: 월별 SE02 중앙값 (4/5월이 튀면 오염) --\n")
print(A[, .(arm, se_med_apr, se_med_may, se_med_oth,
            apr_lift = se_med_apr - se_med_oth, fz_mar)])

cat("\n[b7 완료]\n")
