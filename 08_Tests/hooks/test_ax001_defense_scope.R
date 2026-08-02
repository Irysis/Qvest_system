#==============================================================================
# test_ax001_defense_scope.R — AX-001(방어 조건부 평가) 차단 실효 + scope 판정 검사기
#
# 계약: qepm/memory/axioms/active/AX-001.json (IMMUTABLE, enforcement_mode=block)
#       .claude/rules/axioms.md "Hook 강제" 절 / measurement-graduation §1
#
# 배경 (2026-08-02 실측, WT-D20260802_004 alpha 라운드에서 적발):
#   AS_LowVol_BlitzVanVliet2007 등 방어 계열이 조건부 평가 없이 전기간 SR/CAGR/MDD로
#   기각됐는데 AX-001 훅이 발화하지 않았다. 전수 측정 결과 발화 가능 건수 = 0/559 (0.0%).
#   원인은 "존재 검사로 정체성 검사 대체" 2중:
#     (1) regex "defense|defence" 를 **항상 존재하는 필드명**(statistical_defense /
#         defense_metrics)이 559/559 충족 → 판별력 0. 방어 전략인지와 무관하게 매치.
#     (2) require 의 "stress" 를 **항상 존재하는 채점항목명**(score_breakdown.stress /
#         stress_severity)이 559/559 충족 → 영구 면제.
#   즉 규칙은 살아 있었으나 입력이 조건을 만족시킬 수 없어 구조적으로 죽어 있었다.
#
# ★이 검사기는 "정상 파일에서 경고가 안 뜬다"를 재지 않는다. 그건 검사 사망과 구별이 안 된다.
#   위반을 **일부러 만들어 넣고**(위반 주입) 훅이 실제로 decision:block 을 발행하는지 본다.
#   동시에 과차단(정상 파일 block)도 재서 판별력이 양방향임을 확인한다.
#   마지막으로 **돌연변이 축**: 구판 패턴을 되살리면 주입 케이스를 놓치는지 확인한다
#   (놓쳐야 정상 — 검사기가 실제로 수리분을 재고 있다는 증거).
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }

AX_PATH   <- file.path(PROJ, "qepm/memory/axioms/active/AX-001.json")
HOOK_PATH <- file.path(PROJ, "02_Infrastructure/hooks/axiom_enforcement_hook.sh")
GATE_PATH <- file.path(PROJ, "02_Infrastructure/hurdle_gate.R")

TMPD <- file.path(tempdir(), "ax001_scope_test")
dir.create(TMPD, recursive = TRUE, showWarnings = FALSE)

# ── 훅 실행 헬퍼 ────────────────────────────────────────────────────────────
# r-portability 금칙 ⑤: system2 문자열에 쉘 리다이렉션/&& 주입 금지 (셸 미경유 → 리터럴 argv).
# stdin 은 파일로만 전달하고, stderr 은 system2(stderr=) 인자로 분리한다.
run_hook <- function(file_path, content) {
  payload <- file.path(TMPD, "payload.json")
  write(toJSON(list(tool_name = jsonlite::unbox("Write"),
                    tool_input = list(file_path = jsonlite::unbox(file_path),
                                      content   = jsonlite::unbox(content))),
               auto_unbox = FALSE), payload)
  out <- suppressWarnings(system2("bash", c(shQuote(HOOK_PATH)),
                                  stdin = payload, stdout = TRUE, stderr = FALSE))
  paste(out, collapse = "")
}
blocked <- function(resp) grepl('"decision"\\s*:\\s*"block"', resp)

# ── 픽스처 ──────────────────────────────────────────────────────────────────
HR <- "/x/output/hurdle_result.json"

# 현행 gate 가 내는 형태를 모사 (defense_metrics/statistical_defense/stress 채점항목 상시 존재)
mk_hurdle <- function(detected_family, grade, hard_fail, ax001_status = NULL,
                      role = "none") {
  v <- list(
    strategy = "FixtureStrategy",
    grade = grade, hard_fail = hard_fail,
    fail_reasons = "MDD 54.9% > 45%",
    role = role,
    novelty_detail = list(detected_family = detected_family),
    # ↓ 구판 regex/require 를 항상 충족시키던 상시 필드들 — 픽스처에 반드시 포함해야
    #   "구판이 왜 못 잡았는지"를 재현하고, 신판이 그럼에도 잡는지 볼 수 있다.
    score_breakdown = list(stress = list(score = 6.7, max = 10),
                           stress_severity = list(score = 0, max = 0)),
    statistical_defense = list(dsr = "NA", dsr_significant = FALSE),
    defense_metrics = list(stress_8_outperf_rate = 0.375, stress_8_n_outperf = 3,
                           stress_8_n_total = 8),
    metrics = list(Sharpe = 0.294, MDD = 54.87, CAGR = 4.59)
  )
  if (!is.null(ax001_status)) {
    v$ax001 <- list(in_scope = TRUE, basis = "strategy_name",
                    conditional_axes_n = 8L, ax001_status = ax001_status)
  }
  toJSON(v, auto_unbox = TRUE, pretty = TRUE)
}

cat("=== [1] 위반 주입 — 훅이 실제로 차단을 발행하는가 (차단 실효) ===\n")

# 1a. 방어 계열 + grade F + 조건부 평가 부재 → block
r <- run_hook(HR, mk_hurdle("defense", "F", TRUE))
if (blocked(r)) { ok("주입 1a", "detected_family=defense + grade F + 조건부 부재 → block") } else { bad("주입 1a", paste0("차단 미발행. resp=", substr(r, 1, 160))) }

# 1b. ★핵심 회귀: grade C + hard_fail (실측 15건 중 7건이 이 형태로 F-only 조건을 빠져나갔다)
r <- run_hook(HR, mk_hurdle("defense", "C", TRUE))
if (blocked(r)) { ok("주입 1b", "grade C + hard_fail → block (구판 F-only 조건은 통과시켰음)") } else { bad("주입 1b", paste0("grade C 기각을 놓침. resp=", substr(r, 1, 160))) }

# 1c. ★핵심 회귀: 상시 필드(stress/statistical_defense)가 있어도 면제되지 않아야 한다
#     구판은 이 픽스처에서 require 의 "stress" 가 매치돼 영구 면제였다.
r <- run_hook(HR, mk_hurdle("defense", "F", FALSE))
if (blocked(r)) { ok("주입 1c", "score_breakdown.stress 상시 존재에도 면제되지 않음") } else { bad("주입 1c", paste0("상시 채점항목명이 면제를 만들어 냄(구판 결함 잔존). resp=", substr(r, 1, 160))) }

# 1d. 생산자 자기판정이 위반을 선언한 경우
r <- run_hook(HR, mk_hurdle("other", "F", TRUE, ax001_status = "UNCONDITIONAL_REJECTION"))
if (blocked(r)) { ok("주입 1d", "ax001_status=UNCONDITIONAL_REJECTION → block") } else { bad("주입 1d", paste0("생산자 위반선언을 훅이 무시. resp=", substr(r, 1, 160))) }

# 1e. role 값으로 선언된 방어 (judge/s7 계열 형태)
r <- run_hook("/x/s7_verdict.json",
              toJSON(list(role_label = "defense", grade = "F", crisis = "n/a"),
                     auto_unbox = TRUE))
if (blocked(r)) { ok("주입 1e", "s7_ 파일 role_label=defense + grade F → block") } else { bad("주입 1e", paste0("s7 경로 미차단. resp=", substr(r, 1, 160))) }

cat("\n=== [2] 과차단 검사 — 정상 파일을 막지 않는가 (판별력 양방향) ===\n")

# 2a. 비방어 전략의 기각 → 통과
r <- run_hook(HR, mk_hurdle("momentum", "F", TRUE, ax001_status = "NOT_IN_SCOPE", role = "core"))
if (!blocked(r)) { ok("과차단 2a", "momentum 기각은 AX-001 대상 아님 → 통과") } else { bad("과차단 2a", "비방어 전략을 차단함(과차단)") }

# 2b. 방어 계열이지만 조건부 평가를 실제로 수행 → 통과 (문턱 완화 아님, 평가근거 규율)
r <- run_hook(HR, mk_hurdle("defense", "F", TRUE, ax001_status = "CONDITIONAL_EVALUATED"))
if (!blocked(r)) { ok("과차단 2b", "조건부 평가 수행분은 기각이어도 통과") } else { bad("과차단 2b", "조건부 평가를 마친 방어 전략을 차단함(과차단)") }

# 2c. 방어 계열 + 합격 등급 → 통과
r <- run_hook(HR, mk_hurdle("defense", "A_DEF", FALSE, ax001_status = "CONDITIONAL_EVALUATED"))
if (!blocked(r)) { ok("과차단 2c", "A_DEF 는 기각이 아니므로 통과") } else { bad("과차단 2c", "합격 등급을 차단함(과차단)") }

# 2d. 대상 파일명이 아니면 통과
r <- run_hook("/x/notes.md", mk_hurdle("defense", "F", TRUE))
if (!blocked(r)) { ok("과차단 2d", "applies_to_files 밖 파일은 통과") } else { bad("과차단 2d", "대상 외 파일을 차단함") }

cat("\n=== [3] 구판 패턴 사망 재현 — 실제 산출물에서 발화 가능했는가 ===\n")
# 구판 의미론을 그대로 재현해, 현행 저장된 hurdle_result 에서 발화 가능 건수를 센다.
# 0 이어야 "구판이 죽어 있었다"는 진단이 참이고, 이 검사기가 수리 전후를 구별한다는 증거가 된다.
hrs <- list.files(file.path(PROJ, "stage_artifacts"), pattern = "^hurdle_result\\.json$",
                  recursive = TRUE, full.names = TRUE)
if (length(hrs) == 0L) {
  bad("구판 재현", "stage_artifacts 에서 hurdle_result.json 을 못 찾음 — 검사 자체가 공회전")
} else {
  n_old_fire <- 0L
  for (p in hrs) {
    txt <- tryCatch(paste(readLines(p, warn = FALSE), collapse = "\n"), error = function(e) "")
    if (!nzchar(txt)) next
    old_r1 <- grepl("defense|defence", txt, ignore.case = TRUE)
    old_r2 <- grepl('"grade".*"F"', txt, ignore.case = TRUE)
    old_rq <- grepl("crisis|stress|conditional|bad_normal|regime", txt, ignore.case = TRUE)
    if (old_r1 && old_r2 && !old_rq) n_old_fire <- n_old_fire + 1L
  }
  if (n_old_fire == 0L) {
    ok("구판 재현", sprintf("구판 패턴 발화 가능 = 0/%d (구조적 사망 확인)", length(hrs)))
  } else {
    bad("구판 재현", sprintf("구판이 %d/%d 에서 발화 가능 — 진단 전제가 어긋남", n_old_fire, length(hrs)))
  }
}

cat("\n=== [4] hurdle_gate scope 판정 — 어휘가 방어 계열을 실제로 잡는가 ===\n")
gate_lines <- readLines(GATE_PATH, warn = FALSE)
gate_src   <- paste(gate_lines, collapse = "\n")

# 정의를 실제로 평가해서 쓴다 — 검사기가 패턴을 재작성해 들고 있으면 사본이 갈라져
#   "검사기만 통과하고 본체는 다른" 상태가 된다. 괄호가 패턴 안에도 나오므로
#   정규식으로 끝을 찾지 않고, 파싱될 때까지 줄을 늘려가며 균형을 잡는다.
i0 <- grep("\\.AX001_DEFENSE_VOCAB <- paste0\\(", gate_lines)
VOC <- NULL
if (length(i0) > 0L) {
  for (j in seq(i0[1], min(i0[1] + 15L, length(gate_lines)))) {
    VOC <- tryCatch({
      env <- new.env()
      eval(parse(text = paste(gate_lines[i0[1]:j], collapse = "\n")), envir = env)
      get(".AX001_DEFENSE_VOCAB", envir = env)
    }, error = function(e) NULL)
    if (!is.null(VOC)) break
  }
}
if (is.null(VOC)) {
  bad("어휘 상수", "hurdle_gate.R 에서 .AX001_DEFENSE_VOCAB 정의를 평가하지 못함")
} else {
  should_hit <- c("AS_LowVol_BlitzVanVliet2007", "LowVol", "DownsideBeta_ACX2006",
                  "STR_1662_defense_D25_Q07", "MinVol_KR", "BAB_top25",
                  "low_beta_sleeve", "STR_1499_brk0", "crash_protection_v2")
  should_miss <- c("STR_1715_AR_on_M4_R05", "Momentum_12_1", "QValue_Composite",
                   "FLOW_foreign_net", "Consensus_Revision", "IndMom_M07")
  miss <- should_hit[!grepl(VOC, tolower(should_hit), perl = TRUE)]
  over <- should_miss[grepl(VOC, tolower(should_miss), perl = TRUE)]
  if (length(miss) == 0L) ok("어휘 포착", sprintf("방어 계열 %d/%d 전량 포착", length(should_hit), length(should_hit)))
  else bad("어휘 포착", paste("미포착:", paste(miss, collapse = ", ")))
  if (length(over) == 0L) ok("어휘 과포착", sprintf("비방어 %d건 오포착 0", length(should_miss)))
  else bad("어휘 과포착", paste("오포착:", paste(over, collapse = ", ")))
}

cat("\n=== [5] 순환 차단 확인 — scope 판정이 점수에서 파생되지 않는가 ===\n")
# .effective_role 이 axis 점수보다 먼저 선언적 scope 를 보는지 소스 수준으로 확인.
# (수치 실행은 sim_result 전체가 필요해 배터리 비용이 과다 — 순서 계약만 고정한다)
i_er <- grep("\\.effective_role <- if \\(", gate_lines)
if (length(i_er) == 0L) {
  bad("순환 차단", ".effective_role 정의를 못 찾음")
} else {
  blk <- paste(gate_lines[i_er[1]:min(i_er[1] + 12L, length(gate_lines))], collapse = "\n")
  pos_scope <- regexpr("ax001_in_scope", blk, fixed = TRUE)
  pos_axis  <- regexpr("axis_risk", blk, fixed = TRUE)
  if (pos_scope > 0 && pos_axis > 0 && pos_scope < pos_axis) {
    ok("순환 차단", "선언적 scope 분기가 axis 추론보다 앞섬")
  } else if (pos_scope < 0) {
    bad("순환 차단", ".effective_role 이 여전히 axis 점수만 본다 — AX-001 적용이 채점 결과에 종속")
  } else {
    bad("순환 차단", "axis 분기가 scope 분기보다 앞섬 — 순환 잔존")
  }
}

# defense_metrics 무조건 기록 (조건부 증거를 계산해 놓고 버리지 않는가)
if (grepl("defense_metrics <- list\\(", gate_src)) {
  ok("증거 보존", "defense_metrics 를 role 조건 없이 기록")
} else {
  bad("증거 보존", "defense_metrics 가 여전히 role 조건부 — 조건부 증거가 버려질 수 있음")
}

cat("\n=== [6] 동적 경로 단독 검증 — AX-001.json 의미론 자체 ===\n")
# 왜 따로 재는가: axiom_enforcement_hook.sh 는 동적(AX-001.json) → legacy(.sh 하드코딩)
#   2단이다. 둘 중 하나만 성해도 훅 응답은 block 이라, [1] 만으로는 JSON 쪽 회귀를
#   legacy 가 가려 버린다(돌연변이 M1 실측: JSON 을 구판으로 되돌려도 [1] 전량 통과).
#   그래서 여기서는 JSON 의 regex/require 를 훅의 python 과 동일 의미론으로 직접 적용한다.
#   훅과 동일하게 content 1500자 preview 를 적용 — ax001 블록이 preview 밖으로 밀리면
#   면제 근거가 판정에 도달하지 못해 과차단이 나므로, 배치까지 함께 고정된다.
axj <- tryCatch(fromJSON(AX_PATH, simplifyVector = FALSE), error = function(e) NULL)
eh  <- if (!is.null(axj)) axj$enforcement_hook else NULL
if (is.null(eh) || !length(eh$regex)) {
  bad("동적 경로", "AX-001.json enforcement_hook.regex 부재")
} else {
  `%||%` <- function(a, b) if (is.null(a)) b else a
  dyn_fires <- function(file_path, content) {
    content <- substr(content, 1, 1500)   # 훅의 preview 폭과 동일
    applies <- unlist(eh$applies_to_files %||% list(".*"))
    if (!any(vapply(applies, function(a) grepl(a, file_path, perl = TRUE), logical(1)))) return(FALSE)
    pats <- unlist(eh$regex)
    if (!all(vapply(pats, function(p) grepl(p, content, perl = TRUE, ignore.case = TRUE), logical(1)))) return(FALSE)
    reqs <- unlist(eh$require %||% list())
    if (length(reqs) &&
        any(vapply(reqs, function(q) grepl(q, content, perl = TRUE, ignore.case = TRUE), logical(1)))) return(FALSE)
    TRUE
  }

  chk <- function(nm, want, fp, ct) {
    got <- tryCatch(dyn_fires(fp, ct), error = function(e) NA)
    if (identical(got, want)) ok(nm) else bad(nm, sprintf("기대=%s 실제=%s", want, got))
  }
  chk("동적 1a defense+F 발화",      TRUE,  HR, mk_hurdle("defense", "F", TRUE))
  chk("동적 1b defense+C+hardfail",  TRUE,  HR, mk_hurdle("defense", "C", TRUE))
  chk("동적 1c 상시 stress 비면제",  TRUE,  HR, mk_hurdle("defense", "F", FALSE))
  chk("동적 2a momentum 미발화",     FALSE, HR, mk_hurdle("momentum", "F", TRUE, ax001_status = "NOT_IN_SCOPE", role = "core"))
  chk("동적 2b 조건부평가분 면제",   FALSE, HR, mk_hurdle("defense", "F", TRUE, ax001_status = "CONDITIONAL_EVALUATED"))
  chk("동적 2d 대상외 파일 미발화",  FALSE, "/x/notes.md", mk_hurdle("defense", "F", TRUE))
}

cat(sprintf("\n=== AX-001 defense scope: %d PASS / %d FAIL ===\n", PASS, FAIL))
# run_all_hooks.sh 가 마지막 줄에서 요약을 파싱한다 — 미발행 시 UNREPORTED 로 잡힌다
cat(sprintf('{"test":"ax001_defense_scope","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
