#==============================================================================
# Quant Module — Telegram Notification Module
# telegram_notify.R
#
# Functions:
#   tg_send(msg)                          — plain HTML message
#   tg_strategy_result(name, hurdle)      — result + score breakdown
#   tg_strategy_result_with_chart(...)    — above + equity + annual charts
#   tg_pass_analysis(name, output_dir)    — PASS 전략 팩터 분석 요약
#   tg_dart_progress(done, total)         — DART 수집 진행률
#   tg_dart_complete(ok, empty, fail)     — DART 완료 알림
#   tg_paper_analyzed(id, title, idea)    — 논문 분석 완료
#   tg_briefing(content, slot)            — 단순 브리핑
#   tg_full_briefing(slot)                — 전체 브리핑 (전략+리서치+차트)
#   tg_error(strategy_name, error_msg)    — 오류 알림
#   tg_send_photo(path, caption)          — 사진 전송
#   tg_send_document(path, caption)       — 파일 전송
#==============================================================================

suppressPackageStartupMessages(library(httr))
suppressPackageStartupMessages(library(jsonlite))

# ─── Credentials (.env 로드, hardcoded 금지 — 2026-04-17 rotation) ───────────
.tg_load_env <- function() {
  candidates <- c(
    "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot/.env",
    Sys.getenv("QVEST_PROJECT_DIR", ""),
    getwd()
  )
  for (p in candidates) {
    env_path <- if (file.exists(p)) p else file.path(p, ".env")
    if (file.exists(env_path)) {
      lines <- readLines(env_path, warn = FALSE)
      for (ln in lines) {
        ln <- trimws(ln)
        if (!nzchar(ln) || startsWith(ln, "#") || !grepl("=", ln, fixed = TRUE)) next
        kv <- strsplit(ln, "=", fixed = TRUE)[[1]]
        if (length(kv) >= 2 && !nzchar(Sys.getenv(kv[1]))) {
          do.call(Sys.setenv, setNames(list(paste(kv[-1], collapse = "=")), kv[1]))
        }
      }
      break
    }
  }
}
.tg_load_env()

.TG_TOKEN      <- Sys.getenv("TG_BOT_TOKEN", "")
.TG_CHAT_ID    <- Sys.getenv("TG_CHAT_ID", "")  # 비공개 채널 (전략 브리핑 채널)
.TG_PERSONAL   <- Sys.getenv("TG_PERSONAL_CHAT_ID", "1355291682")   # 개인 DM fallback
if (!nzchar(.TG_TOKEN) || !nzchar(.TG_CHAT_ID)) {
  warning("[telegram_notify] TG_BOT_TOKEN / TG_CHAT_ID 미설정. .env 확인.")
}
.TG_BASE       <- sprintf("https://api.telegram.org/bot%s", .TG_TOKEN)
.TG_API        <- paste0(.TG_BASE, "/sendMessage")

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ─── 전략명+아이디어 추출 헬퍼 ───────────────────────────────────────────────
.extract_strategy_display <- function(strategy_name, output_dir) {
  # output_dir = .../STR_XXX/output/STR_XXX → run_all.R은 2단계 위
  str_dir <- dirname(output_dir)
  # run_all.R 탐색: 현재 dir → 상위 → 2단계 상위
  run_path <- ""
  for (candidate in c(str_dir, dirname(str_dir), dirname(dirname(str_dir)))) {
    p <- file.path(candidate, "run_all.R")
    if (file.exists(p)) { run_path <- p; str_dir <- candidate; break }
  }
  display <- strategy_name
  idea <- ""

  # 1. run_all.R cat("=== STR_XXX: Description ===\n")
  if (file.exists(run_path)) {
    tryCatch({
      lines <- readLines(run_path, n = 15, warn = FALSE)
      m <- grep("cat.*===.*STR_\\d+", lines, value = TRUE)
      if (length(m) > 0) {
        extracted <- regmatches(m[1], regexpr("STR_\\d+[^=]+", m[1]))
        if (length(extracted) > 0) {
          extracted <- trimws(sub("[: ]+$", "", extracted[1]))
          if (nchar(extracted) > nchar(strategy_name) + 2)
            display <- extracted
        }
      }
      # run_all.R ## 주석에서 핵심아이디어 추출 (2~5번째 줄)
      if (idea == "") {
        comment_lines <- grep("^##\\s+", lines, value = TRUE)
        comment_lines <- comment_lines[!grepl("^##\\s*STR_\\d+", comment_lines)]  # 제목줄 제외
        if (length(comment_lines) > 0) {
          idea <- trimws(sub("^##\\s*", "", comment_lines[1]))
          idea <- gsub("^[\"']|[\"']$", "", idea)  # 따옴표 제거
        }
      }
    }, error = function(e) NULL)
  }

  # 2. factor_engine.R cat("[factor_engine] STR_XXX: Description...\n")
  fe_path <- file.path(str_dir, "factor_engine.R")
  if (file.exists(fe_path)) {
    tryCatch({
      lines <- readLines(fe_path, n = 10, warn = FALSE)
      m <- grep("cat.*factor_engine.*STR_\\d+", lines, value = TRUE)
      if (length(m) > 0) {
        extracted <- regmatches(m[1], regexpr("STR_\\d+:\\s*[^.\"]+", m[1]))
        if (length(extracted) > 0) {
          idea <- trimws(sub("^STR_\\d+:\\s*", "", extracted[1]))
        }
      }
      # Also try comment headers: ## STR_XXX  Description
      if (display == strategy_name) {
        hdr <- grep("^##?\\s*STR_\\d+", lines, value = TRUE)
        if (length(hdr) > 0) {
          cleaned <- sub("^##?\\s*", "", hdr[1])
          if (nchar(cleaned) > nchar(strategy_name) + 2)
            display <- trimws(cleaned)
        }
      }
    }, error = function(e) NULL)
  }

  # 3. hurdle_result.json에서 전략 설명 추출
  if (idea == "") {
    hr_path <- file.path(output_dir, "hurdle_result.json")
    if (file.exists(hr_path)) {
      tryCatch({
        hr <- jsonlite::fromJSON(hr_path, simplifyVector = FALSE)
        # role + grade + metrics로 자동 설명 생성
        role <- hr$role %||% "core"
        grade <- hr$grade %||% "?"
        m <- hr$metrics %||% list()
        n_sleeves <- length(list.files(str_dir, pattern = "^sim_sleeve_.*\\.rds$"))
        if (n_sleeves == 0) n_sleeves <- length(list.files(dirname(str_dir), pattern = "^sim_sleeve_.*\\.rds$"))

        # 전략 구조 설명
        struct <- if (n_sleeves >= 3) sprintf("%d-Sleeve Ensemble", n_sleeves)
                  else if (n_sleeves == 2) "2-Sleeve"
                  else "Single Factor"

        idea <- sprintf("%s | %s | SR %.3f | CAGR %.1f%% | MDD %.1f%%",
                        struct, role,
                        as.numeric(m$Sharpe %||% 0),
                        as.numeric(m$CAGR %||% 0),
                        as.numeric(m$MDD %||% 0))
      }, error = function(e) NULL)
    }
  }

  # 4. Directory name fallback: STR_559_entropy_gate → "Entropy Gate"
  if (display == strategy_name) {
    dir_name <- basename(str_dir)
    parts <- strsplit(dir_name, "_")[[1]]
    if (length(parts) >= 3) {
      desc_parts <- parts[3:length(parts)]
      desc_parts <- sapply(desc_parts, function(w)
        paste0(toupper(substr(w, 1, 1)), substr(w, 2, nchar(w))))
      display <- paste(strategy_name, paste(desc_parts, collapse = " "))
    }
  }

  # idea가 display와 거의 같으면 중복 제거
  if (nchar(idea) > 0 && grepl(gsub("[^a-zA-Z0-9]", "", idea),
                                gsub("[^a-zA-Z0-9]", "", display), fixed = TRUE))
    idea <- ""

  list(display = display, idea = idea)
}

# ─── Core send function ───────────────────────────────────────────────────────
tg_send <- function(msg, parse_mode = "", silent = FALSE,
                     validate_emoji = TRUE, emoji_min = 1L) {
  # 2026-04-23: 기본 parse_mode "" (plain). HTML은 <, > 기호로 parse error 유발.
  # 2026-04-24: validate_emoji — 이모지 0개 감지 시 warning log (Judge/Risk 누락 방지)
  if (validate_emoji) {
    # Unicode emoji 범위 (1F300~1F9FF 확장 + 2600~27BF 기본)
    emoji_n <- length(
      regmatches(msg, gregexpr("[\U0001F300-\U0001F9FF☀-➿]", msg))[[1]]
    )
    if (!is.finite(emoji_n)) emoji_n <- 0L
    if (emoji_n < emoji_min) {
      warn_line <- sprintf(
        "%s [tg_send WARN] emoji count %d < min %d (msg first 60: '%s')",
        format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
        emoji_n, emoji_min, substr(msg, 1, 60)
      )
      cat(warn_line, "\n", sep = "")
      try(cat(warn_line, "\n", file = "/tmp/qvest_tg_emoji_warn.log",
              append = TRUE, sep = ""),
          silent = TRUE)
    }
  }

  tryCatch({
    resp <- POST(.TG_API, body = list(
      chat_id    = .TG_CHAT_ID,
      text       = msg,
      parse_mode = parse_mode
    ), encode = "json")
    if (!silent && http_error(resp)) {
      cat(sprintf("[tg] Send failed: %s\n", content(resp, "text", encoding = "UTF-8")))
    }
    invisible(resp)
  }, error = function(e) {
    cat(sprintf("[tg] Error: %s\n", e$message))
  })
}

# ─── 표 포맷 헬퍼 (Step 6, 2026-04-24) ─────────────────────────────────────
# data.frame → <pre> HTML 블록. 고정폭 공백 정렬. tg_send_rich와 함께 사용.
tg_format_table <- function(df, separator = "-") {
  if (!is.data.frame(df) || nrow(df) == 0) return("")
  # 각 column 최대 너비 = max(header, values)
  cols <- names(df)
  char_df <- as.data.frame(lapply(df, function(x) as.character(x)),
                            stringsAsFactors = FALSE)
  widths <- mapply(function(colname, vals) {
    max(nchar(colname, type = "width"),
        max(nchar(vals, type = "width"), na.rm = TRUE))
  }, cols, char_df, USE.NAMES = FALSE)

  pad <- function(s, w) {
    spc <- w - nchar(s, type = "width")
    if (spc > 0) paste0(s, strrep(" ", spc)) else s
  }

  header <- paste(mapply(pad, cols, widths), collapse = "  ")
  sep_line <- paste(sapply(widths, function(w) strrep(separator, w)),
                     collapse = "  ")
  body_rows <- apply(char_df, 1, function(row_vals) {
    paste(mapply(pad, as.character(row_vals), widths), collapse = "  ")
  })

  paste0("<pre>",
         paste(c(header, sep_line, body_rows), collapse = "\n"),
         "</pre>")
}

# ─── Rich send (HTML parse_mode) ───────────────────────────────────────────
# <pre> 표 / <b> 강조 등 HTML 허용. Message 내 &, <, > 는 caller가 escape 필수
# (tg_format_table는 이미 plain 입력).
tg_send_rich <- function(msg, silent = FALSE,
                          validate_emoji = TRUE, emoji_min = 1L) {
  tg_send(msg, parse_mode = "HTML", silent = silent,
          validate_emoji = validate_emoji, emoji_min = emoji_min)
}

# HTML-safe escape 헬퍼 (표 밖 일반 텍스트에 < > & 있을 때 사용)
tg_html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x
}

# ─── Photo / Document send ────────────────────────────────────────────────────
tg_send_photo <- function(image_path, caption = "", parse_mode = "") {
  if (!file.exists(image_path)) {
    cat(sprintf("[tg] Photo not found: %s\n", image_path))
    return(invisible(NULL))
  }
  tryCatch({
    resp <- POST(
      paste0(.TG_BASE, "/sendPhoto"),
      body = list(
        chat_id    = .TG_CHAT_ID,
        photo      = upload_file(image_path),
        caption    = caption,
        parse_mode = parse_mode
      ),
      encode = "multipart"
    )
    if (http_error(resp)) {
      cat(sprintf("[tg] Photo failed: %s\n", content(resp, "text", encoding = "UTF-8")))
    }
    invisible(resp)
  }, error = function(e) cat(sprintf("[tg] Photo error: %s\n", e$message)))
}

tg_send_document <- function(file_path, caption = "") {
  if (!file.exists(file_path)) return(invisible(NULL))
  tryCatch({
    resp <- POST(
      paste0(.TG_BASE, "/sendDocument"),
      body = list(
        chat_id  = .TG_CHAT_ID,
        document = upload_file(file_path),
        caption  = caption
      ),
      encode = "multipart"
    )
    invisible(resp)
  }, error = function(e) cat(sprintf("[tg] Doc error: %s\n", e$message)))
}

# ─── Strategy result (텍스트 + 점수 세부) ─────────────────────────────────────
tg_strategy_result <- function(strategy_name, hurdle_result) {
  verdict_str <- if (isTRUE(hurdle_result$pass)) "✅ PASS" else "❌ FAIL"
  # Use [["score"]] to avoid R partial matching ($score → $score_breakdown)
  score  <- as.numeric(hurdle_result[["score"]] %||% hurdle_result[["total_score"]] %||% 0)
  v      <- hurdle_result[["verdict"]] %||% hurdle_result
  m      <- v[["metrics"]] %||% list()
  sb     <- v[["score_breakdown"]] %||% list()

  .n <- function(x) { val <- as.numeric(x); if (length(val) == 0 || is.na(val[1])) 0 else val[1] }

  # Hard fail 사유
  hard_fail_str <- if (isTRUE(v[["hard_fail"]])) {
    fr <- v[["fail_reasons"]]
    if (is.list(fr)) fr <- unlist(fr)
    sprintf("\n⛔ Hard Fail: %s", paste(fr, collapse = " | "))
  } else ""

  # ── 점수 세부 (score_breakdown 있을 때만) ──
  score_detail_str <- ""
  if (length(sb) > 0) {
    # 라벨 정의
    labels <- list(
      sharpe      = list(label = "SR",      max = 20),
      ir          = list(label = "IR",      max = 15),
      cagr        = list(label = "CAGR",    max = 15),
      rolling     = list(label = "Roll",    max = 15),
      stress      = list(label = "Stress",  max = 10),
      mdd         = list(label = "MDD",     max = 10),
      calmar      = list(label = "Calmar",  max = 10),
      params      = list(label = "Params",  max = 5),
      alpha_trend  = list(label = "Trend",   max = 10),  # [-10 ~ +10]
      oos          = list(label = "OOS",     max = 8),   # [-8 ~ +8]
      ic_stability = list(label = "ICSt",   max = 6)    # [-6 ~ +6]
    )
    # 효율(score/max) 기준 정렬해서 강점 2개, 약점 2개 추출
    eff <- sapply(names(labels), function(nm) {
      s  <- as.numeric(sb[[nm]]$score %||% 0)
      mx <- as.numeric(labels[[nm]]$max)
      s / mx
    })
    sorted_names <- names(sort(eff))  # 오름차순 = 약점 먼저

    fmt_item <- function(nm) {
      lbl <- labels[[nm]]$label
      s   <- as.numeric(sb[[nm]]$score %||% 0)
      mx  <- as.numeric(labels[[nm]]$max)
      # 조정 항목 (음수 가능): 부호 명시
      if (nm %in% c("alpha_trend", "oos", "ic_stability")) {
        icon <- if (s > 1) "↑" else if (s < -1) "↓" else "→"
        sprintf("%s%s%+.1f/%d", icon, lbl, s, mx)
      } else {
        sprintf("%s %.1f/%d", lbl, s, mx)
      }
    }

    weak2   <- sorted_names[1:min(2, length(sorted_names))]
    strong2 <- rev(sorted_names)[1:min(2, length(sorted_names))]

    # 주요 항목 한줄 표시 (alpha_trend 포함)
    main_items <- c("sharpe", "ir", "cagr", "rolling", "alpha_trend")
    main_row <- paste(sapply(intersect(main_items, names(sb)), fmt_item), collapse = " │ ")

    score_detail_str <- sprintf(
      "\n─────────────\n📊 점수 세부 (%.1f/100)\n%s\n✅ 강점: %s\n⚠️ 약점: %s",
      score,
      main_row,
      paste(sapply(strong2, fmt_item), collapse = " │ "),
      paste(sapply(weak2,   fmt_item), collapse = " │ ")
    )
  }

  # Family info (from auto-commit hook context)
  family_str <- ""
  if (exists(".qepm_last_family") && nzchar(.qepm_last_family %||% "")) {
    family_str <- sprintf("\nFamily: %s", .qepm_last_family)
  }

  msg <- sprintf(
    "[백테스트 완료] %s\n%s (%.1f/100)%s\n─────────────\nCAGR: %.1f%% │ Sharpe: %.3f\nMDD: %.1f%% │ IR: %.3f │ Calmar: %.3f%s%s",
    strategy_name, verdict_str, score, hard_fail_str,
    .n(m$CAGR), .n(m$Sharpe), .n(m$MDD), .n(m$IR), .n(m$Calmar),
    family_str, score_detail_str
  )
  tg_send(msg)
}

# ─── Strategy Commentary (5줄 인사이트) ─────────────────────────────────────
tg_strategy_commentary <- function(strategy_name, hurdle_result, output_dir) {
  v  <- hurdle_result[["verdict"]] %||% hurdle_result
  m  <- v[["metrics"]] %||% list()
  sb <- v[["score_breakdown"]] %||% list()
  .n <- function(x) { val <- as.numeric(x); if (length(val) == 0 || is.na(val[1])) 0 else val[1] }

  passed <- isTRUE(hurdle_result[["pass"]])
  score  <- .n(hurdle_result[["score"]] %||% hurdle_result[["total_score"]])
  cagr   <- .n(m$CAGR)
  sharpe <- .n(m$Sharpe)
  mdd    <- .n(m$MDD)
  ir     <- .n(m$IR)
  d061   <- .n(sb$alpha_trend$score)
  d062   <- .n(sb$oos$score)

  # ── 코멘트 생성 ──
  # strategy_name은 이미 [코멘트] 헤더에 표시되므로 중복 제목 제거
  lines <- character(0)

  # 1. 한줄 요약 판정
  if (passed) {
    lines <- c(lines, sprintf("✅ 허들 통과! 실전 후보 등록 (%.1f점)", score))
  } else if (score >= 55) {
    lines <- c(lines, sprintf("🟡 근접 (%.1f점) — 앙상블 후보로 가치 있음", score))
  } else if (score >= 40) {
    lines <- c(lines, sprintf("🟠 중간 (%.1f점) — 팩터 신호 자체는 유의미", score))
  } else {
    lines <- c(lines, sprintf("🔴 약함 (%.1f점) — 단독 운용 불가", score))
  }

  # 2. MDD 분석
  if (abs(mdd) > 45) {
    lines <- c(lines, sprintf("⛔ MDD %.1f%% — 하드페일. 레짐 게이팅 강화 필요", mdd))
  } else if (abs(mdd) > 40) {
    lines <- c(lines, sprintf("⚠️ MDD %.1f%% — 경계선. 방어 팩터 블렌딩 고려", mdd))
  } else {
    lines <- c(lines, sprintf("🛡 MDD %.1f%% — 양호. 방어력 우수", mdd))
  }

  # 3. 최근 트렌드
  if (d061 > 3) {
    lines <- c(lines, "📈 최근 성과 급상승 — 현재 시장에 매우 적합")
  } else if (d061 > 0) {
    lines <- c(lines, "📊 최근 성과 개선 — 긍정적 추세")
  } else if (d061 < -3) {
    lines <- c(lines, "📉 최근 성과 급락 — 팩터 구조 변화 가능성")
  } else {
    lines <- c(lines, "➡️ 최근 성과 보합 — 안정적이나 알파 약화")
  }

  # 4. 알파 진단
  if (ir > 0.3) {
    lines <- c(lines, sprintf("💎 IR %.3f — 벤치마크 대비 강한 알파", ir))
  } else if (ir > 0) {
    lines <- c(lines, sprintf("📌 IR %.3f — 약한 알파, 볼 관리가 핵심", ir))
  } else {
    lines <- c(lines, sprintf("❌ IR %.3f — 알파 부재, BM 대비 언더퍼폼", ir))
  }

  # 5. 앙상블 활용 제안
  if (!passed && score >= 40 && abs(mdd) < 55) {
    lines <- c(lines, "🔧 앙상블 후보: 방어 팩터 블렌딩으로 MDD 개선 가능")
  } else if (passed) {
    lines <- c(lines, "🏆 단독 운용 가능. 다른 PASS 전략과 포트폴리오 조합 권장")
  } else {
    lines <- c(lines, "📝 참고 수준. 팩터 신호는 다른 전략의 보조 인자로 활용")
  }

  msg <- sprintf("[코멘트] %s\n%s", strategy_name, paste(lines, collapse = "\n"))
  tg_send(msg)
}

# ─── 누적 교훈 발송 (10개 단위, 새 교훈만) ──────────────────────────────────
tg_cumulative_lessons <- function() {
  lesson_file <- file.path(PROJECT_ROOT, "04_Research", "lessons_sent.json")
  postmortem_file <- file.path(PROJECT_ROOT, "04_Research", "strategy_postmortem.md")

  # 포스트모템 파일에서 교훈 파싱
  if (!file.exists(postmortem_file)) return(invisible(NULL))
  pm_lines <- readLines(postmortem_file, warn = FALSE)
  lesson_lines <- grep("^###\\s*(Lesson\\s+)?L-", pm_lines, value = TRUE)
  if (length(lesson_lines) == 0) return(invisible(NULL))

  # 이미 보낸 교훈 ID 로드
  sent_ids <- character(0)
  if (file.exists(lesson_file)) {
    sent_data <- tryCatch(jsonlite::fromJSON(lesson_file), error = function(e) list(sent = character(0)))
    sent_ids <- sent_data$sent %||% character(0)
  }

  # 새 교훈만 추출
  new_lessons <- character(0)
  new_ids     <- character(0)
  for (ll in lesson_lines) {
    lid <- regmatches(ll, regexpr("L-\\d+", ll))
    if (length(lid) > 0 && !lid %in% sent_ids) {
      new_lessons <- c(new_lessons, ll)
      new_ids     <- c(new_ids, lid)
    }
  }

  # 10개 이상 쌓였을 때만 발송
  if (length(new_lessons) < 10) return(invisible(NULL))

  # 10개씩 묶어서 발송
  batch <- new_lessons[1:10]
  batch_ids <- new_ids[1:10]
  msg <- sprintf(
    "[누적 교훈 업데이트] 새 교훈 %d건\n─────────────\n%s",
    length(batch),
    paste(gsub("^###\\s*(Lesson\\s+)?", "- ", batch), collapse = "\n")
  )
  tg_send(msg)

  # 보낸 ID 저장
  all_sent <- c(sent_ids, batch_ids)
  writeLines(jsonlite::toJSON(list(sent = all_sent), auto_unbox = TRUE), lesson_file)
  cat(sprintf("[tg] Sent %d new lessons (total sent: %d)\n", length(batch), length(all_sent)))
}

# ─── Strategy result + 차트 2장 + 코멘트 (equity curve + annual returns) ─────
tg_strategy_result_with_chart <- function(strategy_name, hurdle_result, output_dir) {
  # 전략명+아이디어 자동 추출
  info <- .extract_strategy_display(strategy_name, output_dir)
  display_name <- info$display
  if (nchar(info$idea) > 0)
    display_name <- sprintf("%s\n  %s", display_name, info$idea)

  # 1. 텍스트 + 점수 세부
  tg_strategy_result(display_name, hurdle_result)
  Sys.sleep(0.5)

  verdict <- if (isTRUE(hurdle_result[["pass"]])) "PASS" else "FAIL"

  # 2. Equity curve
  equity_path <- file.path(output_dir, "equity_curve.png")
  if (file.exists(equity_path)) {
    tg_send_photo(equity_path,
                  caption = sprintf("%s — Equity Curve (%s)", display_name, verdict))
    Sys.sleep(0.3)
  }

  # 3. Annual returns
  annual_path <- file.path(output_dir, "annual_returns.png")
  if (file.exists(annual_path)) {
    tg_send_photo(annual_path,
                  caption = sprintf("%s — Annual Returns (%s)", display_name, verdict))
    Sys.sleep(0.3)
  }

  # 4. 5줄 코멘트 (NEW)
  Sys.sleep(0.3)
  tg_strategy_commentary(display_name, hurdle_result, output_dir)

  # 5. PASS 전략은 팩터 분석 요약도 전송
  if (isTRUE(hurdle_result[["pass"]])) {
    tg_pass_analysis(strategy_name, output_dir)
  }

  # 6. 누적 교훈 체크 (10개 단위 발송)
  tryCatch(tg_cumulative_lessons(), error = function(e) {
    cat(sprintf("[tg] Lesson check skipped: %s\n", e$message))
  })
}

# ─── PASS 전략 팩터 분석 요약 (strategy_analyzer.R 산출물) ────────────────────
# analysis_report.md에서 IC/Rolling/Stress/Turnover 핵심 수치 추출해서 전송
tg_pass_analysis <- function(strategy_name, output_dir) {
  Sys.sleep(0.3)

  # analysis_report.md 파싱
  report_path <- file.path(output_dir, "analysis_report.md")
  ic_str <- rolling_str <- stress_str <- turnover_str <- hhi_str <- NA_character_

  if (file.exists(report_path)) {
    lines <- readLines(report_path, warn = FALSE)

    .grab <- function(pattern) {
      hit <- grep(pattern, lines, value = TRUE)
      if (length(hit) == 0) return(NA_character_)
      # Strip markdown bold (**) and leading "- "
      trimws(gsub("\\*\\*|^- ", "", hit[1]))
    }

    ic_str      <- .grab("IC Mean")
    rolling_str <- .grab("1Y Rolling Sharpe")
    stress_str  <- .grab("Outperform rate vs BM")
    turnover_str <- .grab("Avg Period Turnover")
    hhi_str     <- .grab("Avg Sector HHI")
  }

  # analysis_ic.csv에서 직접 읽기 (fallback)
  if (is.na(ic_str)) {
    ic_path <- file.path(output_dir, "analysis_ic.csv")
    if (file.exists(ic_path)) {
      ic_dt <- tryCatch(read.csv(ic_path), error = function(e) NULL)
      if (!is.null(ic_dt) && nrow(ic_dt) > 0) {
        ic_mean <- round(mean(ic_dt$IC, na.rm = TRUE), 4)
        icir    <- round(mean(ic_dt$IC, na.rm = TRUE) / sd(ic_dt$IC, na.rm = TRUE), 3)
        pos_r   <- round(mean(ic_dt$IC > 0, na.rm = TRUE) * 100, 1)
        ic_str <- sprintf("IC Mean: %.4f │ ICIR: %.3f │ IC>0: %.1f%%",
                          ic_mean, icir, pos_r)
      }
    }
  }

  # analysis_stress.csv에서 직접 읽기 (fallback)
  if (is.na(stress_str)) {
    stress_path <- file.path(output_dir, "analysis_stress.csv")
    if (file.exists(stress_path)) {
      st_dt <- tryCatch(read.csv(stress_path), error = function(e) NULL)
      if (!is.null(st_dt) && nrow(st_dt) > 0 && "Outperform" %in% names(st_dt)) {
        n_out <- sum(st_dt$Outperform, na.rm = TRUE)
        n_tot <- nrow(st_dt)
        stress_str <- sprintf("Stress 아웃퍼폼: %d/%d (%.0f%%)",
                              n_out, n_tot, n_out / n_tot * 100)
      }
    }
  }

  lines_out <- c()
  if (!is.null(ic_str)      && !is.na(ic_str))      lines_out <- c(lines_out, sprintf("📈 %s", ic_str))
  if (!is.null(rolling_str) && !is.na(rolling_str)) lines_out <- c(lines_out, sprintf("🔄 %s", rolling_str))
  if (!is.null(stress_str)  && !is.na(stress_str))  lines_out <- c(lines_out, sprintf("🛡 %s", stress_str))
  if (!is.null(turnover_str)&& !is.na(turnover_str)) lines_out <- c(lines_out, sprintf("🔁 %s", turnover_str))
  if (!is.null(hhi_str)     && !is.na(hhi_str))     lines_out <- c(lines_out, sprintf("🗂 %s", hhi_str))

  # FMB regression results with grade emoji
  fmb_path <- file.path(output_dir, "analysis_fmb_summary.csv")
  if (file.exists(fmb_path)) {
    fmb_dt <- tryCatch(read.csv(fmb_path), error = function(e) NULL)
    if (!is.null(fmb_dt) && nrow(fmb_dt) > 0) {
      score_row <- fmb_dt[fmb_dt$Variable == "Score", ]
      if (nrow(score_row) > 0) {
        t_val <- score_row$t_stat_NW
        sig_star <- if (isTRUE(score_row$Significant)) "*" else ""
        # FMB grade: t>2.58=A, t>1.96=B, t>1.65=C, else D
        fmb_grade <- if (abs(t_val) >= 2.58) "\U0001f525A"
                     else if (abs(t_val) >= 1.96) "\u2705B"
                     else if (abs(t_val) >= 1.65) "\U0001f7e1C"
                     else "\u26a0\ufe0fD"
        fmb_str <- sprintf("FMB [%s] t=%.2f%s | lambda=%.5f | R2=%.3f",
                           fmb_grade, t_val, sig_star,
                           score_row$Lambda_Mean, score_row$Avg_R2)
        lines_out <- c(lines_out, sprintf("📊 %s", fmb_str))
      }
    }
  }

  # Multi-factor regression results with alpha grade
  mf_path <- file.path(output_dir, "analysis_multifactor.csv")
  if (file.exists(mf_path)) {
    mf_dt <- tryCatch(read.csv(mf_path), error = function(e) NULL)
    if (!is.null(mf_dt) && nrow(mf_dt) > 0) {
      for (j in seq_len(nrow(mf_dt))) {
        r <- mf_dt[j, ]
        t_a <- abs(r$Alpha_tstat)
        sig <- if (t_a >= 1.96) "*" else ""
        # Alpha grade: t>2.58=A, t>1.96=B, t>1.65=C, else D
        a_grade <- if (t_a >= 2.58) "\U0001f525"
                   else if (t_a >= 1.96) "\u2705"
                   else if (t_a >= 1.65) "\U0001f7e1"
                   else "\u26aa"
        mf_str <- sprintf("%s %s: a=%.1f%%/yr (t=%.2f%s) R2=%.3f",
                          a_grade, r$Model, r$Alpha_Annual_Pct, r$Alpha_tstat, sig, r$Adj_R2)
        lines_out <- c(lines_out, mf_str)
      }
    }
  }

  if (length(lines_out) == 0) return(invisible(NULL))

  msg <- sprintf("[팩터 분석] %s\n─────────────\n%s",
                 strategy_name, paste(lines_out, collapse = "\n"))
  tg_send(msg)
}

# ─── DART 수집 진행률 ──────────────────────────────────────────────────────────
tg_dart_progress <- function(done, total, ok_count = NULL, fail_count = NULL) {
  pct   <- round(done / total * 100, 1)
  extra <- if (!is.null(ok_count))
    sprintf("\nOK: %d │ FAIL: %d", ok_count, fail_count) else ""
  msg <- sprintf("[DART 수집] %d/%d (%.1f%%)%s", done, total, pct, extra)
  tg_send(msg)
}

# ─── DART 완료 ────────────────────────────────────────────────────────────────
tg_dart_complete <- function(ok_count, empty_count, fail_count) {
  msg <- sprintf(
    "[DART 수집 완료] ✅\nOK: %d │ EMPTY: %d │ FAIL: %d\n펀더멘털 팩터 계산 준비 완료",
    ok_count, empty_count, fail_count
  )
  tg_send(msg)
}

# ─── 논문 분석 완료 ────────────────────────────────────────────────────────────
tg_paper_analyzed <- function(paper_id, title, idea_summary = NULL) {
  extra <- if (!is.null(idea_summary)) sprintf("\n💡 %s", idea_summary) else ""
  msg <- sprintf("[논문 분석] %s\n%s%s", paper_id, title, extra)
  tg_send(msg)
}

# ─── 오류 알림 ────────────────────────────────────────────────────────────────
tg_error <- function(strategy_name, error_msg) {
  msg <- sprintf("[오류] %s\n<code>%s</code>",
                 strategy_name, substr(error_msg, 1, 300))
  tg_send(msg)
}

# ─── 단순 브리핑 ──────────────────────────────────────────────────────────────
tg_briefing <- function(content, slot = "AM") {
  header <- sprintf("[%s 브리핑] %s", slot, format(Sys.Date(), "%Y-%m-%d"))
  msg <- paste(header, content, sep = "\n─────────────\n")
  tg_send(msg)
}

# ─── 전체 브리핑 (전략 스코어보드 + 리서치 진행률 + DART + 베스트 차트) ──────
tg_full_briefing <- function(slot = "AM") {
  cat("[tg_briefing] Generating full briefing...\n")
  today <- format(Sys.Date(), "%Y-%m-%d")

  # ── 1. 전략 스코어보드 ──
  reg_path <- file.path(PROJECT_ROOT, "06_Registry", "strategy_registry.json")
  strats   <- NULL
  score_text <- "전략 없음"

  if (file.exists(reg_path)) {
    strats <- tryCatch(jsonlite::fromJSON(reg_path), error = function(e) NULL)
    if (!is.null(strats) && is.data.frame(strats) && nrow(strats) > 0) {
      n_pass <- sum(as.logical(strats$hurdle_pass), na.rm = TRUE)
      n_fail <- nrow(strats) - n_pass

      # PASS 전략 먼저, 그 다음 FAIL 상위 — 합쳐서 5개
      pass_rows <- strats[as.logical(strats$hurdle_pass) %in% TRUE, ]
      fail_rows <- strats[!as.logical(strats$hurdle_pass) %in% TRUE, ]
      pass_rows <- pass_rows[order(-pass_rows$hurdle_score), ]
      fail_rows <- fail_rows[order(-fail_rows$hurdle_score), ]

      n_show <- 5
      top <- rbind(
        head(pass_rows, min(n_show, nrow(pass_rows))),
        head(fail_rows, max(0, n_show - nrow(pass_rows)))
      )

      rows <- apply(top, 1, function(r) {
        icon <- if (isTRUE(as.logical(r["hurdle_pass"]))) "✅" else "❌"
        cagr_val <- suppressWarnings(as.numeric(r["cagr"]))
        sr_val   <- suppressWarnings(as.numeric(r["sharpe"]))
        mdd_val  <- suppressWarnings(as.numeric(r["mdd"]))
        sc_val   <- suppressWarnings(as.numeric(r["hurdle_score"]))
        sprintf("%s %s %.0f점 │ CAGR %.1f%% │ SR %.2f │ MDD %.1f%%",
                icon, r["id"], sc_val %||% 0, cagr_val %||% 0,
                sr_val %||% 0, abs(mdd_val %||% 0))
      })

      score_text <- paste(
        c(sprintf("전략 현황 (%d개 │ ✅%d ❌%d)", nrow(strats), n_pass, n_fail),
          rows),
        collapse = "\n"
      )
    }
  }

  # ── 2. 리서치 진행률 ──
  research_text <- ""
  paper_path <- file.path(PROJECT_ROOT, "06_Registry", "paper_registry.json")
  if (file.exists(paper_path)) {
    papers <- tryCatch(jsonlite::fromJSON(paper_path), error = function(e) NULL)
    if (!is.null(papers) && is.data.frame(papers)) {
      n_total    <- nrow(papers)
      n_analyzed <- sum(papers$status == "analyzed", na.rm = TRUE)
      idea_path  <- file.path(PROJECT_ROOT, "06_Registry", "idea_registry.json")
      n_ideas    <- if (file.exists(idea_path)) {
        nrow(tryCatch(jsonlite::fromJSON(idea_path), error = function(e) data.frame()))
      } else 0L
      research_text <- sprintf(
        "리서치 진행률\n논문: %d/%d 분석 (%.0f%%) │ 아이디어: %d개",
        n_analyzed, n_total, n_analyzed / n_total * 100, n_ideas
      )
    }
  }

  # ── 3. DART 수집 상태 ──
  dart_text <- ""
  dart_log  <- file.path(PROJECT_ROOT, "dart_collect.log")
  if (file.exists(dart_log)) {
    last_lines <- tail(readLines(dart_log, warn = FALSE), 5)
    progress_line <- tail(grep("^  \\[", last_lines, value = TRUE), 1)
    if (length(progress_line) > 0) {
      dart_text <- sprintf("DART 수집\n%s", progress_line)
    }
  }

  full_msg <- paste(
    c(sprintf("[%s 브리핑] %s", slot, today),
      "─────────────",
      score_text, "",
      research_text, "",
      dart_text),
    collapse = "\n"
  )
  tg_send(full_msg)
  Sys.sleep(0.5)

  # ── 4. PASS 전략 베스트 차트 2장 전송 ──
  if (!is.null(strats) && is.data.frame(strats) && nrow(strats) > 0) {
    pass_only <- strats[as.logical(strats$hurdle_pass) %in% TRUE, ]
    if (nrow(pass_only) > 0) {
      best_id <- pass_only$id[which.max(pass_only$hurdle_score)]
      chart_base <- Sys.glob(file.path(PROJECT_ROOT, "04_Research", "strategies",
                                        paste0(best_id, "*"), "output"))
      if (length(chart_base) > 0) {
        equity_f <- file.path(chart_base[1], "equity_curve.png")
        annual_f <- file.path(chart_base[1], "annual_returns.png")
        caption  <- sprintf("Best: %s (Score %.1f)", best_id,
                             max(pass_only$hurdle_score, na.rm = TRUE))
        if (file.exists(equity_f)) { tg_send_photo(equity_f, caption); Sys.sleep(0.3) }
        if (file.exists(annual_f)) { tg_send_photo(annual_f, caption); Sys.sleep(0.3) }
      }
    }
  }

  cat("[tg_briefing] Done.\n")
}

#==============================================================================
# Quantitative Trigger Alerts — Lawbook v1.4.2 Ch.13
# Detects significant changes in portfolio KPIs and sends auto-alerts.
# Compare current vs previous snapshot: trigger if delta exceeds threshold.
#==============================================================================

.TG_TRIGGER_CACHE <- file.path(
  ifelse(exists("CACHE_DIR"), CACHE_DIR,
         "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache"),
  "tg_trigger_snapshot.json"
)

tg_trigger_check <- function(current_metrics, strategy_name = "Portfolio") {
  # current_metrics: list with Sharpe, ES99_d, MDD, Turnover
  # Compares to previous snapshot and fires alerts if thresholds exceeded
  #
  # Thresholds (Lawbook Ch.13):
  #   Sharpe_ann  +0.10  → improvement alert
  #   ES99_d      -0.30%p → risk deterioration
  #   MDD         -2.0%p  → drawdown deepened
  #   Turnover    +100%p/yr → cost surge

  THRESHOLDS <- list(
    Sharpe   = list(delta =  0.10, dir = "up",   label = "Sharpe improved"),
    Sharpe_d = list(delta = -0.10, dir = "down", label = "Sharpe deteriorated"),
    ES99_d   = list(delta =  0.30, dir = "up",   label = "ES99 risk increased"),
    MDD      = list(delta =  2.00, dir = "up",   label = "MDD deepened"),
    Turnover = list(delta = 100.0, dir = "up",   label = "Turnover surged")
  )

  # Load previous snapshot
  prev <- if (file.exists(.TG_TRIGGER_CACHE)) {
    tryCatch(fromJSON(.TG_TRIGGER_CACHE, simplifyDataFrame = FALSE), error = function(e) list())
  } else list()

  alerts <- character(0)

  # Check each metric
  if (!is.null(current_metrics$Sharpe) && !is.null(prev$Sharpe)) {
    d <- current_metrics$Sharpe - prev$Sharpe
    if (d >= 0.10) alerts <- c(alerts,
      sprintf("\U0001f4c8 Sharpe +%.3f (%.3f → %.3f)", d, prev$Sharpe, current_metrics$Sharpe))
    if (d <= -0.10) alerts <- c(alerts,
      sprintf("\u26a0\ufe0f Sharpe %.3f (%.3f → %.3f)", d, prev$Sharpe, current_metrics$Sharpe))
  }

  if (!is.null(current_metrics$ES99_d) && !is.null(prev$ES99_d)) {
    d <- current_metrics$ES99_d - prev$ES99_d  # positive = risk increased
    if (d >= 0.30) alerts <- c(alerts,
      sprintf("\U0001f6a8 ES99 +%.2f%%p (%.2f%% → %.2f%%)", d, prev$ES99_d, current_metrics$ES99_d))
  }

  if (!is.null(current_metrics$MDD) && !is.null(prev$MDD)) {
    d <- current_metrics$MDD - prev$MDD  # positive = deeper drawdown
    if (d >= 2.0) alerts <- c(alerts,
      sprintf("\U0001f4c9 MDD +%.1f%%p (%.1f%% → %.1f%%)", d, prev$MDD, current_metrics$MDD))
  }

  if (!is.null(current_metrics$Turnover) && !is.null(prev$Turnover)) {
    d <- current_metrics$Turnover - prev$Turnover
    if (d >= 100) alerts <- c(alerts,
      sprintf("\U0001f504 Turnover +%.0f%%p (%.0f%% → %.0f%%)", d, prev$Turnover, current_metrics$Turnover))
  }

  # Save current as new snapshot
  snapshot <- list(
    strategy  = strategy_name,
    Sharpe    = current_metrics$Sharpe,
    ES99_d    = current_metrics$ES99_d,
    MDD       = current_metrics$MDD,
    Turnover  = current_metrics$Turnover,
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )
  tryCatch(
    write_json(snapshot, .TG_TRIGGER_CACHE, auto_unbox = TRUE, pretty = TRUE),
    error = function(e) NULL
  )

  # Send alerts
  if (length(alerts) > 0) {
    msg <- sprintf("[KPI Trigger Alert] %s\n─────────────\n%s",
                   strategy_name, paste(alerts, collapse = "\n"))
    tg_send(msg)
    cat(sprintf("[tg_trigger] %d alert(s) sent for %s\n", length(alerts), strategy_name))
  } else {
    cat("[tg_trigger] No triggers fired.\n")
  }

  invisible(list(alerts = alerts, snapshot = snapshot))
}

#==============================================================================
# tg_regime_briefing() — Regime 브리핑 표준 양식 (Session 32 확정)
# Chart 1: Regime Score + Cash (24M 바차트)
# Chart 2: 3-Layer Signal (MSM/KTRI 라인 + FRED 바)
# Chart 3: KTRI 9사분면 (Level x Direction, 일간 궤적)
# + 이모지 포함 텍스트 코멘터리
# 날짜: 최신 데이터 기준 (월말 아님)
#==============================================================================
tg_regime_briefing <- function(regime_dt = NULL, ktri_daily = NULL) {
  suppressPackageStartupMessages({
    library(data.table); library(arrow); library(ggplot2); library(scales); library(gridExtra)
  })

  # ── Load data ──
  if (is.null(regime_dt)) {
    cache_path <- file.path(
      ifelse(exists("CACHE_DIR"), CACHE_DIR,
             file.path(PROJECT_ROOT, ".cache")),
      "unified_regime_signal.parquet")
    if (!file.exists(cache_path)) {
      cat("[regime_briefing] unified_regime_signal.parquet not found. Run build_regime_signal_table() first.\n")
      return(invisible(NULL))
    }
    regime_dt <- as.data.table(arrow::read_parquet(cache_path))
  }
  setorder(regime_dt, Date)

  if (is.null(ktri_daily)) {
    ktri_paths <- c(
      file.path(PROJECT_ROOT, "04_Regime_Engine/output/ktri_v3_signals.csv"),
      file.path(PROJECT_ROOT, "04_Research/regime_comparison/output/ktri_v3_signals.csv")
    )
    kp <- ktri_paths[file.exists(ktri_paths)]
    if (length(kp) > 0) {
      ktri_daily <- fread(kp[1])
      ktri_daily[, Date := as.Date(DATE)]
    }
  }

  out_dir <- file.path(
    ifelse(exists("RESEARCH_OUTPUT"), RESEARCH_OUTPUT,
           file.path(PROJECT_ROOT, "04_Research")),
    "regime_analysis")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  latest <- regime_dt[.N]

  # ── ref_date: 최신 데이터 기준 날짜 (월말 X) ──
  raw_date <- tryCatch({
    rp <- ifelse(exists("RAWDATA_CACHE"), RAWDATA_CACHE,
                 file.path(PROJECT_ROOT, ".cache", "RAWDATA.parquet"))
    if (file.exists(rp)) max(as.data.table(arrow::read_parquet(rp))$Date) else NULL
  }, error = function(e) NULL)

  ktri_date <- if (!is.null(ktri_daily) && nrow(ktri_daily) > 0) max(ktri_daily$Date) else NULL

  # 가장 최신 날짜 사용 (RAWDATA > KTRI > regime 월말)
  ref_date <- max(c(raw_date, ktri_date), na.rm = TRUE)
  if (is.na(ref_date) || length(ref_date) == 0) ref_date <- latest$Date

  # ── Chart 1: Regime Score + Cash (24M) ──
  r24 <- tail(regime_dt, 24)
  r24[, Category_f := factor(Category, levels = c("RISK_ON", "NEUTRAL", "CAUTION", "RISK_OFF"))]
  cat_colors <- c(RISK_ON = "#2196F3", NEUTRAL = "#9E9E9E", CAUTION = "#FF9800", RISK_OFF = "#F44336")

  p1 <- ggplot(r24, aes(x = Date)) +
    geom_col(aes(y = Regime_Score, fill = Category_f), width = 25, alpha = 0.85) +
    geom_line(aes(y = Cash_Pct * 100), color = "red", linewidth = 1.2, linetype = "dashed") +
    geom_point(aes(y = Cash_Pct * 100), color = "red", size = 2) +
    scale_fill_manual(values = cat_colors, name = "Regime") +
    scale_y_continuous(name = "Regime Score",
      sec.axis = sec_axis(~ . / 100, name = "Cash %", labels = percent)) +
    labs(title = "Regime Score & Cash Allocation (24M)",
         subtitle = sprintf("Data: %s | Score %.1f | %s | Cash %.1f%%",
                            ref_date, latest$Regime_Score, latest$Category, latest$Cash_Pct * 100)) +
    theme_minimal(base_size = 13) +
    theme(plot.title = element_text(face = "bold", size = 15),
          legend.position = "bottom",
          axis.title.y.right = element_text(color = "red"))
  ggsave(file.path(out_dir, "regime_score_24m.png"), p1, width = 10, height = 5.5, dpi = 150)

  # ── Chart 2: 3-Layer Decomposition ──
  r24_long <- melt(r24, id.vars = "Date",
                   measure.vars = c("MSM_Crisis_Prob", "KTRI_Score"),
                   variable.name = "Layer", value.name = "Value")
  r24_long[Layer == "MSM_Crisis_Prob", Value := Value * 100]
  r24_long[, Layer := factor(Layer,
    levels = c("MSM_Crisis_Prob", "KTRI_Score"),
    labels = c("MSM Crisis %", "KTRI Score"))]

  p2_top <- ggplot(r24_long, aes(x = Date, y = Value, color = Layer)) +
    geom_line(linewidth = 1.1) + geom_point(size = 1.5) +
    geom_hline(yintercept = 50, linetype = "dotted", color = "gray40") +
    scale_color_manual(values = c("MSM Crisis %" = "#E53935", "KTRI Score" = "#1E88E5")) +
    labs(title = "3-Layer Signal Decomposition",
         subtitle = sprintf("MSM: %.1f%% | KTRI: %.1f | FRED MRS: %.1f  (data: %s)",
                            latest$MSM_Crisis_Prob * 100, latest$KTRI_Score, latest$FRED_MRS, ref_date),
         y = "Score / Prob") +
    theme_minimal(base_size = 13) +
    theme(plot.title = element_text(face = "bold", size = 15), legend.position = "bottom")

  p2_bot <- ggplot(r24, aes(x = Date, y = FRED_MRS)) +
    geom_col(fill = "#FF7043", alpha = 0.7, width = 25) +
    labs(y = "FRED MRS", x = "") + theme_minimal(base_size = 11)

  p2 <- arrangeGrob(p2_top, p2_bot, heights = c(3, 1))
  ggsave(file.path(out_dir, "regime_3layer_24m.png"), p2, width = 10, height = 6.5, dpi = 150)

  # ── Chart 3: KTRI x VEA 9-Quadrant (from KTRI_breadth_9grid.R) ──
  ktri_latest <- NULL
  if (!is.null(ktri_daily) && nrow(ktri_daily) > 0) {
    suppressPackageStartupMessages(library(dplyr))
    x <- as.data.frame(ktri_daily[!is.na(KTRI) & !is.na(VEA)])
    x <- x[order(x$Date), ]

    # forward 20d return for zone labels
    x$fwd20 <- dplyr::lead(x$IKS200, 20) / x$IKS200 - 1

    # 9-grid bins: KTRI <40/40-60/>60, VEA <60/60-70/>70
    x$K_bin <- cut(x$KTRI, breaks = c(-Inf, 40, 60, Inf), labels = c("K_Low","K_Mid","K_High"), right = FALSE)
    x$V_bin <- cut(x$VEA,  breaks = c(-Inf, 60, 70, Inf), labels = c("V_Low","V_Mid","V_High"), right = FALSE)
    x$K_num <- as.numeric(x$KTRI)
    x$V_num <- as.numeric(x$VEA)

    # Zone summary table
    tbl <- x %>% filter(!is.na(K_bin), !is.na(V_bin)) %>%
      group_by(K_bin, V_bin) %>%
      summarise(n = n(), avg_fwd20 = mean(fwd20, na.rm = TRUE), .groups = "drop")
    all_grid <- expand.grid(K_bin = c("K_Low","K_Mid","K_High"),
                            V_bin = c("V_Low","V_Mid","V_High"), stringsAsFactors = FALSE)
    tbl2 <- all_grid %>% left_join(tbl, by = c("K_bin","V_bin")) %>% mutate(
      zone = case_when(
        K_bin == "K_High" & V_bin == "V_Low"  ~ "Strong Add",
        K_bin == "K_High" & V_bin == "V_Mid"  ~ "Add (Scaled)",
        K_bin == "K_High" & V_bin == "V_High" ~ "Trend Up / Vol Risk",
        K_bin == "K_Mid"  & V_bin == "V_Low"  ~ "Neutral+",
        K_bin == "K_Mid"  & V_bin == "V_Mid"  ~ "Neutral",
        K_bin == "K_Mid"  & V_bin == "V_High" ~ "Neutral-Defensive",
        K_bin == "K_Low"  & V_bin == "V_Low"  ~ "Weakness Easing",
        K_bin == "K_Low"  & V_bin == "V_Mid"  ~ "Defensive Bias",
        TRUE ~ "Strong Hedge"))

    # Trailing 252d (zone stats + 과거 회색) + 최근 60d (빨강 경로)
    trail_all <- x %>% filter(!is.na(K_num), !is.na(V_num)) %>% tail(252)
    trail_old <- head(trail_all, max(0, nrow(trail_all) - 60)) %>% mutate(t_idx = row_number())
    trail <- trail_all %>% tail(60) %>% mutate(t_idx = row_number())
    ktri_latest_row <- tail(trail, 1)
    ktri_latest <- list(
      KTRI = ktri_latest_row$K_num, VEA = ktri_latest_row$V_num,
      Date = ktri_latest_row$Date,
      Delta_KTRI = if ("Delta_KTRI" %in% names(ktri_latest_row)) ktri_latest_row$Delta_KTRI else NA,
      Action_v3 = if ("Action_v3" %in% names(ktri_latest_row)) ktri_latest_row$Action_v3
                  else if ("Action" %in% names(ktri_latest_row)) ktri_latest_row$Action else "NA")

    latest_action <- ktri_latest$Action_v3

    # Determine current zone (before chart)
    ktri_latest$zone <- tbl2$zone[tbl2$K_bin == as.character(cut(ktri_latest$KTRI, c(-Inf,40,60,Inf),
                        labels=c("K_Low","K_Mid","K_High"), right=FALSE)) &
                        tbl2$V_bin == as.character(cut(ktri_latest$VEA, c(-Inf,60,70,Inf),
                        labels=c("V_Low","V_Mid","V_High"), right=FALSE))]
    now_zone <- if (length(ktri_latest$zone) > 0) ktri_latest$zone else latest_action

    # Start/End date labels only
    date_labels <- trail[c(1, nrow(trail)), , drop = FALSE] %>%
      mutate(anchor_lbl = format(Date, "%y/%m/%d"))

    # 5d direction
    recent5 <- tail(trail, min(5, nrow(trail)))
    dk5 <- if (nrow(recent5) >= 2) recent5$K_num[nrow(recent5)] - recent5$K_num[1] else 0
    dv5 <- if (nrow(recent5) >= 2) recent5$V_num[nrow(recent5)] - recent5$V_num[1] else 0
    dir5 <- if (dk5 >= 0 & dv5 <= 0) "Risk-On tilt"
            else if (dk5 <= 0 & dv5 >= 0) "Risk-Off tilt" else "Mixed"

    # Zone label positions
    label_df <- tbl2 %>% mutate(
      x = case_when(K_bin == "K_Low" ~ 20, K_bin == "K_Mid" ~ 50, TRUE ~ 80),
      y = case_when(V_bin == "V_Low" ~ 30, V_bin == "V_Mid" ~ 65, TRUE ~ 85),
      lbl = paste0(zone, "\nFwd20: ", sprintf("%.2f%%", 100 * ifelse(is.na(avg_fwd20), 0, avg_fwd20))))

    # ── 9-quadrant chart (60d trail + line) ──
    p3 <- ggplot() +
      # Bottom row (VEA Low: calm)
      annotate("rect", xmin=0,xmax=40,ymin=0,ymax=60,fill="#ECEFF1",alpha=0.7) +
      annotate("rect", xmin=40,xmax=60,ymin=0,ymax=60,fill="#E3F2FD",alpha=0.7) +
      annotate("rect", xmin=60,xmax=100,ymin=0,ymax=60,fill="#E8F5E9",alpha=0.7) +
      # Middle row (VEA Mid: transitional)
      annotate("rect", xmin=0,xmax=40,ymin=60,ymax=70,fill="#FBE9E7",alpha=0.6) +
      annotate("rect", xmin=40,xmax=60,ymin=60,ymax=70,fill="#FAFAFA",alpha=0.6) +
      annotate("rect", xmin=60,xmax=100,ymin=60,ymax=70,fill="#F1F8E9",alpha=0.6) +
      # Top row (VEA High: stress)
      annotate("rect", xmin=0,xmax=40,ymin=70,ymax=100,fill="#FFCDD2",alpha=0.55) +
      annotate("rect", xmin=40,xmax=60,ymin=70,ymax=100,fill="#FFE0B2",alpha=0.5) +
      annotate("rect", xmin=60,xmax=100,ymin=70,ymax=100,fill="#DCEDC8",alpha=0.5) +
      # Grid boundaries
      geom_vline(xintercept = c(40, 60), linetype = "dashed", color = "gray45", linewidth = 0.6) +
      geom_hline(yintercept = c(60, 70), linetype = "dashed", color = "gray45", linewidth = 0.6) +
      # Old 192d scatter (gray gradient)
      geom_point(data = trail_old, aes(K_num, V_num, alpha = t_idx),
                 color = "gray60", size = 1.3) +
      scale_alpha_continuous(range = c(0.15, 0.45), guide = "none") +
      # 60d path line (trajectory)
      geom_path(data = trail, aes(K_num, V_num), color = "#B71C1C", linewidth = 0.7, alpha = 0.4) +
      # 60d scatter with gradient
      geom_point(data = trail, aes(K_num, V_num, color = t_idx), size = 1.8, alpha = 0.8) +
      scale_color_gradient(low = "#FFCCBC", high = "#C62828", guide = "none") +
      # Start dot (yellow, white border)
      geom_point(data = head(trail, 1), aes(K_num, V_num), shape = 21, fill = "#FDD835",
                 color = "#424242", size = 5, stroke = 1.2) +
      # Latest dot (yellow, white border)
      geom_point(data = tail(trail, 1), aes(K_num, V_num), shape = 21, fill = "#FDD835",
                 color = "#424242", size = 5, stroke = 1.2) +
      # Zone labels (text only)
      geom_text(data = label_df, aes(x, y, label = lbl), size = 3.2, fontface = "bold",
                color = "gray30", alpha = 0.7) +
      # Connector lines: dot → label (black)
      geom_segment(data = date_labels,
                   aes(x = K_num, y = V_num, xend = K_num + 2.5, yend = V_num - 2.5),
                   color = "gray30", linewidth = 0.4) +
      # Start/End date labels (white box, black text)
      geom_label(data = date_labels, aes(K_num, V_num, label = anchor_lbl),
                 size = 2.4, fontface = "bold", color = "black",
                 fill = scales::alpha("white", 0.85), linewidth = 0.2,
                 label.padding = unit(0.12, "lines"),
                 nudge_x = 2.5, nudge_y = -2.5, hjust = 0) +
      # TODAY badge (top-left) — zone name
      annotate("label", x = 2, y = 98,
               label = sprintf("NOW: %s\nK = %.1f  |  V = %.1f", now_zone,
                               ktri_latest$KTRI, ktri_latest$VEA),
               hjust = 0, vjust = 1, size = 4, fontface = "bold",
               color = "#B71C1C", fill = scales::alpha("white", 0.9), linewidth = 0.3) +
      coord_cartesian(xlim = c(0, 100), ylim = c(0, 100), clip = "off") +
      labs(title = sprintf("KTRI-VEA 9-Quadrant (252d, data: %s)", ref_date),
           subtitle = sprintf("5D Change: KTRI %+.1f | VEA %+.1f | %s", dk5, dv5, dir5),
           x = expression(bold("KTRI  ") * "(Weakness" %<-% "" %->% "Strength)"),
           y = expression(bold("VEA  ") * "(Calm" %<-% "" %->% "Stress)")) +
      theme_minimal(base_size = 12) +
      theme(plot.title = element_text(face = "bold", size = 14),
            plot.subtitle = element_text(size = 11, face = "bold", color = "gray30"),
            axis.title = element_text(size = 11),
            panel.grid.major = element_line(color = "gray90", linewidth = 0.3),
            panel.grid.minor = element_blank())

    ggsave(file.path(out_dir, "ktri_9quad.png"), p3, width = 9, height = 6.8, dpi = 140)

    ktri_latest$dir5 <- dir5
  }

  cat("[regime_briefing] Charts generated.\n")

  # ── Emoji text commentary ──
  cat_emoji <- switch(latest$Category,
    RISK_ON  = "\xf0\x9f\x9f\xa2",   # green circle
    NEUTRAL  = "\xe2\x9a\xaa",        # white circle
    CAUTION  = "\xf0\x9f\x9f\xa1",    # yellow circle
    RISK_OFF = "\xf0\x9f\x94\xb4",    # red circle
    "\xe2\x9d\x93")

  l1_icon <- if (isTRUE(latest$Layer1_Alert)) "\xf0\x9f\x9a\xa8" else "\xe2\x9c\x85"
  l2_icon <- if (isTRUE(latest$Layer2_Alert)) "\xf0\x9f\x9a\xa8" else "\xe2\x9c\x85"
  l3_icon <- if (isTRUE(latest$Layer3_Alert)) "\xf0\x9f\x9a\xa8" else "\xe2\x9c\x85"

  ktri_arrow <- ""
  if (!is.null(ktri_latest)) {
    ktri_arrow <- if (ktri_latest$Delta_KTRI > 1) "\xe2\xac\x86\xef\xb8\x8f"
                  else if (ktri_latest$Delta_KTRI < -1) "\xe2\xac\x87\xef\xb8\x8f"
                  else "\xe2\x9e\xa1\xef\xb8\x8f"
  }

  prev <- if (nrow(regime_dt) >= 2) regime_dt[.N - 1] else latest
  score_delta <- latest$Regime_Score - prev$Regime_Score
  score_trend <- if (score_delta > 2) sprintf("\xe2\xac\x86\xef\xb8\x8f +%.1f", score_delta)
                 else if (score_delta < -2) sprintf("\xe2\xac\x87\xef\xb8\x8f %.1f", score_delta)
                 else sprintf("\xe2\x9e\xa1\xef\xb8\x8f %+.1f", score_delta)
  cash_trend <- sprintf("%+.1f%%p", (latest$Cash_Pct - prev$Cash_Pct) * 100)

  fw_str <- sprintf(
    "\xf0\x9f\x93\x89 Mom %+.0f%% | \xf0\x9f\x9b\xa1 LowVol %+.0f%%\n\xf0\x9f\x92\x8e Quality %+.0f%% | \xf0\x9f\x92\xb0 Value %+.0f%%",
    latest$fw_Mom * 100, latest$fw_LowVol * 100,
    latest$fw_Quality * 100, latest$fw_Value * 100)

  ktri_str <- ""
  if (!is.null(ktri_latest)) {
    qzone <- if (!is.null(ktri_latest$zone) && length(ktri_latest$zone) > 0) ktri_latest$zone else "N/A"
    dir_label <- if (!is.null(ktri_latest$dir5)) ktri_latest$dir5 else ""
    ktri_str <- sprintf(
      "\n\n\xf0\x9f\x93\x8d [KTRI-VEA 9-Quad]\nKTRI: %.1f %s | VEA: %.1f\nZone: %s | Action: %s\n5D: %s",
      ktri_latest$KTRI, ktri_arrow, ktri_latest$VEA,
      qzone, ktri_latest$Action_v3, dir_label)
  }

  n_alerts <- sum(c(latest$Layer1_Alert, latest$Layer2_Alert, latest$Layer3_Alert), na.rm = TRUE)
  verdict <- if (latest$Category == "RISK_OFF") {
    "\xf0\x9f\x94\xb4 RISK_OFF \xe2\x80\x94 \xec\xb5\x9c\xeb\x8c\x80 \xed\x97\xa4\xec\xa7\x80 \xea\xb6\x8c\xea\xb3\xa0"
  } else if (latest$Category == "CAUTION") {
    sprintf("\xe2\x9a\xa0\xef\xb8\x8f CAUTION \xe2\x80\x94 %d/3 Alert. Score 70 \xe2\x86\x92 RISK_OFF", n_alerts)
  } else if (latest$Category == "NEUTRAL") {
    "\xf0\x9f\x94\x8d NEUTRAL \xe2\x80\x94 \xec\xa3\xbc\xec\x9d\x98 \xea\xb4\x80\xec\xb0\xb0"
  } else {
    "\xf0\x9f\x9f\xa2 RISK_ON \xe2\x80\x94 \xec\xa0\x95\xec\x83\x81 \xec\x9a\xb4\xec\x9a\xa9"
  }

  msg <- sprintf(paste0(
    "%s Regime Briefing (%s)\n\n",
    "\xf0\x9f\x93\x8a [Regime Score]\n",
    "Score: %.1f (%s) | Cash: %.1f%% (%s)\n",
    "Category: %s\n\n",
    "\xf0\x9f\x94\x8d [3-Layer Signal]\n",
    "%s L1 MSM Crisis: %.1f%%\n",
    "%s L2 FRED MRS: %.1f\n",
    "%s L3 KTRI: %.1f | VEA: %.1f",
    "%s\n\n",
    "\xf0\x9f\x93\x88 [Factor Tilt]\n",
    "%s\n\n",
    "\xf0\x9f\x8e\xaf [Verdict]\n%s"),
    cat_emoji, ref_date,
    latest$Regime_Score, score_trend, latest$Cash_Pct * 100, cash_trend,
    latest$Category,
    l1_icon, latest$MSM_Crisis_Prob * 100,
    l2_icon, latest$FRED_MRS,
    l3_icon, latest$KTRI_Score, latest$VEA_Score,
    ktri_str,
    fw_str,
    verdict)

  # ── Send ──
  tg_send(msg)
  Sys.sleep(3)
  tg_send_photo(file.path(out_dir, "regime_score_24m.png"), "Regime Score + Cash (24M)")
  Sys.sleep(3)
  tg_send_photo(file.path(out_dir, "regime_3layer_24m.png"), "3-Layer: MSM / FRED / KTRI")
  Sys.sleep(3)
  ktri_chart <- file.path(out_dir, "ktri_9quad.png")
  if (file.exists(ktri_chart)) {
    tg_send_photo(ktri_chart, "KTRI 9-Quadrant Map")
  }

  cat("[regime_briefing] Sent: text + 3 charts\n")
  invisible(list(regime = latest, ktri = ktri_latest, ref_date = ref_date, charts = out_dir))
}

cat("[telegram_notify] Loaded. Bot: @quant12323413245_bot | Channel: -1003850915447\n")
cat("[telegram_notify] +tg_trigger_check(), +tg_regime_briefing()\n")
