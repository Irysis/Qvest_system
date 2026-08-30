#!/usr/bin/env Rscript
#==============================================================================
# rf_auto_notify.R — 강화 무인 러너 **텔레그램 발송** (도훈 지시 2026-08-30 "텔레그램도 무인화")
#
# 발송 시점 3곳 (매 칸마다 보내면 소음이라 블록 단위로 묶는다):
#   1) 블록 완료  — n %% 5 == 0 (5·10·15·20칸)  → 등급표 + 차트 2장
#   2) Grade A    — 즉시(러너가 스스로 정지하는 그 순간)
#   3) 20칸 소진  — reinforce_auto_next_paper.R 이 별도로 보낸다
#
# 규약 = qvest-telegram SKILL:
#   §5.6b 계층 표제 `[1계층·강화 n/20]` 의무 · §6 5섹션 · 원칙 9 실측이면 차트 의무
#   §3.1 kv 키는 한글(영어 비율 60% 초과 stop) · bullet 항목당 영어 약어 2건 미만
#   ★지표 원표기(PORT_t·Calmar)는 kv "값" 에만 쓰고 "키" 는 한글로 (v8 §5.6b)
#
# 실패해도 러너를 죽이지 않는다 — 호출자가 tryCatch 로 감싼다.
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

# ── 원장에서 이 entry 의 실측 표를 뽑는다 (계약 산출값만 — 손계산 금지) ───────
rf_notify_table <- function(base_id) {
  led <- fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
  E <- Filter(function(e) identical(e$base_id, base_id), led$entries)
  if (!length(E)) return(NULL)
  E <- E[[1]]
  rows <- lapply(E$attempts, function(a) {
    es <- a$essence
    if (is.null(es) || is.null(es$port_t)) return(NULL)
    data.table(n = as.integer(a$n), code = es$cell_code %||% sprintf("n%02d", a$n),
               grade = as.character(a$grade), port_t = as.numeric(es$port_t),
               sr = as.numeric(es$net_sharpe %||% NA), cagr = as.numeric(es$cagr %||% NA),
               mdd = as.numeric(es$mdd %||% NA), calmar = as.numeric(es$calmar %||% NA),
               oos = as.numeric(es$oos_retention %||% NA))
  })
  rows <- rbindlist(Filter(Negate(is.null), rows), use.names = TRUE)
  if (!nrow(rows)) return(NULL)
  setorder(rows, n)
  list(entry = E, tab = rows, used = as.integer(E$attempts_used %||% nrow(rows)),
       maxa = as.integer(led$max_attempts %||% 20L))
}

# ── 차트 2장 (원칙 9 — 실측 보고는 글만 보내지 않는다) ────────────────────────
rf_notify_charts <- function(tab, outdir) {
  ok <- requireNamespace("ggplot2", quietly = TRUE)
  if (!ok || !nrow(tab)) return(character(0))
  suppressMessages(library(ggplot2))
  dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  d <- copy(tab); d[, blk := sub("_.*$", "", code)]
  d[, lab := factor(sprintf("%s %s", code, grade), levels = rev(sprintf("%s %s", code, grade)))]
  p1 <- ggplot(d, aes(x = lab, y = port_t, fill = blk)) +
    geom_col(width = 0.66) +
    geom_hline(yintercept = 2.95, linetype = "22", linewidth = 0.8, colour = "#B3261E") +
    annotate("text", x = 1, y = 3.0, label = "A 문턱 2.95", hjust = 0, size = 3.2, colour = "#B3261E") +
    geom_text(aes(label = sprintf("%.3f", port_t)), hjust = -0.15, size = 3.1, colour = "#333333") +
    coord_flip(clip = "off") + ylim(min(0, min(d$port_t, na.rm = TRUE)) - 0.1, 3.4) +
    labs(title = "무인 강화 — 셀별 다중검정 t값", subtitle = "규칙 격자 자동 실행 · 전 셀 실투형 동일 축",
         x = NULL, y = "PORT_t", caption = "출처: 각 셀 authoritative_remeasure.json (15bps 순비용 판)") +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold", size = 12.5), legend.position = "top",
          panel.grid.major.y = element_blank(), plot.margin = margin(10, 28, 8, 8),
          plot.caption = element_text(size = 7.5, colour = "#666666"))
  f1 <- file.path(outdir, "auto_port_t.png"); ggsave(f1, p1, width = 8.4, height = 5.4, dpi = 150)
  p2 <- ggplot(d[is.finite(mdd) & is.finite(oos)], aes(x = mdd, y = oos, colour = blk)) +
    geom_hline(yintercept = 0, linetype = "22", colour = "#999999") +
    geom_point(aes(size = port_t), alpha = 0.85) +
    geom_text(aes(label = code), vjust = -1.1, size = 2.9, show.legend = FALSE) +
    scale_size_continuous(name = "PORT_t", range = c(2.5, 7)) +
    labs(title = "낙폭 대 표본외 유지율", subtitle = "왼쪽 = 낙폭 작음 · 위 = 표본 밖에서 유지. 0선 아래는 반전",
         x = "최대낙폭", y = "표본외 유지율", caption = "점 크기 = 다중검정 t값") +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold", size = 12.5), legend.position = "top",
          plot.caption = element_text(size = 7.5, colour = "#666666"))
  f2 <- file.path(outdir, "auto_mdd_oos.png"); ggsave(f2, p2, width = 8.4, height = 4.8, dpi = 150)
  c(f1, f2)
}

# ── ★셀별 "무엇을 강화했나" — **전문 팩트만** (도훈 지시 2026-08-30) ──────────
#   "조합 축 · 승자 요소" 같은 추상 라벨은 무엇을 바꾼 건지 알려주지 않는다.
#   실제 팩터 코드 · 비중식 · 유니버스 정의를 쓴다. 출처는 **실행된 셀 스펙**(스펙 부재 시 격자).
.rf_f2 <- function(f2) {
  if (is.null(f2) || identical(f2$kind, "none")) return("모멘텀 12-1 단독")
  id <- f2$id %||% "?"
  nm <- switch(id, "V01_BM" = "가치 BM", "Q01_GPA" = "수익성 GP/A",
                   "L01_Amihud" = "비유동 Amihud", "C13_Revision_Breadth_3m" = "이익수정 3M",
                   "lowvol60" = "저변동 sigma60", id)
  sprintf("모멘텀 12-1 + %s (%s) rankZ 50:50", nm, id)
}
.rf_wt <- function(w) {
  k <- w$kind %||% "ew"
  switch(k,
    "ew"               = "동일가중 1/25",
    "score_tilt"       = sprintf("스코어 틸트 w~(z-zmin+%s)", format(w$eps %||% 0.05)),
    "rank_weight"      = "랭크 가중 w~(26-순위)",
    "rank_weight_sqrt" = "제곱근 랭크 w~sqrt(26-순위)",
    "inv_vol"          = sprintf("역변동성 w~1/sigma%s (창끝 t-1)", format(w$window %||% 60)),
    "minvar_lw"        = "최소분산 Ledoit-Wolf",
    "hrp"              = "계층 리스크패리티",
    k)
}
.rf_un <- function(u) {
  k <- u$kind %||% "k200_kq150"
  switch(k,
    "k200_kq150"     = "K200 합집합 KQ150",
    "all_listed"     = "지수 멤버십 해제 전상장",
    "index"          = sprintf("%s 단독", u$flag %||% "?"),
    "size_band"      = sprintf("시총 %.0f~%.0f 분위", 100*(u$q_lo %||% 0), 100*(u$q_hi %||% 1)),
    "sector_neutral" = "섹터 중립 Sector_Lv2",
    k)
}
#' 셀 코드 → "팩터 · 비중 · 유니버스" 한 줄. 스펙 파일 우선, 없으면 격자에서 조립.
#' ★B2/B3 는 격자에 factor2 가 없다 — **실행 시점에 B1 승자를 물려받기** 때문이다.
#'   스펙 파일이 없는(수동 실행된) 셀은 원장에서 B1 승자를 읽어 채운다.
#'   이게 없으면 B2 셀이 "모멘텀 단독" 으로 잘못 표시된다(2026-08-30 적발).
rf_cell_desc <- function(base_id = NULL) {
  g <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE),
                error = function(e) NULL)
  if (is.null(g)) return(list())
  .b1f2 <- NULL
  if (!is.null(base_id)) {
    S <- tryCatch(rf_notify_table(base_id), error = function(e) NULL)
    if (!is.null(S)) {
      b1 <- S$tab[grepl("^B1_", code)]
      if (nrow(b1)) {
        wcode <- b1[which.max(replace(port_t, !is.finite(port_t), -Inf))]$code
        for (b in g$blocks) for (cl in b$cells) if (identical(cl$code, wcode)) .b1f2 <- cl$factor2
      }
    }
  }
  out <- list()
  for (b in g$blocks) for (cl in b$cells) {
    sp <- NULL
    for (d in c(".cache/rf_parallel", ".cache")) {
      f <- file.path(ROOT, d, sprintf(if (identical(d, ".cache")) "rf_cell_spec_%s.json" else "spec_%s.json", cl$code))
      if (file.exists(f)) { sp <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL); break }
    }
    f2 <- if (!is.null(sp)) sp$factor2 else (cl$factor2 %||% (if (b$id %in% c("B2","B3")) .b1f2 else NULL))
    wt <- if (!is.null(sp)) sp$weighting else (cl$weighting %||% list(kind = "ew"))
    un <- if (!is.null(sp)) sp$universe  else (cl$universe  %||% list(kind = "k200_kq150"))
    out[[cl$code]] <- sprintf("%s | %s | %s", .rf_f2(f2), .rf_wt(wt), .rf_un(un))
  }
  out
}

# ── ★인사이트 도출 (도훈 지시 2026-08-30 "인사이트도 같이 보내주면 좋을듯") ──
#   수치만 보내면 "그래서 무엇을 알게 됐나" 가 빠진다. 아래는 **실측 표에서 기계적으로
#   도출되는 것만** 말한다 — 해석을 지어내지 않는다. 근거가 없으면 그 줄을 내지 않는다.
rf_insights <- function(tab) {
  out <- character(0); if (!nrow(tab)) return(out)
  fin <- function(v) v[is.finite(v)]
  m <- fin(tab$mdd)
  if (length(m) >= 5 && (max(m) - min(m)) < 0.15)
    out <- c(out, sprintf("낙폭이 축을 바꿔도 %.0f~%.0f%% 대역에 갇힘 (폭 %.1f%%p)",
                          100*min(m), 100*max(m), 100*(max(m)-min(m))))
  bc <- tab[which.max(replace(calmar, !is.finite(calmar), -Inf))]
  if (isTRUE(is.finite(bc$calmar) && is.finite(bc$mdd) && bc$calmar < 0.64))
    out <- c(out, sprintf("칼마 최고 %.2f — 낙폭 %.0f%% 하에서 합격선은 연복리 %.0f%% 를 요구",
                          bc$calmar, 100*bc$mdd, 100*0.64*bc$mdd))
  b1 <- tab[grepl("^B1_", code)]; b4 <- tab[grepl("^B4_", code)]
  if (nrow(b1) >= 2 && nrow(b4) >= 2) {
    t1 <- b1[which.max(replace(port_t, !is.finite(port_t), -Inf))]
    t4 <- b4[which.max(replace(port_t, !is.finite(port_t), -Inf))]
    if (isTRUE(is.finite(t1$port_t) && is.finite(t4$port_t) && t4$port_t > t1$port_t))
      out <- c(out, sprintf("조합 최고 %.3f 가 단독 최고 %.3f 를 넘음 — 블록별 최적의 합이 전체 최적 아님",
                            t4$port_t, t1$port_t))
  }
  o2 <- fin(tab$oos)
  if (length(o2) >= 5 && max(o2) < 0.7)
    out <- c(out, sprintf("표본외 유지율 최고 %.2f — %d칸 전부 합격 구간 밖", max(o2), length(o2)))
  if (!any(tab$grade == "A", na.rm = TRUE) && nrow(tab) >= 5)
    out <- c(out, sprintf("A등급 0건 — %d칸 측정 후 이 축 조합의 상한이 관측됨", nrow(tab)))
  substr(out, 1, 78)
}

# ── 발송 ──────────────────────────────────────────────────────────────────────
#' @param kind "block" (블록 완료) 또는 "grade_a"
rf_auto_notify <- function(base_id, n, kind = "block") {
  S <- rf_notify_table(base_id); if (is.null(S)) return(invisible(FALSE))
  tab <- S$tab; blk <- sub("_.*$", "", tab$code)
  best <- tab[which.max(replace(port_t, !is.finite(port_t), -Inf))]
  bestC <- tab[which.max(replace(calmar, !is.finite(calmar), -Inf))]
  gcnt <- table(factor(tab$grade, levels = c("A", "B", "C", "F")))
  ch <- tryCatch(rf_notify_charts(tab, file.path(ROOT, "stage_artifacts/rf_auto_report")),
                 error = function(e) character(0))
  ttl <- if (identical(kind, "grade_a"))
    sprintf("[1계층·강화 %d/%d] Grade A 도달 — 무인 정지, 확인 요망", n, S$maxa)
  else
    sprintf("[1계층·강화 %d/%d] 무인 블록 완료 — %s", n, S$maxa, sub("_.*$", "", tab[n == max(tab$n)]$code))
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
  secs <- list(
    list(type = "bullet", emoji = "\U0001F3AF", heading = "현재 리서치 상황",
         items = c("단계: 1계층 강화 프로세스 — 무인 규칙 러너",
                   sprintf("대상: 제가디시-티트먼 1993 모멘텀 강화 · 기저 등급 %s", S$entry$base_grade %||% "F"),
                   sprintf("위치: %d/%d 칸 소진 · 측정 완료 %d건", S$used, S$maxa, nrow(tab)),
                   sprintf("등급 분포: A %d · B %d · C %d · F %d",
                           gcnt[["A"]], gcnt[["B"]], gcnt[["C"]], gcnt[["F"]]))),
    list(type = "summary", emoji = "\U0001F4CC",
         body = if (identical(kind, "grade_a"))
           sprintf("Grade A 도달 — 러너가 스스로 멈췄습니다. 검증과 등재는 확인이 필요합니다")
         else sprintf("최고 %s · 다중검정 t값 %.3f · 합격선 2.95", best$code, best$port_t)),
    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 수치",
         kv = list("최고 다중검정 t값" = sprintf("%.3f (%s)", best$port_t, best$code),
                   "최고 연복리수익률" = sprintf("%.1f%%", 100 * max(tab$cagr, na.rm = TRUE)),
                   "최고 칼마" = sprintf("%.3f (%s · 합격선 0.64)", bestC$calmar, bestC$code),
                   "최대낙폭 대역" = sprintf("%.1f~%.1f%%", 100 * min(tab$mdd, na.rm = TRUE),
                                             100 * max(tab$mdd, na.rm = TRUE)))),
    list(type = "bullet", emoji = "\U0001F527", heading = "무엇을 강화했나",
         items = { dsc <- rf_cell_desc(base_id)
                   ord <- tab[order(-replace(port_t, !is.finite(port_t), -Inf))]
                   k <- min(4L, nrow(ord))
                   vapply(seq_len(k), function(i2) {
                     r <- ord[i2]
                     substr(sprintf("%s %s — %s (%s)", if (i2 == 1L) "1위" else paste0(i2, "위"),
                                    r$code, dsc[[r$code]] %||% "격자 밖",
                                    sprintf("t %.2f · 등급 %s", r$port_t, r$grade)), 1, 78)
                   }, character(1)) }),

    list(type = "bullet", emoji = "💡", heading = "이번 배치에서 알게 된 것",
         items = { ins <- rf_insights(tab)
                   if (length(ins) < 2) ins <- c(ins, "등급은 계약 산출값만 인용 — 손계산 없음",
                                                 "무인 러너는 자본에 접근하지 않음")
                   utils::head(ins, 5) }),
    list(type = "bullet", emoji = "\u27A1\uFE0F", heading = "다음",
         items = if (identical(kind, "grade_a"))
           c("처분: 자동 진행 정지 — 검증과 등재는 사람 확인 후",
             "요청 파일: qepm/mailbox/judge_request.json")
         else c("처분: 자본 배정 없음 — 등급 C 이하는 참고용 보관",
                sprintf("다음: 남은 %d칸을 무인으로 채웁니다", max(0L, S$maxa - S$used)),
                "20칸 소진 시 큐 다음 논문 착수 요청이 발송됩니다")))
  tg_agent_brief(agent = "AlphaSearch", title = ttl, sections = secs, charts = ch)
  invisible(TRUE)
}
