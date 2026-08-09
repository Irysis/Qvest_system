## =============================================================================
## FQ-223 (B) v2 — 방법 B 정정판: **외과적** 롤오버-인지 재구성
##
## b1 v1 실패 원인 (자기정정): anchor = max(sig-63, basis) + "d_lag < basis 면 전방대체"
##   규칙이 **커버리지 중단(stale) 종목**까지 건드려 04/05 아닌 달의 계수도 전부 바꿨다
##   (설계확인 동일비율 0/235 · 관측 514k→285k). 그 arm 의 Δt 는 롤오버 효과가 아니라
##   **표본 재구성 효과**였다 → 폐기.
##
## 정정 규칙 (오염의 정의를 그대로 옮김):
##   basis(sig) = sig 이하 최근 동시변경일 (= 현재 FY 기준이 시작된 날)
##   ★오염 관측 ⟺ d_now >= basis  AND  d_lag < basis
##     (분자 끝점은 새 FY, 분모 끝점은 옛 FY ⇒ 차분이 개정이 아니라 기준연도 교체)
##   수리: 오염 관측만 v_lag 을 **basis 이후 첫 관측**으로 교체. 나머지는 plain 그대로.
##   d_now < basis 인 관측은 두 끝점이 같은 옛 FY 위에 있으므로 오염 아님 — 손대지 않는다.
##
## ⇒ 04/05 외 달은 설계상 계수가 **완전 동일**해야 한다(사후 확인 항목).
## metric_type: canonical_screen_diag. 자본 주장 없음. factor_db 재빌드 없음.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/fq223_rollover_downstream_20260810")
SRC  <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
CD   <- file.path(ROOT, ".cache/consensus")
say <- function(fmt, ...) { cat(sprintf(paste0("[b2] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260810L)
TOL <- 1e-12; LAG <- 63L; T_DB <- 2.5552525842524

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  m/sqrt(s/n)
}
fmb_coefs <- function(dat, xs, ycol = "Ret_1m") {
  f <- as.formula(paste(ycol, "~", paste(xs, collapse = " + ")))
  dat[, {
    fit <- tryCatch(lm(f, data = .SD), error = function(e) NULL)
    if (is.null(fit)) .(term = character(0), est = numeric(0))
    else { cf <- coef(fit); .(term = names(cf), est = as.numeric(cf)) }
  }, by = signal_ym, .SDcols = c(ycol, xs)]
}
z_fdb <- function(x) {                       # factor_db_builder.R z 규약 복제
  ok <- is.finite(x); if (sum(ok) < 20L) return(rep(NA_real_, length(x)))
  q <- quantile(x[ok], c(0.01, 0.99), na.rm = TRUE, names = FALSE)
  w <- pmin(pmax(x, q[1]), q[2])
  mu <- mean(w, na.rm = TRUE); s <- sd(w, na.rm = TRUE)
  if (!is.finite(s) || s < 1e-12) return(rep(NA_real_, length(x)))
  z <- pmin(pmax((w - mu)/s, -3), 3)
  s2 <- sd(z, na.rm = TRUE); if (is.finite(s2) && s2 > 1e-12) z/s2 else z
}

## =============================================================================
## [0] 입력
## =============================================================================
say("================ [0] 입력 실측 ================")
D4 <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet"))); D4[, Date := as.Date(Date)]
sigs <- sort(unique(D4$Date)); K <- length(sigs)
say("판정 패널 %d행 · %d개월 · %s ~ %s", nrow(D4), K, min(sigs), max(sigs))

E <- as.data.table(read_parquet(file.path(CD, "revenue_fy1.parquet")))
E[, Date := as.Date(Date)]; E <- E[!is.na(revenue_fy1), .(Ticker, Date, value = revenue_fy1)]
setorderv(E, c("Ticker","Date"))
say("revenue_fy1: %d행 · 일간 · %s ~ %s · Ticker %d", nrow(E), min(E$Date), max(E$Date), uniqueN(E$Ticker))

## 동시변경일
E[, prev_v := shift(value), by = Ticker]
E[, chg := !is.na(prev_v) & abs(value - prev_v) > TOL]
lv <- E[, .(n_live = .N), by = Date]; cg <- E[chg == TRUE, .(n_chg = .N), by = Date]
bd <- merge(lv, cg, by = "Date", all.x = TRUE)[is.na(n_chg), n_chg := 0L][, frac := n_chg/n_live]
ROLL_raw <- sort(bd[frac >= 0.50 & n_live >= 50L, Date])
ROLL_apr <- ROLL_raw[format(ROLL_raw, "%m") == "04"]
if (!length(ROLL_apr)) stop("[b2] 4월 동시변경일 0건 — 0은 결론이 아니라 정지 신호")
say("동시변경일 %d일 (4월 %d · 4월 외 %d)", length(ROLL_raw), length(ROLL_apr), length(ROLL_raw)-length(ROLL_apr))

E[, obs_date := Date]; setkeyv(E, c("Ticker","Date"))
TK <- unique(E$Ticker)
mkQ <- function(dates) { q <- CJ(Ticker = TK, k = seq_len(K), sorted = FALSE)
  q[, Date := dates[k]]; setkeyv(q, c("Ticker","Date")); q[] }
pull_back <- function(dates) { r <- E[mkQ(dates), roll = TRUE,  on = .(Ticker, Date)]
  r[!is.na(value), .(Ticker, k, v = value, d = obs_date)] }
pull_fwd  <- function(dates) { r <- E[mkQ(dates), roll = -Inf, on = .(Ticker, Date)]
  r[!is.na(value), .(Ticker, k, v = value, d = obs_date)] }

NOW <- pull_back(sigs); setnames(NOW, c("v","d"), c("v_now","d_now"))
LAGP <- pull_back(sigs - LAG); setnames(LAGP, c("v","d"), c("v_lag","d_lag"))
J <- merge(NOW, LAGP, by = c("Ticker","k"))
say("plain 결합 %d 관측", nrow(J))

## =============================================================================
## [1] 판정 패널로 즉시 축소 — (C) 오염 규모는 "실제 쓰인 관측" 위에서만 의미 있다
## =============================================================================
say("================ [1] 판정 패널 축소 ================")
KMAP <- data.table(k = seq_len(K), Date = sigs)
J <- merge(KMAP, J, by = "k")
JP <- merge(D4[, .(Date, Ticker, signal_ym)], J, by = c("Date","Ticker"))
say("판정 패널 교집합 %d / %d (매칭률 %.4f)", nrow(JP), nrow(D4), nrow(JP)/nrow(D4))
if (nrow(JP) < 0.95*nrow(D4)) stop("[b2] 판정 패널 재구성 매칭률 미달 — 중단")

## =============================================================================
## [2] 오염 관측 식별 + 외과적 수리
## =============================================================================
say("================ [2] 오염 식별 + 외과적 수리 ================")
mark_and_fix <- function(ROLL, lab) {
  basis <- as.Date(vapply(sigs, function(s) { kk <- ROLL[ROLL <= s]
    if (!length(kk)) NA_real_ else as.numeric(max(kk)) }, 0), origin = "1970-01-01")
  X <- copy(JP); X[, bas := basis[k]]
  X[, contaminated := !is.na(bas) & d_now >= bas & d_lag < bas]
  ## 수리 앵커: basis 이후 첫 관측 (오염 관측에만 필요)
  FW <- pull_fwd(basis); setnames(FW, c("v","d"), c("v_fix","d_fix"))
  X <- merge(X, FW, by = c("Ticker","k"), all.x = TRUE)
  X[, fixable := contaminated & !is.na(v_fix) & abs(v_fix) > 1e-6]
  X[, v_use := v_lag][fixable == TRUE, v_use := v_fix]
  X[, d_use := d_lag][fixable == TRUE, d_use := d_fix]
  X[, raw_plain := fifelse(abs(v_lag) > 1e-6, (v_now - v_lag)/abs(v_lag), NA_real_)]
  X[, raw_fix   := fifelse(abs(v_use) > 1e-6, (v_now - v_use)/abs(v_use), NA_real_)]
  X[, mon := format(Date, "%m")]
  X[, lab := lab]
  X[]
}
X1 <- mark_and_fix(ROLL_raw, "rawdet")
X2 <- mark_and_fix(ROLL_apr, "aprdet")

cens <- rbindlist(lapply(list(X1, X2), function(X)
  X[, .(lab = lab[1], n = .N, n_contam = sum(contaminated), frac_contam = mean(contaminated),
        n_fixable = sum(fixable), frac_unfixable = sum(contaminated & !fixable)/max(1L, sum(contaminated)),
        span_plain_med = as.numeric(median(as.integer(Date - d_lag))),
        span_fix_med = as.numeric(median(as.integer(Date - d_use)))), by = mon]))
setorder(cens, lab, mon)
say("--- 오염 관측 비율 (판정 패널 기준) ---")
for (i in seq_len(nrow(cens))) with(cens[i], say(
  "  %-7s %s월 n=%6d · 오염 %6d (%.4f) · 수리가능 %6d · 수리불가 %.3f · 창길이 중앙 %.0f→%.0f일",
  lab, mon, n, n_contam, frac_contam, n_fixable, frac_unfixable, span_plain_med, span_fix_med))
tot <- rbindlist(lapply(list(X1,X2), function(X) X[, .(lab=lab[1], n=.N, n_contam=sum(contaminated),
       frac=mean(contaminated), n_fix=sum(fixable))]))
say("★전체 오염 비중: %s", paste(sprintf("%s %.4f (%d/%d)", tot$lab, tot$frac, tot$n_contam, tot$n), collapse=" | "))
fwrite(cens, file.path(OUT, "b2_contamination_census.csv"))

## =============================================================================
## [3] G1/G2 parity (plain 재구성 ↔ DB 배출값)
## =============================================================================
say("================ [3] parity gate ================")
G1 <- merge(D4[, .(Date, Ticker, signal_ym, zdb = M26_Revenue_Mom)],
            X2[, .(Date, Ticker, raw_plain)], by = c("Date","Ticker"))
g1 <- G1[is.finite(raw_plain), .(n = .N, rho = suppressWarnings(cor(raw_plain, zdb, method="spearman", use="complete.obs"))),
         by = .(Date, signal_ym)][is.finite(rho)]
say("G1 월별 Spearman: 중앙 %+.4f · 5%% %+.4f · 최소 %+.4f · |rho|>=0.95 %d/%d",
    median(g1$rho), quantile(g1$rho,.05), min(g1$rho), sum(abs(g1$rho)>=0.95), nrow(g1))
G1_PASS <- median(abs(g1$rho)) >= 0.95
if (!G1_PASS) stop("[b2] G1 FAIL — 재구성이 배출값을 대표 못함. 중단")
SGN <- g1[, .(Date, sgn = sign(rho))]
say("★G1 = PASS (부호: 양 %d달 / 음 %d달)", sum(g1$rho>0), sum(g1$rho<0))

base_cols <- D4[, .(Date, Ticker, signal_ym, C01_SUE, C02_EPS_Chg_1m, C04_ESBR, Ret_1m)]
fit_arm <- function(X, rawcol, lab) {
  A <- X[is.finite(get(rawcol)), .(Date, Ticker, raw = get(rawcol))]
  A <- merge(A, SGN, by = "Date")
  A[, zm := z_fdb(raw)*sgn[1], by = Date]
  DD <- merge(base_cols, A[, .(Date, Ticker, zm)], by = c("Date","Ticker"))
  DD <- DD[complete.cases(DD[, .(C01_SUE, C02_EPS_Chg_1m, C04_ESBR, zm, Ret_1m)])]
  mm <- DD[, .N, by = signal_ym]; DD <- DD[signal_ym %in% mm[N >= 30L, signal_ym]]
  CFx <- fmb_coefs(DD, c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","zm"))
  s <- CFx[term == "zm"][order(signal_ym)]; s[, mon := substr(signal_ym,6,7)]
  list(arm = lab, n_months = nrow(s), n_obs = nrow(DD), t_nw3 = nw_t(s$est),
       mean = mean(s$est), sd = sd(s$est),
       apr = mean(s[mon=="04", est]), may = mean(s[mon=="05", est]),
       oth = mean(s[!(mon %in% c("04","05")), est]), series = s)
}
R_plain <- fit_arm(X2, "raw_plain", "plain(재구성)")
say("★G2 parity: plain 재구성 t %+.4f vs DB t %+.4f ⇒ |Δ| %.4f (문턱 0.15)",
    R_plain$t_nw3, T_DB, abs(R_plain$t_nw3 - T_DB))
G2_PASS <- abs(R_plain$t_nw3 - T_DB) <= 0.15
if (!G2_PASS) stop("[b2] G2 FAIL — 재구성 arm 이 DB arm 을 대표 못함. 중단")
say("★G2 = PASS")

## =============================================================================
## [4] 수리 arm 재적합
## =============================================================================
say("================ [4] 수리 arm ================")
R_f2 <- fit_arm(X2, "raw_fix", "rollaware(4월탐지)")
R_f1 <- fit_arm(X1, "raw_fix", "rollaware(원탐지기)")
arm_tab <- rbindlist(lapply(list(R_plain, R_f2, R_f1), function(r)
  data.table(arm = r$arm, n_months = r$n_months, n_obs = r$n_obs, t_nw3 = r$t_nw3,
             mean = r$mean, sd = r$sd, apr_mean = r$apr, may_mean = r$may, oth_mean = r$oth)))
arm_tab[, delta_t := t_nw3 - R_plain$t_nw3]
arm_tab[, t_B_on_db := T_DB + delta_t]
for (i in seq_len(nrow(arm_tab))) with(arm_tab[i], say(
  "  %-20s n=%3d · %6d obs · ★t %+.4f (Δ %+.4f · DB이식 %+.4f) · 4월 %+.6f · 5월 %+.6f · 평월 %+.6f",
  arm, n_months, n_obs, t_nw3, delta_t, t_B_on_db, apr_mean, may_mean, oth_mean))

## ★설계 확인 — 04/05 외 달 계수가 완전 동일해야 한다
chk <- merge(R_plain$series[, .(signal_ym, mon, e_p = est)],
             R_f2$series[, .(signal_ym, e_f = est)], by = "signal_ym")
chk[, same := abs(e_p - e_f) < 1e-10]
say("★설계 확인: 04/05 외 %d달 중 동일 %d (%.4f) · 04/05 %d달 중 동일 %d (%.4f)",
    chk[!(mon %in% c("04","05")), .N], chk[!(mon %in% c("04","05")), sum(same)],
    chk[!(mon %in% c("04","05")), mean(same)],
    chk[mon %in% c("04","05"), .N], chk[mon %in% c("04","05"), sum(same)],
    chk[mon %in% c("04","05"), mean(same)])
DESIGN_OK <- chk[!(mon %in% c("04","05")), mean(same)] > 0.999
say("   ⇒ 설계 %s", if (DESIGN_OK) "OK (수리가 04/05 에만 국한)" else "★위반 — 다른 달도 바뀜. Δt 해석 불가")

## =============================================================================
## [5] (C) 오염 규모 — 판정 패널 raw 값 분포 (영값 다수 → q90/비영 기준 병기)
## =============================================================================
say("================ [5] (C) 오염 규모 ================")
mg <- rbindlist(lapply(list(list(X2,"raw_plain","plain"), list(X2,"raw_fix","rollaware")), function(z) {
  A <- z[[1]][is.finite(get(z[[2]]))]
  A[, grp := fifelse(mon=="04","04", fifelse(mon=="05","05","other"))]
  A[, .(arm = z[[3]], n = .N, frac_zero = mean(abs(get(z[[2]])) < 1e-9),
        med_nz = median(abs(get(z[[2]]))[abs(get(z[[2]]))>=1e-9]),
        q90_abs = quantile(abs(get(z[[2]])), .90), frac_pos = mean(get(z[[2]]) > 1e-9),
        sd = sd(get(z[[2]]))), by = grp]
}))
setorder(mg, arm, grp)
for (i in seq_len(nrow(mg))) with(mg[i], say(
  "  %-10s %-5s n=%6d · 영값 %.3f · 비영중앙|.| %.5f · q90|.| %.5f · 양비율 %.3f · sd %.4f",
  arm, grp, n, frac_zero, med_nz, q90_abs, frac_pos, sd))
pl <- mg[arm == "plain"]
say("★값 분포 배수(plain, 비영 중앙|raw|): 4월 %.3f배 · 5월 %.3f배 (문턱 2.0)",
    pl[grp=="04", med_nz]/pl[grp=="other", med_nz], pl[grp=="05", med_nz]/pl[grp=="other", med_nz])
say("★양(+)비율: 4월 %.3f · 5월 %.3f · 평월 %.3f (롤오버 상향편향 지문)",
    pl[grp=="04", frac_pos], pl[grp=="05", frac_pos], pl[grp=="other", frac_pos])

## =============================================================================
## [6] 저장
## =============================================================================
fwrite(arm_tab, file.path(OUT, "b2_arm_summary.csv"))
fwrite(mg, file.path(OUT, "b2_raw_magnitude.csv"))
fwrite(chk, file.path(OUT, "b2_design_check.csv"))
fwrite(rbindlist(list(R_plain$series[, arm:="plain"], R_f2$series[, arm:="ra_apr"], R_f1$series[, arm:="ra_raw"])),
       file.path(OUT, "b2_coefs_by_arm.csv"))
saveRDS(list(arm_tab=arm_tab, cens=cens, mg=mg, g1=g1, G1_PASS=G1_PASS, G2_PASS=G2_PASS,
             DESIGN_OK=DESIGN_OK, roll_raw=ROLL_raw, roll_apr=ROLL_apr),
        file.path(OUT, "b2_results.rds"))
say("저장 완료 → %s", OUT)
say("★★[B 정정판] G1 %s · G2 %s · 설계 %s ⇒ t_plain %+.4f → t_RA %+.4f · DB이식 t_B %+.4f (문턱 2.0)",
    if (G1_PASS) "PASS" else "FAIL", if (G2_PASS) "PASS" else "FAIL",
    if (DESIGN_OK) "OK" else "VIOLATION", R_plain$t_nw3, R_f2$t_nw3, T_DB + (R_f2$t_nw3 - R_plain$t_nw3))
