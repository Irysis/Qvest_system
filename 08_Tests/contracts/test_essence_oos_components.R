# test_essence_oos_components.R — P0-02 essence 진단 필드 + 고정 축 재도출 (2026-09-24 · 플랜 qvest-1-drifting-eclipse P0-02)
#
# 대상: 02_Infrastructure/contracts/essence_score.R   (diagnostics · essence_diagnostics · 공용 부품)
#       02_Infrastructure/ops/rf_preflight.R           (rf_preflight_verify_axes 재작성 · rf_essence_diag_backfill)
#       02_Infrastructure/worktask/constraint_defaults.json::diagnostics (tier_graduation 밖)
#
# 절:
#   R  등급 불변 — R1 변경 전 판본(git blob)과 identical 대조(합성 25 + 실산출 20) · R2 essence_score()$diagnostics
#      = essence_diagnostics() 패리티 · R3 진단 설정을 바꿔도/진단이 죽어도 판정 불변(fail-soft)
#   P  진단 양성 대조 — P1 IS 1.0/OOS 0.7 성분 재현 · P2 창(2012 시작 = 84개월 초과, 2005-02 = 1 · 허용 안)
#      · P3 골든에서 달력 성분 = 비율 성분 · P4 달력 분할은 시작을 늦춰도 OOS 구간 불변 · P5 설정 결측 = NA(폴백 없음)
#   C  설정 정합 — C1 앵커 = 격자 start_date · C2 진단 키가 tier_graduation 밖 · C3 허용 = 결정 D-C 문언
#   V  위반 주입(preflight) — 무위반 · n_max 26 · w<0 · Σw 0.8(라벨)/1.2(위반) · 시작 2012/경계 12·13개월 ·
#      유니버스 밖 · LIQ 미달 · LIQ t-1 규약 양방향 · 러너가 쓰는 AR 모양(n_max 중첩) · 보유 부재 NA ·
#      as-of 는 시그널일 · B3 처치 라벨 · RAWDATA 판독 불가 NA
#   B  백필 — 형제 essence_diag.json 기록 · AR 바이트 불변 · 보호 경로 거부
#   M  돌연변이 — 구판 preflight(blob) · as-of 보유일 · LIQ shift 제거 · Σw<1 위반화 · 달력 < · 분할 ceiling ·
#      창 규칙의 등급 누출 · 설정 앵커 드리프트 → 전부 red 여야 한다
#   D  원장 재도출(선택 · QVEST_ESSDIAG_LEDGER=1) — 원장 **사본**에서 창 이탈 칸 수를 두 경로(보유·수익)로 재도출
#
# 쓰기 0 — 운영 원장·authoritative·.cache 무접촉(essence sidecar_log=FALSE · 산출물은 tempdir 샌드박스).
# 재료 부재(git blob · 실산출 · 골든) = SKIP(미측정 — PASS 아님).
# 실행: Rscript 08_Tests/contracts/test_essence_oos_components.R
#   설치 전 사본 대조: QVEST_ESSDIAG_ES_SRC=<essence_score.R 사본> (R·P 절만 의미 있음)

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
TROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(TROOT, "CLAUDE.md"))) TROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, if (nzchar(d)) paste(" ::", d) else "", "\n") }
sk <- function(m) { SKIP <<- SKIP + 1L; cat("  SKIP ", m, "\n") }
chk <- function(m, cond, d = "") {
  r <- tryCatch(isTRUE(cond), error = function(e) { d <<- conditionMessage(e); FALSE })
  if (r) ok(m) else ng(m, d)
  invisible(r)
}
emit <- function() {
  cat(sprintf("\nTOTAL: %d pass / %d fail / %d skipped\n", PASS, FAIL, SKIP))
  cat(sprintf('{"test":"essence_oos_components","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n',
              PASS, FAIL, PASS + FAIL, SKIP))
  quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
}

ES_NEW <- Sys.getenv("QVEST_ESSDIAG_ES_SRC", file.path(TROOT, "02_Infrastructure/contracts/essence_score.R"))
PF_NEW <- file.path(TROOT, "02_Infrastructure/ops/rf_preflight.R")
# 변경 전 판본 — HEAD 7ea5d8377(2026-09-24) 의 blob. blob 은 불변이라 커밋 이후에도 같은 판본을 가리킨다.
OLD_ES_BLOB <- "fe06737f98ea3fb93d19536275ff56860cb1dfb4"
OLD_PF_BLOB <- "e725d4677fe6d5217c2360039f3f0f254e045532"
TMP <- file.path(tempdir(), "essdiag"); dir.create(TMP, showWarnings = FALSE, recursive = TRUE)

src_env <- function(path) {
  e <- new.env(parent = globalenv())
  suppressMessages(sys.source(path, envir = e, keep.source = FALSE))
  e
}
blob_path <- function(sha, name) {
  out <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(TROOT), "cat-file", "-p", sha),
                                           stdout = TRUE, stderr = FALSE)), error = function(e) NULL)
  if (is.null(out) || !is.null(attr(out, "status")) || !length(out)) return(NULL)
  p <- file.path(TMP, name); writeLines(out, p, useBytes = TRUE); p
}
mutate_src <- function(path, old, new, name) {
  s <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  n <- lengths(regmatches(s, gregexpr(old, s, fixed = TRUE)))
  if (n != 1L) stop(sprintf("돌연변이 표적 %d회(1회여야 함): %s", n, substr(old, 1, 60)))
  p <- file.path(TMP, name); writeLines(sub(old, new, s, fixed = TRUE), p, useBytes = TRUE); p
}
drop_diag <- function(x) x[setdiff(names(x), "diagnostics")]

cat("=== P0-02 essence 진단 필드 · 고정 축 재도출 ===\n")
E1 <- tryCatch(src_env(ES_NEW), error = function(e) { ng("신판 essence_score 적재", conditionMessage(e)); NULL })
if (is.null(E1)) emit()
OLDP <- blob_path(OLD_ES_BLOB, "essence_old.R")
E0 <- if (is.null(OLDP)) NULL else tryCatch(src_env(OLDP), error = function(e) NULL)

# ── 픽스처 ────────────────────────────────────────────────────────────────────
mk_bt <- function(active, bench = rep(0, length(active)), dates = NULL,
                  sharpe = 0.9, cagr = 0.20, mdd = 0.20, calmar = 1.0,
                  port_t = 3.5, ir = 0.5, drop_port_t = FALSE, holdings = NULL, af = NULL) {
  n <- length(active)
  if (is.null(dates)) dates <- seq(as.Date("2020-01-01"), by = "month", length.out = n)
  M <- data.table(metric_name = c("Sharpe", "CAGR", "MDD", "Calmar"), metric_value = c(sharpe, cagr, mdd, calmar))
  if (!is.null(af)) M[, annualization_factor := af]
  bcn <- c("Information_Ratio", "Portfolio_Alpha_t_NW_lag3"); bcv <- c(ir, port_t)
  if (drop_port_t) { bcn <- bcn[1]; bcv <- bcv[1] }
  out <- list(metrics = M, benchmark_compare = data.table(metric_name = bcn, active_value = bcv),
              period_returns = data.table(date = dates, ret_net = active + bench),
              benchmark_returns = data.table(date = dates, benchmark_ret = bench))
  if (!is.null(holdings)) out$holdings <- holdings
  out
}
a_block <- rep(c(0.032, -0.030, 0.001), 20)
a_cat   <- c(rep(-0.20, 6), rep(0.02, 54))
a_tail  <- c(rep(-0.108, 6), rep(0.04, 54))
ev_full <- list(trailing_port_t = 1.2, placebo_p = 0.01, book_marginal_delta_sr = 0.08, cor_vs_book = 0.10)
ev_weak <- list(trailing_port_t = 1.2, placebo_p = 0.50, book_marginal_delta_sr = -0.01, cor_vs_book = 0.10)
bdays <- function(from, to) { d <- seq(as.Date(from), as.Date(to), by = "day"); d[!format(d, "%u") %in% c("6", "7")] }
set.seed(20260924)
d05 <- bdays("2005-02-01", "2016-12-30")
a05 <- 0.0004 + 0.008 * sin(seq_along(d05) / 7) + rnorm(length(d05), 0, 0.006)
h05 <- data.table(date = as.Date("2005-02-01"), ticker = sprintf("T%02d", 1:25), actual_weight = 0.04)
SYN <- list(
  S01 = list(bt = mk_bt(a_block)),
  S02 = list(bt = mk_bt(a_block), args = list(oos_stat_version = "v1")),
  S03 = list(bt = mk_bt(a_block), args = list(n_trials_cumulative = 50, selection_type = "chain")),
  S04 = list(bt = mk_bt(a_block), args = list(n_trials_cumulative = 50, selection_type = "sweep")),
  S05 = list(bt = mk_bt(a_block), args = list(n_trials_cumulative = 50)),
  S06 = list(bt = mk_bt(a_block, port_t = 2.95)),
  S07 = list(bt = mk_bt(a_block, port_t = 2.9499)),
  S08 = list(bt = mk_bt(a_block, calmar = 0.64)),
  S09 = list(bt = mk_bt(a_block, calmar = 0.6399)),
  S10 = list(bt = mk_bt(a_block), args = list(oos_is_ratio_override = 0.70)),
  S11 = list(bt = mk_bt(a_block), args = list(oos_is_ratio_override = 0.69)),
  S12 = list(bt = mk_bt(a_block), args = list(oos_is_ratio_override = 0.69, escalation_evidence = ev_full)),
  S13 = list(bt = mk_bt(a_block), args = list(oos_is_ratio_override = 0.49, escalation_evidence = ev_full)),
  S14 = list(bt = mk_bt(a_block), args = list(oos_is_ratio_override = 0.69, escalation_evidence = ev_weak)),
  S15 = list(bt = mk_bt(a_block, sharpe = 0.79)),
  S16 = list(bt = mk_bt(a_block, port_t = -0.5)),
  S17 = list(bt = mk_bt(a_block, drop_port_t = TRUE)),
  S18 = list(bt = mk_bt(a_cat, mdd = 0.74)),
  S19 = list(bt = mk_bt(a_cat, mdd = 0.74), args = list(hard_fail = TRUE)),
  S20 = list(bt = mk_bt(a_tail, mdd = 0.496, calmar = 0.70), args = list(oos_is_ratio_override = 0.9)),
  S21 = list(bt = mk_bt(a_block), args = list(hard_fail = TRUE)),
  S22 = list(bt = mk_bt(rep(0.01, 8))),                                        # n < 12 — 분할 미진입
  S23 = list(bt = mk_bt(rep(0.002, 40))),                                      # sd = 0 — 분할 미진입
  S24 = list(bt = mk_bt(c(a_block[1:20], NA, a_block[22:60]))),                # 비유한 행 제거 경로
  S25 = list(bt = mk_bt(a05, dates = d05, holdings = h05, af = 252),           # 일간·보유 포함 A 후보
             args = list(n_trials_cumulative = 30, selection_type = "sweep"))
)
REAL_RUNS <- c("20260921_100007_6876", "20260921_084710_33240", "20260904_203512_16284", "20260919_022411_12752",
               "20260917_184531_23536", "20260924_065936_16476", "20260905_194655_12508", "20260922_001027_17624",
               "20260831_204638_28312", "20260830_202140_9860", "20260904_205137_5212", "20260905_125848_10832",
               "20260924_020009_4024", "20260903_202728_14268", "20260902_215411_20560", "20260903_090631_35032",
               "20260913_215143_16824", "20260912_170721_32032", "20260912_185620_11412", "20260831_104329_3768")
REAL <- list()
for (r in REAL_RUNS) {
  d <- file.path(TROOT, "stage_artifacts/replication", r)
  if (!file.exists(file.path(d, "bt_result.rds"))) next
  ar <- tryCatch(fromJSON(file.path(d, "authoritative_remeasure.json"), simplifyVector = FALSE), error = function(e) NULL)
  args <- list()
  if (!is.null(ar$n_trials_cumulative)) args$n_trials_cumulative <- as.numeric(ar$n_trials_cumulative)
  if (!is.null(ar$selection_type)) args$selection_type <- as.character(ar$selection_type)
  REAL[[r]] <- list(bt = readRDS(file.path(d, "bt_result.rds")), args = args)
}
run_es <- function(E, fx) do.call(E$essence_score, c(list(fx$bt), fx$args %||% list(), list(sidecar_log = FALSE)))

# ══ R. 등급 불변 ══════════════════════════════════════════════════════════════
cat("\n── R. 등급 불변 ─────────────────────────────────────────────\n")
NEWRES <- list()
if (is.null(E0)) {
  sk(sprintf("R1 변경 전 판본 blob %s 판독 불가(git 부재?) — 비트 대조 미측정", OLD_ES_BLOB))
} else {
  for (grp in list(list(nm = "합성", fx = SYN), list(nm = "실산출", fx = REAL))) {
    if (!length(grp$fx)) { sk(sprintf("R1 %s 픽스처 0건", grp$nm)); next }
    badl <- character(0)
    for (k in names(grp$fx)) {
      o <- run_es(E0, grp$fx[[k]]); nw <- run_es(E1, grp$fx[[k]]); NEWRES[[k]] <- nw
      same <- identical(o, drop_diag(nw)) && identical(names(nw), c(names(o), "diagnostics"))
      if (!same) badl <- c(badl, k)
    }
    chk(sprintf("R1 %s %d종 — 변경 전 판본과 grade·essence·사유·전 필드 identical(진단 칸만 끝에 추가)",
                grp$nm, length(grp$fx)), !length(badl), paste(badl, collapse = ","))
  }
  if (length(REAL) < 15L) sk(sprintf("R1 실산출 %d/20 만 존재 — 표본 축소", length(REAL)))
}
if (!length(NEWRES)) for (k in c(names(SYN), names(REAL))) NEWRES[[k]] <- run_es(E1, c(SYN, REAL)[[k]])
ALLFX <- c(SYN, REAL)
par_bad <- character(0)
for (k in names(ALLFX)) {
  v <- ALLFX[[k]]$args$oos_stat_version %||% "v2"
  if (!identical(NEWRES[[k]]$diagnostics, E1$essence_diagnostics(ALLFX[[k]]$bt, oos_stat_version = v)))
    par_bad <- c(par_bad, k)
}
chk(sprintf("R2 essence_score()$diagnostics = essence_diagnostics() — %d종 패리티", length(ALLFX)),
    !length(par_bad), paste(par_bad, collapse = ","))
# R3 — 진단 설정을 바꿔도 / 진단 조립이 죽어도 판정은 그대로
E3 <- src_env(ES_NEW)
p_alt <- list(window_anchor_date = as.Date("2015-06-01"), window_allowance_months = 0,
              oos_calendar_splits = as.Date(c("2006-01-31", "2024-01-31")), axes_weight_tol = 0.5)
E3$.DIAG_CACHE$p <- p_alt
r3 <- vapply(names(ALLFX), function(k) identical(drop_diag(run_es(E3, ALLFX[[k]])), drop_diag(NEWRES[[k]])), logical(1))
chk("R3a 진단 설정 교란(앵커·허용 0·절단일·허용오차) — 판정·전 필드 불변", all(r3), paste(names(r3)[!r3], collapse = ","))
E3$.essence_diag_build <- function(...) stop("주입된 진단 실패")
r3b <- lapply(names(SYN), function(k) run_es(E3, SYN[[k]]))
chk("R3b 진단 조립 실패 주입 — diagnostics$status=error · 판정·전 필드 불변(fail-soft)",
    all(vapply(seq_along(r3b), function(i) identical(r3b[[i]]$diagnostics$status, "error") &&
                 identical(drop_diag(r3b[[i]]), drop_diag(NEWRES[[names(SYN)[i]]])), logical(1))))

# ══ P. 진단 양성 대조 ══════════════════════════════════════════════════════════
cat("\n── P. 진단 양성 대조 ────────────────────────────────────────\n")
# P1 — IS 1.0 / OOS 0.7 (분할 0.65: n=200 → k=130). 표준화 교대열이라 평균·표준편차가 정확히 설계값이다.
zs <- function(m) as.numeric(scale(rep(c(1, -1), m / 2)))
sig <- 0.02
a_p1 <- c(1.0 * sig / sqrt(12) + sig * zs(130), 0.7 * sig / sqrt(12) + sig * zs(70))
r_p1 <- E1$essence_score(mk_bt(a_p1), sidecar_log = FALSE)
c65 <- r_p1$diagnostics$oos_components[[2]]
chk("P1 분할 0.65 성분 = 설계값(is_ir 1.0 · oos_ir 0.7 · retention 0.7 · n 130/70)",
    identical(c65$split, 0.65) && c65$n_is == 130L && c65$n_oos == 70L &&
      abs(c65$is_ir - 1.0) < 1e-10 && abs(c65$oos_ir - 0.7) < 1e-10 && abs(c65$retention - 0.7) < 1e-10,
    sprintf("is %.6f oos %.6f", c65$is_ir %||% NA, c65$oos_ir %||% NA))
rr <- vapply(r_p1$diagnostics$oos_components, function(x) x$retention, numeric(1))
chk("P1b 성분 retention = 등급이 쓴 oos_retention_splits(반올림 전 원값) · 중앙값 = essence oos_retention",
    identical(round(rr, 3), r_p1$oos_retention_splits) &&
      identical(round(stats::median(rr[is.finite(rr)]), 3), r_p1$essence$oos_retention))
# P2 — 창: 2012 시작 = 84개월(허용 12 초과) · 2005-02 시작 = 1(허용 안) · 보유가 수익보다 앞서면 보유일
d12 <- bdays("2012-01-02", "2016-12-30")
b12 <- mk_bt(a05[seq_along(d12)], dates = d12, af = 252)
g12 <- E1$essence_diagnostics(b12); g05 <- E1$essence_diagnostics(SYN$S25$bt)
chk("P2a 2012-01-02 시작 → window_deviation_months 84 · 허용 초과 TRUE",
    identical(g12$effective_start, "2012-01-02") && identical(g12$window_deviation_months, 84L) &&
      isTRUE(g12$window_exceeds_allowance), sprintf("dev=%s", g12$window_deviation_months))
chk("P2b 2005-02-01 시작 → 1개월 · 허용 안(FALSE) · 창 길이 2012판보다 길다",
    identical(g05$window_deviation_months, 1L) && identical(g05$window_exceeds_allowance, FALSE) &&
      g05$window_months > g12$window_months, sprintf("dev=%s wm=%s/%s", g05$window_deviation_months, g05$window_months, g12$window_months))
b_h <- mk_bt(a05, dates = d05, af = 252,
             holdings = data.table(date = as.Date("2004-12-01"), ticker = "T01", actual_weight = 1))
g_h <- E1$essence_diagnostics(b_h)
chk("P2c 첫 보유일이 첫 수익일보다 앞서면 effective_start = 보유일(source=holdings)",
    identical(g_h$effective_start, "2004-12-01") && identical(g_h$effective_start_source, "holdings") &&
      identical(g_h$window_deviation_months, -1L))
# P3 — 골든: 등록된 달력 절단일이 골든의 비율 절단점이므로 성분이 identical 이어야 한다
GOLD <- REAL[["20260921_100007_6876"]]
if (is.null(GOLD)) sk("P3 골든 20260921_100007_6876 부재") else {
  gg <- E1$essence_diagnostics(GOLD$bt)
  strip <- function(cc) lapply(cc, function(x) x[c("n_is", "n_oos", "is_ir", "oos_ir", "retention")])
  chk("P3 골든 — 달력 성분 = 비율 성분(n·IR·retention identical) · 달력 중앙값 = 비율 중앙값",
      length(gg$oos_calendar_components) == 3L &&
        identical(strip(gg$oos_calendar_components), strip(gg$oos_components)) &&
        identical(gg$oos_retention_calendar,
                  E1$.essence_median_finite(vapply(gg$oos_components, function(x) x$retention, numeric(1)))))
}
# P4 — 시작을 2012 로 늦추면 비율 절단점은 움직이고 달력 OOS 구간은 그대로
dfull <- bdays("2005-02-01", "2026-09-18"); set.seed(7)
afull <- 0.0003 + rnorm(length(dfull), 0, 0.007)
cut <- dfull >= as.Date("2012-01-01")
gF <- E1$essence_diagnostics(mk_bt(afull, dates = dfull, af = 252))
gL <- E1$essence_diagnostics(mk_bt(afull[cut], dates = dfull[cut], af = 252))
oos_of <- function(cc) lapply(cc, function(x) x[c("n_oos", "oos_ir")])
chk("P4 달력 OOS(n·IR) 는 시작 절단에 불변 · 비율 OOS n 은 달라진다",
    identical(oos_of(gF$oos_calendar_components), oos_of(gL$oos_calendar_components)) &&
      !identical(vapply(gF$oos_components, function(x) x$n_oos, integer(1)),
                 vapply(gL$oos_components, function(x) x$n_oos, integer(1))))
# P5 — 설정 결측 = NA (리터럴 폴백 없음)
SB <- file.path(TMP, "sb_root"); dir.create(file.path(SB, "02_Infrastructure/worktask"), recursive = TRUE, showWarnings = FALSE)
cd <- fromJSON(file.path(TROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)
cd$diagnostics <- NULL
write_json(cd, file.path(SB, "02_Infrastructure/worktask/constraint_defaults.json"), auto_unbox = TRUE, digits = NA)
pNA <- E1$.essence_diag_params(root = SB)
gNA <- E1$.essence_diag_build(b12, E1$.essence_active_series(b12), 252,
                              E1$.essence_split_components(E1$.essence_active_series(b12)$a, c(0.55, 0.65, 0.75), 252), pNA)
chk("P5 diagnostics 블록 결측 → 4키 NA · 창 초과·달력 retention NA(지어낸 폴백 없음)",
    setequal(attr(pNA, "missing_keys"), c("window_anchor_date", "window_allowance_months", "oos_calendar_splits", "axes_weight_tol")) &&
      is.na(gNA$window_deviation_months) && is.na(gNA$window_exceeds_allowance) && is.na(gNA$oos_retention_calendar) &&
      length(gNA$oos_components) == 3L)

# ══ C. 설정 정합 ══════════════════════════════════════════════════════════════
cat("\n── C. 설정 정합 ─────────────────────────────────────────────\n")
CD <- fromJSON(file.path(TROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)
PG <- tryCatch(fromJSON(file.path(TROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE), error = function(e) NULL)
anchor_ok <- function(cd, pg) identical(as.character(cd$diagnostics$window_anchor_date), as.character(pg$fixed_axes$start_date))
if (is.null(PG)) sk("C1 reinforce_program.json 부재") else
  chk("C1 diagnostics.window_anchor_date = reinforce_program.json::fixed_axes.start_date (쌍둥이 드리프트 검사)", anchor_ok(CD, PG))
dkeys <- c("window_anchor_date", "window_allowance_months", "oos_calendar_splits", "axes_weight_tol")
chk("C2 진단 4키는 diagnostics 에만 — tier_graduation 안에 없다(등급 정의 오독 방지)",
    all(dkeys %in% names(CD$diagnostics)) && !any(dkeys %in% names(CD$tier_graduation)) &&
      !any(grepl("calendar|window_", names(CD$tier_graduation))))
DR <- tryCatch(fromJSON(file.path(TROOT, "06_Registry/decision_register.json"), simplifyVector = FALSE), error = function(e) NULL)
dc <- if (is.null(DR)) NULL else Filter(function(x) identical(x$id, "D-C"), DR$items)
if (!length(dc)) sk("C3 decision_register D-C 부재") else
  chk("C3 허용 개월 = 결정 D-C(resolved) 문언의 개월 수 — 두 출처 일치",
      identical(dc[[1]]$status, "resolved") &&
        identical(as.numeric(regmatches(dc[[1]]$decision, regexpr("[0-9]+(?=개월)", dc[[1]]$decision, perl = TRUE))),
                  as.numeric(CD$diagnostics$window_allowance_months)))

# ══ V. 고정 축 재도출 — 위반 주입 ══════════════════════════════════════════════
cat("\n── V. 고정 축 재도출(preflight) 위반 주입 ─────────────────────\n")
P1 <- tryCatch(src_env(PF_NEW), error = function(e) { ng("rf_preflight 적재", conditionMessage(e)); NULL })
if (is.null(P1) || !exists("rf_essence_diag_backfill", envir = P1)) { ng("rf_preflight 신판 함수 부재"); emit() }
FX <- list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150", start_date = "2005-01-01", liq_adv20_min = 2e8)
# 합성 RAWDATA — 30종목 · 평일 · 거래대금 1e9/일(기본). T01~T25 K200 · T26~T28 KQ150 · T29~T30 비멤버
rd_days <- bdays("2004-06-01", "2012-03-30")
RAW <- CJ(Date = rd_days, Ticker = sprintf("T%02d", 1:30))
RAW[, `:=`(Close = 100, Vol = 1e7, K200 = as.numeric(Ticker <= "T25"),
           KQ150 = as.numeric(Ticker %in% c("T26", "T27", "T28")))]
exec_days <- function(yms) vapply(yms, function(ym) as.numeric(min(rd_days[format(rd_days, "%Y-%m") == ym])), numeric(1))
sig_of <- function(h) max(rd_days[rd_days < h])
H0dates <- as.Date(exec_days(c("2005-02", "2005-03", "2005-04", "2005-05", "2005-06")), origin = "1970-01-01")
mkH <- function(dates = H0dates, tk = sprintf("T%02d", 1:25), w = NULL) {
  h <- CJ(date = dates, ticker = tk); h[, actual_weight := if (is.null(w)) 1 / length(tk) else w]; h
}
mk_art <- function(nm, H, ar_top_nmax = FALSE) {
  d <- file.path(TMP, "art", nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  fwrite(H, file.path(d, "04_holdings.csv"))
  ar <- list(status = "OK", essence_grade = "C", essence = list(oos_retention = 0.1),
             replication = list(n_max = 25L, has_short = FALSE))       # 러너(run_paper_replication.R)가 쓰는 모양
  if (ar_top_nmax) ar$n_max <- 25L
  write_json(ar, file.path(d, "authoritative_remeasure.json"), auto_unbox = TRUE)
  file.path(d, "authoritative_remeasure.json")
}
VA <- function(E, arp, raw = RAW, fixed = FX, spec = NULL) E$rf_preflight_verify_axes(arp, fixed, spec = spec, rawdata = raw, root = TROOT)
v0 <- VA(P1, mk_art("v0", mkH()))
chk("V0 무위반 25종·Σw=1·2005-02 시작·멤버·LIQ 충족 → ok TRUE · 위반 0 · 라벨 0",
    isTRUE(v0$ok) && !length(v0$violations) && !length(v0$labels) && identical(v0$derived$n_max_realized, 25L) &&
      identical(v0$derived$source, "04_holdings.csv"), paste(v0$violations, v0$labels, collapse = ";"))
h1 <- rbind(mkH(), data.table(date = H0dates[2], ticker = "T26", actual_weight = 0)); h1[date == H0dates[2], actual_weight := 1 / 26]
ARP_V1 <- mk_art("v1", h1)
v1 <- VA(P1, ARP_V1)
chk("V1 한 날 26종 → n_max 위반(러너 AR 모양: n_max 는 replication$ 아래 · 최상위 키 없음)",
    identical(v1$ok, FALSE) && "n_max" %in% v1$codes && identical(v1$derived$n_max_realized, 26L))
h2 <- mkH(); h2[date == H0dates[3] & ticker == "T01", actual_weight := -0.01]; h2[date == H0dates[3] & ticker == "T02", actual_weight := 0.09]
v2 <- VA(P1, mk_art("v2", h2))
chk("V2 음수 비중 → long-only 위반", identical(v2$ok, FALSE) && "negative_weight" %in% v2$codes)
h3a <- mkH(); h3a[date == H0dates[4], actual_weight := 0.8 / 25]
v3a <- VA(P1, mk_art("v3a", h3a))
chk("V3a Σw 0.8 → 라벨 sigma_w_lt_1 · 위반 아님(도훈 D-D) · ok TRUE",
    isTRUE(v3a$ok) && "sigma_w_lt_1" %in% v3a$labels && !length(v3a$codes))
h3b <- mkH(); h3b[date == H0dates[4], actual_weight := 1.2 / 25]
v3b <- VA(P1, mk_art("v3b", h3b))
chk("V3b Σw 1.2 → sigma_w_gt_1 위반", identical(v3b$ok, FALSE) && "sigma_w_gt_1" %in% v3b$codes)
D12 <- as.Date(exec_days(c("2012-01", "2012-02", "2012-03")), origin = "1970-01-01")
v4 <- VA(P1, mk_art("v4", mkH(D12)))
chk("V4 2012-01 시작 → window_deviation 위반 84개월 + holds window_deviation(처분 = P0-12)",
    identical(v4$ok, FALSE) && "window_deviation" %in% v4$codes && "window_deviation" %in% v4$holds &&
      identical(v4$derived$window_deviation_months, 84L))
v4a <- VA(P1, mk_art("v4a", mkH(as.Date(exec_days(c("2006-01", "2006-02")), origin = "1970-01-01"))))
v4b <- VA(P1, mk_art("v4b", mkH(as.Date(exec_days(c("2006-02", "2006-03")), origin = "1970-01-01"))))
chk("V4b 경계 — 12개월(2006-01) 허용 · 13개월(2006-02) 위반",
    isTRUE(v4a$ok) && identical(v4a$derived$window_deviation_months, 12L) &&
      identical(v4b$ok, FALSE) && identical(v4b$derived$window_deviation_months, 13L))
h5 <- mkH(tk = c(sprintf("T%02d", 1:24), "T29"))
v5 <- VA(P1, mk_art("v5", h5))
chk("V5 비멤버(T29) 보유 → universe_outside 위반", identical(v5$ok, FALSE) && "universe_outside" %in% v5$codes &&
      "T29" %in% v5$derived$universe_outside_tickers)
RAW6 <- copy(RAW); RAW6[Ticker == "T27", Vol := 1e5]     # 거래대금 1e7 < 2e8
v6 <- VA(P1, mk_art("v6", mkH(tk = c(sprintf("T%02d", 1:24), "T27"))), raw = RAW6)
chk("V6 LIQ 미달(T27 adv20 1e7) → liq_below 위반", identical(v6$ok, FALSE) && "liq_below" %in% v6$codes)
# V6b — t-1 규약: 시그널일 d 하루만 거래대금 폭증 → 당일 포함하면 통과, t-1 이면 미달(위반이어야 정상)
d_sig <- sig_of(H0dates[1])
RAW6b <- copy(RAW); RAW6b[Ticker == "T28", Vol := 1e5]; RAW6b[Ticker == "T28" & Date == d_sig, Vol := 1e10]
ARP_V6B <- mk_art("v6b", mkH(dates = H0dates[1], tk = c(sprintf("T%02d", 1:24), "T28")))
v6b <- VA(P1, ARP_V6B, raw = RAW6b)
chk("V6b 시그널일 당일만 거래대금 폭증 → t-1 기준 미달 위반(당일 미사용 = C10)", identical(v6b$ok, FALSE) && "liq_below" %in% v6b$codes)
RAW6c <- copy(RAW); RAW6c[Ticker == "T28" & Date == d_sig, Vol := 0]
v6c <- VA(P1, ARP_V6B, raw = RAW6c)
chk("V6c 거울상 — 시그널일 당일만 0 → t-1 기준 충족(ok TRUE)", isTRUE(v6c$ok))
v8 <- P1$rf_preflight_verify_axes(file.path(TMP, "art", "nope", "authoritative_remeasure.json"), FX, rawdata = RAW, root = TROOT)
chk("V8 보유 산출물 부재 → ok NA(통과 아님)", is.na(v8$ok) && !isTRUE(v8$ok) && grepl("미검증", v8$note))
# V9 — as-of = 시그널일 d: T26 은 d 에 멤버·h 에 편출 → 통과 / T30 은 d 에 비멤버·h 에 편입 → 위반
h9 <- H0dates[2]; d9 <- sig_of(h9)
RAW9 <- copy(RAW); RAW9[Ticker == "T26" & Date >= h9, KQ150 := 0]; RAW9[Ticker == "T30" & Date >= h9, KQ150 := 1]
v9a <- VA(P1, mk_art("v9a", mkH(dates = h9, tk = c(sprintf("T%02d", 1:24), "T26"))), raw = RAW9)
v9b <- VA(P1, mk_art("v9b", mkH(dates = h9, tk = c(sprintf("T%02d", 1:24), "T30"))), raw = RAW9)
chk("V9 as-of 시그널일 — d 멤버·h 편출(T26) 통과 · d 비멤버·h 편입(T30) 위반",
    isTRUE(v9a$ok) && identical(v9b$ok, FALSE) && "universe_outside" %in% v9b$codes)
v10 <- VA(P1, mk_art("v10", h5), spec = list(universe = list(kind = "all_listed")))
chk("V10 B3 처치(universe.kind=all_listed) 선언 시 이탈 = 라벨 universe_treatment · 위반 아님",
    !"universe_outside" %in% v10$codes && "universe_treatment:all_listed" %in% v10$labels && is.na(v10$ok))
P1b <- src_env(PF_NEW); P1b$.rf_pf_read_rawdata <- function(...) stop("주입: RAWDATA 판독 불가")
v11 <- P1b$rf_preflight_verify_axes(mk_art("v11", mkH()), FX, rawdata = NULL, root = TROOT)
chk("V11 RAWDATA 판독 불가 → 라벨 rawdata_unavailable · ok NA(통과 아님)",
    is.na(v11$ok) && "rawdata_unavailable" %in% v11$labels && !length(v11$violations))

# ══ B. 형제 백필 ══════════════════════════════════════════════════════════════
cat("\n── B. 형제 백필(rf_essence_diag_backfill) ───────────────────\n")
bd <- file.path(TMP, "bf"); dir.create(bd, showWarnings = FALSE)
bt_b <- mk_bt(a05, dates = d05, af = 252,
              holdings = data.table(date = H0dates, ticker = "T01", actual_weight = 1))
saveRDS(bt_b, file.path(bd, "bt_result.rds"))
fwrite(mkH(), file.path(bd, "04_holdings.csv"))
write_json(list(status = "OK", essence_grade = "B", essence = list(oos_retention = 0.3),
                measurement_regime = list(exec_price = "close_d_legacy")), file.path(bd, "authoritative_remeasure.json"), auto_unbox = TRUE)
md5_before <- unname(tools::md5sum(c(file.path(bd, "authoritative_remeasure.json"), file.path(bd, "bt_result.rds"))))
rec <- tryCatch(P1$rf_essence_diag_backfill(bd, fixed = FX, rawdata = RAW, root = TROOT), error = function(e) e)
j <- tryCatch(fromJSON(file.path(bd, "essence_diag.json"), simplifyVector = FALSE), error = function(e) NULL)
chk("B1 형제 essence_diag.json 기록 · 저장 등급 병기(재채점 없음) · 진단·고정 축 동봉",
    !inherits(rec, "error") && !is.null(j) && identical(j$stored$essence_grade, "B") &&
      identical(j$diagnostics$version, "essence_diag_v1") && isTRUE(j$axes$ok) &&
      identical(j$diagnostics$effective_start, "2005-02-01"))
chk("B2 authoritative_remeasure.json · bt_result.rds 바이트 불변",
    identical(unname(tools::md5sum(c(file.path(bd, "authoritative_remeasure.json"), file.path(bd, "bt_result.rds")))), md5_before))
chk("B3 보호 경로(authoritative_remeasure.json) 로의 기록 거부",
    inherits(tryCatch(P1$rf_essence_diag_backfill(bd, out = file.path(bd, "authoritative_remeasure.json"), rawdata = RAW, root = TROOT),
                      error = function(e) e), "error") &&
      identical(unname(tools::md5sum(file.path(bd, "authoritative_remeasure.json"))), md5_before[1]))
chk("B4 임시 파일 잔재 0(원자 교체)", !length(list.files(bd, pattern = "^\\.essence_diag_.*\\.tmp$", all.files = TRUE)))

# ══ M. 돌연변이 ═══════════════════════════════════════════════════════════════
cat("\n── M. 돌연변이 (전부 red 여야 한다) ─────────────────────────\n")
OLDPF <- blob_path(OLD_PF_BLOB, "rf_preflight_old.R")
if (is.null(OLDPF)) sk("M1 구판 rf_preflight blob 판독 불가") else {
  PO <- src_env(OLDPF)
  o1 <- PO$rf_preflight_verify_axes(ARP_V1, FX)
  chk("M1 구판 preflight(AR 최상위 n_max) → V1 26종을 놓친다(ok TRUE) — 신판만 검출", isTRUE(o1$ok) && identical(v1$ok, FALSE))
}
mut_pf <- function(old, new, nm) src_env(mutate_src(PF_NEW, old, new, nm))
M2 <- mut_pf("as.numeric(hd) - 0.5", "as.numeric(hd) + 0.5", "pf_m2.R")
m2a <- VA(M2, file.path(TMP, "art", "v9a", "authoritative_remeasure.json"), raw = RAW9)
m2b <- VA(M2, file.path(TMP, "art", "v9b", "authoritative_remeasure.json"), raw = RAW9)
chk("M2 as-of 를 보유일로 바꾼 돌연변이 → V9 판정이 정확히 뒤집힌다(T26 위반 · T30 통과 = red)",
    identical(m2a$ok, FALSE) && "universe_outside" %in% m2a$codes && isTRUE(m2b$ok))
M3 <- mut_pf('data.table::shift(data.table::frollmean(tv, 20L, align = "right"), 1L)',
             'data.table::frollmean(tv, 20L, align = "right")', "pf_m3.R")
m3 <- VA(M3, ARP_V6B, raw = RAW6b)
chk("M3 LIQ shift(1) 제거 돌연변이 → V6b(t-1) 위반을 놓친다(ok TRUE = red)", isTRUE(m3$ok) && !length(m3$codes))
M4 <- mut_pf("(D$sigma_w_max <= 1 + tol)", "(D$sigma_w_absdev_max <= tol)", "pf_m4.R")
m4 <- VA(M4, file.path(TMP, "art", "v3a", "authoritative_remeasure.json"))
chk("M4 Σw<1 을 위반으로 만든 돌연변이 → V3a 가 위반으로 뒤집힌다(red)", identical(m4$ok, FALSE) && "sigma_w_gt_1" %in% m4$codes)
M5 <- src_env(mutate_src(ES_NEW, "d <= s); oo <- which(!is.na(d) & d > s)", "d < s); oo <- which(!is.na(d) & d >= s)", "es_m5.R"))
if (is.null(GOLD)) sk("M5 골든 부재") else {
  g5 <- M5$essence_diagnostics(GOLD$bt)
  chk("M5 달력 경계 <= → < 돌연변이 → P3 골든 동일성 깨짐(red)",
      identical(vapply(g5$oos_calendar_components, function(x) as.integer(x$n_is), integer(1)),
                vapply(g5$oos_components, function(x) as.integer(x$n_is), integer(1)) - 1L))
}
M6 <- src_env(mutate_src(ES_NEW, "    k <- floor(n * fr)\n    if (k < .ESSENCE_MIN_SEG", "    k <- ceiling(n * fr)\n    if (k < .ESSENCE_MIN_SEG", "es_m6.R"))
m6 <- vapply(names(REAL), function(k) identical(drop_diag(run_es(M6, REAL[[k]])), drop_diag(NEWRES[[k]])), logical(1))
if (!length(REAL)) sk("M6 실산출 부재") else
  chk("M6 분할점 floor→ceiling 돌연변이 → R1 식 대조가 잡는다(red)", !all(m6))
M7 <- src_env(mutate_src(ES_NEW, "  a_core <- (is.finite(port_t) && port_t >= .gp$port_t_min &&",
  "  a_core <- (isFALSE(.essence_month_diff(as.Date(\"2005-01-01\"), .essence_first_holding_date(bt_result$holdings)) > 12) && is.finite(port_t) && port_t >= .gp$port_t_min &&",
  "es_m7.R"))
m7 <- vapply(names(SYN), function(k) identical(drop_diag(run_es(M7, SYN[[k]])), drop_diag(NEWRES[[k]])), logical(1))
chk("M7 창 규칙을 등급에 누출한 돌연변이 → R1 식 대조가 잡는다(red)", !all(m7))
CDm <- CD; CDm$diagnostics$window_anchor_date <- "2006-01-01"
if (is.null(PG)) sk("M8 reinforce_program.json 부재") else
  chk("M8 설정 앵커 드리프트(2006-01-01) → C1 이 잡는다(red)", !anchor_ok(CDm, PG))

# ══ D. 원장 재도출 (선택) ════════════════════════════════════════════════════
cat("\n── D. 원장 사본 재도출 (QVEST_ESSDIAG_LEDGER=1) ─────────────\n")
if (!identical(Sys.getenv("QVEST_ESSDIAG_LEDGER"), "1")) {
  sk("D 원장 재도출 — 선택 절(QVEST_ESSDIAG_LEDGER=1 일 때만 · 1,200여 산출물 판독)")
} else {
  lc <- file.path(TMP, "ledger_l1_copy.json")
  file.copy(file.path(TROOT, "06_Registry/reinforce_ledger_l1.json"), lc, overwrite = TRUE)   # 사본만 읽는다
  L <- fromJSON(lc, simplifyVector = FALSE)
  allow <- E1$.essence_diag_params()$window_allowance_months
  anc <- E1$.essence_diag_params()$window_anchor_date
  ## 단위 = 칸(attempt) — 감사(D10-10 · synth §1)가 센 단위. 승계·dedup 칸은 같은 산출물을 가리키므로 산출물 판독은 1회만 한다.
  cache <- new.env(); rows <- list()
  for (e in L$entries) for (a in e$attempts) {
    p <- a$artifacts; if (is.list(p)) p <- p[[1]]
    if (!is.character(p) || !length(p) || !file.exists(file.path(p, "04_holdings.csv"))) next
    if (is.null(cache[[p]])) {
      H <- P1$.rf_pf_read_holdings(p)
      hd <- if (is.null(H)) as.Date(NA) else min(H[is.finite(w) & w != 0]$date)
      pr <- tryCatch(fread(file.path(p, "03_period_returns.csv"), select = c("date", "ret_net")), error = function(e) NULL)
      rd <- if (is.null(pr)) as.Date(NA) else min(as.Date(pr$date[is.finite(pr$ret_net) & pr$ret_net != 0]))
      cache[[p]] <- list(hd = hd, rd = rd)
    }
    cc <- cache[[p]]
    rows[[length(rows) + 1L]] <- data.table(dir = p, base = e$base_id, grade = a$grade %||% NA_character_,
      oos = suppressWarnings(as.numeric(a$essence$oos_retention %||% NA)),
      dev_h = E1$.essence_month_diff(anc, cc$hd), dev_r = E1$.essence_month_diff(anc, min(cc$hd, cc$rd, na.rm = TRUE)),
      y = format(cc$hd, "%Y"))
  }
  R <- rbindlist(rows)
  n_ex <- sum(R$dev_h > allow, na.rm = TRUE); n_ex_r <- sum(R$dev_r > allow, na.rm = TRUE)
  hi <- R[is.finite(oos) & oos >= 0.7]; hi13 <- hi[y %in% c("2011", "2012", "2013")]
  top <- if (nrow(hi13)) hi13[, .N, by = base][order(-N)] else data.table(base = character(0), N = integer(0))
  cat(sprintf("    칸 %d (산출물 %d) · 창 이탈(> %d개월) 보유 경로 %d / 수익 경로 %d (산출물 기준 %d) · retention>=0.7 %d칸 중 2011~13 시작 %d (계보 %s)\n",
              nrow(R), uniqueN(R$dir), as.integer(allow), n_ex, n_ex_r, uniqueN(R[dev_h > allow]$dir), nrow(hi), nrow(hi13),
              paste(sprintf("%s=%d", sub("^RP_[0-9]+_[0-9]+_([0-9]+).*$", "\\1", top$base), top$N), collapse = ",")))
  chk("D1 창 이탈 판정 — 보유 경로 = 수익 경로(두 판독이 같은 칸을 가리킨다)", identical(R$dev_h > allow, R$dev_r > allow))
  chk("D2 감사 수치 재현(칸 단위) — 창 이탈 ≥ 168(감사 시점 1099칸 · 원장 append-only) · retention>=0.7 중 2011~13 시작 ≥ 32 · 그 칸들은 단일 계보",
      n_ex >= 168L && nrow(hi13) >= 32L && uniqueN(sub("_(combo_rulefast|promo).*$", "", hi13$base)) == 1L)
}

emit()
