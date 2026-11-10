#!/usr/bin/env Rscript
#==============================================================================
# test_selection_reality_check.R — 선택 현실 점검 계약(등급 v3.4 · 스윕형 선정의 A 관문)
#   대상: 02_Infrastructure/contracts/selection_reality_check.R
#   본다: ① 통계량 = 계약 PORT_t 와 같은 값 ② 정상 부트스트랩 색인 ③ 조정 p값 = Romano & Wolf (2016) 알고리즘 4.1 직접 계산과 일치
#         ④ 음성 대조 — 순수 잡음 집합의 '최고'는 통과하지 못한다(족 단위 오류율) ⑤ 양성 대조 — 진짜 알파 1개는 통과한다
#         ⑥ 닮은 변형은 독립 시행으로 세지 않는다(환산 독립 시행 수 · 요구 t) ⑦ PBO ⑧ 관문 판독(fail-closed · 위조 · 설정 불일치)
#         ⑨ 폴더 적재(없는 날 = 활성 수익 0) ⑩ 호출자 난수 상태 불변 ⑪ 돌연변이 — 보정을 뺀 사본은 음성 대조를 통과시킨다
#   격리: 설정은 임시 파일(path 인자) — 운영 등록부 · ~/.Renviron 을 읽지 않는다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
args <- commandArgs(trailingOnly = FALSE)
me <- sub("^--file=", "", args[grep("^--file=", args)][1])
ROOT <- NA_character_
for (p in c(dirname(dirname(dirname(me))), Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
  if (is.na(p) || !nzchar(p)) next
  p <- gsub("\\\\", "/", p)
  if (file.exists(file.path(p, "02_Infrastructure", "contracts", "selection_reality_check.R"))) { ROOT <- p; break }
}
if (is.na(ROOT)) stop("저장소 루트를 찾지 못했다")
SRC <- file.path(ROOT, "02_Infrastructure", "contracts", "selection_reality_check.R")
E <- new.env(parent = globalenv()); sys.source(SRC, envir = E, keep.source = FALSE)
pass <- 0L; fail <- 0L
chk <- function(name, cond) {
  ok <- isTRUE(tryCatch(cond, error = function(e) { cat("     오류:", conditionMessage(e), "\n"); FALSE }))
  if (ok) pass <<- pass + 1L else fail <<- fail + 1L
  cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", name))
}
TD <- tempfile("src_test_"); dir.create(TD)
CFG_PATH <- file.path(TD, "grade_v3.json")
mk_cfg <- function(alpha = 0.05, B = 1000L, role = "diagnostic", version = "sbT") {
  writeLines(toJSON(list(selection_bias = list(version = version, method = "romano_wolf_stepdown_maxT", bootstrap = "stationary",
    block_rule = "n_cuberoot", alpha = alpha, resamples = B, seed = 7L, nw_lag = 3L, missing_dates = "zero_active",
    pbo = list(role = role, partitions = 16L, flag_above = 0.05))), auto_unbox = TRUE), CFG_PATH)
  E$src_cfg(path = CFG_PATH)
}
cfg <- mk_cfg()

## ① 통계량 = 계약의 .nw_t_mean
CE <- new.env(parent = globalenv())
ctr <- parse(file.path(ROOT, "02_Infrastructure", "contracts", "backtest_result_contract.R"), keep.source = FALSE)
for (ex in ctr) if (is.call(ex) && identical(as.character(ex[[1]]), "<-") && identical(as.character(ex[[2]]), ".nw_t_mean")) eval(ex, CE)
set.seed(11); n <- 1500L
x <- as.numeric(stats::filter(rnorm(n, 0.0004, 0.01), 0.2, method = "recursive"))
A1 <- cbind(a = x, b = rnorm(n, 0, 0.01))
nw <- E$src_nw(A1, 3L)
chk("T01 통계량이 계약의 PORT_t 산식과 같다(자기상관 있는 계열 · 차 1e-12 안쪽)",
    exists(".nw_t_mean", envir = CE) && abs(nw$t[["a"]] - CE$.nw_t_mean(x, 3L)) < 1e-12 && abs(nw$t[["b"]] - CE$.nw_t_mean(A1[, "b"], 3L)) < 1e-12)

## ② 정상 부트스트랩 색인
set.seed(3); ix <- E$src_sb_index(5000L, 1 / 20)
runs <- rle(diff(ix) == 1L | diff(ix) == -4999L)
chk("T02 색인은 1..n 안에 있고 길이가 n 이며 연속 구간의 평균 길이가 기대 블록 길이 근처다",
    length(ix) == 5000L && all(ix >= 1L & ix <= 5000L) && abs(5000 / (sum(!(diff(ix) == 1L | diff(ix) == -4999L)) + 1) - 20) < 4)

## ③ 조정 p값 — 알고리즘 4.1 을 그대로 풀어 쓴 계산과 일치
set.seed(5); K <- 6L; M <- 400L
tt <- c(2.4, 0.3, 1.9, -0.5, 2.1, 0.9); names(tt) <- paste0("s", 1:K)
Tn <- matrix(rnorm(M * K), M, K)
got <- E$src_stepdown_p(tt, Tn)$p_adj
ord <- order(tt, decreasing = TRUE); ref <- numeric(K)
for (s in seq_along(ord)) {
  rest <- ord[s:K]
  mx <- apply(Tn[, rest, drop = FALSE], 1, max)
  p0 <- (sum(mx >= tt[ord[s]]) + 1) / (M + 1)
  ref[ord[s]] <- if (s == 1L) p0 else max(p0, ref[ord[s - 1L]])
}
chk("T03 조정 p값이 Romano & Wolf (2016) 알고리즘 4.1 의 직접 계산과 같다", isTRUE(all.equal(unname(got), ref, tolerance = 1e-12)))
chk("T04 조정 p값은 t 가 큰 순서로 단조 증가한다(단조화 단계)", !is.unsorted(got[ord]))

## ④ 음성 대조 — 순수 잡음 40개에서 '최고'를 골라도 통과율이 alpha 근처다
neg_rate <- function(E0, reps = 40L, K = 40L, n = 1200L) {
  cfg0 <- mk_cfg(B = 1000L); hit <- 0L
  for (r in seq_len(reps)) {
    set.seed(1000L + r)
    A <- matrix(rnorm(n * K, 0, 0.01), n, K, dimnames = list(NULL, paste0("z", 1:K)))
    best <- colnames(A)[which.max(E0$src_nw(A, 3L)$t)]
    hit <- hit + isTRUE(E0$src_check(A, best, cfg0)$pass)
  }
  hit / reps
}
r_neg <- neg_rate(E)
chk(sprintf("T05 음성 대조: 잡음 40개 중 최고를 후보로 세워도 통과율 %.3f — alpha 0.05 근처(0.15 이하)", r_neg), r_neg <= 0.15)

## ⑤ 양성 대조 — 진짜 알파 1개(t 약 4)는 잡음 39개 사이에서 통과한다
set.seed(77); n <- 2500L; K <- 40L
A <- matrix(rnorm(n * K, 0, 0.01), n, K, dimnames = list(NULL, paste0("z", 1:K)))
A[, "z7"] <- A[, "z7"] + 4 * 0.01 / sqrt(n)
c_pos <- E$src_check(A, "z7", cfg, sensitivity = TRUE)
chk(sprintf("T06 양성 대조: 진짜 알파 후보(t %.2f)가 통과한다(조정 p %.4f)", c_pos$candidate_t, c_pos$p_adj_candidate),
    isTRUE(c_pos$pass) && c_pos$p_adj_candidate <= 0.05)
chk("T07 블록 길이 절반 · 두 배에서도 판정이 같다(민감도 진단)",
    c_pos$block_sensitivity$half$p_adj_candidate <= 0.05 && c_pos$block_sensitivity$double$p_adj_candidate <= 0.05)
chk("T08 같은 입력 · 같은 씨앗이면 결과가 같다(재현)", identical(E$src_check(A, "z7", cfg)$p_adj_candidate, c_pos$p_adj_candidate))

## ⑥ 닮은 변형은 독립 시행으로 세지 않는다
set.seed(9); n <- 2000L
core <- rnorm(n, 0, 0.01)
A_sim <- sapply(1:40, function(i) core + rnorm(n, 0, 0.001)); colnames(A_sim) <- paste0("v", 1:40)
A_ind <- matrix(rnorm(n * 40, 0, 0.01), n, 40, dimnames = list(NULL, paste0("u", 1:40)))
c_sim <- E$src_check(A_sim, "v1", cfg); c_ind <- E$src_check(A_ind, "u1", cfg)
chk(sprintf("T09 닮은 변형 40개의 환산 독립 시행 수(%.1f)가 무관한 40개(%.1f)보다 훨씬 작다", c_sim$effective_independent_trials, c_ind$effective_independent_trials),
    c_sim$effective_independent_trials < 6 && c_ind$effective_independent_trials > 20)
chk(sprintf("T10 요구 t 도 낮다(닮은 변형 %.2f < 무관 %.2f) — 무관 40개는 이론값 %.2f 근처", c_sim$required_t, c_ind$required_t, qnorm(0.95^(1 / 40))),
    c_sim$required_t < c_ind$required_t - 0.5 && abs(c_ind$required_t - qnorm(0.95^(1 / 40))) < 0.25)

## ⑦ PBO
p_sim <- E$src_pbo(A_sim, 16L)
A_dom <- A_ind; A_dom[, "u3"] <- A_dom[, "u3"] + 0.002
p_dom <- E$src_pbo(A_dom, 16L)
chk(sprintf("T11 PBO: 조합 수 = C(16,8) = 12870 · 한 전략이 줄곧 우월하면 0 근처(%.3f)", p_dom$pbo), p_dom$combinations == 12870L && p_dom$pbo < 0.02)
chk(sprintf("T12 PBO: 닮은 변형끼리는 0.5 근처(%.3f) — 관례 문턱 0.05 를 관문으로 쓰면 구조적으로 못 넘는다", p_sim$pbo), p_sim$pbo > 0.25 && p_sim$pbo < 0.75)
chk("T13 PBO: 전략 1개 · 관측 부족은 '해당 없음'", identical(E$src_pbo(A_ind[, 1, drop = FALSE])$status, "not_applicable") &&
      identical(E$src_pbo(A_ind[1:40, ])$status, "not_applicable"))

## ⑧ 관문 판독
## 기대 시행 집합(등록 시행 수 · 시행 id) — 관문은 이것을 받아야 통과를 낸다(G1 · 11-10)
EXP <- function(ck) list(n_trials = length(unlist(ck$trial_ids)) + length(unlist(ck$dropped_zero_variance)), ids = unlist(ck$trial_ids))
g_ok <- E$src_gate(c_pos, c_pos$candidate_t, cfg, expected = EXP(c_pos))
chk("T14 관문: 통과 결과 + 같은 PORT_t + 기대 시행 집합 일치 → 통과", isTRUE(g_ok$ok))
chk("T15 관문: PORT_t 가 다른 전략의 결과물을 들이대면 거부(후보 일치 검사)", !isTRUE(E$src_gate(c_pos, c_pos$candidate_t + 0.3, cfg, expected = EXP(c_pos))$ok))
forged <- c_pos; forged$p_adj_candidate <- 0.9
chk("T16 관문: 통과 표시만 참이고 p 가 큰 위조물은 거부(p 로 다시 판정)", !isTRUE(E$src_gate(forged, forged$candidate_t, cfg, expected = EXP(c_pos))$ok))
chk("T17 관문: 설정 판 · alpha 가 다르면 거부", !isTRUE(E$src_gate(c_pos, c_pos$candidate_t, mk_cfg(version = "sbX"), expected = EXP(c_pos))$ok) &&
      !isTRUE(E$src_gate(c_pos, c_pos$candidate_t, mk_cfg(alpha = 0.01), expected = EXP(c_pos))$ok))
cfg <- mk_cfg()
chk("T18 관문: 형식이 아닌 것 · 빈 것은 거부", !isTRUE(E$src_gate(list(pass = TRUE), 3, mk_cfg(), expected = list(n_trials = 1))$ok) &&
      !isTRUE(E$src_gate(NULL, 3, mk_cfg(), expected = list(n_trials = 1))$ok))
## 닮은 변형 전부에 같은 진짜 알파(t 약 5) — 누구를 골라도 유의하지만 '보는 쪽 최고'의 우위는 우연이다(PBO 0.5 근처)
A_good <- A_sim + 5 * 0.01 / sqrt(nrow(A_sim))
cand_g <- colnames(A_good)[which.max(E$src_nw(A_good, 3L)$t)]
cfg_gate <- mk_cfg(role = "gate")
c_gate <- E$src_check(A_good, cand_g, cfg_gate)
cfg <- mk_cfg()
c_diag <- E$src_check(A_good, cand_g, cfg)
chk(sprintf("T19 PBO 역할: 같은 후보(조정 p %.4f · PBO %.2f)가 진단 역할이면 통과 · gate 역할이면 PBO 표식이 막는다", c_diag$p_adj_candidate, c_diag$pbo$pbo),
    isTRUE(c_diag$pass) && isTRUE(c_diag$pbo$flagged) && isTRUE(E$src_gate(c_diag, c_diag$candidate_t, cfg, expected = EXP(c_diag))$ok) &&
      isTRUE(c_gate$pass_reality_check) && !isTRUE(c_gate$pass) && !isTRUE(E$src_gate(c_gate, c_gate$candidate_t, cfg_gate, expected = EXP(c_gate))$ok))

## ⑨ 폴더 적재
mkdir_trial <- function(id, dates, ret, bench) {
  d <- file.path(TD, id); dir.create(d, showWarnings = FALSE)
  fwrite(data.table(run_id = id, strategy_id = id, date = dates, frequency = "daily", ret_net = ret), file.path(d, "03_period_returns.csv"))
  fwrite(data.table(benchmark_id = "B", date = dates, benchmark_ret = bench), file.path(d, "05_benchmark_returns.csv"))
  d
}
set.seed(21); dts <- as.character(seq(as.Date("2015-01-01"), by = "day", length.out = 900L)); bm <- rnorm(900, 0, 0.01)
d1 <- mkdir_trial("cand", dts, bm + rnorm(900, 0.001, 0.005), bm)
d2 <- mkdir_trial("late", dts[301:900], bm[301:900] + rnorm(600, 0, 0.005), bm[301:900])
d3 <- mkdir_trial("full", dts, bm + rnorm(900, 0, 0.005), bm)
X <- E$src_load_trials(c(d2, d3), d1)
chk("T20 적재: 표본 = 후보의 날짜 · 늦게 시작한 시행의 없는 날은 활성 수익 0 · 채움 비율 기록",
    nrow(X$A) == 900L && identical(X$candidate, "cand") && all(X$A[1:300, "late"] == 0) && abs(X$fill_frac[["late"]] - 1 / 3) < 1e-9 && X$fill_frac[["full"]] == 0)
cd <- E$src_check_dirs(c(d2, d3), d1, cfg = cfg)
pr <- fread(file.path(d1, "03_period_returns.csv")); br <- fread(file.path(d1, "05_benchmark_returns.csv"))
chk("T21 폴더 점검의 후보 t = 그 폴더 수익으로 낸 계약 PORT_t", abs(cd$candidate_t - CE$.nw_t_mean(pr$ret_net - br$benchmark_ret, 3L)) < 1e-10 && cd$n_trials == 3L)
pth <- file.path(TD, "selection_reality_check.json"); E$src_write(cd, pth)
g_rt <- E$src_gate(E$src_read(pth), cd$candidate_t, cfg, expected = list(n_trials = 3L, ids = c("cand", "late", "full")))
g_mem <- E$src_gate(cd, cd$candidate_t, cfg, expected = list(n_trials = 3L, ids = c("cand", "late", "full")))
chk(sprintf("T22 저장 · 읽기 왕복 뒤에도 관문 판정 · 사유가 같다(시행 집합 지문 재계산 포함 · %s)", g_rt$reason),
    identical(isTRUE(g_rt$ok), isTRUE(g_mem$ok)) && identical(g_rt$reason, g_mem$reason) && isTRUE(g_mem$ok) == isTRUE(cd$pass))

## ⑩ 호출자 난수 상태 불변
set.seed(123); invisible(runif(3)); s0 <- .Random.seed
invisible(E$src_check(A_ind[, 1:5], "u1", cfg)); s1 <- .Random.seed
chk("T23 점검이 호출자의 난수 상태를 바꾸지 않는다", identical(s0, s1))

## ⑪ 설정 검증 · 돌연변이
bad_cfg <- function(mut) { j <- fromJSON(CFG_PATH, simplifyVector = FALSE); j$selection_bias <- mut(j$selection_bias)
  p <- file.path(TD, "bad.json"); writeLines(toJSON(j, auto_unbox = TRUE), p); inherits(try(E$src_cfg(path = p), silent = TRUE), "try-error") }
mk_cfg()
chk("T24 설정: 재표집 수 1000 미만 · alpha 범위 밖 · 어휘 밖 방법 · 홀수 분할은 멈춘다",
    bad_cfg(function(s) { s$resamples <- 500L; s }) && bad_cfg(function(s) { s$alpha <- 1.2; s }) &&
      bad_cfg(function(s) { s$method <- "bonferroni"; s }) && bad_cfg(function(s) { s$pbo$partitions <- 15L; s }))
src_txt <- readLines(SRC, warn = FALSE, encoding = "UTF-8")
needle <- "  if (K > 1L) for (j in (K - 1L):1L) mx[, j] <- pmax(mx[, j], mx[, j + 1L])"
hit <- which(src_txt == needle)
mut_txt <- src_txt; if (length(hit) == 1L) mut_txt[hit] <- "  # (돌연변이) 남은 가설들의 최댓값을 쓰지 않는다 — 다중 시행 보정 제거"
MF <- file.path(TD, "src_mutant.R"); writeLines(mut_txt, MF, useBytes = TRUE)
EM <- new.env(parent = globalenv()); sys.source(MF, envir = EM, keep.source = FALSE)
r_mut <- neg_rate(EM)
chk(sprintf("T25 돌연변이: 다중 시행 보정을 뺀 사본은 음성 대조를 크게 통과시킨다(통과율 %.2f > 0.5 · 원본 %.3f) — 치환 1곳 성사", r_mut, r_neg),
    length(hit) == 1L && r_mut > 0.5 && r_neg <= 0.15)

## ⑫ 시행 집합의 크기 · 구성 (G1 · 11-10) — 관문은 '그 선택에 영향을 줄 수 있었던 모든 칸'으로 점검했을 때만 통과를 낸다
cfg <- mk_cfg()
set.seed(4242); n <- 2500L; K <- 60L
Z <- matrix(rnorm(n * K, 0, 0.01), n, K, dimnames = list(NULL, paste0("w", 1:K)))
best <- colnames(Z)[which.max(E$src_nw(Z, 3L)$t)]
c_full <- E$src_check(Z, best, cfg)
c_one <- E$src_check(Z[, best, drop = FALSE], best, cfg)
chk(sprintf("T26a 전제: 잡음 60칸의 최고(t %.2f) — 60칸 점검 조정 p %.3f(미달) · 후보 1칸 점검 조정 p %.3f(통과로 보인다)",
            c_full$candidate_t, c_full$p_adj_candidate, c_one$p_adj_candidate), !isTRUE(c_full$pass) && isTRUE(c_one$pass))
g26 <- E$src_gate(c_one, c_one$candidate_t, cfg, expected = list(n_trials = 60L))
chk(sprintf("T26 관문: 등록 시행 60인데 후보 1칸만 넣은 점검은 거부(%s)", g26$reason), !isTRUE(g26$ok) && grepl("< 등록 시행 60", g26$reason, fixed = TRUE))
g27 <- E$src_gate(c_one, c_one$candidate_t, cfg, expected = list(ids = colnames(Z)))
chk(sprintf("T27 관문: 등록 시행 id 가 점검 집합에 빠져 있으면 거부(%s)", g27$reason), !isTRUE(g27$ok) && grepl("누락", g27$reason))
g28 <- E$src_gate(c_pos, c_pos$candidate_t, cfg)
chk(sprintf("T28 관문: 기대 시행 집합을 모르면 통과시키지 않는다(fail-closed · %s)", g28$reason), !isTRUE(g28$ok) && grepl("기대 시행", g28$reason) &&
      !isTRUE(E$src_gate(c_pos, c_pos$candidate_t, cfg, expected = list())$ok))
A_d <- cbind(A, zz = 0)
c_d <- E$src_check(A_d, "z7", cfg)
g29 <- E$src_gate(c_d, c_d$candidate_t, cfg, expected = list(n_trials = 41L, ids = colnames(A_d)))
chk(sprintf("T29 관문: 분산 0 으로 빠진 칸이 있으면 거부(빠진 칸 %s · %s)", paste(unlist(c_d$dropped_zero_variance), collapse = ","), g29$reason),
    identical(unlist(c_d$dropped_zero_variance), "zz") && isTRUE(c_d$pass) && !isTRUE(g29$ok) && grepl("분산 0", g29$reason))
d4 <- mkdir_trial("disj", as.character(seq(as.Date("2019-01-01"), by = "day", length.out = 300L)), rnorm(300, 0.002, 0.01), rnorm(300, 0, 0.01))
c_nx <- E$src_check_dirs(c(d2, d3, d4), d1, cfg = cfg)
g30 <- E$src_gate(c_nx, c_nx$candidate_t, cfg, expected = list(n_trials = 4L, ids = c("cand", "late", "full", "disj")))
chk(sprintf("T30 관문: 후보와 날짜가 하나도 안 겹치는 칸(채움 100%%)이 있으면 거부(%s)", g30$reason),
    "disj" %in% unlist(c_nx$dropped_zero_variance) && !isTRUE(g30$ok))
c_pad <- c_one; c_pad$trial_ids <- as.list(colnames(Z)); c_pad$n_trials <- 60L
g31 <- E$src_gate(c_pad, c_pad$candidate_t, cfg, expected = list(n_trials = 60L, ids = colnames(Z)))
chk(sprintf("T31 관문: 시행 id · 수만 부풀린 위조물은 지문(set_hash) 재계산이 막는다(%s)", g31$reason), !isTRUE(g31$ok) && grepl("지문", g31$reason))
g32 <- E$src_gate(c_full, c_full$candidate_t, cfg, expected = list(n_trials = 60L, ids = colnames(Z)))
chk(sprintf("T32 관문: 집합이 맞으면 구조 검사는 지나고 조정 p 로 판정한다(60칸 · %s)", g32$reason), !isTRUE(g32$ok) && grepl("^조정 p", g32$reason))
## 돌연변이 — 시행 집합 검사 줄을 하나씩 뺀 사본은 위 결함을 다시 연다(소스 텍스트 치환 · 치환 1곳 성사 단정)
mut_gate <- function(needle) {
  h <- which(grepl(needle, src_txt, fixed = TRUE))
  mt <- src_txt; if (length(h) == 1L) mt[h] <- "  # (돌연변이) 시행 집합 검사 1줄 제거"
  f <- file.path(TD, sprintf("src_mut_%d.R", sample.int(1e6, 1))); writeLines(mt, f, useBytes = TRUE)
  e <- new.env(parent = globalenv()); sys.source(f, envir = e, keep.source = FALSE); list(n = length(h), e = e)
}
m1 <- mut_gate("if (is.finite(ex_n) && nt < ex_n) return(no(")
chk("T33 돌연변이: 등록 시행 수 검사를 뺀 사본은 후보 1칸 점검을 통과시킨다(T26 이 그 차이를 본다)",
    m1$n == 1L && isTRUE(m1$e$src_gate(c_one, c_one$candidate_t, cfg, expected = list(n_trials = 60L))$ok))
m2 <- mut_gate("if (!is.finite(ex_n) && !length(ex_ids)) return(no(")
chk("T34 돌연변이: 기대 집합 미지정 검사를 뺀 사본은 기대 없이 통과시킨다(T28 이 그 차이를 본다)",
    m2$n == 1L && isTRUE(m2$e$src_gate(c_pos, c_pos$candidate_t, cfg)$ok))
m3 <- mut_gate("if (length(drp)) return(no(")
chk("T35 돌연변이: 분산 0 칸 검사를 뺀 사본은 빠진 칸이 있는 점검을 통과시킨다(T29 가 그 차이를 본다)",
    m3$n == 1L && isTRUE(m3$e$src_gate(c_d, c_d$candidate_t, cfg, expected = list(n_trials = 40L, ids = setdiff(colnames(A_d), "zz")))$ok))
## (G1 재수리 · 11-10) 채움 100% 가지를 따로 발화 — T30 에서는 분산 0 가지가 먼저 걸린다. 빠진 칸 목록만 지운 위조물(채움 기록은 남음)로
##   그 가지가 지문 검사보다 먼저 막는지 보고, 그 줄을 뺀 사본은 다른 사유(지문)로 넘어가는지 본다(방어선이 실제로 일한다는 양성 대조).
c_nf <- c_nx; c_nf$dropped_zero_variance <- list()
g36 <- E$src_gate(c_nf, c_nf$candidate_t, cfg, expected = list(n_trials = 3L, ids = c("cand", "late", "full")))
chk(sprintf("T36 관문: 빠진 칸 목록을 지워도 채움 100%% 기록이 있으면 거부(채움 %.2f · %s)", as.numeric(c_nx$fill$max_fill_frac), g36$reason),
    isTRUE(as.numeric(c_nx$fill$max_fill_frac) >= 1) && !isTRUE(g36$ok) && grepl("채움 100%", g36$reason, fixed = TRUE))
##   이 검사는 두 줄(if · return)이라 if 줄을 주석으로 바꾸면 return 이 무조건 실행된다 — if 줄을 'if (FALSE)' 로 바꾼다
m4 <- local({ h <- which(grepl("if (is.list(check$fill) && is.finite(num(check$fill$max_fill_frac))", src_txt, fixed = TRUE))
  mt <- src_txt; if (length(h) == 1L) mt[h] <- "  if (FALSE)   # (돌연변이) 채움 100% 검사 끔"
  f <- file.path(TD, "src_mut_fill.R"); writeLines(mt, f, useBytes = TRUE)
  e <- new.env(parent = globalenv()); sys.source(f, envir = e, keep.source = FALSE); list(n = length(h), e = e) })
g37 <- m4$e$src_gate(c_nf, c_nf$candidate_t, cfg, expected = list(n_trials = 3L, ids = c("cand", "late", "full")))
chk(sprintf("T37 돌연변이: 채움 100%% 검사를 뺀 사본은 그 사유를 내지 않는다(T36 이 그 차이를 본다 · 사본 사유 %s) — 치환 1곳 성사", g37$reason),
    m4$n == 1L && !grepl("채움 100%", g37$reason, fixed = TRUE))

unlink(TD, recursive = TRUE)
cat(sprintf("\n%s\n", toJSON(list(test = "test_selection_reality_check", pass = pass, fail = fail, total = pass + fail), auto_unbox = TRUE)))
quit(status = if (fail > 0L) 1L else 0L)
