#!/usr/bin/env Rscript
# =============================================================================
# test_l2_pool_close_t1.R — 2계층 풀 집행 규약 단일화(close_t1) 양방향 검사 (2026-10-10 · 감사 2026-10-08 P3/I3)
# =============================================================================
# 막는 결함: 02_Infrastructure/regime/build_module_performance.R 가 등재 시점 sim_result.rds 를 그대로 읽어 close_d(구 체결) 판과
#   close_t1 판이 한 풀에 섞였다(실측 10-10 풀 80: remeasure_close_t1_* 가 있는데 안 쓴 RP 23 · close_d 최상위만 RP 3 · STR_AS 5 ·
#   레거시 QEPM 7). 설계 04_Research/01_reports/l2_role_rotation_redesign_20261010/README.md §4-1.
# 단언:
#   A 기본(강제 · dry-run): remeasure 판 → 그 판 계약 CSV 계열(l2_pool_series 재조립 · 등재 sim 병기) · 등재 sim 이 바로 그 판이면 그대로 ·
#     신판 close_t1 → 등재 sim · close_d·판독 불가·레거시·무결성 미달·모호·산출물 없음 → 제외 + 사유 코드 ·
#     국면 성과가 close_t1 계열로 계산됨(손 유도 Sharpe)
#   B 진단 스위치: QVEST_L2_INCLUDE_NON_CLOSE_T1=1 + DRY_RUN = 혼합 포함(표식) · 스위치 + 비 dry-run = 중단(정본 미기록)
#   C 정본 경로: 기록 · 멱등(두 번째 실행은 재조립 파일을 다시 쓰지 않는다)
#   D 돌연변이 red 3종: 제외 줄 삭제 · 소비 계열을 등재 sim 으로 되돌림 · 신판 판독 무력화
#   Z 운영 무쓰기
# 방법: tempdir 샌드박스 · 자식 Rscript = 빈 Renviron + QM_ROOT/CLAUDE_PROJECT_DIR = 샌드박스(~/.Renviron QM_ROOT 차단).
# 실행: Rscript 08_Tests/regime/test_l2_pool_close_t1.R   (env L2CT1_CODE_ROOT = 검사할 코드 트리 · 기본 = 이 파일 기준 저장소)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow); library(xts) })

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE)) else "."
}, error = function(e) ".")
CODE_ROOT <- gsub("\\\\", "/", Sys.getenv("L2CT1_CODE_ROOT", ""))
if (!nzchar(CODE_ROOT)) CODE_ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(CODE_ROOT, "02_Infrastructure/regime/build_module_performance.R")))
  CODE_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
OPS_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", CODE_ROOT))
cat(sprintf("=== test_l2_pool_close_t1 ===\n  CODE_ROOT=%s\n  OPS_ROOT=%s\n", CODE_ROOT, OPS_ROOT))
for (.k in c("QVEST_L2_INCLUDE_NON_CLOSE_T1", "QVEST_L2_DRY_RUN", "QVEST_L2_DRY_RUN_OUT", "QVEST_L2_POOL_MODE", "QVEST_FR_ALLOW_BROAD_SCAN")) Sys.unsetenv(.k)

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
P <- 0L; FL <- 0L
ok <- function(c, m) { if (isTRUE(c)) { P <<- P + 1L; cat("  PASS ", m, "\n") } else { FL <<- FL + 1L; cat("  FAIL ", m, "\n") } }
finish <- function() {
  cat(sprintf("\n=== 최종: %d PASS / %d FAIL / 0 SKIP ===\n", P, FL))
  cat(as.character(toJSON(list(test = "test_l2_pool_close_t1", pass = P, fail = FL, total = P + FL, skipped = 0L), auto_unbox = TRUE)), "\n", sep = "")
  quit(status = if (FL > 0L) 1L else 0L, save = "no")
}

# ── 운영 무쓰기 기준선 ─────────────────────────────────────────────────────────
OPS_FILES <- file.path(OPS_ROOT, c("06_Registry/module_performance.json", "06_Registry/module_catalog.json"))
OPS_FILES <- OPS_FILES[file.exists(OPS_FILES)]
MD5_BEFORE <- tools::md5sum(OPS_FILES)
SER_OPS <- file.path(OPS_ROOT, "04_Research/factor_rotation/l2_pool_series")
SER_BEFORE <- if (dir.exists(SER_OPS)) tools::md5sum(sort(list.files(SER_OPS, recursive = TRUE, full.names = TRUE))) else character(0)

TMP <- normalizePath(file.path(tempdir(), paste0("l2ct1_", Sys.getpid())), winslash = "/", mustWork = FALSE)
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
EMPTY_RENV <- file.path(TMP, "empty.Renviron"); file.create(EMPTY_RENV)
RSCRIPT <- file.path(R.home("bin"), "Rscript")
run_child <- function(script, envs) {
  keys <- names(envs); old <- Sys.getenv(keys, unset = NA, names = TRUE)
  on.exit(for (k in keys) { if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)) }, add = TRUE)
  do.call(Sys.setenv, as.list(envs))
  out <- suppressWarnings(system2(RSCRIPT, c("--no-save", shQuote(script)), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); list(status = if (is.null(st)) 0L else as.integer(st), out = out)
}
mutate_file <- function(src, old, new, tag) {
  t <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (lengths(regmatches(t, gregexpr(old, t, fixed = TRUE))) != 1L) return(NA_character_)
  f <- file.path(TMP, paste0("bmp_mut_", tag, ".R")); writeLines(sub(old, new, t, fixed = TRUE), f, useBytes = TRUE); f
}

# ── 샌드박스 ────────────────────────────────────────────────────────────────
PB <- file.path(TMP, "proj")
for (d in c(".cache", "06_Registry", "04_Research/strategies", "stage_artifacts/replication")) dir.create(file.path(PB, d), recursive = TRUE, showWarnings = FALSE)
for (r in c("02_Infrastructure/regime/build_module_performance.R", "02_Infrastructure/regime/l2_pool_admission.R",
            "02_Infrastructure/contracts/defensive_score.R", "02_Infrastructure/validation/overlay_pit_guard.R",
            "02_Infrastructure/data/fred_availability.R", "06_Registry/fred_availability_rules.json",
            "02_Infrastructure/contracts/register_measured_module.R", "02_Infrastructure/contracts/register_module.R",
            "02_Infrastructure/ops/shared_registry_io.R")) {
  dir.create(dirname(file.path(PB, r)), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(file.path(CODE_ROOT, r), file.path(PB, r), overwrite = TRUE)) stop("copy 실패: ", r)
}
BN <- file.path(PB, "02_Infrastructure/regime/build_module_performance.R")

set.seed(20261010)
wkdays <- function(a, b) { d <- seq(as.Date(a), as.Date(b), by = "day"); d[as.POSIXlt(d)$wday %in% 1:5] }
WD <- wkdays("2011-01-03", "2016-12-30")                     # 국면 패널은 모듈보다 1년 먼저 선다 → 모듈 첫 행만 라벨 없음
MD <- WD[WD >= as.Date("2012-01-02")]
CYC <- c("RISK_ON", "NEUTRAL", "CAUTION", "CRISIS", "RISK_OFF")
write_parquet(data.table(Date = WD, Category = CYC[(seq_along(WD) %/% 20L) %% 5L + 1L], avail_date = c(WD[-1], as.Date(NA))),
              file.path(PB, ".cache/unified_regime_signal_daily.parquet"))
BMR <- round(rnorm(length(MD), 3e-4, 0.011), 6)
ser <- function() round(0.8 * BMR + rnorm(length(MD), 4e-4, 0.006), 6)

SA <- "stage_artifacts/replication"
write_contract <- function(rel, ret, auth = NULL, cmv = NULL) {
  d <- file.path(PB, rel); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  fwrite(data.table(date = MD, frequency = "daily", ret_net = ret), file.path(d, "03_period_returns.csv"))
  fwrite(data.table(date = MD, benchmark_ret = BMR), file.path(d, "05_benchmark_returns.csv"))
  if (!is.null(auth)) write_json(auth, file.path(d, "authoritative_remeasure.json"), auto_unbox = TRUE)
  if (!is.null(cmv)) write_json(list(cost_model_version = cmv), file.path(d, "00_manifest.json"), auto_unbox = TRUE)
}
AUTH_T1 <- function(g = "C") list(status = "OK", metric_type = "backtested", essence_grade = g, measurement_regime = list(exec_price = "close_t1"))
AUTH_OLD <- list(status = "OK", metric_type = "backtested", essence_grade = "B")       # 2026-09-25 이전 판 = measurement_regime 없음
write_sim <- function(id, ret, prov = NULL, dir = id) {
  d <- file.path(PB, "04_Research/strategies", dir); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  s <- list(DAILY_NAV_DT = data.table(Date = MD, Strategy_Ret = ret), strategy_xts = xts(ret, order.by = MD), bm_xts = xts(BMR, order.by = MD))
  if (!is.null(prov)) s$provenance <- prov
  saveRDS(s, file.path(d, "sim_result.rds")); file.path("04_Research/strategies", dir, "sim_result.rds")
}
cat_entry <- function(sim_rel, art = NULL, bt = NULL) {
  e <- list(sim_result_path = sim_rel, fr_eligible = TRUE, metric_type = "backtested", contract = list(contract_pass = TRUE),
            grade = "B", essence_grade = "B", role = "core", origin_mode = "test")
  if (!is.null(art)) e$meta <- list(artifacts_dir = art)
  if (!is.null(bt)) e$bt_result_path <- bt
  e
}
MC <- list()
## R1 — 등재 = close_d 최상위 계약 CSV 재조립 · remeasure_close_t1_* 판 있음(실측 23개 지문) → 그 판 계열을 재조립해 소비
R1_T1 <- ser(); R1_D <- round(R1_T1 + 0.002, 6)                          # close_d 판 = 다른 계열(평균 +0.2%/일 — 출처가 Sharpe 로 갈린다)
write_contract(file.path(SA, "R1run"), R1_D, AUTH_OLD, "unlabeled_pre_v24")
write_contract(file.path(SA, "R1run/remeasure_close_t1_t1"), R1_T1, AUTH_T1("C"))
MC$RP_R1 <- cat_entry(write_sim("RP_R1", R1_D, list(built_from = "contract_csv", out_dir = file.path(SA, "R1run"))), file.path(SA, "R1run"))
## R2 — 등재 sim 이 바로 remeasure 판 계약 CSV 재조립(실측 38개 지문 · artifacts_dir = 판 자체) → 등재 sim 그대로
R2 <- ser(); write_contract(file.path(SA, "R2run/remeasure_close_t1_t1"), R2, AUTH_T1("B"))
MC$RP_R2 <- cat_entry(write_sim("RP_R2", R2, list(built_from = "contract_csv", out_dir = file.path(SA, "R2run/remeasure_close_t1_t1"))),
                      file.path(SA, "R2run/remeasure_close_t1_t1"))
## N1 — 신판(측정 자체가 close_t1) → 등재 sim 그대로
N1 <- ser(); write_contract(file.path(SA, "N1run"), N1, AUTH_T1("B"), "replication_weight_delta_v1/first_hold_day_multiplicative")
MC$RP_N1 <- cat_entry(write_sim("RP_N1", N1), file.path(SA, "N1run"))
## 제외 6종
write_contract(file.path(SA, "D1run"), ser(), AUTH_OLD, "unlabeled_pre_v24")
MC$RP_D1 <- cat_entry(write_sim("RP_D1", ser()), NULL, file.path(SA, "D1run/bt_result.rds"))       # artifacts_dir 없음 → bt_result_path 디렉터리
write_contract(file.path(SA, "D2run"), ser(), AUTH_OLD, "replication_weight_delta_v1/exec_day_additive")
MC$RP_D2 <- cat_entry(write_sim("RP_D2", ser()), file.path(SA, "D2run"))
write_contract(file.path(SA, "B1run/remeasure_close_t1_t1"), ser(), modifyList(AUTH_T1("B"), list(status = "FAIL")))
MC$RP_B1 <- cat_entry(write_sim("RP_B1", ser()), file.path(SA, "B1run"))
write_contract(file.path(SA, "A1run/remeasure_close_t1_aa"), ser(), AUTH_T1("B")); write_contract(file.path(SA, "A1run/remeasure_close_t1_bb"), ser(), AUTH_T1("B"))
MC$RP_A1 <- cat_entry(write_sim("RP_A1", ser()), file.path(SA, "A1run"))
MC$RP_X1 <- cat_entry(write_sim("RP_X1", ser()), NULL, file.path(SA, "no_such_run/bt_result.rds"))
write_json(list(modules = MC), file.path(PB, "06_Registry/module_catalog.json"), auto_unbox = TRUE, pretty = TRUE)
## 레거시 QEPM(grade_a_catalog · 카탈로그 밖 · 산출물 없음)
write_sim("STR_L1", ser(), dir = "STR_L1_legacy")
write_json(list(strategies = data.frame(strategy_id = "STR_L1", grade = "A", role = "core")), file.path(PB, "04_Research/grade_a_catalog.json"), auto_unbox = TRUE)
EXP_EXCL <- c(RP_D1 = "no_close_t1:exec_unlabeled", RP_D2 = "no_close_t1:close_d_legacy", RP_B1 = "close_t1_invalid:auth",
              RP_A1 = "close_t1_ambiguous", RP_X1 = "no_close_t1:no_artifacts", STR_L1 = "no_close_t1:legacy_no_artifacts")

child_env <- function(extra = list()) {
  base <- list(QM_ROOT = PB, CLAUDE_PROJECT_DIR = PB, R_ENVIRON_USER = EMPTY_RENV, QVEST_C11_LEGACY_REGIME = "",
               QVEST_L2_POOL_MODE = "", QVEST_FR_ALLOW_BROAD_SCAN = "0", QVEST_L2_INCLUDE_NON_CLOSE_T1 = "0",
               QVEST_L2_DRY_RUN = "0", QVEST_L2_DRY_RUN_OUT = "")
  for (k in names(extra)) base[[k]] <- extra[[k]]
  unlist(base)
}
bmp_dry <- function(script, tag, extra = list()) {
  out <- file.path(TMP, paste0("dry_", tag, ".json")); if (file.exists(out)) file.remove(out)
  r <- run_child(script, child_env(c(list(QVEST_L2_DRY_RUN = "1", QVEST_L2_DRY_RUN_OUT = out), extra)))
  j <- if (file.exists(out)) fromJSON(out, simplifyVector = FALSE) else NULL
  if (is.null(j)) cat(tail(r$out, 12), sep = "\n")
  list(r = r, j = j)
}
sr3 <- function(x) round(mean(x) / sd(x) * sqrt(252), 3)                 # 빌더와 독립인 손 유도(첫 행 = 라벨 없음 → 제외)
DER_R1 <- file.path(PB, "04_Research/factor_rotation/l2_pool_series/RP_R1/sim_result.rds")

cat("\n── A. 기본(강제) · dry-run ──\n")
A <- bmp_dry(BN, "A")
J <- A$j
ok(A$r$status == 0L && !is.null(J), sprintf("A0 완주(status %d)", A$r$status))
if (!is.null(J)) {
  ok(setequal(names(J$modules), c("RP_R1", "RP_R2", "RP_N1")) && identical(as.integer(J$n_modules), 3L),
     sprintf("A1 풀 = close_t1 계열 3모듈만 (실제 %s)", paste(names(J$modules), collapse = ",")))
  ex <- setNames(vapply(J$execution_convention$excluded, function(e) as.character(e$code), ""), vapply(J$execution_convention$excluded, function(e) as.character(e$id), ""))
  ok(isTRUE(J$execution_convention$enforced) && setequal(names(ex), names(EXP_EXCL)) && all(ex[names(EXP_EXCL)] == EXP_EXCL),
     sprintf("A2 제외 6종 = 사유 코드 일치 (%s)", paste(sprintf("%s=%s", names(ex), ex), collapse = " · ")))
  ok(all(vapply(J$execution_convention$excluded, function(e) nzchar(e$reason %||% ""), logical(1))), "A3 제외마다 사유 문장 기록(침묵 제외 없음)")
  m1 <- J$modules$RP_R1
  ok(identical(m1$series_source, "close_t1_remeasure") && identical(m1$sim_result_path, "04_Research/factor_rotation/l2_pool_series/RP_R1/sim_result.rds") &&
       identical(m1$registered_sim_result_path, "04_Research/strategies/RP_R1/sim_result.rds") &&
       identical(m1$series_dir, file.path(SA, "R1run/remeasure_close_t1_t1")) && identical(m1$series_grade, "C"),
     "A4 R1: 소비 = l2_pool_series 재조립 · 등재 sim 병기 · 판 디렉터리 · 그 판 등급(C)")
  d1 <- tryCatch(readRDS(DER_R1), error = function(e) NULL)
  ok(!is.null(d1) && length(d1$DAILY_NAV_DT$Strategy_Ret) == length(MD) &&
       isTRUE(max(abs(as.numeric(d1$DAILY_NAV_DT$Strategy_Ret) - R1_T1)) < 1e-12) &&
       isTRUE(max(abs(as.numeric(d1$bm_xts[, 1]) - BMR)) < 1e-12) &&
       all(as.numeric(as.Date(d1$DAILY_NAV_DT$Date)) == as.numeric(MD)),
     "A5 ★R1 재조립 계열 = remeasure 판 계약 CSV(ret_net · benchmark_ret) 그대로(새 측정 없음)")
  ok(isTRUE(abs(m1$full_sharpe - sr3(R1_T1[-1])) < 1e-9) && !isTRUE(abs(m1$full_sharpe - sr3(R1_D[-1])) < 1e-9),
     sprintf("A6 ★국면 성과 입력 = close_t1 계열(full_sharpe %.3f = 손 유도 %.3f · close_d 판 %.3f 아님)", m1$full_sharpe, sr3(R1_T1[-1]), sr3(R1_D[-1])))
  ok(identical(J$modules$RP_R2$sim_result_path, "04_Research/strategies/RP_R2/sim_result.rds") && identical(J$modules$RP_R2$series_source, "close_t1_remeasure") &&
       !file.exists(file.path(PB, "04_Research/factor_rotation/l2_pool_series/RP_R2")),
     "A7 R2: 등재 sim 이 바로 그 판 → 등재 sim 그대로(재조립 없음)")
  ok(identical(J$modules$RP_N1$sim_result_path, "04_Research/strategies/RP_N1/sim_result.rds") && identical(J$modules$RP_N1$series_source, "native_close_t1") &&
       identical(J$modules$RP_N1$series_grade, "B"), "A8 N1: 신판 close_t1 → 등재 sim 그대로(native_close_t1)")
  ok(identical(as.integer(J$execution_convention$n_series_written), 1L) && identical(J$execution_convention$series_source_counts$close_t1_remeasure, 2L) &&
       identical(J$execution_convention$series_source_counts$native_close_t1, 1L),
     "A9 집계: 재조립 1건 기록 · 계열 출처 remeasure 2 · 신판 1")
  ok(!file.exists(file.path(PB, "06_Registry/module_performance.json")), "A10 dry-run = 정본 미기록")
}

cat("\n── B. 진단 스위치 ──\n")
B1 <- bmp_dry(BN, "B1", list(QVEST_L2_INCLUDE_NON_CLOSE_T1 = "1"))
if (!is.null(B1$j)) {
  jb <- B1$j
  ok(identical(as.integer(jb$n_modules), 9L) && identical(jb$execution_convention$enforced, FALSE) &&
       identical(as.integer(jb$execution_convention$n_included_non_close_t1), 6L) &&
       identical(jb$modules$RP_D1$series_source, "registered_sim_non_close_t1:no_close_t1:exec_unlabeled") &&
       identical(jb$modules$RP_D1$sim_result_path, "04_Research/strategies/RP_D1/sim_result.rds"),
     sprintf("B1 스위치 + dry-run = 혼합 포함 9모듈 · enforced=FALSE · 비 close_t1 6 표식 (실제 %s)", jb$n_modules))
} else ok(FALSE, "B1 dry-run 산출 부재")
B2 <- run_child(BN, child_env(list(QVEST_L2_INCLUDE_NON_CLOSE_T1 = "1")))
ok(B2$status != 0L && any(grepl("QVEST_L2_DRY_RUN=1 과 함께만", B2$out, fixed = TRUE)) && !file.exists(file.path(PB, "06_Registry/module_performance.json")),
   sprintf("B2 스위치 + 비 dry-run = 중단 · 정본 미기록 (status %d)", B2$status))

cat("\n── C. 정본 경로 · 멱등 ──\n")
md5_der <- unname(tools::md5sum(DER_R1))
C1 <- run_child(BN, child_env())
jc <- if (file.exists(f <- file.path(PB, "06_Registry/module_performance.json"))) fromJSON(f, simplifyVector = FALSE) else NULL
ok(C1$status == 0L && !is.null(jc) && setequal(names(jc$modules), c("RP_R1", "RP_R2", "RP_N1")) && isTRUE(jc$execution_convention$enforced),
   sprintf("C1 정본 기록 = 3모듈 · 강제 (status %d)", C1$status))
ok(!is.null(jc) && identical(as.integer(jc$execution_convention$n_series_written), 0L) && identical(unname(tools::md5sum(DER_R1)), md5_der),
   "C2 멱등: 원천 CSV 같으면 재조립 파일을 다시 쓰지 않는다(md5 불변)")
ok(any(grepl("집행 규약 close_t1 단일 · 계열 close_t1_remeasure=2 · native_close_t1=1 · 규약 제외 6", C1$out, fixed = TRUE)),
   "C3 기록 로그 1줄에 규약·계열·제외 수(daily_refresh [8.2] 의 'module_performance.json written' grep 이 집는 줄)")

cat("\n── D. 돌연변이(같은 픽스처에서 빨개져야 한다) ──\n")
muts <- list(
  list(tag = "noexcl", old = "if (!.INCLUDE_NON_CT1) return(invisible(FALSE))", new = "if (FALSE) return(invisible(FALSE))",
       chk = function(j) is.null(j) || !identical(as.integer(j$n_modules), 3L), why = "제외 줄 삭제 → 혼합 풀"),
  list(tag = "regsim", old = "src <- if (!is.null(ser) && !is.na(ser$path %||% NA)) ser$path else f", new = "src <- f",
       chk = function(j) is.null(j) || !isTRUE(abs(j$modules$RP_R1$full_sharpe - sr3(R1_T1[-1])) < 1e-9), why = "소비 계열 = 등재 sim(close_d)"),
  list(tag = "native", old = "  if (identical(ex$exec, \"close_t1\")) {\n    if (!.auth_ok(ex$auth))", new = "  if (TRUE) {\n    if (!.auth_ok(ex$auth))",
       chk = function(j) is.null(j) || "RP_D1" %in% names(j$modules) || "RP_D2" %in% names(j$modules), why = "신판 판독 무력화 → close_d 를 신판으로"))
for (mu in muts) {
  fm <- mutate_file(BN, mu$old, mu$new, mu$tag)
  if (is.na(fm)) { ok(FALSE, sprintf("D %s 돌연변이 대상 줄 부재", mu$tag)); next }
  w <- bmp_dry(fm, paste0("M_", mu$tag))
  ok(w$r$status != 0L || isTRUE(mu$chk(w$j)), sprintf("D %s ★red: %s (status %d)", mu$tag, mu$why, w$r$status))
}

cat("\n── Z. 운영 무쓰기 ──\n")
ok(identical(unname(tools::md5sum(OPS_FILES)), unname(MD5_BEFORE)), sprintf("Z1 운영 풀·카탈로그 md5 불변(%d파일)", length(OPS_FILES)))
SER_AFTER <- if (dir.exists(SER_OPS)) tools::md5sum(sort(list.files(SER_OPS, recursive = TRUE, full.names = TRUE))) else character(0)
ok(identical(SER_AFTER, SER_BEFORE), "Z2 운영 l2_pool_series 불변(검사는 샌드박스에만 재조립)")
unlink(TMP, recursive = TRUE)
finish()
