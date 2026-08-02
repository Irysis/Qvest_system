#==============================================================================
# test_sample_alignment_empty.R — 전략/벤치 날짜축 정합 판정의 "빈 결과 ≠ 합격" 계약
#
# 대상: 02_Infrastructure/strategy_analyzer.R :: sample_alignment_check()
#       (run_analysis §7-G 본체. 사본이 아니라 **원본 파일을 source** 해 실측한다)
#
# 배경 (2026-08-02 실측 재현):
#   구판 §7-G 는 한 줄이었다 —
#     report$Sample_Aligned <- length(strat_only) == 0 && length(bm_only) == 0
#   두 시계열이 **둘 다 비면** 양쪽 setdiff 가 비어 TRUE("완벽 정렬")가 된다.
#   같은 리포트의 Sample_Overlap 은 0 으로 찍히지만 하류가 읽는 것은 불리언이다.
#   감싸는 tryCatch 도 못 잡는다 — 빈 xts 는 오류가 아니라 warning 만 낸다
#   (min() → "no non-missing arguments to min; returning Inf").
#
#   계통: "빈 결과 = 합격" (2026-08-02 lookahead_detector.R / pit_engine_v3.R 11지점).
#   판별 기준 = 빈 값이 *권위 있는 출처가 "없다"고 말해준 것*인가,
#              *아무도 묻지 않은 것*인가.
#   정본 대조군 = 02_Infrastructure/worktask/state_machine.R:96-107
#              (required_artifacts 0건 → PASS / unknown phase → FAIL).
#
# ★검사 구성: 3축을 **양방향**으로 건다.
#   A축(위반 주입) — 빈 입력에서 TRUE 가 나오지 않는가.
#   B축(양성 통제) — 정상 입력에서 기존 판정(정렬/불일치)이 그대로 유지되는가.
#                   A축만 있으면 "항상 NA 반환"으로도 통과한다(검사 공허화).
#   C축(구판 재주입) — 구 한 줄을 같은 픽스처에 넣어 결함이 실제로 재현되는지 대조.
#                   재현되지 않으면 픽스처가 결함을 건드리지 못한다는 뜻이므로 FAIL.
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite); library(xts) })

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ★앵커 1순위 = **이 스크립트 자신의 경로** (bash 의 BASH_SOURCE 등가).
#   QM_ROOT 를 먼저 보면 worktree 에서 돌려도 조용히 **main 트리**의 코드를 검사한다
#   — 수리가 worktree 에 있고 main 엔 없을 때 이 검사기는 "미정의"를 보고하지만,
#   반대(main 만 수리)면 초록을 내면서 실제로는 다른 파일을 잰다.
#   [[reference-cpd-set-in-hooks-unset-in-bash-tool]] / r-portability 금칙 ④.
#   Rscript 최상위에서는 sys.frame()$ofile 이 NULL 이므로 commandArgs 의 --file= 를 쓴다.
.script_dir <- function() {
  a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(a) == 0L) return("")
  normalizePath(dirname(sub("^--file=", "", a[1])), winslash = "/", mustWork = FALSE)
}
.resolve_proj <- function() {
  sd <- .script_dir()
  cands <- c(if (nzchar(sd)) normalizePath(file.path(sd, "..", ".."), winslash = "/", mustWork = FALSE),
             Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             getwd())
  cands <- cands[nzchar(cands)]
  # 존재 검사가 아니라 **표지 검사** — "디렉토리가 있다"는 "그 트리다"를 뜻하지 않는다.
  marker <- "02_Infrastructure/strategy_analyzer.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — 표지 '", marker, "' 를 가진 후보 없음")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

# 원본 source (Rcpp 컴파일 포함 ~10s). 사본 검사 금지 — 사본은 드리프트해도 초록이다.
invisible(suppressMessages(capture.output(
  source(file.path(PROJ, "02_Infrastructure/strategy_analyzer.R")))))

if (!exists("sample_alignment_check") || !is.function(sample_alignment_check)) {
  cat("  FATAL: sample_alignment_check() 미정의 — §7-G 판정 본체가 사라졌거나 이름이 바뀜\n")
  cat(toJSON(list(test = "sample_alignment_empty", pass = 0L, fail = 1L, total = 1L),
             auto_unbox = TRUE), "\n", sep = "")
  quit(status = 2)
}

cat("=== sample alignment: empty-input contract ===\n")

# ─── 픽스처 ──────────────────────────────────────────────────────────────────
mk    <- function(d) xts(rep(0.01, length(d)), order.by = as.Date(d))
EMPTY <- xts(numeric(0), order.by = as.Date(character(0)))
D2    <- c("2020-01-02", "2020-01-03")
D3    <- c("2020-01-02", "2020-01-03", "2020-01-06")

# 구판 한 줄 (C축 대조군 — 이 파일 밖으로 새지 않게 로컬 정의)
legacy_aligned <- function(s, b) {
  so <- setdiff(as.character(index(s)), as.character(index(b)))
  bo <- setdiff(as.character(index(b)), as.character(index(s)))
  length(so) == 0 && length(bo) == 0
}

# ─── A축: 위반 주입 — 빈 입력 ────────────────────────────────────────────────
a1 <- sample_alignment_check(EMPTY, EMPTY)
if (isTRUE(a1$aligned)) {
  bad("empty_both_not_true",
      "빈 xts 2개인데 aligned=TRUE — '비교한 적 없음'이 '완벽 정렬'로 위장(구 결함 재발)")
} else if (is.na(a1$aligned)) {
  ok("empty_both_not_true", "aligned = NA (미판정)")
} else {
  bad("empty_both_not_true", sprintf("예상 밖 값: %s", a1$aligned))
}
if (identical(a1$status, "NOT_COMPARABLE")) {
  ok("empty_both_status", "status = NOT_COMPARABLE")
} else {
  bad("empty_both_status", sprintf("status = %s (사유 라벨 없음 → 하류가 MISALIGNED 와 구분 불가)", a1$status))
}
if (identical(a1$overlap, 0L) || identical(as.integer(a1$overlap), 0L)) {
  ok("empty_both_overlap_zero", "overlap = 0 (자기모순 없음)")
} else {
  bad("empty_both_overlap_zero", sprintf("overlap = %s", a1$overlap))
}
# 결손이 날짜인 척 실리지 않는가 — min()/max() 는 빈 벡터에서 Inf/-Inf 를 낸다.
if (is.na(a1$strat_start) && is.na(a1$bm_end)) {
  ok("empty_edges_na", "start/end = NA (Inf 가 날짜로 위장하지 않음)")
} else {
  bad("empty_edges_na", sprintf("strat_start=%s bm_end=%s", a1$strat_start, a1$bm_end))
}

# 한쪽만 빈 경우도 판정 대상이 아니다(불일치가 아니라 부재).
a2 <- sample_alignment_check(EMPTY, mk(D2))
a3 <- sample_alignment_check(mk(D2), EMPTY)
if (!isTRUE(a2$aligned) && !isTRUE(a3$aligned) &&
    identical(a2$status, "NOT_COMPARABLE") && identical(a3$status, "NOT_COMPARABLE")) {
  ok("empty_one_side_not_comparable", "strat-empty / bm-empty 모두 NOT_COMPARABLE")
} else {
  bad("empty_one_side_not_comparable",
      sprintf("strat-empty=%s/%s, bm-empty=%s/%s", a2$aligned, a2$status, a3$aligned, a3$status))
}

# ─── B축: 양성 통제 — 정상 입력에서 기존 동작이 유지되는가 ───────────────────
# (A축만 있으면 "무조건 NA 반환"으로도 통과한다 — 그건 판정 기능의 사망이다.)
b1 <- sample_alignment_check(mk(D2), mk(D2))
if (isTRUE(b1$aligned) && identical(b1$status, "ALIGNED") && b1$overlap == 2L) {
  ok("normal_match_still_true", "동일 날짜축 → TRUE / ALIGNED / overlap=2")
} else {
  bad("normal_match_still_true",
      sprintf("aligned=%s status=%s overlap=%s — 정상 정렬이 판정되지 않음", b1$aligned, b1$status, b1$overlap))
}

b2 <- sample_alignment_check(mk(D3), mk(D2))
if (isFALSE(b2$aligned) && identical(b2$status, "MISALIGNED") && b2$strat_only == 1L) {
  ok("normal_mismatch_still_false", "부분 겹침 → FALSE / MISALIGNED / strat_only=1")
} else {
  bad("normal_mismatch_still_false",
      sprintf("aligned=%s status=%s strat_only=%s", b2$aligned, b2$status, b2$strat_only))
}

# ★가장 심한 불일치(둘 다 비지 않았는데 겹침 0)는 NA 가 아니라 FALSE 여야 한다.
#   여기서 NA 를 내면 확정 FAIL 이 '미상'으로 격하돼 하류가 건너뛴다 —
#   고치려던 결함의 거울상(과잉교정).
b3 <- sample_alignment_check(mk(c("2020-01-02", "2020-01-03")), mk(c("2021-05-04", "2021-05-06")))
if (isFALSE(b3$aligned) && identical(b3$status, "MISALIGNED")) {
  ok("disjoint_is_false_not_na", "비-중첩 실데이터 → FALSE / MISALIGNED (미상으로 격하 안 됨)")
} else {
  bad("disjoint_is_false_not_na",
      sprintf("aligned=%s status=%s — 확정 불일치가 '비교 불가'로 격하됨", b3$aligned, b3$status))
}

# 날짜 경계가 정상 입력에서는 실제 값으로 실리는가 (NA 일괄 반환 방어)
if (identical(b1$strat_start, "2020-01-02") && identical(b1$strat_end, "2020-01-03")) {
  ok("normal_edges_real", "start/end 실측값")
} else {
  bad("normal_edges_real", sprintf("start=%s end=%s", b1$strat_start, b1$strat_end))
}

# ─── C축: 구판 재주입 — 픽스처가 결함을 실제로 건드리는가 ────────────────────
# 이 대조가 없으면 "빈 입력에서 TRUE 가 안 나온다"가 애초에 나올 수 없었던 것인지,
# 수리 덕분인지 구별할 수 없다(케이스 공허화).
if (isTRUE(legacy_aligned(EMPTY, EMPTY))) {
  ok("legacy_reproduces_defect", "구 한 줄은 같은 픽스처에서 TRUE — 결함 재현 확인")
} else {
  bad("legacy_reproduces_defect",
      "구 한 줄이 빈 입력에서 TRUE 를 내지 않음 — 픽스처가 결함 지점을 건드리지 못함(검사 공허)")
}
if (isTRUE(legacy_aligned(mk(D2), mk(D2))) && isFALSE(legacy_aligned(mk(D3), mk(D2)))) {
  ok("legacy_normal_agrees", "정상 입력에선 구·신 판정 일치 — 수리가 정상경로를 바꾸지 않음")
} else {
  bad("legacy_normal_agrees", "구판 정상경로 기대값 불일치 — 대조군 자체가 어긋남")
}

# ─── D축: 소비부 계약 — NA 를 isTRUE() 로 받는가 ─────────────────────────────
# NA 를 `if (x)` 로 받으면 "argument is not interpretable as logical" 로 죽거나
# (R 4.2+) 조건 오류가 난다. 리포트 생성부가 NA 에서 살아남아야 한다.
# 스캔 범위 = 02_Infrastructure 전체 .R (파일 1개만 보면 나중에 **다른 파일**에 추가된
# 소비부가 그대로 빠져나간다). 범위는 여기 명시한다 — 조용한 상한은 "전부 봤다"로 읽힌다.
SCAN_ROOT <- "02_Infrastructure"
scan_files <- list.files(file.path(PROJ, SCAN_ROOT), pattern = "[.]R$",
                         recursive = TRUE, full.names = TRUE)
reader_hits <- character(); reader_where <- character()
for (f in scan_files) {
  ln <- tryCatch(readLines(f, warn = FALSE), error = function(e) character())
  h <- grep("Sample_Aligned", ln, value = TRUE)
  # 대입부(생산)와 주석은 소비부가 아니다
  h <- h[!grepl("Sample_Aligned\\s*<-", h) & !grepl("^\\s*#", h)]
  if (length(h)) {
    reader_hits <- c(reader_hits, h)
    reader_where <- c(reader_where, rep(sub(paste0("^", PROJ, "/?"), "", f), length(h)))
  }
}
cat(sprintf("  [scan] %s 하위 .R %d개 스캔 — Sample_Aligned 소비부 %d건\n",
            SCAN_ROOT, length(scan_files), length(reader_hits)))
bare <- !grepl("isTRUE\\(", reader_hits)
if (length(reader_hits) == 0L) {
  bad("consumer_uses_istrue",
      sprintf("소비부 0건 — 필드가 어디서도 안 읽히면 판정이 사문화(또는 스캔 범위 %s 가 틀림)", SCAN_ROOT))
} else if (!any(bare)) {
  ok("consumer_uses_istrue",
     sprintf("소비부 %d건 전부 isTRUE() 경유 (%s)", length(reader_hits),
             paste(unique(reader_where), collapse = ", ")))
} else {
  bad("consumer_uses_istrue",
      sprintf("isTRUE() 없이 읽는 지점 %d건: %s", sum(bare),
              paste(sprintf("%s: %s", reader_where[bare], trimws(reader_hits[bare])), collapse = " | ")))
}

# NA 를 실제로 흘려 리포트 문자열 생성이 죽지 않는지 실행 확인
na_render <- tryCatch({
  rep_stub <- list(Sample_Aligned = NA, Sample_Align_Status = "NOT_COMPARABLE",
                   Sample_Overlap = 0L, Sample_StratOnly = 0L, Sample_BMOnly = 0L)
  sprintf("- **Sample Aligned:** %s [%s] (overlap: %d, strat-only: %d, bm-only: %d)",
          if (isTRUE(rep_stub$Sample_Aligned)) "YES" else "NO",
          rep_stub$Sample_Align_Status %||% "NOT_RUN",
          rep_stub$Sample_Overlap %||% 0, rep_stub$Sample_StratOnly %||% 0, rep_stub$Sample_BMOnly %||% 0)
}, error = function(e) paste("ERROR:", conditionMessage(e)))
if (grepl("NOT_COMPARABLE", na_render) && !grepl("^ERROR", na_render)) {
  ok("na_renders_with_reason", trimws(na_render))
} else {
  bad("na_renders_with_reason", na_render)
}

# ─── 요약 ────────────────────────────────────────────────────────────────────
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "sample_alignment_empty", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
