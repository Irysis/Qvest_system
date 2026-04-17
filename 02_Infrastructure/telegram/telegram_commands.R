#!/usr/bin/env Rscript
# QEPM Telegram Command Handler
# Manager 에이전트가 텔레그램 명령어를 받아 처리
# 기존 telegram_notify.R 활용 — 원본 수정 없음

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(yaml)
})

PROJECT_ROOT <- Sys.getenv("QEPM_PROJECT_ROOT",
  "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

source(file.path(PROJECT_ROOT, "02_Infrastructure", "config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))

# ═══════════════════════════════════════════════════════════════
# 명령어 디스패처
# ═══════════════════════════════════════════════════════════════

handle_telegram_command <- function(command, args_text = "") {
  cmd <- tolower(trimws(gsub("^/", "", command)))

  result <- switch(cmd,
    "status"     = cmd_status(),
    "regime"     = cmd_regime(),
    "allocation" = cmd_allocation(),
    "memory"     = cmd_memory(),
    "backlog"    = cmd_backlog(),
    "briefing"   = cmd_briefing(),
    "grade_a"    = cmd_grade_a(),
    "help"       = cmd_help(),
    # 기본: 알 수 없는 명령어
    list(text = sprintf("알 수 없는 명령어: /%s\n/help로 사용 가능한 명령어를 확인하세요.", cmd))
  )

  # 텔레그램 전송
  if (!is.null(result$text)) {
    tg_send(result$text)
  }
  if (!is.null(result$image)) {
    tg_send_photo(result$image, caption = result$caption %||% "")
  }

  invisible(result)
}

# ═══════════════════════════════════════════════════════════════
# 개별 명령어 핸들러
# ═══════════════════════════════════════════════════════════════

cmd_status <- function() {
  # 국면
  regime_text <- tryCatch({
    source(file.path(PROJECT_ROOT, "02_Infrastructure", "regime", "regime_signal.R"))
    signal_dt <- build_regime_signal_table()
    latest <- signal_dt[.N]
    sprintf("🌐 국면: %s (MRS=%s, CrossAsset=%s/3)",
            ifelse(latest$regime_score >= 30, "RISK_OFF",
                   ifelse(latest$regime_score >= 15, "CAUTION", "RISK_ON")),
            round(latest$regime_score, 1),
            sum(c(latest$TS_Signal, latest$HY_Signal, latest$VIX_Signal) == 1, na.rm = TRUE))
  }, error = function(e) "🌐 국면: 조회 불가")

  # 메모리 현황
  memory_text <- tryCatch({
    memory_base <- file.path(PROJECT_ROOT, "memory")
    layers <- c("raw_artifacts", "episodes", "families", "evidence",
                "regime_payoff", "portfolio_policy", "post_trade")
    counts <- sapply(layers, function(l) {
      d <- file.path(memory_base, l)
      if (dir.exists(d)) length(list.files(d)) else 0
    })
    sprintf("💾 메모리: R0=%d R1=%d R2=%d R3=%d R4=%d R5=%d R6=%d",
            counts[1], counts[2], counts[3], counts[4],
            counts[5], counts[6], counts[7])
  }, error = function(e) "💾 메모리: 조회 불가")

  # 최근 전략
  registry_text <- tryCatch({
    reg_path <- file.path(PROJECT_ROOT, "registry", "strategies.json")
    if (file.exists(reg_path)) {
      reg <- fromJSON(reg_path, simplifyDataFrame = FALSE)
      sprintf("📊 전략: %d개 등록", length(reg))
    } else "📊 전략: 레지스트리 없음"
  }, error = function(e) "📊 전략: 조회 불가")

  text <- paste(
    "📋 <b>QEPM 시스템 상태</b>",
    sprintf("⏰ %s", format(Sys.time(), "%Y-%m-%d %H:%M")),
    "",
    regime_text,
    memory_text,
    registry_text,
    sep = "\n"
  )

  list(text = text)
}

cmd_regime <- function() {
  tryCatch({
    regime_json <- system2(
      "Rscript",
      c("-e", sprintf('source("%s/02_Infrastructure/config.R"); source("%s/02_Infrastructure/regime_signal.R"); r <- get_regime_at_date(Sys.Date()-1); cat(jsonlite::toJSON(r, auto_unbox=TRUE))', PROJECT_ROOT, PROJECT_ROOT)),
      stdout = TRUE, stderr = FALSE
    )
    result <- fromJSON(paste(regime_json, collapse = ""), simplifyDataFrame = FALSE)

    text <- paste(
      "🌐 <b>국면 분석 상세</b>",
      sprintf("⏰ %s", result$timestamp),
      "",
      sprintf("📊 현재 국면: <b>%s</b> (신뢰도: %.1f%%)", result$regime, result$confidence * 100),
      "",
      "📈 MRS:",
      sprintf("  Score: %s", result$mrs$mrs_score %||% "N/A"),
      sprintf("  Category: %s", result$mrs$category %||% "N/A"),
      "",
      if (!is.null(result$cross_asset)) {
        sprintf("🔗 Cross-Asset: TS=%s HY=%s VIX=%s (%d/3 signals)",
                result$cross_asset$ts_signal %||% "?",
                result$cross_asset$hy_signal %||% "?",
                result$cross_asset$vix_signal %||% "?",
                result$cross_asset$n_signals %||% 0)
      } else "🔗 Cross-Asset: N/A",
      "",
      if (!is.null(result$bcs)) {
        sprintf("📉 BCS: %.3f (Q%d)", result$bcs$bcs_value %||% 0, result$bcs$bcs_q %||% 0)
      } else "📉 BCS: N/A",
      sep = "\n"
    )

    list(text = text)
  }, error = function(e) {
    list(text = sprintf("🌐 국면 조회 실패: %s", e$message))
  })
}

cmd_allocation <- function() {
  tryCatch({
    alloc_json <- system2(
      "Rscript",
      c("-e", sprintf('source("%s/02_Infrastructure/config.R"); source("%s/02_Infrastructure/portfolio_governor.R"); gap <- pg0_gap_review("V7_ALLWEATHER_001"); cat(jsonlite::toJSON(gap, auto_unbox=TRUE))', PROJECT_ROOT, PROJECT_ROOT)),
      stdout = TRUE, stderr = FALSE
    )
    result <- fromJSON(paste(alloc_json, collapse = ""), simplifyDataFrame = FALSE)

    weights <- result$weights
    lines <- sapply(names(weights), function(s) {
      sprintf("  %s: %.1f%%", s, weights[[s]] * 100)
    })

    text <- paste(
      "⚖️ <b>현재 목표 배분</b>",
      sprintf("국면: %s", result$regime),
      "",
      paste(lines, collapse = "\n"),
      "",
      "📌 EW 가중 | 월간 리밸런싱 | BZ(50/25)",
      sep = "\n"
    )

    list(text = text)
  }, error = function(e) {
    list(text = sprintf("⚖️ 배분 조회 실패: %s", e$message))
  })
}

cmd_memory <- function() {
  tryCatch({
    memory_json <- system2(
      "Rscript",
      c("-e", sprintf('source("%s/qepm/scripts/hybrid_mode.R"); cat(jsonlite::toJSON(hybrid_status(), auto_unbox=TRUE))', PROJECT_ROOT)),
      stdout = TRUE, stderr = FALSE
    )
    result <- fromJSON(paste(memory_json, collapse = ""), simplifyDataFrame = FALSE)

    text <- paste(
      "💾 <b>메모리 파이프라인 현황</b>",
      "",
      sprintf("R0 (Raw): %d", result$layers$R0 %||% 0),
      sprintf("R1 (Digest): %d", result$layers$R1 %||% 0),
      sprintf("R2 (Family): %d", result$layers$R2 %||% 0),
      sprintf("R3 (Evidence): %d", result$layers$R3 %||% 0),
      sprintf("R4 (Regime Payoff): %d", result$layers$R4 %||% 0),
      sprintf("R5 (Portfolio Policy): %d", result$layers$R5 %||% 0),
      sprintf("R6 (Post-Trade): %d", result$layers$R6 %||% 0),
      sep = "\n"
    )

    list(text = text)
  }, error = function(e) {
    list(text = sprintf("💾 메모리 조회 실패: %s", e$message))
  })
}

cmd_backlog <- function() {
  tryCatch({
    backlog_path <- file.path(PROJECT_ROOT, "registry", "backlog.json")
    if (!file.exists(backlog_path)) {
      return(list(text = "📝 백로그: 비어있음"))
    }
    backlog <- fromJSON(backlog_path, simplifyDataFrame = FALSE)
    if (length(backlog) == 0) {
      return(list(text = "📝 백로그: 비어있음"))
    }

    top5 <- head(backlog, 5)
    lines <- sapply(seq_along(top5), function(i) {
      b <- top5[[i]]
      sprintf("%d. [%s] %s (priority: %s)",
              i, b$family %||% "?", b$objective %||% b$title %||% "?",
              b$priority %||% "?")
    })

    text <- paste(
      "📝 <b>연구 백로그 Top 5</b>",
      "",
      paste(lines, collapse = "\n"),
      sprintf("\n전체: %d개", length(backlog)),
      sep = "\n"
    )

    list(text = text)
  }, error = function(e) {
    list(text = sprintf("📝 백로그 조회 실패: %s", e$message))
  })
}

cmd_briefing <- function() {
  tryCatch({
    tg_full_briefing(slot = "AM")
    list(text = NULL)  # tg_full_briefing이 직접 전송
  }, error = function(e) {
    list(text = sprintf("📊 브리핑 생성 실패: %s", e$message))
  })
}

cmd_grade_a <- function() {
  tryCatch({
    reg_path <- file.path(PROJECT_ROOT, "06_Registry")
    if (!dir.exists(reg_path)) {
      return(list(text = "📊 레지스트리 디렉토리 없음"))
    }

    hurdle_files <- list.files(reg_path, pattern = "hurdle_result\\.json$",
                                recursive = TRUE, full.names = TRUE)
    grade_a <- list()
    for (f in hurdle_files) {
      h <- tryCatch(fromJSON(f, simplifyDataFrame = FALSE), error = function(e) NULL)
      if (!is.null(h) && (h$verdict$grade %||% "") == "A") {
        grade_a <- c(grade_a, list(list(
          strategy = h$verdict$strategy %||% basename(dirname(f)),
          score    = h$verdict$score %||% 0,
          sharpe   = h$verdict$sharpe %||% 0,
          cagr     = h$verdict$net_cagr %||% 0
        )))
      }
    }

    if (length(grade_a) == 0) {
      return(list(text = "⭐ Grade A 전략: 0개"))
    }

    # Score 기준 정렬
    scores <- sapply(grade_a, function(x) x$score)
    grade_a <- grade_a[order(-scores)]
    top10 <- head(grade_a, 10)

    lines <- sapply(seq_along(top10), function(i) {
      s <- top10[[i]]
      sprintf("%d. %s (Score %.1f, Sharpe %.3f, CAGR %.1f%%)",
              i, s$strategy, s$score, s$sharpe, s$cagr * 100)
    })

    text <- paste(
      sprintf("⭐ <b>Grade A 전략 Top 10</b> (전체 %d개)", length(grade_a)),
      "",
      paste(lines, collapse = "\n"),
      sep = "\n"
    )

    list(text = text)
  }, error = function(e) {
    list(text = sprintf("⭐ Grade A 조회 실패: %s", e$message))
  })
}

cmd_help <- function() {
  text <- paste(
    "📖 <b>QEPM 명령어 목록</b>",
    "",
    "/status — 시스템 상태 (국면, 메모리, 전략)",
    "/regime — 국면 분석 상세",
    "/allocation — 현재 목표 배분",
    "/memory — 메모리 파이프라인 현황",
    "/backlog — 연구 백로그 Top 5",
    "/briefing — 최근 브리핑 재전송",
    "/grade_a — Grade A 전략 Top 10",
    "/help — 이 도움말",
    "",
    "자유형 질문도 가능합니다.",
    sep = "\n"
  )

  list(text = text)
}

# ═══════════════════════════════════════════════════════════════
# CLI 진입점
# ═══════════════════════════════════════════════════════════════

if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1) {
    cmd <- args[1]
    args_text <- if (length(args) > 1) paste(args[-1], collapse = " ") else ""
    handle_telegram_command(cmd, args_text)
  } else {
    cat("Usage: Rscript telegram_commands.R <command> [args]\n")
  }
}
