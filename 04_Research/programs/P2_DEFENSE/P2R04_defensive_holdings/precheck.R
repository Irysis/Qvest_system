## P2R04 측정 직전 대조 — 사양 23 · 운영 경로 md5(팩터 DB 커넥터 · 등급 계약 v3.2 포함) · 팩터 레지스트리 엔트리 · 비중 카탈로그 엔트리(E3 lean:entropy) · 패키지 · R 판 ·
##   평가 경로 md5 · 행동 카드 설정 사본 md5 가 사전등록 값과 같고, 등록부(research_programs.json)의 이 라운드 사전등록 md5 = 파일 md5 여야 측정한다.
##   + 러너 축(교차 점검 v1 필수 5): rf_cell_worker.R 가 칸 사양 대신 06_Registry/reinforce_program.json fixed_axes 에서 읽는 종목 수 n_max · 수수료 commission_bps =
##     사양 fixed_axes 값 — 파일 md5 핀이 아니라 읽는 키 값을 대조한다(자주 바뀌는 파일이라 무관한 편집으로 측정을 막지 않게)
##   + 등록 → 커밋 → 측정(교차 점검 v1 권고 5): 사전등록 두 사본(stage_artifacts 정본 · 라운드 prereg.json)이 git 추적 · 작업 트리 변경 없음 · 두 md5 같음
##   오버레이 없음 → 오버레이 카탈로그 arm 핀 없음(사전등록에 있으면 대조한다).
##   핀 대조 = evaluate.R 의 핀 대조 함수(평가 시작부와 같은 함수 — EVAL_PIN_FN 후보 이름 중 처음 정의된 것) ∪ 이 파일의 같은 정의(.pc_pin_local) —
##   어느 쪽이든 불일치를 내면 종료 코드 1(measure.sh 가 측정하지 않는다). 데이터 지문(fingerprint.sh — equality · record)을 함께 기록한다. 성과 수치 없음.
## 실행: Rscript precheck.R          산출 = results/precheck.json(evaluate.R 이 ok 를 요구한다)
##       Rscript precheck.R --dry    건식 — 사전등록 없이 칸 계획 · 사양 · 핀 목록 · 러너 축만: register.R 의 상수 블록(P2R04_CONST) 대입문 하나만 골라 평가해
##                                   사양 검사(register.R 과 같은 함수) · 운영 경로 실재 · 비중 카탈로그 · 패키지 · 러너 축 · 평가 경로 · 검사 파일 유무 · 데이터 지문을 출력한다.
##                                   results/ 에 쓰지 않는다 · 측정 허가가 아니다(종료 코드 0 = 사양 · 운영 경로 · 카탈로그 · 패키지 · 러너 축 통과 · 미작성 평가 파일은 목록만)
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PROGRAM <- "P2_DEFENSE"; ROUND <- "P2R04_defensive_holdings"
RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings")
PR <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings/prereg.json")
DRY <- "--dry" %in% commandArgs(trailingOnly = TRUE)
EVAL_PIN_FN <- c("p2r04_pin_mismatches", "p2_pin_mismatches")                  # evaluate.R 쪽 이름 후보(앞이 우선 · P2R03 = p2_pin_mismatches)
EVAL_FP_FN <- c("p2r04_fingerprint", "p2_fingerprint")
## 러너 축 — rf_cell_worker.R:31-32(PROG <- reinforce_program.json · AX <- PROG$fixed_axes) · :96-101(n_long = n_max = AX$n_max · commission_paper = AX$commission_bps / 10000).
##   start_date · universe 는 대조하지 않는다 — 사양에 측정 축 표식(fixed_axes.measurement_axis)이 있으면 워커가 epoch 에서 읽는다(:84-87 · 사양 검사가 표식을 단정).
RUNNER_CFG <- "06_Registry/reinforce_program.json"
RUNNER_KEYS <- c("n_max", "commission_bps")
.pc_md5 <- function(f) unname(as.character(tools::md5sum(f)))
.pc_cj <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
.pc_rel <- function(p) sub(paste0("^", ROOT, "/"), "", p)
## 핀 대조(이 파일의 정의) — P2R03 evaluate.R::p2_pin_mismatches 와 같은 항목 · 같은 비교. 반환 = 불일치 설명(없으면 길이 0)
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
  FRC <- list()                                                                  # 팩터 레지스트리 엔트리({id, path, entry} · evaluate.R 과 같은 비교)
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
## 러너 축 대조(교차 점검 v1 필수 5) — 워커가 읽는 키 값 = 사양 fixed_axes 값(칸마다 같아야 한다). 반환 = list(ok, mismatches, runner, spec …)
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
## 등록 → 커밋 → 측정(교차 점검 v1 권고 5) — 사전등록 두 사본이 git 추적 · 작업 트리 변경 없음 · 두 md5 같음. 반환 = list(ok, mismatches, paths)
PR_COPY <- file.path(RD, "prereg.json")
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
## 데이터 지문 — fingerprint.sh(measure.sh 와 같은 정의) · 줄을 '|' 로 잇는다(P2R03 p2_fingerprint 와 같은 형식)
.pc_fp_local <- function(mode) {
  o <- tryCatch(suppressWarnings(system2("bash", c(shQuote(file.path(RD, "fingerprint.sh")), mode), stdout = TRUE, stderr = TRUE)),
                error = function(e) paste("error:", conditionMessage(e)))
  paste(o, collapse = "|")
}
.pc_git_head <- function() {
  h <- suppressWarnings(system2("git", c("-C", ROOT, "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE))
  st <- attr(h, "status"); if ((!is.null(st) && !identical(as.integer(st), 0L)) || !length(h)) NA_character_ else h[1]
}
## 데이터 상태(벤치 · RAWDATA 마지막 날 — 판정 무관 · 판본 해석용 · P2R03 승계)
.pc_lastd <- function(f) tryCatch(format(max(as.Date(arrow::read_parquet(file.path(ROOT, ".cache", f), col_select = "Date")$Date))), error = function(e) paste("error:", conditionMessage(e)))
.pc_axes_txt <- function(r) paste(vapply(RUNNER_KEYS, function(k) sprintf("%s 러너 %s · 사양 %s", k, format(r$runner[[k]] %||% NA), paste(format(r$spec[[k]] %||% NA), collapse = "/")), ""), collapse = " · ")

if (DRY) {
  ## ── 건식 — register.R 의 P2R04_CONST(순수 상수 · 검사 함수 블록) 대입문 하나만 평가 ──────────────────────────
  ex <- parse(file.path(RD, "register.R"), keep.source = FALSE, encoding = "UTF-8")
  hit <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("P2R04_CONST")), as.list(ex))
  if (length(hit) != 1L) { cat(sprintf("[precheck --dry] register.R 의 P2R04_CONST 대입문이 %d개 — 1개여야 한다\n", length(hit))); quit(status = 1L) }
  K <- eval(hit[[1]][[3]], envir = new.env(parent = globalenv()))
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/measurement_axis.R")))
  ep <- ma_epoch(root = ROOT)
  sc <- K$spec_checks(ROOT, ep$id)
  roles <- vapply(sc$cells, function(z) z$role, "")
  cat(sprintf("[precheck --dry] 칸 계획 %d(기준 %d · 장치 %d · 진단 %d) · 사양 검사 %s(오류 %d) · 활성 epoch %s\n", sc$n_cells, sum(roles == "reference"), sum(roles == "variant"),
              sum(roles == "diagnostic"), if (isTRUE(sc$ok)) "통과" else "실패", length(sc$errors), ep$id))
  for (e in sc$errors) cat("  · ", e, "\n", sep = "")
  for (z in sc$cells) cat(sprintf("  %s  %-14s %-10s %-4s factors=%d(장치 %d회) w=%s%s%s\n", z$md5, z$code, z$role, z$component, z$n_factors, as.integer(z$device_repeat %||% 0L),
                                  format(z$base_weight), if (!is.null(z$device_share)) sprintf(" 방어 몫=%s", format(z$device_share)) else "",
                                  if (!is.null(z$n_family)) sprintf(" n_family=%d", z$n_family) else ""))
  cat(sprintf("[precheck --dry] 혼합 몫 유도 — 장치 방어 몫 s = %s · 도구 상자 몫 t = %s · E3 장치 w = %s · r = %d\n", format(sc$mix$s), format(sc$mix$t),
              format(sc$mix$engines$E3$H$w), as.integer(sc$mix$engines$E3$H$r)))
  om <- K$OPS[!file.exists(file.path(ROOT, K$OPS))]
  cat(sprintf("[precheck --dry] 운영 경로 %d — 없음 %d%s\n", length(K$OPS), length(om), if (length(om)) paste0(": ", paste(om, collapse = ", ")) else ""))
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
  ev <- file.exists(file.path(RD, K$EVALF))
  cat(sprintf("[precheck --dry] 평가 경로 %d — 있음 %d%s\n", length(K$EVALF), sum(ev), if (any(!ev)) paste0(" · 미작성: ", paste(K$EVALF[!ev], collapse = ", ")) else ""))
  tf <- file.exists(file.path(ROOT, K$TESTF))
  cat(sprintf("[precheck --dry] 검사 파일 %d — 있음 %d%s\n", length(K$TESTF), sum(tf), if (any(!tf)) paste0(" · 없음: ", paste(K$TESTF[!tf], collapse = ", ")) else ""))
  cat(sprintf("[precheck --dry] 행동 카드 원본 %s · 사전등록 사본 %s\n", if (file.exists(file.path(ROOT, "06_Registry/behavior_card.json"))) "있음" else "없음",
              if (file.exists(file.path(RD, "behavior_card_cfg_at_prereg.json"))) "있음" else "아직 없음(register.R --draft · rehearse.R 이 만든다)"))
  cat(sprintf("[precheck --dry] 데이터 지문 equality: %s\n", .pc_fp_local("equality")))
  cat(sprintf("[precheck --dry] 데이터 지문 record: %s\n", .pc_fp_local("record")))
  cat(sprintf("[precheck --dry] 데이터 상태: 벤치 마지막 %s · RAWDATA 마지막 %s · 사전등록 %s\n", .pc_lastd("benchmark.parquet"), .pc_lastd("RAWDATA.parquet"),
              if (file.exists(PR)) "있음" else "없음(커밋 확인 = 본 대조에서)"))
  if (file.exists(PR)) { gcm <- .pc_committed()
    cat(sprintf("[precheck --dry] 사전등록 커밋(기록 · 건식 판정 밖) — %s\n", if (isTRUE(gcm$ok)) "두 사본 커밋 · 변경 없음" else paste(gcm$mismatches, collapse = " / "))) }
  ok <- isTRUE(sc$ok) && !length(om) && !length(cat_bad) && !anyNA(pk) && isTRUE(rax$ok)
  cat(sprintf("[precheck --dry] %s — 측정 허가 아님(측정은 사전등록 · 커밋 뒤 Rscript precheck.R)\n", if (ok) "건식 통과" else "건식 실패"))
  quit(status = if (ok) 0L else 1L)
}

## ── 본 대조(측정 직전) ─────────────────────────────────────────────────────────
if (!file.exists(PR)) { cat("[precheck] 사전등록 없음 — 측정하지 않는다(건식 점검 = Rscript precheck.R --dry)\n"); quit(status = 1L) }
pre <- fromJSON(PR, simplifyVector = FALSE)
EF <- file.path(RD, "evaluate.R")
EVE <- new.env(parent = globalenv())                                            # evaluate.R 은 격리 환경에 적재(이 파일의 변수를 덮지 않게)
ev_err <- if (!file.exists(EF)) "evaluate.R 없음" else tryCatch({ source(EF, local = EVE); NULL }, error = function(e) paste("evaluate.R 적재 실패:", conditionMessage(e)))   # 도우미만(본 실행 블록은 sys.nframe 가드)
.pc_pick <- function(cands) { h <- cands[vapply(cands, function(n) exists(n, envir = EVE, mode = "function", inherits = FALSE), logical(1))]; if (length(h)) h[1] else NA_character_ }
pin_fn <- if (is.null(ev_err)) .pc_pick(EVAL_PIN_FN) else NA_character_
fp_fn <- if (is.null(ev_err)) .pc_pick(EVAL_FP_FN) else NA_character_
.pc_registry <- function() tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/programs/program_registry.R")))
  rr <- Filter(function(r) identical(r$round_id, ROUND), pr_get(pr_load(ROOT), PROGRAM)$rounds %||% list())
  if (!length(rr)) "등록부에 이 라운드 기록 없음(register.R --register 미완료)"
  else if (!identical(rr[[1]]$prereg_md5, .pc_md5(PR))) "등록부 기록 사전등록 md5 ≠ 파일(R2)"
  else character(0)
}, error = function(e) paste("등록부 판독 실패:", conditionMessage(e)))
RAX <- .pc_runner_axes(vapply(pre$cells %||% list(), function(z) as.character(z$path %||% NA_character_), character(1)))
GCM <- .pc_committed()
bad <- unique(c(if (!identical(pre$status, "registered")) "사전등록 status ≠ registered",
                if (!identical(pre$round_id, ROUND)) "사전등록 round_id 불일치",
                ev_err,
                if (is.null(ev_err) && is.na(pin_fn)) paste0("evaluate.R 에 핀 대조 함수가 없다(후보: ", paste(EVAL_PIN_FN, collapse = " · "), ")"),
                if (!is.na(pin_fn)) tryCatch(get(pin_fn, envir = EVE)(pre, ROOT), error = function(e) paste0(pin_fn, " 실행 실패: ", conditionMessage(e))),
                .pc_pin_local(pre, ROOT),
                .pc_registry(),
                RAX$mismatches,
                GCM$mismatches))
fpf <- function(mode) if (!is.na(fp_fn)) tryCatch(get(fp_fn, envir = EVE)(RD, mode), error = function(e) paste("error:", conditionMessage(e))) else .pc_fp_local(mode)
out <- list(at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = .pc_md5(PR), ok = !length(bad), mismatches = bad,
            pin_fn = c(evaluate = pin_fn, local = ".pc_pin_local"), n_cells = length(pre$cells),
            runner_axes = RAX, prereg_commit = GCM,
            data_state = list(benchmark_last = .pc_lastd("benchmark.parquet"), rawdata_last = .pc_lastd("RAWDATA.parquet")),
            data_fingerprint = list(equality = fpf("equality"), record = fpf("record"), fn = if (is.na(fp_fn)) ".pc_fp_local" else fp_fn),
            git_head = .pc_git_head())
dir.create(file.path(RD, "results"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), file.path(RD, "results", "precheck.json"), useBytes = TRUE)
if (length(bad)) { cat("[precheck] 불일치 — 측정하지 않는다:\n", paste0("  · ", bad, collapse = "\n"), "\n"); quit(status = 1L) }
cat(sprintf("[precheck] 통과 — 사양 %d · 운영 경로 %d · 비중 카탈로그 %d · 패키지 %d · 평가 경로 %d · 등록부 md5 일치 · 핀 대조 %s ∪ .pc_pin_local · 러너 축 일치(%s) · 사전등록 커밋 확인 · 데이터 지문 기록\n",
            length(pre$cells), length(pre$operational_pins$files), length(pre$operational_pins$catalog_entries),
            length(pre$operational_pins$packages), length(pre$evaluation$files), pin_fn, .pc_axes_txt(RAX)))
