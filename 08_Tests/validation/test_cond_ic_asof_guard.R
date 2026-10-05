#!/usr/bin/env Rscript
#==============================================================================
# test_cond_ic_asof_guard.R — V6 조건부 IC 소비의 호출부 차단 (도훈 결정 D-E-V6-CONDITIONAL-IC 2026-09-25 · pit.md C1/C14 · V6 절)
#
# 배경: .cache/conditional_ic_matrix.csv = 전기간 IC 스냅샷(Usable_Date 없음). 엔진 소비 함수 4종(sg_compute_role_utility ·
#   sg_determine_role · sg_generate_research_slate · sg_role_admission)이 그 conditional_value 로 역할·입장·효용·S5 후보를 정했다.
#   수리 = 호출부 가드(02_Infrastructure/validation/cond_ic_asof_guard.R · 엔진 바이트 불변) + 호출부 3곳
#   (hook_batch_runner.R hook_determine_role · hook_quant_factcheck 행렬 조회 제거 · v55 래퍼 fail-closed) + 문서 표식.
#   as-of 제공자는 미채택(도훈 결정 사항) → 미제공 = 사용 안 함.
#
# 양방향:
#   A. 가드 래퍼 — [양성 대조] 원본은 행렬 섭동(부호·순열·부재·실행렬 사본)에 반응한다(검정력) ·
#      가드판은 모든 섭동에서 역할·입장·효용·slate 가 불변 · 가드판 = 원본의 '행렬 부재' 판 · 효용 U = NA(가짜 w4×0.5 없음) ·
#      slate NULL·파일 쓰기 0(기존 slate 바이트 불변) · 과차단 없음(core_alpha/diversifier 판정·다른 경로 통과) · 제공자 미채택
#   B. 가림 우회 거부 — 합성 소비 함수의 변형 5종(base::file.path · paste0 · list.files · 복사 · 도우미 이관) → cic_blind 가 멈춘다 ·
#      정적 검사가 못 보는 변형(전역 경로 변수)은 A 의 섭동 불변 검사가 잡는다(그 검사의 검정력 실증)
#   C. 정적 봉인 — 코드 트리(git 목록 · 02_Infrastructure·.claude)에서 소비 함수 4종 직접 호출·이름 참조 0(엔진 정의·가드 제외) ·
#      행렬 파일명을 코드로 부르는 파일 = 허용 목록뿐 · 프롬프트·룰·스킬 .md 의 행렬 언급 ±3줄 안 D-E-V6 표식 ·
#      [위반 주입] 합성 트리 6종 적발 · [음성 대조] 주석·*_asof·*_v55·정의·표식 달린 언급은 통과
#   D. 호출부 실행(자식 Rscript · 합성 루트 · R_ENVIRON_USER=빈 파일) — hook_determine_role 역할 불변 · = 원본 부재 판(돌연변이: 원본 호출 복원 → 반응) ·
#      hook_quant_factcheck kr_ic_sign 불변(돌연변이: 구판 행렬 블록 → 반응) · v55 역할/입장 불변 · v55 가드 부재 = fail-closed(구판 폴백 없음)
#   E. 문언 — pit.md Lockbox 절 끝 ORGANIC-DE 예외 문장(결정문 그대로) · V6 절 as-of 문언
#   Z. 격리 — 운영(QM_ROOT) 코드·행렬 해시 불변 · 쓰기 = tempdir 합성 루트만
# 대상 루트: QM_ROOT(기본 운영) · 정적 봉인 파일 목록 = git -C ${QVEST_CIC_SEAL_GIT:-QM_ROOT} ls-files(08_Tests 는 훑지 않는다)
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
CODE <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
SEAL_GIT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QVEST_CIC_SEAL_GIT", CODE), fixed = TRUE))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
finish <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"cond_ic_asof_guard","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL > 0L) 1L else 0L)
}
rel <- function(...) file.path(CODE, ...)
ENGINE <- rel("02_Infrastructure", "stage_gate_engine.R")
GUARD  <- rel("02_Infrastructure", "validation", "cond_ic_asof_guard.R")
HBR    <- rel("02_Infrastructure", "R", "hook_batch_runner.R")
V55    <- rel("02_Infrastructure", "pipeline", "v55_stage_gate_extensions.R")
SCHEMA <- rel("02_Infrastructure", "validation", "stage_artifact_schemas.R")
CONFIG <- rel("02_Infrastructure", "config.R")
PITMD  <- rel(".claude", "rules", "pit.md")
OPS_MAT <- rel(".cache", "conditional_ic_matrix.csv")
TARGETS <- c("sg_compute_role_utility", "sg_determine_role", "sg_generate_research_slate", "sg_role_admission")
for (p in c(ENGINE, GUARD, HBR, V55, SCHEMA, CONFIG, PITMD)) if (!file.exists(p)) { ng("대상 파일 부재", p); finish() }

REAL <- c(ENGINE, GUARD, HBR, V55, CONFIG, PITMD, OPS_MAT[file.exists(OPS_MAT)])
REAL_MD5 <- tools::md5sum(REAL)
SB <- normalizePath(tempfile("cicg_"), winslash = "/", mustWork = FALSE)
for (d in c(".cache", "04_Research/strategies", "06_Registry", "stage_artifacts")) dir.create(file.path(SB, d), recursive = TRUE)
EMPTY_ENV <- file.path(SB, "empty.Renviron"); invisible(file.create(EMPTY_ENV))

# ── 원본 4종 + %||% 만 엔진에서 적재(엔진 전체 source 는 .SG_CACHE 생성 부수효과가 있어 피한다) ──
ex <- parse(ENGINE, encoding = "UTF-8", keep.source = FALSE)
for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && as.character(e[[2]]) %in% c(TARGETS, "%||%")) eval(e, globalenv())
if (!all(vapply(TARGETS, exists, logical(1), envir = globalenv(), inherits = FALSE))) { ng("엔진에서 소비 함수 4종 적재 실패"); finish() }
PROJECT_ROOT <- SB
sys.source(GUARD, envir = globalenv())
for (fn in c("sg_determine_role_asof", "sg_role_admission_asof", "sg_compute_role_utility_asof", "sg_generate_research_slate_asof",
             "cic_blind", "cic_asof_provided"))
  if (!exists(fn, mode = "function")) { ng("가드 공개 함수 부재", fn); finish() }

MAT <- file.path(SB, ".cache", "conditional_ic_matrix.csv")
syn_mat <- function(cv) data.table(Factor_Name = c("F1", "F2", "F3", "F4"), ic_all = c(.01, .02, .03, .01),
  ic_bad = cv + .01, ic_good = .01, conditional_value = cv, recent_3y_icir = .1, n_months = 100L,
  used = c(FALSE, FALSE, FALSE, FALSE), category = c("value", "value", "quality", "risk"))
real_mat <- if (file.exists(OPS_MAT)) fread(OPS_MAT) else NULL
STATES <- list(
  pos    = function() fwrite(syn_mat(c(.05, -.03, .04, .06)), MAT),
  neg    = function() fwrite(syn_mat(c(-.05, .03, -.04, -.06)), MAT),
  absent = function() unlink(MAT))
if (!is.null(real_mat) && "conditional_value" %in% names(real_mat) && nrow(real_mat) > 10) {
  # 실행렬 사본(읽기만) + 그 위 섭동 3종 — 탐침 팩터 F1 행을 붙여 원본이 반응하게 한다
  rm0 <- copy(real_mat)
  addF1 <- function(m, v) { r <- m[1]; r[, `:=`(Factor_Name = "F1", conditional_value = v, category = "value", used = FALSE)]; rbind(m, r) }
  STATES$real_pos <- function() fwrite(addF1(rm0, max(rm0$conditional_value, na.rm = TRUE)), MAT)
  set.seed(20260925)
  for (k in 1:3) local({
    kk <- k; perm <- sample(nrow(rm0)); sg <- sample(c(-1, 1), nrow(rm0), TRUE)
    STATES[[sprintf("real_perm%d", kk)]] <<- function() {
      m <- copy(rm0); m[, conditional_value := conditional_value[perm] * sg]
      fwrite(addF1(m, sample(m$conditional_value, 1)), MAT)
    }
  })
}
S2 <- list(ic_ir = .2, factor_id = "F1")
S3_hi <- list(max_abs_corr_db = .2)   # orth 0.8 — defense 분기(cond>0)
S3_lo <- list(max_abs_corr_db = .6)   # orth 0.4 — cond>0.02 분기
S4 <- list(factor_id = "F1", delta_sharpe = .1, kospi_beat = FALSE)
quiet <- function(expr) { v <- NULL; invisible(capture.output(v <- tryCatch(expr, error = function(e) structure(list(err = conditionMessage(e)), class = "err")))); v }
fmt <- function(x) if (inherits(x, "err")) paste0("ERR:", x$err) else paste(as.character(unlist(x)), collapse = ",")
probe <- function(guarded) {
  if (guarded) list(
    role_hi = quiet(sg_determine_role_asof(S2, S3_hi, S4)), role_lo = quiet(sg_determine_role_asof(S2, S3_lo, S4)),
    adm_def = quiet(sg_role_admission_asof("defense", S4, S3_hi)[c("route", "reason")]),
    util_def = quiet(sg_compute_role_utility_asof("F1", "defense", S2, S3_hi, S4)),
    slate = quiet(sg_generate_research_slate_asof("F1", "STR_T")))
  else list(
    role_hi = quiet(sg_determine_role(S2, S3_hi, S4)), role_lo = quiet(sg_determine_role(S2, S3_lo, S4)),
    adm_def = quiet(sg_role_admission("defense", S4, S3_hi)[c("route", "reason")]),
    util_def = quiet(sg_compute_role_utility("F1", "defense", S2, S3_hi, S4)))
}
SLATE_DIR <- file.path(SB, "04_Research", "strategies", "STR_T", "stage_artifacts")
dir.create(SLATE_DIR, recursive = TRUE)
SLATE_OLD <- file.path(SLATE_DIR, "s5_research_slate_F1.json")
writeLines('{"sentinel":"past slate — must stay byte-identical"}', SLATE_OLD)
SLATE_MD5 <- tools::md5sum(SLATE_OLD)
run_states <- function(guarded) lapply(names(STATES), function(s) { STATES[[s]](); probe(guarded) }) |> setNames(names(STATES))

cat("--- A. 가드 래퍼(섭동 불변 · 양성 대조) ---\n")
R_orig <- run_states(FALSE); R_g <- run_states(TRUE)
key <- function(x) x[c("role_hi", "role_lo", "adm_def")]
chk(!identical(key(R_orig$pos), key(R_orig$neg)) && !identical(R_orig$pos$util_def$utility_score, R_orig$neg$util_def$utility_score),
    "A1 [양성 대조] 원본은 행렬 섭동에 반응한다(역할·입장·효용 — 검정력)",
    sprintf("pos=%s/%s neg=%s/%s", fmt(R_orig$pos$role_hi), fmt(R_orig$pos$adm_def$route), fmt(R_orig$neg$role_hi), fmt(R_orig$neg$adm_def$route)))
if ("real_pos" %in% names(R_orig))
  chk(identical(R_orig$real_pos$role_hi, "defense"), "A1b [양성 대조] 실행렬 사본에서도 원본은 conditional_value 로 defense 를 낸다")
gk <- lapply(R_g, function(x) list(x$role_hi, x$role_lo, x$adm_def, x$util_def$utility_score, x$util_def$component_scores, x$slate))
chk(length(unique(gk)) == 1L, "A2 가드판: 모든 섭동 상태에서 역할·입장·효용·slate 불변",
    sprintf("상태 %d · 고유 결과 %d", length(gk), length(unique(gk))))
chk(!any(unlist(lapply(R_g, function(x) vapply(x[c("role_hi", "role_lo", "adm_def", "util_def", "slate")], inherits, logical(1), "err")))),
    "A2b 가드판 호출이 오류 없이 돈다(실제 엔진 함수 — 가림 AST 검사 통과)")
chk(identical(R_g$pos$role_hi, R_orig$absent$role_hi) && identical(R_g$pos$role_lo, R_orig$absent$role_lo) &&
      identical(R_g$pos$adm_def$route, R_orig$absent$adm_def$route),
    "A3 가드판 = 원본의 '행렬 부재' 판(역할·입장 경로)", sprintf("g=%s/%s absent=%s/%s", fmt(R_g$pos$role_hi), fmt(R_g$pos$adm_def$route),
                                                          fmt(R_orig$absent$role_hi), fmt(R_orig$absent$adm_def$route)))
chk(!identical(R_g$pos$role_hi, "defense") && !identical(R_g$pos$role_lo, "defense") && identical(R_g$pos$adm_def$route, "S5"),
    "A3b defense 는 조건부 IC 근거로 나오지 않고 defense 입장 = S5(근거 미제공 fail-closed)")
chk(isTRUE(grepl("NA\\(as-of", R_g$pos$adm_def$reason)), "A3c 입장 사유에 미제공을 0 으로 적지 않는다(cond=NA(as-of …))", fmt(R_g$pos$adm_def$reason))
u <- R_g$pos$util_def
chk(is.list(u) && !inherits(u, "err") && isTRUE(is.na(u$utility_score)) && isTRUE(is.na(u$component_scores$conditional_value)) &&
      identical(u$utility_status, "unmeasured:cond_ic_asof_unprovided"),
    "A4 효용 U = NA · 성분 conditional_value = NA · 상태 = 미측정(가짜 w4 기여 없음)")
ua <- R_orig$absent$util_def
chk(is.numeric(ua$utility_score) && isTRUE(abs(ua$component_scores$conditional_value - 0.5) < 1e-9),
    "A4b [근거] 원본 '행렬 부재' 판은 cond_norm 0.5 로 가짜 기여를 남긴다(w4×0.5 — U=NA 선택의 이유)",
    sprintf("U=%s cond_norm=%s", fmt(ua$utility_score), fmt(ua$component_scores$conditional_value)))
chk(all(vapply(R_g, function(x) is.null(x$slate), logical(1))) && identical(unname(tools::md5sum(SLATE_OLD)), unname(SLATE_MD5)) &&
      identical(sort(list.files(SLATE_DIR)), "s5_research_slate_F1.json"),
    "A5 slate: 모든 상태에서 NULL · 파일 쓰기 0 · 기존 slate 바이트 불변")
STATES$pos()
invisible(quiet(sg_generate_research_slate_asof("F1", "STR_NEW")))
chk(!dir.exists(file.path(SB, "04_Research", "strategies", "STR_NEW")), "A5b slate: 새 전략 디렉터리도 만들지 않는다")
pw <- quiet(sg_generate_research_slate("F1", "STR_PWR"))
chk(!is.null(pw) && file.exists(file.path(SB, "04_Research/strategies/STR_PWR/stage_artifacts/s5_research_slate_F1.json")),
    "A5c [양성 대조] 원본은 같은 상태에서 slate 를 쓴다(가림이 차이를 만든다)")
S4c <- list(factor_id = "F1", delta_sharpe = .3, kospi_beat = TRUE)
chk(identical(quiet(sg_determine_role_asof(S2, S3_hi, S4c)), "core_alpha") &&
      identical(quiet(sg_role_admission_asof("diversifier", S4, S3_hi))$route, quiet(sg_role_admission("diversifier", S4, S3_hi))$route) &&
      identical(quiet(sg_role_admission_asof("core_alpha", S4c, S3_hi))$route, "S6"),
    "A6 과차단 없음 — core_alpha 판정·diversifier/core_alpha 입장은 원본과 같다")
fp <- tryCatch(environment(cic_blind(sg_determine_role, "x"))$file.path, error = function(e) function(...) NA_character_)
chk(identical(fp(SB, ".cache", "portfolio_gap_vector.json"), base::file.path(SB, ".cache", "portfolio_gap_vector.json")) &&
      !is.na(fp(SB, ".cache", "conditional_ic_matrix.csv")) && !file.exists(fp(SB, ".cache", "conditional_ic_matrix.csv")),
    "A7 가림 file.path — 다른 경로는 그대로, 행렬 경로만 부재 경로로")
chk(identical(cic_asof_provided(), FALSE), "A8 as-of 제공자 미채택(cic_asof_provided = FALSE — 채택은 도훈 결정)")
old_p <- cic_asof_provided; assign("cic_asof_provided", function() TRUE, envir = globalenv())
chk(inherits(quiet(sg_determine_role_asof(S2, S3_hi, S4)), "err"), "A8b 제공 표시만 켜면 멈춘다(구현 없는 as-of 경로 = fail-closed)")
assign("cic_asof_provided", old_p, envir = globalenv())
chk(identical(unname(tools::md5sum(ENGINE)), unname(REAL_MD5[1])) && identical(body(sg_determine_role), body(eval(Filter(function(e)
  is.call(e) && identical(e[[1]], as.name("<-")) && identical(as.character(e[[2]]), "sg_determine_role"), as.list(ex))[[1]][[3]]))) &&
    all(vapply(TARGETS, function(fn) identical(environment(get(fn, envir = globalenv())), globalenv()), logical(1))),
  "A9 엔진 파일·원본 함수 본문·환경 불변(가림은 사본에만)")

cat("--- B. 가림 우회 거부 ---\n")
syn <- function(s4) {
  proj <- PROJECT_ROOT
  cond_path <- file.path(proj, ".cache", "conditional_ic_matrix.csv")
  v <- 0
  if (file.exists(cond_path)) { m <- data.table::fread(cond_path); v <- m[Factor_Name == s4$factor_id]$conditional_value[1] }
  if (!is.na(v) && v > 0) "defense" else "diversifier"
}
mkv <- function(to) { b <- deparse(body(syn)); b2 <- gsub('cond_path <- file.path(proj, ".cache", "conditional_ic_matrix.csv")', to, b, fixed = TRUE)
  if (identical(b, b2)) stop("variant not applied"); f <- syn; body(f) <- parse(text = paste(b2, collapse = "\n"))[[1]]; f }
CIC_GLOBAL_PATH <- MAT
V <- list(
  V1_base_qualified = mkv('cond_path <- base::file.path(proj, ".cache", "conditional_ic_matrix.csv")'),
  V2_paste0         = mkv('cond_path <- paste0(proj, "/.cache/conditional_ic_matrix.csv")'),
  V3_list_files     = mkv('cond_path <- list.files(paste0(proj, "/.cache"), pattern = "^conditional_ic_matrix", full.names = TRUE)[1]'),
  V4_copy           = mkv('cond_path <- file.path(proj, ".cache", "cic_copy.csv"); file.copy(sprintf("%s/.cache/conditional_ic_matrix.csv", proj), cond_path, overwrite = TRUE)'),
  V5_helper         = mkv('cond_path <- CIC_GLOBAL_PATH'))
chk(!inherits(tryCatch(cic_blind(syn, "syn"), error = function(e) structure("", class = "err")), "err"),
    "B0 [음성 대조] 정규형(file.path 직접 인자) 합성 소비 함수는 가림을 받는다")
for (vn in names(V)) {
  r <- tryCatch(cic_blind(V[[vn]], vn), error = function(e) structure(conditionMessage(e), class = "err"))
  chk(inherits(r, "err") && grepl("fail-closed", r), sprintf("B1 [위반 주입] %s → cic_blind 거부(fail-closed)", vn), if (!inherits(r, "err")) "통과됨" else "")
}
V6x <- syn; body(V6x) <- parse(text = paste(gsub('if (file.exists(cond_path))', 'cond_path <- CIC_GLOBAL_PATH; if (file.exists(cond_path))',
                                                    deparse(body(syn)), fixed = TRUE), collapse = "\n"))[[1]]
b6 <- tryCatch(cic_blind(V6x, "V6x"), error = function(e) NULL)
if (!is.null(b6)) {
  outs <- vapply(c("pos", "neg"), function(s) { STATES[[s]](); b6(S4) }, character(1))
  chk(!identical(outs[["pos"]], outs[["neg"]]),
      "B2 [한계 실증] 정적 검사를 통과하는 변형(전역 경로 재대입)은 A 의 섭동 불변 검사가 잡는다(pos≠neg → 불변 red)",
      paste(outs, collapse = "/"))
} else ng("B2 V6x 가 정적 검사에서 이미 거부됨 — 한계 실증 픽스처 무효")
unlink(file.path(SB, ".cache", "cic_copy.csv"))

cat("--- C. 정적 봉인 ---\n")
CODE_EXT <- "\\.(R|r|sh|py|js)$"
md_scope <- function(p) grepl("^\\.claude/", p) || grepl("^02_Infrastructure/prompts/", p)
excluded <- function(p) grepl("(^|/)(_archive[^/]*|_retired[^/]*|[^/]*retired[^/]*)/", p) || grepl("^02_Infrastructure/docs/", p)
MAT_ALLOW <- c("02_Infrastructure/stage_gate_engine.R", "02_Infrastructure/validation/cond_ic_asof_guard.R",
               "02_Infrastructure/data/daily_refresh.sh", "02_Infrastructure/factor_db/build_factor_evidence.py",
               "02_Infrastructure/hooks/arm_gen_read_guard.sh")
# MAT_ALLOW 근거: 엔진 = 생산자(sg_compute_conditional_ic)+소비 4종(호출부 가림) · 가드 = 가림 경로 · daily_refresh = 생산 호출 ·
#   build_factor_evidence = 파생 저장소 생산자(설계 레인 소비 차단 = R2 · B7 = B08 as-of) · arm_gen_read_guard = 읽기 차단기
seal_scan <- function(root, files) {
  v <- character(0)
  for (p in files) {
    fp <- file.path(root, p); if (!file.exists(fp)) next
    txt <- tryCatch(readLines(fp, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
    has_t <- any(grepl(paste(TARGETS, collapse = "|"), txt)); has_m <- any(grepl("conditional_ic_matrix", txt, fixed = TRUE))
    if (!has_t && !has_m) next
    if (grepl("\\.[Rr]$", p)) {
      pd <- tryCatch(getParseData(parse(text = txt, keep.source = TRUE, encoding = "UTF-8")), error = function(e) NULL)
      if (is.null(pd)) { v <- c(v, paste0("unparseable:", p)); next }
      pd <- pd[pd$terminal, ]; pd <- pd[order(pd$line1, pd$col1), ]
      tok <- pd$token; tx <- pd$text
      strv <- ifelse(tok == "STR_CONST", gsub('^[\'"]|[\'"]$', "", tx), NA_character_)
      for (i in seq_along(tok)) {
        if (tok[i] == "SYMBOL_FUNCTION_CALL" && tx[i] %in% TARGETS) v <- c(v, sprintf("call:%s:%d:%s", p, pd$line1[i], tx[i]))
        if (tok[i] == "SYMBOL" && tx[i] %in% TARGETS) {
          nxt <- if (i < length(tok)) tok[i + 1] else ""
          if (!(p == "02_Infrastructure/stage_gate_engine.R" && nxt %in% c("LEFT_ASSIGN", "EQ_ASSIGN")))
            v <- c(v, sprintf("ref:%s:%d:%s", p, pd$line1[i], tx[i]))
        }
        if (tok[i] == "STR_CONST" && strv[i] %in% TARGETS && p != "02_Infrastructure/validation/cond_ic_asof_guard.R")
          v <- c(v, sprintf("str:%s:%d:%s", p, pd$line1[i], strv[i]))
        if (tok[i] == "STR_CONST" && grepl("conditional_ic_matrix", tx[i], fixed = TRUE) && !(p %in% MAT_ALLOW))
          v <- c(v, sprintf("matrix:%s:%d", p, pd$line1[i]))
      }
    } else if (grepl("\\.(sh|py|js)$", p)) {
      cm <- if (grepl("\\.js$", p)) "^\\s*//" else "^\\s*#"
      code <- !grepl(cm, txt)
      hitc <- which(code & grepl(sprintf("(?<![A-Za-z0-9_])(%s)\\s*\\(", paste(TARGETS, collapse = "|")), txt, perl = TRUE))
      for (i in hitc) v <- c(v, sprintf("call:%s:%d", p, i))
      if (!(p %in% MAT_ALLOW)) for (i in which(code & grepl("conditional_ic_matrix", txt, fixed = TRUE))) v <- c(v, sprintf("matrix:%s:%d", p, i))
    } else if (grepl("\\.md$", p) && md_scope(p)) {
      hitc <- which(grepl(sprintf("(?<![A-Za-z0-9_])(%s)\\s*\\(", paste(TARGETS, collapse = "|")), txt, perl = TRUE))
      for (i in hitc) v <- c(v, sprintf("mdcall:%s:%d", p, i))
      for (i in which(grepl("conditional_ic_matrix", txt, fixed = TRUE))) {
        w <- txt[max(1, i - 3):min(length(txt), i + 3)]
        if (!any(grepl("D-E-V6", w, fixed = TRUE))) v <- c(v, sprintf("mdmark:%s:%d", p, i))
      }
    }
  }
  v
}
gl <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(SEAL_GIT), "ls-files", "--cached", "--others", "--exclude-standard",
                                                 "--", "02_Infrastructure", ".claude"), stdout = TRUE, stderr = FALSE)),
               error = function(e) character(0))
FILES <- unique(c(gl, "02_Infrastructure/validation/cond_ic_asof_guard.R", "02_Infrastructure/R/hook_batch_runner.R",
                  "02_Infrastructure/pipeline/v55_stage_gate_extensions.R"))
FILES <- FILES[grepl(CODE_EXT, FILES) | (grepl("\\.md$", FILES) & vapply(FILES, md_scope, logical(1)))]
FILES <- FILES[!vapply(FILES, excluded, logical(1))]
chk(length(gl) > 200L, "C0 봉인 파일 목록 확보(git ls-files)", sprintf("%d개 · git=%s", length(gl), SEAL_GIT))
viol <- seal_scan(CODE, FILES)
chk(!length(viol), "C1 운영 트리 봉인: 소비 함수 4종 직접 호출·참조 0 · 행렬 파일명 = 허용 목록뿐 · .md 언급엔 D-E-V6 표식",
    paste(head(viol, 8), collapse = " | "))
chk(any(grepl("sg_determine_role_asof\\(", readLines(HBR, warn = FALSE, encoding = "UTF-8"))) &&
      sum(grepl("_asof\\(", readLines(V55, warn = FALSE, encoding = "UTF-8"))) >= 2L,
    "C1b 호출부 3곳이 가드 래퍼를 부른다(hook_determine_role · v55 역할/입장)")
FX <- file.path(SB, "sealfx"); dir.create(file.path(FX, "02_Infrastructure"), recursive = TRUE); dir.create(file.path(FX, ".claude"), recursive = TRUE)
fx <- list(
  "02_Infrastructure/x1.R" = "role <- sg_determine_role(s2, s3, s4)",
  "02_Infrastructure/x2.R" = c('f <- get("sg_role_admission")', 'do.call("sg_generate_research_slate", list(1, 2))'),
  "02_Infrastructure/x3.R" = "g <- sg_compute_role_utility",
  "02_Infrastructure/x4.sh" = "Rscript -e \"source('x.R'); sg_role_admission('defense', s4, s3)\"",
  "02_Infrastructure/x5.R" = 'm <- data.table::fread(file.path(".cache", "conditional_ic_matrix.csv"))',
  ".claude/x6.md" = "- `.cache/conditional_ic_matrix.csv` → 조건부 IC 높은 팩터 우선",
  "02_Infrastructure/n1.R" = c("# sg_determine_role(s2, s3, s4) — 주석", "r <- sg_determine_role_asof(s2, s3, s4)",
                               "q <- sg_determine_role_v55(NULL, s2, s3, s4)", 'cat("see sg_determine_role docs")'),
  "02_Infrastructure/n2.sh" = "# sg_role_admission('defense', s4, s3) 주석",
  ".claude/n3.md" = c("### conditional_ic_matrix", "전기간 스냅샷 — 선정 입력 금지(D-E-V6)"),
  "02_Infrastructure/stage_gate_engine.R" = c("sg_determine_role <- function(s2, s3, s4) 1",
                                              'p <- file.path(".cache", "conditional_ic_matrix.csv")'))
for (nm in names(fx)) { dir.create(dirname(file.path(FX, nm)), recursive = TRUE, showWarnings = FALSE); writeLines(fx[[nm]], file.path(FX, nm), useBytes = TRUE) }
fv <- seal_scan(FX, names(fx))
for (bad in c("x1.R", "x2.R", "x3.R", "x4.sh", "x5.R", "x6.md"))
  chk(any(grepl(bad, fv, fixed = TRUE)), sprintf("C2 [위반 주입] %s 적발", bad))
chk(sum(grepl("x2.R", fv, fixed = TRUE)) == 2L, "C2b 문자열 이름 참조(get·do.call) 2건 모두 적발")
chk(!any(grepl("n1.R|n2.sh|n3.md|stage_gate_engine.R", fv)), "C3 [음성 대조] 주석·*_asof·*_v55·문장 속 이름·표식 달린 언급·엔진 정의는 통과",
    paste(grep("n1.R|n2.sh|n3.md|stage_gate_engine.R", fv, value = TRUE), collapse = " | "))

cat("--- D. 호출부 실행(자식 Rscript · 합성 루트) ---\n")
CR <- file.path(SB, "child"); RS <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
for (p in c("02_Infrastructure/config.R", "02_Infrastructure/stage_gate_engine.R", "02_Infrastructure/validation/stage_artifact_schemas.R",
            "02_Infrastructure/validation/cond_ic_asof_guard.R", "02_Infrastructure/R/hook_batch_runner.R",
            "02_Infrastructure/pipeline/v55_stage_gate_extensions.R")) {
  dir.create(dirname(file.path(CR, p)), recursive = TRUE, showWarnings = FALSE); file.copy(rel(p), file.path(CR, p), overwrite = TRUE)
}
for (d in c(".cache", "04_Research/strategies/STR_TD/stage_artifacts", "06_Registry", "stage_artifacts")) dir.create(file.path(CR, d), recursive = TRUE, showWarnings = FALSE)
SD <- file.path(CR, "04_Research/strategies/STR_TD")
write_json(list(factor_id = "F1", ic_ir = .2), file.path(SD, "stage_artifacts/s2_profile_F1.json"), auto_unbox = TRUE)
write_json(list(factor_id = "F1", max_abs_corr_db = .2), file.path(SD, "stage_artifacts/s3_orthogonality_F1.json"), auto_unbox = TRUE)
S4F <- file.path(SD, "stage_artifacts/s4_integration_F1.json")
write_json(list(factor_id = "F1", delta_sharpe = .1, kospi_beat = FALSE), S4F, auto_unbox = TRUE)
CMAT <- file.path(CR, ".cache", "conditional_ic_matrix.csv")
cstate <- function(s) switch(s,
  pos = fwrite(syn_mat(c(.05, -.03, .04, .06)), CMAT), neg = fwrite(syn_mat(c(-.05, .03, -.04, -.06)), CMAT), absent = unlink(CMAT),
  wpos = fwrite(data.table(Factor_Name = c("a", "b"), Q07 = c(.03, .02)), CMAT), wneg = fwrite(data.table(Factor_Name = c("a", "b"), Q07 = c(-.03, -.02)), CMAT))
writeLines(c('a <- commandArgs(TRUE); setwd(Sys.getenv("QM_ROOT"))',
             'if (identical(a[3], "dt")) suppressMessages(library(data.table))',
             'suppressMessages(source(a[1]))',
             'if (a[2] == "role") cat("ROLE=", hook_determine_role(a[4], a[5]), "\\n", sep = "") else hook_quant_factcheck(\'["Q07"]\', "H_T")'),
           file.path(CR, "_child.R"))
child <- function(hbr, mode, dt = "nodt") {
  old <- Sys.getenv(c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER", "R_PROFILE_USER"), unset = NA)
  Sys.setenv(QM_ROOT = CR, CLAUDE_PROJECT_DIR = CR, R_ENVIRON_USER = EMPTY_ENV, R_PROFILE_USER = EMPTY_ENV)
  on.exit(for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)))
  out <- tryCatch(suppressWarnings(system2(RS, c("--no-environ", shQuote(file.path(CR, "_child.R")), shQuote(hbr), mode, dt,
                                                 shQuote(SD), shQuote(S4F)), stdout = TRUE, stderr = FALSE)), error = function(e) character(0))
  if (mode == "role") { r <- grep("^ROLE=", out, value = TRUE); if (length(r)) sub("^ROLE=", "", r[length(r)]) else NA_character_ }
  else { j <- grep('^\\{"hypothesis_id"', out, value = TRUE); if (length(j)) tryCatch(fromJSON(j[length(j)])$kr_ic_sign$Q07 %||% NA_character_, error = function(e) NA_character_) else NA_character_ }
}
HBR_C <- file.path(CR, "02_Infrastructure/R/hook_batch_runner.R")
hb <- readLines(HBR_C, warn = FALSE, encoding = "UTF-8")
MUT1 <- file.path(CR, "mut_role.R"); m1 <- gsub("sg_determine_role_asof(s2, s3, s4)", "sg_determine_role(s2, s3, s4)", hb, fixed = TRUE)
writeLines(m1, MUT1, useBytes = TRUE)
roles_g <- vapply(c("pos", "neg", "absent"), function(s) { cstate(s); child(HBR_C, "role") }, character(1))
roles_m <- if (!identical(m1, hb)) vapply(c("pos", "neg"), function(s) { cstate(s); child(MUT1, "role") }, character(1)) else c(pos = NA, neg = NA)
cat(sprintf("  [값] D1 배포판 %s · D1b 돌연변이 %s
", paste(roles_g, collapse = "/"), paste(roles_m, collapse = "/")))
chk(!anyNA(roles_g) && length(unique(roles_g)) == 1L && !("defense" %in% roles_g),
    "D1 hook_determine_role(배포판): 행렬 pos/neg/부재에서 역할 불변 · defense 아님", paste(roles_g, collapse = "/"))
chk(!anyNA(roles_m) && !identical(roles_m[["pos"]], roles_m[["neg"]]),
    "D1b [돌연변이] 원본 호출 복원판은 행렬에 반응한다(pos≠neg — D1 의 검정력)", paste(roles_m, collapse = "/"))
# D1c (적대검증 추가) — 불변만으로는 '가드 미적재 → 오류 → 기본값 core_alpha' 도 통과한다(역할이 늘 core_alpha 로 굳는 과차단).
#   배포판 역할 = 원본의 '행렬 부재' 판 역할이어야 한다(가드판 = 원본 부재 판 — A3 의 호출부 판).
role_abs_orig <- if (!identical(m1, hb)) { cstate("absent"); child(MUT1, "role") } else NA_character_
chk(!is.na(role_abs_orig) && identical(unname(roles_g[["pos"]]), role_abs_orig),
    "D1c hook_determine_role(배포판) = 원본의 행렬 부재 판 역할(가드 미적재·오류 기본값 core_alpha 로 굳지 않는다)",
    sprintf("배포판=%s 원본부재=%s", roles_g[["pos"]], role_abs_orig))
OLD_BLOCK <- c('    cic_path <- file.path(".", ".cache", "conditional_ic_matrix.csv")', '    if (file.exists(cic_path)) {',
               '      tryCatch({', '        cic <- fread(cic_path)', '        for (fac in factors) {', '          if (fac %in% names(cic)) {',
               '            ic_col <- cic[[fac]]', '            ic_col <- ic_col[!is.na(ic_col)]',
               '            if (length(ic_col) > 0) kr_ic_sign[[fac]] <- if (mean(ic_col) > 0) "+" else "-"',
               '          }', '        }', '      }, error = function(e_cic) NULL)', '    }')
anc <- which(hb == "    result <- list(")
anc <- anc[length(anc)]
MUT2 <- file.path(CR, "mut_cic.R")
if (length(anc) == 1L) writeLines(c(hb[seq_len(anc - 1L)], OLD_BLOCK, hb[anc:length(hb)]), MUT2, useBytes = TRUE)
sg_g <- vapply(c("wpos", "wneg", "absent"), function(s) { cstate(s); child(HBR_C, "qf", "dt") }, character(1))
sg_m <- if (file.exists(MUT2)) vapply(c("wpos", "wneg"), function(s) { cstate(s); child(MUT2, "qf", "dt") }, character(1)) else c(wpos = NA, wneg = NA)
cat(sprintf("  [값] D2 배포판 %s · D2b 돌연변이 %s
", paste(sg_g, collapse = "/"), paste(sg_m, collapse = "/")))
chk(!anyNA(sg_g) && length(unique(sg_g)) == 1L, "D2 hook_quant_factcheck(배포판): 행렬 섭동에 kr_ic_sign 불변", paste(sg_g, collapse = "/"))
chk(!anyNA(sg_m) && !identical(sg_m[["wpos"]], sg_m[["wneg"]]), "D2b [돌연변이] 구판 행렬 블록 복원 → kr_ic_sign 이 반응한다(D2 의 검정력)",
    paste(sg_m, collapse = "/"))
E3 <- new.env(parent = globalenv()); invisible(capture.output(sys.source(V55, envir = E3)))
v_role <- vapply(names(STATES), function(s) { STATES[[s]](); fmt(quiet(E3$sg_determine_role_v55(NULL, S2, S3_hi, S4))) }, character(1))
v_adm <- lapply(names(STATES), function(s) { STATES[[s]](); quiet(E3$sg_role_admission_v55("defense", S4, S3_hi)) })
chk(length(unique(v_role)) == 1L && !("defense" %in% v_role) && all(vapply(v_adm, function(a) identical(a$route, "S5"), logical(1))),
    "D3 v55 역할·defense 입장: 모든 섭동에서 불변(defense 아님 · S5)", paste(unique(v_role), collapse = "/"))
chk(identical(quiet(E3$sg_determine_role_v55(list(expected_role = "cash_allocation"), S2, S3_hi, S4)), "cash_allocation"),
    "D3b v55 힌트 역할 경로는 그대로(과차단 없음)")
BARE <- new.env(parent = baseenv()); for (fn in c(TARGETS, "%||%")) assign(fn, get(fn, envir = globalenv()), envir = BARE)
E4 <- new.env(parent = BARE); invisible(capture.output(sys.source(V55, envir = E4)))
r4 <- quiet(E4$sg_determine_role_v55(NULL, S2, S3_hi, S4))
a4 <- quiet(E4$sg_role_admission_v55("core_alpha", list(factor_id = "F1", delta_sharpe = .3, kospi_beat = TRUE), S3_hi))
chk(inherits(r4, "err") && grepl("fail-closed", r4$err), "D4 v55 가드 부재 → 역할 판정 멈춤(구판 'diversifier' 폴백·원본 직접 호출 없음)")
chk(is.list(a4) && identical(a4$ok, FALSE) && identical(a4$route, "S5"), "D4b v55 가드 부재 → 입장 불가(구판 ok=TRUE 'v55 default' 없음)",
    fmt(if (is.list(a4) && !inherits(a4, "err")) a4$reason else a4))
BARE2 <- new.env(parent = baseenv()); assign("%||%", get("%||%", envir = globalenv()), envir = BARE2)
for (fn in c("sg_role_admission_asof", "cic_blind", "cic_marker_heads", ".cic_policy", "cic_asof_provided", ".cic_blinded_path", ".cic_orig", ".CIC_MARK_RX"))
  assign(fn, get(fn, envir = globalenv()), envir = BARE2)
E5 <- new.env(parent = BARE2); invisible(capture.output(sys.source(V55, envir = E5)))
a5 <- quiet(E5$sg_role_admission_v55("diversifier", S4, S3_hi))
chk(is.list(a5) && identical(a5$ok, FALSE) && isTRUE(grepl("^fail-closed", a5$reason)), "D4c v55 가드는 있으나 엔진 원본 부재 → 가드 오류를 입장 불가로(fail-closed)",
    fmt(if (is.list(a5) && !inherits(a5, "err")) a5$reason else a5))

cat("--- E. 문언 ---\n")
pit <- readLines(PITMD, warn = FALSE, encoding = "UTF-8")
sec <- function(h) { i <- which(startsWith(pit, h)); if (length(i) != 1L) return(character(0)); j <- which(startsWith(pit, "## ") & seq_along(pit) > i)
  pit[(i + 1L):(if (length(j)) j[1] - 1L else length(pit))] }
ORG <- "- ★예외(ORGANIC-DE 2026-09-25 도훈 승인): 유기적 강화 컨트롤러의 **자동 결정 입력**에 한해 τ_D 이후 성과를 제외한다(기계 입력 holdout · B08 대비 완화 명시). 사람·등급·Judge·BOOK·전략 구현·격자 선택은 전기간 그대로."
lb <- sec("## Lockbox — 폐지"); lb <- lb[nzchar(trimws(lb))]
chk(sum(pit == ORG) == 1L && length(lb) && identical(lb[length(lb)], ORG), "E1 pit.md Lockbox 절 끝 = ORGANIC-DE 예외 문장(결정문 그대로 · 1회)")
v6 <- sec("## V6 Gap-Directed")
chk(any(grepl("Usable_Date <= 결정 시점`의 조건부 IC", v6, fixed = TRUE)) && any(grepl("as-of 판 미제공 시 사용 안 함", v6, fixed = TRUE)) &&
      !any(grepl("conditional_ic_matrix.csv` → 조건부 IC 높은 팩터 우선", v6, fixed = TRUE)),
    "E2 pit.md V6 절 = Usable_Date <= 결정 시점 조건부 IC · as-of 판 미제공 시 사용 안 함(구 문언 없음)")

cat("--- Z. 격리 ---\n")
chk(identical(unname(tools::md5sum(REAL)), unname(REAL_MD5)), "Z1 운영(QM_ROOT) 코드·행렬 해시 불변")
unlink(SB, recursive = TRUE, force = TRUE)
finish()
