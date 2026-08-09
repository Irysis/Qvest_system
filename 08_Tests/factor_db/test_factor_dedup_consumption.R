#==============================================================================
# test_factor_dedup_consumption.R — de-dup **소비 배선**이 실제로 행동하는가
#
# 이 검사기가 지키는 것 (test_factor_dup_scan.R 은 *선언 구조*를 지킨다 — 여기는 *소비*):
#   1) 기본 동작 무변경  — 인자 없이 부르면 값이 이전과 동일한가 (회귀 방화벽)
#   2) 정본 해석 실효    — dedup=TRUE 가 실제로 alias 행을 없애는가
#   3) 위반 주입         — alias 를 안 접는 돌연변이 / 정본을 alias 로 잘못 매핑하는
#                          돌연변이에 검사가 빨개지는가 (검사 사망 탐지)
#   4) 양성 대조         — 중복 아닌 팩터(M26/V01_BM/M01_Mom_12_1)가 그대로 통과하는가
#   5) 고아 alias 보존   — canonical 부재 시 개명하지 않고 남기는가
#   6) fail-closed       — dedup=TRUE 인데 API 부재면 조용히 통과하지 않는가
#
# ★"0건은 정지 신호" — 각 축은 대상 수를 함께 보고한다. 대상이 0이면 PASS 가 아니라
#   SKIP 으로 내보내 '검사하지 않은 것'을 통과로 삼지 않는다.
#
# 실행: Rscript 08_Tests/factor_db/test_factor_dedup_consumption.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR",
                   Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
if (!file.exists(file.path(PROJ, "02_Infrastructure/factor_db/factor_dup_scan.R"))) {
  stop("[dedup_consumption] project root 아님 (marker 부재): ", PROJ)
}

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok   <- function(n, d = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(d)) paste0(" — ", d) else "")) }
bad  <- function(n, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s%s\n", n, if (nzchar(d)) paste0(" — ", d) else "")) }
skip <- function(n, d = "") { SKIP <<- SKIP + 1L; cat(sprintf("  SKIP: %s%s\n", n, if (nzchar(d)) paste0(" — ", d) else "")) }

source(file.path(PROJ, "02_Infrastructure/factor_db/factor_dup_scan.R"))

#==============================================================================
cat("=== 0) 합성 registry — 실 registry 와 독립으로 함수 계약을 시험 ===\n")
#==============================================================================
# 합성이라 실 데이터 상태에 흔들리지 않는다. 실 registry 축은 3)/4) 에서 따로 본다.
mk <- function(role = NULL, canonical = NULL, cluster = NULL, aliases = NULL,
               partners = NULL) {
  d <- list()
  if (!is.null(role))      d$role <- role
  if (!is.null(canonical)) d$canonical <- canonical
  if (!is.null(cluster))   d$cluster <- cluster
  if (!is.null(aliases))   d$aliases <- as.list(aliases)
  if (!is.null(partners))  d$partners <- as.list(partners)
  if (length(d)) list(dedup = d) else list()
}
REG <- list(
  CANON_A = mk("canonical", cluster = "T-001", aliases = c("ALIAS_A1", "ALIAS_A2")),
  ALIAS_A1 = mk("alias", canonical = "CANON_A", cluster = "T-001"),
  ALIAS_A2 = mk("alias", canonical = "CANON_A", cluster = "T-001"),
  CANON_B = mk("canonical", cluster = "T-002", aliases = "ORPHAN_B1"),
  ORPHAN_B1 = mk("alias", canonical = "CANON_B", cluster = "T-002"),
  RED_1 = mk("redundant", cluster = "T-003", partners = "RED_2"),
  RED_2 = mk("redundant", cluster = "T-003", partners = "RED_1"),
  CLEAN_1 = mk(), CLEAN_2 = mk()
)

mkpanel <- function(factors, n_ticker = 50L, seed = 1L) {
  set.seed(seed)
  CJ(Ticker = sprintf("T%03d", seq_len(n_ticker)), Factor_Name = factors)[
    , Z_Score_Aligned := rnorm(.N)][]
}

#==============================================================================
cat("=== 1) 정본 해석 실효 — dedup 이 실제로 alias 를 없애는가 ===\n")
#==============================================================================
p_all <- mkpanel(c("CANON_A", "ALIAS_A1", "ALIAS_A2", "RED_1", "RED_2", "CLEAN_1"))
out <- collapse_alias_rows(p_all, registry = REG, warn = FALSE)
kept <- sort(unique(out$Factor_Name))
dropped <- attr(out, "dedup_dropped")
if (setequal(dropped, c("ALIAS_A1", "ALIAS_A2")) &&
    setequal(kept, c("CANON_A", "CLEAN_1", "RED_1", "RED_2"))) {
  ok("collapse_drops_alias", sprintf("제거 %s / 잔존 %d종",
                                     paste(sort(dropped), collapse = ","), length(kept)))
} else {
  bad("collapse_drops_alias", sprintf("dropped=%s kept=%s",
                                      paste(dropped, collapse = ","), paste(kept, collapse = ",")))
}
# 행 수까지 — 라벨만 바뀌고 행이 남는 위장 방지
if (nrow(out) == nrow(p_all[!Factor_Name %in% c("ALIAS_A1", "ALIAS_A2")])) {
  ok("collapse_removes_rows_not_just_labels", sprintf("%d -> %d행", nrow(p_all), nrow(out)))
} else bad("collapse_removes_rows_not_just_labels", sprintf("%d행", nrow(out)))

# redundant 는 접지 않고 보고만
red <- attr(out, "dedup_redundant")
if (is.data.frame(red) && nrow(red) == 2L && all(c("RED_1", "RED_2") %in% red$factor)) {
  ok("redundant_reported_not_merged", "RED_1+RED_2 보고 / 잔존")
} else bad("redundant_reported_not_merged", sprintf("nrow=%s", if (is.null(red)) "NULL" else nrow(red)))

#==============================================================================
cat("=== 2) 고아 alias — canonical 부재 시 개명하지 않고 남기는가 ===\n")
#==============================================================================
p_orph <- mkpanel(c("ORPHAN_B1", "CLEAN_1"))       # CANON_B 없음
out2 <- collapse_alias_rows(p_orph, registry = REG, warn = FALSE)
if ("ORPHAN_B1" %in% out2$Factor_Name && !("CANON_B" %in% out2$Factor_Name) &&
    identical(attr(out2, "dedup_orphan_alias"), "ORPHAN_B1") &&
    nrow(out2) == nrow(p_orph)) {
  ok("orphan_alias_kept_not_renamed", "canonical 부재 → 유지 + 개명 없음")
} else {
  bad("orphan_alias_kept_not_renamed",
      sprintf("factors=%s orphan=%s", paste(unique(out2$Factor_Name), collapse = ","),
              paste(attr(out2, "dedup_orphan_alias"), collapse = ",")))
}

#==============================================================================
cat("=== 3) 양성 대조 — 중복 아닌 팩터는 건드리지 않는가 (합성) ===\n")
#==============================================================================
p_clean <- mkpanel(c("CLEAN_1", "CLEAN_2"))
out3 <- collapse_alias_rows(p_clean, registry = REG, warn = FALSE)
if (nrow(out3) == nrow(p_clean) && length(attr(out3, "dedup_dropped")) == 0L &&
    setequal(unique(out3$Factor_Name), c("CLEAN_1", "CLEAN_2"))) {
  ok("clean_factors_untouched", "제거 0 / 행수 동일")
} else bad("clean_factors_untouched", sprintf("%d행 dropped=%s", nrow(out3),
                                              paste(attr(out3, "dedup_dropped"), collapse = ",")))

#==============================================================================
cat("=== 4) 위반 주입 — 검사가 빨개지는가 (검사 사망 탐지) ===\n")
#==============================================================================
## 주입 A: alias 를 정본으로 안 바꾸는 돌연변이 (role 라벨 제거 = 배선 무력화)
REG_mutA <- REG
REG_mutA$ALIAS_A1$dedup$role <- "redundant"       # alias 가 아니게 됨
REG_mutA$ALIAS_A1$dedup$partners <- list("CANON_A")
outA <- collapse_alias_rows(p_all, registry = REG_mutA, warn = FALSE)
if ("ALIAS_A1" %in% outA$Factor_Name) {
  ok("inject_alias_not_collapsed_detected", "role 강등 → ALIAS_A1 잔존을 검사가 관측")
} else bad("inject_alias_not_collapsed_detected", "돌연변이인데 여전히 제거됨 — 검사 무력")

## 주입 B: 정본을 alias 로 잘못 매핑 (방향 반전) — canonical 이 사라지면 안 된다
REG_mutB <- REG
REG_mutB$CANON_A$dedup <- list(role = "alias", canonical = "ALIAS_A1", cluster = "T-001")
REG_mutB$ALIAS_A1$dedup <- list(role = "canonical", cluster = "T-001",
                                aliases = list("CANON_A"))
outB <- collapse_alias_rows(p_all, registry = REG_mutB, warn = FALSE)
if (!("CANON_A" %in% outB$Factor_Name) && "ALIAS_A1" %in% outB$Factor_Name) {
  ok("inject_reversed_mapping_detected",
     "정본↔alias 반전 → 보존 대상이 바뀜을 검사가 관측 (배선이 registry 를 실제로 읽는 증거)")
} else {
  bad("inject_reversed_mapping_detected",
      sprintf("반전 주입이 결과를 안 바꿈 — 배선이 registry 를 안 읽는다 (factors=%s)",
              paste(sort(unique(outB$Factor_Name)), collapse = ",")))
}

## 주입 C: alias 체인 (A -> B -> C). 고정점까지 해석되는가 + 순환은 멈추는가
REG_chain <- list(
  C_END = mk("canonical", cluster = "T-9", aliases = "C_MID"),
  C_MID = mk("alias", canonical = "C_END", cluster = "T-9"),
  C_TOP = mk("alias", canonical = "C_MID", cluster = "T-9"))
rc <- .fds_resolve_chain(c("C_TOP", "C_MID", "C_END"), REG_chain)
if (identical(unname(rc), c("C_END", "C_END", "C_END"))) {
  ok("alias_chain_resolves_to_fixpoint", "C_TOP->C_MID->C_END 3단 해석")
} else bad("alias_chain_resolves_to_fixpoint", paste(rc, collapse = ","))

REG_cyc <- list(X = mk("alias", canonical = "Y", cluster = "T-8"),
                Y = mk("alias", canonical = "X", cluster = "T-8"))
cyc_warned <- FALSE
invisible(withCallingHandlers(
  .fds_resolve_chain(c("X", "Y"), REG_cyc, max_depth = 4L),
  warning = function(w) { cyc_warned <<- TRUE; invokeRestart("muffleWarning") }))
if (cyc_warned) {
  ok("alias_cycle_warns_not_hangs", "순환 registry 에서 경고 후 종료")
} else {
  bad("alias_cycle_warns_not_hangs", "순환인데 조용히 통과")
}

#==============================================================================
cat("=== 5) 기본 동작 무변경 — 인자 없이 부르면 값이 같은가 (실 connector) ===\n")
#==============================================================================
conn <- file.path(PROJ, "02_Infrastructure/factor_db/factor_db_connector.R")
db_ok <- dir.exists(file.path(PROJ, ".cache/factor_db")) &&
  length(list.files(file.path(PROJ, ".cache/factor_db"),
                    pattern = "^factor_db_\\d{6}\\.parquet$")) > 0L
if (!db_ok) {
  skip("default_behaviour_unchanged", "factor DB 미설치(worktree) — 배포 트리에서 재검사")
  skip("dedup_true_changes_pool", "factor DB 미설치")
  skip("real_registry_positive_control", "factor DB 미설치")
} else {
  suppressWarnings(source(conn))
  PD <- as.Date("2022-06-30")

  base    <- load_month_factors(PD)                       # 인자 없음 = 기존 경로
  explicit<- load_month_factors(PD, dedup = FALSE)
  if (identical(as.data.table(base), as.data.table(explicit)) && nrow(base) > 0L) {
    ok("default_behaviour_unchanged",
       sprintf("dedup 미지정 == dedup=FALSE, %s행 동일", format(nrow(base), big.mark = ",")))
  } else bad("default_behaviour_unchanged",
             sprintf("기본값 경로가 다르다 (%d vs %d행)", nrow(base), nrow(explicit)))

  ded <- load_month_factors(PD, dedup = TRUE)
  nb <- uniqueN(base$Factor_Name); nd <- uniqueN(ded$Factor_Name)
  drop_n <- length(attr(ded, "dedup_dropped"))
  if (drop_n == 0L) {
    skip("dedup_true_changes_pool",
         "이 vintage 에 접을 alias 가 0 — 대상 0을 PASS 로 세지 않는다(계측 생존 확인 필요)")
  } else if (nd == nb - drop_n && nrow(ded) < nrow(base)) {
    ok("dedup_true_changes_pool",
       sprintf("팩터 %d -> %d (alias %d종 제거), 행 %s -> %s",
               nb, nd, drop_n, format(nrow(base), big.mark = ","),
               format(nrow(ded), big.mark = ",")))
  } else {
    bad("dedup_true_changes_pool",
        sprintf("풀 %d -> %d 인데 dropped=%d — 계산 불일치", nb, nd, drop_n))
  }

  # attribute 보존: dedup 을 켜도 factor_db 계보 attribute 가 살아 있어야 한다
  if (!is.null(attr(ded, "factor_db_build_hash")) &&
      !is.null(attr(ded, "factor_db_asof_date"))) {
    ok("dedup_preserves_provenance_attrs",
       sprintf("build_hash + asof(%s) 보존", attr(ded, "factor_db_asof_date")))
  } else bad("dedup_preserves_provenance_attrs", "계보 attribute 유실")

  #============================================================================
  cat("=== 6) 실 registry 양성 대조 — 중복 아닌 팩터가 살아남는가 ===\n")
  #============================================================================
  CONTROLS <- c("M26_Revenue_Mom", "V01_BM", "M01_Mom_12_1")
  inpool <- intersect(CONTROLS, unique(base$Factor_Name))
  if (!length(inpool)) {
    skip("real_registry_positive_control", "대조 팩터가 이 vintage 풀에 없음")
  } else {
    survived <- intersect(inpool, unique(ded$Factor_Name))
    if (setequal(survived, inpool)) {
      ok("real_registry_positive_control",
         sprintf("%s 전건 생존 (오검거 0)", paste(inpool, collapse = ", ")))
    } else {
      bad("real_registry_positive_control",
          sprintf("정상 팩터가 제거됨: %s", paste(setdiff(inpool, survived), collapse = ", ")))
    }
  }

  # 신규 선언 5쌍이 실제로 접히는가 (이 라운드의 회귀 가드)
  NEW_ALIAS <- c("C09_Earnings_Surprise_Sq", "C10_SUE_Persistence",
                 "C13_Revision_Breadth_3m", "M25_Earnings_Mom_Streak")
  tgt <- intersect(NEW_ALIAS, unique(base$Factor_Name))
  if (!length(tgt)) {
    skip("new_5pairs_collapsed", "신규 alias 가 이 vintage 풀에 없음")
  } else {
    still <- intersect(tgt, unique(ded$Factor_Name))
    if (!length(still)) {
      ok("new_5pairs_collapsed", sprintf("%s 전건 접힘", paste(tgt, collapse = ", ")))
    } else {
      bad("new_5pairs_collapsed", sprintf("여전히 남음: %s", paste(still, collapse = ", ")))
    }
  }

  # ICIR 랭킹 표에도 배선이 걸렸는가
  icb <- compute_rolling_ic_all(PD)
  icd <- compute_rolling_ic_all(PD, dedup = TRUE)
  if (nrow(icb) > 0L && nrow(icd) > 0L && nrow(icd) <= nrow(icb)) {
    if (nrow(icd) < nrow(icb)) {
      ok("icir_table_dedup_wired", sprintf("ICIR 표 %d -> %d행", nrow(icb), nrow(icd)))
    } else {
      skip("icir_table_dedup_wired", "IC 표에 접을 alias 0 — 대상 0")
    }
  } else bad("icir_table_dedup_wired", sprintf("icb=%d icd=%d", nrow(icb), nrow(icd)))

  #============================================================================
  cat("=== 7) fail-closed — API 부재 시 조용히 통과하지 않는가 ===\n")
  #============================================================================
  saved <- collapse_alias_rows
  rm(collapse_alias_rows, envir = globalenv())
  bad_dir <- tempfile("nodup_"); dir.create(bad_dir)
  saved_dir <- .fdc_self_dir
  assign(".fdc_self_dir", bad_dir, envir = globalenv())
  errd <- tryCatch({ load_month_factors(PD, dedup = TRUE); FALSE },
                   error = function(e) grepl("fail-closed", conditionMessage(e)))
  assign(".fdc_self_dir", saved_dir, envir = globalenv())
  assign("collapse_alias_rows", saved, envir = globalenv())
  if (isTRUE(errd)) ok("fail_closed_when_api_missing", "API 부재 → stop() (미적용 데이터 반환 안 함)")
  else bad("fail_closed_when_api_missing", "API 가 없는데 조용히 통과 — 결손이 정상값으로 내려앉음")
}

#==============================================================================
cat(sprintf("\n=== test_factor_dedup_consumption: %d PASS / %d FAIL / %d SKIP  (root=%s) ===\n",
            PASS, FAIL, SKIP, PROJ))
## 배터리 집계용 요약 JSON — run_all_hooks.sh 는 마지막 유효 요약 JSON 라인을 파싱한다.
## skip 은 pass 에 섞지 않는다(검사하지 않은 것을 통과로 삼지 않기 위해).
cat(sprintf('{"test":"factor_dedup_consumption","pass":%d,"fail":%d,"total":%d,"skip":%d}\n',
            PASS, FAIL, PASS + FAIL, SKIP))
if (FAIL > 0L) quit(status = 1L)
