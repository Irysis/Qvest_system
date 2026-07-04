# constraint_firewall.R — 제약 방화벽 (2026-07-04 실패지식 아키텍처 그룹 C+D)
#
# 원리3 (제약 방화벽): 고정 제약 7종 + PIT는 배포 현실이 정의한 '문제의 고정 축'이다.
#   실패를 이 제약에 *귀속*하거나 제약 *완화*를 레버로 제시하는 것 = 금지(초안 REJECT).
#   AX-000 따름정리: 제약은 게임의 법칙 — 창의 부담은 방법(envelope-안 레버)에 진다.
#
# 고정 제약 7종 (변수 아님, 실패 원인/레버로 삼으면 REJECT):
#   ① 종목수 max 25  ② 유동성 20일 평균 거래대금 ≥ 2e8 KRW  ③ Long-only(weights≥0)
#   ④ Weight bounds [0,0.20]  ⑤ Σw=1  ⑥ Universe KOSPI200∪KOSDAQ150
#   ⑦ Transaction cost 15bps one-way(v2.4 delta)  + PIT C1~C15
#
# envelope-안 레버(프론티어 화이트리스트 — 이것만 정당한 탐색축):
#   overlay · 잔차 sleeve · 비-return 데이터 · DPL · regime-conditional · multi-sleeve
#   · composite · ML sizing
#
# ★ 신중 (false-positive 방지): "이 봉투 *안에서* 이 방법은 천장"이라는 정직한 서술은
#   PASS(원인 귀속 아님 — envelope-상대 사실). 방화벽은 '제약을 원인/레버로' 삼는
#   진술만 잡는다. 미해결 열어둠(AX-000)도 제약 완화가 아니므로 PASS.
#
# 주요 함수:
#   check_constraint_firewall(text) → list(pass, violations, suggestion)
#     violations: list of {pattern_class, matched, snippet}
#
# 참조: docs/rules/axiom-engine.md INV-7 · CLAUDE.md Production Constraints
#       04_Research/01_reports/failure_knowledge_architecture_plan_20260704.md (원리3/D/H)

# ── 고정 제약 어휘 (원인/레버 귀속 탐지 대상) ──
# 한국어·영어 혼용 진술 모두 커버. 정규식은 대소문자 무시.
.CFW_CONSTRAINT_TERMS <- c(
  # long-only / short
  "long[- ]?only", "롱온리", "롱[- ]?온리", "공매도", "short(ing|-?sell)?", "숏",
  # 종목수
  "종목수", "종목 ?수", "25 ?종", "max ?25", "n_?stocks", "num_?holdings",
  # 유동성
  "유동성", "거래대금", "liquidity", "2e8", "2억",
  # weight bounds / Σw / long-only weight
  "weight ?bound", "비중 ?(상한|한도|제약)", "\\[0, ?0\\.2", "0\\.20 ?cap", "weights? ?≥ ?0", "weights? ?>= ?0",
  # universe
  "유니버스", "universe", "kospi ?200", "k200", "kosdaq ?150", "kq150", "코스피 ?200", "코스닥 ?150",
  # cost
  "거래비용", "transaction ?cost", "15 ?bps", "회전.?비용", "비용 ?모델",
  # PIT (완화 대상으로 삼으면 특히 심각)
  "pit\\b", "미래참조", "look[- ]?ahead"
)

# ── 원인 귀속(attribution) 트리거: "제약 때문에 실패" ──
# 제약어휘 근처에 '때문에/라서/탓에/한계/못/불가/실패' 가 오면 원인귀속 의심.
.CFW_ATTRIBUTION_TRIGGERS <- c(
  "때문에", "때문", "라서", "이라서", "탓", "탓에", "탓으로",
  "제약(으로|이|은|의)? ?(한계|실패|막|묶|발목|천장|원인)",
  "제약 ?때문", "때문에 ?실패", "제약이 ?실패",
  "(long[- ]?only|롱온리|롱 ?온리|공매도 ?불가|숏 ?불가) ?(라서|때문|이라서|여서|이므로|이기 ?때문)",
  "(25 ?종|종목수) ?(제약|한계|때문|이라서|라서|묶여|막혀)",
  "(유동성|universe|유니버스) ?(제약|한계|때문|이라서|라서)",
  "constrain(ed|t) ?(by|caused|limit)", "because of (the )?(constraint|long[- ]?only|universe|liquidity)",
  "due to (the )?(constraint|long[- ]?only|universe|liquidity)",
  "제약이 ?(원인|주범|병목|바인딩)"
)

# ── 완화 레버(relaxation-as-lever) 트리거: "제약 풀면 된다" ──
.CFW_RELAXATION_TRIGGERS <- c(
  "제약 ?(완화|해지|해제|풀|풀면|풀어|없애|없으면|제거|늘리|상향|확대|초과)",
  "완화(가|를|하면|해야|가 ?필요|가 ?레버|가 ?유일)",
  "short(ing)? ?(허용|가능|열|풀)", "공매도 ?(허용|가능|열|풀|도입)", "숏 ?(허용|가능|열)",
  "롱숏(이면|으로|이 ?되면|허용)", "long[- ]?short ?(이면|으로|허용|되면|가능)",
  ">? ?25 ?종 (넘게|이상|초과|필요|허용|늘)", "25 ?종 ?(넘게|이상|초과|이상으로|넘어)",
  "종목수 ?(늘|확대|상향|초과|제한 ?풀)", "n_?stocks ?(>|증가|늘)",
  "유니버스 ?(확대|넓|늘|전종목|풀|밖)", "universe ?(expand|widen|relax|beyond)",
  "유동성 ?(기준)?(을|를|은|는| )? ?(완화|낮|풀|내리|하향)", "liquidity ?(threshold ?)?(relax|lower)",
  "비중 ?(상한|한도) ?(완화|풀|올리|상향|초과)", "0\\.2(0)? ?(넘게|초과|상향|완화)",
  "제약 ?없으면", "제약 ?없이", "without (the )?constraint", "if .{0,15}(constraint|long[- ]?only) .{0,10}relax",
  "relax(ing|ed)? ?(the )?(constraint|universe|liquidity|long[- ]?only|bound|cap)",
  "제약을 ?레버", "완화를 ?레버", "제약 ?완화가 ?(레버|유일|필요|해법)"
)

# ── envelope-안 레버 화이트리스트 (정당한 프론티어 — 이 어휘 존재는 방화벽 통과 방향) ──
.CFW_ENVELOPE_LEVERS <- c(
  "overlay", "오버레이", "잔차 ?sleeve", "잔차 ?슬리브", "residual ?sleeve",
  "비-?return", "비 ?리턴", "non[- ]?return", "대체 ?데이터", "alternative ?data", "dart", "insider",
  "\\bdpl\\b", "direct ?portfolio", "regime[- ]?conditional", "국면[- ]?(조건부|배분|배합|인지)",
  "multi[- ]?sleeve", "다 ?sleeve", "다 ?슬리브", "멀티 ?sleeve",
  "composite", "컴포지트", "복합 ?팩터", "ml ?sizing", "ml ?비중", "머신러닝 ?sizing"
)

# ── 정직한 envelope-상대 천장 서술 (원인귀속 아님 — 명시 PASS 신호) ──
# "이 봉투 안에서 천장" / "envelope-상대" / "미해결 열어둠" 은 제약을 원인/레버로 삼지 않음.
.CFW_HONEST_CEILING <- c(
  "봉투 ?(안|내)(에서)?", "envelope[- ]?(안|상대|내|relative|within)", "제약 ?(안|내)(에서)?",
  "이 ?(제약|봉투|envelope) ?(하에서|안에서|내에서)",
  "천장(이다|에 ?도달|은|을 ?친|이 ?존재)", "ceiling (within|under)",
  "미해결(로)? ?(열어|남|둠)", "unresolved", "open ?(problem|question)",
  "제약은 ?문제의 ?축", "고정 ?축", "문제의 ?(고정 )?축", "problem ?axis"
)

.cfw_grep_any <- function(text, patterns) {
  hits <- character(0)
  for (p in patterns) {
    m <- regmatches(text, regexpr(p, text, ignore.case = TRUE, perl = TRUE))
    if (length(m) && nzchar(m)) hits <- c(hits, m)
  }
  unique(hits)
}

# 매치 주변 스니펫 (감사 가독성)
.cfw_snippet <- function(text, needle, span = 40L) {
  pos <- regexpr(needle, text, ignore.case = TRUE, perl = TRUE, fixed = FALSE)
  if (pos[1] < 0) return(substr(text, 1, min(nchar(text), 80)))
  s <- max(1L, pos[1] - span); e <- min(nchar(text), pos[1] + attr(pos, "match.length") + span)
  gsub("\\s+", " ", substr(text, s, e))
}

#' 제약 방화벽 판정
#'
#' @param text 검사할 진술 (statement_refined + retry_condition 등 초안 텍스트)
#' @return list(pass=logical, violations=list, suggestion=character)
#'   violations 원소: list(pattern_class=c("attribution","relaxation"), matched, snippet)
check_constraint_firewall <- function(text) {
  if (is.null(text) || !nzchar(paste(text, collapse = " ")))
    return(list(pass = TRUE, violations = list(), suggestion = ""))
  txt <- paste(text, collapse = " \n ")

  has_constraint_term <- length(.cfw_grep_any(txt, .CFW_CONSTRAINT_TERMS)) > 0
  attribution_hits <- .cfw_grep_any(txt, .CFW_ATTRIBUTION_TRIGGERS)
  relaxation_hits  <- .cfw_grep_any(txt, .CFW_RELAXATION_TRIGGERS)
  honest_ceiling   <- length(.cfw_grep_any(txt, .CFW_HONEST_CEILING)) > 0

  violations <- list()

  # (1) 완화 레버: 제약어휘 유무와 무관하게 완화 트리거 자체가 위반
  #     ("short 허용", ">25종", "제약 완화" 등은 그 자체로 완화-레버 제시)
  if (length(relaxation_hits) > 0) {
    for (h in relaxation_hits) {
      violations[[length(violations) + 1L]] <- list(
        pattern_class = "relaxation",
        matched = h, snippet = .cfw_snippet(txt, h))
    }
  }

  # (2) 원인 귀속: 제약어휘 + 귀속트리거 동시 존재 시 위반.
  #     단 '정직한 envelope-상대 천장 서술'이면 원인귀속으로 오탐하지 않음.
  #     (천장 서술은 제약을 원인이 아니라 '문제의 축'으로 취급 — 통과)
  if (has_constraint_term && length(attribution_hits) > 0 && !honest_ceiling) {
    for (h in attribution_hits) {
      violations[[length(violations) + 1L]] <- list(
        pattern_class = "attribution",
        matched = h, snippet = .cfw_snippet(txt, h))
    }
  }

  pass <- length(violations) == 0
  suggestion <- if (pass) "" else paste0(
    "제약 방화벽 위반 — 고정 제약(종목수≤25·유동성 2e8·long-only·[0,0.20]·Σw=1·",
    "K200∪KQ150·15bps·PIT)은 문제의 고정 축이지 변수가 아닙니다. ",
    "실패를 제약에 귀속하거나 제약 완화를 레버로 제시하지 말고, envelope-안 레버",
    "(overlay·잔차 sleeve·비-return 데이터·DPL·regime-conditional·multi-sleeve·composite·ML sizing) ",
    "상대로 재작성하세요. '이 봉투 안에서 이 경로는 천장'식 정직 서술 또는 '미해결 열어둠'(AX-000)은 허용됩니다.")

  list(pass = pass, violations = violations, suggestion = suggestion)
}

# ── 단위 테스트 (Rscript constraint_firewall.R test) ──
.cfw_selftest <- function() {
  cases <- list(
    # REJECT — 원인 귀속
    list(t = "EP-단독 전략이 long-only라서 실패했다. 공매도가 불가능해 short leg 알파를 못 담는다.",
         expect = FALSE, label = "attribution: long-only 때문에 실패"),
    list(t = "25종 종목수 제약 때문에 분산이 안 되어 MDD가 커졌다.",
         expect = FALSE, label = "attribution: 종목수 제약 때문에"),
    list(t = "유니버스 제약이 원인이라 알파가 희석된다.",
         expect = FALSE, label = "attribution: universe 제약이 원인"),
    # REJECT — 완화 레버
    list(t = "SR 천장 ~1.1, 돌파는 >25종 분산 또는 short 허용뿐이다.",
         expect = FALSE, label = "relaxation: >25종 / short 허용"),
    list(t = "제약을 완화해서 롱숏으로 가면 SR이 오른다.",
         expect = FALSE, label = "relaxation: 제약 완화 + 롱숏"),
    list(t = "제약 없으면 이 알파는 통과한다.",
         expect = FALSE, label = "relaxation: 제약 없으면"),
    list(t = "유동성 기준을 낮추면 소형주 프리미엄을 담을 수 있다.",
         expect = FALSE, label = "relaxation: 유동성 완화"),
    # PASS — envelope-안 레버
    list(t = "이 경로는 standalone에서 약하나, overlay와 regime-conditional 배분으로 프론티어가 열린다.",
         expect = TRUE, label = "envelope lever: overlay + regime-conditional"),
    list(t = "잔차 sleeve 스태킹과 DPL 직접 최적화로 봉투 안에서 SR을 올린다.",
         expect = TRUE, label = "envelope lever: 잔차 sleeve + DPL"),
    list(t = "비-return 데이터(DART insider)와 multi-sleeve composite로 다음 가설을 세운다.",
         expect = TRUE, label = "envelope lever: 비-return + multi-sleeve"),
    # PASS — 정직한 envelope-상대 천장 서술
    list(t = "이 봉투 안에서 single-factor long-only top-25는 PORT_t 2.0이 천장이다. 제약은 문제의 고정 축.",
         expect = TRUE, label = "honest ceiling: 봉투 안 천장 + 문제의 축"),
    list(t = "long-only top-25 envelope-상대로 이 경로는 소진. 다른 방법 소진 시 미해결로 열어둔다.",
         expect = TRUE, label = "honest ceiling: envelope-상대 + 미해결 열어둠"),
    # PASS — 제약 무관 일반 실패 서술
    list(t = "value premium 약화 + quality mix 부재로 EP-단독 경로가 이 시기 F. composite로 재도전.",
         expect = TRUE, label = "neutral: 메커니즘 서술 + composite frontier")
  )
  pass_n <- 0L; fail_n <- 0L
  for (c in cases) {
    r <- check_constraint_firewall(c$t)
    ok <- identical(r$pass, c$expect)
    if (ok) pass_n <- pass_n + 1L else fail_n <- fail_n + 1L
    cat(sprintf("[%s] %s  (got pass=%s, expect=%s, nviol=%d)\n",
                if (ok) "OK  " else "FAIL", c$label, r$pass, c$expect, length(r$violations)))
  }
  cat(sprintf("\n[constraint_firewall selftest] %d/%d PASS%s\n",
              pass_n, pass_n + fail_n, if (fail_n) sprintf(" — %d FAIL", fail_n) else ""))
  invisible(fail_n == 0)
}

if (sys.nframe() == 0 && !interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1 && args[1] == "test") {
    ok <- .cfw_selftest()
    quit(status = if (ok) 0L else 1L)
  } else if (length(args) >= 2 && args[1] == "check") {
    r <- check_constraint_firewall(paste(args[-1], collapse = " "))
    cat(sprintf("pass=%s  n_violations=%d\n", r$pass, length(r$violations)))
    for (v in r$violations) cat(sprintf("  [%s] matched='%s' :: %s\n", v$pattern_class, v$matched, v$snippet))
    if (!r$pass) cat("\nsuggestion: ", r$suggestion, "\n", sep = "")
  } else {
    cat("usage:\n  Rscript constraint_firewall.R test\n",
        "  Rscript constraint_firewall.R check <text...>\n", sep = "")
  }
}
