## harness_compliance.R — 성과 측정 **전에** 재료가 하네스를 거쳤는지 확인
##
## 왜 계약인가 (2026-08-09 실사고):
##  STR_1675 두 변형이 book-marginal 4축 적대 검증(무작위 파킹 97% · 귀무 창 **2.5%** · 연도 7/7 · 중복 아님)을
##  전부 통과했다. 오늘 아크에서 근거가 가장 강한 후보였다. **그 다음에** 재료를 열어보니:
##    - `run_all.R:49` `.cache/factor_db_daily` + `:131` `open_dataset(pq_files)` = **C15 우회**
##    - `load_month_factors()` 호출 **0건**
##    - 헤더 `:22` 가 그것을 **"C15 : 일간 DB Arrow open_dataset 직접" 이라며 'PIT 준수' 절에 기재**
##    - 계약 10-component·audit **0건** → `metric_type = unavailable`
##  ⇒ **AX-002 가 통계보다 상위**("하네스 내 성과만 유효. 프로세스 우회 = 미래참조 = C1 위반 동급").
##  4축 검증에 쏟은 라운드가 통째로 낭비됐다 — **순서가 틀렸다**.
##
## ⇒ 규약: 후보의 성과를 재기 **전에** 이 함수를 통과시킨다.
##   판정은 3축: ①10-component ②audit status ③factor DB 접근 방식(C15)
##
## SOT 메모리: [[project-contract-compliance-and-orthogonality-are-disjoint-20260809]]

suppressPackageStartupMessages({ library(data.table) })

.HC_TEN <- c("00_manifest","01_strategy_spec","02_nav","03_period_returns","04_holdings",
             "05_benchmark_returns","06_metrics","07_benchmark_compare","08_rolling_metrics",
             "09_drawdowns","10_audit")

#' 재료의 하네스 준수 3축 확인
#' @param artifact_path 산출물 파일 또는 디렉토리 (전략 루트/output/backtest_results 어디든)
#' @param code_path run_all.R 등 생산 코드 (NULL 이면 artifact_path 상위에서 탐색)
harness_compliance <- function(artifact_path, code_path = NULL) {
  p <- gsub("\\\\", "/", artifact_path)
  base <- if (dir.exists(p)) p else dirname(p)
  roots <- unique(c(base, dirname(base), dirname(dirname(base))))
  roots <- roots[dir.exists(roots)]

  ## ① 10-component
  best <- list(n = 0L, dir = NA_character_)
  for (r0 in roots) {
    for (cd in unique(c(r0, list.files(r0, pattern = "backtest_result", full.names = TRUE,
                                       include.dirs = TRUE)))) {
      if (!dir.exists(cd)) next
      ff <- list.files(cd)
      n <- sum(vapply(.HC_TEN, function(t) any(grepl(paste0("^", t), ff)), TRUE))
      if (n > best$n) best <- list(n = n, dir = cd)
    }
  }
  ## ② audit
  audit_status <- NA_character_; audit_rows <- NA_integer_
  if (best$n >= 8L && !is.na(best$dir)) {
    af <- list.files(best$dir, pattern = "^10_audit", full.names = TRUE)[1]
    if (!is.na(af)) {
      A <- tryCatch(data.table::fread(af), error = function(e) NULL)
      if (!is.null(A) && nrow(A)) {
        audit_rows <- nrow(A)
        sc <- names(A)[grepl("status|result|pass", names(A), ignore.case = TRUE)][1]
        if (!is.na(sc)) audit_status <- names(sort(table(A[[sc]]), decreasing = TRUE))[1]
      }
    }
  }
  ## ③ C15 — factor DB 접근 방식
  cp <- code_path
  if (is.null(cp)) {
    for (r0 in roots) {
      f <- list.files(r0, pattern = "^run_all\\.R$", recursive = TRUE, full.names = TRUE)
      if (length(f)) { cp <- f[1]; break }
    }
  }
  c15 <- NA_character_; c15_evidence <- NA_character_
  if (!is.null(cp) && file.exists(cp)) {
    L <- tryCatch(readLines(cp, warn = FALSE), error = function(e) character(0))
    lmf <- grep("load_month_factors", L)
    od  <- grep("open_dataset\\(", L)
    fdb <- grep("factor_db|factor_db_daily", L)
    direct <- length(od) > 0 && length(fdb) > 0
    c15 <- if (length(lmf) && !direct) "via_contract"
           else if (direct && !length(lmf)) "DIRECT_BYPASS"
           else if (length(lmf) && direct) "MIXED" else "unknown"
    if (direct) c15_evidence <- sprintf("open_dataset@%s + factor_db@%s",
      paste(head(od,2), collapse=","), paste(head(fdb,2), collapse=","))
  }

  ## ④ [additive 2026-08-09] ★대체 검증 기록 — 10-component 형식이 아니어도 하네스를 거쳤을 수 있다
  ##   초판 결함: 파일명만 보고 판정해 `performance_summary.json` 의 walkforward_integrity·lockbox·
  ##   subperiods 같은 **다른 형식의 검증 기록을 못 봤다**(STR_1698 실사고 — "하네스 밖" 으로 오분류).
  ##   ⇒ 존재 검사(파일명)로 정체 검사(검증 여부)를 대체하지 않는다.
  ##   ★성능 규율: 이 함수는 **측정 전에** 부르는 것이므로 빨라야 한다.
  ##   초판은 `recursive=TRUE` 로 대형 트리를 훑어 **10분 타임아웃**을 냈다 —
  ##   느린 사전 게이트는 아무도 안 부르므로 목적을 스스로 무너뜨린다.
  ##   ⇒ 비재귀 + 1단계 하위만 · 파일 수 상한 · 크기 상한.
  VKEYS <- c("walkforward_integrity","lockbox","prelb","subperiods","oos","purge",
             "audit_status","pit_check","harvey","dsr")
  vrec <- list(found = character(0), files = character(0))
  scan_dirs <- unique(c(roots,
    unlist(lapply(roots, function(r0)
      list.dirs(r0, recursive = FALSE, full.names = TRUE)))))
  scan_dirs <- head(scan_dirs[dir.exists(scan_dirs)], 12L)
  n_read <- 0L
  for (r0 in scan_dirs) {
    if (n_read >= 15L) break
    js <- list.files(r0, pattern = "\\.json$", recursive = FALSE, full.names = TRUE)
    js <- js[file.size(js) < 5e5]
    for (jf in head(js, 6L)) {
      if (n_read >= 15L) break
      n_read <- n_read + 1L
      x <- tryCatch(jsonlite::fromJSON(jf, simplifyVector = TRUE), error = function(e) NULL)
      if (is.null(x) || !length(names(x))) next
      k <- intersect(tolower(names(x)), VKEYS)
      if (length(k)) {
        vrec$found <- unique(c(vrec$found, k))
        vrec$files <- unique(c(vrec$files, basename(jf)))
      }
    }
  }
  has_alt <- length(vrec$found) >= 2L

  ok10 <- best$n >= 8L
  okc15 <- identical(c15, "via_contract")
  list(
    ten_component = best$n, ten_dir = best$dir,
    audit_status = audit_status, audit_rows = audit_rows,
    c15 = c15, c15_evidence = c15_evidence, code_path = cp,
    alt_validation = vrec$found, alt_validation_files = vrec$files, has_alt_validation = has_alt,
    compliant = ok10 && okc15,
    ## ★등급 — 두 축(10-component · C15)을 **독립으로** 반영한다.
    ##   초판 결함: 단일 사다리가 `okc15` 없이는 `ok10` 을 무시해 **PG2(10-c 11/11 · audit PASS)를
    ##   'unvalidated' 로 오분류**했다. production 산출물은 생산 코드가 다른 곳에 있어 C15 가
    ##   탐지 불가일 수 있는데, 그것이 '검증 안 됨' 을 뜻하지 않는다.
    ##   ⇒ 준수 재료를 미검증으로 찍는 게이트는 게이트로서 실패다.
    tier = if (ok10 && okc15) "contract_compliant"
           else if (ok10 && identical(c15, "DIRECT_BYPASS")) "contract_but_c15_bypass"
           else if (ok10) "contract_c15_undetected"
           else if (has_alt && okc15) "validated_needs_retrofit"
           else if (has_alt) "validated_c15_issue"
           else "unvalidated",
    metric_type = if (ok10) "backtested_candidate"
                  else if (has_alt) "backtested_retrofit_candidate" else "unavailable",
    note = paste0(
      "compliant = 10-component>=8 AND C15 via_contract. ",
      "★AX-002: 하네스 밖 성과는 통계가 아무리 좋아도 자본 승격 불가. ",
      "성과 측정 **전에** 이 확인을 하라 — 순서가 바뀌면 라운드가 통째로 낭비된다(2026-08-09 실사고)."))
}

#' 강제 게이트 — 하네스 밖이면 stop
assert_harness_compliant <- function(artifact_path, code_path = NULL, label = "material",
                                     allow_screen_tier = FALSE) {
  r <- harness_compliance(artifact_path, code_path)
  if (!isTRUE(r$compliant)) {
    msg <- sprintf(paste0("assert_harness_compliant[%s]: 재료가 계약 경로 밖이다 — ",
      "10-component %d/11%s · C15 %s%s. ",
      "★AX-002(하네스 내 성과만 유효)가 통계보다 상위다. ",
      "선결: build_bt_result 재산출 + audit, C15 는 load_month_factors 경유 또는 carve-out 명시 승인."),
      label, r$ten_component,
      if (is.na(r$audit_status)) " · audit 없음" else sprintf(" · audit %s(%d행)", r$audit_status, r$audit_rows),
      r$c15 %||% "unknown",
      if (is.na(r$c15_evidence)) "" else sprintf(" (%s)", r$c15_evidence))
    if (isTRUE(allow_screen_tier)) { warning(msg, call. = FALSE); return(invisible(r)) }
    stop(msg)
  }
  invisible(r)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
cat("[harness_compliance.R] Loaded — harness_compliance() / assert_harness_compliant()\n")
