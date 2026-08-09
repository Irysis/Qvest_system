## ============================================================================
## FQ-165 P1 — 기준선(incumbent book) 재현 + production parity 검증 + 잡음 스케일 추정
##
## 기준선 권위(§7b): 05_Production 현행 코드 경로에서 파생한 신호만.
##   · score 원천 = stage_artifacts/WT_D20260425_010/alpha_scores.parquet
##       (2-4 forward_weights_R05_noLayer4_M4gAE.R:38 및 2-3 계보가 읽는 그 파일)
##   · 가중 = strategy_tilt_weights.R::linear_tilt_qd + tophi φ=3 + CRISIS ub 0.10
##       (admit·북 기록·incumbent_book_ir 1.416 을 측정한 그 규약. z-선형 배포판 아님)
##   · 선별 = top-20 by score_eff → 유동성(20d ADV ≥ 2e8) 교집합  (run_all.R 정본 순서)
##   · overlay = 캐리어 실측 invested_t (M4∩AE gate × β_R05) — arm 불변(paired)
##   · 비용 = 15bps × Σ|Δ(invested·w)|  (v2.4 delta 사상, 현금 leg 포함)
##   · 벤치 = IKS200 vintage pin benchmark_pinned_20260702.parquet
## parity 대조 = judge 확정값(SR_geo 1.898 / CAGR 0.4526 / MDD 0.2329) + book_state IR 1.416
##
## 잡음 스케일(P1-C): **실제 M26 을 보기 전에** 개입 규모의 노이즈를 추정한다 —
##   M26 점수를 월별 무작위 순열한 placebo 를 같은 형태로 결합해 paired 차이의 sd 를 측정.
##   이 sd 가 사전등록 검정력 바의 **외부 기준 계열**이 된다(바가 t 검정 재진술로 퇴화하는 것 방지).
## ============================================================================
suppressMessages({library(data.table); library(arrow); library(jsonlite)
                  library(PerformanceAnalytics); library(xts)})
options(scipen = 999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/FQ165_m26_book_marginal"
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")
source("02_Infrastructure/contracts/required_effect_size.R")

P <- readRDS(file.path(OUT, "p0_inputs.rds"))
ap <- P$ap; m26 <- P$m26; raw <- P$raw; bm <- P$bm; ovl <- P$ovl
TOPN <- 20L; MINN <- 15L; LIQ <- 2e8; LAM <- 1.5; UB <- 0.20; UBCR <- 0.10; BPS <- 0.0015

ym <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
ap[, ymi := ym(Date)]; m26[, ymi := ym(Date)]
raw[, TV := Close*Vol]; setkey(raw, Date, Ticker)
bm_x <- xts(bm$BM_Ret, order.by = bm$Date)

## ── 월별 전처리 (arm 무관 공통) ───────────────────────────────────────────────
sig_dates <- sort(unique(ap[!is.na(score_eff), Date]))
MO <- list()
for (i in seq_len(length(sig_dates)-1L)) {
  sd_i <- sig_dates[i]; nx <- sig_dates[i+1L]
  if (!nrow(ovl[decision_date == sd_i])) next          # overlay 실측 있는 달만 (paired)
  panel <- ap[Date == sd_i & !is.na(score_eff)]; if (!nrow(panel)) next
  start_d <- min(raw[Date >= sd_i]$Date); if (!length(start_d) || is.na(start_d)) next
  end_d <- { z <- min(raw[Date >= nx]$Date); if (!length(z) || is.na(z)) max(raw$Date) else z }
  ## 유동성: 결정일 **이전** 20영업일 ADV (C10 — 당일 거래량 미사용)
  liqd <- raw[Date >= (start_d-30L) & Date < start_d, .(ADV = mean(TV, na.rm=TRUE)), by = Ticker]
  elig <- liqd[ADV >= LIQ, Ticker]
  sret <- raw[Date > start_d & Date <= end_d, .(rf = prod(1+Ret, na.rm=TRUE)-1), by = Ticker]
  seg  <- bm_x[index(bm_x) > start_d & index(bm_x) <= end_d]
  bmr  <- if (nrow(seg) > 0) as.numeric(Return.cumulative(seg)) else NA_real_
  ## ★M26: PIT 정렬 = 직전 월말 신호 (base 결정월 ymi = M26 signal ymi + 1). P0d 실측 근거.
  mrow <- m26[ymi == ym(sd_i) - 1L & is.finite(M26_Revenue_Mom), .(Ticker, M26 = M26_Revenue_Mom)]
  MO[[length(MO)+1L]] <- list(dd = sd_i, ed = end_d, regime = panel$regime_state[1L],
    score = setNames(panel$score_eff, panel$Ticker), elig = elig,
    ret = setNames(sret$rf, sret$Ticker), bm = bmr,
    m26 = setNames(mrow$M26, mrow$Ticker), inv = ovl[decision_date == sd_i, invested][1])
}
cat(sprintf("[P1-A] 월 %d개 (%s ~ %s) · 벤치 결측 %d · M26 커버 중앙 %.3f\n",
  length(MO), MO[[1]]$dd, MO[[length(MO)]]$dd, sum(!is.finite(sapply(MO, `[[`, "bm"))),
  median(sapply(MO, function(m) { s <- names(m$score); mean(s %in% names(m$m26)) }))))

## ── 가중 규약 (정본 verbatim) ────────────────────────────────────────────────
.apply_tophi <- function(w_tilt, w_prev, phi, ub) {
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev)); wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp); if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi/(1+phi)
  normalize_long_only(blend*wp + (1-blend)*w_tilt, lb = 0, ub = ub, target_sum = 1)
}
canon_w <- function(a, w_prev, ub) {              # a = named score vector (선별 완료분)
  wt <- linear_tilt_qd(a, lambda = LAM, lb = 0, ub = ub); names(wt) <- names(a)
  .apply_tophi(wt, w_prev, 3, ub)
}
dnot <- function(cur, prv) { u <- union(names(cur), names(prv))
  x <- setNames(rep(0,length(u)),u); x[names(cur)] <- cur
  y <- setNames(rep(0,length(u)),u); y[names(prv)] <- prv; sum(abs(x-y)) }

## select_fn(m) -> named score vector of chosen names (길이 ≤ TOPN)
## wgt_fn(a, w_prev, ub, m) -> named weight vector
run_arm <- function(select_fn, wgt_fn = function(a,wp,ub,m) canon_w(a,wp,ub)) {
  n <- length(MO); wp <- NULL; npv <- NULL
  gb <- nb <- go <- no <- tno <- numeric(n); nm <- integer(n)
  for (k in seq_len(n)) {
    m <- MO[[k]]; ub <- if (identical(m$regime,"CRISIS")) UBCR else UB
    a <- select_fn(m); if (!length(a)) { a <- m$score[order(-m$score)][seq_len(min(TOPN,length(m$score)))] }
    w <- wgt_fn(a, wp, ub, m)
    rv <- m$ret[names(w)]; rv[is.na(rv)] <- 0
    gb[k] <- sum(w*rv); nm[k] <- length(w)
    nb[k] <- gb[k] - BPS*(if (is.null(wp)) sum(abs(w)) else dnot(w, wp))
    nw <- w * m$inv
    go[k] <- gb[k] * m$inv
    tno[k] <- (if (is.null(npv)) sum(abs(nw)) else dnot(nw, npv))
    no[k]  <- go[k] - BPS*tno[k]
    wp <- w; npv <- nw
  }
  list(ret_net = no, ret_gross = go, bare_net = nb, turn = tno, n_names = nm)
}

eval_dates <- as.Date(sapply(MO, function(m) as.character(m$ed)))
bmv <- sapply(MO, `[[`, "bm"); bmv[!is.finite(bmv)] <- 0

nw_t <- function(x, L=3){ x <- x[is.finite(x)]; n <- length(x)
  m <- mean(x); e <- x-m; s <- sum(e^2)/n
  for (l in 1:L){ ga <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*(1-l/(L+1))*ga }
  m/sqrt(s/n) }

summarize <- function(a, label) {
  x <- xts(a$ret_net, order.by = eval_dates)
  tab <- table.AnnualizedReturns(x, scale = 12, Rf = 0)
  act <- a$ret_net - bmv
  data.table(arm = label,
    SR_geo = as.numeric(tab[3,1]), CAGR = as.numeric(tab[1,1]),
    MDD = as.numeric(maxDrawdown(x)),
    Calmar = as.numeric(tab[1,1]) / as.numeric(maxDrawdown(x)),
    IR_net_active_recon_v1 = mean(act)/sd(act)*sqrt(12),
    active_mean_ann = mean(act)*12, TE = sd(act)*sqrt(12),
    turnover_ann = mean(a$turn)*12, n_names_mean = mean(a$n_names))
}

## ── P1-B. 기준선 재현 + parity ────────────────────────────────────────────────
sel_base <- function(m) {
  s <- m$score[order(-m$score)]
  N <- min(TOPN, length(s)); if (N < MINN && length(s) >= MINN) N <- MINN
  a <- s[seq_len(N)]
  tk <- intersect(names(a), m$elig); if (length(tk) < 5L) tk <- names(a)
  a[tk]
}
BASE <- run_arm(sel_base)
sb <- summarize(BASE, "BASE_incumbent_canonical")
cat("\n===== [P1-B] 기준선 재현 =====\n"); print(sb)
ref <- list(SR_geo = 1.898, CAGR = 0.4526, MDD = 0.2329, IR = 1.416)
par_tbl <- data.table(
  metric = c("SR_geo","CAGR","MDD","IR_net_active_recon_v1"),
  reproduced = c(sb$SR_geo, sb$CAGR, sb$MDD, sb$IR_net_active_recon_v1),
  authority  = c(ref$SR_geo, ref$CAGR, ref$MDD, ref$IR),
  source = c("judge WT-D20260702_002","judge","judge","book_state.incumbent_book_ir"))
par_tbl[, abs_diff := abs(reproduced - authority)]
par_tbl[, tol := c(0.06, 0.02, 0.02, 0.10)]
par_tbl[, pass := abs_diff <= tol]
cat("\n===== [P1-B2] production parity 대조 =====\n"); print(par_tbl)
PARITY <- all(par_tbl$pass)
cat(sprintf("\n[production_parity_verified] = %s\n", PARITY))

## ── P1-C. placebo 잡음 스케일 (★실제 M26 결합 결과를 보기 전) ────────────────
## M26 을 월별 무작위 순열 → 같은 형태(z-blend w=0.30)로 결합. 개입 규모의 노이즈 sd 측정.
zcs <- function(v) { s <- sd(v, na.rm=TRUE); if (!is.finite(s) || s < 1e-12) return(rep(0, length(v)))
  (v - mean(v, na.rm=TRUE))/s }
make_blend_selector <- function(w_m26, m26_get) function(m) {
  sc <- m$score; tk <- intersect(names(sc), m$elig); if (length(tk) < 5L) tk <- names(sc)
  sc <- sc[tk]
  mv <- m26_get(m)[tk]; mv_z <- zcs(mv); mv_z[!is.finite(mv_z)] <- 0
  blend <- zcs(sc) + w_m26 * mv_z; names(blend) <- tk
  o <- order(-blend); N <- min(TOPN, length(o))
  ## 비중은 정본 tilt 를 **blend 점수** 위에 적용 (rerank 형태 — 가중 규칙 불변)
  blend[o][seq_len(N)]
}
set.seed(20260809)
plc <- vapply(1:12, function(s) {
  sel <- make_blend_selector(0.30, function(m) {
    v <- m$m26; if (!length(v)) return(setNames(numeric(0), character(0)))
    setNames(sample(unname(v)), names(v)) })
  A <- run_arm(sel)
  d <- A$ret_net - BASE$ret_net
  c(sd = sd(d), mean = mean(d))
}, numeric(2))
PLACEBO_SD <- median(plc["sd", ])
cat(sprintf("\n[P1-C] placebo(M26 월별 순열) 12 draw · paired 차이 sd 중앙 %.5f (범위 %.5f~%.5f) · 평균효과 중앙 %+.5f\n",
            PLACEBO_SD, min(plc["sd",]), max(plc["sd",]), median(plc["mean",])))

## ── P1-D. 검정력 바 (착수 전 의무) ───────────────────────────────────────────
n_m <- length(MO)
bar_ext <- required_effect(n = n_m, t_threshold = 2.0, sd_monthly = PLACEBO_SD, design = "full")
bar_25e <- required_effect(n = n_m, t_threshold = 2.0, sd_monthly = SPREAD_SD_MONTHLY_25EW, design = "full")
cat(sprintf("\n[P1-D] 검정력 바 (n=%d, paired 차이)\n", n_m))
cat(sprintf("   외부기준 A: placebo sd %.5f → 필요 월 %+.5f = 연 %+.3f%%\n",
            PLACEBO_SD, bar_ext$required_monthly, bar_ext$required_annual*100))
cat(sprintf("   외부기준 B: 25EW 스프레드 sd %.4f → 필요 월 %+.5f = 연 %+.3f%%  (개입 규모 대비 과대 — 참조만)\n",
            SPREAD_SD_MONTHLY_25EW, bar_25e$required_monthly, bar_25e$required_annual*100))
## ΔIR 게이트 0.05 의 표집 SE (블록 부트스트랩, base 계열)
set.seed(11)
bl <- 12L; nb_ <- floor(n_m/bl)
ir_boot <- replicate(2000, {
  st <- sample(seq_len(n_m-bl+1), nb_, replace=TRUE)
  idx <- unlist(lapply(st, function(s) s:(s+bl-1)))
  a <- BASE$ret_net[idx] - bmv[idx]; mean(a)/sd(a)*sqrt(12) })
cat(sprintf("   incumbent IR 블록부트(block=12, 2000회): 중앙 %.3f · sd %.3f · [5%%,95%%] [%.3f, %.3f]\n",
            median(ir_boot), sd(ir_boot), quantile(ir_boot,.05), quantile(ir_boot,.95)))
cat("   ⇒ ΔIR 0.05 는 IR 자체의 표집 sd 보다 훨씬 작다 — ΔIR 단독은 확증이 아니라 **문턱**이고,\n")
cat("     유의성 판정은 paired 차이 검정이 담당한다(WT-D20260809_001 C-2 교훈).\n")

saveRDS(list(MO=MO, BASE=BASE, base_summary=sb, parity=par_tbl, parity_pass=PARITY,
             eval_dates=eval_dates, bmv=bmv, placebo_sd=PLACEBO_SD, placebo=plc,
             bar_ext=bar_ext, bar_25e=bar_25e, ir_boot=ir_boot, n_months=n_m),
        file.path(OUT, "p1_base.rds"))
fwrite(par_tbl, file.path(OUT, "p1_parity.csv"))
cat("\n[saved] p1_base.rds / p1_parity.csv\n")
