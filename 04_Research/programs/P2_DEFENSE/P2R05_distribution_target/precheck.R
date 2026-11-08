## P2R05 측정 · 워밍 직전 대조(P2R04 precheck.R 승계) — 사양 16 · 운영 경로 md5(DT 엔진 파일 포함 · 팩터 DB 커넥터 · 등급 계약 v3.2) · 팩터 레지스트리 엔트리 ·
##   비중 카탈로그 엔트리(E3 lean:entropy) · 패키지 · R 판 · 평가 경로 md5 · 행동 카드 설정 사본 md5 가 사전등록 값과 같고, 등록부의 이 라운드 사전등록 md5 = 파일 md5 여야 한다.
##   + (i)   템플릿 차분 대조 — DT_2002_06975/template_diff_check.R rc 0
##   + (ii)  생성 엔진 7개 md5 = engines_manifest.json = 사전등록 핀(engines 절)
##   + (iii) DT 엔진 정적 PIT(lookahead_detector · clean = TRUE 만) · CODE_VERSION · 규칙 상수 · 양성 대조 리허설 요약 md5 = 핀 · 파이썬 판 = 핀(engine_checks.R — register.R 과 같은 정의)
##           + DT 시험 증거(tests/_out 결과 JSON 8 + README) md5 = 사전등록 tests_dt 핀 · 통과(격리 점검 v1 권고 9 · engine_checks.R test_evidence_check)
##   + (iv)  러너 축 — rf_cell_worker.R 가 칸 사양 대신 06_Registry/reinforce_program.json fixed_axes 에서 읽는 n_max · commission_bps = 사양 fixed_axes 값(키 값 대조 · P2R04 방식)
##   + (v)   --gpu-gate — nvidia-smi 표의 다른 연산(Type C) 프로세스 0 까지 대기 · memory.used 기록. 미달 = 대기(폴링) · 프로세스를 끄지 않는다 · 마감 = rc 7
##   + (vi)  등록 → 커밋 → 워밍 → 측정 — 사전등록 두 사본(stage_artifacts 정본 · 라운드 prereg.json)이 git 추적 · 작업 트리 변경 없음 · 두 md5 같음
##   핀 대조 = evaluate.R 의 핀 대조 함수(평가 시작부와 같은 함수 — EVAL_PIN_FN 후보 중 처음 정의된 것) ∪ 이 파일의 같은 정의(.pc_pin_local) — 어느 쪽이든 불일치면 rc 1.
##   데이터 지문(fingerprint.sh — equality · record · dnn_input)을 함께 기록한다. 성과 수치 없음. 쓰기 = results/precheck.json(본 대조) · warm/precheck_warm.json(--warm) · --gpu-out 경로뿐.
## 실행: Rscript precheck.R                    본 대조(측정 직전 · measure.sh) → results/precheck.json(evaluate.R 이 ok 를 요구한다)
##       Rscript precheck.R --warm             워밍 직전 대조(warm_cache.sh ①) — 본 대조와 같은 항목 · results/ 에 쓰지 않는다 → warm/precheck_warm.json
##       Rscript precheck.R --warm-check       워밍 센티널 단정(measure.sh · 측정 직전) — rc 0 = 유효 · 신선 / 10 = 유효하나 워밍 뒤 데이터 판본이 바뀜 / 1 = 없음 · 무효
##       Rscript precheck.R --gpu-gate [--gpu-once] [--gpu-deadline=YYYY-mm-ddTHH:MM] [--gpu-poll=초] [--gpu-out=<json>]
##                                             GPU 게이트(warm_cache.sh ③) — rc 0 = 다른 Type C 0 / 7 = 바쁨(--gpu-once) · 마감 / 8 = nvidia-smi 조회 실패(확인 불가 = 통과 아님)
##       Rscript precheck.R --dry              건식 — 사전등록 없이 칸 계획 · 사양 · 운영 경로 · 카탈로그 · 패키지 · 러너 축 · DT 엔진 · 평가 경로 · 지문 · GPU(1회 · 판정 밖) · 레인 상태:
##                                             register.R 의 P2R05_CONST 대입문 하나만 골라 평가(사양 검사 = register.R 과 같은 함수). 쓰지 않는다 · 측정 허가가 아니다
##                                             (rc 0 = 사양 · 운영 경로 · 카탈로그 · 패키지 · 러너 축 통과 ∧ 있는 DT 엔진 검사 · DT 시험 증거 통과 · 다른 에이전트 산출 미비는 '대기'로 목록만)
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
if (!file.exists(file.path(ROOT, "02_Infrastructure/hooks/qvest_hook_router.py"))) stop("[precheck] 프로젝트 루트 표지 없음: ", ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
## bare "bash" 금지(금칙 ⑦) — 메인 PC WSL bash 가로챔 수리(2026-11-08 환경 최신화 재고정에 포함 · 지문 정의 · 입력 불변)
if (!exists("qv_bash", mode = "function")) source(file.path(ROOT, "02_Infrastructure/ops/qv_bash.R"))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PROGRAM <- "P2_DEFENSE"; ROUND <- "P2R05_distribution_target"
RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R05_distribution_target")
PR <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R05_distribution_target/prereg.json")
PR_COPY <- file.path(RD, "prereg.json")
WARM_SENT <- file.path(ROOT, "04_Research/programs/_lib/night_state/p2r05_warm.done")
ARGS <- commandArgs(trailingOnly = TRUE)
MODE <- if ("--dry" %in% ARGS) "dry" else if ("--warm-check" %in% ARGS) "warm_check" else if ("--warm" %in% ARGS) "warm" else if ("--gpu-gate" %in% ARGS) "gpu_gate" else "main"
argv <- function(k, d = NULL) { v <- sub(paste0("^--", k, "="), "", grep(paste0("^--", k, "="), ARGS, value = TRUE, perl = TRUE)); if (length(v)) v[1] else d }
EVAL_PIN_FN <- c("p2r05_pin_mismatches", "p2_pin_mismatches")                  # evaluate.R 쪽 이름 후보(앞이 우선 · P2R03 · P2R04 = p2_pin_mismatches)
EVAL_FP_FN <- c("p2r05_fingerprint", "p2_fingerprint")
## 러너 축 — rf_cell_worker.R(PROG <- reinforce_program.json · AX <- PROG$fixed_axes · n_long = n_max = AX$n_max · commission_paper = AX$commission_bps / 10000).
##   start_date · universe 는 대조하지 않는다 — 사양에 측정 축 표식(fixed_axes.measurement_axis)이 있으면 워커가 epoch 에서 읽는다(사양 검사가 표식을 단정).
RUNNER_CFG <- "06_Registry/reinforce_program.json"
RUNNER_KEYS <- c("n_max", "commission_bps")
LANE_CFG <- "06_Registry/reinforce_auto_config.json"                           # 충실구현 레인 스위치(replication_lane.enabled) — 읽기만(정지 · 재개는 도훈 확인 사항)
source(file.path(RD, "engine_checks.R"))                                        # P2R05_DTC(register.R · warm_engine.R 과 같은 정의)
DTC <- P2R05_DTC
.pc_md5 <- function(f) if (file.exists(f)) unname(as.character(tools::md5sum(f))) else NA_character_
.pc_cj <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
.pc_rel <- function(p) sub(paste0("^", ROOT, "/"), "", gsub("\\\\", "/", p))
.pc_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
## 핀 대조(이 파일의 정의) — P2R04 precheck.R::.pc_pin_local 과 같은 항목 · 같은 비교. 반환 = 불일치 설명(없으면 길이 0)
.pc_pin_local <- function(pre, root) {
  md5r <- function(f) .pc_md5(file.path(root, f))
  bad <- character(0)
  if (!length(pre$cells)) bad <- c(bad, "사양 칸 목록이 비었다")
  for (c0 in pre$cells) if (!identical(md5r(c0$path), c0$md5)) bad <- c(bad, paste("사양 md5:", c0$code))
  op <- pre$operational_pins
  if (is.null(op)) return(c(bad, "운영 핀 없음"))
  for (f in op$files) if (!identical(md5r(f$path), f$md5)) bad <- c(bad, paste("운영 경로 md5:", f$path))
  wc <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries, error = function(e) list())
  for (pin in op$catalog_entries) {
    ent <- Filter(function(z) identical(z$catalog_id, pin$catalog_id), wc)
    if (!length(ent) || !identical(ent[[1]]$status, pin$status) || !identical(.pc_cj(ent[[1]]$resolver), .pc_cj(pin$resolver)))
      bad <- c(bad, paste("비중 카탈로그 엔트리:", pin$catalog_id))
  }
  if (length(op$overlay_arms)) {
    oc <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE)$arms, error = function(e) list())
    for (pin in op$overlay_arms) { ent <- Filter(function(z) identical(z$id, pin$id), oc)
      if (!length(ent) || !identical(.pc_cj(ent[[1]]), .pc_cj(pin$entry))) bad <- c(bad, paste("오버레이 카탈로그 arm:", pin$id)) }
  }
  FRC <- list()
  for (pin in op$factor_registry_entries) {
    fp <- pin$path %||% ".cache/factor_db/factor_registry.json"
    if (is.null(FRC[[fp]])) FRC[[fp]] <- tryCatch(jsonlite::fromJSON(file.path(root, fp), simplifyVector = FALSE), error = function(e) list())
    ent <- FRC[[fp]][[pin$id %||% ""]]
    if (is.null(ent) || !identical(.pc_cj(ent), .pc_cj(pin$entry))) bad <- c(bad, paste("팩터 레지스트리 엔트리:", pin$id %||% "?"))
  }
  for (pk in names(op$packages)) {
    v <- tryCatch(as.character(utils::packageVersion(pk)), error = function(e) NA_character_)
    if (!identical(v, op$packages[[pk]])) bad <- c(bad, paste(pk, "판"))
  }
  if (!identical(R.version.string, op$r_version)) bad <- c(bad, "R 판")
  for (f in pre$evaluation$files %||% list()) if (!identical(md5r(f$path), f$md5)) bad <- c(bad, paste("평가 경로 md5:", f$path))
  if (!is.null(pre$behavior_card_cfg) && !identical(md5r(pre$behavior_card_cfg$path), pre$behavior_card_cfg$md5)) bad <- c(bad, "행동 카드 설정 사본 md5")
  bad
}
## 러너 축 대조 — 워커가 읽는 키 값 = 사양 fixed_axes 값(칸마다 같아야 한다)
.pc_runner_axes <- function(spec_paths) {
  ax <- tryCatch(fromJSON(file.path(ROOT, RUNNER_CFG), simplifyVector = FALSE)$fixed_axes, error = function(e) NULL)
  sp <- lapply(spec_paths, function(p) tryCatch(fromJSON(file.path(ROOT, p), simplifyVector = FALSE)$fixed_axes, error = function(e) NULL))
  bad <- character(0); runner <- list(); spec <- list()
  if (is.null(ax)) bad <- c(bad, sprintf("러너 축 판독 실패: %s", RUNNER_CFG))
  if (!length(spec_paths) || any(vapply(sp, is.null, logical(1)))) bad <- c(bad, "사양 fixed_axes 판독 실패")
  for (k in RUNNER_KEYS) {
    sv <- unique(vapply(sp, function(a) { x <- suppressWarnings(as.numeric(a[[k]] %||% NA)); if (length(x) == 1L) x else NA_real_ }, numeric(1)))
    rv <- suppressWarnings(as.numeric(ax[[k]] %||% NA)); if (length(rv) != 1L) rv <- NA_real_
    spec[[k]] <- sv; runner[[k]] <- rv
    if (length(sv) != 1L || is.na(sv)) bad <- c(bad, sprintf("사양 fixed_axes.%s 가 칸마다 다르거나 없다(%s)", k, paste(format(sv), collapse = "/")))
    else if (is.na(rv) || !isTRUE(all.equal(rv, sv))) bad <- c(bad, sprintf("러너 축 %s fixed_axes.%s = %s ≠ 사양 %s — 워커가 다른 값으로 잰다", RUNNER_CFG, k, format(rv), format(sv)))
  }
  list(ok = !length(bad), mismatches = bad, file = RUNNER_CFG, keys = RUNNER_KEYS, runner = runner, spec = spec, n_specs = length(spec_paths),
       source = "rf_cell_worker.R — AX <- reinforce_program.json$fixed_axes · portfolio_spec n_long = n_max = AX$n_max · commission_paper = AX$commission_bps / 10000")
}
.pc_axes_txt <- function(r) paste(vapply(RUNNER_KEYS, function(k) sprintf("%s 러너 %s · 사양 %s", k, format(r$runner[[k]] %||% NA), paste(format(r$spec[[k]] %||% NA), collapse = "/")), ""), collapse = " · ")
## 등록 → 커밋 → 측정 — 사전등록 두 사본이 git 추적 · 작업 트리 변경 없음 · 두 md5 같음(system2 명령 문자열에 리다이렉션 없음 · r-portability ⑤)
.pc_committed <- function() {
  paths <- c(.pc_rel(PR), .pc_rel(PR_COPY)); bad <- character(0)
  if (!file.exists(PR_COPY)) bad <- c(bad, paste("라운드 디렉터리 사본 없음:", .pc_rel(PR_COPY)))
  else if (!identical(.pc_md5(PR_COPY), .pc_md5(PR))) bad <- c(bad, "사전등록 두 사본 md5 불일치(stage_artifacts 정본 ≠ 라운드 prereg.json)")
  for (p in paths) {
    o <- suppressWarnings(system2("git", c("-C", ROOT, "ls-files", "--error-unmatch", "--", p), stdout = TRUE, stderr = FALSE))
    st <- attr(o, "status")
    if (!is.null(st) && !identical(as.integer(st), 0L)) bad <- c(bad, paste("git 미추적(등록 뒤 커밋 안 됨):", p))
  }
  s <- suppressWarnings(system2("git", c("-C", ROOT, "status", "--porcelain", "--", paths), stdout = TRUE, stderr = FALSE))
  st <- attr(s, "status")
  if (!is.null(st) && !identical(as.integer(st), 0L)) bad <- c(bad, sprintf("git status 실패(rc %s) — 커밋 상태 확인 불가", st))
  else { s <- s[nzchar(s)]; if (length(s)) bad <- c(bad, paste("사전등록 작업 트리 변경(미커밋 · 커밋 뒤 수정):", paste(trimws(s), collapse = " | "))) }
  list(ok = !length(bad), mismatches = bad, paths = paths)
}
## 데이터 지문 — fingerprint.sh(measure.sh · warm_cache.sh 와 같은 정의) · 줄을 '|' 로 잇는다(P2R04 p2_fingerprint 와 같은 형식)
.pc_fp_local <- function(mode) {
  o <- tryCatch(suppressWarnings(system2(qv_bash(), c(shQuote(file.path(RD, "fingerprint.sh")), mode), stdout = TRUE, stderr = TRUE)),
                error = function(e) paste("error:", conditionMessage(e)))
  paste(o, collapse = "|")
}
.pc_git_head <- function() {
  h <- suppressWarnings(system2("git", c("-C", ROOT, "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE))
  st <- attr(h, "status"); if ((!is.null(st) && !identical(as.integer(st), 0L)) || !length(h)) NA_character_ else h[1]
}
.pc_lastd <- function(f) tryCatch(format(max(as.Date(arrow::read_parquet(file.path(ROOT, ".cache", f), col_select = "Date")$Date))), error = function(e) paste("error:", conditionMessage(e)))
## GPU 상태 — nvidia-smi 표의 프로세스 줄에서 Type 이 정확히 'C'(연산 전용)인 것만 센다. Windows WDDM 에서는 화면 앱이 'C+G' 로 줄줄이 보이므로
##   --query-compute-apps(C+G 포함)를 쓰면 게이트가 영원히 닫힌다(10-18 실측 — C+G 20여 개 · C 1개 = 레인 THGNN python.exe). 조회 실패 = 확인 불가(통과 아님)
.pc_smi <- function() {
  s <- Sys.which("nvidia-smi"); s <- if (nzchar(s)) s else "C:/Windows/System32/nvidia-smi.exe"
  if (!file.exists(s)) NA_character_ else s
}
.pc_gpu_state <- function() {
  smi <- .pc_smi(); at <- .pc_now()
  if (is.na(smi)) return(list(ok = FALSE, why = "nvidia-smi 없음", at = at))
  q <- suppressWarnings(system2(smi, c("--query-gpu=name,memory.used,memory.total", "--format=csv,noheader,nounits"), stdout = TRUE, stderr = FALSE))
  st <- attr(q, "status"); st <- if (is.null(st)) 0L else as.integer(st)
  if (st != 0L || !length(q)) return(list(ok = FALSE, why = sprintf("nvidia-smi 메모리 조회 실패(rc %d)", st), at = at))
  mm <- trimws(strsplit(q[1], ",", fixed = TRUE)[[1]])
  tb <- suppressWarnings(system2(smi, character(0), stdout = TRUE, stderr = FALSE))
  st2 <- attr(tb, "status"); st2 <- if (is.null(st2)) 0L else as.integer(st2)
  if (st2 != 0L || !length(tb)) return(list(ok = FALSE, why = sprintf("nvidia-smi 프로세스 표 조회 실패(rc %d)", st2), at = at))
  rx <- "^\\|\\s+\\d+\\s+\\S+\\s+\\S+\\s+(\\d+)\\s+(C|G|C\\+G)\\s+(.*?)\\s+(\\S+)\\s+\\|\\s*$"
  rows <- grep(rx, tb, value = TRUE, perl = TRUE)
  typ <- sub(rx, "\\2", rows, perl = TRUE); pid <- sub(rx, "\\1", rows, perl = TRUE); nm <- sub(rx, "\\3", rows, perl = TRUE)
  C <- lapply(which(typ == "C"), function(i) list(pid = pid[i], name = nm[i]))
  list(ok = TRUE, at = at, gpu = mm[1], memory_used_mib = suppressWarnings(as.numeric(mm[2])), memory_total_mib = suppressWarnings(as.numeric(mm[3])),
       n_process_rows = length(rows), n_type_c = length(C), type_c = C, types = as.list(table(typ)))
}
.pc_gpu_txt <- function(g) if (!isTRUE(g$ok)) paste("조회 실패 —", g$why) else
  sprintf("%s · memory.used %s / %s MiB · Type C %d%s · 프로세스 줄 %d", g$gpu, format(g$memory_used_mib), format(g$memory_total_mib), g$n_type_c,
          if (g$n_type_c) paste0("(", paste(vapply(g$type_c, function(z) sprintf("pid %s %s", z$pid, z$name), ""), collapse = " · "), ")") else "", g$n_process_rows)
.pc_lane <- function() tryCatch({ r <- fromJSON(file.path(ROOT, LANE_CFG), simplifyVector = FALSE)$replication_lane
  list(enabled = isTRUE(r$enabled), paused_at = r$paused_at %||% NA_character_, resumed_at = r$resumed_at %||% NA_character_) },
  error = function(e) list(enabled = NA, why = conditionMessage(e)))
.pc_registry <- function() tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/programs/program_registry.R")))
  rr <- Filter(function(r) identical(r$round_id, ROUND), pr_get(pr_load(ROOT), PROGRAM)$rounds %||% list())
  if (!length(rr)) "등록부에 이 라운드 기록 없음(register.R --register 미완료)"
  else if (!identical(rr[[1]]$prereg_md5, .pc_md5(PR))) "등록부 기록 사전등록 md5 ≠ 파일(R2)"
  else character(0)
}, error = function(e) paste("등록부 판독 실패:", conditionMessage(e)))
.pc_py_pin <- function(pre, pyv) {
  if (is.null(pre$engines$python)) return("사전등록에 파이썬 판 핀 없음")
  if (!isTRUE(pyv$ok)) return(paste("파이썬 판 조회 실패:", pyv$why %||% "?"))
  d <- DTC$PY_KEYS[!vapply(DTC$PY_KEYS, function(k) identical(as.character(pyv[[k]] %||% NA), as.character(pre$engines$python[[k]] %||% NA)), logical(1))]
  if (length(d)) paste("파이썬 판 ≠ 사전등록 핀:", paste(sprintf("%s %s → %s", d, vapply(d, function(k) as.character(pre$engines$python[[k]] %||% "?"), ""),
                                                          vapply(d, function(k) as.character(pyv[[k]] %||% "?"), "")), collapse = " · ")) else character(0)
}
## 본 대조 · 워밍 대조가 같이 쓰는 전 항목 — 반환 = list(bad, 기록 …)
.pc_full <- function(pre) {
  EF <- file.path(RD, "evaluate.R")
  EVE <- new.env(parent = globalenv())                                          # evaluate.R 은 격리 환경에 적재(이 파일의 변수를 덮지 않게 · 본 실행 블록은 sys.nframe 가드)
  ev_err <- if (!file.exists(EF)) "evaluate.R 없음" else tryCatch({ source(EF, local = EVE); NULL }, error = function(e) paste("evaluate.R 적재 실패:", conditionMessage(e)))
  pick <- function(cands) { h <- cands[vapply(cands, function(n) exists(n, envir = EVE, mode = "function", inherits = FALSE), logical(1))]; if (length(h)) h[1] else NA_character_ }
  pin_fn <- if (is.null(ev_err)) pick(EVAL_PIN_FN) else NA_character_
  fp_fn <- if (is.null(ev_err)) pick(EVAL_FP_FN) else NA_character_
  RAX <- .pc_runner_axes(vapply(pre$cells %||% list(), function(z) as.character(z$path %||% NA_character_), character(1)))
  GCM <- .pc_committed()
  DTE <- DTC$run_all(ROOT, pins = pre$engines, run_diff = TRUE)
  PYV <- DTC$python_versions(ROOT)
  TEV <- DTC$test_evidence_check(ROOT, pins = pre$tests_dt$files)              # DT 시험 증거 md5 = 사전등록 핀 · 통과(격리 점검 v1 권고 9)
  bad <- unique(c(if (!identical(pre$status, "registered")) "사전등록 status ≠ registered",
                  if (is.null(pre$tests_dt$files)) "사전등록에 DT 시험 증거 핀(tests_dt) 없음",
                  if (length(TEV$pending)) paste("DT 시험 증거 없음:", TEV$pending), TEV$errors,
                  if (!identical(pre$round_id, ROUND)) "사전등록 round_id 불일치",
                  ev_err,
                  if (is.null(ev_err) && is.na(pin_fn)) paste0("evaluate.R 에 핀 대조 함수가 없다(후보: ", paste(EVAL_PIN_FN, collapse = " · "), ")"),
                  if (!is.na(pin_fn)) tryCatch(get(pin_fn, envir = EVE)(pre, ROOT), error = function(e) paste0(pin_fn, " 실행 실패: ", conditionMessage(e))),
                  .pc_pin_local(pre, ROOT), .pc_registry(), RAX$mismatches, GCM$mismatches,
                  if (!isTRUE(DTE$ok)) paste("DT 엔진:", c(DTE$errors, DTE$why_pending)), .pc_py_pin(pre, PYV)))
  fpf <- function(mode) if (!is.na(fp_fn)) tryCatch(get(fp_fn, envir = EVE)(RD, mode), error = function(e) paste("error:", conditionMessage(e))) else .pc_fp_local(mode)
  list(bad = bad, pin_fn = pin_fn, RAX = RAX, GCM = GCM, DTE = DTE, PYV = PYV, TEV = TEV,
       fp = list(equality = fpf("equality"), record = fpf("record"), dnn_input = .pc_fp_local("dnn_input"), fn = if (is.na(fp_fn)) ".pc_fp_local" else fp_fn))
}
## 워밍 센티널 단정 — 유효(상태 · 사전등록 md5 · 엔진 md5 = 핀 = 현재 · CODE_VERSION · 캐시 전 달 · cuda · 양성 대조 · RX0 확인 · 워밍 중 데이터 불변) ∧ 신선(워밍 끝 dnn_input 지문 = 현재)
.pc_warm_check <- function(pre) {
  if (!file.exists(WARM_SENT)) return(list(status = "missing", errors = paste("워밍 센티널 없음:", .pc_rel(WARM_SENT), "— warm_cache.sh 먼저")))
  w <- tryCatch(fromJSON(WARM_SENT, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(w)) return(list(status = "invalid", errors = "워밍 센티널 JSON 판독 실패"))
  e <- character(0); add <- function(...) e <<- c(e, paste0(...))
  if (!identical(w$schema, "p2r05_warm_v1")) add("schema ≠ p2r05_warm_v1")
  if (!identical(w$status, "ok")) add("워밍 상태 ", w$status %||% "?", "(", paste(unlist(w$why), collapse = " · "), ")")
  if (!identical(w$round_id, ROUND)) add("round_id 불일치")
  if (!identical(w$prereg_md5, .pc_md5(PR))) add("워밍 때 사전등록 md5 ≠ 현재 사전등록")
  if (!identical(w$code_version, pre$engines$code_version)) add("CODE_VERSION ≠ 사전등록 핀")
  for (g in pre$engines$generated %||% list()) {
    cur <- .pc_md5(file.path(ROOT, g$path))
    if (!identical(as.character(w$engines_md5[[g$rule]] %||% NA), g$md5) || !identical(cur, g$md5)) add("engine_", g$rule, ".R md5: 워밍 ", w$engines_md5[[g$rule]] %||% "없음", " · 핀 ", g$md5, " · 현재 ", cur)
  }
  dn <- function(b) {                                                           # 완료/전체 — 숫자 필드(cache_done · cache_total) 우선 · 없으면 "a/b" 문자열(판정 구현과 같은 형식)
    d <- suppressWarnings(as.integer(b$cache_done %||% NA)); t <- suppressWarnings(as.integer(b$cache_total %||% NA))
    if ((length(d) != 1L || is.na(d)) && is.character(b$cache_months) && grepl("^[0-9]+/[0-9]+$", trimws(b$cache_months))) {
      v <- as.integer(strsplit(trimws(b$cache_months), "/", fixed = TRUE)[[1]]); d <- v[1]; t <- v[2] }
    c(if (length(d) == 1L) d else NA_integer_, if (length(t) == 1L) t else NA_integer_) }
  cmt <- dn(w); cm <- cmt[1]; sm <- cmt[2]
  if (is.na(cm) || is.na(sm) || sm < 1L || cm != sm) add("분위 캐시 ", format(cm), "/", format(sm), " — 전 달이 아니다")
  if (!identical(as.character(w$cache_months %||% ""), sprintf("%d/%d", cm, sm))) add("cache_months 문자열(완료/전체)이 숫자 필드와 다르다 — 판정 구현이 읽는 형식")
  if (!isTRUE(w$q50$all_cuda)) add("학습 달 장치가 전부 cuda 가 아니다(혼합 장치 캐시)")
  ## 재시드 캐시(판단 T1 R-20261018-007 — 워밍 ⑤ · RX0S 칸이 쓴다) — 상태 · 전 달 · cuda · 엔진 md5 = 사전등록 핀 = 현재
  rct <- dn(w$reseed %||% list()); rcm <- rct[1]; rsm <- rct[2]
  if (!identical(w$reseed$status, "ok")) add("재시드 워밍 상태 ", w$reseed$status %||% "없음")
  if (is.na(rcm) || is.na(rsm) || rsm < 1L || rcm != rsm) add("재시드 캐시 ", format(rcm), "/", format(rsm), " — 전 달이 아니다")
  if (!isTRUE(w$reseed$all_cuda)) add("재시드 학습 달 장치가 전부 cuda 가 아니다")
  rp <- pre$engines$rx0s; rcur <- if (!is.null(rp$path)) .pc_md5(file.path(ROOT, rp$path)) else NA_character_
  if (is.null(rp$md5) || !identical(as.character(w$engines_md5$RX0S %||% NA), rp$md5) || !identical(rcur, rp$md5))
    add("engine_RX0S.R md5: 워밍 ", w$engines_md5$RX0S %||% "없음", " · 핀 ", rp$md5 %||% "없음", " · 현재 ", rcur)
  if (!isTRUE(w$positive_control$pass)) add("양성 대조 통과 기록 없음")
  if (!identical(w$rx0$status, "ok")) add("RX0 평균 캐시 확인(워밍 ⑥) 상태 ", w$rx0$status %||% "없음")
  if (!identical(w$dnn_input_fp$start, w$dnn_input_fp$end)) add("워밍 중 데이터 판본이 바뀌었다(dnn_input 지문 시작 ≠ 끝)")
  cur_fp <- .pc_fp_local("dnn_input")
  fresh <- identical(as.character(w$dnn_input_fp$end %||% ""), cur_fp)
  list(status = if (length(e)) "invalid" else if (!fresh) "stale" else "fresh", errors = e, sentinel = .pc_rel(WARM_SENT), finished_at = w$finished_at %||% NA_character_,
       cache = sprintf("분위 %s/%s · 재시드 %s/%s", format(cm), format(sm), format(rcm), format(rsm)), fp_warm = w$dnn_input_fp$end %||% NA_character_, fp_now = cur_fp)
}

## ── GPU 게이트(워밍 ③) ─────────────────────────────────────────────────────────────
if (MODE == "gpu_gate") {
  once <- "--gpu-once" %in% ARGS
  poll <- suppressWarnings(as.integer(argv("gpu-poll", "300"))); if (is.na(poll) || poll < 10L) poll <- 300L   # 300초 = notify_done.sh 와 같은 폴링(운영 · 판정 무관)
  dl <- argv("gpu-deadline"); dlt <- if (!is.null(dl)) as.POSIXct(dl, format = "%Y-%m-%dT%H:%M") else NULL
  if (!is.null(dl) && is.na(dlt)) { cat("[precheck --gpu-gate] --gpu-deadline 형식 오류(YYYY-mm-ddTHH:MM):", dl, "\n"); quit(status = 2L) }
  out <- argv("gpu-out"); t0 <- Sys.time(); n <- 0L
  done <- function(status, g, rc) {
    rec <- list(status = status, waited_s = round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), polls = n, state = g, deadline = dl %||% NA_character_)
    if (!is.null(out)) writeLines(toJSON(rec, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), out, useBytes = TRUE)
    cat(sprintf("[precheck --gpu-gate] %s — %s · 대기 %s초\n", status, .pc_gpu_txt(g), rec$waited_s))
    quit(status = rc)
  }
  repeat {
    n <- n + 1L; g <- .pc_gpu_state()
    if (!isTRUE(g$ok)) done("smi_fail", g, 8L)
    if (identical(g$n_type_c, 0L)) done("clear", g, 0L)
    cat(sprintf("[precheck --gpu-gate] %s — 다른 연산(Type C) %d · 대기(끄지 않는다) · %s\n", .pc_now(), g$n_type_c, .pc_gpu_txt(g)))
    if (once) done("busy", g, 7L)
    if (!is.null(dlt) && Sys.time() >= dlt) done("deadline", g, 7L)
    Sys.sleep(poll)
  }
}

## ── 건식 ─────────────────────────────────────────────────────────────────────────
if (MODE == "dry") {
  ## register.R 의 P2R05_CONST(상수 · 검사 함수 블록) 대입문 하나만 평가 — 사양 검사 · 칸 계획 · 운영 경로 목록의 단일 정본
  ex <- parse(file.path(RD, "register.R"), keep.source = FALSE, encoding = "UTF-8")
  hit <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("P2R05_CONST")), as.list(ex))
  if (length(hit) != 1L) { cat(sprintf("[precheck --dry] register.R 의 P2R05_CONST 대입문이 %d개 — 1개여야 한다\n", length(hit))); quit(status = 1L) }
  K <- eval(hit[[1]][[3]], envir = new.env(parent = globalenv()))
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/measurement_axis.R")))
  ep <- ma_epoch(root = ROOT)
  sc <- K$spec_checks(ROOT, ep$id)
  roles <- vapply(sc$cells, function(z) z$role, "")
  cat(sprintf("[precheck --dry] 칸 계획 %d(기준 %d · 재시드 %d · 변형 %d · 진단 %d · 비교 기준 %d) · 사양 검사 %s(오류 %d) · 활성 epoch %s\n", sc$n_cells, sum(roles == "reference"),
              sum(roles == "reseed"), sum(roles == "variant"), sum(roles == "diagnostic"), sum(roles == "comparison"), if (isTRUE(sc$ok)) "통과" else "실패", length(sc$errors), ep$id))
  for (e in sc$errors) cat("  · ", e, "\n", sep = "")
  for (z in sc$cells) cat(sprintf("  %s  %-13s %-10s %-3s w=%-5s factors=%d%s%s · 기저 %s%s\n", z$md5, z$code, z$role, z$component, format(z$base_weight), z$n_factors,
                                  if (!is.null(z$n_family)) sprintf(" n_family=%d(앞선 %d)", z$n_family, z$n_prior) else "",
                                  if (!is.null(z$control)) paste0(" control=", z$control) else "",
                                  paste(basename(z$engine_files), collapse = "+"),
                                  if (any(is.na(z$engine_md5))) "(엔진 파일 대기)" else ""))
  OPS <- tryCatch(K$ops(ROOT), error = function(e) { cat("[precheck --dry] 운영 경로 목록 실패:", conditionMessage(e), "\n"); character(0) })
  om <- OPS[!file.exists(file.path(ROOT, OPS))]
  om_dt <- om[startsWith(om, DTC$DT_DIR)]; om_other <- setdiff(om, om_dt)
  cat(sprintf("[precheck --dry] 운영 경로 %d(P2R04 승계 %d + DT 엔진 %d — 재시드 엔진 포함) — 없음 %d%s%s\n", length(OPS), length(OPS) - length(DTC$ops_rel(ROOT)), length(DTC$ops_rel(ROOT)), length(om),
              if (length(om_other)) paste0(" · ★승계 경로 없음: ", paste(om_other, collapse = ", ")) else "",
              if (length(om_dt)) sprintf(" · DT 엔진 대기(구현 에이전트 A) %d", length(om_dt)) else ""))
  wc <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries, error = function(e) list())
  cat_bad <- character(0)
  for (cid in K$PIN_CATS) { ent <- Filter(function(z) identical(z$catalog_id, cid), wc)
    st <- if (length(ent)) ent[[1]]$status %||% "?" else "없음"
    if (!identical(st, "active")) cat_bad <- c(cat_bad, cid)
    cat(sprintf("[precheck --dry] 비중 카탈로그 %s — %s\n", cid, st)) }
  pk <- vapply(K$PKGS, function(p) tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_), character(1))
  cat(sprintf("[precheck --dry] 패키지 %s · %s\n", paste(sprintf("%s %s", names(pk), pk), collapse = " · "), R.version.string))
  rax <- .pc_runner_axes(vapply(sc$cells, function(z) z$path, character(1)))
  cat(sprintf("[precheck --dry] 러너 축(%s fixed_axes · 워커가 읽는 값) %s — %s\n", RUNNER_CFG, if (isTRUE(rax$ok)) "일치" else "불일치", .pc_axes_txt(rax)))
  for (e in rax$mismatches) cat("  · ", e, "\n", sep = "")
  dte <- DTC$run_all(ROOT, pins = NULL, run_diff = TRUE)
  if (length(dte$pending)) cat(sprintf("[precheck --dry] DT 엔진 — 대기(구현 에이전트 A 산출 %d개 없음): %s\n", length(dte$pending), paste(basename(dte$pending), collapse = ", ")))
  if (!is.null(dte$record$generated)) {
    cat(sprintf("[precheck --dry] DT 엔진 검사(i 차분 · ii 매니페스트 · iii 정적 PIT · iv 규칙 줄 · v CODE_VERSION · vi 상수%s) %s%s\n",
                if (length(dte$pending)) "" else " · vii 양성 대조 리허설", if (!length(dte$errors)) "통과" else "실패", if (length(dte$errors)) sprintf("(%d)", length(dte$errors)) else ""))
    for (e in dte$errors) cat("  · ", e, "\n", sep = "")
    dc <- dte$record$diff_check
    cat(sprintf("  CODE_VERSION %s · 상수 %s · 템플릿 차분 rc %s · 정적 PIT %s\n", dte$record$code_version, .pc_cj(dte$record$constants),
                format(dc$rc %||% NA), if (isTRUE(dte$record$static_pit$ok)) "clean 7/7" else "미통과"))
    for (g in dte$record$generated) cat(sprintf("  %s  engine_%s.R\n", g$md5, g$rule))
    rs <- dte$record$rx0s
    if (!is.null(rs)) cat(sprintf("  %s  %s(재시드 짝 · %s)\n", rs$md5 %||% "(없음)", rs$path,
                                  if (is.na(rs$md5 %||% NA)) "대기 — 구현 에이전트 A" else if (isTRUE(rs$ok))
                                    sprintf("원본과 다른 줄 %s = 시드 1(%s행) + 식별자 %d(%s)", format(rs$n_diff_lines %||% NA), format(rs$seed_line$line %||% NA), length(rs$identifier_lines),
                                            paste(vapply(rs$identifier_lines, function(z) sprintf("%d행 %s", z$line, sub("\\s*<-.*$", "", z$reseed)), ""), collapse = " · "))
                                  else paste(rs$errors, collapse = " · ")))
  }
  tev <- DTC$test_evidence_check(ROOT)                                          # DT 시험 증거(격리 점검 v1 권고 9) — 없음 = 대기(구현 에이전트 A) · 실패 = 건식 실패
  cat(sprintf("[precheck --dry] DT 시험 증거 %d — 통과 %d · 없음 %d · 실패 %d (md5 핀 대상 · 사전등록 tests_dt)\n", length(tev$record),
              sum(vapply(tev$record, function(z) isTRUE(z$pass), logical(1))), length(tev$pending), length(tev$errors)))
  for (z in tev$record) cat(sprintf("  %-32s  %s%s\n", if (is.na(z$md5)) "(없음)" else z$md5, basename(z$path),
                                    if (is.na(z$md5)) " — 대기(구현 에이전트 A)" else if (isTRUE(z$pass)) sprintf(" — 통과%s", if (!is.null(z$n_ok)) sprintf("(%s/%s)", z$n_ok, z$n) else if (!is.null(z$n_cases)) sprintf("(사례 %s)", z$n_cases) else if (!is.null(z$mutants_fail_all_n)) sprintf("(뮤턴트 %s 전부 실패)", z$mutants_fail_all_n) else "")
                                    else if (is.na(z$pass)) " — md5 핀만(README)" else paste0(" — ★실패", if (!is.null(z$why)) paste0("(", z$why, ")") else "")))
  for (e in tev$errors) cat("  · ", e, "\n", sep = "")
  pyv <- DTC$python_versions(ROOT)
  cat(sprintf("[precheck --dry] 파이썬 판(기록) %s\n", if (isTRUE(pyv$ok)) paste(sprintf("%s %s", DTC$PY_KEYS, vapply(DTC$PY_KEYS, function(k) as.character(pyv[[k]] %||% "?"), "")), collapse = " · ") else paste("조회 실패 —", pyv$why)))
  ev <- file.exists(file.path(RD, K$EVALF))
  ev_b <- K$EVALF[!ev & K$EVALF %in% c("evaluate.R", "evaluate_fixture.R", "round_rules.R")]; ev_c <- K$EVALF[!ev & !(K$EVALF %in% ev_b)]
  cat(sprintf("[precheck --dry] 평가 경로 %d — 있음 %d%s%s\n", length(K$EVALF), sum(ev), if (length(ev_b)) paste0(" · 대기(판정 구현 · 에이전트 B): ", paste(ev_b, collapse = ", ")) else "",
              if (length(ev_c)) paste0(" · ★측정 기계 미작성: ", paste(ev_c, collapse = ", ")) else ""))
  tf <- file.exists(file.path(ROOT, K$TESTF))
  cat(sprintf("[precheck --dry] 검사 파일 %d — 있음 %d%s\n", length(K$TESTF), sum(tf), if (any(!tf)) paste0(" · 없음: ", paste(K$TESTF[!tf], collapse = ", ")) else ""))
  cat(sprintf("[precheck --dry] 리허설 요약 %s · 행동 카드 원본 %s · 사전등록 사본 %s\n", if (file.exists(file.path(RD, "rehearsal", "summary.json"))) "있음" else "없음(Rscript rehearse.R — evaluate.R 생긴 뒤)",
              if (file.exists(file.path(ROOT, "06_Registry/behavior_card.json"))) "있음" else "없음",
              if (file.exists(file.path(RD, "behavior_card_cfg_at_prereg.json"))) "있음" else "아직 없음(register.R --draft · rehearse.R 이 만든다)"))
  cat(sprintf("[precheck --dry] 데이터 지문 equality: %s\n", .pc_fp_local("equality")))
  cat(sprintf("[precheck --dry] 데이터 지문 record: %s\n", .pc_fp_local("record")))
  cat(sprintf("[precheck --dry] 데이터 지문 dnn_input: %s\n", .pc_fp_local("dnn_input")))
  cat(sprintf("[precheck --dry] 데이터 상태: 벤치 마지막 %s · RAWDATA 마지막 %s · 사전등록 %s · 워밍 센티널 %s\n", .pc_lastd("benchmark.parquet"), .pc_lastd("RAWDATA.parquet"),
              if (file.exists(PR)) "있음" else "없음(커밋 확인 = 본 대조에서)", if (file.exists(WARM_SENT)) "있음" else "없음(warm_cache.sh — 등록 · 커밋 뒤)"))
  g <- .pc_gpu_state(); ln <- .pc_lane()
  cat(sprintf("[precheck --dry] GPU(1회 · 판정 밖): %s · 게이트 %s\n", .pc_gpu_txt(g), if (!isTRUE(g$ok)) "확인 불가" else if (g$n_type_c == 0L) "열림" else "닫힘(워밍 전 대기 대상)"))
  cat(sprintf("[precheck --dry] 충실구현 레인(%s replication_lane): enabled=%s · 정지/재개 = 도훈 확인 사항(이 파일은 바꾸지 않는다)\n", LANE_CFG, format(ln$enabled)))
  if (file.exists(PR)) { gcm <- .pc_committed()
    cat(sprintf("[precheck --dry] 사전등록 커밋(기록 · 건식 판정 밖) — %s\n", if (isTRUE(gcm$ok)) "두 사본 커밋 · 변경 없음" else paste(gcm$mismatches, collapse = " / "))) }
  ok <- isTRUE(sc$ok) && !length(om_other) && !length(cat_bad) && !anyNA(pk) && isTRUE(rax$ok) && !length(dte$errors) && !length(ev_c) && !length(tev$errors)
  pend <- c(if (length(dte$pending)) sprintf("DT 엔진 %d", length(dte$pending)), if (length(tev$pending)) sprintf("DT 시험 증거 %d", length(tev$pending)),
            if (length(ev_b)) sprintf("판정 구현 %d", length(ev_b)))
  cat(sprintf("[precheck --dry] %s%s — 측정 허가 아님(측정은 사전등록 · 커밋 · 워밍 뒤 Rscript precheck.R)\n", if (ok) "건식 통과" else "건식 실패",
              if (length(pend)) paste0(" · 다른 에이전트 산출 대기: ", paste(pend, collapse = " · ")) else ""))
  quit(status = if (ok) 0L else 1L)
}

## ── 사전등록이 필요한 모드(본 대조 · 워밍 대조 · 워밍 센티널 단정) ─────────────────────────────────────
if (!file.exists(PR)) { cat("[precheck] 사전등록 없음 — 측정 · 워밍하지 않는다(건식 점검 = Rscript precheck.R --dry)\n"); quit(status = 1L) }
pre <- fromJSON(PR, simplifyVector = FALSE)

if (MODE == "warm_check") {
  wc <- .pc_warm_check(pre)
  cat(sprintf("[precheck --warm-check] %s — 센티널 %s · 캐시 %s · 끝 %s%s\n", wc$status, wc$sentinel %||% "-", wc$cache %||% "-", wc$finished_at %||% "-",
              if (length(wc$errors)) paste0("\n  · ", paste(wc$errors, collapse = "\n  · ")) else if (identical(wc$status, "stale")) "\n  · 워밍 뒤 데이터 판본이 바뀌었다(dnn_input 지문 워밍 끝 ≠ 현재) — warm_cache.sh 를 다시 돌린다(내용 주소 캐시라 바뀐 달만 재학습)" else ""))
  quit(status = switch(wc$status, fresh = 0L, stale = 10L, 1L))
}

F <- .pc_full(pre)
out <- list(at = .pc_now(), mode = MODE, prereg_md5 = .pc_md5(PR), ok = !length(F$bad), mismatches = F$bad,
            pin_fn = c(evaluate = F$pin_fn, local = ".pc_pin_local"), n_cells = length(pre$cells),
            runner_axes = F$RAX, prereg_commit = F$GCM,
            engines = list(ok = isTRUE(F$DTE$ok), errors = F$DTE$errors, code_version = F$DTE$record$code_version,
                           diff_check = F$DTE$record$diff_check[c("ok", "rc")], static_pit_ok = F$DTE$record$static_pit$ok, python = F$PYV,
                           tests_dt = list(ok = isTRUE(F$TEV$ok), n = length(F$TEV$record), errors = F$TEV$errors, pending = F$TEV$pending)),
            data_state = list(benchmark_last = .pc_lastd("benchmark.parquet"), rawdata_last = .pc_lastd("RAWDATA.parquet")),
            data_fingerprint = F$fp, gpu = .pc_gpu_state(), lane = .pc_lane(), git_head = .pc_git_head())
of <- if (MODE == "warm") file.path(RD, "warm", "precheck_warm.json") else file.path(RD, "results", "precheck.json")
dir.create(dirname(of), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), of, useBytes = TRUE)
tag <- if (MODE == "warm") "[precheck --warm]" else "[precheck]"
if (length(F$bad)) { cat(tag, " 불일치 — ", if (MODE == "warm") "워밍하지 않는다" else "측정하지 않는다", ":\n", paste0("  · ", F$bad, collapse = "\n"), "\n", sep = ""); quit(status = 1L) }
cat(sprintf("%s 통과 — 사양 %d · 운영 경로 %d · 비중 카탈로그 %d · 패키지 %d · 평가 경로 %d · 등록부 md5 일치 · 핀 대조 %s ∪ .pc_pin_local · 러너 축 일치(%s) · DT 엔진(차분 · 매니페스트 · 정적 PIT · 상수 · 리허설 · 시험 증거 md5) 일치 · 파이썬 판 일치 · 사전등록 커밋 확인 · 데이터 지문 기록 → %s\n",
            tag, length(pre$cells), length(pre$operational_pins$files), length(pre$operational_pins$catalog_entries),
            length(pre$operational_pins$packages), length(pre$evaluation$files), F$pin_fn, .pc_axes_txt(F$RAX), .pc_rel(of)))
