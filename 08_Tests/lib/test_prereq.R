#==============================================================================
# test_prereq.R — 배터리 suite 공용 "전제 부재 → skip" 계약 (2026-08-02)
#
# 문제:
#   08_Tests 배터리의 일부 케이스는 **gitignore 된 재생성 산출물**(.cache/*)을 읽는다.
#   worktree 는 .gitignore:5 로 .cache/ 를 추적하지 않으므로 그 트리에는 산출물이 없다
#   (실측 2026-08-02: main .cache = 240 항목 / worktree = 1 항목). 이때 케이스가 FAIL 로
#   계상되면 "코드 결함"과 "전제 부재"가 같은 빨강이 된다 — 러너 앵커를 self-first 로
#   고친 직후 정확히 이 형태로 worktree 배터리가 상시 빨강이 됐다.
#
# ★그런데 skip 을 **조용히** 만들면 지금보다 나쁘다.
#   이 저장소의 반복 실패 계통 1순위가 "전제/결손을 정상값으로 내려앉힘"이다
#   (빈 결과=합격 11지점 · 미스캔=PIT 통과 · 발화 0=안전 · 존재 검사로 정체성 검사 대체).
#   그래서 이 계약은 skip 을 **말하게** 만든다:
#     ① skip 은 반드시 *구체적 파일 경로*(prereq)를 근거로 남긴다 — 사유 문자열만으로는 불가.
#     ② 그 경로가 **실제로 부재할 때만** skip 이 성립한다. 존재하면 helper 가 거부하고
#        호출자는 정상 검사를 수행한다(= 아래 tp_require 의 반환 계약).
#     ③ 러너(run_all_hooks.sh)가 suite 를 믿지 않고 **경로를 다시 stat 해서 재검증**한다.
#        존재하는데 skip 으로 보고되면 그 자리에서 FAIL 로 뒤집힌다.
#     ④ skip 건수·사유는 러너 총계 라인과 결과 JSON 에 항상 노출된다(0 건이어도 "(skip 0)").
#
# ★적용 경계 (중요):
#   skip 은 **입력 산출물의 부재**에만 쓴다. 검사기 자체가 죽어 결과를 못 내는 경우
#   (해석기 사망 · 라이브러리 부재 · 구문 오류)는 skip 이 아니라 FAIL 이다.
#   둘을 같은 채널로 접으면 "검사 사망"이 "환경 차이"로 위장된다
#   (2026-08-02 실사고: deployed_holdings_check 14 케이스 uniform exit 49 = 미실행인데
#    10/14 가 '검거 성공' 종료코드와 겹쳐 거짓 초록이 났다).
#   요약 JSON 자체를 못 내면 러너의 UNREPORTED 가드가 이미 +1 FAIL 로 계상한다 — 그 경로를
#   이 helper 로 우회하지 말 것.
#
# 사용:
#   source(file.path(PROJ, "08_Tests/lib/test_prereq.R")); tp_init(PROJ)
#   if (!tp_require("E2_canonical_state", ".cache/factor_db/build_hash.txt",
#                   "gitignore 된 재생성 산출물")) {
#     # skip 기록 완료 — 아무것도 하지 않는다
#   } else {
#     ... 실제 검사 ...
#   }
#   cat(tp_summary_json("build_hash_provenance", PASS, FAIL), "\n", sep = "")
#==============================================================================

.TP <- new.env(parent = emptyenv())
.TP$root  <- NULL
.TP$skips <- list()

#' 프로젝트 루트 고정. suite 가 resolve 한 루트를 그대로 넘긴다.
tp_init <- function(root) {
  if (!is.character(root) || length(root) != 1L || !nzchar(root))
    stop("tp_init: root 는 길이-1 비어있지 않은 문자열이어야 함")
  .TP$root  <- normalizePath(root, winslash = "/", mustWork = FALSE)
  .TP$skips <- list()
  invisible(.TP$root)
}

#' 전제 충족 여부. TRUE = 충족(호출자가 실제 검사 수행) / FALSE = 부재를 skip 으로 기록함.
#'
#' ★존재/부재 판정과 skip 기록이 **분리 불가**하다 — 이 함수를 거치지 않고 skip 을
#'   만들 방법을 두지 않는 것이 계약의 핵심이다(있는 산출물을 skip 으로 빼는 경로 봉쇄).
#' @param case    케이스 식별자 (러너 출력·JSON 에 그대로 실린다)
#' @param prereq  repo-상대 경로 1개 이상. 하나라도 없으면 skip.
#' @param reason  왜 이 트리에 없는지 (gitignore 산출물 등). 러너가 그대로 노출한다.
tp_require <- function(case, prereq, reason = "") {
  if (is.null(.TP$root)) stop("tp_require: tp_init(PROJ) 를 먼저 호출할 것")
  if (!is.character(prereq) || length(prereq) == 0L)
    stop("tp_require: prereq 는 최소 1개의 repo-상대 경로여야 함 (사유 문자열만으로 skip 불가)")
  abs <- file.path(.TP$root, prereq)
  miss <- which(!file.exists(abs))
  if (length(miss) == 0L) return(TRUE)          # 전제 충족 → 정상 검사로 진행
  i <- miss[1L]
  .TP$skips[[length(.TP$skips) + 1L]] <- list(
    case       = case,
    prereq     = abs[i],        # 러너가 다시 stat 할 절대경로 (재검증 대상)
    prereq_rel = prereq[i],
    reason     = if (nzchar(reason)) reason else "전제 산출물 부재"
  )
  cat(sprintf("  SKIP: %s — 전제 부재 '%s' (%s)\n", case, prereq[i],
              if (nzchar(reason)) reason else "사유 미기재"))
  FALSE
}

tp_skip_count <- function() length(.TP$skips)
tp_skips      <- function() .TP$skips

#' 요약 JSON 1행. skip 채널을 항상 발행한다 — 0 건이어도 필드를 빼지 않는다
#' (필드 부재는 '스킵 없음'과 '스킵 채널 사망'을 구별하지 못한다).
#' total = pass + fail + skip (= 케이스 총 인구조사). 러너 총계도 같은 정의를 쓴다.
tp_summary_json <- function(test, pass, fail) {
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("tp_summary_json: jsonlite 필요")
  jsonlite::toJSON(list(
    test  = test,
    pass  = as.integer(pass),
    fail  = as.integer(fail),
    skip  = as.integer(length(.TP$skips)),
    total = as.integer(pass) + as.integer(fail) + as.integer(length(.TP$skips)),
    skips = if (length(.TP$skips) == 0L) list() else .TP$skips
  ), auto_unbox = TRUE)
}

#' 사람이 읽는 총계 1행 (suite 표준 "TOTAL: n pass / m fail" 을 skip 까지 확장).
tp_total_line <- function(pass, fail) {
  sprintf("TOTAL: %d pass / %d fail / %d skip\n",
          as.integer(pass), as.integer(fail), length(.TP$skips))
}
