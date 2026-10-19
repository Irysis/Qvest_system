## round_core v1 · metrics — 판정 표의 지표 공급자. 수치는 전부 R 계약 산출(AX-008 · 손계산 없음):
##   diagnosis_packet(.dp_read · 행동 카드 bc_monthly) · beta_controlled_alpha · gv3_window · 칸 평가(eval.json).
##   계약 파일은 읽기만 한다(진행 중 라운드의 핀 대상 — 수정 금지). 계약 의존은 rc_deps() 한 곳에서 적재한다.

## 계약 적재(프로세스당 1회 · 메모) — diagnosis_packet 이 행동 카드 · 대조 · 등급 · 노출 분해를 함께 적재한다
.RC <- new.env(parent = emptyenv())
rc_deps <- function(root = rc_root()) {
  if (isTRUE(.RC$loaded) && identical(.RC$root, root)) return(invisible(.RC$E))
  for (f in c("02_Infrastructure/contracts/diagnosis_packet.R", "02_Infrastructure/contracts/beta_controlled_alpha.R",
              "02_Infrastructure/contracts/matched_controls.R"))
    invisible(capture.output(suppressMessages(source(file.path(root, f), local = globalenv()))))
  .RC$E <- .dp_deps(root); .RC$root <- root; .RC$loaded <- TRUE
  invisible(.RC$E)
}

## 월 수익(행동 카드 계약의 월 복리 집계) — 칸 산출물의 전략 순수익 · 벤치 수익
rc_monthly_pair <- function(E, artifacts) {
  rd <- .dp_read(E, artifacts)
  mon <- function(d, col) E$bc_monthly(d[, .(date, r = get(col))], "r")
  S <- mon(rd$pr[, .(date, ret_net)], "ret_net"); K <- mon(rd$br[, .(date, benchmark_ret)], "benchmark_ret")
  merge(S[, .(ym, s = r)], K[, .(ym, k = r)], by = "ym")[order(ym)]
}

## β-통제 알파(보는 창 = ym ≤ τ_D 의 달 · 시험 창 = 그 뒤 · NW lag 3 · 연율) — P1R01 evaluate.R 과 같은 계산
rc_metric_beta_alpha <- function(E, artifacts, tau) {
  M <- rc_monthly_pair(E, artifacts)
  tym <- format(as.Date(tau), "%Y-%m")
  bv <- beta_controlled_alpha(M[ym <= tym]$s, M[ym <= tym]$k, periods_per_year = 12, nw_lag = 3L)
  bt <- tryCatch(beta_controlled_alpha(M[ym > tym]$s, M[ym > tym]$k, periods_per_year = 12, nw_lag = 3L), error = function(z) NULL)
  list(t_alpha_vis = bv$t_alpha, alpha_ann_vis = bv$alpha_ann, beta_vis = bv$beta, port_t_vis = bv$port_t, n_vis = bv$n,
       t_alpha_test = bt$t_alpha %||% NA_real_, alpha_ann_test = bt$alpha_ann %||% NA_real_, n_test = bt$n %||% NA_integer_)
}

## 칸 평가 기록(eval.json)에서 읽는 지표 — 보는 창 패킷 · 전기간 카드가 이미 계산한 값
rc_metric_from_eval <- function(ev) {
  num <- function(x) suppressWarnings(as.numeric(x %||% NA))
  list(uc_vis = num(ev[["visible"]][["uc"]]), cagr_vis = num(ev[["visible"]][["cagr"]]), uc_test = num(ev[["test"]][["uc"]] %||% NA),
       calmar_vis = num(ev[["visible"]][["calmar"]]), port_t_packet_vis = num(ev[["visible"]][["port_t"]]), mdd_vis = num(ev[["visible"]][["mdd"]]),
       dc_vis = num(ev[["visible"]][["dc"]]), dd_capture_median_vis = num(ev[["visible"]][["dd_capture_median"]]),
       dd_capture_worst_vis = num(ev[["visible"]][["dd_capture_worst"]]), n_crisis_vis = num(ev[["visible"]][["n_crisis"]]))
}

## 증분 β-통제 알파(개선 − 같은 배치 기준 · round_kit rk_pair_alpha 이관 — 같은 계산)
rc_pair_alpha <- function(E, var_dir, base_dir, tau) {
  v <- .dp_read(E, var_dir); b <- .dp_read(E, base_dir)
  mon <- function(d, col) E$bc_monthly(d[, .(date, r = get(col))], "r")
  S <- merge(mon(v$pr[, .(date, ret_net)], "ret_net")[, .(ym, s = r)], mon(b$pr[, .(date, ret_net)], "ret_net")[, .(ym, b = r)], by = "ym")
  K <- mon(b$br[, .(date, benchmark_ret)], "benchmark_ret")[, .(ym, k = r)]
  D <- merge(S, K, by = "ym")[order(ym)]; tym <- format(as.Date(tau), "%Y-%m")
  one <- function(d) {
    a <- tryCatch(beta_controlled_alpha(d$s - d$b, d$k, periods_per_year = 12, nw_lag = 3L), error = function(e) NULL)
    list(d_alpha = a$alpha_ann %||% NA_real_, t = a$t_alpha %||% NA_real_, n = a$n %||% NA_integer_,
         window = if (nrow(d)) c(d$ym[1], d$ym[nrow(d)]) else NA)
  }
  list(visible = one(D[ym <= tym]), test = one(D[ym > tym]))
}

## 보유 집중(round_kit rk_concentration 이관) — 리밸일별 최대 비중 · 유효 종목 수(현금 몫 제외)
rc_concentration <- function(dir, tau) {
  H <- fread(file.path(dir, "04_holdings.csv"))
  wc <- intersect(c("target_weight", "actual_weight"), names(H))[1]
  H[, w := as.numeric(get(wc))]; H <- H[is.finite(w) & w > 0]
  H[, date := as.Date(date)]
  per <- H[, .(n = .N, maxw = max(w) / sum(w), effn = 1 / sum((w / sum(w))^2)), by = date]
  f <- function(p) if (!nrow(p)) list(n_dates = 0L) else
    list(n_dates = nrow(p), maxw_median = stats::median(p$maxw), maxw_max = max(p$maxw),
         effn_median = stats::median(p$effn), effn_min = min(p$effn), names_median = stats::median(p$n))
  list(visible = f(per[date <= as.Date(tau)]), full = f(per))
}

## 보는 창 종합점수 S(등급 v3 의 S 식 · 상수는 사전등록이 정본에서 옮긴 값 — round_kit rk_S 이관)
rc_S <- function(calmar, port_t, fs) ifelse(is.finite(calmar) & is.finite(port_t) & calmar > 0 & port_t > 0,
                                          (calmar / fs$calmar_norm)^fs$w_calmar * (port_t / fs$port_t_norm)^fs$w_port_t, 0)
