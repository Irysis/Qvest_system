#!/usr/bin/env Rscript
#==============================================================================
# test_rf_rebase_driver.R — P0-05 재측정 → P0-06 원장 rebase 드라이버 종단 검사 (2026-09-24 · 통합 검증 I1·I2)
#
# 대상: 02_Infrastructure/reinforcement/rf_rebase_driver.R (rfr_plan · rfr_remeasure · rfr_items · rfr_rebase · rfr_epoch)
#   + 실제 P0-05 계약(remeasure_from_holdings.R) · 원장 writer(reinforce_ledger.R) · 적대검증 규약 판독(rf_overlay_adversary.R) ·
#     러너 관문(rf_runner_gates.R) — 스크래치 스크립트 없이 저장소 코드만으로 통합 드라이런이 끝까지 가는가.
# 픽스처(샌드박스 — 운영 무접촉): 골든 20260921_100007_6876 사본(칸 + 승격 기저 공유) · B6 20260921_155730_10736 사본(기저 전용) ·
#   C11 표식 칸 · native close_t1 칸 2개(가짜 auth) · 산출물 없는 legacy 칸(부분 rebase entry)
# 재는 것:
#   P 계획 — 전환 이전 칸·기저만 · native close_t1 제외 · C11 skip · D-A N(1 + 계보 측정 칸 · 상속 제외 · 산출물 참조 최대) ·
#          기저 전용 산출물 = 저장 기록 · 승격 기저 = 부모 승자 칸의 sweep N
#   M 재측정 — 칸별 채점 열로 형제 판(sweep/N · chain/1) · 재호출 = 캐시(R① 채점 대조 통과)
#   I 항목 — regime = P0-05 키 · essence_new = 정본 조립기 · C11·형제 부재 = missing(사유) · 채점 불일치 = scoring_mismatch
#       [돌연변이] 채점 대조 제거 → 낡은 채점 판이 항목이 된다
#   R rebase — 계획 뒤 원장 변경 = 거부 · 실제 쓰기: essence = 형제 판 측정 값(dsr·N·selection_type) · 구 dsr 은 history ·
#       등급 = 형제 판 · 자식 parent best 갱신 · 기저 2건
#   A 소비자 — 적대검증 규약 판독이 rebase 칸을 형제 판(close_t1 · declared_verified)으로 읽는다(I2 — 구판은 conflict) ·
#       러너 관문 regime·회계(rebase_sibling · sweep N)
#   E epoch — 부분 rebase(off_regime) 거부 · 승계 0 거부 · 전 칸 뒤 승계(require_regime = 규약명 ∪ 키)
# 운영 무접촉: 운영 원장·stage_artifacts 는 읽기만(골든·B6 원본 md5 전후 동일) · 시장 데이터 읽기만.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; why <- paste(as.character(why), collapse = " "); cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
sk <- function(m) { SKIP <<- SKIP + 1L; cat("  SKIP", m, "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
finish <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d · 건너뜀 %d\n", PASS, FAIL, SKIP))
  cat(sprintf('{"test":"rf_rebase_driver","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n', PASS, FAIL, PASS + FAIL, SKIP))
  quit(status = if (FAIL == 0L) 0L else 1L)
}
Sys.unsetenv("QVEST_RF_CLAIM"); Sys.unsetenv("QVEST_CONSTRAINT_DEFAULTS")
GOLD <- file.path(ROOT, "stage_artifacts/replication/20260921_100007_6876")
B6   <- file.path(ROOT, "stage_artifacts/replication/20260921_155730_10736")
if (!all(file.exists(file.path(c(GOLD, B6), "bt_result.rds"))) || !file.exists(file.path(ROOT, ".cache/RAWDATA.parquet"))) {
  sk("재료 부재(골든·B6 산출물·RAWDATA 캐시) — 미측정"); finish() }
md5_src0 <- tools::md5sum(c(list.files(GOLD, full.names = TRUE), list.files(B6, full.names = TRUE)))

invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_rebase_driver.R"), encoding = "UTF-8"))))
rfr_load(ROOT)
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_overlay_adversary.R"), encoding = "UTF-8"))))

# ── 샌드박스 ────────────────────────────────────────────────────────────────
SB <- gsub("\\\\", "/", tempfile("rd"))    # 짧게(Windows 260자 — 형제 판 CSV 경로)
for (d in c("06_Registry", "02_Infrastructure/worktask", "sa", ".cache")) dir.create(file.path(SB, d), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(SB, "02_Infrastructure/worktask"))
file.copy(file.path(ROOT, "06_Registry/pit_quarantine.json"), file.path(SB, "06_Registry"))
cpy <- function(src, nm) { d <- file.path(SB, "sa", nm); dir.create(d, recursive = TRUE)
  file.copy(file.path(src, c("bt_result.rds", "authoritative_remeasure.json", "01_strategy_spec.json")), d); d }
AG <- cpy(GOLD, "20260921_100007_6876"); AB <- cpy(B6, "20260921_155730_10736"); AC <- cpy(GOLD, "20260921_100007_c11")
fake <- function(nm, ep = "close_t1") { d <- file.path(SB, "sa", nm); dir.create(d, recursive = TRUE)
  writeLines(toJSON(list(essence_grade = "C", measurement_regime = list(exec_price = ep, selection_type = "sweep", n_trials_cumulative = 3L)),
                    auto_unbox = TRUE), file.path(d, "authoritative_remeasure.json")); d }
AN1 <- fake("native_1"); AN2 <- fake("native_2")
CUR <- rf_current_regime(SB)$regime
ess <- function(cc, pt, cm, extra = list()) c(list(cell_code = cc, block = sub("_.*$", "", cc), port_t = pt, net_sharpe = 1.1, cagr = 0.27,
                                                  mdd = 0.55, calmar = cm, oos_retention = 0.1, dsr = 0.61, selection_type = "chain",
                                                  n_trials_cumulative = 1L, spec = "C:/x/spec_fixture.json", source = "authoritative_remeasure.json",
                                                  beta = 0.8), extra)
c11 <- list(list(flag = "pit_c11", verdict = "consumed", evidence = "fixture"))
L <- .rf_skeleton(1L); L$current_axis <- "n_max_25"
ent <- function(bid, attempts, ...) { e <- list(base_id = bid, base_grade = "B", paper_key = "fixture", status = "exhausted", measurement_axis = "n_max_25",
                                                axis_valid = TRUE, attempts_used = length(attempts), attempts = attempts)
  x <- list(...); for (k in names(x)) e[[k]] <- x[[k]]; e }
att <- function(n, cc, art, e, grade = "B", ...) { a <- list(n = as.integer(n), cell_code = cc, grade = grade, artifacts = art, essence = e)
  x <- list(...); for (k in names(x)) a[[k]] <- x[[k]]; a }
L$entries <- list(
  ent("D_P", list(att(1, "B1_1", AG, ess("B1_1", 4.349, 0.501)),
                  att(2, "B1_2", AC, ess("B1_2", 2.0, 0.2), vintage_flags = c11),
                  att(3, "B2_6", AN1, ess("B2_6", 1.5, 0.15)),
                  att(4, "B2_7", AN1, ess("B2_7", 1.5, 0.15, list(inherited_from = "B2_6")))),   # 상속 칸 — N 에서 제외
      base_artifacts = AB),
  ent("D_P_promo1", list(att(1, "B1_1", AN2, ess("B1_1", 3.0, 0.3))), status = "active", base_artifacts = AG,
      parent = list(base_id = "D_P", depth = 1L, cell = "B1_1", best_port_t = 4.349, best_calmar = 0.501, promoted_at = "2026-09-20T12:00:00+0900")),
  ent("D_U", list(att(1, "B1_1", file.path(SB, "sa", "gone"), ess("B1_1", 1.0, 0.1)))))   # 산출물 없는 legacy 칸 — 부분 rebase entry
.rf_write(L, 1L, SB)
LP <- .rf_path(1L, SB)

cat("\n=== P 계획 ===\n")
e <- err_of(rfr_plan(1L, file.path(SB, "no_such_root"), code_root = ROOT))
chk(!is.na(e) && grepl("06_Registry 가 없다", e), "P0 명시 root 가 틀리면 멈춘다 — 다른 루트(운영)로 넘어가지 않는다(2026-09-24 실사고 재발 방지)", e)
P <- rfr_plan(1L, SB, code_root = ROOT)
if (!startsWith(tolower(attr(P, "ledger_path")), tolower(SB))) { ng("P0b 계획 원장이 샌드박스 밖 — 검사 중단(운영 쓰기 방지)", attr(P, "ledger_path")); finish() }
row <- function(b, nn) P[base_id == b & P$n == nn]
chk(identical(attr(P, "exec_price"), CUR) && nrow(P) == 5L && !nrow(row("D_P", "3")) && !nrow(row("D_P_promo1", "1")),
    sprintf("P1 계획 = 전환 이전 칸·기저 5행(native %s 칸 2개 제외) · 목표 = 현행 규약 %s", CUR, CUR), paste(P$base_id, P$n, collapse = " | "))
chk(isTRUE(row("D_P", "2")$skip) && grepl("pit_c11", row("D_P", "2")$skip_reason), "P2 C11 표식 칸 → skip(blocked_flag:pit_c11)")
# D-A: D_P 계보 측정 칸 = n1·n2·n3(n4 상속 제외) = 3 → N 4 · 승격 기저(골든 공유)는 부모 칸 참조 최대 N 4 · 기저 전용(B6) = 저장 기록
chk(identical(row("D_P", "1")$selection_type, "sweep") && identical(row("D_P", "1")$n_trials_cumulative, 4L) &&
      identical(row("D_P_promo1", "base")$selection_type, "sweep") && identical(row("D_P_promo1", "base")$n_trials_cumulative, 4L) &&
      is.na(row("D_P", "base")$selection_type) && grepl("stored_auth", row("D_P", "base")$n_trials_basis),
    "P3 ★D-A 채점 — 칸 = sweep · N = 1 + 계보 측정 칸(상속 제외) = 4 · 골든을 공유하는 승격 기저도 같은 N · 기저 전용 산출물 = 저장 기록",
    paste(sprintf("%s#%s=%s/%s", P$base_id, P$n, P$selection_type, P$n_trials_cumulative), collapse = " "))

cat("\n=== M 재측정 (실제 P0-05 · 샌드박스 사본 in-place) ===\n")
e <- err_of(rfr_remeasure(P, SB))
chk(!is.na(e) && grepl("in_place=TRUE", e), "M1 in_place 미명시 → 재측정 거부(운영 쓰기 = 별도 승인)")
S9 <- file.path(SB, "e9"); dir.create(file.path(S9, "06_Registry"), recursive = TRUE)
e <- err_of(rfr_remeasure(P, S9, in_place = TRUE, n_workers = 1L, claim = FALSE, barrier = FALSE))
chk(!is.na(e) && grepl("root 밖", e) && !length(list.files(SB, pattern = "^remeasure_", recursive = TRUE, include.dirs = TRUE)),
    "M1b 계획 원장·산출물이 쓰기 root 밖 → in-place 쓰기 거부 · 쓰기 0(계획과 쓰기 root 불일치 차단)", e)
t0 <- Sys.time()
B <- NULL; e <- err_of(invisible(capture.output(B <- rfr_remeasure(P, SB, in_place = TRUE, n_workers = 1L, claim = FALSE, barrier = FALSE))))
cat(sprintf("    (재측정 %.0f초)\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
KEY <- rfh_regime(CUR, ROOT)$key
sg <- file.path(AG, paste0("remeasure_", KEY), "authoritative_remeasure.json"); sb <- file.path(AB, paste0("remeasure_", KEY), "authoritative_remeasure.json")
jg <- if (file.exists(sg)) fromJSON(sg, simplifyVector = FALSE) else list(); jb <- if (file.exists(sb)) fromJSON(sb, simplifyVector = FALSE) else list()
chk(is.na(e) && identical(B$status, "done") && identical(jg$measurement_regime$selection_type, "sweep") &&
      identical(as.integer(jg$measurement_regime$n_trials_cumulative), 4L) && identical(jb$measurement_regime$selection_type, "chain") &&
      identical(as.integer(jb$measurement_regime$n_trials_cumulative), 1L) && !dir.exists(file.path(AC, paste0("remeasure_", KEY))),
    "M2 형제 판 — 골든 = sweep/4(D-A) · B6 = chain/1(저장) · C11 칸은 재측정 안 함", paste(e, B$status))
chk(identical(jg$measurement_regime$regime, KEY) && abs(jg$essence$portfolio_alpha_t_nw_lag3 - 3.777) < 5e-4 &&
      all(file.exists(file.path(dirname(sg), c("03_period_returns.csv", "04_holdings.csv")))),
    sprintf("M3 골든 형제 판 = %s · PT %.3f(P0-04 3.777) · 03/04 CSV 포함", KEY, jg$essence$portfolio_alpha_t_nw_lag3 %||% NA))
B2 <- NULL; invisible(capture.output(B2 <- rfr_remeasure(P, SB, in_place = TRUE, n_workers = 1L, claim = FALSE, barrier = FALSE)))
chk(identical(B2$status, "done") && all(B2$rows$t1_cached), "M4 재호출 = 캐시(같은 채점 인자 — R① 대조 통과 · 다시 재지 않는다)")

cat("\n=== I 항목 ===\n")
I <- rfr_items(P, SB, code_root = ROOT)
ks <- vapply(I$items, function(x) paste0(x$base_id, "#", x$n), "")
chk(setequal(ks, c("D_P#1", "D_P#base", "D_P_promo1#base")) && all(vapply(I$items, function(x) identical(x$regime, KEY), logical(1))) &&
      nrow(I$missing) == 2L && any(grepl("pit_c11", I$missing$reason)) && any(I$missing$reason == "sibling_absent"),
    "I1 항목 3(칸 1 · 기저 2) · regime = P0-05 키 · missing = C11 skip + 형제 부재(D_U) — 사유가 남는다", paste(ks, collapse = ","))
en <- Filter(function(x) identical(x$base_id, "D_P") && identical(x$n, 1L), I$items)[[1]]$essence_new
chk(isTRUE(abs(en$dsr - jg$essence$dsr) < 1e-12) && identical(en$n_trials_cumulative, 4L) && is.null(en$beta) && identical(en$spec, "C:/x/spec_fixture.json"),
    "I2 essence_new = 정본 조립기(형제 dsr·N · 구 보조 값 beta 소멸 · 신원 spec 유지)")
P5 <- copy(P); attributes(P5) <- attributes(P); P5[base_id == "D_P" & n == "1", n_trials_cumulative := 5L]
P5[base_id == "D_P_promo1" & n == "base", n_trials_cumulative := 5L]
I5 <- rfr_items(P5, SB, code_root = ROOT)
chk(sum(grepl("scoring_mismatch", I5$missing$reason)) == 2L && length(I5$items) == 1L,
    "I3 계획 N(5) ≠ 형제 판 N(4) → 그 칸들은 항목에서 빠진다(scoring_mismatch · 낡은 채점 판으로 rebase 하지 않는다)")
EI <- new.env(); invisible(capture.output(sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_rebase_driver.R"), envir = EI)))
body_txt <- deparse(EI$rfr_items, width.cutoff = 500L)
mut_txt <- sub("want_st <- r$selection_type", "want_st <- NA_character_", paste(body_txt, collapse = "\n"), fixed = TRUE)
if (identical(mut_txt, paste(body_txt, collapse = "\n"))) ng("I4 돌연변이 패턴 부재") else {
  fm <- eval(parse(text = mut_txt)); environment(fm) <- globalenv()
  Im <- fm(P5, SB, code_root = ROOT)
  chk(length(Im$items) == 3L, "I4 [돌연변이] 채점 대조 제거 → 낡은 채점 판(N 4 ≠ 계획 5)이 항목이 된다 — I3 이 잡는다")
}

cat("\n=== R rebase ===\n")
raw0 <- readBin(LP, "raw", file.info(LP)$size)
L2 <- rf_load(1L, SB); L2$note_touch <- "외부 쓰기 흉내"; .rf_write(L2, 1L, SB)
e <- err_of(rfr_rebase(P, I$items, SB, dry_run = TRUE))
chk(!is.na(e) && grepl("계획 뒤 원장이 바뀌었다", e), "R1 계획 뒤 원장 변경 → rebase 거부(D-A N 이 낡는다)", e)
writeBin(raw0, LP)
R0 <- NULL; e <- err_of(invisible(capture.output(R0 <- rfr_rebase(P, I$items, SB, dry_run = TRUE))))
chk(is.na(e) && R0$n_rebased == 3L && !isTRUE(R0$written), "R2 dry_run — 3칸 계획 · 쓰기 없음", e)
R1 <- NULL; e <- err_of(invisible(capture.output(R1 <- rfr_rebase(P, I$items, SB, dry_run = FALSE))))
LA <- rf_load(1L, SB); eP <- LA$entries[[.rf_find(LA, "D_P")]]; eK <- LA$entries[[.rf_find(LA, "D_P_promo1")]]
a1 <- eP$attempts[[1]]
chk(is.na(e) && isTRUE(R1$written) && R1$n_rebased == 3L && identical(a1$grade, jg$essence_grade) &&
      isTRUE(abs(a1$essence$port_t - jg$essence$portfolio_alpha_t_nw_lag3) < 1e-6) && isTRUE(abs(a1$essence$dsr - jg$essence$dsr) < 1e-6) &&
      identical(a1$essence$selection_type, "sweep") && identical(a1$essence$n_trials_cumulative, 4L) && is.null(a1$essence$beta) &&
      isTRUE(abs(a1$essence_history$close_d_legacy$essence$dsr - 0.61) < 1e-12),
    "R3 ★rebase 기록 — 등급·측정 키 전부 형제 판(PT·dsr·sweep/4) · 구 dsr 0.61·beta 는 history 에만(L-B2)", e)
chk(identical(a1$measurement_regime$regime, KEY) && identical(a1$measurement_regime$exec_price, CUR) &&
      isTRUE(abs(eK$parent$best_port_t - jg$essence$portfolio_alpha_t_nw_lag3) < 1e-6) && length(eK$parent_rebased_from) == 1L &&
      identical(eP$base_grade, jb$essence_grade) && identical(eK$base_measurement_regime$regime, KEY),
    "R4 원장 표식 regime = 키 · exec_price = 현행 · 자식 parent best 갱신 · 기저 2건(B6 전용 · 승격 공유) rebase")

cat("\n=== A 소비자 (적대검증 규약 판독 · 러너 관문) ===\n")
x <- .adv_attempt_exec(a1, .adv_art_dir(a1, SB))
chk(identical(x$status, "declared_verified") && identical(x$exec_price, CUR) && identical(tolower(.adv_art_dir(a1, SB)), tolower(dirname(sg))),
    "A1 ★I2 적대검증 — rebase 칸의 산출물 = 형제 판 · 규약 declared_verified(close_t1) · Calmar 대조 통과", paste(x$status, x$source))
xo <- .adv_attempt_exec(a1, AG)
chk(identical(xo$status, "conflict"), "A2 [대조] 옛 산출물(원장 artifacts)로 읽으면 conflict — 통합 검증 I2 재현(A1 이 그 경로를 피한다)", xo$status)
ctx <- rf_runner_ctx(SB)
cr <- rf_cell_regime(a1, ctx)
el <- rf_a_eligibility(eP, modifyList(a1, list(grade = "A")), NULL, rf_a_ctx(ctx, LA$entries, "D_P"))
chk(identical(cr$regime, CUR) && identical(el$facts$accounting_source, "rebase_sibling") && identical(as.integer(el$facts$n_trials), 4L) &&
      identical(el$facts$selection_type, "sweep") && !("legacy_regime" %in% el$codes) && !("accounting_fail" %in% el$codes),
    "A3 러너 관문 — rebase 칸 규약 = 현행 · A 회계 원천 = 형제 판(sweep/4 · D-A)", paste(cr$regime, el$facts$accounting_source, paste(el$codes, collapse = "+")))

cat("\n=== E epoch ===\n")
e <- err_of(invisible(capture.output(rfr_epoch(1L, SB, epoch = "exec_close_t1", legacy = "n_max_25@close_d_legacy", reason = "검사",
                                                evidence = "test_rf_rebase_driver", code_root = ROOT))))
chk(!is.na(e) && grepl("rebase 가 안 끝난 entry", e) && grepl("D_U", e), "E1 부분 rebase(D_U off_regime) → 전환 거부", e)
d <- NULL; e <- err_of(invisible(capture.output(d <- rfr_epoch(1L, SB, epoch = "exec_close_t1", legacy = "n_max_25@close_d_legacy", reason = "검사",
                                                                evidence = "test_rf_rebase_driver", allow_partial = TRUE, code_root = ROOT))))
chk(is.na(e) && d$n_carried == 2L && all(c(CUR, KEY) %in% d$require_regime) && !isTRUE(d$written),
    "E2 allow_partial dry_run — 승계 2(D_P: rebase + native + C11 칸 목록화 · promo1) · require_regime = 규약명 ∪ 키", e)
S0 <- file.path(SB, "e0"); dir.create(file.path(S0, "06_Registry"), recursive = TRUE); dir.create(file.path(S0, "02_Infrastructure/worktask"), recursive = TRUE)
file.copy(file.path(SB, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(S0, "02_Infrastructure/worktask"))
file.copy(file.path(SB, "06_Registry/pit_quarantine.json"), file.path(S0, "06_Registry"))
writeBin(raw0, file.path(S0, "06_Registry/reinforce_ledger_l1.json"))     # rebase 전 판
e <- err_of(invisible(capture.output(rfr_epoch(1L, S0, epoch = "exec_close_t1", legacy = "x", reason = "r", evidence = "e",
                                                allow_partial = TRUE, code_root = ROOT))))
chk(!is.na(e) && grepl("승계 0건", e), "E3 rebase 전 원장 — 승계 0 → 전환 거부(결합 풀이 빈다)", e)
LA$entries <- Filter(function(e) !identical(e$base_id, "D_U"), LA$entries); .rf_write(LA, 1L, SB)
x <- NULL; e <- err_of(invisible(capture.output(x <- rfr_epoch(1L, SB, epoch = "exec_close_t1", legacy = "n_max_25@close_d_legacy", reason = "검사",
                                                                evidence = "test_rf_rebase_driver", dry_run = FALSE, code_root = ROOT))))
LE <- rf_load(1L, SB)
chk(is.na(e) && isTRUE(x$written) && identical(LE$current_axis, "exec_close_t1") &&
      all(vapply(LE$entries, function(e) identical(e$measurement_axis, "exec_close_t1"), logical(1))) &&
      identical(unlist(LE$entries[[.rf_find(LE, "D_P")]]$axis_blocked_legacy), "2"),
    "E4 전 칸 rebase 뒤 전환 — 전 entry 새 축 승계 · C11 칸(n2)은 axis_blocked_legacy", e)

cat("\n=== F 러너 폴백 — 형제 판(in-place)을 새 측정으로 집지 않는다 (L-B1 위치 계약) ===\n")
# 세 폴백(reinforce_auto_run.R · rf_cell_worker.R · rf_replication_verify.R)을 소스에서 떼어 가짜 stage_artifacts 로 실행.
#   r_old/authoritative_remeasure.json(옛 · strategy_name X) · r_old/remeasure_<키>/authoritative_remeasure.json(새 mtime · 같은 X)
FB <- file.path(SB, "fb"); dir.create(file.path(FB, "stage_artifacts/replication/r_old/remeasure_close_t1_ab12cd34"), recursive = TRUE)
fa <- file.path(FB, "stage_artifacts/replication/r_old/authoritative_remeasure.json")
fr <- file.path(FB, "stage_artifacts/replication/r_old/remeasure_close_t1_ab12cd34/authoritative_remeasure.json")
writeLines(toJSON(list(strategy_name = "X", essence_grade = "C"), auto_unbox = TRUE), fa)
writeLines(toJSON(list(strategy_name = "X", essence_grade = "B", kind = "remeasure_from_holdings"), auto_unbox = TRUE), fr)
Sys.setFileTime(fa, Sys.time() - 3600); Sys.setFileTime(fr, Sys.time())
grab <- function(f, start_re, end_re) { s <- readLines(file.path(ROOT, f), warn = FALSE, encoding = "UTF-8")
  i0 <- grep(start_re, s)[1]; if (is.na(i0)) return(NULL); i1 <- i0 + which(grepl(end_re, s[(i0 + 1L):length(s)]))[1]
  if (is.na(i1)) NULL else s[i0:i1] }
FBS <- list(
  run = list(f = "02_Infrastructure/ops/reinforce_auto_run.R", s = "^ar_p <- res\\$authoritative_remeasure_path", e = "^\\}$", v = "ar_p"),
  worker = list(f = "02_Infrastructure/ops/rf_cell_worker.R", s = "^ar <- res\\$authoritative_remeasure_path", e = "^\\}$", v = "ar"),
  verify = list(f = "02_Infrastructure/ops/rf_replication_verify.R", s = "^ar <- res\\$authoritative_remeasure_path", e = "^\\}$", v = "ar"))
for (nm in names(FBS)) {
  b <- FBS[[nm]]; L0 <- grab(b$f, b$s, b$e)
  if (is.null(L0)) { ng(sprintf("F-%s 폴백 블록 추출 실패", nm)); next }
  runb <- function(lines) { env <- new.env(parent = globalenv()); env$ROOT <- FB; env$SNAME <- "X"
    env$res <- list(out_dir = file.path(FB, "nope")); eval(parse(text = lines, encoding = "UTF-8"), envir = env)
    gsub("\\\\", "/", get(b$v, envir = env)) }
  got <- runb(L0)
  mut <- L0[!grepl("cand <- cand[!grepl(\"/remeasure_", L0, fixed = TRUE)]
  gm <- if (length(mut) < length(L0)) runb(mut) else NA_character_
  chk(identical(tolower(got), tolower(gsub("\\\\", "/", fa))) && identical(tolower(gm), tolower(gsub("\\\\", "/", fr))),
      sprintf("F-%s 폴백은 remeasure_* 형제 판(더 새 mtime · 같은 strategy_name)을 건너뛰고 원 산출물을 고른다 · [돌연변이] 필터 줄 삭제 → 형제 판을 집는다", nm),
      sprintf("got=%s mut=%s", got, gm))
}

md5_src1 <- tools::md5sum(c(list.files(GOLD, full.names = TRUE), list.files(B6, full.names = TRUE)))
chk(identical(md5_src0, md5_src1) && !any(grepl("^remeasure_", c(list.files(GOLD), list.files(B6)))),
    "X1 운영 산출물(골든·B6) md5 불변 · 그 안에 remeasure_ 0(쓰기는 샌드박스 사본에만)")
unlink(SB, recursive = TRUE, force = TRUE)
finish()
