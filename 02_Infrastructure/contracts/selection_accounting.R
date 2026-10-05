# selection_accounting.R — 선택 회계 계약 (플랜 qvest-1-drifting-eclipse P1-03) — ★이 판은 sa_subwindow 하나만 싣는다
# =============================================================================
# 범위(2026-09-25 밤 · P2 통합 구현 ③): P1-03 이 이 파일에 둘 항목(N_eff · DSR · CSCV-PBO · 짝지은 블록 부트스트랩 공용화 ·
#   가족 조정 Calmar · retention 감쇠귀무) 중 **sa_subwindow(절단판 진단)만** 먼저 싣는다. 나머지는 스텁 없이 부재다 —
#   이름만 있는 함수는 '있는 것처럼 보이는 계기'가 된다(양성 대조 없는 계기는 방어선으로 세지 않는다 · pit.md 존치 교훈).
#
# ★라벨: "진단 — 등급 대체 아님". 절단판 essence 는 권위 등급이 아니다(authoritative_remeasure.json::essence_grade 만 인용).
#   사전등록(PR-L1 성공 ③ · 실패 · 멈춤 STOP_L1_TRUNC / PR-L2 2차)이 이 값을 '2024-12 절단판 ΔCalmar ≥ 0 ∧ Δretention > 0' 로 소비한다.
#   절단판도 2016~24 를 본 상태의 설계라 완전한 사전성이 없다(플랜 P2 공통 규약) — '확증'이 아니라 반증 시도의 한 축.
#
# sa_subwindow(artifact_dir, cut = <설정 cut id>, end = NULL):
#   ① 입력 판 = 권위 재측정과 같은 판(remeasure_<prefer>_* 형제가 하나면 그것 · regime_key 로 지정 가능) — bt_result.rds + authoritative_remeasure.json.
#   ② ★항등 자기검사(매 호출): 저장 bt 표(nav · period_returns · holdings · benchmark_returns)로 계약 표(metrics · benchmark_compare ·
#      rolling_metrics · drawdowns)를 **정본 builder 로 다시 짓고** audit → essence_score(저장 채점 인자 n_trials·selection_type) 한 값이
#      authoritative_remeasure.json essence 와 identical 이어야 한다(아니면 stop — 이 산출물에서는 재구성 경로를 믿을 수 없다).
#   ③ 절단: 네 표를 date ≤ end 로 자른 뒤 ②와 같은 경로로 essence. end ≥ 산출 마지막 날이면 절단 없음 = ② 그 자체(비트 동일).
#      하네스는 인과적이다(보유창 수익·비용은 그날까지의 정보로만 기장) — 표 절단 = 데이터 끝이 end 였던 시뮬레이션(검사 [S2] 가 독립 경로로 대조).
#   절단일은 설정(selection_accounting_config.json subwindow.cuts)에서만 — end 인자 직접 지정은 진단용이며 산출물에 end_source="argument" 로 남는다
#   (사전등록 판정은 cut id 산출만 받아야 한다 — 절단일 쇼핑 차단).
#   ★집행(2026-09-26): 최상위 수치 end_from_config(설정 cut id = 1 · end 인자 = 0)를 싣고, 소비자 rf_prereg.R 판정 입력 검사가
#     prereg_config verdict.contracts.sa_subwindow.pinned 로 1 과 대조한다 — end 인자 산출은 판정 입력에서 거부된다(선언이 아니라 소비 쪽 집행).
# 출력 = 최상위 measurement_regime(권위 재측정의 실현 규약 그대로 — exec_price · key · harness_md5 · cost_model_version · selection_type ·
#   n_trials_cumulative) + window + essence(절단판) + identity(②) + input 지문. sa_write() = 명시 out_dir 에만(원자 쓰기).
#
# 재사용(사본 금지): backtest_result_contract.R(build_metrics · build_benchmark_compare · build_rolling_metrics · build_drawdowns · AUDIT_COLS) ·
#   audit_bt_result.R · essence_score.R — remeasure_from_holdings.R 와 같은 방식(source local 환경 · 채점 중에만 QM_ROOT/CLAUDE_PROJECT_DIR = 루트).
# 설정 = 02_Infrastructure/contracts/selection_accounting_config.json(없으면 멈춘다). 검사 = 08_Tests/contracts/test_selection_accounting.R
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

SA_VERSION <- "selection_accounting_v0_subwindow"
SA_LABEL   <- "진단 — 등급 대체 아님"
.sa_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.SA_SELF_DIR <- local({
  hit <- NA_character_
  for (i in rev(seq_len(sys.nframe()))) {
    fr <- tryCatch(sys.frame(i), error = function(e) NULL)
    if (is.null(fr)) next
    for (nm in c("ofile", "file")) {
      v <- tryCatch(get0(nm, envir = fr, inherits = FALSE), error = function(e) NULL)
      if (is.character(v) && length(v) == 1L && grepl("selection_accounting\\.R$", v)) { hit <- v; break }
    }
    if (!is.na(hit)) break
  }
  if (is.na(hit)) NA_character_ else normalizePath(dirname(hit), winslash = "/", mustWork = FALSE)
})

#' 루트 — 명시 인자 > CLAUDE_PROJECT_DIR > QM_ROOT. 표지 = CLAUDE.md + 06_Registry(essence .graduation_root 와 같은 규약) · 운영 리터럴 폴백 없음
sa_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""))) {
    if (!is.character(p) || !nzchar(p)) next
    p <- sub("/+$", "", gsub("\\\\", "/", p))
    if (file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry")) && dir.exists(file.path(p, "02_Infrastructure"))) return(p)
  }
  stop("[sa] 루트를 찾지 못했다(CLAUDE.md·06_Registry 표지) — root 인자 또는 CLAUDE_PROJECT_DIR/QM_ROOT")
}

sa_config <- function(root = NULL, path = NULL) {
  root <- sa_root(root)
  p <- .sa_or(path, file.path(root, "02_Infrastructure/contracts/selection_accounting_config.json"))
  if (!file.exists(p)) stop("[sa] 설정 부재: ", p, " — 기본값을 지어내지 않는다(fail-closed)")
  cfg <- fromJSON(p, simplifyVector = FALSE)
  sw <- cfg$subwindow
  if (!is.list(sw) || !is.list(sw$cuts) || !length(sw$cuts) || !nzchar(.sa_or(sw$prefer_exec_price, "")))
    stop("[sa] 설정 subwindow(cuts · prefer_exec_price) 부재")
  for (k in names(sw$cuts)) {
    e <- tryCatch(as.Date(sw$cuts[[k]]$end), error = function(e) NA)
    if (!length(e) || is.na(e)) stop("[sa] subwindow.cuts.", k, ".end 가 날짜가 아니다")
    if (!nzchar(.sa_or(sw$cuts[[k]]$source, ""))) stop("[sa] subwindow.cuts.", k, ".source(근거) 부재")
  }
  cfg$.path <- gsub("\\\\", "/", p); cfg$.md5 <- unname(as.character(tools::md5sum(p)))
  cfg
}

.sa_contract_dir <- function(root) {
  if (!is.na(.SA_SELF_DIR) && file.exists(file.path(.SA_SELF_DIR, "essence_score.R"))) return(.SA_SELF_DIR)
  file.path(root, "02_Infrastructure", "contracts")
}

.sa_with_root <- function(root, expr) {
  old <- c(QM_ROOT = Sys.getenv("QM_ROOT", NA), CLAUDE_PROJECT_DIR = Sys.getenv("CLAUDE_PROJECT_DIR", NA))
  owd <- getwd()
  on.exit({
    for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k))
    setwd(owd)
  }, add = TRUE)
  Sys.setenv(QM_ROOT = root, CLAUDE_PROJECT_DIR = root); setwd(root)
  force(expr)
}

.SA_DEP <- new.env(parent = globalenv())   # 정본 계약이 base·패키지 함수를 찾도록
.sa_deps <- function(root) {
  cd <- .sa_contract_dir(root)
  if (isTRUE(.SA_DEP$.loaded) && identical(.SA_DEP$.dir, cd)) return(invisible(.SA_DEP))
  for (f in c("backtest_result_contract.R", "audit_bt_result.R", "essence_score.R"))
    if (!file.exists(file.path(cd, f))) stop(sprintf("[sa] 정본 계약 부재: %s/%s", cd, f))
  .sa_with_root(root, capture.output(suppressMessages({
    source(file.path(cd, "backtest_result_contract.R"), local = .SA_DEP, encoding = "UTF-8")
    source(file.path(cd, "audit_bt_result.R"), local = .SA_DEP, encoding = "UTF-8")
    source(file.path(cd, "essence_score.R"), local = .SA_DEP, encoding = "UTF-8")
  })))
  for (fn in c("build_metrics", "build_benchmark_compare", "build_rolling_metrics", "build_drawdowns", "audit_bt_result", "essence_score", ".essence_af"))
    if (!exists(fn, envir = .SA_DEP, inherits = FALSE)) stop("[sa] 정본 함수 부재: ", fn)
  if (!exists("AUDIT_COLS", envir = .SA_DEP, inherits = FALSE)) stop("[sa] AUDIT_COLS 부재")
  .SA_DEP$.loaded <- TRUE; .SA_DEP$.dir <- cd
  invisible(.SA_DEP)
}

#' 입력 판 해석 — remeasure_<prefer>_* 형제가 하나면 그것(권위 재측정 판) · regime_key 지정 가능 · 아니면 디렉터리 자신
sa_resolve <- function(artifact_dir, prefer = "close_t1", regime_key = NULL) {
  ad <- sub("/+$", "", gsub("\\\\", "/", artifact_dir))
  if (!dir.exists(ad)) stop("[sa] 산출물 디렉터리 부재: ", ad)
  sib <- list.dirs(ad, recursive = FALSE, full.names = TRUE)
  sib <- sib[grepl(paste0("^remeasure_", prefer, "_"), basename(sib))]
  if (!is.null(regime_key)) sib <- sib[basename(sib) == paste0("remeasure_", regime_key)]
  if (length(sib) > 1L) stop("[sa] 형제 판이 여럿이다 — regime_key 로 지정하라: ", paste(basename(sib), collapse = ","))
  use <- if (length(sib) == 1L) gsub("\\\\", "/", sib) else ad
  need <- file.path(use, c("bt_result.rds", "authoritative_remeasure.json"))
  if (!all(file.exists(need))) stop("[sa] 입력 부재(bt_result.rds · authoritative_remeasure.json): ", use)
  list(dir = use, of_artifact = ad, basis = if (length(sib) == 1L) paste0("sibling:", basename(use)) else "artifact_dir")
}

# 계약 표 재구성(정본 builder · build_bt_result 와 같은 호출 순서·인자) → audit → essence
.sa_rebuild_score <- function(bt0, nav, pr, h, br, nt, st, root) {
  D <- .SA_DEP
  run_id <- as.character(bt0$manifest$run_id[1]); sid <- as.character(bt0$manifest$strategy_id[1])
  freq <- unique(as.character(bt0$period_returns$frequency)); freq <- freq[!is.na(freq)]
  if (length(freq) != 1L) stop("[sa] period_returns.frequency 가 하나가 아니다: ", paste(freq, collapse = ","))
  af <- D$.essence_af(as.data.table(bt0$metrics))           # 저장 계약 표가 쓴 연환산 인자(정본 판독 함수)
  .sa_with_root(root, {
    metrics <- NULL; bc <- NULL; rm_ <- NULL; dd <- NULL; bt <- NULL; es <- NULL
    capture.output(suppressMessages({
      metrics <- D$build_metrics(nav, pr, h, run_id, sid, freq, af)
      bc <- D$build_benchmark_compare(pr, br, run_id, sid, af)
      rm_ <- D$build_rolling_metrics(pr, br, run_id, sid)
      dd <- D$build_drawdowns(pr, br, run_id, sid)
    }))
    audit <- data.table(matrix(nrow = 0, ncol = length(D$AUDIT_COLS), dimnames = list(NULL, D$AUDIT_COLS)))
    bt <- list(manifest = bt0$manifest, strategy_spec = bt0$strategy_spec, nav = nav, period_returns = pr, holdings = h,
               benchmark_returns = br, metrics = metrics, benchmark_compare = bc, rolling_metrics = rm_, drawdowns = dd, audit = audit)
    class(bt) <- c("bt_result", "list")
    capture.output(bt <- suppressMessages(D$audit_bt_result(bt)))
    capture.output(es <- suppressWarnings(suppressMessages(D$essence_score(bt, n_trials_cumulative = nt, selection_type = st, sidecar_log = FALSE))))
    list(bt = bt, es = es)
  })
}

.sa_json_rt <- function(x) fromJSON(toJSON(x, auto_unbox = TRUE, digits = NA, na = "null", null = "null"), simplifyVector = TRUE)
.sa_md5 <- function(p) unname(as.character(tools::md5sum(p)))

#' 절단판 진단. cut = 설정 subwindow.cuts 의 id(판정용) · end = 날짜 직접(진단용 — end_source 에 남는다). 둘 다 없으면 설정 default_cut.
#' @param verify_identity TRUE(기본) = 전 구간 재구성 essence 가 권위 산출과 identical 인지 매번 확인(아니면 stop)
sa_subwindow <- function(artifact_dir, cut = NULL, end = NULL, root = NULL, cfg = NULL, regime_key = NULL, verify_identity = TRUE) {
  root <- sa_root(root); cfg <- .sa_or(cfg, sa_config(root)); sw <- cfg$subwindow
  if (!is.null(cut) && !is.null(end)) stop("[sa] cut 과 end 를 함께 줄 수 없다")
  if (is.null(end)) {
    cut <- .sa_or(cut, sw$default_cut)
    if (is.null(cut) || is.null(sw$cuts[[cut]])) stop("[sa] 설정에 없는 절단 id: ", format(cut))
    end_d <- as.Date(sw$cuts[[cut]]$end); end_src <- paste0("config:subwindow.cuts.", cut)
  } else {
    end_d <- as.Date(end); if (is.na(end_d)) stop("[sa] end 가 날짜가 아니다"); end_src <- "argument"; cut <- NA_character_
  }
  .sa_deps(root)
  src <- sa_resolve(artifact_dir, prefer = sw$prefer_exec_price, regime_key = regime_key)
  bp <- file.path(src$dir, "bt_result.rds"); ap <- file.path(src$dir, "authoritative_remeasure.json")
  bt0 <- readRDS(bp); au <- fromJSON(ap, simplifyVector = FALSE)
  mr <- .sa_or(au$measurement_regime, list())
  nt <- suppressWarnings(as.integer(.sa_or(mr$n_trials_cumulative, au$n_trials_cumulative))[1])
  st <- as.character(.sa_or(mr$selection_type, au$selection_type))[1]
  if (!is.finite(nt) || nt < 1L || !(st %in% c("chain", "sweep"))) stop("[sa] 저장 채점 인자(n_trials_cumulative·selection_type) 판독 불가 — 같은 채점을 재현할 수 없다")
  if (!nzchar(.sa_or(mr$exec_price, ""))) stop("[sa] 권위 산출에 measurement_regime.exec_price 가 없다 — 실현 규약 재도출 불가")
  tb <- function(x) { x <- as.data.table(x); if ("date" %in% names(x)) x[, date := as.Date(date)]; x }
  nav <- tb(bt0$nav); pr <- tb(bt0$period_returns); h <- tb(bt0$holdings); br <- tb(bt0$benchmark_returns)
  if (!nrow(pr)) stop("[sa] period_returns 가 비었다")
  last <- max(pr$date); first <- min(pr$date)
  # ② 항등 자기검사 — 저장 표 그대로 재구성한 essence = 권위 산출(JSON 왕복 비교)
  ident <- NULL
  if (isTRUE(verify_identity) || end_d >= last) {
    full <- .sa_rebuild_score(bt0, copy(tb(bt0$nav)), copy(tb(bt0$period_returns)), copy(tb(bt0$holdings)), copy(tb(bt0$benchmark_returns)), nt, st, root)
    ess_same <- identical(.sa_json_rt(full$es$essence), .sa_json_rt(au[["essence"]]))
    grd_same <- identical(as.character(full$es$grade), as.character(au$essence_grade))
    ident <- list(applicable = TRUE, essence_identical = ess_same, grade_identical = grd_same,
                  rule = "저장 표 → 정본 builder 재구성 → audit → essence_score(저장 채점 인자) 가 authoritative_remeasure.json 과 identical")
    if (!ess_same || !grd_same)
      stop(sprintf("[sa] 항등 자기검사 실패(essence %s · grade %s) — 이 산출물의 재구성 경로를 믿을 수 없다(채점 코드·문턱이 산출 뒤 바뀌었을 수 있다 · 재측정판을 쓸 것): %s",
                   ess_same, grd_same, src$dir))
  }
  truncated <- end_d < last
  if (!truncated) { es <- full$es } else {
    keep <- function(x) x[date <= end_d]
    nav_t <- keep(nav); pr_t <- keep(pr); h_t <- keep(h); br_t <- keep(br)
    if (!nrow(pr_t)) stop(sprintf("[sa] 절단일 %s 이전 수익이 없다(첫 수익일 %s)", format(end_d), format(first)))
    es <- .sa_rebuild_score(bt0, nav_t, pr_t, h_t, br_t, nt, st, root)$es
  }
  n_used <- if (truncated) sum(pr$date <= end_d) else nrow(pr)
  list(contract = "sa_subwindow", label = SA_LABEL, version = SA_VERSION, created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
       note = paste0("진단 — 등급 대체 아님. 절단판 essence = 저장 계약 표를 date ≤ end 로 잘라 정본 builder·audit·essence_score(저장 채점 인자)로 다시 낸 값. ",
                     "권위 등급은 authoritative_remeasure.json::essence_grade 만. 절단판도 절단 뒤 구간을 본 설계 — 반증 시도의 한 축(플랜 P2)."),
       measurement_regime = list(exec_price = mr$exec_price, key = .sa_or(mr$key, mr$regime), harness_md5 = mr$harness_md5,
                                 cost_model_version = mr$cost_model_version, selection_type = st, n_trials_cumulative = nt,
                                 basis = "authoritative_remeasure.json measurement_regime(권위 재측정의 실현값)"),
       window = list(cut_id = cut, end = format(end_d), end_source = end_src, first = format(first), last_full = format(last),
                     last_used = format(if (truncated) max(pr$date[pr$date <= end_d]) else last),
                     n_days_full = nrow(pr), n_days_used = n_used, truncated = truncated),
       end_from_config = as.integer(startsWith(end_src, "config:")),   # 최상위 수치 — 소비자 pinned 대조 키(1 만 판정 입력)
       identity = ident,
       essence = es$essence, grade_diagnostic = es$grade, grade_diagnostic_note = "절단판 등급 산식 값 — 권위 등급 아님(인용 금지)",
       input = list(artifact = src$of_artifact, dir = src$dir, basis = src$basis, bt_md5 = .sa_md5(bp), auth_md5 = .sa_md5(ap),
                    strategy_id = as.character(bt0$manifest$strategy_id[1]), run_id = as.character(bt0$manifest$run_id[1]),
                    essence_grade_auth = au$essence_grade),
       config = list(path = cfg$.path, md5 = cfg$.md5, contracts_dir = .SA_DEP$.dir))
}

#' 쓰기(명시 out_dir 에만 · 원자) — <prefix>.json
sa_write <- function(res, out_dir, prefix = NULL) {
  if (missing(out_dir) || !nzchar(out_dir)) stop("[sa] out_dir 필수 — 기본 쓰기 경로 없음")
  prefix <- .sa_or(prefix, paste0("sa_subwindow_", if (is.na(res$window$cut_id)) "arg" else res$window$cut_id))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out <- file.path(out_dir, paste0(prefix, ".json")); tmp <- file.path(out_dir, paste0(".", prefix, ".json.tmp", Sys.getpid()))
  writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null"), tmp, useBytes = TRUE)
  if (!file.rename(tmp, out)) { unlink(tmp); stop("[sa] 원자 쓰기 실패: ", out) }
  invisible(out)
}

cat("[selection_accounting.R] Loaded (", SA_VERSION, ") — sa_config · sa_resolve · sa_subwindow · sa_write (P1-03 의 나머지 항목은 부재)\n", sep = "")
