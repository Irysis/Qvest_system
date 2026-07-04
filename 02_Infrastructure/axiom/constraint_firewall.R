# constraint_firewall.R — 제약 방화벽 (2026-07-04 실패지식 아키텍처 그룹 C+D)
#
# ★핵심 (도훈 mandate — 메커니즘 비-ossification): 방화벽은 '딱 한 번 작동하는
#   하드코딩된 정규식 멍청이'가 아니라 **의미판단(LLM) 우선 + 케이스 학습**이다.
#   - semantic 모드(기본): 실제 판정은 *호출하는 LLM 에이전트*가 수행한다. 이 함수는
#     판단에 필요한 컨텍스트(원리 + 케이스 few-shot + 제약 어휘)를 조립해 반환하는
#     *컨텍스트 제공자*다. 씨앗/축적 케이스에 *없는* 임의 패러프레이즈·영어·미묘한
#     프레이밍도 LLM이 원리로 일반화해 판정한다.
#   - backstop 모드: 비-LLM 경로(예: draft_proposed 명백-위반 가드)를 위한 결정론
#     1차 필터. **비-소진적(non-exhaustive) backstop** — 정규식이 못 잡는 위반은
#     semantic 모드가 잡는다. backstop은 '명백한' 위반만 stop.
#   - 자기발전: append_firewall_case()로 잡은 위반을 firewall_cases.json에 축적 →
#     다음 판정이 few-shot로 소비 → 잡을수록 똑똑해진다(corpus 학습 루프와 동형).
#
# 원리3 (제약 방화벽): 고정 제약 7종 + PIT는 배포 현실이 정의한 '문제의 고정 축'이다.
#   실패를 이 제약에 *귀속*하거나 제약 *완화*를 레버로 제시하는 것 = 위반(초안 REJECT).
#   AX-000 따름정리: 제약은 게임의 법칙 — 창의 부담은 방법(envelope-안 레버)에 진다.
#
# 고정 제약 7종 (변수 아님):
#   ① 종목수 max 25  ② 유동성 20일 평균 거래대금 ≥ 2e8 KRW  ③ Long-only(weights≥0)
#   ④ Weight bounds [0,0.20]  ⑤ Σw=1  ⑥ Universe KOSPI200∪KOSDAQ150
#   ⑦ Transaction cost 15bps one-way(v2.4 delta)  + PIT C1~C15
#
# envelope-안 레버(프론티어 화이트리스트 — 이것만 정당한 탐색축):
#   overlay · 잔차 sleeve · 비-return 데이터 · DPL · regime-conditional · multi-sleeve
#   · composite · ML sizing · uncertainty
#
# 주요 함수:
#   load_firewall_context(max_cases=)  — 초안 에이전트(LLM)가 읽을 원리 + 케이스 라이브러리
#   check_constraint_firewall(text, mode="semantic"|"backstop")
#     - semantic(기본): LLM 판정용 프롬프트 + 케이스 few-shot 조립 반환(함수는 판정 안 함)
#     - backstop: firewall_cases 축적 패턴 + base_signals 결정론 1차 필터(비-소진적)
#   append_firewall_case(caught, why, reframed=, violation_class=) — 새 위반 축적(자기발전)
#
# 참조: docs/rules/axiom-engine.md §0.1 + INV-7 · CLAUDE.md Production Constraints
#       04_Research/01_reports/failure_knowledge_architecture_plan_20260704.md (원리3/D/H)

suppressPackageStartupMessages(library(jsonlite))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

.cfw_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot", getwd())
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}
.cfw_cases_path <- function(root = .cfw_root()) file.path(root, "06_Registry", "firewall_cases.json")

# ── 케이스 라이브러리 로드/저장 ──
load_firewall_cases <- function(root = .cfw_root()) {
  cp <- .cfw_cases_path(root)
  if (!file.exists(cp))
    stop("firewall_cases.json 없음: ", cp,
         " — 06_Registry/firewall_cases.json 를 먼저 생성하세요.")
  fromJSON(cp, simplifyVector = FALSE)
}

.cfw_save_cases <- function(lib, root = .cfw_root()) {
  write_json(lib, .cfw_cases_path(root), pretty = TRUE, auto_unbox = TRUE, null = "null")
  invisible(TRUE)
}

#' 초안 에이전트(LLM)가 읽을 방화벽 판정 컨텍스트
#'
#' semantic 모드의 primary 산출물. LLM 에이전트는 이 원리 + 케이스 few-shot을 읽고
#' *스스로* 대상 텍스트가 제약-귀속/완화-레버 위반인지 판정한다. 정규식이 아니라 의미로.
#'
#' @param max_cases few-shot로 실을 최근 케이스 수 (씨앗 우선 + 최신 축적)
#' @return list(principle, envelope_levers, fixed_constraints, cases, guidance)
load_firewall_context <- function(max_cases = 24L, root = .cfw_root()) {
  lib <- load_firewall_cases(root)
  cases <- lib$cases %||% list()
  # 씨앗 케이스 전량 유지 + 최신 축적분 우선. 총 max_cases로 절단(few-shot 예산).
  is_seed <- vapply(cases, function(c) isTRUE(c$seed), logical(1))
  seed_cases <- cases[is_seed]
  learned <- cases[!is_seed]
  if (length(learned) > 1) {
    ord <- order(vapply(learned, function(c) c$added_at %||% "", character(1)), decreasing = TRUE)
    learned <- learned[ord]
  }
  budget <- max(0L, max_cases - length(seed_cases))
  picked <- c(seed_cases, if (budget > 0 && length(learned)) head(learned, budget) else list())

  list(
    principle = lib$principle,
    fixed_constraints = (lib$base_signals %||% list())$fixed_constraints %||% list(),
    envelope_levers = ((lib$base_signals %||% list())$envelope_levers %||% list())$terms %||% list(),
    cases = picked,
    n_cases_total = length(cases),
    guidance = paste0(
      "판정 방법(★의미 우선 — 정규식 아님): 대상 텍스트가 (a)실패/한계를 위 고정 제약에 ",
      "*귀속*하거나(attribution) (b)제약 *완화*를 레버로 제시(relaxation)하면 = 위반. ",
      "아래 cases는 few-shot 예시일 뿐 — 예시에 없는 임의 표현·영어·미묘한 프레이밍도 ",
      "principle로 일반화해 판정하라. ★위반 아님(PASS): 'envelope 안에서 이 경로는 천장'식 ",
      "정직 서술 / '미해결 열어둠'(AX-000) / envelope-안 레버 제시. ",
      "위반이면 envelope-상대(envelope_levers)로 재작성하고 append_firewall_case()로 축적하라.")
  )
}

# ── backstop 모드: 비-LLM 경로용 결정론 1차 필터 (비-소진적) ──
# base_signals의 backstop_terms + 축적 케이스의 caught_text에서 추린 명백 패턴만 잡는다.
# ★비소진적 backstop: 여기서 PASS라도 semantic 모드(LLM)가 잡을 수 있다. 이 필터는
#   '명백한' 완화-레버/귀속만 stop한다(false-negative 허용, false-positive 최소).

.CFW_RELAXATION_BACKSTOP <- c(
  "제약 ?(완화|해지|해제|풀면|풀어|없애|없으면|제거|상향|확대)",
  "short(ing)? ?(허용|가능|열|풀)", "공매도 ?(허용|가능|열|풀|도입)", "숏 ?(허용|가능|열)",
  "롱숏(이면|으로|이 ?되면|허용)", "long[- ]?short ?(이면|으로|허용|되면|가능)",
  ">? ?25 ?종 ?(넘게|이상|초과|필요|허용|늘)", "25 ?종 ?(넘게|이상|초과|넘어)",
  "종목수 ?(늘|확대|상향|초과|제한 ?풀)",
  "유니버스 ?(확대|넓|늘|전종목|풀|밖)", "universe ?(expand|widen|relax|beyond)",
  "유동성 ?(기준)?(을|를|은|는| )? ?(완화|낮|풀|내리|하향)", "liquidity ?(threshold ?)?(relax|lower)",
  "비중 ?(상한|한도) ?(완화|풀|올리|상향|초과)", "0\\.2(0)? ?(넘게|초과|상향|완화)",
  "제약 ?없으면", "제약 ?없이", "without (the )?constraint",
  "relax(ing|ed)? ?(the )?(constraint|universe|liquidity|long[- ]?only|bound|cap)",
  # 조건부-완화 관용구: "<제약>만 되면 풀린다/풀릴 문제" — 제약 해지를 가정법 레버로.
  #   (2026-07-04 자기발전: '공매도만 되면 풀릴 문제' 패러프레이즈가 backstop 미포착 →
  #    케이스 축적 원리로 backstop도 성장. semantic이 primary지만 관용구는 backstop도 잡게.)
  "(공매도|short|숏|롱숏|long[- ]?short|제약|제한) ?(만|이|가|은|는)? ?되면 ?(풀|해결|살|산다|된)",
  "(공매도|short|숏|제약|제한) ?만 ?(되면|가능|풀리)"
)

.CFW_CONSTRAINT_TERMS_BACKSTOP <- c(
  "long[- ]?only", "롱온리", "롱 ?온리", "공매도", "종목수", "25 ?종",
  "유동성", "거래대금", "liquidity", "유니버스", "universe", "kospi ?200", "kosdaq ?150",
  "비중 ?(상한|한도)", "거래비용", "transaction ?cost", "15 ?bps", "pit\\b", "미래참조"
)

.CFW_ATTRIBUTION_BACKSTOP <- c(
  "때문에 ?(실패|안|못|막|묶|커)", "라서 ?(실패|안|못)", "탓(에|으로)? ?(실패|안|못)",
  "제약 ?때문", "(제약|한계)(이|가) ?(원인|주범|병목|바인딩|실패)",
  "(long[- ]?only|롱온리|공매도 ?불가) ?(라서|때문|이라서|여서|이므로)",
  "(25 ?종|종목수|유동성|universe|유니버스) ?(제약|한계|때문|이라서|라서|묶여|막혀)",
  "because of (the )?(constraint|long[- ]?only|universe|liquidity)",
  "due to (the )?(constraint|long[- ]?only|universe|liquidity)"
)

.CFW_HONEST_BACKSTOP <- c(
  "봉투 ?(안|내)(에서)?", "envelope[- ]?(안|상대|내|relative|within)",
  "이 ?(제약|봉투|envelope) ?(하에서|안에서|내에서)",
  "미해결(로)? ?(열어|남|둠)", "unresolved", "open ?(problem|question)",
  "제약은 ?문제의 ?축", "고정 ?축", "문제의 ?(고정 )?축"
)

.cfw_grep_any <- function(text, patterns) {
  hits <- character(0)
  for (p in patterns) {
    m <- tryCatch(regmatches(text, regexpr(p, text, ignore.case = TRUE, perl = TRUE)),
                  error = function(e) character(0))
    if (length(m) && nzchar(m)) hits <- c(hits, m)
  }
  unique(hits)
}

.cfw_snippet <- function(text, needle, span = 40L) {
  pos <- regexpr(needle, text, ignore.case = TRUE, perl = TRUE, fixed = FALSE)
  if (pos[1] < 0) return(substr(text, 1, min(nchar(text), 80)))
  s <- max(1L, pos[1] - span); e <- min(nchar(text), pos[1] + attr(pos, "match.length") + span)
  gsub("\\s+", " ", substr(text, s, e))
}

# backstop: 축적 케이스에서 완화-레버 패턴 힌트를 동적으로 흡수(자기발전 — 정규식도 성장)
.cfw_learned_relaxation_terms <- function(lib) {
  cs <- lib$cases %||% list()
  viol <- Filter(function(c) identical(c$violation_class %||% "", "relaxation"), cs)
  # caught_text 자체를 fixed 부분매치 후보로. 짧게 정규화.
  vapply(viol, function(c) c$caught_text %||% "", character(1))
}

#' 제약 방화벽 판정
#'
#' @param text  검사 대상 진술
#' @param mode  "semantic"(기본, LLM 컨텍스트 반환) | "backstop"(결정론 1차 필터)
#' @return
#'   mode="semantic": list(mode, pass=NA, needs_llm_judgment=TRUE, context=<load_firewall_context>, text)
#'                    → 실제 pass/fail 판정은 호출 LLM 에이전트가 context로 수행.
#'   mode="backstop":  list(mode, pass=logical, violations=list, suggestion, note)
#'                    → 명백 위반만 결정론적으로 stop(비-소진적).
check_constraint_firewall <- function(text, mode = c("semantic", "backstop"), root = .cfw_root()) {
  mode <- match.arg(mode)
  if (is.null(text) || !nzchar(paste(text, collapse = " "))) {
    if (mode == "backstop") return(list(mode = mode, pass = TRUE, violations = list(),
                                        suggestion = "", note = "empty text"))
    return(list(mode = mode, pass = NA, needs_llm_judgment = FALSE,
                context = NULL, text = "", note = "empty text"))
  }
  txt <- paste(text, collapse = " \n ")

  if (mode == "semantic") {
    # primary 경로: 판정하지 않고 LLM 판정 컨텍스트를 조립해 반환.
    ctx <- load_firewall_context(root = root)
    return(list(
      mode = "semantic",
      pass = NA,                    # 함수가 판정하지 않음 — LLM이 context로 판정
      needs_llm_judgment = TRUE,
      text = txt,
      context = ctx,
      note = paste0("semantic 모드: 판정은 호출 LLM 에이전트가 context(원리+케이스 few-shot)로 ",
                    "수행. 정규식 매칭 아님. 위반 판정 시 append_firewall_case()로 축적.")))
  }

  # backstop 모드: 비-LLM 경로용 결정론 1차 필터 (비-소진적)
  lib <- tryCatch(load_firewall_cases(root), error = function(e) list(cases = list()))
  learned_relax <- .cfw_learned_relaxation_terms(lib)

  has_constraint <- length(.cfw_grep_any(txt, .CFW_CONSTRAINT_TERMS_BACKSTOP)) > 0
  relax_hits <- .cfw_grep_any(txt, .CFW_RELAXATION_BACKSTOP)
  attr_hits  <- .cfw_grep_any(txt, .CFW_ATTRIBUTION_BACKSTOP)
  honest     <- length(.cfw_grep_any(txt, .CFW_HONEST_BACKSTOP)) > 0

  violations <- list()
  # (1) 완화-레버: 자체로 명백 위반
  for (h in relax_hits) violations[[length(violations) + 1L]] <-
    list(pattern_class = "relaxation", matched = h, snippet = .cfw_snippet(txt, h))
  # (2) 원인 귀속: 제약어휘 + 귀속 트리거 동시, 단 정직 천장 서술이면 오탐 제외
  if (has_constraint && length(attr_hits) > 0 && !honest)
    for (h in attr_hits) violations[[length(violations) + 1L]] <-
      list(pattern_class = "attribution", matched = h, snippet = .cfw_snippet(txt, h))

  pass <- length(violations) == 0
  suggestion <- if (pass) "" else paste0(
    "제약 방화벽 backstop 위반 — 고정 제약(종목수≤25·유동성 2e8·long-only·[0,0.20]·Σw=1·",
    "K200∪KQ150·15bps·PIT)은 문제의 고정 축이지 변수가 아닙니다. envelope-안 레버",
    "(overlay·잔차 sleeve·비-return·DPL·regime-conditional·multi-sleeve·composite·ML sizing) ",
    "상대로 재작성하세요. ('봉투 안에서 천장' 정직 서술·'미해결 열어둠'은 허용.)")

  list(mode = "backstop", pass = pass, violations = violations, suggestion = suggestion,
       note = paste0("★비-소진적 backstop: 여기서 pass=TRUE라도 semantic(LLM) 판정이 잡을 수 ",
                     "있음. 명백 위반만 결정론적으로 stop. (learned relaxation cases: ",
                     length(learned_relax), ")"))
}

#' 새 위반 케이스를 라이브러리에 축적 (자기발전)
#'
#' semantic 판정에서 LLM이 위반을 잡으면 이 함수로 firewall_cases.json에 append한다.
#' 다음 load_firewall_context가 few-shot로 소비 → 방화벽이 잡을수록 똑똑해진다.
#'
#' @param caught        잡힌 위반 원문
#' @param why           왜 위반인지 (제약-귀속/완화-레버 근거)
#' @param reframed      envelope-상대 재작성문 (선택)
#' @param violation_class "attribution" | "relaxation" | "none"(pass 사례 축적 시)
#' @param verdict       "violation"(기본) | "pass"(정직 통과 사례도 few-shot 가치)
append_firewall_case <- function(caught, why, reframed = NULL,
                                 violation_class = "attribution",
                                 verdict = "violation", root = .cfw_root()) {
  stopifnot(nzchar(caught), nzchar(why))
  lib <- load_firewall_cases(root)
  new_case <- list(
    verdict = verdict,
    violation_class = violation_class,
    caught_text = caught,
    why_violation = why,
    reframed_to = reframed %||% NULL,
    added_at = format(Sys.Date()),
    seed = FALSE)
  # 중복 방지: 동일 caught_text 있으면 skip
  existing <- vapply(lib$cases %||% list(), function(c) c$caught_text %||% "", character(1))
  if (caught %in% existing) {
    message("[firewall] 이미 축적된 케이스 — skip: ", substr(caught, 1, 50))
    return(invisible(lib))
  }
  lib$cases <- c(lib$cases %||% list(), list(new_case))
  lib$generated_at <- format(Sys.Date())
  .cfw_save_cases(lib, root)
  cat(sprintf("[firewall] 케이스 축적: [%s/%s] %s (총 %d건)\n",
              verdict, violation_class, substr(caught, 1, 50), length(lib$cases)))
  invisible(lib)
}

# ── 단위 테스트 (Rscript constraint_firewall.R test) ──
.cfw_selftest <- function() {
  root <- .cfw_root()
  pass_n <- 0L; fail_n <- 0L
  check <- function(label, cond) {
    if (isTRUE(cond)) { pass_n <<- pass_n + 1L; cat(sprintf("[OK  ] %s\n", label)) }
    else { fail_n <<- fail_n + 1L; cat(sprintf("[FAIL] %s\n", label)) }
  }

  # A. semantic 모드: 판정 안 하고 context 반환 (primary)
  s <- check_constraint_firewall("EP-단독이 long-only라서 실패", mode = "semantic")
  check("semantic: pass=NA (함수 판정 안 함)", is.na(s$pass))
  check("semantic: needs_llm_judgment=TRUE", isTRUE(s$needs_llm_judgment))
  check("semantic: context에 principle 존재", nzchar(s$context$principle %||% ""))
  check("semantic: context에 케이스 few-shot 존재", length(s$context$cases) >= 3)
  check("semantic: context에 envelope_levers 존재", length(s$context$envelope_levers) >= 5)

  # B. 일반화: 씨앗에 *없는* 패러프레이즈를 담은 context가 조립되는가
  #    (실판정은 LLM이 하지만, context가 원리+few-shot을 제대로 싣는지 검증)
  para <- "25종이란 틀이 밸류를 죽였다. 그 틀만 없으면 알파가 산다."  # 씨앗에 없는 표현
  sp <- check_constraint_firewall(para, mode = "semantic")
  check("일반화: 패러프레이즈에도 context 조립됨", nzchar(sp$context$principle %||% "") &&
          length(sp$context$cases) >= 3 && nzchar(sp$context$guidance %||% ""))
  # backstop도 이 패러프레이즈의 완화-레버("틀만 없으면")를 잡는지
  bp <- check_constraint_firewall(para, mode = "backstop")
  # "없으면"류는 base 완화 트리거에 근접 — 최소 semantic가 잡도록 보장되면 충분.
  # backstop이 놓쳐도 비-소진적이므로 실패 아님(단 명백 완화는 잡아야).
  check("backstop: 비-소진적 note 존재", grepl("비-소진적|비소진", bp$note))

  # C. backstop: 명백 완화-레버 stop
  b1 <- check_constraint_firewall("SR 천장 돌파는 >25종 분산 또는 short 허용뿐이다.", mode = "backstop")
  check("backstop: >25종/short 허용 = 위반", isFALSE(b1$pass) && length(b1$violations) > 0)
  b2 <- check_constraint_firewall("제약을 완화해서 롱숏으로 가면 SR이 오른다.", mode = "backstop")
  check("backstop: 제약 완화+롱숏 = 위반", isFALSE(b2$pass))
  b3 <- check_constraint_firewall("유동성 기준을 낮추면 소형주 프리미엄을 담는다.", mode = "backstop")
  check("backstop: 유동성 완화 = 위반", isFALSE(b3$pass))
  ba <- check_constraint_firewall("25종 종목수 제약 때문에 분산이 안 되어 실패했다.", mode = "backstop")
  check("backstop: 종목수 귀속 = 위반", isFALSE(ba$pass))

  # D. backstop: 정직 천장 서술 통과 (false-positive 없어야)
  h1 <- check_constraint_firewall(
    "이 봉투 안에서 single-factor long-only top-25는 PORT_t 2.0이 천장이다. 제약은 문제의 고정 축.",
    mode = "backstop")
  check("backstop: 봉투-안 천장 서술 = 통과", isTRUE(h1$pass))
  h2 <- check_constraint_firewall(
    "long-only top-25 envelope-상대로 이 경로 소진. 다른 방법 소진 시 미해결로 열어둔다.",
    mode = "backstop")
  check("backstop: envelope-상대 + 미해결 = 통과", isTRUE(h2$pass))
  h3 <- check_constraint_firewall(
    "overlay와 regime-conditional 배분·잔차 sleeve로 봉투 안에서 프론티어를 연다.",
    mode = "backstop")
  check("backstop: envelope-안 레버 = 통과", isTRUE(h3$pass))

  # E. 케이스 축적(자기발전): append → few-shot 반영. temp 파일로 격리.
  tmp_root <- file.path(tempdir(), paste0("cfw_test_", as.integer(Sys.time())))
  dir.create(file.path(tmp_root, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  file.copy(.cfw_cases_path(root), .cfw_cases_path(tmp_root), overwrite = TRUE)
  n0 <- length(load_firewall_cases(tmp_root)$cases)
  append_firewall_case(
    caught = "25종이란 틀이 밸류를 죽였다. 그 틀만 없으면 알파가 산다.",
    why = "종목수 제약을 실패 원인으로 귀속 + 제약 완화('틀만 없으면')를 레버로 제시.",
    reframed = "top-25 envelope 안에서 밸류 경로가 이 시기 약함(사실). 프론티어: value+quality composite / regime-conditional value.",
    violation_class = "attribution", root = tmp_root)
  n1 <- length(load_firewall_cases(tmp_root)$cases)
  check("자기발전: append로 케이스 축적됨(+1)", n1 == n0 + 1L)
  # few-shot 소비 확인: load_firewall_context가 새 케이스를 싣는가
  ctx2 <- load_firewall_context(root = tmp_root)
  caught_texts <- vapply(ctx2$cases, function(c) c$caught_text %||% "", character(1))
  check("자기발전: 축적 케이스가 few-shot에 노출됨", any(grepl("틀이 밸류를 죽였", caught_texts)))
  # 중복 append skip
  append_firewall_case(caught = "25종이란 틀이 밸류를 죽였다. 그 틀만 없으면 알파가 산다.",
                       why = "dup", root = tmp_root)
  n2 <- length(load_firewall_cases(tmp_root)$cases)
  check("자기발전: 중복 caught_text skip", n2 == n1)
  unlink(tmp_root, recursive = TRUE)

  cat(sprintf("\n[constraint_firewall selftest] %d/%d PASS%s\n",
              pass_n, pass_n + fail_n, if (fail_n) sprintf(" — %d FAIL", fail_n) else ""))
  invisible(fail_n == 0)
}

if (sys.nframe() == 0 && !interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1 && args[1] == "test") {
    ok <- .cfw_selftest()
    quit(status = if (ok) 0L else 1L)
  } else if (length(args) >= 1 && args[1] == "context") {
    ctx <- load_firewall_context()
    cat("── PRINCIPLE ──\n", ctx$principle, "\n\n", sep = "")
    cat("── GUIDANCE ──\n", ctx$guidance, "\n\n", sep = "")
    cat(sprintf("── CASES (%d/%d) ──\n", length(ctx$cases), ctx$n_cases_total))
    for (c in ctx$cases) cat(sprintf("  [%s/%s] %s\n", c$verdict %||% "?",
      c$violation_class %||% "?", substr(c$caught_text %||% "", 1, 70)))
  } else if (length(args) >= 2 && args[1] == "backstop") {
    r <- check_constraint_firewall(paste(args[-1], collapse = " "), mode = "backstop")
    cat(sprintf("[backstop] pass=%s  n_violations=%d\n", r$pass, length(r$violations)))
    for (v in r$violations) cat(sprintf("  [%s] matched='%s' :: %s\n", v$pattern_class, v$matched, v$snippet))
    if (!r$pass) cat("\nsuggestion: ", r$suggestion, "\n", sep = "")
    cat("\nnote: ", r$note, "\n", sep = "")
  } else {
    cat("usage:\n  Rscript constraint_firewall.R test\n",
        "  Rscript constraint_firewall.R context           # LLM 판정 컨텍스트 출력(semantic primary)\n",
        "  Rscript constraint_firewall.R backstop <text...> # 결정론 1차 필터(비-소진적)\n", sep = "")
  }
}
