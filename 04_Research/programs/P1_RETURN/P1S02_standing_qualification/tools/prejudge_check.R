## P1S02(판 2 · 코어 v3) 판정 전 점검 — 판정 규칙 · 원장 무접촉 · 판정 결과를 바꾸지 않는다(판 1 보관본 ../P1S01_…/tools/prejudge_check.R 를 판 2 로 옮김)
##   설계 README(04_Research/01_reports/portfolio_paper_layer_split_20261112) §8 '판 2 첫 판정 전 점검' 10항목 + 판단 T3 C-20261111-048 · T4 C-20261111-063 반영.
##   시험 창 값은 읽지 않는다(유한한지만 본다). 하나라도 ★이면 판정(judge)하지 않고 멈춰 보고한다 — 인프라 결함이 '미시험' 판정으로 굳지 않게.
##   1 측정 ok  2 지문  3 키 파일  4 축 감사  5 실효 시작 날짜  6 칸 평가(--eval)  7 β-통제 알파 유한  8 기저 = 점수 패널(base_kind)
##   9 엔진 신호일(진단의 첫 엔진 신호일 · 월말 수 · 레인 점수 패널이 있으면 신호일 집합 대조)  10 후보 폭(실효 시작 규칙이 선 날이 있는가)
##   11 (실패 · 경고가 났을 때) 메시지의 수치를 원천 개수(기저 캐시 신호일 수 · 일별 종목 수 · 셀 경로가 읽은 신호일 수)와 맞춘 뒤에 기전을 적는다 —
##      이 스크립트가 원천 개수를 찍어 준다. 안 맞는 수치가 남으면 보고는 '원인 조사 중(사실만)'.
## 사용: Rscript 04_Research/programs/P1_RETURN/P1S02_standing_qualification/tools/prejudge_check.R <code> [--eval] [--lane-panel <factors_panel.parquet>]
##          [--expect-first-engine-date <YYYY-MM-DD>] [--expect-engine-dates <수>] [--expect-effective-start <YYYY-MM-DD>]   (판단 T1 C-20261111-081 · 점검 v1 R-5)
##          [--round-dir <판 폴더>] [--registry <등록부 사본>]   (리허설 전용 — 격리 판 · 임시 등록부 · RC_SA_ROOT 는 환경변수로)
##   기대값 인자가 주어지면 진단(rf_engine_diag.json::base_alignment) · 권위 기록(실효 시작)의 값과 대조해 다르면 ★(항목 9 · 5). 안 주면 종전처럼 출력만.
##   시드 기대값(DESIGN §5): 첫 엔진 신호일 2004-07-30 · 엔진 신호일 268.
##   --eval 은 칸 평가 캐시 results/<code>/eval.json · eval.key 를 쓴다(뒤의 judge 가 같은 파일을 읽는다 — 같은 함수 · 판정을 바꾸지 않는다 · 점검 v1 S-2).
a <- commandArgs(trailingOnly = TRUE); code <- a[1]; do_eval <- "--eval" %in% a
argv <- function(k) if (k %in% a) a[which(a == k) + 1L] else NA_character_
lane_panel <- argv("--lane-panel")
exp_first <- argv("--expect-first-engine-date"); exp_n <- suppressWarnings(as.integer(argv("--expect-engine-dates"))); exp_eff <- argv("--expect-effective-start")
rd_arg <- argv("--round-dir"); reg_arg <- argv("--registry"); if (is.na(reg_arg)) reg_arg <- NULL
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(root, "04_Research/programs/_lib/round_core/v3/load.R"))
setwd(rc_root()); root <- rc_root()
rd <- rc_abs(if (is.na(rd_arg)) "04_Research/programs/P1_RETURN/P1S02_standing_qualification" else rd_arg, root)
ctx <- rc_standing_context(rd, root, registry_path = reg_arg)
it <- rc_standing_items(rc_standing_ledger_read(ctx$ledger))[[code]]
if (is.null(it)) stop("원장에 항목 없음: ", code)
bad <- character(0); flag <- function(k, ...) { bad <<- c(bad, k); cat("  ★", sprintf(...), "\n") }
fin <- function(x) { v <- suppressWarnings(as.numeric(unlist(x))[1]); if (length(v) && is.finite(v)) "유한" else "NA" }
cat(sprintf("[1 · 2] %s · 측정 기록 %d건 · 측정됨(ok ∧ 지문 동일)=%s · 판정=%s\n", code, length(it[["measures"]]),
            .rcs_measured(it), if (is.null(it[["verdict"]])) "없음" else "있음"))
for (m in it[["measures"]]) cat(sprintf("  measure: ok=%s fp_same=%s rc=%s 분=%.1f error=%s deferred=%s\n", m[["ok"]], m[["fp_same"]], m[["rc"]],
                                        as.numeric(m[["seconds"]] %||% NA) / 60, m[["error"]] %||% "-", m[["deferred"]] %||% "-"))
if (!.rcs_measured(it)) flag("1", "ok ∧ 지문 동일인 측정이 없다")
rj <- file.path(ctx$P$results, paste0(code, ".json"))
if (!file.exists(rj)) { cat("[1] 결과 json 없음 — 측정 안 됨\n"); quit(status = 3) }
r <- rc_json_read(rj); cat(sprintf("[1] 결과 json ok=%s · artifacts=%s\n", r$ok, r$artifacts %||% "-"))
if (!isTRUE(r$ok)) { cat("[1] 측정 실패 기록: ", substr(paste(unlist(r$err %||% r$error %||% ""), collapse = " "), 1, 400), "\n"); quit(status = 3) }
src <- .rc_artifact_dir(r$artifacts)
cat("[3] 키 파일\n")
for (f in RC_EVAL_KEY_FILES) { ok <- file.exists(file.path(src, f)); cat(sprintf("  %-32s %s\n", f, if (ok) "있음" else "★없음")); if (!ok) bad <- c(bad, "3") }
ax <- tryCatch(rc_axis_audit(root, r$artifacts), error = function(e) list(ok = FALSE, err = conditionMessage(e)))
cat(sprintf("[4] 축 감사 ok=%s · 최대 종목 %s/%s · 최소 비중 %s · 최대 Σw %s%s\n", ax$ok, ax$n_max_realized %||% "?", ax$max_names %||% "?",
            signif(ax$w_min %||% NA, 4), signif(ax$sigma_w_max %||% NA, 6), if (!is.null(ax$err)) paste0(" · 오류 ", ax$err) else ""))
if (!isTRUE(ax$ok)) flag("4", "축 감사 실패")
ar <- tryCatch(rc_json_read(file.path(src, "authoritative_remeasure.json")), error = function(e) NULL)
es <- ar$measurement_axis$effective_start
cat(sprintf("[5 · 10] authoritative_remeasure.json 판독=%s · 측정 축=%s · 실효 시작=%s(상태 %s)\n", !is.null(ar),
            ar$measurement_axis$epoch %||% ar$measurement_axis$id %||% "?", es$date %||% "?", es$status %||% es$state %||% "?"))
if (is.null(ar) || is.null(es$date)) flag("5", "권위 기록의 실효 시작을 읽지 못했다")
if (!is.na(exp_eff) && !identical(as.character(es$date %||% NA), exp_eff)) flag("5", "실효 시작 %s ≠ 기대 %s", es$date %||% "?", exp_eff)
## 8 · 9 — 기저 정합 진단(셀 엔진이 산출 폴더에 쓴다) + 원천 개수(11)
dj <- file.path(src, "rf_engine_diag.json")
if (!file.exists(dj)) flag("8", "rf_engine_diag.json 없음 — 기저 정합 진단이 없는 측정(옛 셀 엔진?)") else {
  D <- rc_json_read(dj); BA <- D[["base_alignment"]]
  cat(sprintf("[8 · 9] 진단 schema=%s · 셀 신호일 수 %s · 기저 항목 %d\n", D$schema %||% "?", D$n_sig_dates %||% "?", length(BA)))
  if (!length(BA)) flag("8", "base_alignment 절 없음")
  for (nm in names(BA)) { b <- BA[[nm]]
    cat(sprintf("  %s: rule %s · base_kind %s · 시작 %s(주입 %s) · 엔진 신호일 %s(첫 %s) → 월말 %s(시작일 이후 %s · 첫 %s) · 옮김 %s · 덮임 %s · 달력 밖 %s · 꼬리 %s · 최대 지연 %s · 캐시 적중 %s\n",
                nm, b$rule %||% "?", b$base_kind %||% "?", b$start %||% "?", b$start_injected %||% "?", b$n_engine_dates %||% "?", b$first_engine_date %||% "?",
                b$n_cell_dates %||% "?", b$n_cell_dates_from_start %||% "?", b$first_cell_date %||% "?", b$n_moved %||% "?", b$n_superseded %||% "?",
                b$n_offcal %||% "?", b$n_dropped_tail %||% "?", b$max_lag_td %||% "?", b$from_cache %||% "?"))
    if (!identical(b$rule, "month_snap_v1")) flag("8", "%s: 정렬 규칙이 month_snap_v1 이 아니다", nm)
    if (!identical(b$base_kind, "factors")) flag("8", "%s: 기저가 점수 패널이 아니다(base_kind = %s)", nm, b$base_kind %||% "?")
    if (!isTRUE(b$start_injected)) flag("5", "%s: 측정 시작일이 기저 엔진에 전달되지 않았다", nm)
    if (isTRUE((b$n_superseded %||% 0) > 0) || isTRUE((b$n_offcal %||% 0) > 0)) flag("9", "%s: 월말 격자 밖 신호(덮임 %s · 달력 밖 %s)", nm, b$n_superseded, b$n_offcal)
    if (!is.na(exp_first) && !identical(as.character(b$first_engine_date %||% NA), exp_first)) flag("9", "%s: 첫 엔진 신호일 %s ≠ 기대 %s", nm, b$first_engine_date %||% "?", exp_first)
    if (!is.na(exp_n) && !identical(suppressWarnings(as.integer(b$n_engine_dates %||% NA)), exp_n)) flag("9", "%s: 엔진 신호일 수 %s ≠ 기대 %d", nm, b$n_engine_dates %||% "?", exp_n)
  }
  if (!is.na(exp_first) || !is.na(exp_n)) cat(sprintf("  기대값 대조: 첫 엔진 신호일 %s · 엔진 신호일 수 %s\n", if (is.na(exp_first)) "-" else exp_first, if (is.na(exp_n)) "-" else exp_n))
  if (!is.na(lane_panel) && file.exists(lane_panel) && length(BA) == 1L) {
    ## 레인 점수 패널의 신호일 집합과 기저 캐시(엔진 원산출)의 신호일 집합 대조 — 주입한 시작일이 레인과 같은 격자를 냈는가(C-063)
    ld <- sort(unique(as.Date(arrow::read_parquet(lane_panel, col_select = "Date")$Date)))
    cat(sprintf("  레인 패널 신호일 %d(첫 %s) — 진단의 엔진 신호일 수 %s · 첫 %s\n", length(ld), format(min(ld)), BA[[1]]$n_engine_dates %||% "?", BA[[1]]$first_engine_date %||% "?"))
  }
}
E <- rc_deps(root)
m <- rc_safe(rc_metric_beta_alpha, E, r$artifacts, ctx$tau, what = code)
if (!isTRUE(m$ok)) flag("7", "β-통제 알파 계산 실패: %s", m$error) else {
  cat(sprintf("[7] β-통제 알파: 보는 창 t=%s · α=%s · n=%s · 시험 창 t=%s · n=%s(값 미표시)\n", fin(m$value$t_alpha_vis), fin(m$value$alpha_ann_vis),
              m$value$n_vis %||% "NA", fin(m$value$t_alpha_test), if (is.finite(suppressWarnings(as.numeric(m$value$n_test %||% NA)))) "유한" else "NA"))
  if (!identical(fin(m$value$t_alpha_vis), "유한")) flag("7", "보는 창 t(α) 가 유한하지 않다")
}
if (do_eval) {
  env <- rc_eval_env(root, ctx$spec[["behavior_card_cfg"]])
  t0 <- Sys.time()
  ev <- rc_safe(rc_eval_cell, root, ctx$round_dir, list(code = code, engine = it[["engine"]], role = it[["role"]], spec = it[["cell_spec"]]), env, ctx$tau, what = code)
  cat(sprintf("[6] 칸 평가 %.1f분 · ok=%s\n", as.numeric(difftime(Sys.time(), t0, units = "mins")), ev$ok))
  if (!isTRUE(ev$ok)) flag("6", "칸 평가 실패: %s", ev$error) else {
    e <- ev$value; mm <- rc_metric_from_eval(e)
    cat(sprintf("[6] 칸 평가 status=%s · 보는 창 %s · uc_vis=%s · 위기 수=%s · 강세 수=%s · 하락노출 중앙=%s · 시험 창 uc=%s(값 미표시)\n",
                e$status, paste(unlist(e$visible$window), collapse = "~"), fin(mm$uc_vis), e$visible$n_crisis %||% "NA", e$visible$n_bull %||% "NA",
                fin(mm$dd_capture_median_vis), fin(mm$uc_test)))
    if (!identical(e$status, "evaluated") || !identical(fin(mm$uc_vis), "유한")) flag("6", "칸 평가 상태 %s · 보는 창 상승 포착 %s", e$status, fin(mm$uc_vis))
  }
}
cat(sprintf("[점검 결과] %s — %s\n", code, if (length(bad)) paste0("★멈춤(항목 ", paste(sort(unique(bad)), collapse = " · "), ") — 판정하지 않는다") else "이상 없음"))
quit(status = if (length(bad)) 4L else 0L)
