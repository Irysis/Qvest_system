## ★보관본(2026-11-11 P1S01 측정 세션) — 판 1(P1S01 · 코어 v1)에 묶인 판정 전 점검. 판 1 은 보류 고정이라 이 파일은 참고용이다.
##   판 2 에서는 코어 판 · 판 경로를 바꿔 다시 쓴다(설계 04_Research/01_reports/portfolio_paper_layer_split_20261112/README.md §8 점검 항목).
##   판단 J-20261111-019 의 근거 실행본 · 판단 Superfan T3 C-20261111-057(스크래치에만 있던 것을 저장소로).
##   더할 것(C-20261111-048): 실패 · 경고 메시지의 수치(최대 폭 · 보유 중앙 · rows · tickers)를 원천 개수(기저 캐시 신호일 수 · 일별 종목 수 · 셀 경로가 읽은 신호일 수)와 맞춘 뒤에 기전을 적는다.
## P1S01 판정 전 점검(세션 Q · 11-11) — 판정 규칙 · 원장 무접촉 · 판정 결과를 바꾸지 않는다
##   ① 측정 결과 json(ok · 산출 폴더) ② 칸 평가 키 파일 존재 ③ 축 감사(롱온리 · ≤ 25 · Σw ≤ 1)
##   ④ rc_eval_cell(판정이 부르는 그 함수 · 내용 주소 캐시 — 판정이 같은 키로 재사용) — 상태 · 보는 창 판정 지표 유한 여부
##   ⑤ rc_metric_beta_alpha — 보는 창 t(α) · n 유한 여부(값은 찍지 않는다) · 시험 창 열은 유한 여부만
## 사용: Rscript prejudge_check.R <code> [--eval]   (--eval 이 없으면 ④ 생략)
a <- commandArgs(trailingOnly = TRUE); code <- a[1]; do_eval <- "--eval" %in% a
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(root, "04_Research/programs/_lib/round_core/v1/load.R"))
setwd(rc_root()); root <- rc_root()
rd <- rc_abs("04_Research/programs/P1_RETURN/P1S01_standing_qualification", root)
ctx <- rc_standing_context(rd, root)
it <- rc_standing_items(rc_standing_ledger_read(ctx$ledger))[[code]]
if (is.null(it)) stop("원장에 항목 없음: ", code)
fin <- function(x) { v <- suppressWarnings(as.numeric(unlist(x))[1]); if (length(v) && is.finite(v)) "유한" else "NA" }
cat(sprintf("[점검] %s · 측정 기록 %d건 · 측정됨(ok ∧ 지문 동일)=%s · 판정=%s\n", code, length(it[["measures"]]),
            .rcs_measured(it), if (is.null(it[["verdict"]])) "없음" else "있음"))
for (m in it[["measures"]]) cat(sprintf("  measure: ok=%s fp_same=%s rc=%s 분=%.1f deferred=%s\n", m[["ok"]], m[["fp_same"]], m[["rc"]],
                                        as.numeric(m[["seconds"]] %||% NA) / 60, m[["deferred"]] %||% "-"))
rj <- file.path(ctx$P$results, paste0(code, ".json"))
if (!file.exists(rj)) { cat("[점검] 결과 json 없음 — 측정 안 됨\n"); quit(status = 3) }
r <- rc_json_read(rj); cat(sprintf("[점검] 결과 json ok=%s · artifacts=%s\n", r$ok, r$artifacts %||% "-"))
if (!isTRUE(r$ok)) { cat("[점검] 측정 실패 기록: ", substr(paste(unlist(r$err %||% r$error %||% ""), collapse = " "), 1, 400), "\n"); quit(status = 3) }
src <- .rc_artifact_dir(r$artifacts)
for (f in RC_EVAL_KEY_FILES) cat(sprintf("  %-32s %s\n", f, if (file.exists(file.path(src, f))) "있음" else "★없음"))
ax <- tryCatch(rc_axis_audit(root, r$artifacts), error = function(e) list(ok = FALSE, err = conditionMessage(e)))
cat(sprintf("[점검] 축 감사 ok=%s · 최대 종목 %s/%s · 최소 비중 %s · 최대 Σw %s%s\n", ax$ok, ax$n_max_realized %||% "?", ax$max_names %||% "?",
            signif(ax$w_min %||% NA, 4), signif(ax$sigma_w_max %||% NA, 6), if (!is.null(ax$err)) paste0(" · 오류 ", ax$err) else ""))
ar <- tryCatch(rc_json_read(file.path(src, "authoritative_remeasure.json")), error = function(e) NULL)
cat(sprintf("[점검] authoritative_remeasure.json 판독=%s · 측정 축=%s · 실효 시작=%s\n", !is.null(ar),
            ar$measurement_axis$epoch %||% ar$measurement_axis$id %||% "?", ar$measurement_axis$effective_start$date %||% "?"))
E <- rc_deps(root)
m <- rc_safe(rc_metric_beta_alpha, E, r$artifacts, ctx$tau, what = code)
if (!isTRUE(m$ok)) cat("[점검] ★β-통제 알파 계산 실패: ", m$error, "\n") else
  cat(sprintf("[점검] β-통제 알파: 보는 창 t=%s · α=%s · n=%s · 시험 창 t=%s · n=%s(값 미표시)\n", fin(m$value$t_alpha_vis), fin(m$value$alpha_ann_vis),
              m$value$n_vis %||% "NA", fin(m$value$t_alpha_test), if (is.finite(suppressWarnings(as.numeric(m$value$n_test %||% NA)))) "유한" else "NA"))
if (do_eval) {
  env <- rc_eval_env(root, ctx$spec[["behavior_card_cfg"]])
  t0 <- Sys.time()
  ev <- rc_safe(rc_eval_cell, root, ctx$round_dir, list(code = code, engine = it[["engine"]], role = it[["role"]], spec = it[["cell_spec"]]), env, ctx$tau, what = code)
  cat(sprintf("[점검] 칸 평가 %.1f분 · ok=%s\n", as.numeric(difftime(Sys.time(), t0, units = "mins")), ev$ok))
  if (!isTRUE(ev$ok)) cat("[점검] ★칸 평가 실패: ", ev$error, "\n") else {
    e <- ev$value; mm <- rc_metric_from_eval(e)
    cat(sprintf("[점검] 칸 평가 status=%s · 보는 창 %s · uc_vis=%s · 위기 수=%s · 강세 수=%s · 하락노출 중앙=%s · 시험 창 uc=%s(값 미표시)\n",
                e$status, paste(unlist(e$visible$window), collapse = "~"), fin(mm$uc_vis), e$visible$n_crisis %||% "NA", e$visible$n_bull %||% "NA",
                fin(mm$dd_capture_median_vis), fin(mm$uc_test)))
  }
}
