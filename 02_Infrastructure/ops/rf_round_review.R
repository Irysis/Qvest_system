#!/usr/bin/env Rscript
#==============================================================================
# rf_round_review.R — 라운드 종료 리뷰 (도훈 지시 2026-09-04)
#
# "최종 강화 프로세스 종료 메세지가 2번 오는거 같은데? 마지막에 오는 메세지는
#  전체 블록에 대한 리뷰여야할 꺼 같아"
#
# 실측: 종료 시점에 두 통이 나갔다 —
#   20:17  무인 블록 완료 — 결합   (마지막 **블록**만 리뷰)
#   20:26  B등급 구성 추가 강화 개시 (인계 쪽지)
# 어느 쪽도 35칸 전체의 결론이 아니었다. 라운드를 닫는 메시지가 라운드를 요약해야 한다.
#
# ★이 파일은 승격/이월 메시지를 **대체**한다. 승격 정보는 이 리뷰의 마지막 절로 들어간다.
#   두 통을 한 통으로 합치는 것이지 하나를 더 늘리는 게 아니다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RR_BLKNAME <- c(B1 = "멀티팩터", B5 = "리스크오버레이", B2 = "비중방법론",
                B3 = "유니버스", B4 = "결합")

#' 라운드 전체를 한 통으로 요약해 발송한다.
#' @param entry  강화 원장 entry (exhausted 직후)
#' @param promo  승격 정보 list(base_id, depth, cell, grade, port_t) 또는 NULL(이월)
rf_round_review <- function(entry, promo = NULL, root = Sys.getenv("QM_ROOT", getwd())) {
  ats <- entry$attempts %||% list()
  if (!length(ats)) return(invisible(FALSE))
  D <- rbindlist(lapply(ats, function(a) {
    es <- a$essence %||% list()
    data.table(code = as.character(a$cell_code %||% ""),
               grade = as.character(a$grade %||% ""),
               port_t = suppressWarnings(as.numeric(es$port_t %||% NA)),
               cagr = suppressWarnings(as.numeric(es$cagr %||% NA)),
               mdd = suppressWarnings(as.numeric(es$mdd %||% NA)),
               calmar = suppressWarnings(as.numeric(es$calmar %||% NA)),
               inh = !is.null(es$inherited_from))
  }), fill = TRUE)
  D[, blk := sub("_.*$", "", code)]
  M <- D[is.finite(port_t)]
  if (!nrow(M)) return(invisible(FALSE))
  own <- M[inh == FALSE]
  best <- M[which.max(port_t)]
  bestC <- M[which.max(replace(calmar, !is.finite(calmar), -Inf))]

  ## ── 블록별 궤적 ──────────────────────────────────────────────────────────
  ord <- intersect(c("B1", "B5", "B2", "B3", "B4"), unique(M$blk))
  trace <- vapply(ord, function(b) {
    s <- M[blk == b]
    sprintf("%s %d칸 · 최고 PORT_t %.3f · Calmar 중앙 %.3f",
            RR_BLKNAME[[b]] %||% b, nrow(s), max(s$port_t, na.rm = TRUE),
            stats::median(s$calmar, na.rm = TRUE))
  }, character(1))

  ## ── 축별 기여 (LOO) — 전결합을 기준선으로 Δ 를 낸다 ──────────────────────
  loo <- character(0)
  b4 <- M[blk == "B4"]
  if (nrow(b4)) {
    .pick <- function(pat) { r <- b4[grepl(pat, code)]; if (nrow(r)) r[1] else NULL }
    full <- M[code == b4$code[1]]                       # B4 첫 칸 = 전결합
    if (nrow(full)) {
      lbl <- c("팩터", "비중", "유니버스", "오버레이")
      for (k in seq_along(lbl)) {
        r <- b4[k + 1L]
        if (is.na(r$code) || !is.finite(r$port_t)) next
        loo <- c(loo, sprintf("− %s  ΔPORT_t %+.3f · ΔCalmar %+.3f",
                              lbl[k], full$port_t - r$port_t, full$calmar - r$calmar))
      }
      if (length(loo)) loo <- c(sprintf("전결합 기준 PORT_t %.3f · Calmar %.3f",
                                        full$port_t, full$calmar),
                                loo, "Δ 가 음수면 그 축이 순손실이다.")
    }
  }

  ## ── 벽 — A 문턱까지 무엇이 필요한가 (산술) ───────────────────────────────
  gap <- character(0)
  if (is.finite(best$port_t))
    gap <- c(gap, sprintf("PORT_t %.3f → 문턱 2.95 까지 %+.3f", best$port_t, 2.95 - best$port_t))
  if (is.finite(bestC$calmar) && is.finite(bestC$mdd) && bestC$mdd > 0)
    gap <- c(gap, sprintf("Calmar %.3f → 문턱 0.64. MDD %.1f%% 를 유지하면 CAGR %.0f%% 가 필요하다(현재 %.1f%%)",
                          bestC$calmar, 100 * bestC$mdd, 100 * 0.64 * bestC$mdd, 100 * bestC$cagr))
  mr <- range(M$mdd, na.rm = TRUE)
  if (all(is.finite(mr)))
    gap <- c(gap, sprintf("MDD 는 %d칸 내내 %.1f~%.1f%% 를 못 벗어났다", nrow(M), 100*mr[1], 100*mr[2]))

  nxt <- if (!is.null(promo))
    c(sprintf("승격 — %s(%s · PORT_t %.3f)을 기저로 새 라운드(깊이 %d)",
              promo$cell %||% "?", promo$grade %||% "?",
              suppressWarnings(as.numeric(promo$port_t %||% NA)), promo$depth %||% 1L),
      "부모 최고치를 못 넘으면 승격 중단 · 깊이 상한 3",
      "다음 논문은 이 사슬이 끝난 뒤로 밀린다")
  else c("승격 조건 미충족 — 큐의 다음 논문으로 이월", "이 논문은 소비 처리된다")

  gc2 <- table(factor(own$grade, levels = c("A", "B", "C", "F")))
  secs <- list(
    list(type = "summary", emoji = "\U0001F3C1",
         body = sprintf("%d칸 소진 · 최고 %s PORT_t %.3f · Calmar %.3f",
                        nrow(D), best$grade, best$port_t, best$calmar)),
    list(type = "kv", emoji = "\U0001F4CA", heading = "라운드 최종",
         kv = list("최고 PORT_t" = sprintf("%.3f (%s · %s)", best$port_t, best$code, best$grade),
                   "최고 Calmar" = sprintf("%.3f (%s)", bestC$calmar, bestC$code),
                   "CAGR / MDD" = sprintf("%.1f%% / %.1f%%", 100*best$cagr, 100*best$mdd),
                   "등급 분포" = sprintf("A %d · B %d · C %d · F %d (승계 %d칸 제외)",
                                     gc2[["A"]], gc2[["B"]], gc2[["C"]], gc2[["F"]], sum(M$inh)))),
    list(type = "bullet", emoji = "\U0001F9ED", heading = "블록별 궤적", items = unname(trace)),
    if (length(loo)) list(type = "bullet", emoji = "\U00002696", heading = "축별 기여 (LOO)",
                          items = loo) else NULL,
    list(type = "bullet", emoji = "\U0001F9F1", heading = "무엇이 벽이었나", items = gap),
    list(type = "bullet", emoji = "\U000027A1\U0000FE0F", heading = "다음", items = nxt)
  )
  secs <- Filter(Negate(is.null), secs)

  ok <- tryCatch({
    ## ★telegram 을 **명시적으로** source 한다 — rf_auto_notify.R 은 그걸 함수 안에서
    ##   하므로 이 파일에서는 tg_agent_brief 가 보이지 않는다(실측: could not find function).
    suppressMessages(source(file.path(root, "02_Infrastructure/telegram/telegram_notify.R")))
    suppressMessages(source(file.path(root, "02_Infrastructure/ops/rf_auto_notify.R")))
    secs <- .rf_axname_deep(secs)          # 블록 코드 → 축 이름 (같은 정본)
    r <- tg_agent_brief(agent = "AlphaSearch",
      lock_scope = sprintf("rf_round_review_%s", entry$base_id),
      title = sprintf("[1계층·라운드 종료] %s — %d칸 · 최고 %s",
                      substr(.rf_target_label(entry), 1, 40), nrow(D), best$grade),
      sections = secs, relaxed = TRUE, glossary = FALSE,
      decode_jargon = FALSE, decode_mode = "off")
    isTRUE(r$ok %||% TRUE)
  }, error = function(e) { message("[rf_round_review] ", conditionMessage(e)); FALSE })
  invisible(ok)
}
