#==============================================================================
# MRS Dashboard — 최신 데이터로 차트 재생성 + 텔레그램 발송
# mrs_dashboard.R
#
# Author: Forge Agent
# Date:   2026-04-09
#
# FUNCTIONS:
#   generate_mrs_dashboard(send_telegram, output_dir)
#     — 최신 MRS 재계산 + 차트 3장 생성 + 텔레그램 발송
#
# CHARTS (3장):
#   1. mrs_timeline_24m.png  — MRS Score Timeline (최근 24개월), 국면 배경색
#   2. mrs_phase_dist.png    — 국면 분포: 전체 vs 최근 3년 비교 막대그래프
#   3. mrs_vs_kospi.png      — MRS vs KOSPI200 누적수익률 (이중축, 최근 3년)
#
# USAGE:
#   source("02_Infrastructure/config.R")
#   source(file.path(INFRA_DIR, "reports/mrs_dashboard.R"))
#   result <- generate_mrs_dashboard(send_telegram = TRUE)
#   cat(sprintf("MRS: %.1f | 국면: %s | 차트: %d장\n",
#               result$current_mrs, result$current_phase, length(result$charts)))
#
# DEPENDENCIES:
#   - config.R        (PROJECT_ROOT, INFRA_DIR)
#   - regime_engine_daily.R  (build_daily_regime)
#   - backtest_harness.R     (load_rawdata → BM_DT for KOSPI200)
#   - telegram_notify.R      (tg_send_photo)
#   - ggplot2, data.table
#==============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(data.table)
})

# Ensure PROJECT_ROOT / INFRA_DIR are available
if (!exists("PROJECT_ROOT")) {
  source("/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot/02_Infrastructure/config.R")
}


#==============================================================================
# INTERNAL helpers
#==============================================================================

.mrs_phase_label <- function(mrs_score) {
  dplyr::case_when(
    mrs_score < 20 ~ "Normal",
    mrs_score < 50 ~ "Caution",
    TRUE           ~ "Crisis"
  )
}

# ggplot2 theme — clean minimal
.mrs_theme <- function() {
  theme_bw(base_size = 12) +
    theme(
      plot.title    = element_text(face = "bold", size = 13),
      plot.subtitle = element_text(size = 10, color = "grey40"),
      legend.position = "bottom",
      panel.grid.minor = element_blank()
    )
}


#==============================================================================
# CHART 1: MRS Score Timeline (최근 24개월)
#==============================================================================

.chart_timeline_24m <- function(regime_dt, output_path) {
  dt <- copy(regime_dt)
  dt[, Phase := fifelse(MRS < 20, "Normal",
                        fifelse(MRS < 50, "Caution", "Crisis"))]
  dt[, Phase := factor(Phase, levels = c("Normal", "Caution", "Crisis"))]

  # 최근 24개월
  cutoff <- max(dt$Date) - 365.25 * 2
  dt24 <- dt[Date >= cutoff]

  if (nrow(dt24) == 0) {
    cat("[mrs_dashboard] 데이터 부족 — timeline 차트 생략\n")
    return(invisible(NULL))
  }

  # 국면 구간 배경: rle로 연속 구간 계산
  phases <- dt24[, .(Date, Phase, MRS)]
  setorder(phases, Date)

  # 구간별 rect 데이터 생성
  rle_result <- rle(as.character(phases$Phase))
  ends       <- cumsum(rle_result$lengths)
  starts     <- c(1L, ends[-length(ends)] + 1L)

  rect_dt <- data.table(
    xmin  = phases$Date[starts],
    xmax  = phases$Date[ends],
    Phase = rle_result$values
  )
  rect_dt[, xmax := xmax + 1]  # 마지막 날 포함

  phase_colors <- c(
    Normal  = "#E8F5E9",  # 연초록
    Caution = "#FFF9C4",  # 연노랑
    Crisis  = "#FFEBEE"   # 연빨강
  )

  # 최신 값
  latest      <- dt24[Date == max(Date)]
  latest_mrs  <- round(latest$MRS, 1)
  latest_date <- format(max(dt24$Date), "%Y-%m-%d")
  latest_phase <- as.character(latest$Phase)

  subtitle_txt <- sprintf("%s 기준 | 현재 MRS: %.1f | 국면: %s",
                          latest_date, latest_mrs, latest_phase)

  p <- ggplot(dt24, aes(x = Date, y = MRS)) +
    geom_rect(data = rect_dt,
              aes(xmin = xmin, xmax = xmax, ymin = 0, ymax = 100, fill = Phase),
              inherit.aes = FALSE, alpha = 0.5) +
    scale_fill_manual(values = phase_colors, name = "국면") +
    geom_hline(yintercept = c(20, 50), linetype = "dashed",
               color = c("#4CAF50", "#F44336"), linewidth = 0.5) +
    geom_line(color = "black", linewidth = 0.9) +
    annotate("text", x = max(dt24$Date), y = latest_mrs + 4,
             label = sprintf("%.1f", latest_mrs),
             hjust = 1, size = 3.5, fontface = "bold") +
    scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
    scale_x_date(date_breaks = "3 months", date_labels = "%y-%m") +
    labs(
      title    = "MRS Score Timeline (최근 24개월)",
      subtitle = subtitle_txt,
      x        = NULL,
      y        = "MRS Score (0~100)"
    ) +
    .mrs_theme()

  ggsave(output_path, p, width = 10, height = 4.5, dpi = 150)
  cat(sprintf("[mrs_dashboard] Chart 1 저장: %s\n", output_path))
  invisible(output_path)
}


#==============================================================================
# CHART 2: 국면 분포 — 전체 vs 최근 3년
#==============================================================================

.chart_phase_dist <- function(regime_dt, output_path) {
  dt <- copy(regime_dt)
  dt[, Phase := fifelse(MRS < 20, "Normal",
                        fifelse(MRS < 50, "Caution", "Crisis"))]
  dt[, Phase := factor(Phase, levels = c("Normal", "Caution", "Crisis"))]

  cutoff_3y <- max(dt$Date) - 365.25 * 3

  # 전체 비율
  tbl_all <- dt[, .N, by = Phase]
  tbl_all[, Pct   := N / sum(N) * 100]
  tbl_all[, Period := "전체 기간"]

  # 최근 3년 비율
  tbl_3y <- dt[Date >= cutoff_3y, .N, by = Phase]
  tbl_3y[, Pct   := N / sum(N) * 100]
  tbl_3y[, Period := "최근 3년"]

  # 누락 국면 보완 (0%로 채움)
  all_phases <- c("Normal", "Caution", "Crisis")
  for (ph in all_phases) {
    if (!ph %in% tbl_all$Phase) {
      tbl_all <- rbindlist(list(tbl_all,
        data.table(Phase = ph, N = 0L, Pct = 0, Period = "전체 기간")))
    }
    if (!ph %in% tbl_3y$Phase) {
      tbl_3y <- rbindlist(list(tbl_3y,
        data.table(Phase = ph, N = 0L, Pct = 0, Period = "최근 3년")))
    }
  }

  combined <- rbindlist(list(tbl_all, tbl_3y))
  combined[, Phase  := factor(Phase, levels = c("Normal", "Caution", "Crisis"))]
  combined[, Period := factor(Period, levels = c("전체 기간", "최근 3년"))]

  bar_colors <- c(Normal = "#66BB6A", Caution = "#FFA726", Crisis = "#EF5350")

  p <- ggplot(combined, aes(x = Period, y = Pct, fill = Phase)) +
    geom_col(position = "dodge", width = 0.6) +
    geom_text(aes(label = sprintf("%.1f%%", Pct)),
              position = position_dodge(width = 0.6),
              vjust = -0.4, size = 3.2) +
    scale_fill_manual(values = bar_colors, name = "국면") +
    scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20),
                       labels = function(x) paste0(x, "%")) +
    labs(
      title    = "국면 분포: 전체 기간 vs 최근 3년",
      subtitle = sprintf("기준일: %s", format(max(dt$Date), "%Y-%m-%d")),
      x        = NULL,
      y        = "비율 (%)"
    ) +
    .mrs_theme()

  ggsave(output_path, p, width = 7, height = 5, dpi = 150)
  cat(sprintf("[mrs_dashboard] Chart 2 저장: %s\n", output_path))
  invisible(output_path)
}


#==============================================================================
# CHART 3: MRS vs KOSPI200 누적수익률 (최근 3년, 이중축)
#==============================================================================

.chart_mrs_vs_kospi <- function(regime_dt, output_path) {
  # BM_DT 로드 (KOSPI200 일간 수익률)
  bm_dt <- tryCatch({
    if (!exists("load_rawdata", mode = "function")) {
      source(file.path(INFRA_DIR, "backtest_harness.R"))
    }
    raw <- load_rawdata(use_cache = TRUE)
    as.data.table(raw$BM_DT)
  }, error = function(e) {
    cat(sprintf("[mrs_dashboard] BM_DT 로드 실패: %s — KOSPI200 차트 생략\n", e$message))
    return(NULL)
  })

  if (is.null(bm_dt) || nrow(bm_dt) == 0) {
    # BM 없으면 MRS only 차트
    .chart_mrs_only_3y(regime_dt, output_path)
    return(invisible(output_path))
  }

  bm_dt[, Date := as.Date(Date)]
  setorder(bm_dt, Date)

  # 최근 3년 구간
  cutoff_3y <- max(regime_dt$Date) - 365.25 * 3

  # MRS 일간 데이터 (3년)
  mrs3 <- regime_dt[Date >= cutoff_3y, .(Date, MRS)]
  setorder(mrs3, Date)

  # KOSPI200 누적수익률 (3년)
  bm3 <- bm_dt[Date >= cutoff_3y, .(Date, BM_Ret)]
  setorder(bm3, Date)
  bm3[is.na(BM_Ret), BM_Ret := 0]
  bm3[, CumRet := cumprod(1 + BM_Ret) - 1]

  # 공통 날짜로 조인
  merged <- merge(mrs3, bm3[, .(Date, CumRet)], by = "Date", all.x = TRUE)
  merged[, CumRet := nafill(CumRet, type = "locf")]
  setorder(merged, Date)

  if (nrow(merged) == 0) {
    cat("[mrs_dashboard] 병합 후 데이터 없음 — KOSPI200 차트 생략\n")
    return(invisible(NULL))
  }

  # 이중축 스케일링: CumRet (0~0.x) → MRS 스케일 (0~100)
  # 오른쪽 축 = CumRet * scale_factor + offset
  cr_range  <- range(merged$CumRet, na.rm = TRUE)
  mrs_range <- c(0, 100)

  scale_factor <- diff(mrs_range) / max(diff(cr_range), 1e-6)
  offset       <- mrs_range[1] - cr_range[1] * scale_factor

  merged[, CumRet_scaled := CumRet * scale_factor + offset]

  # 위기 구간 음영
  dt_phase <- copy(merged)
  dt_phase[, Phase := fifelse(MRS >= 50, "Crisis", NA_character_)]

  rle_res <- rle(!is.na(dt_phase$Phase))
  ends_i   <- cumsum(rle_res$lengths)
  starts_i <- c(1L, ends_i[-length(ends_i)] + 1L)

  crisis_rows <- which(rle_res$values)
  if (length(crisis_rows) > 0) {
    rect_dt <- data.table(
      xmin = dt_phase$Date[starts_i[crisis_rows]],
      xmax = dt_phase$Date[ends_i[crisis_rows]] + 1
    )
  } else {
    rect_dt <- data.table(xmin = as.Date(character(0)),
                          xmax = as.Date(character(0)))
  }

  # 오른쪽 축 labels: 역변환
  breaks_cr  <- pretty(cr_range, n = 5)
  breaks_mrs <- breaks_cr * scale_factor + offset
  labels_cr  <- paste0(round(breaks_cr * 100, 0), "%")

  latest_date <- format(max(merged$Date), "%Y-%m-%d")

  p <- ggplot(merged, aes(x = Date)) +
    {if (nrow(rect_dt) > 0)
       geom_rect(data = rect_dt,
                 aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
                 inherit.aes = FALSE,
                 fill = "#FFEBEE", alpha = 0.6)
    } +
    geom_line(aes(y = MRS, color = "MRS"), linewidth = 0.9) +
    geom_line(aes(y = CumRet_scaled, color = "KOSPI200 누적수익률"),
              linewidth = 0.9, linetype = "dashed") +
    geom_hline(yintercept = c(20, 50), linetype = "dotted",
               color = c("#4CAF50", "#F44336"), linewidth = 0.4) +
    scale_color_manual(
      values = c("MRS" = "black", "KOSPI200 누적수익률" = "#1565C0"),
      name   = NULL
    ) +
    scale_y_continuous(
      name     = "MRS Score",
      limits   = c(0, 100),
      breaks   = seq(0, 100, 20),
      sec.axis = sec_axis(
        transform = ~ (. - offset) / scale_factor,
        name      = "KOSPI200 누적수익률",
        labels    = function(x) paste0(round(x * 100, 0), "%")
      )
    ) +
    scale_x_date(date_breaks = "6 months", date_labels = "%y-%m") +
    labs(
      title    = "MRS vs KOSPI200 누적수익률 (최근 3년)",
      subtitle = sprintf("%s 기준 | 음영: Crisis 구간(MRS≥50)", latest_date),
      x        = NULL
    ) +
    .mrs_theme()

  ggsave(output_path, p, width = 10, height = 5, dpi = 150)
  cat(sprintf("[mrs_dashboard] Chart 3 저장: %s\n", output_path))
  invisible(output_path)
}

# BM 없을 때 fallback: MRS 3년 단독 차트
.chart_mrs_only_3y <- function(regime_dt, output_path) {
  dt <- copy(regime_dt)
  cutoff_3y <- max(dt$Date) - 365.25 * 3
  dt3 <- dt[Date >= cutoff_3y]
  dt3[, Phase := fifelse(MRS < 20, "Normal",
                         fifelse(MRS < 50, "Caution", "Crisis"))]

  p <- ggplot(dt3, aes(x = Date, y = MRS, color = Phase)) +
    geom_line(linewidth = 0.9) +
    scale_color_manual(values = c(Normal = "#4CAF50", Caution = "#FF9800",
                                  Crisis = "#F44336")) +
    scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
    scale_x_date(date_breaks = "6 months", date_labels = "%y-%m") +
    labs(title    = "MRS Score (최근 3년)",
         subtitle = sprintf("%s 기준 (KOSPI200 BM 로드 실패)",
                            format(max(dt3$Date), "%Y-%m-%d")),
         x = NULL, y = "MRS Score") +
    .mrs_theme()

  ggsave(output_path, p, width = 10, height = 4.5, dpi = 150)
  cat(sprintf("[mrs_dashboard] Chart 3 (fallback) 저장: %s\n", output_path))
  invisible(output_path)
}


#==============================================================================
# MAIN: generate_mrs_dashboard()
#==============================================================================

#' MRS Dashboard — 최신 데이터로 차트 재생성 + 텔레그램 발송
#'
#' @param send_telegram logical. TRUE면 tg_send_photo()로 3장 발송 (default TRUE)
#' @param output_dir    차트 저장 경로 (default "/tmp/mrs_dashboard/")
#' @return list:
#'   $regime_dt     — 전체 daily MRS data.table (Date, MRS, exposure, ...)
#'   $charts        — 저장된 차트 파일 경로 벡터 (성공한 것만)
#'   $current_mrs   — 최신 MRS 값 (numeric)
#'   $current_phase — 최신 국면 문자열 ("Normal"/"Caution"/"Crisis")
#'   $latest_date   — 최신 날짜 (Date)
#' @export
generate_mrs_dashboard <- function(send_telegram = TRUE,
                                   output_dir    = "/tmp/mrs_dashboard/") {

  cat("=== [MRS Dashboard] 시작 ===\n")
  t_start <- proc.time()

  # ── 0. 의존성 로드 ──────────────────────────────────────────────────────────
  if (!exists("INFRA_DIR")) {
    source("/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot/02_Infrastructure/config.R")
  }

  # regime_engine_daily.R
  if (!exists("build_daily_regime", mode = "function")) {
    source(file.path(INFRA_DIR, "regime/regime_engine_daily.R"))
  }

  # telegram_notify.R
  if (!exists("tg_send_photo", mode = "function")) {
    source(file.path(INFRA_DIR, "telegram/telegram_notify.R"))
  }

  # ── 1. 출력 디렉토리 생성 ───────────────────────────────────────────────────
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  cat(sprintf("[mrs_dashboard] 출력 디렉토리: %s\n", output_dir))

  # ── 2. 최신 MRS 재계산 (캐시 무효화) ───────────────────────────────────────
  cat("[mrs_dashboard] MRS 재계산 중 (use_cache=FALSE)...\n")
  regime_dt <- tryCatch(
    build_daily_regime(use_cache = FALSE),
    error = function(e) {
      cat(sprintf("[mrs_dashboard] MRS 재계산 실패: %s\n  → 캐시 로드 시도\n",
                  e$message))
      build_daily_regime(use_cache = TRUE)
    }
  )

  if (is.null(regime_dt) || nrow(regime_dt) == 0) {
    stop("[mrs_dashboard] regime_dt가 비어 있습니다. FRED 캐시를 확인하세요.")
  }
  regime_dt[, Date := as.Date(Date)]
  setorder(regime_dt, Date)

  latest_row   <- regime_dt[Date == max(Date)]
  current_mrs  <- round(latest_row$MRS, 2)
  current_phase <- ifelse(current_mrs < 20, "Normal",
                          ifelse(current_mrs < 50, "Caution", "Crisis"))
  latest_date  <- max(regime_dt$Date)

  cat(sprintf("[mrs_dashboard] MRS: %.1f | 국면: %s | 최신일: %s\n",
              current_mrs, current_phase, latest_date))

  # ── 3. 차트 3장 생성 ────────────────────────────────────────────────────────
  chart_paths <- list(
    timeline = file.path(output_dir, "mrs_timeline_24m.png"),
    dist     = file.path(output_dir, "mrs_phase_dist.png"),
    kospi    = file.path(output_dir, "mrs_vs_kospi.png")
  )

  cat("[mrs_dashboard] Chart 1: MRS Timeline (24개월)...\n")
  tryCatch(
    .chart_timeline_24m(regime_dt, chart_paths$timeline),
    error = function(e) {
      cat(sprintf("[mrs_dashboard] Chart 1 실패: %s\n", e$message))
      chart_paths$timeline <<- NULL
    }
  )

  cat("[mrs_dashboard] Chart 2: 국면 분포...\n")
  tryCatch(
    .chart_phase_dist(regime_dt, chart_paths$dist),
    error = function(e) {
      cat(sprintf("[mrs_dashboard] Chart 2 실패: %s\n", e$message))
      chart_paths$dist <<- NULL
    }
  )

  cat("[mrs_dashboard] Chart 3: MRS vs KOSPI200...\n")
  tryCatch(
    .chart_mrs_vs_kospi(regime_dt, chart_paths$kospi),
    error = function(e) {
      cat(sprintf("[mrs_dashboard] Chart 3 실패: %s\n", e$message))
      chart_paths$kospi <<- NULL
    }
  )

  # 성공한 차트만 필터
  charts_ok <- Filter(function(p) !is.null(p) && file.exists(p),
                      unlist(chart_paths))
  cat(sprintf("[mrs_dashboard] 차트 %d장 생성 완료\n", length(charts_ok)))

  # ── 4. 텔레그램 발송 ────────────────────────────────────────────────────────
  if (send_telegram && length(charts_ok) > 0) {
    cat("[mrs_dashboard] 텔레그램 발송 중...\n")

    date_str   <- format(latest_date, "%Y-%m-%d")
    phase_icon <- switch(current_phase,
                         Normal  = "GREEN CIRCLE",
                         Caution = "YELLOW CIRCLE",
                         Crisis  = "RED CIRCLE",
                         "CIRCLE")

    chart_labels <- c(
      mrs_timeline_24m = "MRS Score Timeline (24M)",
      mrs_phase_dist   = "국면 분포 (전체 vs 최근 3년)",
      mrs_vs_kospi     = "MRS vs KOSPI200 (3Y)"
    )

    for (cp in charts_ok) {
      fname   <- tools::file_path_sans_ext(basename(cp))
      label   <- if (!is.null(chart_labels[[fname]])) chart_labels[[fname]] else fname
      caption <- sprintf(
        "[Q-Lead] %s MRS %s (%s 기준)\nMRS: %.1f | 국면: %s",
        phase_icon,
        label,
        date_str,
        current_mrs,
        current_phase
      )
      tryCatch(
        tg_send_photo(cp, caption = caption),
        error = function(e)
          cat(sprintf("[mrs_dashboard] 텔레그램 발송 실패 (%s): %s\n",
                      basename(cp), e$message))
      )
      Sys.sleep(0.5)
    }
    cat("[mrs_dashboard] 텔레그램 발송 완료\n")
  }

  # ── 5. 결과 반환 ────────────────────────────────────────────────────────────
  elapsed <- round((proc.time() - t_start)[["elapsed"]], 1)
  cat(sprintf("=== [MRS Dashboard] 완료 (%.1fs) — MRS %.1f | %s | 차트 %d장 ===\n",
              elapsed, current_mrs, current_phase, length(charts_ok)))

  invisible(list(
    regime_dt     = regime_dt,
    charts        = charts_ok,
    current_mrs   = current_mrs,
    current_phase = current_phase,
    latest_date   = latest_date
  ))
}
