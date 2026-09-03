#!/usr/bin/env Rscript
# ★RETIRED (v10 2026-08-29 · 헤더 2026-09-03) — 무인 리서치 레인 퇴역: morning_run 에서 철거됐고
#   예약작업·bat 호출 0. 파일은 사료(08_Tests 가 경로로 직접 실행하므로 이동·삭제 금지).
#   재개 레시피 = git 태그 pre-v10-2layer 의 morning_run.sh [0.55]~[0.6] 구간.
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
#       라우팅 신호: `screen_route_hint`(str, lean_verify_build.py 가 hurdle_result 에서 이관) —
#       hard_fail 과 **독립**으로 SCREEN_TIER 를 여는 축(v9.1 S2a). MDD 가 리서치 층 탈락
#       권한을 잃은 뒤에도 결합 층 주소가 살아 있어야 하므로 OR 가산이다.
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
# ── [2026-08-23 v9.1 / S2a] 라우팅을 hard_fail 에서 분리한다.
#   왜: 리서치 층에서 MDD 의 탈락 권한이 사라지면(E-2) `hard_fail=FALSE` 인데도
#   구조 사유(MDD 69.8%)를 갖고 결합 층으로 가야 하는 산출물이 생긴다. 구판은
#   `structural` 이 hard_fail 에 **곱해져** 있어서 그 순간 SCREEN_TIER 발급이 0 이 된다.
#   ⇒ hurdle_gate 가 이미 발급한 라우트 라벨(`screen_route_hint`, lean_verify_build.py:172-174
#     가 hurdle_result 에서 옮겨 적는다)을 **독립 근거로 OR 가산**한다.
#   ★구 경로는 지우지 않는다 — hard_fail 이 살아 있는 구 산출물·합성 입력의 판정이
#     바뀌면 기존 검사기 6개의 단언이 무의미해진다. 가산이지 대체가 아니다.
route_hint <- if (!is.null(v$screen_route_hint)) as.character(v$screen_route_hint)[1] else ""
# ── [2026-08-24] ★세 번째 독립 근거: essence 의 구조 낙폭 라벨.
#   왜 필요한가: 도훈 지시로 essence 의 `hard_fail` 에서 MDD 를 걷어냈다. 그러면 구조
#   후보는 등급으로도 안 걸리고 `hard_fail` 로도 안 걸린다 — 여기서 라벨을 안 읽으면
#   `structural` 이 FALSE 가 되어 **SCREEN_TIER 대신 QUARANTINE 으로 조용히 떨어진다**
#   (실측 22건이 그 대상이었다). MDD 의 탈락 권한을 없애는 것과 **라우팅 근거를 없애는
#   것은 다른 일**이고, 후자는 v9.1/S2a 가 이미 반대한 결함이다.
#   ★가산이지 대체가 아니다 — 위 두 근거(hard_fail 사유 · route_hint)는 그대로 둔다.
es_struct <- isTRUE(v$essence_structural_drawdown)
structural <- (hard_fail && grepl("drawdown|mdd|turnover|calmar|concentration|structural",
                                  hf_reason, ignore.case = TRUE)) ||
              grepl("OVERLAY_CANDIDATE|TURNOVER_REVIEW", route_hint) ||
              es_struct

# pit 은 항상 명시 TRUE 여야 한다(결측도 불가) — PIT 은 결측을 통과로 읽지 않는다.
signal_alive <- isTRUE(layers[["pit"]]) && ok_or_absent("robustness")
four_pass <- isTRUE(layers[["pit"]]) &&
  all(vapply(c("contract", "robustness", "fidelity"), ok_or_absent, logical(1)))

# ── 등급 바닥(v9 2026-08-23): ADOPT 는 hurdle 등급 A/B 에만. 2026-08-23 실측 — Grade C ·
#   IR −0.48 · 초과CAGR −8.3%p(IVOL×TO 저-저 셀)가 hard_fail 없음 ∧ PIT PASS 만으로 ADOPT 가 됐다
#   (IS 샤프≈0 이라 oos 비율이 5.32 로 폭발해 robustness 도 못 막음).
#   ★v9.21 §1-c: `grade` 의 출처가 **hurdle proxy → essence 권위**로 바뀌었다. 옮겨 적는 주체는
#     여전히 lean_verify_build.py 이고, 그 파일이 `grade_basis` 로 출처를 못박는다
#     (essence 부재 시 hurdle 폴백 — 비우지 않는다. 비우면 등급 바닥이 조용히 사라진다).
#   ★`sub("_.*$","")` 는 남긴다 — essence 는 접미어를 내지 않지만 구 산출물(proxy A_NOVEL 등)이
#     같은 필드로 들어오므로, 지우면 그 판들이 "A_NOVEL" 그대로 비교돼 등급 바닥을 우회한다.
#   결측(등급 없음)은 기존 철학대로 차단하지 않는다 — 막는 것은 **명시 등급**뿐이고,
#   그 집합은 축마다 다르다(바로 아래에서 재단).
grade_raw  <- if (!is.null(v$grade)) toupper(sub("_.*$", "", as.character(v$grade)[1])) else ""
# ── ★바닥의 **엄격도는 등급 축마다 다르다** (2026-08-24 실측으로 재단).
#   소스를 proxy→권위로 바꾸면서 차단 집합 {C,F} 를 그대로 두면 **바닥을 이중으로 조인다**.
#   실측(authoritative_remeasure.json 207 런, 같은 런의 두 등급 대조):
#     hurdle  A 11 · B 169 · C 18 · F  9  → {C,F} 차단  27 (13%)
#     essence B  3 · C 138 · F 66        → {C,F} 차단 204 (**99%**)
#   ⇒ 무인 레인의 ADOPT(=L-code 적립 허용)가 87%→1% 로 붕괴한다. 그건 판정 강화가 아니라
#     **원장 정지**다(공리 엔진의 연료가 끊긴다).
#
#   ★바닥이 원래 막으려던 것으로 재단한다. 2026-08-23 도입 사유가 코드에 남아 있다 —
#     "Grade C · **IR −0.48** · 초과CAGR −8.3%p 가 ADOPT 됐다". 그건 **음(−)의 알파**이고
#     essence 에서 그것의 정확한 이름은 **F** 다(`port_t <= 0 || net_ir <= 0` 분지).
#     반면 essence **C** 는 "양(+)의 알파이나 B 미달" — 리서치 층이 교훈으로 남겨야 하는
#     재료이고 lean-loop 5단계가 적립 대상으로 규정한 바로 그것이다.
#   ⇒ 권위 축에서는 **F 만** 막고, proxy 폴백 축에서는 구 동작 {C,F} 를 유지한다
#     (구 산출물·합성 입력의 판정이 바뀌면 기존 검사기 6개의 단언이 무의미해진다).
gb <- if (!is.null(v$grade_basis)) as.character(v$grade_basis)[1] else ""
grade_authoritative <- grepl("essence", gb, fixed = TRUE)
grade_floor <- if (grade_authoritative) c("F") else c("C", "F")
grade_low  <- grade_raw %in% grade_floor
if (grade_low) failed <- c(failed, sprintf("grade_%s", grade_raw))

if (four_pass && !hard_fail && !grade_low) {
  # ★ADOPT 도 라벨을 보존한다(2026-08-23). 구판은 여기서 route 를 "" 로 덮었다 —
  #   그래서 "채택됐다"와 "어느 결합 층으로 가나"가 배타가 됐고, MDD 탈락 권한이
  #   사라져 구조 후보들이 ADOPT 로 올라오는 순간 결합 층 주소가 통째로 증발한다.
  decision <- "ADOPT"; route <- route_hint
} else if (structural && signal_alive) {
  # §3 screening tier — 신호는 실재하고 배포 형태가 막았다. 버리지 않고 라우팅한다.
  decision <- "SCREEN_TIER"
  route <- if (nzchar(route_hint)) route_hint
           else if (grepl("turnover", hf_reason, ignore.case = TRUE)) "TURNOVER_REVIEW"
           else "OVERLAY_CANDIDATE"
} else {
  decision <- "QUARANTINE"; route <- ""
}

v$gate_decision <- decision
v$gate_failed_layers <- paste(c(failed, if (hard_fail) "hard_fail" else NULL), collapse = ",")
v$gate_absent_layers <- paste(absent, collapse = ",")
v$lean <- lean_mode
v$gate_authority <- "auto_alpha_gate.R"   # 에이전트가 쓴 판정과 구분하기 위한 서명
# ★판정 근거를 원장에 남긴다 — 세 근거 중 무엇이 SCREEN_TIER 를 만들었는지 사후에 갈리게.
#   이걸 안 남기면 "라우팅이 왜 됐나"를 재구성할 수 없다(구조 라벨이 등급에서 빠진 뒤로
#   등급만 보고는 알 수 없다).
v$gate_structural_basis <- paste(c(
  if (hard_fail && grepl("drawdown|mdd|turnover|calmar|concentration|structural", hf_reason,
                         ignore.case = TRUE)) "hard_fail_reason" else NULL,
  if (grepl("OVERLAY_CANDIDATE|TURNOVER_REVIEW", route_hint)) "screen_route_hint" else NULL,
  if (es_struct) "essence_structural_drawdown" else NULL), collapse = ",")
if (!is.null(v$grade_basis)) v$gate_grade_basis <- as.character(v$grade_basis)[1]
# 바닥 집합도 남긴다 — 축마다 다르므로 사후에 "왜 이 등급이 통과/차단됐나"가 갈려야 한다.
v$gate_grade_floor <- paste(grade_floor, collapse = ",")
v$gate_rule <- paste0(
  "PIT 는 명시 PASS 필수(결측 불가). contract/robustness/fidelity 는 명시 FAIL 만 실패이고 ",
  "**결측은 요구되지 않음**(v9 lean — L4 폐지·robustness 는 산출물에 있을 때만). ",
  "그 조건 ∧ hard_fail 없음 ∧ 등급이 바닥 집합 밖 → ADOPT. ★바닥은 축마다 다르다 — ",
  "권위(essence)={F} (음의 알파만) · proxy(hurdle)={C,F} (구 동작 유지). 소스를 권위로 바꾸며 ",
  "{C,F} 를 그대로 두면 실측 99% 차단 = 원장 정지였다(2026-08-24). 구조 근거 3종 중 하나 ",
  "(①hard_fail 사유가 MDD/turnover/calmar ②screen_route_hint 가 OVERLAY_CANDIDATE/TURNOVER_REVIEW ",
  "③essence structural_drawdown 라벨) ∧ PIT PASS ∧ robustness 미-FAIL → ",
  "SCREEN_TIER(자본 tier 면제 없음, measurement-graduation.md §3). 그 외 QUARANTINE. ",
  "★ADOPT 는 리서치 층 채택이고 자본 자격이 아니다. ★MDD 는 **어느 층에서도 등급을 접지 않는다** ",
  "(2026-08-24 도훈 지시 — essence 의 drawdown→hard_fail 추론 제거). 위험 축은 Calmar 비율 ",
  "(=CAGR/|MDD| ≥ 0.64) 하나이고, 자본 층은 그 위에 discovery_graduation_gate HARD 4종을 얹는다. ",
  "screen_route 는 ADOPT 에서도 보존된다(라우팅은 등급·hard_fail 과 독립 축, v9.1 S2a).",
  if (lean_mode) sprintf(" [lean=true · 결측층=%s]", paste(absent, collapse = "/")) else "")
if (nzchar(route)) v$screen_route <- route
v$gate_checked_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
tryCatch(write(toJSON(v, pretty = TRUE, auto_unbox = TRUE, na = "null"), vf),
         error = function(e) NULL)

msg <- decision
if (length(failed)) msg <- sprintf("%s: failed=%s", msg, paste(failed, collapse = ","))
if (hard_fail) msg <- sprintf("%s | hard_fail=%s", msg, substr(hf_reason, 1, 80))
if (nzchar(route)) msg <- sprintf("%s | screen_route=%s (근거=%s · 자본 tier 면제 아님)",
                                  msg, route, v$gate_structural_basis)
cat(msg, "\n", sep = "")
quit(status = if (decision == "ADOPT") 0L else 1L)
