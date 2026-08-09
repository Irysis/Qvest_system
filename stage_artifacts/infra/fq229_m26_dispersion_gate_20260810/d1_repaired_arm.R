## =============================================================================
## FQ-229 (D) — 오염판 / 수리판 양쪽에서 재측정 (PREREG §8)
##  수리판 = FQ-223 make_raw(ROLL_raw) "RA_원탐지기" 재구성 (동일 로직 재사용, factor_db 재빌드 없음)
##  ★창-정합: plain 도 수리판과 **같은 공통 월집합**에서 다시 잰다. 서로 다른 창의 수치를 나란히 놓지 않는다.
## metric_type: canonical_screen_diag. 자본 주장 없음.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT   <- file.path(ROOT, "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
SRC   <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
CD    <- file.path(ROOT, ".cache/consensus")
say <- function(fmt, ...) { cat(sprintf(paste0("[d1] ", fmt, "\n"), ...)); flush.console() }
set.seed(20260814L)
TOL <- 1e-12; LAG <- 63L; MINN <- 30L; NWLAG <- 3L; BURN <- 24L; T_THRESH <- 2.0

nw_t <- function(x, lag = NWLAG) { x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) }
ols_nw <- function(y, X, lag = NWLAG) {
  X <- cbind(`(Intercept)` = 1, as.matrix(X)); ok <- is.finite(y) & apply(is.finite(X), 1, all)
  y <- y[ok]; X <- X[ok, , drop = FALSE]; n <- length(y)
  XtXi <- solve(crossprod(X)); b <- as.numeric(XtXi %*% crossprod(X, y)); e <- as.numeric(y - X %*% b)
  S <- crossprod(X*e)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1)
    G <- crossprod((X*e)[(l+1):n,,drop=FALSE], (X*e)[1:(n-l),,drop=FALSE])/n; S <- S + w*(G+t(G)) }
  V <- XtXi %*% (n*S) %*% XtXi; se <- sqrt(pmax(diag(V),0))
  data.table(term = colnames(X), est = b, se = se, t = b/se, n = n,
             r2 = 1 - sum(e^2)/sum((y-mean(y))^2)) }
fmb_coefs <- function(dat, xs, ycol = "Ret_1m") {
  f <- as.formula(paste(ycol, "~", paste(xs, collapse = " + ")))
  dat[, { fit <- tryCatch(lm(f, data = .SD), error = function(e) NULL)
    if (is.null(fit)) .(term=character(0), est=numeric(0))
    else { cf <- coef(fit); .(term = names(cf), est = as.numeric(cf)) } },
    by = signal_ym, .SDcols = c(ycol, xs)] }
z_fdb <- function(x) { ok <- is.finite(x); if (sum(ok) < 20L) return(rep(NA_real_, length(x)))
  q <- quantile(x[ok], c(0.01, 0.99), na.rm = TRUE, names = FALSE)
  w <- pmin(pmax(x, q[1]), q[2]); mu <- mean(w, na.rm = TRUE); s <- sd(w, na.rm = TRUE)
  if (!is.finite(s) || s < 1e-12) return(rep(NA_real_, length(x)))
  z <- pmin(pmax((w-mu)/s, -3), 3); s2 <- sd(z, na.rm = TRUE)
  if (is.finite(s2) && s2 > 1e-12) z/s2 else z }
neutral <- function(m) { out <- m; run <- 0; cnt <- 0
  for (i in seq_along(m)) { out[i] <- if (cnt > 0 && run/cnt > 1e-9) m[i]/(run/cnt) else m[i]
    run <- run + m[i]; cnt <- cnt + 1 }; out }

## ---------------------------------------------------------------- [0] 재구성
say("================ [0] 수리판 재구성 (FQ-223 로직 재사용) ================")
D4 <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet"))); D4[, Date := as.Date(Date)]
sigs <- sort(unique(D4$Date)); K <- length(sigs)
say("★입력 실측: 판정 패널 %d행 · %d개월 · %s ~ %s", nrow(D4), K, min(sigs), max(sigs))
E <- as.data.table(read_parquet(file.path(CD, "revenue_fy1.parquet"))); E[, Date := as.Date(Date)]
E <- E[!is.na(revenue_fy1), .(Ticker, Date, value = revenue_fy1)]; setorderv(E, c("Ticker","Date"))
E[, prev_v := shift(value), by = Ticker]; E[, chg := !is.na(prev_v) & abs(value - prev_v) > TOL]
lv <- E[, .(n_live = .N), by = Date]; cg <- E[chg == TRUE, .(n_chg = .N), by = Date]
bd <- merge(lv, cg, by = "Date", all.x = TRUE)[is.na(n_chg), n_chg := 0L][, frac := n_chg/n_live]
ROLL_raw <- sort(bd[frac >= 0.50 & n_live >= 50L, Date])
if (!length(ROLL_raw)) stop("[d1] 동시변경일 0건 — 정지 신호")
say("동시변경일 %d건 (FQ-223 원탐지기와 동일 기준)", length(ROLL_raw))
E[, obs_date := Date]; setkeyv(E, c("Ticker","Date")); TK <- unique(E$Ticker)
mkQ <- function(d) { q <- CJ(Ticker = TK, k = seq_len(K), sorted = FALSE); q[, Date := d[k]]
  setkeyv(q, c("Ticker","Date")); q[] }
pb <- function(d) { r <- E[mkQ(d), roll = TRUE,  on = .(Ticker, Date)]; r[!is.na(value), .(Ticker, k, v = value, dd = obs_date)] }
pf <- function(d) { r <- E[mkQ(d), roll = -Inf, on = .(Ticker, Date)]; r[!is.na(value), .(Ticker, k, v = value, dd = obs_date)] }
NOW <- pb(sigs); setnames(NOW, c("v","dd"), c("v_now","d_now"))
LG  <- pb(sigs - LAG); setnames(LG, c("v","dd"), c("v_lag","d_lag"))
KMAP <- data.table(k = seq_len(K), Date = sigs)
JP <- merge(D4[, .(Date, Ticker, signal_ym)], merge(KMAP, merge(NOW, LG, by = c("Ticker","k")), by = "k"),
            by = c("Date","Ticker"))
say("판정 패널 재구성 %d / %d", nrow(JP), nrow(D4))
bas <- as.Date(vapply(sigs, function(s) { kk <- ROLL_raw[ROLL_raw <= s]
  if (!length(kk)) NA_real_ else as.numeric(max(kk)) }, 0), origin = "1970-01-01")
X <- copy(JP); X[, b := bas[k]]
X[, contam := !is.na(b) & d_now >= b & d_lag < b]
FW <- pf(bas); setnames(FW, c("v","dd"), c("v_fix","d_fix"))
X <- merge(X, FW, by = c("Ticker","k"), all.x = TRUE)
X[, fixable := contam & !is.na(v_fix) & abs(v_fix) > 1e-6 & !is.na(d_fix) & d_fix <= Date]
X[, v_use := v_lag][fixable == TRUE, v_use := v_fix]
X[, raw := fifelse(abs(v_use) > 1e-6, (v_now - v_use)/abs(v_use), NA_real_)]
say("오염 %d (%.4f) · 수리 %d", sum(X$contam), mean(X$contam), sum(X$fixable))
X_plain <- copy(JP)[, raw := fifelse(abs(v_lag) > 1e-6, (v_now - v_lag)/abs(v_lag), NA_real_)]

## 부호 정렬 (FQ-223 G1 규약 재사용)
SGNsrc <- merge(D4[, .(Date, Ticker, zdb = M26_Revenue_Mom)], X_plain[, .(Date, Ticker, raw)], by = c("Date","Ticker"))
sg <- SGNsrc[is.finite(raw), .(rho = suppressWarnings(cor(raw, zdb, method = "spearman", use = "complete.obs"))), by = Date]
say("G1 부호정렬: 월별 |rho| 중앙 %.4f · 음부호 %d달", median(abs(sg$rho)), sum(sg$rho < 0))
if (median(abs(sg$rho)) < 0.95) stop("[d1] G1 FAIL — 정지")
SGN <- sg[, .(Date, sgn = sign(rho))]
base_cols <- D4[, .(Date, Ticker, signal_ym, C01_SUE, C02_EPS_Chg_1m, C04_ESBR, Ret_1m)]
prep <- function(XX) { AA <- XX[is.finite(raw), .(Date, Ticker, raw)]
  AA <- merge(AA, SGN, by = "Date")[, zm := z_fdb(raw)*sgn[1], by = Date]
  DD <- merge(base_cols, AA[, .(Date, Ticker, zm)], by = c("Date","Ticker"))
  DD <- DD[complete.cases(DD[, .(C01_SUE, C02_EPS_Chg_1m, C04_ESBR, zm, Ret_1m)])]
  list(DD = DD, ok_ym = DD[, .N, by = signal_ym][N >= MINN, signal_ym]) }
P_plain <- prep(X_plain); P_ra <- prep(X)
common_ym <- sort(intersect(P_plain$ok_ym, P_ra$ok_ym))
say("★공통 월집합 %d개월 (plain %d / RA %d) — 창-정합 후에만 나란히 놓는다",
    length(common_ym), length(P_plain$ok_ym), length(P_ra$ok_ym))

## ---------------------------------------------------------------- [1] arm 별 성분
say("================ [1] arm 별 월별 성분 + parity ================")
build <- function(P, lab) {
  DD <- P$DD[signal_ym %in% common_ym]
  s <- fmb_coefs(DD, c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","zm"))[term == "zm"][order(signal_ym)]
  mv <- DD[, .(disp_t = sd(Ret_1m), sdz = sd(zm)), by = signal_ym][order(signal_ym)]
  d <- merge(s[, .(signal_ym, b = est)], mv, by = "signal_ym")[order(signal_ym)]
  d[, ss := b * sdz / disp_t][, disp_lag1 := shift(disp_t, 1L)]
  list(lab = lab, d = d, t = nw_t(d$b)) }
B_plain <- build(P_plain, "plain(오염판)"); B_ra <- build(P_ra, "RA_원탐지기(수리판)")
say("plain t %+.4f · FQ-223 기록 +2.47826 · |Δ| %.2e", B_plain$t, abs(B_plain$t - 2.47826452473205))
say("RA    t %+.4f · FQ-223 기록 +3.29929 · |Δ| %.2e", B_ra$t, abs(B_ra$t - 3.29928900286445))
par_ok <- abs(B_plain$t - 2.47826452473205) < 1e-3 && abs(B_ra$t - 3.29928900286445) < 1e-3
say("★parity %s", if (par_ok) "PASS" else "★FAIL — 재구성 불일치")
if (!par_ok) stop("[d1] 수리판 재구성 parity FAIL — 정지")

## ---------------------------------------------------------------- [2] 지평 스캔 (h=0,1)
say("================ [2] 지평 스캔 h=0/1 — 스케일(S1) vs 기술(S2) ================")
HZ <- rbindlist(lapply(list(B_plain, B_ra), function(BB) rbindlist(lapply(0:1, function(h) {
  d <- copy(BB$d); d[, x := if (h == 0L) disp_t else disp_lag1]
  r1 <- ols_nw(d$b, d[, .(x)]); r2 <- ols_nw(d$ss, d[, .(x)])
  data.table(arm = BB$lab, h = h, n = r1$n[1],
             S1_c = r1[term=="x", est], S1_t = r1[term=="x", t], S1_r2 = r1$r2[1],
             S2_c = r2[term=="x", est], S2_t = r2[term=="x", t], S2_r2 = r2$r2[1]) }))))
for (i in seq_len(nrow(HZ))) with(HZ[i], say(
  "  %-22s h=%d n=%3d · S1 c %+.5f t %+.3f R2 %.4f | S2 c %+.5f t %+.3f R2 %.4f",
  arm, h, n, S1_c, S1_t, S1_r2, S2_c, S2_t, S2_r2))
say("★수리 효과: h=0 S1 t %+.3f → %+.3f · h=0 S2 t %+.3f → %+.3f · h=1 S1 t %+.3f → %+.3f",
    HZ[arm==B_plain$lab & h==0, S1_t], HZ[arm==B_ra$lab & h==0, S1_t],
    HZ[arm==B_plain$lab & h==0, S2_t], HZ[arm==B_ra$lab & h==0, S2_t],
    HZ[arm==B_plain$lab & h==1, S1_t], HZ[arm==B_ra$lab & h==1, S1_t])
say("   판정: 수리판에서 h=1 이 문턱 %.1f 도달 arm = %s", T_THRESH,
    { s <- HZ[h == 1 & abs(S1_t) >= T_THRESH, arm]; if (length(s)) paste(s, collapse=" / ") else "0건" })

## ---------------------------------------------------------------- [3] 게이트 재료자격 (arm 자기 창)
say("================ [3] 게이트 G1~G4 재료자격 (arm 별 자기 창에서 재구성) ================")
mkgates <- function(d) { d1v <- d$disp_lag1; n <- length(d1v)
  expq <- function(p) { v <- rep(NA_real_, n)
    for (i in seq_len(n)) { h <- d1v[1:i]; h <- h[is.finite(h)]
      if (length(h) >= BURN) v[i] <- quantile(h, p, names = FALSE) }; v }
  q70 <- expq(0.70); q50 <- expq(0.50); q25 <- expq(0.25); q75 <- expq(0.75)
  gz <- rep(NA_real_, n)
  for (i in seq_len(n)) { h <- d1v[1:i]; h <- h[is.finite(h)]
    if (length(h) >= BURN) gz[i] <- (d1v[i] - mean(h))/sd(h) }
  g4 <- rep(NA_real_, n)
  for (i in seq_len(n)) if (is.finite(q25[i])) g4[i] <-
    if (d1v[i] >= q75[i]) 1.50 else if (d1v[i] >= q50[i]) 1.15 else if (d1v[i] >= q25[i]) 0.85 else 0.50
  fx <- function(v) { v[!is.finite(v)] <- 1; v }
  list(G1 = fx(ifelse(is.finite(q70) & d1v >= q70, 1, ifelse(is.finite(q70), 0, NA))),
       G2 = fx(ifelse(is.finite(q50) & d1v >= q50, 1, ifelse(is.finite(q50), 0, NA))),
       G3 = fx(pmin(pmax(1 + 1.0*gz, 0), 2)), G4 = fx(g4)) }
MAT <- rbindlist(lapply(list(B_plain, B_ra), function(BB) {
  gg <- mkgates(BB$d); y <- BB$d$b; t0 <- nw_t(y)
  rbindlist(lapply(names(gg), function(nm) { mt <- neutral(gg[[nm]])
    data.table(arm = BB$lab, gate = nm, t_base = t0, t_gated = nw_t(mt*y),
               delta_t = nw_t(mt*y) - t0, mean_exposure = mean(mt), n_on = sum(gg[[nm]] > 0)) })) }))
for (i in seq_len(nrow(MAT))) with(MAT[i], say(
  "  %-22s %s: t %+.4f → %+.4f (Δt %+.4f) · 발화 %d · 평균노출 %.3f", arm, gate, t_base, t_gated, delta_t, n_on, mean_exposure))
say("★게이트 판정: Δt > 0 인 (arm, gate) 조합 = %s",
    { s <- MAT[delta_t > 0, paste0(arm, "/", gate)]; if (length(s)) paste(s, collapse=" · ") else "0건 — 오염판·수리판 양쪽에서 어떤 게이트도 개선 없음" })

fwrite(HZ, file.path(OUT, "d1_horizon_by_arm.csv"))
fwrite(MAT, file.path(OUT, "d1_gate_by_arm.csv"))
fwrite(rbindlist(list(cbind(arm = B_plain$lab, B_plain$d), cbind(arm = B_ra$lab, B_ra$d))),
       file.path(OUT, "d1_components_by_arm.csv"))
saveRDS(list(HZ = HZ, MAT = MAT, common_n = length(common_ym),
             t_plain = B_plain$t, t_ra = B_ra$t), file.path(OUT, "d1_results.rds"))
say("저장 완료 -> %s", OUT)
say("★★[D 요약] 공통 %d개월 · plain t %+.3f / RA t %+.3f · h=1 S1 최대|t| %.3f · 개선 게이트 %d개",
    length(common_ym), B_plain$t, B_ra$t, max(abs(HZ[h==1, S1_t])), sum(MAT$delta_t > 0))
