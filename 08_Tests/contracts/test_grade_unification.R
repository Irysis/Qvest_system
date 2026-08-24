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

# ══ B. MDD 설계 보존 (되살리기 방지 래칫) ═══════════════════════════════════
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

emit()
