#!/usr/bin/env Rscript
# =============================================================================
# test_jm_causal.R — regime_jump_model C1 수리(jm_causal v1 · 도훈 결정 PIT-C11-JM-C1) 양방향 검사
# =============================================================================
# 막는 결함: 구판은 refit 블록 (prev_end, end_i] 의 상태를 end_i 까지의 창으로 적합한 Viterbi *역추적* 경로·중심점·
#   표준화로 매겼다 → 블록 안 t 의 출력이 t 이후 최대 125거래일 입력에 의존(C11 1단계 S3 jm_lookahead_probe).
# 단정(합성 픽스처 · 손 유도 기대값):
#   E  온라인 추론 = 창 [s,t] 에 고정 모수로 푼 Viterbi 의 마지막 상태(원문 Shu-Yu-Mulvey 2024 §3.4.2) — 무작위 창 대조 ·
#      벡터화(여러 t 동시) = 단건 · Bear_Prob 식 = 구판 식(언더플로 구간 NaN 0)
#   F  ★미래 섭동: t* 이후 입력(종가·VIX)을 교란해도 Date ≤ t* 출력 전 열 identical(양성) ·
#      구판 알고리즘(참조 구현 — 블록 끝 창 적합 + 역추적)은 같은 섭동에서 t* 이하가 변한다(음성 = 섭동에 이빨이 있다)
#      + 전환 선취(anticipation) 섭동: 격변 국면 시작 직후 t* 에서 미래를 평온으로 바꿔도 불변(양성) ·
#        역추적은 미래가 격변이면 t* 이전으로 전환을 당겨 쓴다 → 구판 참조·M2 는 t* 이하 **상태**가 뒤집힌다(음성)
#   P  접두 불변: t* 에서 자른 입력의 출력 = 전체 입력 출력의 t* 이하 행
#   S  출력 계약: 구판 7열 순서 보존 + JM_Fit_Date(< Date) · 속성 jm_causal/spec/C11 · parquet 왕복 후 판독기 = causal ·
#      판독기 위반 주입(속성 제거·판 불일치·Fit≥Date·열 삭제) 전부 적발
#   C  VIX 입력 C11 관문: legacy·stale epoch 판 = 중단 · 현행 키 = 통과 · label 정책 = 미해소 표식 ·
#      파일 부재 = 중단(구판은 조용히 VIX=0) · 가용일(avail_date) 결합(행 날짜 결합 아님)
#   M  돌연변이(대상 파일 사본): M1 모수 창 블록 끝까지 · M2 역추적 경로 · M3 표준화 블록 끝까지 · M4 Fit 일 위조(자체검증) ·
#      M6 C11 관문 무력화 · M8 가용일 대신 날짜 결합 · M9 상태 1일 선행(P2 스윕) · M10 delay 기본 0 · M11 판독기 C11 무시 — 전부 red
#   P2 (2026-09-25 적대 검증 N1~N3 수리) 전환일 −3~+1 접두 불변 스윕 · S7/S8 delay 기본값 고정 · C3b label 판 c11_unresolved
# 쓰기: tempdir() 만. 운영 파일은 읽기만(대상 소스·overlay_pit_guard·atomic_parquet·C11 규칙 파일).
# 실행: Rscript 08_Tests/regime/test_jm_causal.R   (R_ENVIRON_USER=<빈 파일> 권장 · 약 1~2분)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) normalizePath(f[1], winslash = "/", mustWork = TRUE) else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(.self)) dirname(dirname(dirname(.self))) else
  gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
JMF <- file.path(ROOT, "02_Infrastructure/regime/regime_jump_model.R")
Sys.setenv(QM_ROOT = ROOT)                                  # C11 규칙 키 판독 루트 고정(이 프로세스 안에서만)

P <- 0L; FL <- 0L; SKIPS <- list()
ok <- function(c, m) { if (isTRUE(c)) { P <<- P + 1L; cat("  PASS ", m, "\n") } else { FL <<- FL + 1L; cat("  FAIL ", m, "\n") } }
skip <- function(axis, reason) { SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason); cat("  SKIP ", axis, "—", reason, "\n") }
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
TD <- normalizePath(file.path(tempdir(), paste0("jmc_", Sys.getpid())), winslash = "/", mustWork = FALSE)
dir.create(TD, recursive = TRUE, showWarnings = FALSE)
mutant <- function(src, old, new, tag) {
  t <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (lengths(regmatches(t, gregexpr(old, t, fixed = TRUE))) != 1L) return(NA_character_)
  f <- file.path(TD, paste0(tag, "_", basename(src))); writeLines(sub(old, new, t, fixed = TRUE), f, useBytes = TRUE); f
}
load_jm <- function(src, cache_dir) {
  e <- new.env(parent = globalenv()); e$PROJECT_ROOT <- ROOT; e$CACHE_DIR <- cache_dir
  invisible(capture.output(sys.source(src, envir = e, keep.source = FALSE)))
  e
}
quiet <- function(expr) { r <- NULL; invisible(capture.output(r <- force(expr))); r }

if (!file.exists(JMF)) { cat("대상 파일 부재:", JMF, "\n"); quit(status = 1L, save = "no") }

# ── 합성 픽스처: 평온/격변 블록이 교대하는 일간 수익 + 표식 계약을 실은 regime_daily_v2 ───────────────
CFG <- list(min_warmup = 150L, refit_freq_days = 50L, lookback = 250L, lambda = 50, delay = 1L)
mk_inputs <- function(n = 640L, seed = 11L) {
  set.seed(seed)
  d <- seq(as.Date("2003-01-01"), by = "day", length.out = ceiling(n * 1.5) + 10L)
  d <- d[!(as.POSIXlt(d)$wday %in% c(0L, 6L))][seq_len(n)]
  reg <- integer(0); s <- 0L
  while (length(reg) < n) { L <- sample(40:120, 1L); reg <- c(reg, rep(s, L)); s <- 1L - s }
  reg <- reg[seq_len(n)]
  r <- ifelse(reg == 1L, rnorm(n, -0.002, 0.025), rnorm(n, 0.0006, 0.008))
  bm <- data.table(Date = d, BM_Close = 1000 * cumprod(1 + r))
  vz <- as.numeric(stats::filter(reg * 1.5 + rnorm(n, 0, 0.5), rep(1 / 5, 5), sides = 1)); vz[is.na(vz)] <- 0
  list(bm = bm, vix = data.table(Date = d, VIX_z_smooth = vz), reg = reg)
}
write_inputs <- function(dir, bm, vix, key, contract = c("current", "legacy", "stale", "lag1")) {
  contract <- match.arg(contract)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write_parquet(bm, file.path(dir, "benchmark.parquet"))
  rd <- copy(vix)
  if (contract != "legacy") {
    rd[, avail_date := if (contract == "lag1") as.Date(Date) + 1L else as.Date(Date)]
    kk <- if (contract == "stale") "c11_avail:1999-01-01.b0:deadbeef" else key
    rd[, c11_regime_key := kk]; setattr(rd, "c11_avail_regime_key", kk)
  }
  write_parquet(rd, file.path(dir, "regime_daily_v2.parquet"))
  invisible(dir)
}
run_jm <- function(e, ...) quiet(e$compute_jm_daily_signal(lambda = CFG$lambda, min_warmup = CFG$min_warmup,
                                                            refit_freq_days = CFG$refit_freq_days, lookback = CFG$lookback,
                                                            delay = CFG$delay, write = FALSE, ...))

# 구판 알고리즘 참조 구현(음성 대조) — 원 compute_jm_daily_signal 의 블록 채움과 같은 식:
#   refit 격자 + 행 n, 블록 (prev_end, end_i] 를 [end_i−l+1, end_i] 창 적합(표준화 포함)의 역추적 경로·softmax 로 채운다.
old_block_fill <- function(e, ft, use_vix = TRUE) {
  X <- as.matrix(ft[, c("dd10", "sortino20", "sortino60", if (use_vix) "VIX_z"), with = FALSE]); n <- nrow(X)
  st <- rep(NA_integer_, n); bp <- rep(NA_real_, n)
  ri <- seq(CFG$min_warmup, n, by = CFG$refit_freq_days); if (tail(ri, 1) != n) ri <- c(ri, n)
  for (k in seq_along(ri)) {
    end_i <- ri[k]; ws <- max(1L, end_i - CFG$lookback + 1L); Xr <- X[ws:end_i, , drop = FALSE]
    mu <- colMeans(Xr); sdv <- apply(Xr, 2, sd); sdv[sdv < 1e-8] <- 1
    Xw <- sweep(sweep(Xr, 2, mu, "-"), 2, sdv, "/")
    f <- e$.jm_fit(Xw, K = 2L, lambda = CFG$lambda)
    prev <- if (k == 1L) 0L else ri[k - 1L]
    for (t in max(prev + 1L, ws):end_i) {
      pos <- t - ws + 1L; st[t] <- as.integer(f$states[pos] == f$bear_state)
      u <- setdiff(1:2, f$bear_state)
      db <- 0.5 * sum((Xw[pos, ] - f$Theta[f$bear_state, ])^2); du <- 0.5 * sum((Xw[pos, ] - f$Theta[u, ])^2)
      bp[t] <- exp(-db) / (exp(-db) + exp(-du))
    }
  }
  data.table(Date = ft$Date, JM_State = st, Bear_Prob = bp)
}

cat("test_jm_causal — regime_jump_model C1 수리(jm_causal) 양방향\n  대상:", JMF, "\n")
IN <- mk_inputs()
D0 <- file.path(TD, "base")
E0 <- load_jm(JMF, D0)
KEY <- tryCatch(E0$.jm_c11_env()$c11_rules_key(), error = function(e) NA_character_)
USE_VIX <- !is.na(KEY) && nzchar(KEY)
if (!USE_VIX) skip("C", sprintf("C11 규칙 키 판독 불가(%s/06_Registry/fred_availability_rules.json) — VIX 경로는 use_vix=FALSE 로 대체", ROOT))
write_inputs(D0, IN$bm, IN$vix, KEY, "current")

# ── E. 온라인 추론 = 창 Viterbi 의 마지막 상태 ────────────────────────────────────────────────
set.seed(3)
Xs <- matrix(rnorm(400 * 3), 400, 3); Xs[150:260, 1] <- Xs[150:260, 1] + 2.5
Th <- rbind(c(0, 0, 0), c(2.5, 0, 0))
eq_all <- TRUE; nchk <- 0L
for (lam in c(3, 50)) for (i in 1:25) {
  t <- sample(20:400, 1L); s <- sample(max(1L, t - 300L):t, 1L)
  a <- E0$.jm_online_states(Xs, Th, lam, t_rel = t, s_rel = s)
  b <- if (t > s) tail(E0$.jm_dp_path(Xs[s:t, , drop = FALSE], Th, lam)$states, 1L) else which.min(0.5 * rowSums(sweep(Th, 2, Xs[t, ])^2))
  eq_all <- eq_all && identical(as.integer(a), as.integer(b)); nchk <- nchk + 1L
}
ok(eq_all, sprintf("E1 .jm_online_states = 창 [s,t] 역추적 Viterbi 의 마지막 상태(무작위 %d 창 · λ 3/50)", nchk))
tt <- 200:260; ss <- pmax(1L, tt - 120L)
vb <- E0$.jm_online_states(Xs, Th, 50, t_rel = tt, s_rel = ss)
sg <- vapply(seq_along(tt), function(i) E0$.jm_online_states(Xs, Th, 50, t_rel = tt[i], s_rel = ss[i]), integer(1))
ok(identical(as.integer(vb), as.integer(sg)), "E2 벡터화(여러 t 끝 정렬 동시 재귀) = t 단건 재귀")
Zm <- matrix(rnorm(60), 20, 3); ob <- apply(Zm, 1, function(z) { db <- 0.5 * sum((z - Th[2, ])^2); du <- 0.5 * sum((z - Th[1, ])^2); exp(-db) / (exp(-db) + exp(-du)) })
nb <- E0$.jm_bear_prob(Zm, Th, 2L)
ok(max(abs(nb - ob)) < 1e-12 && all(is.finite(E0$.jm_bear_prob(Zm * 1e3, Th, 2L))),
   "E3 Bear_Prob = 구판 softmax 식(차 < 1e-12) · 원거리(구판 0/0=NaN 구간)도 유한")

# ── 기준 실행 + 출력 계약 ──────────────────────────────────────────────────────────────────
B <- run_jm(E0, use_vix = USE_VIX)
old_cols <- c("Date", "Price", "Vol_Est", "Bear_Prob", "JM_State", "Bear_Prob_lag", "JM_State_lag")
ok(identical(names(B)[1:7], old_cols) && identical(names(B)[8], "JM_Fit_Date") && ncol(B) == 8L,
   "S1 구판 7열 순서 보존 + 8열 JM_Fit_Date")
ok(inherits(B$Date, "Date") && inherits(B$JM_Fit_Date, "Date") && is.integer(B$JM_State) && is.double(B$Bear_Prob) &&
     all(B$JM_State %in% 0:1) && all(B$Bear_Prob >= 0 & B$Bear_Prob <= 1),
   "S2 열 형(Date·Date·int·double) · 상태 0/1 · Bear_Prob ∈ [0,1]")
ft0 <- quiet(E0$build_jm_features(use_vix = USE_VIX))
first_ok <- identical(min(B$Date), ft0$Date[CFG$min_warmup + 2L])       # 첫 모수 적용 행(warmup+1) 의 lag 가 서는 다음 행
ok(all(B$JM_Fit_Date < B$Date) && first_ok && identical(E0$jm_causal_status(B), "causal"),
   sprintf("S3 전 행 JM_Fit_Date < Date · 첫 행 = warmup+2 행(%s) · 판독기 causal", as.character(min(B$Date))))
ok(identical(attr(B, "jm_causal"), E0$JM_CAUSAL_VERSION) && grepl("2402.05272", attr(B, "jm_causal_spec"), fixed = TRUE) &&
     (!USE_VIX || (identical(attr(B, "jm_input_c11_status"), "avail_annotated") && identical(attr(B, "jm_input_c11_regime_key"), KEY))),
   "S4 속성 jm_causal·spec(원문 ID)·C11 입력 상태/키")
pq <- file.path(TD, "rt.parquet"); source(file.path(ROOT, "02_Infrastructure/utils/atomic_parquet.R"))
qvest_atomic_write_parquet(B, pq, tag = "t/jm")
RT <- as.data.table(read_parquet(pq))
ok(identical(E0$jm_causal_status(RT), "causal") && identical(attr(RT, "jm_causal"), E0$JM_CAUSAL_VERSION),
   "S5 parquet 왕복(원자 기록 → as.data.table) 뒤에도 속성·판독기 causal")
V1 <- copy(RT); setattr(V1, "jm_causal", NULL)
V2 <- copy(RT); setattr(V2, "jm_causal", "jm_causal:v0")
V3 <- copy(RT); V3[50L, JM_Fit_Date := Date]
V4 <- copy(RT)[, JM_Fit_Date := NULL]; setattr(V4, "jm_causal", E0$JM_CAUSAL_VERSION)
V5 <- copy(RT); V5[7L, JM_Fit_Date := NA]
ok(identical(E0$jm_causal_status(V1), "legacy_noncausal") && identical(E0$jm_causal_status(V2), "stale_version") &&
     identical(E0$jm_causal_status(V3), "violated") && identical(E0$jm_causal_status(V4), "malformed") &&
     identical(E0$jm_causal_status(V5), "violated"),
   "S6 판독기 위반 주입 5종 적발(속성 제거·판 불일치·Fit=Date·열 삭제·Fit NA)")

# ── F. 미래 섭동 ─────────────────────────────────────────────────────────────────────────
k_star <- CFG$min_warmup + 5L * CFG$refit_freq_days + 12L                # 블록 중간(뒤로 38행 남음)
t_star <- ft0$Date[k_star]
pert_inputs <- function() {
  bm <- copy(IN$bm); vx <- copy(IN$vix); set.seed(99)
  k <- which(bm$Date > t_star)
  bm[k, BM_Close := bm$BM_Close[k[1] - 1L] * cumprod(1 + rnorm(length(k), -0.012, 0.04))]
  vx[Date > t_star, VIX_z_smooth := VIX_z_smooth + 4]
  list(bm = bm, vix = vx)
}
PI <- pert_inputs(); D1 <- file.path(TD, "pert"); write_inputs(D1, PI$bm, PI$vix, KEY, "current")
E1 <- load_jm(JMF, D1)
Bp <- run_jm(E1, use_vix = USE_VIX)
cols_cmp <- c("Date", "Bear_Prob", "JM_State", "Bear_Prob_lag", "JM_State_lag", "JM_Fit_Date")
same_upto <- function(A, C, tstar) {
  a <- as.data.frame(A[Date <= tstar, ..cols_cmp]); c <- as.data.frame(C[Date <= tstar, ..cols_cmp])
  nrow(a) > 0L && identical(a, c)
}
ok(!isTRUE(all.equal(B[Date > t_star, Bear_Prob], Bp[Date > t_star, Bear_Prob])),
   sprintf("F0 섭동이 t* 이후 출력을 실제로 바꾼다(섭동 유효 · t*=%s)", as.character(t_star)))
ok(same_upto(B, Bp, t_star), sprintf("F1 ★양성: t* 이후 입력 교란 → Date ≤ t* 전 열 identical (%d행)", nrow(B[Date <= t_star])))
ftp <- quiet(E1$build_jm_features(use_vix = USE_VIX))
O0 <- old_block_fill(E0, ft0, USE_VIX); O1 <- old_block_fill(E0, ftp, USE_VIX)
m <- merge(O0[Date <= t_star & !is.na(JM_State)], O1[Date <= t_star & !is.na(JM_State)], by = "Date")
nd_bp <- sum(abs(m$Bear_Prob.x - m$Bear_Prob.y) > 1e-9); nd_st <- sum(m$JM_State.x != m$JM_State.y)
ok(nd_bp > 0L, sprintf("F2 ★음성: 구판 알고리즘(블록 끝 창 적합·역추적)은 같은 섭동에서 t* 이하가 변한다(Bear_Prob %d행 · 상태 %d행)", nd_bp, nd_st))

# ── F3/F4. 전환 선취 섭동 — 전방 필터가 bear 로 넘어가기 하루 전(t*)에서 미래를 평온으로 교체 ─────────────────
#   t* 는 신판 출력에서 고른다(필터 0→1 전환일의 전일 · 결정적). 그날까지 bear 증거가 λ 바로 밑까지 쌓여 있다.
#   역추적(스무딩)은 t* 뒤의 격변(기준 입력)을 보고 t* 이전 구간을 bear 로 당긴다 — 미래가 평온이면 bull 로 둔다.
#   전방 필터는 t* 이하만 보므로 둘이 같아야 한다.
calm_future <- function(ts) {
  bm <- copy(IN$bm); vx <- copy(IN$vix); set.seed(123)
  k <- which(bm$Date > ts)
  bm[k, BM_Close := bm$BM_Close[k[1] - 1L] * cumprod(1 + rnorm(length(k), 0.0006, 0.008))]
  vx[Date > ts, VIX_z_smooth := 0]
  list(bm = bm, vix = vx)
}
cand <- integer(0)
sw <- B[JM_State == 1L & shift(JM_State) == 0L, Date]                   # 필터 bull→bear 전환일
for (d in as.list(sw)) {
  k <- match(d, ft0$Date) - 1L                                          # t* = 전환 전일(ft index)
  if (is.na(k) || k <= CFG$min_warmup + 5L) next
  be <- CFG$min_warmup + CFG$refit_freq_days * ceiling((k - CFG$min_warmup) / CFG$refit_freq_days)
  if ((k - CFG$min_warmup) %% CFG$refit_freq_days == 0L) next           # 블록 경계 당일 제외
  if (be - k >= 10L && be <= nrow(ft0)) cand <- c(cand, k)
}
cand <- head(cand, 3L)
ANT <- lapply(seq_along(cand), function(i) {
  ts <- ft0$Date[cand[i]]; ci <- calm_future(ts); dd <- file.path(TD, sprintf("ant%d", i))
  write_inputs(dd, ci$bm, ci$vix, KEY, "current"); list(dir = dd, tstar = ts)
})
if (!length(ANT)) ok(FALSE, "F3 전환 선취 후보 0 — 픽스처 격변 전환이 블록 중간에 없다(픽스처 수리 필요)") else {
  same3 <- vapply(ANT, function(z) same_upto(B, run_jm(load_jm(JMF, z$dir), use_vix = USE_VIX), z$tstar), logical(1))
  ok(all(same3), sprintf("F3 ★양성: 전환 선취 섭동 %d건(t*=%s) 전부 Date ≤ t* identical", length(ANT),
                         paste(vapply(ANT, function(z) as.character(z$tstar), ""), collapse = ",")))
  flips <- vapply(ANT, function(z) {
    Oz <- old_block_fill(E0, quiet(load_jm(JMF, z$dir)$build_jm_features(use_vix = USE_VIX)), USE_VIX)
    mm <- merge(O0[Date <= z$tstar & !is.na(JM_State)], Oz[Date <= z$tstar & !is.na(JM_State)], by = "Date")
    sum(mm$JM_State.x != mm$JM_State.y)
  }, integer(1))
  ok(any(flips > 0L), sprintf("F4 ★음성: 구판 알고리즘은 같은 섭동에서 t* 이하 **상태**가 뒤집힌다(후보별 %s행)", paste(flips, collapse = "/")))
}
PERT <- c(list(list(dir = D1, tstar = t_star)), ANT)

# ── P. 접두 불변 ─────────────────────────────────────────────────────────────────────────
D2 <- file.path(TD, "trunc"); write_inputs(D2, IN$bm[Date <= t_star], IN$vix[Date <= t_star], KEY, "current")
Bt <- run_jm(load_jm(JMF, D2), use_vix = USE_VIX)
ok(identical(max(Bt$Date), t_star) && same_upto(B, Bt, t_star), "P1 t* 에서 자른 입력의 출력 = 전체 입력 출력의 t* 이하 행(identical)")

# ── P2. 접두 불변 스윕(2026-09-25 적대 검증 JM N1 수리) ──────────────────────────────────────────
#   F1·P1 의 t* 는 전환에서 먼 고정점 하나 · F3 후보는 검사 대상 자신의 출력에서 고른다 → 상태 열 1~5일 선행 누출
#   (jm_state[ts] 에 t+L 을 심은 판)은 λ 가 상태를 붙잡아 며칠치 교란으로는 뒤집히지 않아 전부 통과했다(X3b 26 PASS).
#   누출 판은 **자기 전환일에서** 미래를 본다: 전체 입력에선 t 에 전환(미래 봄), t 에서 자른 입력에선 못 본다.
#   그래서 대상 출력의 전환일 −3~+1 일 전부를 t 로 잡고 '자른 입력의 마지막 행 = 전체 입력의 t 행'(상태·Bear_Prob)을 단정한다.
sweep_prefix <- function(f, Bref) {
  swd <- Bref[JM_State != shift(JM_State), Date]; swd <- swd[!is.na(swd)]
  ks <- sort(unique(unlist(lapply(match(swd, ft0$Date), function(k) (k - 3L):(k + 1L)))))
  ks <- ks[!is.na(ks) & ks > CFG$min_warmup + 2L & ks <= nrow(ft0)]
  bad <- 0L
  for (k in ks) {
    tk <- ft0$Date[k]; dd <- file.path(TD, sprintf("sw_%d", k))
    if (!dir.exists(dd)) write_inputs(dd, IN$bm[Date <= tk], IN$vix[Date <= tk], KEY, "current")
    Tk <- tryCatch(run_jm(load_jm(f, dd), use_vix = USE_VIX), error = function(e) NULL)
    if (is.null(Tk) || !nrow(Tk) || !identical(Tk[.N, Date], tk) ||
        !identical(Tk[.N, JM_State], Bref[Date == tk, JM_State]) || !identical(Tk[.N, Bear_Prob], Bref[Date == tk, Bear_Prob])) bad <- bad + 1L
  }
  list(n = length(ks), bad = bad, n_sw = length(swd))
}
SW0 <- sweep_prefix(JMF, B)
ok(SW0$n >= 10L && SW0$bad == 0L, sprintf("P2 ★접두 불변 스윕: 전환 %d개의 −3~+1일 %d점 전부 '자른 입력 마지막 행 = 전체 t 행'(불일치 %d)", SW0$n_sw, SW0$n, SW0$bad))

# ── S7. delay 기본값 고정(2026-09-25 JM N2) — 판독기·표식은 delay 를 보증하지 않는다. 0 으로 표류하면 *_lag 가 같은 날 값 ──
ok(identical(eval(formals(E0$compute_jm_daily_signal)$delay), 1L) && all(B$JM_State_lag[-1] == B$JM_State[-nrow(B)]) &&
     isTRUE(all(B$Bear_Prob_lag[-1] == B$Bear_Prob[-nrow(B)])),
   "S7 compute_jm_daily_signal 기본 delay = 1L · *_lag = 1행 지연(같은 날 값 아님)")
Bd <- quiet(E0$compute_jm_daily_signal(lambda = CFG$lambda, min_warmup = CFG$min_warmup, refit_freq_days = CFG$refit_freq_days,
                                       lookback = CFG$lookback, write = FALSE, use_vix = USE_VIX))      # delay 미지정 = 기본값 경로
ok(identical(as.data.frame(Bd[, ..cols_cmp]), as.data.frame(B[, ..cols_cmp])), "S8 delay 미지정(기본값) 실행 = delay=1 실행(기본값 표류 적발)")

# ── C. VIX 입력 C11 관문 ────────────────────────────────────────────────────────────────
if (USE_VIX) {
  Dl <- file.path(TD, "legacy"); write_inputs(Dl, IN$bm, IN$vix, KEY, "legacy")
  El <- load_jm(JMF, Dl)
  old_pol <- Sys.getenv("QVEST_C11_LEGACY_REGIME", NA); Sys.unsetenv("QVEST_C11_LEGACY_REGIME")
  e1 <- err_of(quiet(El$build_jm_features(use_vix = TRUE)))
  ok(!is.na(e1) && grepl("legacy", e1) && grepl("C11", e1), "C1 legacy 판(가용일·키 없음) = 중단(기본 정책 stop)")
  Ds <- file.path(TD, "stale"); write_inputs(Ds, IN$bm, IN$vix, KEY, "stale")
  Es <- load_jm(JMF, Ds)
  e2 <- err_of(quiet(Es$build_jm_features(use_vix = TRUE)))
  ok(!is.na(e2) && grepl("stale_epoch", e2, fixed = TRUE), "C2 stale epoch 판(옛 규칙 키) = 중단")
  fl <- quiet(El$build_jm_features(use_vix = TRUE, c11_policy = "label"))
  ok(identical(attr(fl, "jm_c11")$status, "unresolved_legacy_panel"), "C3 label 정책(진단 전용) = 진행하되 미해소 표식")
  ## C3b (JM N3): label 정책 산출은 판독기가 causal 로 읽지 않는다 · 캐시 기록 거부(진단 계산 write=FALSE 는 허용)
  cl <- tryCatch(quiet(El$compute_jm_daily_signal(lambda = CFG$lambda, min_warmup = CFG$min_warmup, refit_freq_days = CFG$refit_freq_days,
                                                  lookback = CFG$lookback, delay = CFG$delay, write = FALSE, c11_policy = "label")), error = function(e) e)
  ew <- err_of(quiet(El$compute_jm_daily_signal(lambda = CFG$lambda, min_warmup = CFG$min_warmup, refit_freq_days = CFG$refit_freq_days,
                                                lookback = CFG$lookback, delay = CFG$delay, write = TRUE, out_path = file.path(TD, "label_w.parquet"),
                                                c11_policy = "label")))
  ok(!inherits(cl, "error") && identical(El$jm_causal_status(cl), "c11_unresolved") && !is.na(ew) && grepl("c11_unresolved", ew, fixed = TRUE) &&
       !file.exists(file.path(TD, "label_w.parquet")),
     "C3b label 정책 산출 = 판독기 c11_unresolved(causal 아님) · write=TRUE 는 자체검증 중단(캐시 미기록)")
  Dm <- file.path(TD, "missing"); dir.create(Dm, showWarnings = FALSE); write_parquet(IN$bm, file.path(Dm, "benchmark.parquet"))
  e4 <- err_of(quiet(load_jm(JMF, Dm)$build_jm_features(use_vix = TRUE)))
  ok(!is.na(e4) && grepl("판독 실패", e4, fixed = TRUE), "C4 regime_daily_v2 부재 = 중단(구판은 조용히 VIX_z=0)")
  Da <- file.path(TD, "lag1"); write_inputs(Da, IN$bm, IN$vix, KEY, "lag1")
  fa <- quiet(load_jm(JMF, Da)$build_jm_features(use_vix = TRUE))
  exp_v <- IN$vix$VIX_z_smooth[match(fa$Date, IN$vix$Date) - 1L]         # 가용일 = 날짜+1 → 결정일 d 에는 직전 행 값
  ok(isTRUE(all.equal(fa$VIX_z[-1], exp_v[-1])) && !isTRUE(all.equal(fa$VIX_z[-1], IN$vix$VIX_z_smooth[match(fa$Date, IN$vix$Date)][-1])),
     "C5 결합 = 가용일(avail_date ≤ d) 기준 — 행 날짜 결합이 아니다(가용일 +1 픽스처에서 직전 행 값)")
  if (!is.na(old_pol)) Sys.setenv(QVEST_C11_LEGACY_REGIME = old_pol)
}

# ── M. 돌연변이 ─────────────────────────────────────────────────────────────────────────
mut_red_future <- function(f, tag) {
  if (is.na(f)) { ok(FALSE, sprintf("%s 대상 줄 부재(돌연변이 미적용 — 검사 좌표 낡음)", tag)); return(invisible()) }
  r0 <- tryCatch(run_jm(load_jm(f, D0), use_vix = USE_VIX), error = function(e) e)
  if (inherits(r0, "error") || !identical(load_jm(f, D0)$jm_causal_status(r0), "causal")) { ok(TRUE, sprintf("%s ★red(기준 실행 거부)", tag)); return(invisible()) }
  hit <- character(0)
  for (z in PERT) {                                   # 섭동 중 하나라도 t* 이하를 바꾸면 red
    r1 <- tryCatch(run_jm(load_jm(f, z$dir), use_vix = USE_VIX), error = function(e) e)
    if (inherits(r1, "error") || !same_upto(r0, r1, z$tstar)) { hit <- as.character(z$tstar); break }
  }
  ok(length(hit) > 0L, sprintf("%s ★red%s", tag, if (length(hit)) sprintf("(t*=%s 섭동)", hit) else ""))
}
mut_red_future(mutant(JMF, "Xw_raw <- X_all[win_start:r_i, , drop = FALSE]",
                      "Xw_raw <- X_all[win_start:block_end[ri], , drop = FALSE]", "m1"), "M1 모수 창을 블록 끝까지(구판 적합) → 섭동 적발")
mut_red_future(mutant(JMF, "st <- .jm_online_states(Z, par$Theta, lambda, t_rel = ts - a + 1L, s_rel = ss - a + 1L)",
                      "st <- tail(.jm_dp_path(Z, par$Theta, lambda)$states, length(ts))", "m2"), "M2 전방 필터 → 블록 창 역추적 경로 → 섭동 적발")
mut_red_future(mutant(JMF, "mu <- colMeans(Xw_raw); sdv <- apply(Xw_raw, 2, sd)",
                      "mu <- colMeans(X_all[win_start:block_end[ri], , drop = FALSE]); sdv <- apply(X_all[win_start:block_end[ri], , drop = FALSE], 2, sd)",
                      "m3"), "M3 표준화 통계를 블록 끝까지 → 섭동 적발")
f4 <- mutant(JMF, "fit_i[ts]     <- par$i", "fit_i[ts]     <- ts", "m4")
if (is.na(f4)) ok(FALSE, "M4 대상 줄 부재") else {
  e4m <- err_of(run_jm(load_jm(f4, D0), use_vix = USE_VIX))
  ok(!is.na(e4m) && grepl("자체검증 FAIL", e4m, fixed = TRUE), "M4 ★red: Fit 일 = 행 날짜 위조 → 자체검증 중단(캐시 미기록)")
}
## M9 (N1): 상태 열 1일 선행 누출 — 구판 검사(F1·F3·P1)는 전부 통과했다. P2 스윕이 잡아야 한다.
f9 <- mutant(JMF, "jm_state[ts]  <- as.integer(st == par$bear)",
             "jm_state[ts]  <- as.integer(st == par$bear); if (length(ts) > 1L) jm_state[head(ts, -1L)] <- jm_state[tail(ts, -1L)]", "m9")
if (is.na(f9)) ok(FALSE, "M9 대상 줄 부재") else {
  r9 <- tryCatch(run_jm(load_jm(f9, D0), use_vix = USE_VIX), error = function(e) NULL)
  s9 <- if (is.null(r9)) list(bad = 1L, n = 0L) else sweep_prefix(f9, r9)
  ok(s9$bad > 0L, sprintf("M9 ★red: 상태 1일 선행 누출 → P2 스윕 불일치 %d/%d", s9$bad, s9$n))
}
## M10 (N2): delay 기본값 0 표류
f10 <- mutant(JMF, "lookback = 3000L, delay = 1L, write = TRUE,", "lookback = 3000L, delay = 0L, write = TRUE,", "m10")
if (is.na(f10)) ok(FALSE, "M10 대상 줄 부재") else {
  e10 <- load_jm(f10, D0)
  B10 <- tryCatch(quiet(e10$compute_jm_daily_signal(lambda = CFG$lambda, min_warmup = CFG$min_warmup, refit_freq_days = CFG$refit_freq_days,
                                                    lookback = CFG$lookback, write = FALSE, use_vix = USE_VIX)), error = function(e) NULL)
  ok(!identical(eval(formals(e10$compute_jm_daily_signal)$delay), 1L) &&
       (is.null(B10) || !identical(as.data.frame(B10[, ..cols_cmp]), as.data.frame(B[, ..cols_cmp]))),
     "M10 ★red: delay 기본값 0 → S7·S8 기대 불일치")
}
## M11 (N3): 판독기가 C11 입력 상태를 무시(구판)
f11 <- mutant(JMF, "if (!is.null(cs) && !(as.character(cs)[1] %in% c(\"avail_annotated\", \"not_used\"))) return(\"c11_unresolved\")",
              "invisible(cs)", "m11")
if (is.na(f11)) ok(FALSE, "M11 대상 줄 부재") else if (USE_VIX) {
  e11 <- load_jm(f11, file.path(TD, "legacy"))
  w11 <- file.path(TD, "label_m11.parquet")
  invisible(tryCatch(quiet(e11$compute_jm_daily_signal(lambda = CFG$lambda, min_warmup = CFG$min_warmup, refit_freq_days = CFG$refit_freq_days,
                                                       lookback = CFG$lookback, delay = CFG$delay, write = TRUE, out_path = w11, c11_policy = "label")),
                     error = function(e) NULL))
  ok(file.exists(w11), "M11 ★red: 판독기 C11 무시 → label 정책 판이 causal 표식으로 캐시 기록(C3b 가 잡는다)")
}
if (USE_VIX) {
  f6 <- mutant(JMF, "gate <- ce$c11_legacy_gate(rd, \"VIX_z_smooth\",",
               "gate <- list(status = \"avail_annotated\", legacy = FALSE); .unused <- list(rd, \"VIX_z_smooth\",", "m6")
  if (is.na(f6)) ok(FALSE, "M6 대상 줄 부재") else {
    e6 <- err_of(quiet(load_jm(f6, file.path(TD, "stale"))$build_jm_features(use_vix = TRUE)))
    ok(is.na(e6) || !grepl("stale_epoch", e6, fixed = TRUE), "M6 ★red: C11 관문 무력화 → stale 판이 통과(C2 가 잡는다)")
  }
  f8 <- mutant(JMF, "al <- ce$c11_asof_align(ft$Date, rd, \"VIX_z_smooth\")",
               "al <- list(value = rd$VIX_z_smooth[match(ft$Date, rd$Date)])", "m8")
  if (is.na(f8)) ok(FALSE, "M8 대상 줄 부재") else {
    fa8 <- quiet(load_jm(f8, file.path(TD, "lag1"))$build_jm_features(use_vix = TRUE))
    exp8 <- IN$vix$VIX_z_smooth[match(fa8$Date, IN$vix$Date) - 1L]
    ok(!isTRUE(all.equal(fa8$VIX_z[-1], exp8[-1])), "M8 ★red: 가용일 대신 행 날짜 결합 → C5 기대값 불일치")
  }
}

unlink(TD, recursive = TRUE, force = TRUE)
cat(sprintf("\n=== 최종: %d PASS / %d FAIL / %d SKIP ===\n", P, FL, length(SKIPS)))
cat(as.character(toJSON(list(test = "test_jm_causal", pass = P, fail = FL, total = P + FL,
                             skipped = length(SKIPS), skips = SKIPS), auto_unbox = TRUE)), "\n", sep = "")
## 성공 시 quit 하지 않는다 — 08_Tests/regime/run_all.R 가 같은 프로세스에서 sys.source 한다(quit(0) 은 러너를 죽인다 · 수렴 규약).
if (FL > 0L || length(SKIPS) > 0L) quit(status = 1L, save = "no")
