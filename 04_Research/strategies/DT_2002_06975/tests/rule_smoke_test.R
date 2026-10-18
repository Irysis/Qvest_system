## =============================================================================
## rule_smoke_test.R — DT 규칙 블록 스모크 시험(합성 예측표 · DNN 학습 없음 · 데이터 파일 미사용)
##   생성 엔진 7개(engine_<규칙>.R) 각각에서 실제 구역 코드(ident · dt_const · rule_fns · r_pc_assert · r_rule · sigma252)를
##   표지로 잘라 격리 환경에서 실행하고, 기대값은 시험 쪽에서 독립 재도출한다(엔진 함수를 기대값 계산에 쓰지 않는다).
##   단언: 규칙별 점수 식 · V1/N1/S1 거부 수(동률 평균 순위 포함 — 서로 다른 값 = ⌊0.2N⌋ · 경계 걸친 동률 = 통째 통과) ·
##         N1/N2 순열 재현성(같은 시드 → 같은 결과 · 전역 난수 상태 복원(있음/없음 두 경우) · 접두 안정 · null_perm 규약 재도출 일치) ·
##         S1/S2 σ 재배정 단조성 · 다중집합 보존 · σ 결측 = 그날 s 중앙값 · NA 처리(분위 비유한 행 = 점수 NA · N 에서 제외 · 예측표 제외) ·
##         S_hist(자기 이력 폭 짝 D^H — 철학 P1 C-20261018-065): 재배정 단조성 · 다중집합 · h 결측 = 중앙값 · hist252 구역 = 독립 계산 ·
##         실현 라벨 경계(lab_i ≤ u) — 경계를 지운 뮤턴트(소스 텍스트 치환)를 경계 단언이 잡는다 · 엔진 시동 검산도 그 뮤턴트에서 멈춘다 ·
##         예측표(이름 · 열 13개 · 실현 라벨 없음 · 로그 줄 · 7 엔진 같은 파일 · 내용이 다르면 중단 · σ/h/키 바뀌면 이름 바뀜) · FACTORS 전달(원본 조립 줄) ·
##         양성 대조 R 재단언(통과 · 미달 · 판본 불일치 · 열 부재) · σ 구역(독립 계산 일치 · 창 끝 t−1 · MEM 신호일만 · .G 불변) ·
##         템플릿 가드(.DT_RULE = TEMPLATE 이면 멈춤) · 거부 몫 = 1/.QUINT 단언.
## 실행: Rscript tests/rule_smoke_test.R     (종료 코드 0 = 단언 전부 통과)
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
for (p in c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""))) if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/hooks/qvest_hook_router.py"))) { ROOT <- gsub("\\\\", "/", p); break }
DT_DIR <- file.path(ROOT, "04_Research/strategies/DT_2002_06975")
OUT <- file.path(DT_DIR, "tests", "_out", "rule_smoke")
unlink(OUT, recursive = TRUE); dir.create(file.path(OUT, "qpred"), recursive = TRUE, showWarnings = FALSE)
RULES <- c("Q50", "V1", "V2", "N1", "N2", "S1", "S2")
CV <- "DT_2002_06975/dnn_quantile/rev1"

R <- list()
chk <- function(name, ok, detail = "") {
  R[[length(R) + 1L]] <<- list(name = name, ok = isTRUE(ok), detail = detail)
  cat(sprintf("[rule-smoke] %-4s %s%s\n", if (isTRUE(ok)) "OK" else "FAIL", name, if (nzchar(detail)) paste0(" — ", detail) else ""))
}
expect_error <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")

## ── 구역 추출 ──
read_lines <- function(p) readLines(p, encoding = "UTF-8", warn = FALSE)
zone_text <- function(lines, name) {
  s <- grep(sprintf("^## >>> DT_ZONE %s orig=", name), lines); e <- grep(sprintf("^## <<< DT_ZONE %s$", name), lines)
  if (length(s) != 1L || length(e) != 1L || e <= s) stop("구역 추출 실패: ", name)
  paste(lines[(s + 1L):(e - 1L)], collapse = "\n")
}
eval_zone <- function(lines, name, env) eval(parse(text = zone_text(lines, name), keep.source = FALSE, encoding = "UTF-8"), envir = env)
py_src_expr <- function(path) {                       # 엔진의 .PY_SRC 대입문(실물)을 그대로 쓴다
  ex <- parse(path, keep.source = FALSE, encoding = "UTF-8")
  h <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name(".PY_SRC")), as.list(ex))
  if (length(h) != 1L) stop(".PY_SRC 대입문이 1개가 아니다")
  h[[1]]
}
sandbox <- function(lines, quint = 5L) {
  env <- new.env(parent = globalenv())
  env$.QUINT <- quint
  eval_zone(lines, "ident", env); eval_zone(lines, "dt_const", env)
  out <- capture.output(eval_zone(lines, "rule_fns", env))
  attr(env, "rule_fns_out") <- out
  env
}

## ── 합성 입력(시험 자체 난수 · 엔진 호출 전에 만든다) ──
set.seed(20261018)
bd <- seq(as.Date("2005-01-03"), as.Date("2005-04-29"), by = "day"); bd <- bd[!(as.POSIXlt(bd)$wday %in% c(0L, 6L))]
CAL <- data.table(Date = bd, di = seq_along(bd))
SIGD <- as.Date(c("2005-01-31", "2005-02-28", "2005-03-31", "2005-04-29"))
stopifnot(all(SIGD %in% CAL$Date))
PI <- CAL[match(SIGD, Date), di]
mk_day <- function(pi, n, q10) {
  q50 <- q10 + runif(n, 0.02, 0.3); q90 <- q50 + runif(n, 0.02, 0.3)
  raw <- cbind(q10, q50, q90); sw <- sample.int(n, max(1L, n %/% 10L)); raw[sw, 1:2] <- raw[sw, 2:1]   # 날 머리 교차(재배열 전 값만)
  data.table(pred_i = pi, Ticker = sprintf("A%06d", sample(100000:999999, n)), q10_raw = raw[, 1], q50_raw = raw[, 2], q90_raw = raw[, 3],
             q10 = q10, q50 = q50, q90 = q90)
}
d1 <- mk_day(PI[1], 100L, runif(100, 0.05, 0.6))                                   # 서로 다른 100값 → V1 거부 20
d2 <- mk_day(PI[2], 40L, runif(40, 0.05, 0.6))                                     # 37 유효 + 3 비유한 → 거부 ⌊0.2·37⌋ = 7
d2[38:40, c("q10", "q50", "q90") := .(NA_real_, q50, q90)]; d2[39, q50 := NaN]; d2[40, q90 := Inf]
q3 <- c(sort(runif(18, 0.05, 0.2)), rep(0.25, 4), sort(runif(78, 0.3, 0.6)))       # 순위 19~22 동률(평균 20.5 → 0.205 > 0.2) → 거부 18
d3 <- mk_day(PI[3], 100L, sample(q3))
q4 <- c(rep(0.04, 3), sort(runif(47, 0.1, 0.6)))                                   # 순위 1~3 동률(평균 2 → 0.04) → 거부 10
d4 <- mk_day(PI[4], 50L, sample(q4))
PR0 <- rbindlist(list(d1, d2, d3, d4))
SIG0 <- PR0[, .(Ticker, pred_i, sigma252 = runif(.N, 0.01, 0.05))]
SIG0[sample.int(.N, 12L), sigma252 := NA_real_]                                    # σ 결측 12행
SIG0 <- SIG0[-c(5L, 150L)]                                                         # σ 표에 없는 종목 2행(조인 뒤 NA)
HIST0 <- PR0[, .(Ticker, pred_i, h_hist = runif(.N, 0.05, 0.4))]
HIST0[sample.int(.N, 9L), h_hist := NA_real_]                                      # h 결측 9행
HIST0 <- HIST0[-c(7L, 220L)]                                                       # h 표에 없는 종목 2행(조인 뒤 NA)
SCH0 <- data.table(Date = SIGD, pred_i = PI)
DG0 <- data.table(k = 1:4, pred_i = PI, n_train = 1000L, n_pred = c(100L, 40L, 100L, 50L), cache_key = sprintf("%040d", 1:4),
                  cross_rate = c(0.01, 0, 0.02, 0.1), code_version = CV, n_inputs = 31L,
                  pc_raw_rho10 = 0.98, pc_raw_rho50 = 0.98, pc_raw_rho90 = 0.97, pc_rea_rho10 = 0.98, pc_rea_rho50 = 0.98, pc_rea_rho90 = 0.97,
                  pc_raw_cov10 = 0.10, pc_rea_cov10 = 0.10, pc_raw_cov90 = 0.90, pc_rea_cov90 = 0.90, pc_pass = TRUE)
EXP_VETO_V1 <- c(20L, 7L, 18L, 10L)

## ── 독립 기대값 ──
exp_veto <- function(d, q, share) {
  out <- rep(NA, length(q))
  for (dd in unique(d)) { ix <- which(d == dd & is.finite(q)); out[ix] <- rank(q[ix], ties.method = "average") / length(ix) <= share }
  out
}
exp_perm <- function(d, tk, s, start, seed) {           # rf_cell_engine.R null_perm 규약(305-323행)의 재도출
  ud <- sort(unique(d))
  mi <- (as.integer(format(ud, "%Y")) - as.integer(format(start, "%Y"))) * 12L + (as.integer(format(ud, "%m")) - as.integer(format(start, "%m")))
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  ms <- as.integer(floor(stats::runif(max(mi) + 1L) * 2147483646)) + 1L
  out <- rep(NA_real_, length(s))
  for (j in seq_along(ud)) {
    ix <- which(d == ud[j]); ix <- ix[order(tk[ix], method = "radix")]
    set.seed(ms[mi[j] + 1L], kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
    out[ix] <- s[ix][sample.int(length(ix))]
  }
  out
}
exp_sigma <- function(d, tk, s, sig) {
  out <- rep(NA_real_, length(s))
  for (dd in unique(d)) {
    ix <- which(d == dd); val <- ix[!is.na(sig[ix])]
    out[setdiff(ix, val)] <- median(s[ix])
    out[val[order(sig[val], tk[val], method = "radix")]] <- sort(s[val])
  }
  out
}

## ── 한 엔진의 규칙 블록 실행 ──
run_rule <- function(lines, env, PR = PR0, SIG = SIG0, SCH = SCH0, DG = DG0, start = as.Date("2005-01-01"), HIST = HIST0) {
  env$.PR <- copy(PR); env$.DT_SIG <- copy(SIG); env$.SCH <- copy(SCH); env$.DG <- copy(DG); env$.CAL <- copy(CAL); env$.DT_HIST <- copy(HIST)
  env$.START <- start; env$.QD <- file.path(OUT, "qpred"); env$.DT_CODE_VERSION <- CV
  out <- capture.output(eval_zone(lines, "r_rule", env))
  ## 원본 조립의 FACTORS 줄(구역 밖 · 엔진 파일에서 그대로 가져온다)
  fl <- grep("^FACTORS <- \\.PR\\[is\\.finite\\(Score\\) & !is\\.na\\(Date\\), \\.\\(Date, Ticker, Score\\)\\]$", lines, value = TRUE)
  if (length(fl) != 1L) stop("FACTORS 조립 줄을 엔진에서 찾지 못함")
  eval(parse(text = fl), envir = env)
  list(out = out, PR = env$.PR, FACTORS = env$FACTORS, QP = env$.DT_QP)
}

eng_paths <- file.path(DT_DIR, sprintf("engine_%s.R", RULES)); names(eng_paths) <- RULES
qp_md5 <- NULL; qp_path <- NULL
for (rule in RULES) {
  L <- read_lines(eng_paths[[rule]])
  env <- sandbox(L)
  chk(sprintf("%s ident · dt_const 상수", rule),
      identical(env$.DT_RULE, rule) && identical(env$.TAG, sprintf("[DT_2002_06975:%s]", rule)) && identical(env$.DT_TAUS, c(0.1, 0.5, 0.9)) &&
        identical(env$.DT_VETO_SHARE, 0.2) && identical(env$.DT_PERM_SEED, 20261018L) && identical(env$.DT_SIGMA_WIN, 252L) && identical(env$.DT_SIGMA_MIN, 126L))
  chk(sprintf("%s rule_fns 시동 검산", rule), any(grepl("규칙 함수 검산 통과", attr(env, "rule_fns_out"), fixed = TRUE)))
  ## 전역 난수 상태 복원(있음)
  set.seed(777); rs0 <- .Random.seed; rk0 <- RNGkind()
  a <- run_rule(L, env)
  chk(sprintf("%s 전역 난수 상태 복원(.Random.seed 있음)", rule), identical(rs0, .Random.seed) && identical(rk0, RNGkind()))
  P <- a$PR; ok_rows <- P$dt_ok %in% TRUE
  ## NA 처리
  chk(sprintf("%s NA 처리(분위 비유한 3행 = 점수 NA · 예측표 제외)", rule),
      sum(!ok_rows) == 3L && all(is.na(P$Score[!ok_rows])) && all(is.na(P$s[!ok_rows])) && sum(ok_rows) == 287L)
  U <- P[ok_rows]
  ## s · s_perm · s_sigma 독립 재도출(규칙 무관)
  s_exp <- U$q50 - U$q10
  sp_exp <- exp_perm(U$Date, U$Ticker, U$s, as.Date("2005-01-01"), 20261018L)
  ss_exp <- exp_sigma(U$Date, U$Ticker, U$s, U$sigma252)
  chk(sprintf("%s s = q50 − q10 ≥ 0", rule), isTRUE(all.equal(U$s, s_exp, tolerance = 0)) && all(U$s >= 0))
  chk(sprintf("%s s_perm = null_perm 규약 재도출", rule), identical(U$s_perm, sp_exp))
  chk(sprintf("%s s_sigma = σ 재배정 재도출", rule), identical(U$s_sigma, ss_exp))
  sh_exp <- exp_sigma(U$Date, U$Ticker, U$s, U$h_hist)
  chk(sprintf("%s s_hist = h 재배정 재도출(σ 와 같은 재배정 규칙)", rule), identical(U$s_hist, sh_exp))
  ## 점수 식
  sc_exp <- switch(rule,
    Q50 = U$q50, V2 = U$q10, N2 = U$q50 - U$s_perm, S2 = U$q50 - U$s_sigma,
    V1 = ifelse(exp_veto(U$Date, U$q10, 0.2), NA_real_, U$q50),
    N1 = ifelse(exp_veto(U$Date, U$q50 - U$s_perm, 0.2), NA_real_, U$q50),
    S1 = ifelse(exp_veto(U$Date, U$q50 - U$s_sigma, 0.2), NA_real_, U$q50))
  chk(sprintf("%s 점수 식(독립 재도출과 일치)", rule), identical(U$Score, as.numeric(sc_exp)))
  nveto <- U[, sum(is.na(Score)), by = Date][order(Date), V1]
  want <- switch(rule, V1 = EXP_VETO_V1, N1 = c(20L, 7L, 20L, 10L), S1 = c(20L, 7L, 20L, 10L), c(0L, 0L, 0L, 0L))
  chk(sprintf("%s 거부 수 신호일별 %s(기대 %s)", rule, paste(nveto, collapse = "/"), paste(want, collapse = "/")), identical(as.integer(nveto), want))
  ## FACTORS 전달 — 점수 유한 행만(거부 = 후보에서 빠진다 · 셀 엔진 !is.na(.base_sig))
  chk(sprintf("%s FACTORS = 점수 유한 행 %d", rule, nrow(a$FACTORS)), nrow(a$FACTORS) == sum(is.finite(U$Score)) && !anyNA(a$FACTORS$Score) &&
        identical(names(a$FACTORS), c("Date", "Ticker", "Score")))
  ## 예측표
  ln <- grep("^\\[DT qpred\\] path=", a$out, value = TRUE)
  m <- regmatches(ln, regexec("^\\[DT qpred\\] path=(.+) rows=([0-9]+) months=([0-9]+)$", ln))[[1]]
  q <- if (length(m) == 4L && file.exists(m[2])) as.data.table(read_parquet(m[2], mmap = FALSE)) else NULL
  chk(sprintf("%s 예측표 로그 줄 · 이름 · 열 13 · 행 287 · 4개월 · 라벨 없음", rule),
      length(ln) == 1L && !is.null(q) && grepl("^[0-9a-f]{8}_[0-9a-f]{8}\\.parquet$", basename(m[2])) &&
        identical(names(q), c("Date", "Ticker", "q10", "q50", "q90", "q10_raw", "q50_raw", "q90_raw", "s_perm", "s_sigma", "sigma252", "s_hist", "h_hist")) &&
        nrow(q) == 287L && as.integer(m[3]) == 287L && as.integer(m[4]) == 4L && uniqueN(q$Date) == 4L &&
        !any(grepl("^y|label|ret|fwd", names(q), ignore.case = TRUE)), if (length(m) == 4L) basename(m[2]) else "로그 줄 없음")
  if (is.null(qp_md5)) { qp_md5 <- unname(tools::md5sum(m[2])); qp_path <- m[2] }
  else chk(sprintf("%s 예측표 = 앞 엔진과 같은 파일 · 같은 내용(규칙 무관)", rule),
           identical(m[2], qp_path) && identical(unname(tools::md5sum(m[2])), qp_md5) && any(grepl("기존 파일과 내용 일치", a$out, fixed = TRUE)))
  ## σ 재배정 성질
  ok_mono <- all(vapply(split(seq_len(nrow(U)), U$Date), function(ix) {
    v <- ix[!is.na(U$sigma252[ix])]; o <- v[order(U$sigma252[v], U$Ticker[v], method = "radix")]
    !is.unsorted(U$s_sigma[o]) && isTRUE(all.equal(sort(U$s_sigma[v]), sort(U$s[v]), tolerance = 0)) &&
      all(U$s_sigma[setdiff(ix, v)] == median(U$s[ix]))
  }, logical(1)))
  chk(sprintf("%s σ 재배정 단조 · 다중집합 보존 · 결측 = 중앙값(σ 결측 %d행)", rule, sum(is.na(U$sigma252))), ok_mono && sum(is.na(U$sigma252)) >= 2L)
  ## s_hist 재배정 성질(단조 · 다중집합 · h 결측 = 중앙값) — C-20261018-065 단언 ①
  ok_mono_h <- all(vapply(split(seq_len(nrow(U)), U$Date), function(ix) {
    v <- ix[!is.na(U$h_hist[ix])]; o <- v[order(U$h_hist[v], U$Ticker[v], method = "radix")]
    !is.unsorted(U$s_hist[o]) && isTRUE(all.equal(sort(U$s_hist[v]), sort(U$s[v]), tolerance = 0)) &&
      all(U$s_hist[setdiff(ix, v)] == median(U$s[ix]))
  }, logical(1)))
  chk(sprintf("%s s_hist 재배정 단조(h 큰 종목에 큰 s) · 다중집합 보존 · h 결측 = 중앙값(h 결측 %d행)", rule, sum(is.na(U$h_hist))),
      ok_mono_h && sum(is.na(U$h_hist)) >= 2L && !identical(U$s_hist, U$s_sigma))
  ## 순열 성질
  ok_perm <- all(vapply(split(seq_len(nrow(U)), U$Date), function(ix) isTRUE(all.equal(sort(U$s_perm[ix]), sort(U$s[ix]), tolerance = 0)), logical(1))) &&
    any(U$s_perm != U$s)
  chk(sprintf("%s 순열 = 날짜별 다중집합 보존 · 실제로 섞임", rule), ok_perm)
}

## ── 규칙 무관 단언(엔진 하나로) ──
L <- read_lines(eng_paths[["N2"]]); env <- sandbox(L)
## 재현성 + 전역 난수 상태 없음 경우(RNGkind() 조회가 상태를 만들 수 있으므로 조회 → 삭제 → 실행 → 존재 확인 → 조회 순)
rk0 <- RNGkind()
if (exists(".Random.seed", envir = globalenv())) rm(".Random.seed", envir = globalenv())
a1 <- run_rule(L, env)
absent_after <- !exists(".Random.seed", envir = globalenv())
chk("N2 전역 난수 상태 복원(.Random.seed 없음 → 없음 · RNGkind 동일)", absent_after && identical(rk0, RNGkind()))
a2 <- run_rule(L, env)
chk("N2 같은 시드 → 같은 순열(두 번 실행)", identical(a1$PR$s_perm, a2$PR$s_perm) && identical(a1$PR$Score, a2$PR$Score))
## 접두 안정 — 앞 3개월만 넣어도 그 달들의 순열이 같다
a3 <- run_rule(L, env, PR = PR0[pred_i %in% PI[1:3]], SCH = SCH0[1:3], DG = DG0[1:3])
m3 <- a1$PR[pred_i %in% PI[1:3] & dt_ok %in% TRUE, .(pred_i, Ticker, s_perm)][a3$PR[dt_ok %in% TRUE, .(pred_i, Ticker, s_perm)], on = .(pred_i, Ticker)]
chk("N2 접두 안정(뒤 달을 빼도 앞 달 순열 그대로)", nrow(m3) == 237L && identical(m3$s_perm, m3$i.s_perm))
## 시드 검정력 — 다른 주 시드면 순열이 달라진다
env2 <- sandbox(L); env2$.DT_PERM_SEED <- 1L
a4 <- run_rule(L, env2)
chk("N2 다른 주 시드 → 다른 순열(검정력) · 예측표 이름도 바뀐다(짝 상수 = 지문)", !identical(a1$PR$s_perm, a4$PR$s_perm) && !identical(basename(a4$QP), basename(a1$QP)))
## 결정론 가드 — 같은 이름의 예측표 내용이 다르면 멈춘다
qp <- a1$QP; bak <- tempfile(fileext = ".parquet"); invisible(file.copy(qp, bak))
tam <- as.data.table(read_parquet(qp, mmap = FALSE)); invisible(gc()); tam[1, q50 := q50 + 1e-9]; write_parquet(tam, qp)
chk("예측표 같은 지문 · 다른 내용 → 중단", expect_error(run_rule(L, env)))
invisible(file.copy(bak, qp, overwrite = TRUE)); unlink(bak)
## 데이터가 바뀌면 다른 이름(지문)
SIGb <- copy(SIG0); SIGb[1, sigma252 := sigma252 * 1.01]
a5 <- run_rule(L, env, SIG = SIGb)
chk("σ 표가 바뀌면 예측표 이름(데이터 지문)이 바뀐다", !identical(basename(a5$QP), basename(a1$QP)))
HISTb <- copy(HIST0); HISTb[1, h_hist := h_hist * 1.01]
a7 <- run_rule(L, env, HIST = HISTb)
chk("h 표가 바뀌면 예측표 이름(데이터 지문)이 바뀐다", !identical(basename(a7$QP), basename(a1$QP)))
DGb <- copy(DG0); DGb[2, cache_key := sprintf("%040d", 99L)]
a6 <- run_rule(L, env, DG = DGb)
chk("달 캐시 키가 바뀌면 예측표 이름이 바뀐다", !identical(basename(a6$QP), basename(a1$QP)))

## ── 양성 대조 R 재단언(r_pc_assert) ──
pc_run <- function(DG, py = NULL) {
  e <- sandbox(L); e$.DG <- copy(DG)
  if (is.null(py)) eval(py_src_expr(eng_paths[["N2"]]), envir = e) else e$.PY_SRC <- py
  eval_zone(L, "r_pc_assert", e); e
}
e_ok <- tryCatch(pc_run(DG0), error = function(x) x)
chk("r_pc_assert 통과 기록 → 통과 · CODE_VERSION 추출", !inherits(e_ok, "error") && identical(e_ok$.DT_CODE_VERSION, CV))
for (bad in list(list("pc_raw_cov10", 0.9), list("pc_rea_cov90", 0.5), list("pc_raw_rho90", 0.79), list("pc_rea_rho10", NA_real_), list("pc_pass", FALSE))) {
  DGx <- copy(DG0); set(DGx, j = bad[[1]], value = bad[[2]])
  chk(sprintf("r_pc_assert 미달 %s = %s → 중단", bad[[1]], format(bad[[2]])), expect_error(pc_run(DGx)))
}
DGx <- copy(DG0); DGx[, code_version := "RP_AUTO_2002_06975/dnn_rolling/rev3"]
chk("r_pc_assert 판본 불일치 → 중단", expect_error(pc_run(DGx)))
DGx <- copy(DG0); DGx[, pc_raw_rho50 := NULL]
chk("r_pc_assert 기록 열 부재 → 중단", expect_error(pc_run(DGx)))

## ── σ 구역(sigma252) — 독립 계산 · 창 끝 t−1 · MEM 신호일만 · .G 불변 ──
set.seed(5)
gd <- seq(as.Date("2003-01-01"), as.Date("2005-06-30"), by = "day"); gd <- gd[!(as.POSIXlt(gd)$wday %in% c(0L, 6L))]
nd <- length(gd)
G <- rbindlist(lapply(c("A000010", "A000020", "A000030"), function(tk) {
  cl <- 100 * exp(cumsum(rnorm(nd, 0, 0.02)))
  if (tk == "A000020") cl[300:340] <- NA                                     # 거래 정지 구간
  if (tk == "A000030") cl[1:(nd - 200)] <- NA                                # 늦게 상장 → 유효 관측 부족
  data.table(Ticker = tk, Date = gd, di = seq_len(nd), Close = cl, MEM = TRUE)
}))
G[Ticker == "A000010" & di %in% 600:620, MEM := FALSE]                       # 비적격 기간
me <- data.table(Date = gd, di = seq_len(nd))[, .(di = max(di)), by = .(format(Date, "%Y%m"))]$di
SCHg <- data.table(pred_i = me[me > 300])
p_t1 <- SCHg$pred_i[5]; G[Ticker == "A000010" & di == p_t1, Close := Close * 10]   # 신호일 당일 급등 — t−1 창이면 그날 σ 에 안 들어간다
G0 <- copy(G)
eg <- sandbox(L); eg$.G <- G; eg$.SCH <- SCHg
sig_log <- capture.output(eval_zone(L, "sigma252", eg))
S <- eg$.DT_SIG
exp_s <- rbindlist(lapply(split(G0, G0$Ticker), function(g) {
  pts <- SCHg$pred_i[g$MEM[SCHg$pred_i]]
  data.table(Ticker = g$Ticker[1], pred_i = pts, sigma252 = vapply(pts, function(p) {
    j <- (p - 252L):(p - 1L); j <- j[j >= 2L]
    r <- log(g$Close[j] / g$Close[j - 1L]); r <- r[is.finite(r)]
    if (length(r) >= 126L) sd(r) else NA_real_ }, numeric(1)))
}))
setorder(S, Ticker, pred_i); setorder(exp_s, Ticker, pred_i)
chk(sprintf("σ 구역 = 독립 계산(%d행 · 결측 %d)", nrow(S), sum(is.na(S$sigma252))),
    identical(S$Ticker, exp_s$Ticker) && identical(S$pred_i, exp_s$pred_i) && isTRUE(all.equal(S$sigma252, exp_s$sigma252, tolerance = 1e-12)))
chk(sprintf("σ 구역 MEM 아닌 신호일 제외(비적격 신호일 %d)", sum(SCHg$pred_i %in% 600:620)), any(SCHg$pred_i %in% 600:620) &&
      nrow(S[Ticker == "A000010" & pred_i %in% 600:620]) == 0L && nrow(S[Ticker == "A000010"]) == sum(!(SCHg$pred_i %in% 600:620)))
chk("σ 구역 늦은 상장 = 유효 관측 부족 → NA 포함", any(is.na(S[Ticker == "A000030", sigma252])) && any(is.finite(S[Ticker == "A000030", sigma252])))
s_at <- S[Ticker == "A000010" & pred_i == p_t1, sigma252]; s_next <- S[Ticker == "A000010" & pred_i == SCHg$pred_i[6], sigma252]
chk(sprintf("σ 창 끝 t−1(신호일 당일 10배 급등 미반영 %.4f · 다음 신호일 반영 %.4f)", s_at, s_next), s_at < 0.05 && s_next > 0.1)
chk("σ 구역이 .G 를 바꾸지 않는다(열 · 값 · 행 순서)", identical(names(G0), names(eg$.G)) && identical(as.list(G0), as.list(eg$.G)))

## ── 자기 이력 폭 구역(hist252) — 독립 계산 · 실현 라벨 경계(lab_i ≤ u) · 경계 제거 뮤테이션 검출 · .P 불변 (C-20261018-065 단언 ②) ──
set.seed(9)
nd2 <- 700L
mkP <- function(tk, from = 1L, gap = integer(0)) {
  di <- setdiff(from:nd2, gap)
  y <- runif(length(di), 0.02, 1); lab <- di + 5L
  tl <- di > nd2 - 5L; y[tl] <- NA_real_; lab[tl] <- NA_integer_                  # 마지막 5일 = 미실현(엔진 규약: y 비유한 ⇒ lab_i NA)
  data.table(Ticker = tk, di = as.integer(di), y = y, lab_i = as.integer(lab))
}
PP <- rbindlist(list(mkP("A000010"), mkP("A000020", gap = 300:360), mkP("A000030", from = 500L)))
PP[sample.int(.N, 40L), y := NA_real_]; PP[is.na(y), lab_i := NA_integer_]
SCHh <- data.table(pred_i = as.integer(seq(320L, 695L, by = 21L)))
SCHh[, u_i := pred_i - (seq_len(.N) %% 5L)]                                         # u ∈ [p − 4, p]
## 각 신호일 직전 '그 신호일 u 까지 미실현'인 행(di ∈ (u − 5, p − 1] ⇒ lab_i > u)을 극단 좌꼬리 값으로 — 경계를 어기면 h 가 반드시 달라진다
for (j in seq_len(nrow(SCHh))) PP[di > SCHh$u_i[j] - 5L & di <= SCHh$pred_i[j] - 1L & !is.na(y), y := 1e-6]
exp_h_fun <- function(leak) rbindlist(lapply(split(PP, PP$Ticker), function(g) {
  pts <- SCHh$pred_i[SCHh$pred_i %in% g$di]
  data.table(Ticker = g$Ticker[1], pred_i = pts, h_hist = vapply(pts, function(p) {
    u <- SCHh$u_i[SCHh$pred_i == p]
    keep <- g$di >= p - 252L & g$di <= p - 1L & is.finite(g$y) & (leak | (!is.na(g$lab_i) & g$lab_i <= u))
    v <- g$y[keep]
    if (length(v) >= 126L) unname(median(v) - quantile(v, 0.1, type = 7)) else NA_real_ }, numeric(1)))
}))
exp_h <- exp_h_fun(FALSE); leak_h <- exp_h_fun(TRUE)
setorder(exp_h, Ticker, pred_i); setorder(leak_h, Ticker, pred_i)
fin <- is.finite(exp_h$h_hist)
chk(sprintf("자기 이력 폭 시험 검정력 — 경계를 어긴 기대값이 유한 h %d점 모두에서 다르다", sum(fin)),
    sum(fin) >= 20L && all(exp_h$h_hist[fin] != leak_h$h_hist[fin]) && any(!fin))
PP0 <- copy(PP)
eh <- sandbox(L); eh$.P <- PP; eh$.SCH <- SCHh
hist_log <- capture.output(eval_zone(L, "hist252", eh))
Hc <- copy(eh$.DT_HIST); setorder(Hc, Ticker, pred_i)
chk(sprintf("hist252 구역 = 독립 계산(%d행 · 결측 %d) — 실현 라벨 경계 lab_i ≤ u", nrow(Hc), sum(is.na(Hc$h_hist))),
    identical(Hc$Ticker, exp_h$Ticker) && identical(Hc$pred_i, exp_h$pred_i) && isTRUE(all.equal(Hc$h_hist, exp_h$h_hist, tolerance = 1e-12)))
chk("hist252 구역이 .P 를 바꾸지 않는다(열 · 값 · 행 순서)", identical(names(PP0), names(eh$.P)) && identical(as.list(PP0), as.list(eh$.P)))
## 뮤테이션: .dt_hist_at 의 실현 라벨 경계를 지운다(소스 텍스트 치환 · 치환 성사 단정) → u 뒤 라벨이 h 에 들어간다
zt <- zone_text(L, "rule_fns"); old_b <- "!is.na(lab[k]) & lab[k] <= us[j] & "
n_b <- lengths(regmatches(zt, gregexpr(old_b, zt, fixed = TRUE)))
ztm <- sub(old_b, "", zt, fixed = TRUE)
subst_ok <- n_b == 1L && !identical(zt, ztm) && !grepl(old_b, ztm, fixed = TRUE)
exm <- parse(text = ztm, keep.source = FALSE, encoding = "UTF-8")
defm <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name(".dt_hist_at")), as.list(exm))
em <- sandbox(L); eval(defm[[1]], envir = em); em$.P <- copy(PP); em$.SCH <- SCHh
invisible(capture.output(eval_zone(L, "hist252", em)))
Hm <- copy(em$.DT_HIST); setorder(Hm, Ticker, pred_i)
mut_caught <- !isTRUE(all.equal(Hm$h_hist, exp_h$h_hist, tolerance = 1e-12))
chk(sprintf("뮤테이션(실현 라벨 경계 제거 · 치환 %d회) → 경계 단언이 잡는다(뮤턴트 h ≠ 기대 h) · 뮤턴트 = 누출 기대값", n_b),
    subst_ok && length(defm) == 1L && mut_caught && isTRUE(all.equal(Hm$h_hist, leak_h$h_hist, tolerance = 1e-12)))
eg2 <- new.env(parent = globalenv()); eg2$.QUINT <- 5L; eval_zone(L, "ident", eg2); eval_zone(L, "dt_const", eg2)
chk("뮤턴트 rule_fns 는 엔진 시동 검산(자기 이력 폭)에서도 멈춘다", expect_error(capture.output(eval(parse(text = ztm, keep.source = FALSE, encoding = "UTF-8"), envir = eg2))))

## ── 가드 ──
LT <- read_lines(file.path(DT_DIR, "engine_template.R"))
chk("템플릿(.DT_RULE = TEMPLATE)은 ident 구역에서 멈춘다", expect_error(sandbox(LT)))
chk("거부 몫 ≠ 1/.QUINT 이면 dt_const 구역이 멈춘다", expect_error(sandbox(L, quint = 4L)))

ok <- all(vapply(R, function(z) z$ok, logical(1)))
writeLines(toJSON(list(ok = ok, n = length(R), n_ok = sum(vapply(R, function(z) z$ok, logical(1))), checks = R,
                       qpred_example = basename(qp_path %||% ""), at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")), auto_unbox = TRUE, pretty = TRUE),
           file.path(DT_DIR, "tests", "_out", "rule_smoke_results.json"))
cat(sprintf("[rule-smoke] %s — 단언 %d 중 통과 %d\n", if (ok) "OK" else "FAIL", length(R), sum(vapply(R, function(z) z$ok, logical(1)))))
quit(status = if (ok) 0L else 1L)
