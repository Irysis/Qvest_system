#!/usr/bin/env Rscript
# auto_alpha_gate.R — 자동 alpha-search 산출물 검증 게이트 (도훈 mandate 2026-06-18)
# 무인 AUTORUN 전용. 검증 verdict 를 받아 ADOPT / SCREEN_TIER / QUARANTINE 결정.
# 결정은 *결정적*(코드)으로 — LLM 이 임의로 ADOPT 못 하게 한다. fail-closed(불명확→QUARANTINE).
#
# ── 2026-08-22 개정 (논문 라우터 전수 감사 후속). 세 결함을 동시에 닫는다:
#
#  ① **선언과 실제가 갈렸다.** 구판 gate_rule 문자열은 4층만 말하는데 원장에는
#     `L5_hard_fail_grade_F` 로 떨어진 건이 있었다. 실측: auto_verify_FQ110B_20260808.json 을
#     구판 게이트로 재실행하면 **ADOPT(exit 0)** 가 나오는데 파일에 기록된 판정은 QUARANTINE 이다.
#     ⇒ 게이트가 `hard_fail` 을 **읽지 않아서** 재실행이 판정을 뒤집는다. 이제 읽고, 규칙에 적는다.
#
#  ② **계층 분리가 이 경로에서 소실됐다.** measurement-graduation.md §3 은 2계층을 정의한다 —
#     구조 사유(MDD·turnover)로 탈락해도 **신호가 실재하면** screen_route 로 후속 소비면에
#     라우팅한다. 그런데 구판은 screen_route 를 한 번도 발급하지 않았다(키워드 전수 0회).
#     실측 사례 FQ110B: oos_retention **1.267**(HARD 0.7 통과) · IC +0.0278(ICIR 0.248,
#     pos_rate 62.4%) · PIT 15 PASS/0 FAIL 인데 **MDD 62.7% 하나로** QUARANTINE.
#     §3 이 명시한 그 구조 모순 그대로다 — "overlay 가 시스템 입증 MDD 레버인데
#     모듈 단계에서 선기각". ⇒ 신호층이 살아 있고 탈락 사유가 **구조**면 SCREEN_TIER 로 보낸다.
#     ★SCREEN_TIER 는 자본 tier 에 **어떤 면제도 주지 않는다**(§3 명문). 소비 경로 라벨일 뿐이고
#      exit 은 여전히 1(=L-code 적립 금지)이다. 바뀌는 것은 '버림' 이 '다른 소비면으로' 가 되는 것뿐.
#
#  ③ **입력 계약이 두 갈래인데 한 갈래만 읽었다.** 검증기가 L1_/L2_ 접두 스키마로 진화했는데
#     게이트는 flat 만 읽어 `NULL → FALSE → QUARANTINE` 으로 흡수했다. 실측 21개 중 비-flat 10개.
#     ⚠**실현 손실은 0** 이었다(그 10건은 어차피 FAIL) — 잠복 결함이지 수율 0 의 원인이 아니다.
#     그래도 닫는다: 지금 손실이 없다는 건 아직 좋은 후보가 안 왔다는 뜻이지 오면 잡힌다는 뜻이 아니다.
#     ★그리고 **어느 층도 못 읽으면 판정이 아니라 오류(exit 2)** 다 — 결손을 정상값으로 내려앉히지 않는다.
#
# 입력: auto_verify_<id>.json — flat(`pit_pass` …) 또는 L계층(`L1_pit_pass` …) 둘 다 허용.
#       구조 탈락 신호: `hard_fail`(bool) + `hard_fail_reason`(str) + mdd/calmar/turnover.
# 출력: 같은 JSON 에 gate_decision / gate_failed_layers / gate_rule / gate_authority /
#       screen_route(해당 시) 기록. stdout 1줄. exit 0=ADOPT · 1=미채택(QUARANTINE|SCREEN_TIER) · 2=error.
suppressMessages(library(jsonlite))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) { cat("ERROR: no verification json arg\n"); quit(status = 2) }
vf <- args[1]
if (!file.exists(vf)) { cat("ERROR: verification json missing\n"); quit(status = 2) }
v <- tryCatch(fromJSON(vf, simplifyVector = TRUE), error = function(e) NULL)
if (is.null(v) || !is.list(v)) { cat("ERROR: unreadable verification json\n"); quit(status = 2) }

# ── 3값 판정: TRUE / FALSE / NA(미기입). NA 를 FALSE 로 접지 않는다.
tri <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA)
  if (is.list(x)) {                        # {pass:…} / {verdict:…} 형태 허용
    for (k in c("pass", "verdict", "status", "result")) if (!is.null(x[[k]])) x <- x[[k]]
  }
  if (is.null(x) || length(x) == 0) return(NA)
  if (is.logical(x)) return(isTRUE(x[1]))
  s <- tolower(trimws(as.character(x)[1]))
  if (s %in% c("true", "pass", "1", "yes")) return(TRUE)
  if (s %in% c("false", "fail", "0", "no")) return(FALSE)
  if (s %in% c("skip_not_executed", "skip", "n/a", "na", "")) return(NA)
  FALSE
}
# 계약 2갈래를 별칭으로 흡수 — 소비자가 스키마 버전을 알 필요가 없게 한다.
pick <- function(...) { for (k in c(...)) if (!is.null(v[[k]])) return(tri(v[[k]])); NA }
layers <- c(
  pit        = pick("pit_pass",        "L1_pit_pass", "L1_signal_validity"),
  contract   = pick("contract_pass",   "L2_contract_pass", "L2_factor_authenticity"),
  robustness = pick("robustness_pass", "L3_robustness_pass", "L3_robustness"),
  fidelity   = pick("fidelity_pass",   "L4_fidelity_pass", "L4_fidelity")
)

# ★한 층도 못 읽었으면 판정이 아니라 **오류**다. QUARANTINE 으로 흡수하면
#   '판정했다' 와 '읽지 못했다' 가 같은 라벨이 되고, 그게 수율 0 의 해석을 망친다.
if (all(is.na(layers))) {
  v$gate_decision <- "ERROR_UNREADABLE"
  v$gate_authority <- "auto_alpha_gate.R"
  v$gate_rule <- "입력 계약 불일치 — flat(pit_pass…) 도 L계층(L1_pit_pass…) 도 아님"
  v$gate_checked_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  tryCatch(write(toJSON(v, pretty = TRUE, auto_unbox = TRUE, na = "null"), vf), error = function(e) NULL)
  cat("ERROR: 검증 JSON 에서 4층 중 하나도 읽지 못했습니다 (계약 불일치) — 판정 아님\n")
  quit(status = 2)
}

# ── v9 Lean Loop (2026-08-23): **결측 ≠ 실패**.
#   구판은 `!isTRUE(z)` 라 NA(미기입)도 실패로 접었다. 그 규칙은 4층을 전부 채우는
#   구 체인에서만 맞다 — v9 는 L4 충실성 검증자(claude -p)를 폐지했고, robustness 는
#   산출물에 oos 축이 있을 때만 채워진다. 그대로 두면 lean 입력이 **항상** QUARANTINE 이
#   되어 게이트가 판정을 그만두고 상수를 낸다.
#   ⇒ pit 은 여전히 **필수**(PIT 는 증거 부재를 통과로 읽지 않는다). contract/robustness/
#     fidelity 는 **명시 FALSE 일 때만** 실패고, NA 는 "요구되지 않음"으로 통과시킨다.
#   ★그 사실은 판정에 함께 남긴다 — `lean=true` + `gate_absent_layers`. 판정이 4층 전수
#     위에서 나왔는지 축소 입력 위에서 나왔는지 사후에 구별되지 않으면 수율 해석이 오염된다.
absent <- names(layers)[vapply(layers, is.na, logical(1))]
failed <- names(layers)[vapply(layers, function(z) isFALSE(z), logical(1))]
lean_mode <- isTRUE(tri(v$lean)) || length(absent) > 0
# NA 통과 술어 — 명시 FALSE 만 막는다.
ok_or_absent <- function(nm) !isFALSE(layers[[nm]])

# ── 구조 탈락(hard_fail): 신호 유무가 아니라 배포 형태(MDD·turnover)의 문제.
hard_fail <- isTRUE(tri(v$hard_fail))
hf_reason <- if (!is.null(v$hard_fail_reason)) as.character(v$hard_fail_reason)[1] else ""
structural <- hard_fail && grepl("drawdown|mdd|turnover|calmar|concentration|structural",
                                 hf_reason, ignore.case = TRUE)

# pit 은 항상 명시 TRUE 여야 한다(결측도 불가) — PIT 은 결측을 통과로 읽지 않는다.
signal_alive <- isTRUE(layers[["pit"]]) && ok_or_absent("robustness")
four_pass <- isTRUE(layers[["pit"]]) &&
  all(vapply(c("contract", "robustness", "fidelity"), ok_or_absent, logical(1)))

# ── 등급 바닥(v9 2026-08-23): ADOPT 는 hurdle 등급 A/B 에만. 2026-08-23 실측 — Grade C ·
#   IR −0.48 · 초과CAGR −8.3%p(IVOL×TO 저-저 셀)가 hard_fail 없음 ∧ PIT PASS 만으로 ADOPT 가 됐다
#   (IS 샤프≈0 이라 oos 비율이 5.32 로 폭발해 robustness 도 못 막음). 등급은 lean_verify_build 가
#   hurdle_result 에서 옮겨 적는다(`grade`). 결측은 기존 철학대로 차단하지 않고 **명시 C/F 만** 막는다.
grade_raw  <- if (!is.null(v$grade)) toupper(sub("_.*$", "", as.character(v$grade)[1])) else ""
grade_low  <- grade_raw %in% c("C", "F")
if (grade_low) failed <- c(failed, sprintf("grade_%s", grade_raw))

if (four_pass && !hard_fail && !grade_low) {
  decision <- "ADOPT"; route <- ""
} else if (structural && signal_alive) {
  # §3 screening tier — 신호는 실재하고 배포 형태가 막았다. 버리지 않고 라우팅한다.
  decision <- "SCREEN_TIER"
  route <- if (grepl("turnover", hf_reason, ignore.case = TRUE)) "TURNOVER_REVIEW" else "OVERLAY_CANDIDATE"
} else {
  decision <- "QUARANTINE"; route <- ""
}

v$gate_decision <- decision
v$gate_failed_layers <- paste(c(failed, if (hard_fail) "hard_fail" else NULL), collapse = ",")
v$gate_absent_layers <- paste(absent, collapse = ",")
v$lean <- lean_mode
v$gate_authority <- "auto_alpha_gate.R"   # 에이전트가 쓴 판정과 구분하기 위한 서명
v$gate_rule <- paste0(
  "PIT 는 명시 PASS 필수(결측 불가). contract/robustness/fidelity 는 명시 FAIL 만 실패이고 ",
  "**결측은 요구되지 않음**(v9 lean — L4 폐지·robustness 는 산출물에 있을 때만). ",
  "그 조건 ∧ hard_fail 없음 ∧ hurdle 등급 명시 C/F 아님 → ADOPT. hard_fail 이 구조 사유(MDD/turnover/calmar) ∧ ",
  "PIT PASS ∧ robustness 미-FAIL → SCREEN_TIER(자본 tier 면제 없음, ",
  "measurement-graduation.md §3). 그 외 QUARANTINE.",
  if (lean_mode) sprintf(" [lean=true · 결측층=%s]", paste(absent, collapse = "/")) else "")
if (nzchar(route)) v$screen_route <- route
v$gate_checked_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
tryCatch(write(toJSON(v, pretty = TRUE, auto_unbox = TRUE, na = "null"), vf),
         error = function(e) NULL)

msg <- decision
if (length(failed)) msg <- sprintf("%s: failed=%s", msg, paste(failed, collapse = ","))
if (hard_fail) msg <- sprintf("%s | hard_fail=%s", msg, substr(hf_reason, 1, 80))
if (nzchar(route)) msg <- sprintf("%s | screen_route=%s (자본 tier 면제 아님)", msg, route)
cat(msg, "\n", sep = "")
quit(status = if (decision == "ADOPT") 0L else 1L)
