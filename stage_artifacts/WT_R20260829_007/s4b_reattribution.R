# S4b — 선행 C 등급 런의 FM Score NW-t +3.199 재귀속 (정의 x 사양 x 표본 분해)
#  선행 엔진(02_Infrastructure/alpha_search/fe_mom52w.R) 실측 판독:
#    .hi52 = frollapply(shift(Close,1), 252, max)   <- **당일 종가를 최고가 창에서 제외**
#    .Score = Close/.hi52 - 1                        <- 신고가 경신일이면 양(+)  => 상한 없음
#  GH2004 원문 FH = P_{t-1}/high_{t-1} 이고 high 는 당월 포함 12개월 최고가 => FH <= 1.
#  즉 선행 런이 잰 변수는 GH2004 의 근접도가 아니라 '직전 고점 대비 초과' 다.
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(arrow); library(sandwich); library(lmtest); library(RcppRoll)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
O2 <- readRDS(file.path(OUT, "s2_objects.rds")); O4 <- readRDS(file.path(OUT, "s4_objects.rds"))
E0 <- O2$E0; R <- O2$R; P <- O4$P; SIG <- O2$SIG
ME <- sort(unique(E0$Date))

## ── 선행 정의 재구성: hi52_excl_today ───────────────────────────────────────
RAW <- as.data.table(arrow::read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","K200","KQ150")))
RAW[, Date := as.Date(Date)]
ever <- unique(RAW[K200 == TRUE | KQ150 == TRUE, Ticker])
RAW <- RAW[Ticker %in% ever & Date >= as.Date("2000-01-01") & is.finite(Close) & Close > 0]
setorder(RAW, Ticker, Date)
RAW[, hi_incl := { n <- .N; if (n < 2L) NA_real_ else RcppRoll::roll_max(Close, n = min(252L, n), align="right", fill=NA) }, by = Ticker]
RAW[, hi_excl := shift(hi_incl, 1L), by = Ticker]
RAW[, prior_score := fifelse(is.finite(hi_excl) & hi_excl > 0, Close/hi_excl - 1, NA_real_)]
PS <- RAW[Date %in% ME, .(Date, Ticker, prior_score, fh_incl = fifelse(is.finite(hi_incl) & hi_incl>0, Close/hi_incl, NA_real_))]
rm(RAW); gc(verbose = FALSE)

Q <- merge(P, PS, by = c("Date","Ticker"), all.x = TRUE)
setorder(SIG, Ticker, Date)
SIG[, m12 := { s <- rep(0, .N); c0 <- rep(0L, .N)
               for (k in 0:11) { xx <- shift(mret, k); s <- s + fifelse(is.finite(xx), log1p(xx), 0); c0 <- c0 + as.integer(is.finite(xx)) }
               fifelse(c0 >= 10L, expm1(s), NA_real_) }, by = Ticker]
Q <- merge(Q, SIG[, .(Date, Ticker, m12)], by = c("Date","Ticker"), all.x = TRUE)
cat(sprintf("[S4b] Q %d rows / %d months | prior_score 가용 %.3f | max(prior_score)=%.3f · 양(+) 비율 %.3f\n",
            nrow(Q), uniqueN(Q$Date), mean(is.finite(Q$prior_score)),
            max(Q$prior_score, na.rm=TRUE), mean(Q$prior_score > 0, na.rm=TRUE)))
cat(sprintf("[S4b] 정의 대조: cor(prior_score, fh252) Spearman 월평균 = %.4f\n",
            Q[is.finite(prior_score) & is.finite(fh252), .(r = cor(prior_score, fh252, method="spearman")), by=Date][, mean(r)]))

## ── 선행 런의 NW 공식 (strategy_analyzer.R::.nw_tstat, L = floor(T^(1/3))) ──
nw_prior <- function(x) { x <- x[!is.na(x)]; T_n <- length(x); if (T_n < 5) return(NA_real_)
  xb <- mean(x); L <- max(1, floor(T_n^(1/3))); v <- var(x)
  for (j in seq_len(L)) v <- v + 2*(1 - j/(L+1))*cov(x[1:(T_n-j)], x[(j+1):T_n])
  xb/sqrt(max(v/T_n, 1e-20)) }
nw_lag3 <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }
zsd <- function(v) (v - mean(v, na.rm=TRUE))/max(sd(v, na.rm=TRUE), 1e-8)

## ── 재귀속 격자: 정의 2 x 사양 2 (표본은 본 라운드 적격집합으로 고정) ──────
run_prior_spec <- function(scorecol) {
  d <- Q[is.finite(get(scorecol)) & is.finite(Size) & Size > 0 & is.finite(m12) & is.finite(Ret_1m),
         .(Date, Ticker, S = get(scorecol), lnS = log(Size), M = m12, Ret_1m)]
  co <- d[, { if (.N < 30L) NULL else { m <- copy(.SD)
      m[, `:=`(Sz = zsd(S), Lz = zsd(lnS), Mz = zsd(M))]
      f <- tryCatch(lm(Ret_1m ~ Sz + Lz + Mz, data = m), error=function(e) NULL)
      if (is.null(f)) NULL else as.list(coef(f)) } }, by = Date]
  list(spec = "prior (strategy_analyzer.R): Ret ~ z(Score) + z(lnSize) + z(Ret_12m_noskip), NW L=floor(T^(1/3))",
       n_months = nrow(co),
       lambda_score = mean(co$Sz, na.rm=TRUE), t_score_priorNW = nw_prior(co$Sz), t_score_NWlag3 = nw_lag3(co$Sz),
       lambda_size = mean(co$Lz, na.rm=TRUE), t_size_priorNW = nw_prior(co$Lz),
       lambda_mom = mean(co$Mz, na.rm=TRUE), t_mom_priorNW = nw_prior(co$Mz)) }

grid <- list(
  prior_def_prior_spec = run_prior_spec("prior_score"),
  gh2004_def_prior_spec = run_prior_spec("fh252"))

cat("\n===== 재귀속 격자 (표본 = 본 라운드 적격집합 고정) =====\n")
for (nm in names(grid)) { x <- grid[[nm]]
  cat(sprintf("%-24s lambda=%+8.5f  t(선행NW)=%+7.3f  t(NW lag3)=%+7.3f  | size t=%+7.3f mom t=%+7.3f  n=%d\n",
              nm, x$lambda_score, x$t_score_priorNW, x$t_score_NWlag3, x$t_size_priorNW, x$t_mom_priorNW, x$n_months)) }
cat(sprintf("\n선행 런 보고치: lambda=+0.00494 t=+3.199 | Size t=-3.225 | Momentum t=-1.886 (n=254)\n"))

## ── 선행 정의를 본 라운드 통제 사다리에 태우면? ─────────────────────────────
rz <- function(v) { n <- sum(is.finite(v)); q <- (frank(v, ties.method="average", na.last="keep")-0.5)/n
  qnorm(pmin(pmax(q, 1e-4), 1-1e-4)) }
CTRLS <- list(
  T0_none = character(0),
  T1_mom_size = c("jt6","logsize"),
  T2_plus_ind = c("jt6","logsize","ind6"),
  T3_plus_vol_L = c("jt6","logsize","ind6","rv63","L01_Amihud","L09_Amihud_20d","L11_Kyle_Lambda"),
  T4_full = c("jt6","logsize","ind6","rv63","L01_Amihud","L09_Amihud_20d","L11_Kyle_Lambda","D35_RealVol_63d","lo52"))
allc <- unique(c("prior_score", unlist(CTRLS)))
D <- copy(Q); for (cc in allc) D[, (paste0("z_",cc)) := rz(get(cc)), by = .(Date, mkt)]
prior_ladder <- lapply(names(CTRLS), function(nm) {
  vs <- c("z_prior_score", if (length(CTRLS[[nm]])) paste0("z_", CTRLS[[nm]]) else NULL)
  d <- D[, c("Date","Ret_1m", vs), with=FALSE]; for (v in vs) d <- d[is.finite(get(v))]
  d <- d[is.finite(Ret_1m)]
  frm <- as.formula(paste("Ret_1m ~", paste(vs, collapse=" + ")))
  co <- d[, { if (.N < 40L) NULL else as.list(coef(lm(frm, data=.SD))) }, by=Date]
  list(step = nm, controls = CTRLS[[nm]], n_months = nrow(co),
       lambda = mean(co$z_prior_score, na.rm=TRUE), nw_t = nw_lag3(co$z_prior_score)) })
names(prior_ladder) <- names(CTRLS)
cat("\n===== 선행 정의(prior_score) 를 본 라운드 통제 사다리에 태움 (시장-내 랭킹) =====\n")
for (nm in names(prior_ladder)) { x <- prior_ladder[[nm]]
  cat(sprintf("  %-14s lambda=%+8.5f NW-t(lag3)=%+7.3f n=%d\n", nm, x$lambda, x$nw_t, x$n_months)) }

res <- list(
  meta = list(wt_id = "WT-R20260829_007", test_id = "F4b — 선행 런 재귀속",
              metric_type = "cross_sectional_regression",
              envelope_applicability = "NOT_APPLICABLE"),
  prior_run_reported = list(strategy_id = "STR_AS_20260612_132740_321992",
    fmb_score_lambda = 0.00494, fmb_score_t_nw = 3.199, fmb_size_t_nw = -3.225,
    fmb_momentum_t_nw = -1.886, n_months = 254,
    engine = "02_Infrastructure/alpha_search/fe_mom52w.R",
    analyzer = "02_Infrastructure/strategy_analyzer.R L170-250"),
  definition_discrepancy = list(
    prior_definition = "Score = Close_t / max(Close over [t-252, t-1]) - 1  (당일 종가를 최고가 창에서 **제외**) -> 신고가 경신일에 양(+), 상한 없음",
    gh2004_definition = "FH = P_{t-1} / high_{t-1}, high = **당월 포함** 12개월 최고가 -> FH <= 1",
    consequence = "선행 런이 잰 변수는 '준거점 대비 위치'가 아니라 '직전 고점 대비 초과폭'이다. 두 변수는 신고가 경신 코호트에서 갈린다.",
    prior_score_positive_share = mean(Q$prior_score > 0, na.rm=TRUE),
    spearman_prior_vs_gh2004 = Q[is.finite(prior_score) & is.finite(fh252), .(r = cor(prior_score, fh252, method="spearman")), by=Date][, mean(r)]),
  reattribution_grid = grid,
  prior_definition_control_ladder = prior_ladder,
  reading = "정의(선행 vs GH2004) x 사양(선행 FM vs 본 라운드 사다리)의 4칸을 같은 표본 위에서 재고, 어느 축이 t 3.199 를 만들었는지 확정한다.")
write_json(res, file.path(OUT, "s4b_reattribution.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(Q = Q, grid = grid, prior_ladder = prior_ladder), file.path(OUT, "s4b_objects.rds"))
cat("\n[S4b] done\n")
