## P1R02 보고 전용 추가(★등록 뒤 추가 · 판정 H1 불변 · 철학 P1 C-20261017-014 · 016 수용) — 계약 함수만(손계산 없음 · AX-008)
##   1 행동 카드 + MC8(라운드 3단계 표준) → 롱 레그 산출물 폴더 behavior_card.json
##   2 크기 짝 묶음(보는 창): 크기 짝 바구니 α · t · (롱 레그 − 크기 짝) α · t = 크기 뺀 선택 알파 · 플라시보 경로(크기 짝 무작위) α t 분포에서 롱 레그 t 의 위치 ·
##     M3 보정판(선택 알파 ÷ 롱숏 α) + M3 > 1 꼬리표 → results/report_extras.json · 시험 창 · 전기간 블록은 results/full/report_extras_full.json 으로 분리
##   3 보는 창 진단 패킷 dp_build(tau_d = 2022-12-31) → results/P1R02_LONG/visible/
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT)
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RD  <- file.path(ROOT, "04_Research/programs/P1_RETURN/P1R02_1801_long_leg")
TAU <- "2022-12"
m  <- fromJSON(file.path(RD, "results/measure.json")); L_DIR <- m$out_dir
ev <- tryCatch(fromJSON(file.path(RD, "results/evaluation.json"), simplifyVector = FALSE), error = function(e) list())
invisible(capture.output(suppressMessages({
  source(file.path(ROOT, "02_Infrastructure/contracts/matched_controls.R"))
  source(file.path(ROOT, "02_Infrastructure/contracts/beta_controlled_alpha.R"))
  source(file.path(ROOT, "02_Infrastructure/contracts/diagnosis_packet.R"))
})))
E <- .dp_deps(ROOT)
## 1 — 카드와 대조는 같은 입력(raw 1회 적재)
pr <- fread(file.path(L_DIR, "03_period_returns.csv")); br <- fread(file.path(L_DIR, "05_benchmark_returns.csv")); H <- fread(file.path(L_DIR, "04_holdings.csv"))
pr[, date := as.Date(date)]; br[, date := as.Date(date)]; H[, date := as.Date(date)]
spec <- fromJSON(file.path(L_DIR, "01_strategy_spec.json")); man <- tryCatch(fromJSON(file.path(L_DIR, "00_manifest.json")), error = function(e) list())
uni <- as.character((spec$universe %||% man$universe_id)[1])
raw <- mc_load_raw(ROOT, from = min(H$date) - 31L, to = max(pr$date), hygiene = identical(uni, "ALL_HYG"))
card <- mc_card(L_DIR, root = ROOT, raw = raw); mc_write(card, L_DIR, root = ROOT)
cfg <- mc_cfg(ROOT); ep <- .mc_exec_price(spec, pr$date, H$date)
ctl <- mc_controls(H, pr, br, raw, cfg, ep$value, uni)
## 2 — 월 수익(행동 카드 계약 bc_monthly) · β 통제 α(계약)
mon <- function(d) E$bc_monthly(d[, .(date, r = ret)], "r")
S  <- mon(pr[, .(date, ret = ret_net)]); K <- mon(br[, .(date, ret = benchmark_ret)]); SB <- mon(ctl$series$size_matched)
D  <- Reduce(function(a, b) merge(a, b, by = "ym"), list(S[, .(ym, s = r)], SB[, .(ym, sb = r)], K[, .(ym, k = r)]))[order(ym)]
al <- function(x, k) { a <- tryCatch(beta_controlled_alpha(x, k, periods_per_year = 12, nw_lag = 3L), error = function(e) NULL)
  if (is.null(a)) list(ok = FALSE) else list(ok = TRUE, alpha_ann = a$alpha_ann, t = a$t_alpha, beta = a$beta, n = a$n) }
blk <- function(W) {
  long <- al(W$s, W$k); size <- al(W$sb, W$k); sel <- al(W$s - W$sb, W$k)
  pt <- NA_real_; pq <- NA_real_; npl <- 0L
  if (!is.null(ctl$placebo) && !is.null(ctl$placebo$P)) {
    tj <- vapply(seq_len(ncol(ctl$placebo$P)), function(j) {
      pj <- mon(data.table(date = ctl$placebo$date, ret = ctl$placebo$P[, j]))
      x <- merge(pj[, .(ym, p = r)], W[, .(ym, k)], by = "ym")
      a <- tryCatch(beta_controlled_alpha(x$p, x$k, periods_per_year = 12, nw_lag = 3L), error = function(e) NULL)
      if (is.null(a)) NA_real_ else a$t_alpha }, numeric(1))
    tj <- tj[is.finite(tj)]; npl <- length(tj)
    if (npl && isTRUE(long$ok)) { pq <- mean(tj >= long$t); pt <- as.numeric(stats::quantile(tj, 0.95)) }
  }
  list(window = c(W$ym[1], W$ym[nrow(W)]), long = long, size_matched = size, selection_long_minus_size = sel,
       placebo = list(n = npl, share_ge_long_t = pq, t_q95 = pt, basis = "크기 짝 무작위 바구니(MC8 플라시보 · 같은 크기 분위 · 같은 비중)"))
}
lsa <- suppressWarnings(as.numeric(ev$visible$M2_long_short$alpha_ann %||% NA))
V <- blk(D[ym <= TAU])
V$M3_corrected <- if (is.finite(lsa) && lsa > 0 && isTRUE(V$selection_long_minus_size$ok)) V$selection_long_minus_size$alpha_ann / lsa else NA_real_
V$M3_gt_1_flag <- isTRUE(suppressWarnings(as.numeric(ev$visible$M3_long_share %||% NA)) > 1)
V$selection_alpha_claim <- isTRUE(V$selection_long_minus_size$ok) && isTRUE(V$selection_long_minus_size$t >= 2.0) &&
  isTRUE(is.finite(V$placebo$share_ge_long_t) && V$placebo$share_ge_long_t <= 0.05)
V$selection_alpha_rule <- "'선택 알파' 서술 = 크기 뺀 t ≥ 2.0 ∧ 롱 레그 t 가 플라시보 상위 5% 안(철학 P1 C-014)"
V$branch <- {
  h1 <- identical(ev$verdict$H1, "holds"); s2 <- isTRUE(V$selection_long_minus_size$t >= 2.0)
  if (h1 && s2) "① 처방 축 ≤25 롱온리 라운드" else if (h1) "② 크기 프리미엄 — 엔진 라운드 열지 않음" else if (s2) "③ 크기 분위 중립 구성으로 롱온리 경로 유지" else "④ 롱온리 후보 아님" }
V$note <- "등록 뒤 추가 · 보고 전용 · 판정(H1) 불변 · 분기 = 원장 C-20261017-015 응답(평가 전 고정)"
dir.create(file.path(RD, "results/full"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(list(schema = "p1r02_report_extras_v1", visible = V, mc8_card = file.path(L_DIR, "behavior_card.json")),
                  auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RD, "results/report_extras.json"))
writeLines(toJSON(list(schema = "p1r02_report_extras_full_v1", test = blk(D[ym > TAU]), full = blk(D)), auto_unbox = TRUE, pretty = TRUE,
                  null = "null", na = "null", digits = NA), file.path(RD, "results/full/report_extras_full.json"))
## 3 — 보는 창 진단 패킷
pk <- dp_build(L_DIR, root = ROOT, tau_d = "2022-12-31", raw = raw)
dp_write(pk, file.path(RD, "results/P1R02_LONG/visible"))
cat(sprintf("[P1R02 추가] 보는 창: 롱 α %.2f%% t %.2f · 크기 짝 α %.2f%% t %.2f · 선택(롱−크기) α %.2f%% t %.2f · 플라시보 ≥ 롱 t 비율 %s · 분기 %s\n",
            100 * V$long$alpha_ann, V$long$t, 100 * V$size_matched$alpha_ann, V$size_matched$t,
            100 * V$selection_long_minus_size$alpha_ann, V$selection_long_minus_size$t, format(round(V$placebo$share_ge_long_t, 3)), V$branch))
