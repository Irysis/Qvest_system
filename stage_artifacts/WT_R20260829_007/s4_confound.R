# S4 — F4 필수 교란 기각 (이 라운드의 실질 게이트)
#   ①시장-내 랭킹 vs 혼합 랭킹  ②L-family(L01/L09/L11) + 실현변동성(D35) + 산업모멘텀(M07) 통제
#   ③직교성은 전 구간 상관이 아니라 분위 양끝(절단면) 잔존으로 측정  ④축별 누출 귀무
#   ★선행 C 등급 런(STR_AS_20260612_132740_321992)의 FM Score NW-t +3.199 가 이 통제 뒤에 생존하는가.
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest); library(future.apply)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
O2 <- readRDS(file.path(OUT, "s2_objects.rds")); O3 <- readRDS(file.path(OUT, "s3_objects.rds"))
E0 <- O2$E0; R <- O2$R; BASE <- O3$BASE; SIG <- O3$SIG
ME <- sort(unique(E0$Date))
t0 <- Sys.time()

nw_t <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(c(mean=NA_real_,t=NA_real_,n=length(x)))
  m <- lm(x ~ 1); ct <- coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))
  c(mean = ct[1,1], t = ct[1,3], n = length(x)) }
zsc <- function(v) { s <- sd(v, na.rm = TRUE); if (!is.finite(s) || s == 0) return(rep(NA_real_, length(v)))
  (v - mean(v, na.rm = TRUE))/s }
rz <- function(v) { n <- sum(is.finite(v)); q <- (frank(v, ties.method="average", na.last="keep")-0.5)/n
  qnorm(pmin(pmax(q, 1e-4), 1-1e-4)) }

## ── Factor DB 통제축 로드 (PIT C15: load_month_factors 경유만) ──────────────
FN <- c("L01_Amihud","L09_Amihud_20d","L11_Kyle_Lambda","D35_RealVol_63d",
        "M06_High_52w","M02_Mom_6_1","M07_IndMom","M17_Low_52w")
plan(multisession, workers = min(6L, max(1L, parallel::detectCores()-1L)))
FDB <- rbindlist(future_lapply(ME, function(d) {
  suppressWarnings(suppressMessages(library(data.table)))
  rt <- Sys.getenv("QM_ROOT"); if (!nzchar(rt)) rt <- getwd()
  Sys.setenv(CLAUDE_PROJECT_DIR = rt)
  suppressMessages(source(file.path(rt, "02_Infrastructure/factor_db/factor_db_connector.R")))
  x <- tryCatch(as.data.table(load_month_factors(d, factor_names = FN)), error = function(e) NULL)
  if (is.null(x) || !nrow(x)) return(NULL)
  w <- dcast(x[Factor_Name %in% FN], Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
             fun.aggregate = function(v) v[1])
  w[, Date := d][] }, future.seed = TRUE), fill = TRUE)
plan(sequential)
cat(sprintf("[S4] FDB %d rows / %d months / elapsed %.1fs\n", nrow(FDB), uniqueN(FDB$Date),
            as.numeric(difftime(Sys.time(), t0, units="secs"))))

## ── 신호 패널 (월말 s, skip 없음 = 실투 후보와 동일 시점 규약) ──────────────
P <- merge(E0[, .(Date, Ticker, mkt, fh252, fh12m, lo52, jt6, ind6, rv63, amih20, Size)],
           R, by = c("Date","Ticker"))
P <- merge(P, FDB, by = c("Date","Ticker"), all.x = TRUE)
P[, logsize := log(pmax(Size, 1))]
cat(sprintf("[S4] 패널 %d rows / %d months / FDB 매칭률 %.3f\n", nrow(P), uniqueN(P$Date),
            mean(is.finite(P$M06_High_52w))))

## ── 양성 대조 A: 자체 산출 fh252 vs Factor DB M06_High_52w ──────────────────
par_m06 <- P[is.finite(fh252) & is.finite(M06_High_52w), .(rho = cor(fh252, M06_High_52w, method="spearman"), n = .N), by = Date]
parity_m06 <- list(mean_abs_spearman = mean(abs(par_m06$rho), na.rm=TRUE),
                   median_spearman = median(par_m06$rho, na.rm=TRUE),
                   min_abs = min(abs(par_m06$rho), na.rm=TRUE), n_months = nrow(par_m06),
                   note = "Z_Score_Aligned 는 IC 로 방향이 결정되므로 부호는 데이터 산물이다 — 크기(|rho|)만 읽는다. |rho| ~ 1 이면 자체 산출 신호가 등재 M06 과 동일 대상.")
cat(sprintf("[S4][PARITY] fh252 vs M06_High_52w: mean|rho|=%.4f median rho=%+.4f min|rho|=%.4f\n",
            parity_m06$mean_abs_spearman, parity_m06$median_spearman, parity_m06$min_abs))

## ── 연속 스코어 FM 사다리 (통제 전 -> 후) ───────────────────────────────────
##   랭킹 모드: pooled(혼합) / mktint(시장-내). z 는 각 모드의 그룹 안에서 산출.
mk_z <- function(dt, cols, mode) { g <- if (mode == "pooled") "Date" else c("Date","mkt")
  for (cc in cols) dt[, (paste0("z_",cc)) := rz(get(cc)), by = g]; invisible(dt) }

ladder_spec <- list(
  S0_signal_only      = character(0),
  S1_plus_mom_size    = c("jt6","logsize"),
  S2_plus_indmom      = c("jt6","logsize","ind6"),
  S3_plus_vol         = c("jt6","logsize","ind6","rv63"),
  S4_plus_Lfamily     = c("jt6","logsize","ind6","rv63","L01_Amihud","L09_Amihud_20d","L11_Kyle_Lambda"),
  S5_full_D35_M17     = c("jt6","logsize","ind6","rv63","L01_Amihud","L09_Amihud_20d","L11_Kyle_Lambda","D35_RealVol_63d","lo52"))
ALLC <- unique(c("fh252","fh12m", unlist(ladder_spec)))

run_ladder <- function(mode, sigcol = "fh252") {
  D <- copy(P)
  mk_z(D, ALLC, mode)
  lapply(names(ladder_spec), function(nm) {
    ctr <- ladder_spec[[nm]]
    vs <- c(paste0("z_", sigcol), if (length(ctr)) paste0("z_", ctr) else NULL)
    d <- D[, c("Date","Ticker","Ret_1m", vs), with = FALSE]
    for (v in vs) d <- d[is.finite(get(v))]
    d <- d[is.finite(Ret_1m)]
    frm <- as.formula(paste("Ret_1m ~", paste(vs, collapse = " + ")))
    co <- d[, { if (.N < 40L) NULL else { f <- tryCatch(lm(frm, data = .SD), error=function(e) NULL)
                 if (is.null(f)) NULL else as.list(coef(f)) } }, by = Date]
    if (!nrow(co)) return(NULL)
    key <- paste0("z_", sigcol)
    z <- nw_t(co[[key]])
    list(step = nm, controls = ctr, n_months = nrow(co),
         n_obs_median = median(d[, .N, by=Date]$N),
         signal_lambda_monthly = unname(z["mean"]), signal_lambda_ann_pct = 100*12*unname(z["mean"]),
         signal_nw_t = unname(z["t"]),
         all_coefs = setNames(lapply(setdiff(names(co), "Date"), function(v) {
           zz <- nw_t(co[[v]]); list(var = v, mean = unname(zz["mean"]), nw_t = unname(zz["t"])) }),
           setdiff(names(co), "Date"))) }) }

L_pooled <- run_ladder("pooled"); names(L_pooled) <- names(ladder_spec)
L_mktint <- run_ladder("mktint"); names(L_mktint) <- names(ladder_spec)
cat("\n===== F4 사다리: 연속 근접도 스코어 (통제 전 -> 후) =====\n")
for (mode in c("pooled","mktint")) { LL <- if (mode=="pooled") L_pooled else L_mktint
  cat(sprintf("-- ranking=%s --\n", mode))
  for (nm in names(LL)) { x <- LL[[nm]]; if (is.null(x)) next
    cat(sprintf("  %-18s lambda=%+8.5f (%+6.2f%%/yr) NW-t=%+7.3f  n=%d obs=%.0f\n",
                nm, x$signal_lambda_monthly, x$signal_lambda_ann_pct, x$signal_nw_t, x$n_months, x$n_obs_median)) } }

## ── 축별 누출 귀무 (순수 통제변수를 score 로 주입) ──────────────────────────
leak_axes <- c("rv63","amih20","logsize","L01_Amihud","L09_Amihud_20d","L11_Kyle_Lambda","D35_RealVol_63d")
D2 <- copy(P); mk_z(D2, unique(c(ALLC, leak_axes)), "mktint")
leak <- lapply(leak_axes, function(a) {
  vs <- c(paste0("z_",a), paste0("z_", ladder_spec$S2_plus_indmom))
  d <- D2[, c("Date","Ret_1m", vs), with=FALSE]; for (v in vs) d <- d[is.finite(get(v))]
  d <- d[is.finite(Ret_1m)]
  frm <- as.formula(paste("Ret_1m ~", paste(vs, collapse=" + ")))
  co <- d[, { if (.N < 40L) NULL else as.list(coef(lm(frm, data=.SD))) }, by = Date]
  z <- nw_t(co[[paste0("z_",a)]])
  list(axis = a, lambda_monthly = unname(z["mean"]), nw_t = unname(z["t"]), n = unname(z["n"])) })
names(leak) <- leak_axes
sig_ref <- L_mktint$S2_plus_indmom$signal_nw_t
cat("\n===== 축별 누출 귀무 (동일 사양 S2 에 순수 통제축 주입) =====\n")
for (a in leak_axes) cat(sprintf("  %-18s NW-t=%+7.3f  (신호 자신 %+7.3f)\n", a, leak[[a]]$nw_t, sig_ref))

## ── 직교화 후 재검정 + 절단면(분위 양끝) 잔존 ───────────────────────────────
CTRL <- ladder_spec$S4_plus_Lfamily
orth_run <- function(conv) {   # conv: "raw" | "rank"
  D <- copy(P); mk_z(D, ALLC, "mktint")
  vs <- paste0("z_", CTRL)
  d <- D[, c("Date","Ticker","mkt","Ret_1m","fh252","rv63","amih20","logsize", "z_fh252", vs), with=FALSE]
  for (v in c("z_fh252", vs)) d <- d[is.finite(get(v))]
  if (conv == "rank") { for (v in vs) d[, (v) := rz(get(v)), by = .(Date, mkt)] }
  frm <- as.formula(paste("z_fh252 ~", paste(vs, collapse=" + ")))
  d[, resid_fh := { f <- lm(frm, data = .SD); as.numeric(residuals(f)) }, by = Date]
  dd <- d[is.finite(Ret_1m)]
  co <- dd[, { if (.N < 40L) NULL else as.list(coef(lm(Ret_1m ~ resid_fh, data=.SD))) }, by = Date]
  z <- nw_t(co$resid_fh)
  ## 전 구간 상관 (직교화 후) — 관행 진단
  fullcor <- d[, lapply(.SD, function(v) cor(resid_fh, v, method="spearman", use="pairwise")),
               by = Date, .SDcols = c("rv63","amih20","logsize")]
  ## 절단면: resid_fh 십분위별 통제축 평균 -> 양끝 대 중앙 비율
  d[, dec := as.integer(pmin(10L, 1L + floor((frank(resid_fh, ties.method="first")-0.5)/.N*10))), by = Date]
  prof <- d[, .(rv = mean(rv63, na.rm=TRUE), am = mean(amih20, na.rm=TRUE), ls = mean(logsize, na.rm=TRUE)),
            by = .(Date, dec)]
  pm <- prof[, .(rv = mean(rv, na.rm=TRUE), am = mean(am, na.rm=TRUE), ls = mean(ls, na.rm=TRUE)), by = dec][order(dec)]
  ends_mid <- function(v) { e <- mean(c(v[1], v[10])); m <- mean(v[4:7]); e/m }
  list(convention = conv, n_months = nrow(co),
       resid_signal_lambda = unname(z["mean"]), resid_signal_ann_pct = 100*12*unname(z["mean"]),
       resid_signal_nw_t = unname(z["t"]),
       fullsample_spearman_after_orth = list(rv63 = mean(fullcor$rv63, na.rm=TRUE),
                                             amihud20 = mean(fullcor$amih20, na.rm=TRUE),
                                             logsize = mean(fullcor$logsize, na.rm=TRUE)),
       cutplane_decile_profile = list(
         rv63 = pm$rv, amihud20 = pm$am, logsize = pm$ls,
         ends_over_middle_ratio = list(rv63 = ends_mid(pm$rv), amihud20 = ends_mid(pm$am), logsize = ends_mid(pm$ls))),
       reading_rule = "전 구간 상관 ~0 인데 양끝/중앙 비율이 1 에서 멀면 통제축이 절단면 위에서 되살아난 것 — 직교성 주장 불성립.") }
ORTH_raw  <- orth_run("raw")
ORTH_rank <- orth_run("rank")
cat("\n===== 직교화 후 재검정 + 절단면 =====\n")
for (o in list(ORTH_raw, ORTH_rank)) {
  cat(sprintf("  conv=%-4s resid lambda=%+8.5f (%+6.2f%%/yr) NW-t=%+7.3f | 전구간 rho: rv %+0.3f am %+0.3f size %+0.3f | 양끝/중앙: rv %.4f am %.4f size %.4f\n",
    o$convention, o$resid_signal_lambda, o$resid_signal_ann_pct, o$resid_signal_nw_t,
    o$fullsample_spearman_after_orth$rv63, o$fullsample_spearman_after_orth$amihud20, o$fullsample_spearman_after_orth$logsize,
    o$cutplane_decile_profile$ends_over_middle_ratio$rv63, o$cutplane_decile_profile$ends_over_middle_ratio$amihud20,
    o$cutplane_decile_profile$ends_over_middle_ratio$logsize)) }

## ── 시장 더미 아티팩트 점검 (3/20 선례) ─────────────────────────────────────
D3 <- copy(P); mk_z(D3, ALLC, "pooled"); setnames(D3, "z_fh252", "z_fh_pooled")
D4 <- copy(P); mk_z(D4, ALLC, "mktint"); setnames(D4, "z_fh252", "z_fh_mktint")
MM <- merge(D3[, .(Date, Ticker, mkt, z_fh_pooled)], D4[, .(Date, Ticker, z_fh_mktint)], by = c("Date","Ticker"))
mkt_art <- list(
  rho_pooled_z_vs_KQ_dummy = MM[is.finite(z_fh_pooled), .(r = cor(z_fh_pooled, as.integer(mkt=="KQ150"), method="spearman")), by=Date][, mean(r, na.rm=TRUE)],
  rho_mktint_z_vs_KQ_dummy = MM[is.finite(z_fh_mktint), .(r = cor(z_fh_mktint, as.integer(mkt=="KQ150"), method="spearman")), by=Date][, mean(r, na.rm=TRUE)],
  kq_share_top30_pooled = MM[is.finite(z_fh_pooled), { th <- quantile(z_fh_pooled, 0.7, na.rm=TRUE); .(s = mean(mkt[z_fh_pooled>=th]=="KQ150")) }, by=Date][, mean(s, na.rm=TRUE)],
  kq_share_bot30_pooled = MM[is.finite(z_fh_pooled), { th <- quantile(z_fh_pooled, 0.3, na.rm=TRUE); .(s = mean(mkt[z_fh_pooled<=th]=="KQ150")) }, by=Date][, mean(s, na.rm=TRUE)],
  kq_share_top30_mktint = MM[is.finite(z_fh_mktint), { th <- quantile(z_fh_mktint, 0.7, na.rm=TRUE); .(s = mean(mkt[z_fh_mktint>=th]=="KQ150")) }, by=Date][, mean(s, na.rm=TRUE)],
  note = "3/20 은 같은 자리에서 혼합 랭킹이 시장 더미(-19.58%/yr NW-t -2.526)를 재고 있음을 적발했다. 본 축에서도 같은 검사를 건다.")
cat(sprintf("\n[S4][MKT] pooled z vs KQ더미 rho=%+.4f / mktint rho=%+.4f | 상위30%% KQ비중 pooled %.3f vs mktint %.3f (하위30%% pooled %.3f)\n",
            mkt_art$rho_pooled_z_vs_KQ_dummy, mkt_art$rho_mktint_z_vs_KQ_dummy,
            mkt_art$kq_share_top30_pooled, mkt_art$kq_share_top30_mktint, mkt_art$kq_share_bot30_pooled))

## ── 판정 ────────────────────────────────────────────────────────────────────
t_before <- L_mktint$S0_signal_only$signal_nw_t
t_after  <- L_mktint$S4_plus_Lfamily$signal_nw_t
t_full   <- L_mktint$S5_full_D35_M17$signal_nw_t
verdict <- list(
  prior_run_coordinate = list(
    strategy_id = "STR_AS_20260612_132740_321992",
    fmb_score_lambda = 0.00494, fmb_score_t_nw = 3.199,
    controls_present_in_prior_run = "없음 — 시장-내 랭킹 여부 불명 · L-family/변동성/산업모멘텀 통제 전부 부재",
    what_this_test_does = "동일 신호를 동일 시점 규약으로 재측정하되 통제를 단계별로 추가해 t 3.199 의 귀속을 확정한다."),
  t_no_control = t_before, t_after_Lfamily_vol = t_after, t_full_spec = t_full,
  attenuation_ratio = if (is.finite(t_before) && t_before != 0) t_after/t_before else NA_real_,
  reject_if_1 = "혼합 랭킹에서 유의하던 FHH 가 시장-내 랭킹에서 소멸하면 시장 더미 아티팩트",
  reject_if_2 = "L-family/변동성 통제 후 신호가 소멸하면 저변동성/유동성 계열의 재명명",
  leakage_null_max_abs_t = max(abs(vapply(leak, function(x) x$nw_t, numeric(1))), na.rm=TRUE),
  leakage_null_beats_signal = max(abs(vapply(leak, function(x) x$nw_t, numeric(1))), na.rm=TRUE) > abs(sig_ref))

res <- list(
  meta = list(wt_id = "WT-R20260829_007", test_id = "F4", tier = "confound_rejection_mandatory",
              metric_type = "cross_sectional_regression",
              envelope_applicability = "NOT_APPLICABLE — 단면 회귀. 포트폴리오 판정 아님.",
              control_transform_convention = "z = 시장-내(또는 혼합) 단면 정규분위(rank -> qnorm). 직교화는 raw/rank 두 규약 병기 — '통제했다' 진술은 변환 규약 없이 강도가 미정이다(measurement-graduation §3).",
              pit_c15 = "L01/L09/L11/D35/M06/M02/M07/M17 전부 load_month_factors() 경유 · Z_Score_Aligned 그대로(C13)",
              n_months = uniqueN(P$Date)),
  parity_own_signal_vs_factordb_M06 = parity_m06,
  ladder_pooled = L_pooled, ladder_market_internal = L_mktint,
  leakage_null_by_axis = leak, signal_reference_t_S2 = sig_ref,
  orthogonalized = list(raw = ORTH_raw, rank = ORTH_rank),
  market_dummy_artifact_check = mkt_art,
  verdict = verdict)
write_json(res, file.path(OUT, "s4_confound.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(P = P, FDB = FDB, L_pooled = L_pooled, L_mktint = L_mktint,
             ORTH_raw = ORTH_raw, ORTH_rank = ORTH_rank, leak = leak), file.path(OUT, "s4_objects.rds"))
cat(sprintf("\n[S4] done %.1fs | t(통제전)=%+.3f -> t(L-family+vol)=%+.3f -> t(full)=%+.3f\n",
            as.numeric(difftime(Sys.time(), t0, units="secs")), t_before, t_after, t_full))
