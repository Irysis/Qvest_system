# tg_chart_pack.R — 실측 보고 표준 차트팩 v1 (도훈 mandate 2026-07-11)
# ─────────────────────────────────────────────────────────────────────────────
# 목적: "실측 수치가 나오는 리서치 보고 = 그래프 첨부 의무" (qvest-telegram SKILL.md §2 원칙 9)
#       글-only 브리핑의 직관성 부족 해소 — 모든 에이전트가 재사용하는 단일 생성기.
#
# 진입점 3종:
#   tg_chart_pack(period_returns, out_dir, title, ...)      → 표준 3종 PNG 경로 벡터
#       01: equity_curve.png   누적수익(log) 전략 vs BM
#       02: annual_returns.png 연간수익률 막대 전략 vs BM
#       03: drawdown.png       수중곡선(underwater) 전략 vs BM
#   tg_chart_sweep(labels, values, out_dir, title, ...)     → config/멀티암 비교 가로막대 1종
#   tg_chart_pack_from_bt(bt_result, out_dir, title)        → 10-component 계약 소비 래퍼
#
# 사용 (SKILL.md §7 참조):
#   source("02_Infrastructure/telegram/tg_chart_pack.R")
#   paths <- tg_chart_pack(pr, out_dir = "stage_artifacts/WT_X", title = "...")
#   tg_agent_brief(..., charts = paths)
#
# ★원칙 — 시각화 전용 파일:
#   본 파일은 성과 '수치'를 계산·보고하지 않는다. 캡션/주석에 찍히는 수치는
#   호출자가 계약 산출물(build_bt_result/essence_score/canonical_screen_bt) 값을
#   metrics_note 인자로 전달한 것만 표기한다. 아래 wealth index / 낙폭 계산은
#   차트의 선을 그리기 위한 시각화 산술이며 게이트·판정·보고 수치로 인용 금지.
# ─────────────────────────────────────────────────────────────────────────────

.tgcp_col_str <- "#1f77b4"   # 전략 (house 파랑)
.tgcp_col_bm  <- "#888888"   # 벤치마크 (회색)
.tgcp_col_pos <- "#2ca02c"
.tgcp_col_neg <- "#d62728"

# 내부: 시각화 전용 wealth index (게이트/보고 수치 인용 금지 — 헤더 원칙 참조)
.tgcp_wealth <- function(r) cumprod(1 + ifelse(is.na(r), 0, r))

.tgcp_png <- function(path, w = 1000, h = 560) {
  grDevices::png(path, width = w, height = h, res = 110)
  graphics::par(mar = c(4, 4.4, 3.2, 1), family = "")
}

#' 표준 3종 차트팩
#' @param period_returns data.frame/data.table — date, ret_net(전략 net), benchmark_ret(BM) 컬럼
#' @param out_dir 출력 디렉토리 (없으면 생성)
#' @param title 차트 메인 타이틀 접두 (예: "WT-D20260711_002 난독화 전수")
#' @param date_col/ret_col/bm_col 컬럼명 오버라이드
#' @param bm_label 벤치 라벨 (기본 "KOSPI200")
#' @param metrics_note 계약 산출 수치 1줄 (호출자 책임 — 예: "PORT_t 2.35 · oos 0.71 · calmar 0.66 (forge)")
#' @param prefix 파일명 접두 (동일 dir 다중 전략 구분)
#' @return 생성된 PNG 절대경로 벡터 (tg_agent_brief charts= 직결)
tg_chart_pack <- function(period_returns, out_dir, title,
                          date_col = "date", ret_col = "ret_net",
                          bm_col = "benchmark_ret", bm_label = "KOSPI200",
                          metrics_note = NULL, prefix = "") {
  pr <- as.data.frame(period_returns)
  stopifnot(all(c(date_col, ret_col) %in% names(pr)))
  has_bm <- bm_col %in% names(pr) && any(!is.na(pr[[bm_col]]))
  pr <- pr[order(as.Date(pr[[date_col]])), ]
  d  <- as.Date(pr[[date_col]])
  nav_s <- .tgcp_wealth(pr[[ret_col]])
  if (has_bm) nav_b <- .tgcp_wealth(pr[[bm_col]])
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  paths <- character(0)
  sub_note <- sprintf("%s~%s · %d기간%s",
                      format(min(d), "%Y-%m"), format(max(d), "%Y-%m"), length(d),
                      if (!is.null(metrics_note)) paste0(" · ", metrics_note) else "")

  # ── 01 누적수익 (log) ──
  f1 <- file.path(out_dir, paste0(prefix, "equity_curve.png"))
  .tgcp_png(f1)
  yl <- range(c(nav_s, if (has_bm) nav_b), finite = TRUE)
  plot(d, nav_s, type = "l", lwd = 2.4, col = .tgcp_col_str, log = "y", ylim = yl,
       xlab = "", ylab = "누적수익 (로그, 시작=1)", main = paste0(title, " — 누적수익 vs ", bm_label))
  if (has_bm) lines(d, nav_b, lwd = 2, col = .tgcp_col_bm, lty = 2)
  # graphics:: 명시 — PerformanceAnalytics 로드 시 legend 마스킹 충돌 (FQ-017 실사고)
  graphics::legend("topleft", legend = c("전략", if (has_bm) bm_label),
         col = c(.tgcp_col_str, if (has_bm) .tgcp_col_bm),
         lwd = c(2.4, if (has_bm) 2), lty = c(1, if (has_bm) 2), bty = "n")
  mtext(sub_note, side = 3, line = 0.2, cex = 0.78, col = "#555555")
  dev.off(); paths <- c(paths, f1)

  # ── 02 연간수익률 막대 ──
  f2 <- file.path(out_dir, paste0(prefix, "annual_returns.png"))
  yr <- format(d, "%Y")
  agg <- function(r) tapply(seq_along(r), yr, function(ix) prod(1 + ifelse(is.na(r[ix]), 0, r[ix])) - 1)  # 시각화 전용
  ann_s <- agg(pr[[ret_col]])
  .tgcp_png(f2)
  if (has_bm) {
    ann_b <- agg(pr[[bm_col]])
    mat <- rbind(ann_s, ann_b) * 100
    barplot(mat, beside = TRUE, names.arg = names(ann_s), col = c(.tgcp_col_str, "#bbbbbb"),
            border = NA, las = 2, cex.names = 0.7, ylab = "연간수익률 (백분율)",
            main = paste0(title, " — 연간수익률 vs ", bm_label))
    graphics::legend("topleft", legend = c("전략", bm_label), fill = c(.tgcp_col_str, "#bbbbbb"), border = NA, bty = "n")
  } else {
    barplot(ann_s * 100, names.arg = names(ann_s),
            col = ifelse(ann_s >= 0, .tgcp_col_pos, .tgcp_col_neg),
            border = NA, las = 2, cex.names = 0.7, ylab = "연간수익률 (백분율)",
            main = paste0(title, " — 연간수익률"))
  }
  abline(h = 0, col = "#333333")
  dev.off(); paths <- c(paths, f2)

  # ── 03 수중곡선 (drawdown) ──
  f3 <- file.path(out_dir, paste0(prefix, "drawdown.png"))
  dd_s <- nav_s / cummax(nav_s) - 1                      # 시각화 전용
  .tgcp_png(f3)
  yl3 <- range(c(dd_s, if (has_bm) nav_b / cummax(nav_b) - 1, 0), finite = TRUE)
  plot(d, dd_s * 100, type = "l", lwd = 2, col = .tgcp_col_str, ylim = yl3 * 100,
       xlab = "", ylab = "고점 대비 낙폭 (백분율)", main = paste0(title, " — 낙폭(수중곡선)"))
  polygon(c(d, rev(d)), c(dd_s * 100, rep(0, length(d))), col = grDevices::adjustcolor(.tgcp_col_str, 0.25), border = NA)
  if (has_bm) { dd_b <- nav_b / cummax(nav_b) - 1; lines(d, dd_b * 100, lwd = 1.6, col = .tgcp_col_bm, lty = 2) }
  abline(h = 0, col = "#333333")
  graphics::legend("bottomleft", legend = c("전략", if (has_bm) bm_label),
         col = c(.tgcp_col_str, if (has_bm) .tgcp_col_bm),
         lwd = c(2, if (has_bm) 1.6), lty = c(1, if (has_bm) 2), bty = "n")
  mtext(sub_note, side = 3, line = 0.2, cex = 0.78, col = "#555555")
  dev.off(); paths <- c(paths, f3)

  normalizePath(paths, winslash = "/")
}

#' sweep / 멀티암 비교 가로막대 (R4/R5·챔피언십·A/B 보고용)
#' @param labels config/암 이름 벡터
#' @param values 실측 값 벡터 (예: paired NW-t, PORT_t) — 계약/실측 산출값만 전달
#' @param hline 기준선 (예: 2.0 paired / 2.95 PORT_t), hline_label 기준선 라벨
#' @param highlight 강조할 라벨 (예: 현직/승자)
tg_chart_sweep <- function(labels, values, out_dir, title,
                           value_label = "실측값", hline = NULL, hline_label = NULL,
                           highlight = NULL, filename = "sweep_compare.png") {
  stopifnot(length(labels) == length(values))
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  o <- order(values)
  lb <- labels[o]; vl <- values[o]
  cols <- ifelse(vl >= 0, .tgcp_col_str, .tgcp_col_neg)
  if (!is.null(highlight)) cols[lb %in% highlight] <- "#ff7f0e"
  f <- file.path(out_dir, filename)
  h <- max(560, 120 + 34 * length(lb))
  grDevices::png(f, width = 1000, height = h, res = 110)
  graphics::par(mar = c(4.2, 12, 3.2, 1.4), family = "")
  bp <- barplot(vl, names.arg = lb, horiz = TRUE, las = 1, col = cols, border = NA,
                xlab = value_label, main = title, cex.names = 0.72)
  text(vl, bp, labels = sprintf("%.2f", vl), pos = ifelse(vl >= 0, 4, 2), cex = 0.7, xpd = TRUE)
  abline(v = 0, col = "#333333")
  if (!is.null(hline)) {
    abline(v = hline, col = .tgcp_col_neg, lty = 2, lwd = 1.6)
    mtext(sprintf("기준선 %s%.2f", if (!is.null(hline_label)) paste0(hline_label, " ") else "", hline),
          side = 3, line = 0.2, cex = 0.75, col = .tgcp_col_neg)
  }
  dev.off()
  normalizePath(f, winslash = "/")
}

#' 10-component bt_result 계약 소비 래퍼 — period_returns + benchmark_returns 병합 후 표준 3종
tg_chart_pack_from_bt <- function(bt_result, out_dir, title = NULL, metrics_note = NULL, prefix = "") {
  pr <- as.data.frame(bt_result$period_returns)
  stopifnot(all(c("date", "ret_net") %in% names(pr)))
  bm <- tryCatch(as.data.frame(bt_result$benchmark_returns), error = function(e) NULL)
  if (!is.null(bm) && nrow(bm) > 0 && all(c("date", "benchmark_ret") %in% names(bm))) {
    pr <- merge(pr[, c("date", "ret_net")], bm[, c("date", "benchmark_ret")], by = "date", all.x = TRUE)
  }
  if (is.null(title)) {
    title <- tryCatch(bt_result$manifest$strategy_id, error = function(e) NULL)
    if (is.null(title) || !nzchar(title)) title <- "백테스트 실측"
  }
  bm_name <- tryCatch(unique(as.data.frame(bt_result$benchmark_returns)$benchmark_name)[1],
                      error = function(e) NA_character_)
  tg_chart_pack(pr, out_dir = out_dir, title = title,
                bm_label = if (!is.na(bm_name) && nzchar(bm_name)) bm_name else "KOSPI200",
                metrics_note = metrics_note, prefix = prefix)
}
