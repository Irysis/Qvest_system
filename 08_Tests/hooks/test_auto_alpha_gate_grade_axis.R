# test_auto_alpha_gate_grade_axis.R — 무인 게이트의 등급 축·구조 라우팅 계약 (v9.21 축 1-c)
#
# 대상: 02_Infrastructure/ops/auto_alpha_gate.R  (등급 바닥 · 구조 근거 3종)
#       02_Infrastructure/ops/lean_verify_build.py (등급 출처 · 라벨 이관)
#
# ★왜 이 시험이 필요한가 — 두 결함이 **서로를 가린다**:
#
#   ① 2026-08-24 도훈 지시로 essence 의 `hard_fail` 에서 MDD 를 걷어냈다. 그러면 구조 후보가
#      등급으로도 `hard_fail` 로도 안 걸린다. 게이트가 `essence_structural_drawdown` 라벨을
#      읽지 않으면 그 후보는 **SCREEN_TIER 대신 QUARANTINE 으로 조용히 떨어진다**
#      (실측 22건). "MDD 의 탈락 권한을 없애는 것" 과 "라우팅 근거를 없애는 것" 은 다른 일이다.
#
#   ② 등급 소스를 proxy→권위로 바꾸며 차단 집합 {C,F} 를 그대로 두면 바닥이 **이중으로** 조인다.
#      실측(같은 런 207건의 두 등급 대조): hurdle {C,F} 차단 27(13%) vs essence {C,F} 차단
#      204(**99%**). 그건 판정 강화가 아니라 **원장 정지**다 — ADOPT 가 L-code 적립 조건이므로
#      무인 레인의 적립이 87%→1% 로 붕괴한다.
#      ⇒ 바닥을 도입 사유로 재단했다: 권위 축은 **{F}**(음의 알파 = 도입 사유 그 자체),
#        proxy 축은 **{C,F}**(구 동작 유지 — 기존 검사기 6개의 단언을 살린다).
#
# 이 시험은 **위반 주입 + 돌연변이 통제**로 두 결함을 양방향으로 잡는다.
# 계기는 "경고 0" 이 아니라 **발화 실증**으로 신뢰한다.

suppressPackageStartupMessages({ library(jsonlite) })

PASS <- 0L; FAIL <- 0L; SKIP <- 0L; SKIPS <- list()
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, " :: ", d, "\n") }
sk <- function(a, r, mi) { SKIP <<- SKIP + 1L
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = a, reason = r, missing = mi)
  cat("  SKIP ", a, " — ", r, "\n") }
emit <- function() {
  ## ★임시 디렉터리 정리는 **여기**서 한다 — 최상위 `on.exit()` 는 조용한 no-op 이라
  ##   (r-portability 금칙 2) 정리가 한 번도 실행되지 않는다. emit() 이 유일 종료점이므로
  ##   수명을 여기에 묶는다. 2026-08-24 같은 함정을 하루에 두 번 밟았다.
  if (exists("TMP", inherits = TRUE)) try(unlink(TMP, recursive = TRUE, force = TRUE), silent = TRUE)
  cat(sprintf("\nTOTAL: %d pass / %d fail / %d skipped\n", PASS, FAIL, SKIP))
  j <- sprintf('{"test":"auto_alpha_gate_grade_axis","pass":%d,"fail":%d,"total":%d,"skipped":%d',
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
GATE <- file.path(ROOT, "02_Infrastructure", "ops", "auto_alpha_gate.R")
LVB  <- file.path(ROOT, "02_Infrastructure", "ops", "lean_verify_build.py")

cat("=== auto_alpha_gate 등급 축 · 구조 라우팅 (v9.21) ===\n")
if (!file.exists(GATE)) { sk("gate_present", "auto_alpha_gate.R 부재", GATE); emit() }

TMP <- file.path(tempdir(), sprintf("aagx_%d", Sys.getpid()))
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
# (정리는 emit() 이 한다 — 최상위 on.exit 은 no-op. r-portability 금칙 2)

# 게이트를 **실제로 실행**한다 — 자구 grep 이 아니라 판정을 본다.
#   ★Rscript 를 한 줄 인자로만 부른다(개행 포함 -e 는 이 환경에서 rc=139).
run_gate <- function(fields, label) {
  p <- file.path(TMP, sprintf("auto_verify_%s.json", label))
  write(toJSON(fields, auto_unbox = TRUE, pretty = TRUE, na = "null"), p)
  out <- suppressWarnings(system2("Rscript", c(GATE, p), stdout = TRUE, stderr = TRUE))
  rc <- attr(out, "status"); if (is.null(rc)) rc <- 0L
  back <- tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) list())
  list(rc = as.integer(rc), stdout = paste(out, collapse = " "),
       decision = back$gate_decision %||% NA_character_,
       route = back$screen_route %||% NA_character_,
       floor = back$gate_grade_floor %||% NA_character_,
       basis = back$gate_structural_basis %||% NA_character_,
       failed = back$gate_failed_layers %||% NA_character_)
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# 통과 기반 골격 — PIT PASS · contract PASS · 나머지 결측(lean)
base_ok <- list(lean = TRUE, pit_pass = TRUE, contract_pass = TRUE,
                robustness_pass = TRUE, strategy_id = "TESTX")

# ══ A. 등급 바닥이 축마다 다르다 (②) ════════════════════════════════════════
cat("\n── A. 등급 바닥 = 축별 재단 ────────────────────────────────\n")

# A1 — 권위 축 · essence C → **ADOPT** (원장 정지 방지). 이것이 이번 변경의 본체다.
r <- run_gate(c(base_ok, list(grade = "C",
                grade_basis = "essence_score(authoritative_remeasure.json)")), "a1")
if (identical(r$decision, "ADOPT") && identical(r$rc, 0L))
  ok("권위 축 essence C → ADOPT (양의 알파는 적립된다 — 원장 정지 방지)") else
  ng("★권위 축에서 C 가 막혔다 — 무인 레인 적립이 1% 로 붕괴한다",
     sprintf("decision=%s rc=%d floor=%s", r$decision, r$rc, r$floor))

# A2 — 권위 축 바닥이 실제로 {F} 로 기록되는가(사후 감사 가능성)
if (identical(as.character(r$floor), "F"))
  ok("권위 축 바닥 = {F} 로 원장에 기록 — 왜 통과했는지 사후에 갈린다") else
  ng("★바닥 집합이 기록되지 않았다", sprintf("floor=%s", r$floor))

# A3 — 권위 축 · essence F → 차단. 바닥이 **무언가는** 막아야 계기다(양성 대조).
r <- run_gate(c(base_ok, list(grade = "F",
                grade_basis = "essence_score(authoritative_remeasure.json)")), "a3")
if (!identical(r$decision, "ADOPT") && grepl("grade_F", as.character(r$failed), fixed = TRUE))
  ok("권위 축 essence F → 차단 (도입 사유 = IR −0.48 음의 알파를 정확히 잡는다)") else
  ng("★권위 축에서 F 가 통과했다 — 바닥이 아무것도 막지 않는다",
     sprintf("decision=%s failed=%s", r$decision, r$failed))

# A4 — proxy 축 · hurdle C → 차단 (구 동작 유지. 기존 검사기 6개의 단언 보호)
r <- run_gate(c(base_ok, list(grade = "C",
                grade_basis = "hurdle_gate(proxy — 권위 등급 부재)")), "a4")
if (!identical(r$decision, "ADOPT") && identical(as.character(r$floor), "C,F"))
  ok("proxy 축 hurdle C → 차단 · 바닥 {C,F} (구 동작 유지)") else
  ng("★proxy 축 구 동작이 깨졌다", sprintf("decision=%s floor=%s", r$decision, r$floor))

# A5 — ★돌연변이 통제: 축 라벨을 지우면 A1 이 뒤집히는가
#   grade_basis 가 없으면 proxy 로 읽혀 C 가 막혀야 한다. 안 뒤집히면 A1 은 아무것도 안 재는 것.
r <- run_gate(c(base_ok, list(grade = "C")), "a5")
if (!identical(r$decision, "ADOPT") && identical(as.character(r$floor), "C,F"))
  ok("돌연변이 통제: grade_basis 제거 → proxy 로 읽혀 C 차단 (A1 이 축을 실제로 재고 있다)") else
  ng("★돌연변이 통제 실패 — grade_basis 없이도 C 가 통과한다(바닥이 무조건 느슨)",
     sprintf("decision=%s floor=%s", r$decision, r$floor))

# A6 — 등급 결측은 차단하지 않는다(기존 철학 — 결측 ≠ 실패)
r <- run_gate(base_ok, "a6")
if (identical(r$decision, "ADOPT"))
  ok("등급 결측 → 차단 안 함 (결측 ≠ 실패, v9 lean 철학 유지)") else
  ng("★결측을 실패로 접었다", sprintf("decision=%s", r$decision))

# ══ B. 구조 라우팅 — essence 라벨이 세 번째 독립 근거 (①) ═══════════════════
cat("\n── B. 구조 라우팅 3종 근거 ─────────────────────────────────\n")

# B1 — ★핵심: hard_fail 없음 ∧ route_hint 없음 ∧ essence 라벨만 → SCREEN_TIER
#   MDD 를 걷어낸 뒤 이 경로가 유일한 라우팅 근거다. 없으면 22건이 QUARANTINE.
r <- run_gate(c(base_ok, list(grade = "F",
                grade_basis = "essence_score(authoritative_remeasure.json)",
                essence_structural_drawdown = TRUE)), "b1")
if (identical(r$decision, "SCREEN_TIER") &&
    identical(as.character(r$route), "OVERLAY_CANDIDATE"))
  ok("essence 구조 라벨 단독 → SCREEN_TIER/OVERLAY_CANDIDATE (22건이 QUARANTINE 되지 않는다)") else
  ng("★구조 라벨을 읽지 않는다 — MDD 후보가 조용히 QUARANTINE 된다",
     sprintf("decision=%s route=%s basis=%s", r$decision, r$route, r$basis))

# B2 — 그 근거가 원장에 이름으로 남는가 (셋 중 무엇이 라우팅을 만들었나)
if (grepl("essence_structural_drawdown", as.character(r$basis), fixed = TRUE))
  ok("라우팅 근거가 이름으로 기록 — 사후에 셋 중 무엇이 발화했는지 갈린다") else
  ng("★근거가 기록되지 않았다 — 라우팅 재구성 불가", sprintf("basis=%s", r$basis))

# B3 — ★돌연변이 통제: 라벨을 FALSE 로 바꾸면 QUARANTINE 으로 뒤집히는가
r <- run_gate(c(base_ok, list(grade = "F",
                grade_basis = "essence_score(authoritative_remeasure.json)",
                essence_structural_drawdown = FALSE)), "b3")
if (identical(r$decision, "QUARANTINE"))
  ok("돌연변이 통제: 라벨 FALSE → QUARANTINE (B1 이 라벨을 실제로 읽는다)") else
  ng("★돌연변이 통제 실패 — 라벨과 무관하게 SCREEN_TIER 가 난다",
     sprintf("decision=%s", r$decision))

# B4 — 기존 두 근거가 살아 있는가 (가산이지 대체가 아니다)
r <- run_gate(c(base_ok, list(grade = "F",
                grade_basis = "essence_score(authoritative_remeasure.json)",
                screen_route_hint = "TURNOVER_REVIEW")), "b4")
if (identical(r$decision, "SCREEN_TIER") && identical(as.character(r$route), "TURNOVER_REVIEW"))
  ok("route_hint 근거 보존 — 신규 라벨이 기존 경로를 대체하지 않았다") else
  ng("★기존 route_hint 경로가 깨졌다", sprintf("decision=%s route=%s", r$decision, r$route))

r <- run_gate(c(base_ok, list(grade = "F",
                grade_basis = "essence_score(authoritative_remeasure.json)",
                hard_fail = TRUE,
                hard_fail_reason = "Structural drawdown: MDD 64.4%")), "b5")
if (identical(r$decision, "SCREEN_TIER") &&
    grepl("hard_fail_reason", as.character(r$basis), fixed = TRUE))
  ok("hard_fail 사유 근거 보존 — 구 산출물(hard_fail 살아 있는 판)의 판정 불변") else
  ng("★hard_fail 사유 경로가 깨졌다 — 기존 검사기 6개의 단언이 무의미해진다",
     sprintf("decision=%s basis=%s", r$decision, r$basis))

# ══ C. 추출기 계약 — 등급 출처를 비우지 않는다 ══════════════════════════════
cat("\n── C. lean_verify_build 등급 출처 ──────────────────────────\n")
if (!file.exists(LVB)) sk("C_lvb", "lean_verify_build.py 부재", LVB) else {
  L <- paste(readLines(LVB, warn = FALSE), collapse = "\n")
  # C1 — 권위 우선 + proxy 병기
  if (grepl("aut.get('essence_grade')", L, fixed = TRUE) &&
      grepl("v['grade_proxy']", L, fixed = TRUE))
    ok("권위(essence) 우선 · proxy 는 grade_proxy 로 병기 — 축을 섞지 않는다") else
    ng("★등급 출처가 하나로 뭉쳐 있다")
  # C2 — ★권위 부재 시 **비우지 않고 라벨**하는가 (비우면 바닥이 조용히 사라진다)
  if (grepl("grade_basis'] = 'hurdle_gate(proxy", L, fixed = TRUE))
    ok("권위 부재 시 proxy 폴백 + 라벨 — 등급 바닥이 조용히 사라지지 않는다") else
    ng("★권위 부재 시 등급을 비운다 — 게이트에서 '요구되지 않음'이 되어 바닥이 증발한다")
  # C3 — 구조 라벨 이관
  if (grepl("v['essence_structural_drawdown']", L, fixed = TRUE))
    ok("essence 구조 라벨 이관 — 게이트가 읽을 수 있다") else
    ng("★구조 라벨이 게이트까지 도달하지 않는다")
}

emit()
