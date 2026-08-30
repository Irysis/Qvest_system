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
  lo  <- max(1L, as.integer(n_used) - 4L)
  blk <- tab[n >= lo & n <= as.integer(n_used)]
  if (!nrow(blk)) return(invisible(NULL))

  bid   <- sub("_.*$", "", blk$code[1])                      # B1/B2/B3/B4
  best  <- blk[which.max(replace(port_t, !is.finite(port_t), -Inf))]
  worst <- blk[which.min(replace(port_t, !is.finite(port_t),  Inf))]
  g     <- table(factor(blk$grade, levels = c("A", "B", "C", "F")))

  # 격자에서 이 블록의 축 이름과 다음 블록을 읽는다 — 하드코딩 금지
  prog <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/reinforce_program.json"),
                                      simplifyVector = FALSE), error = function(e) NULL)
  axis_of <- function(x) { for (b in prog$blocks) if (identical(b$id, x)) return(b$axis %||% x); x }
  nxt <- NULL
  if (!is.null(prog)) { ids <- vapply(prog$blocks, function(b) b$id %||% "", character(1))
                        k <- match(bid, ids); if (!is.na(k) && k < length(ids)) nxt <- ids[k + 1L] }

  # 기준선 = 이 블록 이전까지의 최고 (없으면 기저 등급)
  pre <- tab[n < lo]
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
  if (!is.null(nxt)) probes <- c(probes, sprintf("다음 격자 축 %s(%s) — 이 블록 승자 위에서 측정", nxt, axis_of(nxt)))
  probes <- c(probes, sprintf("%s(최고 %.3f)는 B4 조합 후보로 고정 · %s(최저 %.3f)는 축 역작동 여부를 조합 LOO 로 분리",
                              best$code, best$port_t, worst$code, worst$port_t))
  if (is.null(nxt)) probes <- c(probes, "격자 소진 — 승자가 B 이상이면 승격(carry) 사슬, 아니면 큐 다음 논문")

  sp <- tryCatch({ ap <- file.path(S$entry$base_artifacts %||% "", "authoritative_remeasure.json")
                   if (file.exists(ap)) jsonlite::fromJSON(ap, simplifyVector = FALSE)$replication$source_paper$url
                   else NULL }, error = function(e) NULL)

  r <- tryCatch(emit_lcode(mode = "reinforcement",
      strategy_id = sprintf("%s_%s", base_id, bid),
      grade = best$grade %||% "F", lesson_text = substr(lesson, 1, 900),
      metric_type = "backtested",
      next_probe = probes, source_paper = sp,
      portfolio_alpha_t = if (is.finite(best$port_t)) best$port_t else NULL,
      oos_retention = if (is.finite(best$oos)) best$oos else NULL,
      metrics = list(cagr = best$cagr, mdd = best$mdd, calmar = best$calmar),
      tags = c("reinforcement", "rule_grid", tolower(bid)), dry_run = dry_run),
    error = function(e) { message("[rf_block_lcode] emit 실패: ", conditionMessage(e)); NULL })
  invisible(if (is.list(r)) (r$l_code %||% r$id %||% TRUE) else r)
}
