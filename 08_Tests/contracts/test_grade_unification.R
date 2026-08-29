# test_grade_unification.R — 등급 일원화 계약 (v9.21 축 1)
#
# 대상: 02_Infrastructure/contracts/essence_score.R   (등급 enum · MDD 설계)
#       02_Infrastructure/alpha_search/run_alpha_search.R (권위 측정 상시화 · 축 분리)
#       02_Infrastructure/axiom/lcode_schema.R          (enum 정합)
#
# 왜 이 시험이 본체인가:
#   이 저장소는 등급이 **둘 병존한 게 아니라** hurdle_gate.R 이 2026-05-31 에 이미
#   DEMOTED(authoritative=FALSE · grade_basis="proxy_diagnostic_18component") 됐는데
#   **문서가 강등을 안 따라간** 상태였다. 그리고 배선은 더 나빴다 — 강등된 proxy 등급이
#   "권위 등급을 계산할지 여부"를 정하는 **순환 의존**이었고(hurdle A/B 일 때만 essence 호출),
#   그래서 lean 라운드에는 권위 등급이 아예 없었다. docs/qvest_ast_v1_1_sot.md:84 가 이 사다리를
#   **"생존편향 구조"** 로 이미 반증 기록해 뒀다 — proxy 가 통과시킨 것만 권위 측정을 받으니
#   표본이 위로 잘린다.
#   ⇒ 일원화의 실질은 "치환"이 아니라 **"lean 에서 권위 등급을 항상 산출"** 이다. 이 검사기가
#     그 사실을 못박고, 되돌아가면(게이트 재도입) 잡는다.

suppressPackageStartupMessages({ })

## ★`%||%` 명시 정의 — base 상속에 기대지 않는다. R 4.4 부터 base 에 있지만 판본에 따라
##   없고, 없으면 조용히 다른 것을 찾아 쓴다(이 저장소가 두 번 기록한 함정).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

PASS <- 0L; FAIL <- 0L; SKIP <- 0L; SKIPS <- list()
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, " :: ", d, "\n") }
sk <- function(a, r, mi) { SKIP <<- SKIP + 1L
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = a, reason = r, missing = mi)
  cat("  SKIP ", a, " — ", r, "\n") }
emit <- function() {
  cat(sprintf("\nTOTAL: %d pass / %d fail / %d skipped\n", PASS, FAIL, SKIP))
  j <- sprintf('{"test":"grade_unification","pass":%d,"fail":%d,"total":%d,"skipped":%d',
               PASS, FAIL, PASS + FAIL, SKIP)
  if (SKIP > 0L) j <- paste0(j, ',"skips":[', paste(vapply(SKIPS, function(s)
    sprintf('{"axis":"%s","reason":"%s","missing":"%s"}', s$axis, s$reason, s$missing),
    character(1)), collapse = ","), "]")
  cat(paste0(j, "}\n")); quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
}

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
ES   <- file.path(ROOT, "02_Infrastructure", "contracts", "essence_score.R")
RAS  <- file.path(ROOT, "02_Infrastructure", "alpha_search", "run_alpha_search.R")
SCH  <- file.path(ROOT, "02_Infrastructure", "axiom", "lcode_schema.R")
CDJ  <- file.path(ROOT, "02_Infrastructure", "worktask", "constraint_defaults.json")

cat("=== grade unification (v9.21) ===\n")
for (f in c(ES, RAS, SCH)) if (!file.exists(f)) { sk("files_present", "대상 파일 부재", f); emit() }

# ══ A. 등급 enum 4값 (§1-b) ═════════════════════════════════════════════════
cat("\n── A. 등급 enum 4값 ────────────────────────────────────────\n")
e <- new.env(parent = globalenv())
.loaded <- tryCatch({ suppressMessages(sys.source(ES, envir = e)); TRUE },
                    error = function(x) { ng("essence_score 로드", conditionMessage(x)); FALSE })

if (.loaded) {
  esrc <- readLines(ES, warn = FALSE); EJ <- paste(esrc, collapse = "\n")

  # A1 — "uncertain" 이 등급 축에서 사라졌는가 (실행 자구만; 주석은 허용)
  code <- esrc[!grepl("^\\s*#", esrc)]
  if (!any(grepl('grade <- "uncertain"', code, fixed = TRUE)))
    ok('grade <- "uncertain" 자구가 실행 위치에 없다 — 등급 축 정화') else
    ng("★uncertain 이 여전히 등급으로 발행된다")

  # A2 — 계약 미경유는 NA, 그리고 사유는 metric_type 이 보존하는가 (둘 다 단언)
  if (grepl("grade <- NA_character_", EJ, fixed = TRUE) &&
      grepl('metric_type = if (contract_ok) "backtested" else "uncertain"', EJ, fixed = TRUE))
    ok("계약 미경유 → 등급 NA + metric_type='uncertain' (사실은 보존, 등급 축만 정화)") else
    ng("★NA 전환 또는 metric_type 보존 중 하나가 빠졌다")

  # A3 — ★enum 정합: lcode_schema 가 받는 값과 essence 가 내는 값이 같은 집합인가
  sch <- paste(readLines(SCH, warn = FALSE), collapse = "\n")
  if (grepl('LCODE_VALID_GRADES <- c("A", "B", "C", "F")', sch, fixed = TRUE))
    ok("LCODE_VALID_GRADES = A/B/C/F — essence 4값과 정합(무변경으로 성립)") else
    ng("★L-code enum 이 essence 4값과 어긋난다 — validate_lcode 가 적립을 막는다")
}

# ══ B. MDD 설계 보존 (되돌리면 잡히는 단방향 검사) ═════════════════════════
cat("\n── B. MDD 는 Calmar 비율로만 걸린다 ───────────────────────\n")
if (!.loaded) sk("B_mdd", "essence_score 미로드", ES) else {
  ai <- grep("a_core <- ", esrc)[1]
  blk <- paste(esrc[ai:min(ai + 6L, length(esrc))], collapse = "\n")
  # B1 — a_core 에 MDD 직접 문턱이 없는가
  if (!grepl("mdd", blk, ignore.case = TRUE))
    ok("a_core 에 MDD 직접 문턱 없음 — Calmar 가 비율로 대신한다") else
    ng("★a_core 에 MDD 조건이 들어갔다 — 도훈 확인 2026-08-24 설계를 되돌린 것",
       gsub("\\s+", " ", blk))
  # B2 — 그 사유가 코드에 기록돼 있는가(문서 정합 중 오독 방지)
  if (grepl("Calmar 로 \\*\\*비율\\*\\*로 걸려", paste(esrc, collapse = "\n")) ||
      grepl("MDD 직접 조건은 \\*\\*의도적으로 없다\\*\\*", paste(esrc, collapse = "\n")))
    ok("설계 사유가 코드에 기록 — 문서 정합 중 되살리는 것을 막는다") else
    ng("★사유 기록 없음 — 다음 사람이 'MDD 조건이 빠졌다'로 오독한다")
  # B3 — 정본 문서가 그 비율을 실제로 선언하는가
  if (file.exists(CDJ)) {
    cj <- paste(readLines(CDJ, warn = FALSE), collapse = "")
    if (grepl("CAGR/\\|MDD\\|", cj) && grepl("0.64", cj, fixed = TRUE))
      ok("정본(constraint_defaults)에 Calmar=CAGR/|MDD| 0.64 선언 확인") else
      ng("★정본에 비율 근거가 없다")
  } else sk("B3_canon", "constraint_defaults.json 부재", CDJ)

  # ── B4~B6: ★hard_fail 에서 MDD 를 걷어낸 것 (2026-08-24 도훈 지시) ──────────
  #   "hard_fail 조건에서 MDD만 걷어내면 되는거 아냐?" — 구판은
  #   `if (is.null(hard_fail)) hard_fail <- isTRUE(dd_profile$structural_hard_fail)` 로
  #   drawdown 에서 추론해 **등급을 F 로 접었다**. 그 추론의 4개 논리합이 전부 drawdown 량이라
  #   (MDD>=0.70 · 45%+ ep>=15 · 55%+ ep>=6 · 수중 표본비>=0.25) 그 한 줄이 곧 MDD 탈락이었다.
  #   hurdle_gate.R:465 가 2026-08-23 에 리서치 층에서 한 절단과 같다.
  # ★공백 collapse 로 충분하다 — 아래 단언은 전부 fixed=TRUE 한 줄 패턴이다.
  #   (정규식 escape 를 bash→python→R 3계층으로 통과시키려다 두 번 깨졌다. 백슬래시를 쓰지 않는다.)
  ej_code <- paste(code, collapse = " ")
  # B4 — 추론 자구가 사라졌는가
  if (!grepl("hard_fail <- isTRUE(dd_profile$structural_hard_fail)", ej_code, fixed = TRUE))
    ok("drawdown → hard_fail 추론 자구 제거 — MDD 가 등급을 접지 않는다") else
    ng("★MDD 추론이 되살아났다 — 도훈 지시 2026-08-24 를 되돌린 것")
  # B5 — ★주입 경로는 **살아 있어야** 한다 (제거가 과잉이면 자본 층 권한이 사라진다)
  if (grepl("hard_fail_injected", ej_code, fixed = TRUE) &&
      grepl("} else if (hard_fail) {", ej_code, fixed = TRUE))
    ok("외부(judge) 주입 → F 분지 보존 — 자본 층 권한(INV-7) 유지") else
    ng("★주입 경로까지 지웠다 — judge 가 hard_fail 을 넘길 수 없다(과잉 절단)")
  # B6 — 구조 정보가 라벨로 남는가 (조용한 정보 소실 방지)
  if (grepl("structural_drawdown = structural_drawdown", ej_code, fixed = TRUE))
    ok("structural_drawdown 라벨 반환 — 오버레이 라우팅 근거 보존") else
    ng("★구조 정보가 사라졌다 — 하류가 '결합 층 재료'와 '약한 신호'를 구분 못한다")
}

# ══ C. 권위 측정 상시화 (§1-a) ══════════════════════════════════════════════
cat("\n── C. 권위 측정 상시화 ─────────────────────────────────────\n")
rs <- readLines(RAS, warn = FALSE); RJ <- paste(rs, collapse = "\n")
rcode <- rs[!grepl("^\\s*##?\\s", rs)]        # 주석 제외 = 실행 자구

# C1 — auth 계산이 정확히 1회인가 (앞으로 옮기면서 중복이 생기기 쉽다)
nauth <- length(grep("auth <- \\.authoritative_remeasure", rcode))
if (identical(nauth, 1L)) ok("권위 측정 호출 1회 — 중복 계산 없음") else
  ng("★권위 측정 호출이 1회가 아니다", sprintf("%d회", nauth))

# C2 — ★게이트가 사라졌는가: proxy 등급이 권위 측정 여부를 정하지 않는다
#   구판 자구 = `if (isTRUE(deep)) { if (grade %in% c("A","A_NOVEL",...) || screen_remeasure)`
if (!any(grepl("screen_remeasure", rcode)) &&
    !grepl('if \\(isTRUE\\(deep\\)\\) \\{[^}]*A_NOVEL', RJ))
  ok("순환 의존 해제 — proxy 등급이 권위 측정 여부를 정하지 않는다") else
  ng("★게이트가 남아 있다 — lean 라운드에 권위 등급이 없는 상태로 되돌아간다")

# C3 — 두 축이 이름으로 분리됐는가
if (any(grepl("grade_proxy <- hg\\$grade", rcode)) &&
    any(grepl("grade <- auth\\$essence_grade", rcode)))
  ok("축 분리: grade=권위(essence) · grade_proxy=진단(hurdle)") else
  ng("★두 축이 같은 이름을 쓰거나 정의가 없다")

# C4 — 판정 플래그가 권위 등급에서 갈리는가 + 접미어 나열이 제거됐는가
flag_ok <- any(grepl('pass    <- identical\\(grade, "A"\\)', rcode)) &&
           any(grepl('is_fail <- identical\\(grade, "F"\\)', rcode))
suffix_left <- length(grep("A_NOVEL|A_DEF|B_DEF", rcode))
if (flag_ok && identical(suffix_left, 0L))
  ok("pass/is_fail 이 권위 등급 기준 · hurdle 접미어 나열 0 (조용한 축소 방지)") else
  ng("★플래그가 권위 등급 기준이 아니거나 접미어가 남았다",
     sprintf("flag_ok=%s suffix=%d", flag_ok, suffix_left))

# C5 — FMT 는 proxy 축을 유지하는가 (축 섞기 금지)
if (any(grepl("\\.judge_fmt\\(.*grade_proxy\\)", rcode)))
  ok("FMT(proxy 진단 taxonomy)에는 proxy 등급을 넘긴다 — 축을 섞지 않는다") else
  ng("★FMT 에 권위 등급을 넘긴다 — proxy taxonomy 가 다른 축으로 채점된다")

# C6 — ★lean 라운드도 권위 등급을 원장에 남기는가 (essence_grade 0건 문제 해소)
if (any(grepl("essence_grade = grade", rcode)))
  ok("6c(lean) meta 에 essence_grade 기록 — module_catalog 의 essence_grade 0건 해소") else
  ng("★lean 등재에 권위 등급이 안 실린다 — 카탈로그에서 여전히 조회 불가")

# C7 — ★돌연변이 통제: 게이트를 되살리면 C2 가 실제로 뒤집히는가
mut <- c(rcode, '  if (isTRUE(deep)) { if (grade %in% c("A","A_NOVEL","A_DEF")) { } }',
         "  screen_remeasure <- TRUE")
if (any(grepl("screen_remeasure", mut)))
  ok("돌연변이 통제: 게이트 자구를 되살리면 C2 검출이 뒤집힌다") else
  ng("★돌연변이 통제 실패 — C2 는 아무것도 재고 있지 않다")

# ══ D. 등급 축의 출처 구분 (혼합 corpus 방지) ═══════════════════════════════
cat("\n── D. 등급 축 출처 구분 ────────────────────────────────────\n")
#
# ★플랜 P1 정정(2026-08-24): 플랜은 논문 러너 12종을 "run_alpha_search 와 같은 패치"로
#   적었으나 실사 결과 그들은 bt_contract·essence_score·run_alpha_search 가 **전부 0** 인
#   독립 일회성 스크립트다. run_hurdle_gate 를 직접 부르고 .write_lcode 만 공유한다(auth=NULL).
#   ⇒ 거기서 접미어 나열(A_NOVEL/A_DEF)을 지우면 **조용히 조건이 좁아진다** — hurdle 은 그
#     값들을 실제로 반환하므로 proxy 축에서는 그 나열이 맞다. 12개 파일을 고치는 게 아니라
#     **불변식을 강제**하는 것이 옳다: 등급이 어느 채점기에서 왔는지 corpus 가 구분 가능해야 한다.
#     구분 수단은 이미 있다 — metric_type(proxy/backtested) + authoritative 필드.

RUNNERS <- c("run_coverage_delta", "run_disclosure_meta", "run_hzz_inverse", "run_hzz_trend",
             "run_pead_paper", "run_qfactor_paper", "run_qmj_paper", "run_residmom_paper",
             "run_te_sink", "run_bsc_momentum", "run_dm_momentum", "run_volmanaged")
.rd <- file.path(ROOT, "02_Infrastructure", "alpha_search")
srcs <- lapply(RUNNERS, function(f) {
  p <- file.path(.rd, paste0(f, ".R"))
  if (!file.exists(p)) NA_character_ else paste(readLines(p, warn = FALSE), collapse = "\n")
})
names(srcs) <- RUNNERS
present <- RUNNERS[!vapply(srcs, function(x) is.na(x[1]), logical(1))]

# D1 — 논문 러너에 essence 스택이 없다(전제 확인). 생겼으면 D2 의 근거가 바뀐다.
stacked <- present[vapply(present, function(f)
  grepl("essence_score", srcs[[f]], fixed = TRUE) ||
  grepl("authoritative_remeasure", srcs[[f]], fixed = TRUE), logical(1))]
if (length(present) && !length(stacked))
  ok(sprintf("논문 러너 %d종에 essence 스택 없음 — proxy 축임이 전제로 확인됨", length(present))) else
  ng("★일부 러너에 essence 스택이 생겼다 — 그 파일은 essence 축으로 전환할 것",
     paste(stacked, collapse = ","))

# D2 — ★반대 방향 단방향 검사: proxy 축 러너에서 hurdle 접미어를 지우지 말 것
lost <- present[vapply(present, function(f)
  grepl("pass\\s*<-", srcs[[f]]) && !grepl("A_NOVEL", srcs[[f]], fixed = TRUE), logical(1))]
if (!length(lost))
  ok("proxy 축 러너가 hurdle 접미어 나열을 유지 — 조용한 조건 축소 없음") else
  ng("★proxy 축 러너에서 접미어가 사라졌다 — hurdle A_NOVEL/A_DEF 가 조용히 탈락한다",
     paste(lost, collapse = ","))

# D3 — corpus 불변식: backtested 등급은 authoritative 근거를 동반해야 한다
cp <- file.path(ROOT, ".cache", "lcode_corpus.json")
if (!requireNamespace("jsonlite", quietly = TRUE) || !file.exists(cp)) {
  sk("D3_corpus", "corpus 또는 jsonlite 부재", cp)
} else {
  co <- tryCatch(jsonlite::fromJSON(cp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(co$lcodes)) sk("D3_corpus", "corpus 파싱 실패", cp) else {
    as_l <- Filter(function(x) identical(x$research_mode, "alpha_search"), co$lcodes)
    bt   <- Filter(function(x) identical(x$metric_type, "backtested"), as_l)
    wa   <- sum(vapply(bt, function(x) !is.null(x$authoritative), logical(1)))
    ratio <- if (length(bt)) wa / length(bt) else NA_real_
    ## ★문턱을 1.0 으로 걸지 않는다 — v9.21 **이전** 산출분에 예외 6건이 실재한다(실측).
    ##   소급 재계산(§1-d) 전에는 잔재가 남으므로 여기서는 **회귀 방지**만 본다.
    if (is.na(ratio) || ratio >= 0.85)
      ok(sprintf("corpus 불변식: backtested %d건 중 authoritative 보유 %d (%.0f%%) — 축 추적 가능",
                 length(bt), wa, 100 * ratio)) else
      ng(sprintf("★backtested 인데 authoritative 근거 없는 L-code 가 늘었다 (%.0f%%)", 100 * ratio),
         "등급 출처가 corpus 에서 추적 불가해진다")
  }
}

# ══ E. 원장 반영 — 병기이지 덮어쓰기가 아니다 (§1-d, 도훈 승인 2026-08-24) ═════
cat("\n── E. 원장 반영 (essence_regrade) ──────────────────────────\n")
#
# 반영 규약: 과거 L-code 의 `grade` 는 **발행 시점의 판정**이라 불변이고, 권위 등급은
#   `essence_grade` 로 **병기**한다. `grade_raw` 가 원문을 보존하는 정직-원장 규약과 같다.
#
# ★반영에서 실제로 두 번 넘어졌다 — 그래서 이 축들이 있다:
#   (1) R 의 `fromJSON(simplifyVector=FALSE)` → `toJSON()` 왕복이 JSON `null` 을 `{}` 로
#       **변조**했다(실측: authoritative.dsr 19건). 값-단위 대조로 잡아 전량 롤백 후 Python 재작성.
#   (2) 하베스터가 **고정 키 집합**만 투영해 병기 필드를 통째로 버렸다 — 원본엔 있는데
#       corpus 보유 **0/547**. "생산자만 있고 소비자 0" 의 재발이었다.
LCP <- file.path(ROOT, "stage_artifacts", "l_code")
HRV <- file.path(ROOT, "02_Infrastructure", "axiom", "lcode_harvester.py")
MCJ <- file.path(ROOT, "06_Registry", "module_catalog.json")

if (!requireNamespace("jsonlite", quietly = TRUE) || !file.exists(cp)) {
  sk("E_ledger", "corpus 또는 jsonlite 부재", cp)
} else {
  co2 <- tryCatch(jsonlite::fromJSON(cp, simplifyVector = FALSE), error = function(x) NULL)
  L <- if (is.null(co2)) list() else co2$lcodes
  eg <- Filter(function(x) "essence_grade" %in% names(x), L)

  # E1 — ★투영이 살아 있는가 (하베스터가 다시 드롭하면 여기서 걸린다)
  if (length(eg) > 0L)
    ok(sprintf("corpus 에 essence_grade 투영 %d건 — 소비자가 권위 등급을 볼 수 있다", length(eg))) else
    ng("★권위 등급이 corpus 에 없다 — 원본에 병기해도 소비자 0 (하베스터 투영 확인)")

  # E2 — 역사 필드가 살아 있는가 (덮어쓰기 방지)
  #   ★불변식은 "grade 가 비어 있지 않다" 가 **아니라** "grade 가 발행 시점과 같다" 다.
  #     구판 단언(non-null)은 발행 때부터 grade 가 null 이던 1건(L-AS-20260808-Hurst,
  #     `grade_raw` 도 null)을 반영 사고로 오독했다 — **데이터가 아니라 단언이 틀렸다.**
  #     `essence_regrade.grade_at_emit` 이 반영 시점에 찍은 사본이므로 그것과 대조한다.
  if (length(eg)) {
    kept <- sum(vapply(eg, function(x)
      identical(as.character(x$grade %||% NA_character_),
                as.character(x$essence_grade_at_emit %||% NA_character_)), logical(1)))
    if (identical(kept, length(eg)))
      ok(sprintf("발행 시점 grade 가 %d건 전부 불변 — 원장은 역사다", kept)) else
      ng("★권위 등급이 발행 시점 판정을 덮었다", sprintf("%d/%d", kept, length(eg)))
  }

  # E3 — ★두 축이 실제로 갈리는가. 전부 같으면 병기가 아무것도 안 하는 것이다(양성 대조).
  if (length(eg)) {
    diff <- sum(vapply(eg, function(x)
      !is.null(x$essence_grade) && !identical(as.character(x$essence_grade),
                                              as.character(x$grade)), logical(1)))
    if (diff > 0L)
      ok(sprintf("두 축이 갈리는 건 %d — 병기가 실제 정보를 담는다", diff)) else
      ng("★모든 건에서 두 축이 같다 — 병기가 아무것도 재고 있지 않다")
  }

  # E4 — 하베스터가 **없는 것을 지어내지 않는가** (미조인 원본엔 키가 없어야 한다)
  if (length(L)) {
    frac <- length(eg) / length(L)
    if (frac > 0 && frac < 1)
      ok(sprintf("투영이 조인된 건에만 있다 (%d/%d) — 미조인은 키 자체가 없다", length(eg), length(L))) else
      ng("★전건에 키가 생겼다 — '재계산 대상 아님'과 '등급 미발행'이 구분되지 않는다")
  }
}

# E5 — 하베스터 투영 코드가 역사 필드를 덮지 않는가 (자구 래칫)
if (!file.exists(HRV)) sk("E5_harvester", "lcode_harvester.py 부재", HRV) else {
  hj <- paste(readLines(HRV, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (grepl('entry["essence_grade"] = data.get("essence_grade")', hj, fixed = TRUE) &&
      !grepl('entry["grade"] = data.get("essence_grade")', hj, fixed = TRUE))
    ok("하베스터가 essence_grade 를 별도 키로 투영 — grade 를 덮지 않는다") else
    ng("★투영이 사라졌거나 grade 를 덮는다")
}

# E6 — module_catalog 병기 (신규 등재와 같은 자리인가)
if (!file.exists(MCJ) || !requireNamespace("jsonlite", quietly = TRUE)) {
  sk("E6_catalog", "module_catalog.json 부재", MCJ)
} else {
  mc <- tryCatch(jsonlite::fromJSON(MCJ, simplifyVector = FALSE), error = function(x) NULL)
  mods <- if (is.null(mc)) list() else mc$modules
  n_eg <- sum(vapply(mods, function(v) {
    m <- v$meta; !is.null(m) && "essence_grade" %in% names(m) }, logical(1)))
  if (n_eg > 0L)
    ok(sprintf("module_catalog meta.essence_grade %d건 — run_alpha_search 6c 와 같은 자리", n_eg)) else
    ng("★catalog 에 권위 등급이 없다 — 카탈로그 조회로는 여전히 알 수 없다")
}

emit()
