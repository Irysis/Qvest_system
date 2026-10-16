#==============================================================================
# program_report.R — v10.01 1계층 리서치 보고 발송기 (2026-10-13 · 발송 규칙 v10.01)
#
# 왜: 텔레그램 감사(10-13)의 최악 10건 — 헤드라인이 이번 결과를 말하지 않음 · 실패 원인 소실 · 포인터 절삭 ·
#   숫자 중간 절삭 · 지표명/단위 혼재 · 등급 체계 3개 노출 · 내부 코드 유출 · 상태 섹션이 맨 아래 · 블록당 푸시 4~5건.
#   이 발송기는 그 반대로 짠다(규칙 정본 = .claude/skills/qvest-telegram/SKILL.md §v10.01).
# 규칙(요약):
#   ① 리서치 1단위 = 메시지 1통. 첫 줄 = 이번 결과의 판정어(강함/보통/약함/판정 불가 · 등급).
#   ② 지표 이름은 하나: 하락 포착률(위기) · 상승 포착률(강세) · 위기 방어 판정 · CAGR · 최대낙폭 · Calmar · CDaR · PORT_t.
#      낙폭은 음수 %(−41.2%), 수익률은 부호 있는 %, 비율은 소수 둘째 자리.
#   ③ 숫자를 자르지 않는다 — 넘칠 것 같으면 행 단위로 덜어내고 "외 N건"과 산출물 경로를 남긴다.
#   ④ 내부 코드(셀 코드 · entry id · 함수명 · 절대경로)를 본문에 쓰지 않는다. 경로는 마지막 '산출물:' 한 줄만.
#   ⑤ 평상 보고는 무음(mute). 판정 변화 · 실패 · 프로그램 종료만 푸시.
# 공개: prep_fmt_pct · prep_fmt_ratio · prep_verdict_word · prep_card_digest · prep_send
# 검사: 08_Tests/programs/test_program_report.R (dry-run)
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

.prep_or <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

prep_fmt_pct <- function(x, digits = 1L, signed = TRUE) {
  if (is.null(x) || !is.finite(x)) return("—")
  s <- formatC(100 * x, format = "f", digits = digits)
  if (signed && x > 0) s <- paste0("+", s)
  sub("^-", "−", paste0(s, "%"))
}
prep_fmt_ratio <- function(x, digits = 2L) {
  if (is.null(x) || !is.finite(x)) return("—")
  sub("^-", "−", formatC(x, format = "f", digits = digits))
}

PREP_VERDICT_WORD <- c(strong = "강함", normal = "보통", weak = "약함", insufficient = "판정 불가")
prep_verdict_word <- function(v) .prep_or(unname(PREP_VERDICT_WORD[v]), "판정 불가")

## 크기 · 노출 짝 대조 귀속(MC8 · contracts/matched_controls.R::mc_attribution) — 라벨 · 상태를 사람 말로(내부 코드 비노출)
PREP_DEFENSE_WORD <- c(selection_defense = "선택 방어", size_defense = "크기 방어",
                       exposure_defense = "노출 방어", no_defense = "방어 없음", insufficient = "판정 불가(위기 2번 미만)")
PREP_CONTROL_STATUS_WORD <- c(not_applicable_long_short = "롱숏 전략이라 대조 정의 밖", no_crises = "위기 구간 없음",
                              no_holdings = "보유 기록 없음", no_windows = "보유창에 수익일 없음",
                              no_basket = "크기 바스켓을 못 만듦")

# 위기 줄에 붙일 크기+노출 짝 대조의 하락 포착률(없으면 빈 문자열)
.prep_ctrl_capture <- function(ctrl, peaks) {
  out <- rep("", length(peaks))
  pc <- if (is.list(ctrl) && is.list(ctrl[["size_exposure_matched"]])) ctrl[["size_exposure_matched"]][["per_crisis"]] else NULL
  if (is.null(pc) || !NROW(pc)) return(out)
  pc <- as.data.table(pc)
  j <- match(as.Date(peaks), as.Date(pc$peak_date))
  ok <- !is.na(j)
  if (any(ok)) out[ok] <- paste0(" · 크기·노출 짝 ", vapply(pc$control_dd_capture[j[ok]], prep_fmt_ratio, character(1)))
  out
}

# 대조 한 줄 — 귀속 라벨(attribution)이 정본, 구 단일 대조(size_matched) 라벨은 하위 호환
.prep_controls_line <- function(ctrl, window) {
  if (is.null(ctrl) || identical(ctrl[["status"]], "not_provided"))
    return("크기·노출 짝 대조 없음 — 방어가 실력인지 크기·노출 효과인지 아직 모른다")
  att <- ctrl[["attribution"]]
  aw <- if (is.list(att)) att[[window]] else NULL
  if (is.list(aw) && !is.null(aw[["label"]])) {
    a <- suppressWarnings(as.numeric(.prep_or(att[["placebo_alpha"]], NA_real_)))
    top <- if (is.finite(a)) prep_fmt_pct(1 - a, 0L, signed = FALSE) else "대부분"
    return(sprintf("크기·노출 짝 대조: %s — 같은 크기 분포·평균 노출로 무작위로 고른 포트폴리오의 %s보다 덜 빠진 위기 %s · 같은 평균 노출의 시장보다 덜 빠진 위기 %s · 시장보다 덜 빠진 위기 %s (평균 노출 %s)",
                   .prep_or(unname(PREP_DEFENSE_WORD[aw[["label"]]]), "판정 불가"), top,
                   prep_fmt_pct(aw[["share_beats_size_exposure"]], 0L, signed = FALSE),
                   prep_fmt_pct(aw[["share_beats_exposure"]], 0L, signed = FALSE),
                   prep_fmt_pct(aw[["share_beats_bench"]], 0L, signed = FALSE),
                   prep_fmt_ratio(ctrl[["exposure_profile"]][["mean"]])))
  }
  sm <- ctrl[["size_matched"]]
  if (is.list(sm) && !is.null(sm[["label"]]))
    return(sprintf("크기 짝 대조: %s(위기 %s에서 대조보다 덜 빠짐)",
                   if (identical(sm[["label"]], "selection_defense")) "선택 방어" else "크기·노출 방어",
                   prep_fmt_pct(sm[["share_beats"]], 0L, signed = FALSE)))
  paste0("크기·노출 짝 대조 판정 불가 — ", .prep_or(unname(PREP_CONTROL_STATUS_WORD[.prep_or(ctrl[["status"]], "")]), "대조 생성 실패"))
}

# 경로에서 프로젝트 루트를 떼고 슬래시로 통일 — 절대경로 유출 방지(감사 10-13: 윈도 경로 혼합으로 제거 실패)
.prep_rel <- function(p, root = Sys.getenv("QM_ROOT", "")) {
  if (is.null(p) || !nzchar(p)) return("")
  p <- gsub("\\\\", "/", p); r <- gsub("\\\\", "/", root)
  if (nzchar(r)) p <- sub(paste0("^", gsub("([.|()^${}+*?\\[\\]])", "\\\\\\1", r), "/?"), "", p)
  p
}

#' 행동 카드 → 보고 재료(판정 문장 · 위기 표 · 핵심 수치)
prep_card_digest <- function(card, window = c("overall", "visible", "test"), max_rows = 8L) {
  window <- match.arg(window)
  V <- card[[window]]
  cr <- card$crises
  head <- sprintf("위기 %d번 · 하락 포착률 중앙 %s(최악 %s) · 강세 상승 포착률 중앙 %s → 위기 방어 %s",
                  .prep_or(V$n_crisis, 0L), prep_fmt_ratio(V$crisis_dd_capture_median),
                  prep_fmt_ratio(V$crisis_dd_capture_worst), prep_fmt_ratio(V$bull_up_capture_median),
                  prep_verdict_word(V$verdict))
  ## 위기 1개 = 1줄(글머리표). 공용 표 렌더러는 모바일 가독성 때문에 2열 상한이라 5열 표를 못 쓴다.
  lines <- character(0); omitted <- 0L
  if (!is.null(cr) && nrow(cr)) {
    cr <- as.data.table(cr)
    w_sel <- window
    if (w_sel != "overall") cr <- cr[cr$window == w_sel]
    lab_w <- c(visible = "보는 창", test = "시험 창", straddle = "걸침")
    if (nrow(cr)) lines <- sprintf("%s~%s(%s) 시장 %s → 전략 %s · 포착 %s%s%s",
      format(as.Date(cr$peak_date), "%y.%m"), format(as.Date(cr$trough_date), "%y.%m"), unname(lab_w[cr$window]),
      vapply(-cr$bm_dd, prep_fmt_pct, character(1), digits = 0L),
      vapply(-cr$st_dd, prep_fmt_pct, character(1), digits = 0L),
      vapply(cr$dd_capture, prep_fmt_ratio, character(1)),
      .prep_ctrl_capture(card$controls, cr$peak_date),
      ifelse(cr$ongoing, " · 진행 중", ""))
    if (length(lines) > max_rows) { omitted <- length(lines) - max_rows; lines <- utils::tail(lines, max_rows) }
  }
  S <- card$stats
  kv <- list(
    "CAGR" = prep_fmt_pct(S$cagr),
    "최대낙폭" = prep_fmt_pct(-S$mdd),
    "Calmar" = prep_fmt_ratio(S$calmar),
    "CDaR(상위 5% 낙폭 평균)" = prep_fmt_pct(-S$cdar),
    "베타 하락장 / 상승장" = sprintf("%s / %s", prep_fmt_ratio(S$beta_down), prep_fmt_ratio(S$beta_up)),
    "롤링 3년 통과율" = if (is.finite(.prep_or(card$rolling$pass_life, NA_real_))) prep_fmt_pct(card$rolling$pass_life, 0L, signed = FALSE) else "—")
  ctrl_line <- .prep_controls_line(card$controls, window)
  list(headline = head, lines = lines, omitted = omitted, kv = kv, controls = ctrl_line,
       verdict = .prep_or(V$verdict, "insufficient"))
}

#' 한 줄(판정 · 다음)을 길이에 맞는 섹션으로 — 1줄 헤드라인(summary)은 20~100자만 받는다(tg_format_summary).
#'   범위를 벗어나면 발송 전체가 stop 으로 죽는다(10-13 dry-run 실측: '다음: 큐 다음 논문으로 넘어간다' 18자 → 1통 소실).
#'   100자 초과 = 문단(text · 문장·숫자 안 자름) · 20자 미만 = 프로그램·대상 맥락을 붙여 1줄 · 그래도 짧으면 공백 채움(내용 손실 0).
.prep_line <- function(label, body, emoji, program, target) {
  body <- as.character(body)[1]
  line <- paste0(label, ": ", body)
  if (nchar(line) > 100L) return(list(heading = label, type = "text", body = body))
  if (nchar(line) < 20L) line <- paste0(label, "(", program, "): ", body)
  if (nchar(line) < 20L) line <- paste0(label, "(", program, " · ", target, "): ", body)
  if (nchar(line) < 20L) line <- formatC(line, width = -20L)
  list(heading = "", type = "summary", emoji = emoji, body = line)
}

#' 보고 1통 발송 — 리서치 1단위 = 메시지 1통
#' @param program 프로그램 이름(예: "방어 엔진") · @param target 대상(사람이 읽는 이름)
#' @param status list(stage=, position=, previous=) — 현재 리서치 상황 4필드 중 3개(대상은 target)
#' @param verdict_line 판정 1~2줄(평문) — 없으면 카드 헤드라인
#' @param push TRUE = 푸시(판정 변화 · 실패 · 종료), FALSE = 무음
#' @param extra 추가 섹션 목록(선택)
## 위기별 낙폭 차트(2026-10-16 도훈 "위기별 낙폭 (시장 대비)은 시각화 자료로 대체") — 행동 카드 위기마다 시장(KOSPI200) 낙폭 vs 전략 낙폭 막대 ·
##   하락 포착률 라벨 · 사건명(06_Registry/crisis_event_names.json — 도훈 10-17 '보는창/시험창을 해당 시점 하락 이벤트 명칭으로') · 보는 창 / 시험 창은
##   행마다 적지 않고 경계선 1줄 · 진행 중 표시. 수치 = 행동 카드(계약 산출 · AX-008) 그대로 — 손계산 없음. 글꼴 = 현대하모니 M(§0.7).
##   반환 = 그린 파일 경로(그릴 위기가 없으면 NULL).
## 사건명 — 위기 고점 월에 가장 가까운 등록 항목(허용 ±tolerance_months) · 없으면 "" (이름을 지어내지 않는다 · 등록부 부재 = 전부 "")
.prep_event_names <- function(peak_dates, root = NULL) {
  rt <- .prep_or(root, Sys.getenv("QM_ROOT", getwd()))
  reg <- tryCatch(jsonlite::fromJSON(file.path(rt, "06_Registry/crisis_event_names.json"), simplifyVector = FALSE), error = function(e) NULL)
  out <- rep("", length(peak_dates))
  if (is.null(reg) || !length(reg$events)) return(out)
  tol <- as.integer(.prep_or(reg$match$tolerance_months, 2L))
  mon <- function(d) { d <- as.Date(d); as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m")) }
  ev_m <- vapply(reg$events, function(e) mon(paste0(e$peak, "-01")), integer(1))
  ev_n <- vapply(reg$events, function(e) as.character(e$name), character(1))
  for (i in seq_along(peak_dates)) {
    gap <- abs(ev_m - mon(peak_dates[i]))
    if (length(gap) && is.finite(min(gap)) && min(gap) <= tol) out[i] <- ev_n[which.min(gap)]
  }
  out
}
prep_crisis_chart <- function(card, path, window = "overall", root = NULL) {
  cr <- card$crises
  if (is.null(cr) || !NROW(cr)) return(NULL)
  cr <- data.table::as.data.table(cr)
  w_sel <- window
  if (!identical(w_sel, "overall")) cr <- cr[cr$window == w_sel]      # data.table 안에서 window 는 열 이름 — 인자는 w_sel 로
  if (!nrow(cr)) return(NULL)
  for (p in c("ggplot2", "ragg", "systemfonts")) if (!requireNamespace(p, quietly = TRUE)) stop("[prep_crisis_chart] 패키지 없음: ", p)
  fam <- ""
  fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
  fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
  if (!is.na(fM)) { try(systemfonts::register_font(name = "HDHM", plain = fM), silent = TRUE); fam <- "HDHM" }
  cr <- cr[order(as.Date(peak_date))]
  nm <- .prep_event_names(cr$peak_date, root)
  ## 첫 줄 = 날짜(+ 진행 중) · 둘째 줄 = 사건명 — 진행 중 표식을 날짜 줄에 둬 이름 줄이 길어지지 않게(왼쪽 축 폭 = 막대 폭을 먹는다)
  cr[, key := paste0(format(as.Date(peak_date), "%y.%m"), "~", format(as.Date(trough_date), "%y.%m"),
                     ifelse(.prep_true_vec(ongoing), " · 진행 중", ""), ifelse(nzchar(nm), paste0("\n", nm), ""))]
  ## 세로 배치(10-17) — 위기 = 행(위 = 오래된 위기) · 가로 막대. 위기 15개를 가로로 늘어놓으면 3262×870 이 돼 휴대폰 텔레그램에서 글자가 안 보였다.
  ##   폭 고정(7.2in · 150dpi ≈ 1080px) · 높이 = 위기 수에 비례. 포착률은 0 오른쪽 여백에 행마다 1개.
  cr[, key := factor(key, levels = rev(unique(key)))]
  ## 보는 창 / 시험 창 경계 — 시간순 첫 '보는 창 아닌' 위기 위에 선 1줄(전체 창이고 둘 다 있을 때만)
  k_first <- if (identical(w_sel, "overall")) which(as.character(cr$window) != "visible")[1] else NA_integer_
  div_x <- if (is.finite(k_first) && k_first > 1L) nrow(cr) - k_first + 1.5 else NA_real_
  L <- data.table::rbindlist(list(cr[, .(key, who = "시장(KOSPI200)", v = -abs(as.numeric(bm_dd)))], cr[, .(key, who = "전략", v = -abs(as.numeric(st_dd)))]))
  L[, who := factor(who, levels = c("전략", "시장(KOSPI200)"))]                      # 뒤집힌 축에서 행 안 위 = 시장 · 아래 = 전략
  m <- max(abs(L$v), na.rm = TRUE); if (!is.finite(m) || m <= 0) m <- 0.1
  capl <- cr[, .(key, lab = paste0("포착 ", vapply(as.numeric(dd_capture), prep_fmt_ratio, character(1))))]
  pct <- function(x) vapply(x, function(z) prep_fmt_pct(z, 0L), character(1))
  g <- ggplot2::ggplot(L, ggplot2::aes(key, v, fill = who)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(0.8), width = 0.76) +
    ggplot2::geom_text(ggplot2::aes(y = v - 0.015 * m, label = pct(v)), position = ggplot2::position_dodge(0.8), hjust = 1, size = 3.3, family = fam) +
    ggplot2::geom_text(data = capl, ggplot2::aes(key, 0.04 * m, label = lab), inherit.aes = FALSE, hjust = 0, size = 3.5, family = fam, colour = "#333333") +
    ggplot2::geom_hline(yintercept = 0, colour = "#444444", linewidth = 0.4) +
    (if (is.finite(div_x)) ggplot2::geom_vline(xintercept = div_x, linetype = "dashed", colour = "#888888", linewidth = 0.45) else NULL) +
    ggplot2::coord_flip(clip = "off") +
    ggplot2::scale_fill_manual(values = c("시장(KOSPI200)" = "#9e9e9e", "전략" = "#1f77b4"), breaks = c("시장(KOSPI200)", "전략")) +
    ggplot2::scale_y_continuous(breaks = function(l) { b <- pretty(l); b[b <= 0] }, labels = function(x) pct(x),
                                limits = c(-1.3 * m, 0.45 * m), expand = ggplot2::expansion(mult = 0)) +   # 0 오른쪽 = 포착 라벨 자리(눈금 없음)
    ggplot2::labs(title = "위기별 낙폭 — 시장(KOSPI200) vs 전략",
                  subtitle = paste0("막대 = 위기 구간 고점→저점 낙폭\n포착 = 전략 낙폭 ÷ 시장 낙폭(낮을수록 방어)",
                                    if (is.finite(div_x)) sprintf("\n점선 위 = 보는 창 · 아래 = 시험 창(정보 경계 %s 이후)", .prep_or(card$cfg$tau_d, "τ_D")) else ""),
                  caption = "위기 = KOSPI200 Lunde-Timmermann 20/20 · 수치 = 행동 카드(계약 산출) · 사건명 = 06_Registry/crisis_event_names.json", x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_family = fam, base_size = 12.5) +
    ggplot2::theme(legend.position = "top", legend.justification = "left", legend.title = ggplot2::element_blank(),
                   panel.grid.minor = ggplot2::element_blank(), panel.grid.major.y = ggplot2::element_blank(),
                   axis.text.y = ggplot2::element_text(size = 11, colour = "#222222"),
                   plot.title = ggplot2::element_text(size = 16), plot.subtitle = ggplot2::element_text(size = 10.5, colour = "#555555"),
                   plot.caption = ggplot2::element_text(size = 8.5, colour = "#777777"), plot.title.position = "plot")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(path, g, width = 7.2, height = 2.2 + 0.5 * nrow(cr), dpi = 150, device = ragg::agg_png)
  path
}
.prep_or_vec <- function(x, d) { x <- as.character(x); x[is.na(x) | !nzchar(x)] <- d; x }
.prep_true_vec <- function(x) !is.na(x) & as.logical(x) %in% TRUE
## 핵심 수치의 CAGR · 최대낙폭 · Calmar = 산출물 권위 기록(authoritative_remeasure.json::essence — 등급이 쓴 값)이 있으면 그 값.
##   카드 값은 월간 수익으로 잰 것이라 같은 전략이 등급과 다른 Calmar 로 보였다(10-17 1801.01777: 카드 0.93 · 등급 0.918). 없으면 카드 값.
.prep_auth_kv <- function(kv, artifact) {
  if (is.null(artifact) || !nzchar(artifact)) return(kv)
  d <- if (dir.exists(artifact)) artifact else dirname(artifact)
  es <- tryCatch(jsonlite::fromJSON(file.path(d, "authoritative_remeasure.json"))$essence, error = function(e) NULL)
  num <- function(x) { v <- suppressWarnings(as.numeric(x)); if (length(v) == 1L && is.finite(v)) v else NA_real_ }
  if (is.finite(num(es$cagr)))   kv[["CAGR"]] <- prep_fmt_pct(num(es$cagr))
  if (is.finite(num(es$mdd)))    kv[["최대낙폭"]] <- prep_fmt_pct(-abs(num(es$mdd)))
  if (is.finite(num(es$calmar))) kv[["Calmar"]] <- prep_fmt_ratio(num(es$calmar))
  kv
}
## 차트 저장 위치 — 그 리서치 단위의 산출물 폴더(§0.5) · 산출물이 파일이면 그 폴더 · 없으면 임시 파일
.prep_chart_path <- function(artifact, name = "crisis_drawdown.png") {
  if (is.null(artifact) || !nzchar(artifact)) return(tempfile("crisis_drawdown_", fileext = ".png"))
  d <- if (dir.exists(artifact)) artifact else dirname(artifact)
  file.path(d, name)
}

prep_send <- function(program, target, status, card = NULL, verdict_line = NULL, next_step = NULL,
                      artifact = NULL, charts = NULL, push = FALSE, window = "overall", extra = NULL,
                      dry_run = identical(Sys.getenv("QVEST_TG_DRY_RUN", ""), "1"), root = NULL, crisis = c("lines", "chart")) {
  ## crisis = "chart"(충실구현 보고 · 도훈 10-16) — 위기별 낙폭 글줄 대신 위기 차트를 붙이고 대조 1줄만 남긴다 · 차트 실패면 글줄로 돌아간다(1통 보존)
  crisis <- match.arg(crisis)
  if (!exists("tg_agent_brief", mode = "function")) {
    rt <- .prep_or(root, Sys.getenv("QM_ROOT", getwd()))
    suppressMessages(source(file.path(rt, "02_Infrastructure/telegram/telegram_notify.R")))
  }
  D <- if (!is.null(card)) prep_card_digest(card, window) else NULL
  if (!is.null(D)) D$kv <- .prep_auth_kv(D$kv, artifact)
  vword <- if (!is.null(D)) prep_verdict_word(D$verdict) else ""
  title <- sprintf("[1계층·%s] %s%s", program, target, if (nzchar(vword)) paste0(" — 위기 방어 ", vword) else "")
  secs <- list(list(heading = "현재 리서치 상황", type = "text",
                    body = sprintf("단계: %s\n대상: %s\n위치: %s\n직전 판정: %s",
                                   .prep_or(status$stage, "—"), target, .prep_or(status$position, "—"),
                                   .prep_or(status$previous, "—"))),
               .prep_line("판정", .prep_or(verdict_line, if (!is.null(D)) D$headline else "—"), "🎯", program, target))
  cp <- if (!is.null(D) && length(D$lines) && identical(crisis, "chart"))
    tryCatch(prep_crisis_chart(card, .prep_chart_path(artifact), window, root = root), error = function(e) { message("[prep_send] 위기 차트 실패 — 글줄로: ", conditionMessage(e)); NULL })
  else NULL
  if (!is.null(cp) && file.exists(cp)) {
    charts <- c(stats::setNames(cp, "위기별 낙폭 — 시장(KOSPI200) vs 전략"), charts)
    ctl <- D$controls[nzchar(.prep_or(D$controls, ""))]
    if (length(ctl)) secs[[length(secs) + 1L]] <- if (length(ctl) >= 2L) list(heading = "위기 방어 귀속", type = "bullet", items = ctl) else
      list(heading = "위기 방어 귀속", type = "text", body = ctl[1])                    # 글머리표는 2줄 이상만 받는다(tg_agent_brief)
  } else if (!is.null(D) && length(D$lines))
    secs[[length(secs) + 1L]] <- list(heading = "위기별 낙폭 (시장 대비)", type = "bullet",
                                      items = c(D$lines,
                                                if (D$omitted > 0L) sprintf("앞선 위기 %d건은 산출물에 있다", D$omitted),
                                                D$controls))
  if (!is.null(D))
    secs[[length(secs) + 1L]] <- list(heading = "핵심 수치", type = "kv", kv = D$kv)
  ## extra = 추가 섹션 목록(tg_agent_brief 섹션 형식) — 감사 지적 요약처럼 단위마다 다른 재료. 위기 표 · 핵심 수치 뒤, 다음 앞
  if (length(extra)) secs <- c(secs, extra)
  if (!is.null(next_step) && nzchar(next_step))
    secs[[length(secs) + 1L]] <- .prep_line("다음", next_step, "➡️", program, target)
  footer <- if (!is.null(artifact) && nzchar(artifact)) paste0("산출물: ", .prep_rel(artifact)) else NULL
  tg_agent_brief(agent = "AlphaSearch", title = title, sections = secs, footer = footer, charts = charts,
                 relaxed = TRUE, force = TRUE, decode_jargon = FALSE, glossary = FALSE,
                 mute = !isTRUE(push), dry_run = dry_run,
                 ## 잠금 · 본문 보관 파일 이름 — 대상 앞 40자 + 해시(긴 논문명이 Windows 260자 경로를 넘어 중복 차단 · 보관이 조용히 빠지던 위험 · 10-16)
                 lock_scope = sprintf("prep_%s_%s_%s_%s", gsub("[^A-Za-z0-9가-힣]", "_", program),
                                      substr(gsub("[^A-Za-z0-9가-힣]", "_", target), 1L, 40L), substr(as.character(openssl::md5(enc2utf8(target))), 1L, 8L),
                                      format(Sys.time(), "%Y%m%d%H%M%S")))
}
