# S6 — 부수관측 F2 (장기 무반전) · F3 (신고가 부근 개인 순매수 부호)
#  F2: GH2004 Table VI 사양 (6,k,12) — gap k = 12/24/36/48, j = k+1..k+12 평균
#  F3: GK2001 의 KR 대응 — 근접도 상위 코호트의 개인 순매수 부호. 기전 진단 전용(신호 경로 미진입).
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(arrow); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
O2 <- readRDS(file.path(OUT, "s2_objects.rds")); O3 <- readRDS(file.path(OUT, "s3_objects.rds"))
SIG <- O3$SIG; E0 <- O2$E0; R <- O2$R
ME <- sort(unique(E0$Date))

nw <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(c(mean=NA_real_,t=NA_real_,n=length(x)))
  m <- lm(x ~ 1); ct <- coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE)); c(mean=ct[1,1], t=ct[1,3], n=length(x)) }
nw_l <- function(x, L) { x <- x[is.finite(x)]; if (length(x) < 8L) return(c(mean=NA_real_,t=NA_real_,n=length(x)))
  m <- lm(x ~ 1); ct <- coeftest(m, vcov = NeweyWest(m, lag = L, prewhite = FALSE)); c(mean=ct[1,1], t=ct[1,3], n=length(x)) }

## ══ F2 — 장기 무반전 (anchoring vs 수익률 외삽 분기점) ══════════════════════
setorder(SIG, Ticker, Date)
BASECOLS <- merge(E0[, .(Date, Ticker, mkt)], SIG[, .(Date, Ticker, Size, mret)], by = c("Date","Ticker"))
BASECOLS <- merge(BASECOLS, R, by = c("Date","Ticker"))
BASECOLS[, logsize := log(pmax(Size, 1))]

mk_dum <- function(dt, col, prefix) {
  dt[, pct := { v <- get(col); n <- sum(is.finite(v))
                fifelse(is.finite(v), (frank(v, ties.method="average", na.last="keep")-0.5)/n, NA_real_) }, by = .(Date, mkt)]
  dt[, (paste0(prefix,"H")) := as.integer(is.finite(pct) & pct >= 0.7)]
  dt[, (paste0(prefix,"L")) := as.integer(is.finite(pct) & pct <= 0.3)]
  dt[, pct := NULL]; invisible(dt) }

f2_run <- function(k) {
  Ls <- k:(k+11L)
  SL <- SIG[, .(Date, Ticker)]
  for (L in Ls) { SL[, (paste0("fh_",L)) := SIG[, shift(fh252, L), by = Ticker]$V1 ]
                  SL[, (paste0("jt_",L)) := SIG[, shift(jt6,   L), by = Ticker]$V1 ]
                  SL[, (paste0("in_",L)) := SIG[, shift(ind6,  L), by = Ticker]$V1 ] }
  B <- merge(BASECOLS, SL, by = c("Date","Ticker"))
  co <- rbindlist(lapply(Ls, function(L) {
    D <- B[, c("Date","Ticker","mkt","mret","logsize","Ret_1m",
               paste0("fh_",L), paste0("jt_",L), paste0("in_",L)), with = FALSE]
    setnames(D, c(paste0("fh_",L), paste0("jt_",L), paste0("in_",L)), c("FH","JT","IND"))
    D <- D[is.finite(mret) & is.finite(logsize) & is.finite(Ret_1m) & is.finite(FH) & is.finite(JT) & is.finite(IND)]
    if (!nrow(D)) return(NULL)
    mk_dum(D,"JT","J"); mk_dum(D,"IND","M"); mk_dum(D,"FH","FH")
    out <- D[, { if (.N < 40L) NULL else as.list(coef(lm(Ret_1m ~ mret + logsize + JH + JL + MH + ML + FHH + FHL, data=.SD))) }, by = Date]
    if (!nrow(out)) return(NULL); out[, L := L][] }), fill = TRUE)
  if (!nrow(co)) return(NULL)
  vars <- setdiff(names(co), c("Date","L"))
  avg <- co[, lapply(.SD, mean, na.rm=TRUE), by = Date, .SDcols = vars][order(Date)]
  g <- function(v) { z <- nw(avg[[v]]); list(mean_monthly = unname(z["mean"]), mean_ann_pct = 100*12*unname(z["mean"]),
                                             nw_t = unname(z["t"]), n = unname(z["n"])) }
  sp_fh <- nw(avg$FHH - avg$FHL); sp_jt <- nw(avg$JH - avg$JL); sp_in <- nw(avg$MH - avg$ML)
  list(gap_k = k, j_range = c(k+1L, k+12L), n_months = nrow(avg),
       FHH = g("FHH"), FHL = g("FHL"), JH = g("JH"), JL = g("JL"), MH = g("MH"), ML = g("ML"),
       fh_spread = list(mean_monthly = unname(sp_fh["mean"]), nw_t = unname(sp_fh["t"])),
       jt_spread = list(mean_monthly = unname(sp_jt["mean"]), nw_t = unname(sp_jt["t"])),
       ind_spread = list(mean_monthly = unname(sp_in["mean"]), nw_t = unname(sp_in["t"]))) }

F2 <- lapply(c(12L,24L,36L,48L), f2_run); names(F2) <- paste0("gap_", c(12,24,36,48))
cat("\n===== F2 — 장기 무반전 (GH2004 Table VI 사양) =====\n")
cat(sprintf("%-8s %14s %14s %14s %14s %14s %14s\n","gap","FHH","FHL","JH","JL","MH","ML"))
for (nm in names(F2)) { x <- F2[[nm]]; if (is.null(x)) next
  f <- function(a) sprintf("%+6.3f(%+5.2f)", 100*a$mean_monthly, a$nw_t)
  cat(sprintf("%-8s %14s %14s %14s %14s %14s %14s  n=%d\n", nm, f(x$FHH), f(x$FHL), f(x$JH), f(x$JL), f(x$MH), f(x$ML), x$n_months)) }
cat("GH2004 미국 실측(k=12): JT winner -0.09 (t -2.63) 유의 반전 / 52wh winner,loser 전 gap 비유의(무반전)\n")

## ══ F3 — 신고가 부근 개인 순매수 부호 ═══════════════════════════════════════
IW <- as.data.table(arrow::read_parquet(".cache/investor_stock/investor_wide.parquet"))
IW[, Date := as.Date(Date)]
IW <- IW[Date >= as.Date("2005-01-01") & Ticker %in% unique(E0$Ticker)]
IW[, ym := format(Date, "%Y-%m")]
FLOW <- IW[, .(ind_net = sum(Individual, na.rm=TRUE), inst_net = sum(Institutional, na.rm=TRUE),
               frn_net = sum(Foreign, na.rm=TRUE), nd = .N), by = .(Ticker, ym)]
rm(IW); gc(verbose = FALSE)
data_end <- max(FLOW$ym)
ym_map <- data.table(ym = format(ME, "%Y-%m"), Date = ME)
FL <- merge(FLOW, ym_map, by = "ym")[, ym := NULL]
X <- merge(E0[, .(Date, Ticker, mkt, fh252, Size)], FL, by = c("Date","Ticker"))
X <- X[is.finite(fh252) & is.finite(Size) & Size > 0]
X[, `:=`(ind_scaled = ind_net/Size, inst_scaled = inst_net/Size, frn_scaled = frn_net/Size)]
X[, pct := (frank(fh252, ties.method="average")-0.5)/.N, by = .(Date, mkt)]
X[, coh := fifelse(pct >= 0.7, "H", fifelse(pct <= 0.3, "L", "M"))]
f3 <- function(col) {
  m <- X[, .(v = mean(get(col), na.rm=TRUE), n = .N), by = .(Date, coh)]
  w <- dcast(m[n >= 5L], Date ~ coh, value.var = "v")
  w <- w[is.finite(H) & is.finite(L)]
  zH <- nw(w$H); zL <- nw(w$L); zD <- nw(w$H - w$L)
  list(variable = col, n_months = nrow(w),
       top30_mean = unname(zH["mean"]), top30_nw_t = unname(zH["t"]),
       bot30_mean = unname(zL["mean"]), bot30_nw_t = unname(zL["t"]),
       HminusL_mean = unname(zD["mean"]), HminusL_nw_t = unname(zD["t"])) }
F3 <- lapply(c("ind_scaled","inst_scaled","frn_scaled"), f3)
names(F3) <- c("individual","institutional","foreign")
cat("\n===== F3 — 근접도 코호트별 월간 순매수 / 시가총액 =====\n")
for (nm in names(F3)) { x <- F3[[nm]]
  cat(sprintf("%-14s top30 %+9.5f (t %+6.3f) | bot30 %+9.5f (t %+6.3f) | H-L %+9.5f (t %+6.3f) n=%d\n",
              nm, x$top30_mean, x$top30_nw_t, x$bot30_mean, x$bot30_nw_t, x$HminusL_mean, x$HminusL_nw_t, x$n_months)) }

## 단면 회귀판 (규모/유동성 통제 후 개인 순매수 ~ 근접도)
rz <- function(v) { n <- sum(is.finite(v)); q <- (frank(v, ties.method="average", na.last="keep")-0.5)/n
  qnorm(pmin(pmax(q, 1e-4), 1-1e-4)) }
X[, `:=`(z_fh = rz(fh252), z_size = rz(log(pmax(Size,1)))), by = .(Date, mkt)]
co3 <- X[is.finite(ind_scaled) & is.finite(z_fh) & is.finite(z_size),
         { if (.N < 40L) NULL else as.list(coef(lm(ind_scaled ~ z_fh + z_size, data=.SD))) }, by = Date]
z3 <- nw(co3$z_fh)
F3_reg <- list(spec = "ind_net/Size ~ z(근접도) + z(log Size), 시장-내 랭킹, 월별 단면 -> NW lag-3",
               lambda = unname(z3["mean"]), nw_t = unname(z3["t"]), n_months = unname(z3["n"]))
cat(sprintf("F3 회귀판: lambda(z_근접도) = %+.6f  NW-t = %+.3f  n=%d\n", F3_reg$lambda, F3_reg$nw_t, F3_reg$n_months))

res <- list(
  meta = list(wt_id = "WT-R20260829_007", tests = c("F2","F3"), tier = "side_observation",
              envelope_applicability = "NOT_APPLICABLE", metric_type = "cross_sectional_regression",
              note = "부수 관측은 성과와 독립적으로 실패할 수 있어야 기전 청구를 진다. 성과 판정 아님."),
  F2_long_horizon_no_reversal = list(
    spec = "GH2004 Table VI (6,k,12): 각 보유월 t 에 대해 j = k+1..k+12 시점 변수로 단면회귀 후 j 평균 -> 월별 계수 -> NW lag-3",
    reject_if = "근접도 winner 더미(FHH)가 k=12~48 에서 유의 음(반전)이면 anchoring 이 아니라 과거수익률 외삽의 재파라미터화 -> anchoring 라벨 철회",
    paper_reference = "GH2004: JT winner k=12 계수 -0.09 (t -2.63) 유의 반전 / MG winner -0.11 (t -2.42) / 52주 신고가 winner·loser 전 gap 비유의(무반전)",
    results = F2),
  F3_individual_flow_near_high = list(
    spec = "월간 투자자 순매수(원) / 시가총액. 근접도 시장-내 상위 30%(H) vs 하위 30%(L) 코호트 평균의 월별 시계열 -> NW lag-3. 회귀판 병기.",
    reject_if = "근접도 상위 코호트에서 개인 순매수가 유의 양(+)이면(추격매수) GH2004 가 서술한 주체·마찰 구조가 KR 에 없는 것 -> mechanism.agent 서술 철회",
    paper_reference = "Grinblatt & Keloharju (2001) — 투자자는 역사적 고가 부근 종목을 (보유·매수보다) 매도할 확률이 유의하게 높다 (GH2004 가 주체 증거로 인용)",
    data_caveat = "A6/A7 수동 QuantiWise export 계열 · 실효 지연 ~22일(비정기) · 데이터 종점 확인값 아래 기재. 미래참조는 t-1 집계로 막히나 스테일은 못 막는다. 기전 진단 전용이며 신호 경로에 미진입.",
    flow_data_end_ym = data_end,
    cohort_means = F3, regression_form = F3_reg))
write_json(res, file.path(OUT, "s6_side.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(F2 = F2, F3 = F3, F3_reg = F3_reg), file.path(OUT, "s6_objects.rds"))
cat("\n[S6] done\n")
