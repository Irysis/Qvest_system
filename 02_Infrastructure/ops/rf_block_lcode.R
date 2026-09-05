#==============================================================================
# rf_block_lcode.R — 블록 완료 시 L-code **무인 발행** (2026-08-30)
#
# 왜 생겼나: 강화 SKILL §0 은 "보고 단위 = 블록(등급 5건 일괄 텔레그램 + L-code 1건)"
#   이라 적어 뒀는데, 러너 2종 어디에도 emit_lcode 호출이 없었다(grep 0건). 텔레그램만
#   나가고 L-code 는 세션이 손으로 채워야 했다 — 무인 루프에 사람 대기 지점이 하나 남아
#   있었던 것이고, 세션이 안 오면 그 블록의 학습은 원장 밖에서 증발한다.
#
# ★지어내지 않는다: 교훈 문장과 next_probe 는 **실측 표에서 기계적으로 도출되는 것만**
#   쓴다. 요약·인사이트 생산자는 텔레그램과 동일(rf_notify_table / rf_insights) — 두 곳이
#   다른 것을 말하면 그 자체가 결함이다.
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' 다음 블록 해석 — ★entry 의 **적응 순서**가 정본이다 (2026-09-05)
#'
#' 왜 생겼나: 구판은 `prog$blocks` 의 **선언 순서**에서 k+1 을 집었다. 그런데 러너는
#'   선언 순서로 돌지 않는다 — `rf_block_order_decide()` 가 entry 마다 순서를 정하고
#'   (수익 축 충족 · 위험 축 미달이면 B5 를 2번째로 당긴다), 그 순서로 배치를 재배열한다.
#'   실측(RP_20260904_163647_18444_rescued_rulefast_promo2 · B1 · L-RF-20260904_223318):
#'   L-code 는 "다음 격자 축 B2(weighting)" 라 적었는데 재도출한 적응 순서는
#'   B1>B5>B2>B3>B4 였다. 부팅 `Last:` 줄이 next_probe[0] 을 그대로 echo 하므로
#'   **세션이 보는 계기가 틀린 축을 가리켰다**.
#'
#' 순서 정본은 셋이고 우선순위가 있다:
#'   ① entry$block_order — 러너가 사전등록한 것. 덮어쓰기 금지(rf_record_block_order)라
#'      이게 있으면 이게 사실이다.
#'   ② rf_block_order_decide(entry, prog) — 아직 등록 전. 러너는 `used >= 5` 인 **다음 배치
#'      직전**에 등록하는데 L-code 는 그 앞(블록 경계)에서 나간다 — 실측 사례가 정확히 이 창이다.
#'      규칙이 결정론이라 재도출이 가능하다. 다만 등록 전이므로 잠정으로 표시한다.
#'   ③ prog$blocks 선언 순서 — 위 둘이 다 없을 때만.
#'
#' @return list(id = 다음 블록(없으면 NULL), order = 쓴 순서, src = ledger/decide/program)
rf_next_block <- function(entry, bid, prog,
                          root = Sys.getenv("QM_ROOT",
                            "C:/Users/99922/OneDrive/Quant_Module_Moltbot")) {
  ids <- if (is.null(prog)) character(0) else
         vapply(prog$blocks, function(b) as.character(b$id %||% ""), character(1))
  ids <- ids[nzchar(ids)]

  ord <- as.character(unlist(entry$block_order %||% character(0)))
  ord <- ord[nzchar(ord)]
  src <- "ledger"

  if (!length(ord) && !is.null(prog) && !is.null(entry)) {
    ord <- tryCatch({
      suppressMessages(source(file.path(root, "02_Infrastructure/reinforcement/rf_lesson.R"),
                              local = TRUE))
      as.character(rf_block_order_decide(entry, prog, root = root)$order)
    }, error = function(e) character(0))
    ord <- ord[nzchar(ord)]
    src <- "decide"
  }
  # ★순서가 이 블록을 담고 있지 않으면 그 순서로는 다음을 못 읽는다 — 선언 순서로 떨어진다.
  if (!length(ord) || is.na(match(bid, ord))) { ord <- ids; src <- "program" }

  k <- match(bid, ord)
  list(id = if (!is.na(k) && k < length(ord)) ord[k + 1L] else NULL,
       order = ord, src = src)
}

#' @param base_id 원장 entry
#' @param n_used  블록 경계에서의 attempts_used (이번 블록 = n_used-4 .. n_used)
#' @return l_code (문자) 또는 NULL
rf_emit_block_lcode <- function(base_id, n_used, root = Sys.getenv("QM_ROOT",
                                  "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                                dry_run = FALSE) {
  suppressMessages(source(file.path(root, "02_Infrastructure/ops/rf_auto_notify.R")))
  suppressMessages(source(file.path(root, "02_Infrastructure/axiom/lcode_emit.R")))
  S <- tryCatch(rf_notify_table(base_id), error = function(e) NULL)
  if (is.null(S) || !nrow(S$tab)) return(invisible(NULL))
  tab <- S$tab
  # ★블록은 **셀 코드**로 자른다 (2026-09-04). 구판은 `n_used-4 .. n_used` — 블록이 5칸이라는
  #   가정이었다. B1 이 설계에 따라 가변 길이(실측 14칸)가 된 순간 뒤 5칸만 담기고,
  #   그 L-code 가 스스로 "5칸 실측" 이라 적었으며 같은 블록의 B1_4 를 "직전 최고" 로 인용했다.
  #   잘못된 교훈은 next_probe 로 다음 결정에 주입되고 주간 증류에도 그대로 들어간다 —
  #   같은 개수 가정이 커서·알림·검사·발행기 **네 층**에 있었고 여기가 마지막이다.
  .n_end <- as.integer(n_used)
  .row   <- tab[n == .n_end]
  .bid0  <- if (nrow(.row)) sub("_.*$", "", .row$code[1]) else NA_character_
  blk <- if (!is.na(.bid0)) tab[grepl(paste0("^", .bid0, "_"), code) & n <= .n_end] else
         tab[n >= max(1L, .n_end - 4L) & n <= .n_end]
  if (!nrow(blk)) return(invisible(NULL))

  # ★진행 중 블록에서는 발행하지 않는다 — 측정 없는 L-code 는 기록이 아니라 잡음이다.
  #   러너는 블록 경계(측정 완료 후)에서만 부르지만, 검사·수동 호출이 in-flight 를 집을 수 있다.
  if (!any(is.finite(blk$port_t))) return(invisible(NULL))
  bid   <- sub("_.*$", "", blk$code[1])                      # B1/B2/B3/B4
  best  <- blk[which.max(replace(port_t, !is.finite(port_t), -Inf))]
  worst <- blk[which.min(replace(port_t, !is.finite(port_t),  Inf))]
  g     <- table(factor(blk$grade, levels = c("A", "B", "C", "F")))

  # 격자에서 이 블록의 축 이름과 다음 블록을 읽는다 — 하드코딩 금지
  prog <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/reinforce_program.json"),
                                      simplifyVector = FALSE), error = function(e) NULL)
  axis_of <- function(x) { for (b in prog$blocks) if (identical(b$id, x)) return(b$axis %||% x); x }
  .nb  <- rf_next_block(S$entry, bid, prog, root = root)
  nxt  <- .nb$id

  # 기준선 = 이 블록 이전까지의 최고 (없으면 기저 등급)
  # ★기준선은 **이 블록 밖**의 최고다. 구판은 n < lo 로 잘라 같은 블록의 앞 칸이
  #   "직전 최고" 로 인용됐다(B1_4 사례). 블록 코드로 배제한다.
  pre <- tab[!grepl(paste0("^", bid, "_"), code) & n <= .n_end]
  base_line <- if (nrow(pre)) pre[which.max(replace(port_t, !is.finite(port_t), -Inf))] else NULL

  lesson <- sprintf("[%s %s] %d칸 실측 — 최고 %s 다중검정t %.3f · 칼마 %.3f · 등급 A%d/B%d/C%d/F%d.",
                    bid, axis_of(bid), nrow(blk), best$code, best$port_t, best$calmar,
                    g[["A"]], g[["B"]], g[["C"]], g[["F"]])
  if (!is.null(base_line) && is.finite(base_line$port_t))
    lesson <- paste(lesson, sprintf("직전 최고 %s(%.3f) 대비 %s.", base_line$code, base_line$port_t,
                                    if (best$port_t > base_line$port_t) "전진" else "열위 — 이 축은 기준선을 못 넘었다"))
  ins <- tryCatch(rf_insights(blk), error = function(e) character(0))
  if (length(ins)) lesson <- paste(lesson, paste(ins, collapse = " · "))

  # next_probe — 규칙 도출(C/F 는 2건 이상 계약)
  probes <- character(0)
  if (!is.null(nxt)) probes <- c(probes, sprintf("다음 격자 축 %s(%s) — 이 블록 승자 위에서 측정%s",
                                                 nxt, axis_of(nxt),
                                                 if (identical(.nb$src, "decide")) " (적응 순서 잠정 — 원장 미등록)" else ""))
  probes <- c(probes, sprintf("%s(최고 %.3f)는 B4 조합 후보로 고정 · %s(최저 %.3f)는 축 역작동 여부를 조합 LOO 로 분리",
                              best$code, best$port_t, worst$code, worst$port_t))
  if (is.null(nxt)) probes <- c(probes, "격자 소진 — 승자가 B 이상이면 승격(carry) 사슬, 아니면 큐 다음 논문")

  sp <- tryCatch({ ap <- file.path(S$entry$base_artifacts %||% "", "authoritative_remeasure.json")
                   if (file.exists(ap)) jsonlite::fromJSON(ap, simplifyVector = FALSE)$replication$source_paper$url
                   else NULL }, error = function(e) NULL)

  r <- tryCatch(emit_lcode(mode = "reinforcement",
      strategy_id = sprintf("%s_%s", base_id, bid),
      grade = best$grade %||% "F", # ★절단 없음 (도훈 지시 2026-09-04) — 구판은 규칙이 썰 교훈을 900자에서 잘랐다.
      #   칸이 많은 블록일수록 뒤가 잘리므로, 정작 정보가 많은 블록에서 가장 많이 잎혀다.
      lesson_text = lesson,
      metric_type = "backtested",
      next_probe = probes, source_paper = sp,
      portfolio_alpha_t = if (is.finite(best$port_t)) best$port_t else NULL,
      oos_retention = if (is.finite(best$oos)) best$oos else NULL,
      metrics = list(cagr = best$cagr, mdd = best$mdd, calmar = best$calmar),
      tags = c("reinforcement", "rule_grid", tolower(bid)), dry_run = dry_run),
    error = function(e) { message("[rf_block_lcode] emit 실패: ", conditionMessage(e)); NULL })
  invisible(if (is.list(r)) (r$l_code %||% r$id %||% TRUE) else r)
}
