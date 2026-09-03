# S3 — 1급(F1) GH2004 Table V 이식 Fama-MacBeth  [envelope_applicability: NOT_APPLICABLE]
#   R_it = b0 + b1*R_{i,t-1} + b2*size_{i,t-1} + b3*JH + b4*JL + b5*MH + b6*ML + b7*FHH + b8*FHL + e
#   더미 = 측정월 t-j 의 상/하위 30%. j=2..7 (1개월 skip) 평균 -> 월별 계수 시계열 -> NW lag-3 t
#   ★이것은 단면 회귀 계수 검정이지 포트폴리오 성과가 아니다. 실투형 envelope 미적용.
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
O <- readRDS(file.path(OUT, "s2_objects.rds"))
SIG <- O$SIG; E0 <- O$E0; R <- O$R; bench <- O$bench

nw_t <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(NA_real_)
  m <- lm(x ~ 1); ct <- coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))
  c(mean = ct[1,1], t = ct[1,3], n = length(x)) }

## ── 래그 패널: 각 종목의 월간 시계열에 lag 1..6 부여 ────────────────────────
setorder(SIG, Ticker, Date)
LAGV <- c("fh252","fh12m","lo52","jt6","ind6")
for (L in 1:6) for (v in LAGV) SIG[, (paste0(v,"_l",L)) := shift(get(v), L), by = Ticker]
SIG[, logsize := log(pmax(Size, 1))]

## ── 회귀 표본: 적격 단면(월말 s, 유니버스 + 유동성) + forward 수익 ──────────
KEEP <- c("Date","Ticker","mkt","mret","logsize", unlist(lapply(1:6, function(L) paste0(LAGV,"_l",L))))
BASE <- merge(E0[, .(Date, Ticker)], SIG[, ..KEEP], by = c("Date","Ticker"))
BASE <- merge(BASE, R, by = c("Date","Ticker"))
cat(sprintf("[S3] 회귀 표본 %d rows / %d months / 월중앙 %.0f종\n",
            nrow(BASE), uniqueN(BASE$Date), median(BASE[, .N, by = Date]$N)))

## ── 더미 생성기 ─────────────────────────────────────────────────────────────
mk_dum <- function(dt, col, prefix, mode) {
  # mode: "pooled" = 혼합 랭킹 / "mktint" = 시장(K200/KQ150)-내 랭킹
  g <- if (mode == "pooled") "Date" else c("Date","mkt")
  dt[, pct := { v <- get(col); n <- sum(is.finite(v))
                fifelse(is.finite(v), (frank(v, ties.method="average", na.last="keep")-0.5)/n, NA_real_) }, by = g]
  dt[, (paste0(prefix,"H")) := as.integer(is.finite(pct) & pct >= 0.7)]
  dt[, (paste0(prefix,"L")) := as.integer(is.finite(pct) & pct <= 0.3)]
  dt[!is.finite(pct), c(paste0(prefix,"H"), paste0(prefix,"L")) := NA_integer_]
  dt[, pct := NULL]; invisible(dt) }

## ── FM 실행기 ───────────────────────────────────────────────────────────────
run_fm <- function(fhcol, mode, jrange = 2:7, extra = character(0), label = "") {
  coefs <- rbindlist(lapply(jrange, function(j) {
    L <- j - 1L
    D <- BASE[, c("Date","Ticker","mkt","mret","logsize","Ret_1m",
                  paste0(fhcol,"_l",L), paste0("jt6_l",L), paste0("ind6_l",L),
                  if (length(extra)) paste0(extra,"_l",L) else NULL), with = FALSE]
    setnames(D, paste0(fhcol,"_l",L), "FH"); setnames(D, paste0("jt6_l",L), "JT")
    setnames(D, paste0("ind6_l",L), "IND")
    if (length(extra)) setnames(D, paste0(extra,"_l",L), extra)
    D <- D[is.finite(mret) & is.finite(logsize) & is.finite(Ret_1m) & is.finite(FH) & is.finite(JT) & is.finite(IND)]
    if (length(extra)) for (e in extra) D <- D[is.finite(get(e))]
    mk_dum(D, "JT", "J", mode); mk_dum(D, "IND", "M", mode); mk_dum(D, "FH", "FH", mode)
    if (length(extra)) for (e in extra) mk_dum(D, e, paste0(e,"_"), mode)
    rhs <- c("mret","logsize","JH","JL","MH","ML","FHH","FHL",
             if (length(extra)) unlist(lapply(extra, function(e) c(paste0(e,"_H"), paste0(e,"_L")))) else NULL)
    frm <- as.formula(paste("Ret_1m ~", paste(rhs, collapse = " + ")))
    out <- D[, { if (.N < 40L) NULL else {
        f <- tryCatch(lm(frm, data = .SD), error = function(e) NULL)
        if (is.null(f)) NULL else as.list(coef(f)) } }, by = Date]
    if (!nrow(out)) return(NULL)
    out[, j := j][] }), fill = TRUE)
  if (!nrow(coefs)) return(NULL)
  vars <- setdiff(names(coefs), c("Date","j"))
  avg <- coefs[, lapply(.SD, function(x) mean(x, na.rm = TRUE)), by = Date, .SDcols = vars]
  avg <- avg[order(Date)]
  st <- lapply(vars, function(v) { z <- nw_t(avg[[v]])
    list(var = v, mean_monthly = unname(z["mean"]), mean_ann_pct = 100*12*unname(z["mean"]),
         nw_t = unname(z["t"]), n_months = unname(z["n"])) })
  names(st) <- vars
  sp <- avg[, .(Date, spread = FHH - FHL, jt_spread = JH - JL, ind_spread = MH - ML)]
  z1 <- nw_t(sp$spread); z2 <- nw_t(sp$jt_spread); z3 <- nw_t(sp$ind_spread)
  dd <- sp$spread - sp$jt_spread; z4 <- nw_t(dd)
  list(label = label, fh_convention = fhcol, ranking_mode = mode, j_range = range(jrange),
       n_months = nrow(avg), n_cs_regressions = nrow(coefs),
       coefficients = st,
       spreads = list(
         fh_HminusL = list(mean_monthly = unname(z1["mean"]), mean_ann_pct = 100*12*unname(z1["mean"]), nw_t = unname(z1["t"])),
         jt_HminusL = list(mean_monthly = unname(z2["mean"]), mean_ann_pct = 100*12*unname(z2["mean"]), nw_t = unname(z2["t"])),
         ind_HminusL = list(mean_monthly = unname(z3["mean"]), mean_ann_pct = 100*12*unname(z3["mean"]), nw_t = unname(z3["t"])),
         fh_minus_jt_spread = list(mean_monthly = unname(z4["mean"]), nw_t = unname(z4["t"]),
                                   labeling = "reference_only_not_verdict_bearing — 숏 레그 포함 청구")),
       series = avg) }

fmt1 <- function(x) sprintf("%-8s %+8.4f%%/월 (%+7.2f%%/yr) NW-t=%+7.3f n=%d", x$var,
                            100*x$mean_monthly, x$mean_ann_pct, x$nw_t, x$n_months)
show <- function(r) { cat(sprintf("\n--- %s | fh=%s | rank=%s | n_months=%d (%d 단면회귀) ---\n",
                                  r$label, r$fh_convention, r$ranking_mode, r$n_months, r$n_cs_regressions))
  for (v in c("FHH","FHL","JH","JL","MH","ML","mret","logsize")) if (!is.null(r$coefficients[[v]])) cat(" ", fmt1(r$coefficients[[v]]), "\n")
  cat(sprintf("   FHH-FHL %+8.4f%%/월 t=%+7.3f | JH-JL %+8.4f%%/월 t=%+7.3f | MH-ML %+8.4f%%/월 t=%+7.3f\n",
              100*r$spreads$fh_HminusL$mean_monthly, r$spreads$fh_HminusL$nw_t,
              100*r$spreads$jt_HminusL$mean_monthly, r$spreads$jt_HminusL$nw_t,
              100*r$spreads$ind_HminusL$mean_monthly, r$spreads$ind_HminusL$nw_t)) }

F1_pooled_252  <- run_fm("fh252", "pooled", 2:7, label = "F1 base (혼합 랭킹, M06 252d 규약)")
F1_mktint_252  <- run_fm("fh252", "mktint", 2:7, label = "F1 base (시장-내 랭킹, M06 252d 규약)")
F1_pooled_12m  <- run_fm("fh12m", "pooled", 2:7, label = "F1 base (혼합 랭킹, GH2004 12개월 규약)")
F1_mktint_12m  <- run_fm("fh12m", "mktint", 2:7, label = "F1 base (시장-내 랭킹, GH2004 12개월 규약)")
for (r in list(F1_pooled_252, F1_mktint_252, F1_pooled_12m, F1_mktint_12m)) show(r)

## ── F5: M17_Low_52w 동시 투입 (준거점 식별) ─────────────────────────────────
F5_mktint <- run_fm("fh252", "mktint", 2:7, extra = "lo52", label = "F5 (M17_Low_52w 동시 투입, 시장-내 랭킹)")
F5_pooled <- run_fm("fh252", "pooled", 2:7, extra = "lo52", label = "F5 (M17_Low_52w 동시 투입, 혼합 랭킹)")
for (r in list(F5_mktint, F5_pooled)) { show(r)
  for (v in c("lo52_H","lo52_L")) if (!is.null(r$coefficients[[v]])) cat(" ", fmt1(r$coefficients[[v]]), "\n") }

## ── 사전등록 판정 ───────────────────────────────────────────────────────────
prim <- F1_mktint_252
rj1 <- !(is.finite(prim$coefficients$FHH$nw_t) && prim$coefficients$FHH$nw_t >= 2 &&
         prim$coefficients$FHH$mean_monthly > 0)
dom <- prim$spreads$fh_HminusL$mean_monthly - prim$spreads$jt_HminusL$mean_monthly
rj2 <- !(is.finite(dom) && dom > 0 && is.finite(prim$spreads$fh_minus_jt_spread$nw_t) &&
         prim$spreads$fh_minus_jt_spread$nw_t >= 2)

res <- list(
  meta = list(wt_id = "WT-R20260829_007", test_id = "F1", tier = "primary_cross_sectional_statistic",
              envelope_applicability = "NOT_APPLICABLE — 단면 회귀 계수 검정. 실투형 envelope(<=25종/long-only/Sigma w=1) 미적용. 포트폴리오 판정 아님.",
              metric_type = "cross_sectional_regression",
              spec = "GH2004 Table V 9변수: R_{t-1} + size_{t-1} + JH + JL + MH + ML + FHH + FHL. 상/하위 30% 더미. j=2..7 평균(1개월 skip).",
              deviation_from_paper = c(
                "GH2004 = CRSP 전종목(수천), 20개 2-digit SIC 산업, 1963-07~2001-12(462월). 본 이식 = K200 union KQ150(월중앙 ~349종), RAWDATA Sector 라벨 EW 산업수익, 2005-01~2026-08.",
                "GH2004 의 high = 최근 12개월 최고가. 본 라운드는 두 규약 병기 — fh252(in-house M06, 최근 252 거래일 종가 최고) / fh12m(원문 규약, 최근 12 캘린더월 월중 종가 최고).",
                "산업 정의: GH2004 는 시가총액가중 20 SIC 산업. 본 이식은 RAWDATA Sector EW — M07_IndMom 관행 계승(H8 승계)."),
              paper_reference = list(
                FHH = "+0.16%/월 (t 3.06) raw / +0.27%/월 (t 6.49) risk-adj",
                FHL = "-0.48%/월 (t -4.07) raw", JH = "+0.17%/월 (t 2.07) raw", JL = "-0.21%/월 raw",
                MH = "+0.18%/월 raw", ML = "-0.07%/월 raw")),
  F1_market_internal_M06_252d = F1_mktint_252[names(F1_mktint_252) != "series"],
  F1_pooled_M06_252d = F1_pooled_252[names(F1_pooled_252) != "series"],
  F1_market_internal_GH_12m = F1_mktint_12m[names(F1_mktint_12m) != "series"],
  F1_pooled_GH_12m = F1_pooled_12m[names(F1_pooled_12m) != "series"],
  F5_low52_identification_mktint = F5_mktint[names(F5_mktint) != "series"],
  F5_low52_identification_pooled = F5_pooled[names(F5_pooled) != "series"],
  preregistered_verdict = list(
    primary_spec = "F1 시장-내 랭킹 / M06 252d 규약 (선행 런과의 신호 규약 정합)",
    reject_if_1 = "FHH 가 유의 양(+)이 아니면 근접도의 KR 예측력 부재 -> 기각",
    reject_if_1_fired = rj1,
    reject_if_2 = "(FHH-FHL) 이 (JH-JL) 을 압도하지 못하면 GH2004 지배 주장이 KR 에 불성립",
    reject_if_2_fired = rj2,
    dominance_gap_monthly = dom,
    labeling_constraint = "(FHH-FHL) 지배 검정은 숏 레그 포함 청구다 — reference_only_not_verdict_bearing. 롱온리 관련 반쪽은 FHH 단독이며 별도 보고한다."))
write_json(res, file.path(OUT, "s3_primary_fm.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(BASE = BASE, SIG = SIG,
             F1_mktint_252 = F1_mktint_252, F1_pooled_252 = F1_pooled_252,
             F1_mktint_12m = F1_mktint_12m, F1_pooled_12m = F1_pooled_12m,
             F5_mktint = F5_mktint, F5_pooled = F5_pooled), file.path(OUT, "s3_objects.rds"))
cat(sprintf("\n[S3] reject_if_1 fired=%s | reject_if_2 fired=%s | dominance gap=%+0.5f/월\n",
            rj1, rj2, dom))
