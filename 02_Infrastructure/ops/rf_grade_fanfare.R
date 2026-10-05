#!/usr/bin/env Rscript
#==============================================================================
# rf_grade_fanfare.R — 등급 도달 이펙트 메시지 (도훈 지시 2026-09-04)
#
# "B등급 등장 시 메인 텔레그램 메세지 나오기 전에 이팩트 메세지 하나 띄워주면 좋겠다.
#  화려하게 A등급은 더 화려하게"
#
# ★두 번 울리지 않는다: entry 당 등급당 **최초 1회**만. 마커는 파일로 남긴다.
#   그러지 않으면 B 가 하나 나온 뒤 모든 블록마다 축포가 울려 소음이 된다 —
#   적응형 절이 매 블록 따라붙던 것과 같은 병이다(같은 날 수리).
#
# ★본문이 아니다. 주의를 끄는 깃발이고, 근거·표·차트는 곧 이어 나오는 블록 메시지가 진다.
#   그래서 tg_agent_brief(제목·날짜·섹션 계약)가 아니라 tg_send_rich 를 쓴다.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' @param base_id  강화 entry
#' @param grade    "A" 또는 "B"
#' @param code     셀 코드 (예: B2_6)
#' @param es       essence list (port_t/cagr/mdd/calmar)
#' @param n,maxa   진행 칸수 / 예산
#' @param title    전략(논문) 표시명
#' @param base_grade 기저 등급 — 어디서 올라왔는지
#' @return TRUE(발송) / FALSE(중복이거나 실패)
rf_grade_fanfare <- function(base_id, grade, code, es = list(), n = NA, maxa = NA,
                             title = "", base_grade = "",
                             root = Sys.getenv("QM_ROOT", getwd()), force = FALSE) {
  g <- toupper(as.character(grade %||% "")[1])
  if (!g %in% c("A", "B")) return(invisible(FALSE))

  # ── 최초 1회 가드 ──────────────────────────────────────────────────────────
  mdir <- file.path(root, ".cache", "rf_fanfare")
  dir.create(mdir, recursive = TRUE, showWarnings = FALSE)
  mk <- file.path(mdir, sprintf("%s__%s.flag", gsub("[^A-Za-z0-9_.-]", "_", base_id), g))
  if (!isTRUE(force) && file.exists(mk)) return(invisible(FALSE))

  .f <- function(k, d = 3) { v <- suppressWarnings(as.numeric(es[[k]] %||% NA))
                             if (is.finite(v)) sprintf(paste0("%.", d, "f"), v) else "—" }
  .pc <- function(k) { v <- suppressWarnings(as.numeric(es[[k]] %||% NA))
                       if (is.finite(v)) sprintf("%.1f%%", 100 * v) else "—" }
  # 잘렸으면 잘렸다고 보이게 한다 — 구판은 말없이 잘랐다(2026-09-12).
  ttl <- as.character(title %||% "")
  if (nchar(ttl) > 54L) ttl <- paste0(substr(ttl, 1L, 53L), "…")
  pos <- if (is.finite(suppressWarnings(as.numeric(n)))) sprintf("%s/%s칸", n, maxa) else ""
  from <- if (nzchar(as.character(base_grade %||% ""))) sprintf("기저 %s 에서", base_grade) else ""

  msg <- if (identical(g, "B")) paste0(
    "\U0001F389\U0001F38A  <b>B등급 도달</b>  \U0001F38A\U0001F389\n",
    "━━━━━━━━━━━━━━━\n",
    "<b>", ttl, "</b>\n",
    "<code>", code, "</code>  ",
    "다중검정 t <b>", .f("port_t"), "</b> · 칼마 <b>", .f("calmar"), "</b>\n",
    "연복리 ", .pc("cagr"), " · 최대낙폭 ", .pc("mdd"), "\n",
    "━━━━━━━━━━━━━━━\n",
    "\U0001F517 2계층 로테이션 풀 자격 · ", pos, " ", from, "\n",
    "\U0001F4C4 상세는 이어지는 블록 보고에."
  ) else paste0(
    "\U0001F3C6\U00002728\U0001F3C6\U00002728\U0001F3C6\U00002728\U0001F3C6\n",
    "\U00002728   <b>G R A D E   A</b>   \U00002728\n",
    "\U0001F3C6\U00002728\U0001F3C6\U00002728\U0001F3C6\U00002728\U0001F3C6\n",
    "━━━━━━━━━━━━━━━━━━\n",
    "<b>", ttl, "</b>\n",
    "<code>", code, "</code>\n",
    "  다중검정 t  <b>", .f("port_t"), "</b>   (합격선 2.95)\n",
    "  칼마        <b>", .f("calmar"), "</b>   (합격선 0.64)\n",
    "  연복리      <b>", .pc("cagr"), "</b>   (합격선 16%)\n",
    "  최대낙폭    ", .pc("mdd"), "\n",
    "━━━━━━━━━━━━━━━━━━\n",
    "\U0001F6A9 <b>Judge(PIT) 검증 대기</b> — 통과해야 BOOK 후보다.\n",
    "\U0001F512 등재는 도훈 confirm 없이 안 된다.\n",
    "\U0001F504 루프는 멈추지 않는다 — 남은 칸과 다음 논문은 계속 간다.\n",
    "\U0001F4C4 근거·차트는 이어지는 보고에.  ", pos, " ", from
  )

  ok <- tryCatch({
    suppressMessages(source(file.path(root, "02_Infrastructure/telegram/telegram_notify.R")))
    r <- tg_send_rich(msg, emoji_min = 1L)
    isTRUE(r$ok %||% TRUE)
  }, error = function(e) FALSE)

  if (isTRUE(ok)) writeLines(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), mk)
  invisible(ok)
}

#' 이번 블록이 **처음으로** 그 등급을 냈는가 — 원장에서 재도출한다(선언 아님)
#' @return "A" / "B" / NA  (둘 다면 A 우선)
#' ★P1-06(2026-09-25): 통제 칸(carry 재현 · null 희석 — 격자 standing_cells[control])은 등급을 '냈다'고 세지 않는다 —
#'   승격 entry 의 B1_0 은 부모 구성을 다시 잰 것이라 B 가 당연하다(축포가 매 승격마다 울린다). control_codes 로 뺀다
#'   (기본 = 격자에서 읽는다 · 읽지 못하면 빼지 않는다 = 구판 거동).
rf_fanfare_new_grade <- function(entry, block_codes,
                                 control_codes = tryCatch({
                                   .r <- Sys.getenv("QM_ROOT", getwd())
                                   if (!exists("rfbd_control_codes", mode = "function"))
                                     suppressMessages(source(file.path(.r, "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE))
                                   rfbd_control_codes(.r) }, error = function(e) character(0))) {
  ats <- Filter(function(a) !(as.character(a$cell_code %||% "") %in% control_codes), entry$attempts %||% list())
  if (!length(ats)) return(NA_character_)
  .g <- function(a) toupper(substr(as.character(a$grade %||% ""), 1, 1))
  .c <- function(a) as.character(a$cell_code %||% "")
  inblk <- vapply(ats, function(a) .c(a) %in% block_codes, logical(1))
  for (g in c("A", "B")) {
    got_now  <- any(vapply(ats[inblk],  function(a) identical(.g(a), g), logical(1)))
    got_past <- any(vapply(ats[!inblk], function(a) identical(.g(a), g), logical(1)))
    if (got_now && !got_past) return(g)
  }
  NA_character_
}
