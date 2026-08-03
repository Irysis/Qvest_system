# =============================================================================
# build_composites.R — WT-D20260803_007 (FQ-135) Step A+B
#   A: walk-forward step 별 arm 멤버십 확정 (IS-only — OOS 수익 절대 미투입)
#   B: 월 루프 1회에서 전체 z 로 composite score 패널 산출 (top-80 절단 없음)
#
#   사전등록: stage_artifacts/WT_D20260803_007/preregistration.json (측정 전 고정)
#   PIT: load_month_factors(d) 경유(C15) → Z_Score_Aligned 그대로(C13). 유동성/멤버십은
#        canonical_screen_bt 의 liq_dt(t-1 ADV, C10)가 담당.
#
# 실행: Rscript stage_artifacts/WT_D20260803_007/build_composites.R
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
SRC5 <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[wt007A] ", fmt, "\n"), ...))

source("02_Infrastructure/contracts/backtest_result_contract.R")   # .nw_t_mean
nw_t <- function(x, lag = 3L, min_obs = 30L) {
  xv <- x[is.finite(x)]; if (length(xv) < min_obs) return(NA_real_)
  .nw_t_mean(xv, lag = lag)
}

PR5  <- readRDS(file.path(SRC5, "persistence_results.rds"))
META <- readRDS(file.path(SRC5, "pool_meta.rds"))
A    <- PR5$A                       # 287월 x 285 factor : canonical net-active
POOL <- PR5$pool
DATES <- as.Date(rownames(A))
NM <- nrow(A)
say("A: %d월 x %d factor (%s ~ %s)", NM, ncol(A), DATES[1], DATES[NM])
stopifnot(identical(colnames(A), POOL))

# ── 사전등록 상수 ───────────────────────────────────────────────────────────
IS0 <- 120L; OOSB <- 24L; W_ERA <- 36L; ERA_MIN <- 30L
K_PRIM <- 20L; K_SENS <- c(10L, 40L); N_RAND <- 200L
COV_MIN_MEMBER <- 0.60
SEED <- 20260803L
SS_IS_END <- 191L                   # secondary single split

# ── Step A-1 : 창 t 계산기 ──────────────────────────────────────────────────
era_bounds <- function(is_end, W = W_ERA) {
  ne <- is_end %/% W
  if (ne < 2L) return(list())
  lapply(seq_len(ne), function(k) c(is_end - k * W + 1L, is_end - (k - 1L) * W))
}
era_t_mat <- function(is_end) {
  bnds <- era_bounds(is_end)
  if (!length(bnds)) return(NULL)
  do.call(rbind, lapply(bnds, function(b)
    apply(A[b[1]:b[2], , drop = FALSE], 2, nw_t, min_obs = ERA_MIN)))
}
level_t <- function(i0, i1, min_obs = 30L)
  apply(A[i0:i1, , drop = FALSE], 2, nw_t, min_obs = min_obs)

metrics_at <- function(is_end) {
  TT <- era_t_mat(is_end)
  stopifnot(!is.null(TT))
  TTrel <- TT - rowMeans(TT, na.rm = TRUE)
  wmin <- function(M) apply(M, 2, function(v) if (all(is.na(v))) NA_real_ else min(v, na.rm = TRUE))
  rel <- wmin(TTrel); abs_ <- wmin(TT)
  lvl <- level_t(1L, is_end)
  ok <- is.finite(rel) & is.finite(lvl)
  perp <- rep(NA_real_, length(rel)); names(perp) <- names(rel)
  if (sum(ok) > 10L) perp[ok] <- residuals(lm(rel[ok] ~ lvl[ok]))
  # 진단축 (선택 아님)
  sgn <- apply(TT, 2, function(v) { v <- v[is.finite(v)]
    if (length(v) < 2L) NA_real_ else max(mean(v > 0), mean(v < 0)) })
  sdv <- apply(TT, 2, sd, na.rm = TRUE)
  list(rel = rel, abs = abs_, perp = perp, level = lvl,
       sign_rate = sgn, era_sd = sdv, n_era = nrow(TT), era_t = TT)
}
pick <- function(v, K, top = TRUE) {
  v <- v[is.finite(v)]
  o <- order(v, names(v), decreasing = top)          # 동점 tie-break: 이름 (성과 무관)
  names(v)[o[seq_len(min(K, length(v)))]]
}

# ── Step A-2 : walk-forward step 정의 ───────────────────────────────────────
steps <- list(); s <- IS0
while (s < NM) { e <- min(s + OOSB, NM); steps[[length(steps)+1L]] <- list(is_end = s, oos = (s+1L):e); s <- e }
NS <- length(steps)
say("walk-forward step %d | OOS 총 %d월", NS, sum(vapply(steps, function(x) length(x$oos), 1L)))

MET <- lapply(steps, function(st) metrics_at(st$is_end))
for (i in seq_len(NS)) say("step%d IS끝=%s era=%d | cor(rel,level)=%.3f cor(abs,level)=%.3f cor(perp,level)=%.3f",
  i, DATES[steps[[i]]$is_end], MET[[i]]$n_era,
  cor(MET[[i]]$rel, MET[[i]]$level, use = "pairwise.complete.obs"),
  cor(MET[[i]]$abs, MET[[i]]$level, use = "pairwise.complete.obs"),
  cor(MET[[i]]$perp, MET[[i]]$level, use = "pairwise.complete.obs"))

# ── Step A-3 : arm 별 (step → 멤버) ─────────────────────────────────────────
set.seed(SEED)
ARM <- list()
addarm <- function(id, memb_by_step, oos_by_step, kind) {
  ARM[[id]] <<- list(id = id, kind = kind, members = memb_by_step, oos = oos_by_step)
}
oos_all <- lapply(steps, function(st) st$oos)

addarm("A_REL_TOP",  lapply(MET, function(m) pick(m$rel,  K_PRIM, TRUE)),  oos_all, "treatment")
addarm("A_REL_BOT",  lapply(MET, function(m) pick(m$rel,  K_PRIM, FALSE)), oos_all, "reverse_control")
addarm("A_ABS_TOP",  lapply(MET, function(m) pick(m$abs,  K_PRIM, TRUE)),  oos_all, "secondary")
addarm("A_PERP_TOP", lapply(MET, function(m) pick(m$perp, K_PRIM, TRUE)),  oos_all, "secondary")
for (K in K_SENS) {
  addarm(sprintf("A_REL_TOP_K%d", K), lapply(MET, function(m) pick(m$rel, K, TRUE)),  oos_all, "sensitivity")
  addarm(sprintf("A_REL_BOT_K%d", K), lapply(MET, function(m) pick(m$rel, K, FALSE)), oos_all, "sensitivity")
}
addarm("SINGLE_BEST", lapply(MET, function(m) pick(m$level, 1L, TRUE)), oos_all, "control_single")
addarm("POOL_EW",     lapply(seq_len(NS), function(i) POOL),            oos_all, "base_unselected")

# 위반 주입 1: 전기간(OOS 포함) 지표로 선정
MET_FULL <- metrics_at(NM)
addarm("LEAK_FULLSAMPLE", lapply(seq_len(NS), function(i) pick(MET_FULL$rel, K_PRIM, TRUE)),
       oos_all, "violation_injection")
# 위반 주입 2: OOS 블록 자체 PORT_t argmax (고전 look-ahead)
addarm("LEAK_ORACLE_OOS", lapply(steps, function(st) {
  v <- apply(A[st$oos, , drop = FALSE], 2, nw_t, min_obs = 20L); pick(v, K_PRIM, TRUE) }),
  oos_all, "violation_injection")

# 보조 단일분할 (IS 1..191 / OOS 192..287)
MET_SS <- metrics_at(SS_IS_END); ss_oos <- list((SS_IS_END + 1L):NM)
addarm("SS_A_REL_TOP",  list(pick(MET_SS$rel,   K_PRIM, TRUE)),  ss_oos, "single_split")
addarm("SS_A_REL_BOT",  list(pick(MET_SS$rel,   K_PRIM, FALSE)), ss_oos, "single_split")
addarm("SS_SINGLE_BEST",list(pick(MET_SS$level, 1L,     TRUE)),  ss_oos, "single_split")

MAIN_ARMS <- names(ARM)
# 무작위 귀무 200 draw (step 마다 재추첨 — A 와 동일한 재선택 리듬)
for (r in seq_len(N_RAND))
  addarm(sprintf("RAND_%03d", r), lapply(seq_len(NS), function(i) sample(POOL, K_PRIM)), oos_all, "random_null")
say("arm 총 %d (main %d + random %d)", length(ARM), length(MAIN_ARMS), N_RAND)
say("A_REL_TOP step1 멤버: %s", paste(head(ARM$A_REL_TOP$members[[1]], 6), collapse = ", "))
say("A_REL_BOT step1 멤버: %s", paste(head(ARM$A_REL_BOT$members[[1]], 6), collapse = ", "))
say("SINGLE_BEST step별: %s", paste(vapply(ARM$SINGLE_BEST$members, `[`, character(1), 1), collapse = " > "))

# ── Step A-4 : 월 → (arm, 멤버) 활성 맵 ─────────────────────────────────────
ACT <- vector("list", NM)
for (a in names(ARM)) for (i in seq_along(ARM[[a]]$oos)) {
  mem <- ARM[[a]]$members[[i]]
  for (j in ARM[[a]]$oos[[i]]) ACT[[j]] <- c(ACT[[j]], setNames(list(mem), a))
}
say("활성 맵: 월 %d 에서 arm 활성 (첫 활성월 %s)", sum(lengths(ACT) > 0), DATES[which(lengths(ACT) > 0)[1]])

# ── Step B : 월 루프 — 전체 z 에서 composite ────────────────────────────────
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
stopifnot(length(MEND) == uniqueN(format(MEND, "%Y-%m")))
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]; setkey(UNIV, Date, Ticker)

TOPK_RAND <- 80L                    # random arm 저장 절단 (main arm 은 전량 저장)
set.seed(SEED + 1L)
placebo_seeds <- sample.int(1e6, NM)

out_main <- vector("list", NM); out_rand <- vector("list", NM); out_plac <- vector("list", NM)
cov_log  <- vector("list", NM)
build_hash <- "unknown"
t0 <- Sys.time()
sink(file.path(OUT, "build_connector.log"))
for (i in seq_len(NM)) {
  if (!length(ACT[[i]])) next
  d <- DATES[i]
  tk <- UNIV[.(d), Ticker, nomatch = 0L]
  if (!length(tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || !nrow(fdt)) next
  if (identical(build_hash, "unknown")) {
    bh <- attr(fdt, "factor_db_build_hash"); if (!is.null(bh)) build_hash <- bh
  }
  S <- fdt[Ticker %in% tk & Factor_Name %in% POOL & is.finite(Z_Score_Aligned),
           .(Ticker, Factor_Name, z = Z_Score_Aligned)]
  rm(fdt)
  if (!nrow(S)) next
  tks <- sort(unique(S$Ticker)); fns <- sort(unique(S$Factor_Name))
  Z <- matrix(NA_real_, length(tks), length(fns), dimnames = list(tks, fns))
  Z[cbind(match(S$Ticker, tks), match(S$Factor_Name, fns))] <- S$z
  rm(S)
  cov_log[[i]] <- data.table(Date = d, n_ticker = length(tks), n_factor = length(fns))

  comp <- function(mem) {
    mm <- intersect(mem, fns)
    if (!length(mm)) return(NULL)
    Zi <- Z[, mm, drop = FALSE]
    cnt <- rowSums(is.finite(Zi))
    sc  <- rowSums(Zi, na.rm = TRUE) / pmax(cnt, 1L)
    sc[cnt < ceiling(COV_MIN_MEMBER * length(mm))] <- NA_real_
    sc
  }
  mains <- list(); rands <- list()
  for (a in names(ACT[[i]])) {
    sc <- comp(ACT[[i]][[a]]); if (is.null(sc)) next
    ok <- is.finite(sc); if (!any(ok)) next
    if (startsWith(a, "RAND_")) {
      o <- order(sc[ok], decreasing = TRUE)
      kk <- names(sc[ok])[o[seq_len(min(TOPK_RAND, sum(ok)))]]
      rands[[a]] <- data.table(arm = a, Date = d, Ticker = kk, score = unname(sc[kk]))
    } else {
      mains[[a]] <- data.table(arm = a, Date = d, Ticker = names(sc)[ok], score = unname(sc[ok]))
      if (a == "A_REL_TOP") {          # placebo: 월내 ticker 셔플 (전체 횡단면)
        set.seed(placebo_seeds[i]); pv <- sample(unname(sc[ok]))
        out_plac[[i]] <- data.table(arm = "PLACEBO_SHUFFLE", Date = d,
                                    Ticker = names(sc)[ok], score = pv)
      }
    }
  }
  if (length(mains)) out_main[[i]] <- rbindlist(mains)
  if (length(rands)) out_rand[[i]] <- rbindlist(rands)
  rm(Z); if (i %% 24L == 0L) gc(FALSE)
}
sink()
MAINP <- rbindlist(Filter(Negate(is.null), out_main))
RANDP <- rbindlist(Filter(Negate(is.null), out_rand))
PLACP <- rbindlist(Filter(Negate(is.null), out_plac))
COVL  <- rbindlist(Filter(Negate(is.null), cov_log))
say("월 루프 완료 %.0fs | main %d행(%d arm) | rand %d행 | placebo %d행 | 월 %d",
    as.numeric(difftime(Sys.time(), t0, units = "secs")), nrow(MAINP),
    uniqueN(MAINP$arm), nrow(RANDP), nrow(PLACP), uniqueN(MAINP$Date))
say("월별 유효 ticker 중앙값 %.0f / factor 중앙값 %.0f | build_hash=%s",
    median(COVL$n_ticker), median(COVL$n_factor), build_hash)

write_parquet(MAINP, file.path(OUT, "composite_main.parquet"))
write_parquet(RANDP, file.path(OUT, "composite_rand.parquet"))
write_parquet(PLACP, file.path(OUT, "composite_placebo.parquet"))
saveRDS(list(arms = ARM, main_arms = MAIN_ARMS, steps = steps, dates = DATES,
             met = MET, met_full = MET_FULL, met_ss = MET_SS, pool = POOL,
             consts = list(IS0 = IS0, OOSB = OOSB, W_ERA = W_ERA, ERA_MIN = ERA_MIN,
                           K_PRIM = K_PRIM, K_SENS = K_SENS, N_RAND = N_RAND,
                           COV_MIN_MEMBER = COV_MIN_MEMBER, SEED = SEED,
                           SS_IS_END = SS_IS_END, TOPK_RAND = TOPK_RAND),
             coverage = COVL, build_hash = build_hash,
             generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
        file.path(OUT, "memberships.rds"))
say("저장 — composite_main/rand/placebo.parquet + memberships.rds")
