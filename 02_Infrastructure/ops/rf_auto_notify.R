#!/usr/bin/env Rscript
#==============================================================================
# rf_auto_notify.R — 강화 무인 러너 **텔레그램 발송** (도훈 지시 2026-08-30 "텔레그램도 무인화")
#
# 발송 시점 3곳 (매 칸마다 보내면 소음이라 블록 단위로 묶는다):
#   1) 블록 완료  — n %% 5 == 0 (블록 경계마다)  → 등급표 + 차트 2장
#   2) Grade A    — 즉시(러너가 스스로 정지하는 그 순간)
#   3) 상한 소진  — reinforce_auto_next_paper.R 이 별도로 보낸다
#
# 규약 = qvest-telegram SKILL:
#   §5.6b 계층 표제 `[1계층·강화 n/N]` 의무(N = 원장 max_attempts) · §6 5섹션 · 원칙 9 실측이면 차트 의무
#   §3.1 kv 키는 한글(영어 비율 60% 초과 stop) · bullet 항목당 영어 약어 2건 미만
#   ★지표 원표기(PORT_t·Calmar)는 kv "값" 에만 쓰고 "키" 는 한글로 (v8 §5.6b)
#
# 실패해도 러너를 죽이지 않는다 — 호출자가 tryCatch 로 감싼다.
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
# ★승자 셀 성과 요약 = 예전 알파 서칭 포맷(도훈 지시 2026-08-30).
#   배치 kv 는 전 칸 요약이라 상세가 없다 — 승자 한 칸의 전체 지표를 붙인다.
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_perf_summary.R")))

# ── 원장에서 이 entry 의 실측 표를 뽑는다 (계약 산출값만 — 손계산 금지) ───────
# ★스펙 헬퍼는 정본(rf_spec_sig.R)을 쓴다 — 재구현하면 두 벌이 갈린다.
#   ★인자 안에서 source(local=TRUE) 하면 suppressMessages 프레임에 정의돼 사라진다(2026-09-04 실측).
if (!exists(".rp_all_factors")) suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")))

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
       # ★분모는 **entry 별 상한**이다 (2026-09-04). B1 설계가 가변 길이가 되면서 총예산이
       #   entry 마다 다르다(실측 34). 전역 25 를 쓰면 "34/25" 같은 보고가 나간다.
       maxa = as.integer(E$max_attempts %||% led$max_attempts %||% 25L))
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
# ★기저를 여기서 말하지 않는다. 구판은 "모멘텀 12-1 + X rankZ 50:50" 을 반환했는데,
#   ①기저는 논문마다 다르고(현행은 충실구현 engine.R 신호이지 모멘텀이 아니다)
#   ②비율은 팩터 개수에 따라 변한다(2팩터면 50:50 이 아니라 1/3씩).
#   즉 두 군데가 동시에 틀렸다. 기저와 비율은 호출부가 한 번만 말한다.
.rf_f2 <- function(f2) {
  if (is.null(f2) || identical(f2$kind, "none")) return("추가 팩터 없음")
  id <- f2$id %||% f2$catalog_id %||% "?"
  nm <- switch(id, "V01_BM" = "가치 B/M", "Q01_GPA" = "수익성 GP/A",
                   "L01_Amihud" = "비유동 Amihud", "C13_Revision_Breadth_3m" = "이익수정 3M",
                   "lowvol60" = "저변동 sigma60", id)
  # 한글 라벨이 없으면 id 를 두 번 쓰지 않는다 — "D16_Coskewness (D16_Coskewness)" 는
  # 30자를 먹고 정보가 0이다. 순위 줄이 48자로 잘리는 자리에서 이게 구분자를 밀어낸다.
  if (identical(nm, id)) id else sprintf("%s (%s)", nm, id)
}
# 컴포짓 비율 — 기저 1 + 팩터 n 을 rankZ 등가중으로 섞는다. 이 한 줄이 희석의 크기다.
.rf_mix <- function(nf) {
  nf <- as.integer(nf %||% 0L)
  sprintf("rankZ 등가중 기저 1/%d + 팩터 %d종", nf + 1L, nf)
}
.rf_wt <- function(w) {
  k <- w$kind %||% "ew"
  # ★카탈로그 arm 은 kind 가 전부 "catalog" 라 그것만 찍으면 다섯 칸이 같은 이름이 된다
  #   (2026-08-31 실측: B2 칸이 전부 "catalog"). 실제 방법 이름은 label/catalog_id 에 있다.
  if (identical(k, "catalog"))
    return(sprintf("비중 %s", w$label %||% sub("^.*:", "", w$catalog_id %||% "?")))
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
.RF_OV_ACT <- c(cross_sectional = "종목별", scalar_exposure = "총노출")
.RF_OV_ST  <- c(drawdown = "낙폭", vol = "변동성", multivar = "다변량", ml = "학습",
                trend = "추세", dispersion = "분산", holding_level = "종목상태")
# 오버레이 축 — B5 다섯 칸을 가르는 유일한 값이다. 이게 없으면 순위 네 줄이 같은 문장이 된다.
#' 오버레이 서술. 층 리스트(v10.2 중첩)를 받으면 층마다 축약해 " + " 로 잇는다.
#' ★구판은 단수 객체만 봤다 — 리스트가 오면 o$kind 가 NULL 이라 NA 를 돌려주고
#'   오버레이 축이 서술에서 통째로 사라졌다(B5 네 칸이 같은 문장으로 보이던 병의 재발 경로).
.rf_ov <- function(o) {
  if (is.null(o)) return(NA_character_)
  if (is.null(o$kind)) {
    L <- Filter(function(z) is.list(z) && !is.null(z$kind), o)
    if (!length(L)) return(NA_character_)
    v <- vapply(L, function(z) .rf_ov1(z) %||% NA_character_, character(1))
    v <- v[!is.na(v)]
    if (!length(v)) return(NA_character_)
    v[-1] <- sub("^오버레이 ", "", v[-1])   # 접두는 한 번만 — 층은 " + " 로 잇는다
    return(paste(v, collapse = " + "))
  }
  .rf_ov1(o)
}
.rf_ov1 <- function(o) {
  if (is.null(o) || identical(as.character(o$kind %||% "none"), "none")) return(NA_character_)
  aid <- as.character(o$arm_id %||% "")
  knd <- as.character(o$kind   %||% "?")
  ax <- tryCatch({
    d <- fromJSON(file.path(ROOT, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE)
    h <- Filter(function(a) identical(as.character(a$id %||% ""), aid), d$arms %||% list())
    if (!length(h)) h <- Filter(function(a) identical(as.character(a$kind %||% ""), knd), d$arms %||% list())
    if (length(h)) {
      # ★action/state 가 비어 있는 구 arm 은 기전 지도의 계열 매핑으로 파생한다 —
      #   축 라벨을 여기서 따로 만들면 픽커·지도와 갈린다(정본 하나 규율).
      z <- tryCatch({
        # ★cat() 배너는 suppressMessages 로 안 막힌다 — 출력을 통째로 삼킨다.
        #   안 그러면 arm 하나당 한 줄씩 스케줄러 로그에 쌓인다.
        invisible(utils::capture.output(suppressMessages(
          source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_mechanism_map.R"), local = TRUE))))
        rfm_arm_axis(h[[1]])
      }, error = function(e) list(action = "", state = ""))
      a <- .RF_OV_ACT[[as.character(h[[1]]$action %||% z$action %||% "")]] %||% ""
      s <- .RF_OV_ST[[ as.character(h[[1]]$state  %||% z$state  %||% "")]] %||% ""
      paste(c(a, s)[nzchar(c(a, s))], collapse = "/")
    } else ""
  }, error = function(e) "")
  nm <- if (nzchar(aid)) aid else knd
  if (nzchar(ax)) sprintf("오버레이 %s (%s)", ax, nm) else sprintf("오버레이 %s", nm)
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
# ── 대상 라벨 — ★원장 entry 에서 파생한다 ────────────────────────────────────
#   2026-08-30: 이 자리에 논문 제목이 "제가디시-티트먼 1993 모멘텀" 으로 **하드코딩**돼
#   있었다. 그 논문은 전날 소진된 직전 대상이고, 그 뒤 모든 블록 텔레그램이 틀린 대상을
#   보고했다. 무인 배선은 다 있었는데 이 한 줄만 논문을 따라오지 않았다.
#   출처 = 충실구현 산출물의 source_paper(계약이 쓴 값). 없으면 paper_key → base_id 순.
.rf_target_label <- function(E) {
  ttl <- NULL
  # ★승격 entry 의 base_artifacts 는 **부모의 승자 셀** 산출물이다. 그 안의 source_paper 는
  #   그 셀의 근거 논문(예: 유니버스 셀이면 Hong-Lim-Stein)이지 이 전략의 기저 논문이 아니다.
  #   2026-08-31 적발: 승격 1대 텔레그램이 대상을 B3_11 의 근거 논문으로 보고했다.
  #   그래서 사슬을 거슬러 **parent 가 없는 최초 entry** 의 산출물을 본다.
  ba <- E$base_artifacts %||% ""
  if (!is.null(E$parent)) {
    led <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"),
                             simplifyVector = FALSE), error = function(e) NULL)
    cur <- E; guard <- 0L
    while (!is.null(led) && !is.null(cur$parent) && guard < 8L) {
      guard <- guard + 1L
      pid <- cur$parent$base_id %||% ""
      nx <- Filter(function(x) identical(x$base_id, pid), led$entries)
      if (!length(nx)) break
      cur <- nx[[1]]
    }
    if (nzchar(cur$base_artifacts %||% "")) ba <- cur$base_artifacts
  }
  ap <- file.path(ba, "authoritative_remeasure.json")
  if (nzchar(ba) && file.exists(ap)) {
    o <- tryCatch(fromJSON(ap, simplifyVector = FALSE), error = function(e) NULL)
    ttl <- o$replication$source_paper$title %||% NULL
  }
  if (is.null(ttl) || !nzchar(ttl)) ttl <- E$paper_key %||% E$base_id %||% "?"
  ttl <- substr(as.character(ttl), 1, 58)
  # 승격 사슬이면 그 사실이 대상의 일부다 — 같은 논문이라도 다른 기저다
  if (!is.null(E$parent))
    ttl <- sprintf("%s [승격 %s대]", ttl, as.character(E$parent$depth %||% 1L))
  ttl
}

# 미결 칸은 essence 가 없어 cell_code 를 못 읽는다 — 격자 순서(n)로 되찾는다.
.rf_cellcode_of <- function(a) {
  g <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE),
                error = function(e) NULL)
  if (is.null(g)) return(NULL)
  cs <- do.call(c, lapply(g$blocks, function(b) lapply(b$cells, function(cl) cl$code)))
  n <- as.integer(a$n %||% 0L)
  if (n >= 1L && n <= length(cs)) cs[[n]] else NULL
}
# ★B4(결합) 칸 라벨 — 결합 칸의 정체성은 팩터/비중/유니버스 값이 아니라 **어느 블록을
#   넣고 뺐는가**(부분집합)다. 축 차집합으로 서술하면, LOO 로 뺀 축이 마침 carry 와 같은
#   값일 때 여러 칸이 정확히 같은 문장이 된다 — 2026-09-03 도훈 적발("2위에서 4위 같은 내용").
.RF_BLK_KO <- c(B1 = "팩터", B2 = "비중", B3 = "유니버스", B5 = "오버레이")
.rf_combo <- function(code) {
  g <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE),
                error = function(e) NULL)
  if (is.null(g)) return(NA_character_)
  for (b in g$blocks) for (cl in b$cells) if (identical(as.character(cl$code %||% ""), code)) {
    u <- as.character(unlist(cl$combo$use %||% list()))
    if (!length(u)) return(NA_character_)
    ko <- unname(.RF_BLK_KO[u]); ko[is.na(ko)] <- u[is.na(ko)]
    lab <- as.character(cl$label %||% "")
    return(if (nzchar(lab)) sprintf("%s · %s", lab, paste(ko, collapse = "+"))
           else paste(ko, collapse = "+"))
  }
  NA_character_
}

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
    # ★spec 경로는 2026-08-31 부터 entry 별이다(구판 고정 이름은 다음 entry 가 덮어써
    #   부모 스펙을 소실시켰다). 이 entry 것을 먼저 찾고, 없으면 구 이름으로 떨어진다.
    sp <- NULL
    .cands <- character(0)
    if (!is.null(base_id) && nzchar(base_id)) .cands <- c(.cands,
      file.path(ROOT, ".cache/rf_parallel", sprintf("spec_%s__%s.json", cl$code, substr(base_id, 1, 48))),
      file.path(ROOT, ".cache",             sprintf("rf_cell_spec_%s__%s.json", cl$code, substr(base_id, 1, 48))))
    .cands <- c(.cands,
      file.path(ROOT, ".cache/rf_parallel", sprintf("spec_%s.json", cl$code)),
      file.path(ROOT, ".cache",             sprintf("rf_cell_spec_%s.json", cl$code)))
    for (f in .cands) {
      if (file.exists(f)) { sp <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL); break }
    }
    # 승계 entry 의 스펙은 factor2 가 아니라 factors(복수)를 쓴다 — 그쪽이 정본이다.
    f2 <- if (!is.null(sp) && length(sp$factors))
            paste(vapply(sp$factors, .rf_f2, character(1)), collapse = "+")
          else if (!is.null(sp)) sp$factor2
          else (cl$factor2 %||% (if (b$id %in% c("B2","B3")) .b1f2 else NULL))
    wt <- if (!is.null(sp)) sp$weighting else (cl$weighting %||% list(kind = "ew"))
    un <- if (!is.null(sp)) sp$universe  else (cl$universe  %||% list(kind = "k200_kq150"))
    .f2txt <- if (is.character(f2)) f2 else .rf_f2(f2)
    # ★오버레이는 있을 때만 4번째 축으로 붙인다 — B1~B3 문장은 3축 그대로다(하위호환).
    ov <- if (!is.null(sp)) sp$overlay else cl$overlay
    .ovtxt <- .rf_ov(ov)
    out[[cl$code]] <- if (is.na(.ovtxt))
      sprintf("%s | %s | %s", .f2txt, .rf_wt(wt), .rf_un(un)) else
      sprintf("%s | %s | %s | %s", .f2txt, .rf_wt(wt), .rf_un(un), .ovtxt)
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
  # 승자 셀의 산출물 디렉터리 (원장 attempts[].artifacts)
  .win_dir <- tryCatch({
    hit <- Filter(function(x) identical(as.integer(x$n %||% -1L), as.integer(best$n)),
                  info$entry$attempts)
    d <- if (length(hit)) hit[[1]]$artifacts %||% NULL else NULL
    if (!is.null(d) && dir.exists(d)) d else NULL
  }, error = function(e) NULL)
  .win_kv <- if (is.null(.win_dir)) list() else
    tryCatch(rf_perf_kv(.win_dir), error = function(e) list())

  ch <- tryCatch(rf_notify_charts(tab, file.path(ROOT, "stage_artifacts/rf_auto_report")),
                 error = function(e) character(0))
  ttl <- if (identical(kind, "grade_a"))
    sprintf("[1계층·강화 %d/%d] Grade A 도달 — 무인 정지, 확인 요망", n, S$maxa)
  else
    sprintf("[1계층·강화 %d/%d] 무인 블록 완료 — %s", n, S$maxa, sub("_.*$", "", tab[n == max(tab$n)]$code))
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
  .learn_sec <- NULL
  # ★이번 블록에서 배운 것 (도훈 지시 2026-09-04) — 규칙 요약 + LLM 기전 + 처방.
  #   L-code 에 있을 때만 낸다. 없으면 그 줄을 안 낸다(없는 것을 지어내지 않는다).
  #   ★발송이 L-code·기전보다 **뒤로** 옮겨졌기에 이 절이 채워질 수 있다 — 구판 순서에서는
  #     텔레그램이 먼저 나가서 기전이 영원히 메시지에 못 들어갔다.
  { .lcp <- file.path(ROOT, "stage_artifacts/l_code/reinforcement",
                      sprintf("l_code_%s_%s.json", base_id,
                              sub("_.*$", "", tab[n == max(tab[n <= S$used]$n)]$code[1])))
    .LD <- if (file.exists(.lcp)) tryCatch(fromJSON(.lcp, simplifyVector = TRUE),
                                           error = function(e) NULL) else NULL
    .items <- character(0)
    if (!is.null(.LD)) {
      if (nzchar(as.character(.LD$mechanism %||% "")))
        .items <- c(.items, paste0("기전: ", as.character(.LD$mechanism)))
      .na <- .LD$next_block_actions
      if (!is.null(.na) && length(.na)) {
        .at <- if (is.data.frame(.na)) as.character(.na$action) else
               vapply(.na, function(x) as.character(x$action %||% "")[1], character(1))
        .items <- c(.items, paste0("다음 블록 처방: ", paste(.at, collapse = " / ")))
      }
      .av <- .LD$avoid
      if (!is.null(.av) && length(.av))
        .items <- c(.items, paste0("쓰지 말 것: ", paste(as.character(unlist(.av)), collapse = " / ")))
      if (nzchar(as.character(.LD$prior_action_status %||% "")))
        .items <- c(.items, paste0("앞 처방 집행: ", as.character(.LD$prior_action_status)))
    }
    .learn_sec <- if (length(.items)) list(type = "bullet", emoji = "\U0001F9E0",
      heading = "이번 블록에서 배운 것", items = .items) else NULL
  }

  secs <- list(
    list(type = "bullet", emoji = "\U0001F3AF", heading = "현재 리서치 상황",
         items = c("단계: 1계층 강화 프로세스 — 무인 규칙 러너",
                   sprintf("대상: %s · 기저 등급 %s", .rf_target_label(S$entry), S$entry$base_grade %||% "F"),
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
    # ★승자 셀의 전체 지표 — 계약 산출물 읽기 전용(손계산 금지).
    #   산출물 경로가 없는 예전 entry 는 조용히 건너뛴다(NULL → 섹션 미추가).
    if (!is.null(.win_dir) && length(.win_kv))
      list(type = "kv", emoji = "\U0001F4C8",
           heading = sprintf("승자 셀 성과 요약 (%s)", best$code),
           kv = .win_kv) else NULL,
    .learn_sec,
    # ★"무엇을 강화했나" — 순위표만으로는 **무엇 위에 무엇을 얹었는지**가 안 읽힌다
    #   (도훈 2026-08-31 "무엇을 강화했나 파트 설명을 좀 더"). 네 줄을 먼저 세운다:
    #   ①기저(무엇 위에) ②컴포짓 비율(희석의 크기) ③승계 구성과 그 성능(=이번 기준선)
    #   ④이번 블록이 만진 축. 그 다음에야 순위가 뜻을 갖는다 — 기준선 대비 증감으로 읽힌다.
    list(type = "bullet", emoji = "\U0001F527", heading = "무엇을 강화했나",
         items = { dsc  <- rf_cell_desc(base_id)
                   # ★순위는 **이번 블록** 칸으로 한정한다. 전체 정렬로 뽑으면 그 블록 성적이
                   #   나쁠 때 지난 블록 칸이 상위를 차지해, 블록 완료 보고가 지난 얘기를 한다
                   #   (2026-08-31 실측: B2 다섯 칸이 전부 음수라 B2 메시지의 순위 4개 중 3개가
                   #   B1 칸이었고 "이번 축" 도 B1 로 표시됐다). 전체 최고는 [핵심 수치]가 준다.
                   # ★검사 이음매: QVEST_RF_FORCE_BLOCK 이 있으면 그 블록을 렌더한다.
                   #   평시엔 빈 문자열이라 아무 영향이 없다. 이게 없으면 검사가 각 entry 의
                   #   마지막 블록밖에 못 봐서, 나머지 블록의 서술 붕괴가 계속 새 나간다
                   #   (2026-09-03: B5 -> B4 -> B1 순으로 세 번 다 안 보는 블록에서 났다).
                   .fb <- Sys.getenv("QVEST_RF_FORCE_BLOCK", "")
                   .curblk <- if (nzchar(.fb)) .fb else { .m <- tab[n <= S$used]
                                if (nrow(.m)) sub("_.*$", "", .m[which.max(n)]$code) else NA_character_ }
                   .inblk <- if (!is.na(.curblk)) tab[grepl(paste0("^", .curblk, "_"), code)] else tab[0]
                   ord  <- (if (nrow(.inblk)) .inblk else tab)[order(-replace(port_t, !is.finite(port_t), -Inf))]
                   .cut <- function(x) substr(x, 1, 78)
                   EN   <- S$entry
                   cy   <- EN$carry
                   .cb  <- if (!is.null(cy)) suppressWarnings(as.numeric(EN$parent$best_port_t %||% NA)) else NA_real_
                   # 제목은 58자까지 오는데 접미(승격 n대)까지 붙으면 80자를 넘어 꼬리가 잘린다.
                   # 이 줄은 "무엇 위에 얹었나" 만 말하면 되므로 제목을 더 짧게 자른다.
                   it <- .cut(sprintf("기저: %s 의 충실구현 신호", substr(.rf_target_label(EN), 1, 56)))
                   # 승계 구성 + 기준선. 최초 entry 는 승계가 없다 — 그 사실을 적는다.
                   if (!is.null(cy)) {
                     .fs <- paste(vapply(cy$factors %||% list(), .rf_f2, character(1)), collapse = " + ")
                     if (!nzchar(.fs)) .fs <- "없음"
                     it <- c(it, .cut(sprintf("승계 구성: %s | %s | %s",
                                              .fs, .rf_wt(cy$weighting), .rf_un(cy$universe))),
                                 .cut(.rf_mix(length(cy$factors %||% list()))))
                     if (is.finite(.cb)) it <- c(it,
                       .cut(sprintf("기준선 t %.2f — 이번 칸들은 이걸 넘어야 개선이다", .cb)))
                   } else it <- c(it, "승계: 없음(최초 강화) — 기준선은 기저 신호 자신")
                   # ★블록 누적 (2026-09-04) — 이제 각 블록은 **지금까지 최고 구성** 위에 선다.
                   #   구판은 B1 승자만 물어서, 순서가 적응하면 앞 블록 승자가 버려졌다.
                   #   그 사실이 보고에 없으면 "무엇 위에 얹었나" 가 실제와 다르다.
                   .bst <- ord[0]
                   { .m2 <- tab[n <= S$used & is.finite(port_t)]
                     if (nrow(.m2)) .bst <- .m2[which.max(port_t)] }
                   if (nrow(.bst)) {
                     .bsp <- tryCatch({ .a <- Filter(function(x)
                         identical(as.integer(x$n %||% -1L), as.integer(.bst$n)), EN$attempts)
                       if (length(.a)) .a[[1]]$essence$spec else NULL }, error = function(e) NULL)
                     .bd  <- if (!is.null(.bsp) && nzchar(.bsp) && file.exists(.bsp))
                               tryCatch(fromJSON(.bsp, simplifyVector = FALSE), error = function(e) NULL) else NULL
                     it <- c(it, .cut(sprintf("누적 바닥: %s (t %.2f) — 이 구성 위에 이번 축만 얹는다",
                                              .bst$code, .bst$port_t)))
                     if (!is.null(.bd))
                       it <- c(it, .cut(sprintf("  = %s | %s | %s%s",
                         paste(vapply(.rp_all_factors(.bd), .rf_f2, character(1)), collapse = "+"),
                         .rf_wt(.bd$weighting), .rf_un(.bd$universe),
                         { .o <- .rf_ov(.bd$overlay); if (is.na(.o)) "" else paste0(" | ", .o) })))
                   }
                   .blk <- if (!is.na(.curblk)) .curblk else sub("_.*$", "", ord[1]$code)
                   it <- c(it, .cut(sprintf("이번 축: %s", switch(.blk,
                     "B1" = "B1 멀티팩터 — 기저에 팩터 1종을 등가중으로 더한다",
                     "B2" = "B2 비중방법론 — 종목 선정은 그대로, 비중 산식만 바꾼다",
                     "B3" = "B3 유니버스 — 신호는 그대로, 후보 집합을 좁힌다",
                     "B4" = "B4 결합 — 앞 승자를 합치고 하나씩 빼서(LOO) 기여를 가른다",
                     "B5" = "B5 리스크 오버레이 — 최고 구성 위에 노출 스케일만 얹는다",
                     sprintf("%s 축", .blk)))))
                   k <- min(4L, nrow(ord))
                   # ★순위 줄은 **그 칸이 바꾼 축**만 적는다. 전 축을 쓰면 승계와 겹치는
                   #   부분(비중·유니버스)이 자리를 다 먹고 등급·기준선 대비가 80자에서 잘린다
                   #   — 정작 판단에 쓰이는 두 값이 사라진다(2026-08-31 미리보기에서 적발).
                   # ★서술의 기준은 **함께 순위에 오른 칸들**이다 (2026-09-03 도훈 3차 적발).
                   #   구판은 carry 라는 고정 기준으로만 뺐다. 그래서 ①carry 가 없으면(최초 강화)
                   #   전문을 그대로 자르고 ②B1 처럼 칸들이 팩터를 **누적**하면 공통 접두가 길어져
                   #   앞에서 48자를 자르는 순간 1~4위가 글자까지 같아졌다(실측 nchar 62/94/142/194/238,
                   #   구분자는 전부 문자열 **끝**에 있었다). 기준을 블록 공통분으로 옮기면
                   #   남는 것이 곧 그 칸을 가르는 값이다.
                   .prs <- lapply(ord$code, function(cd) {
                     f <- dsc[[cd]] %||% ""
                     p <- strsplit(f, " | ", fixed = TRUE)[[1]]
                     if (length(p) %in% c(3L, 4L)) p else NULL })
                   .prs <- Filter(Negate(is.null), .prs)
                   .allsame <- function(j) length(unique(vapply(.prs, function(p) p[j], character(1)))) <= 1L
                   .blkcom <- if (length(.prs) >= 2L)
                     Reduce(intersect, lapply(.prs, function(p) trimws(strsplit(p[1], "+", fixed = TRUE)[[1]])))
                     else character(0)
                   .wt_same <- length(.prs) >= 2L && .allsame(2L)
                   .un_same <- length(.prs) >= 2L && .allsame(3L)
                   #' 팩터 추가분을 48자 안에서 **구분되게** 적는다. 누적형이면 항목을 다 쓰면
                   #' 또 앞이 겹치므로, 앞머리에 개수를 세우고 마지막(가장 최근 추가)을 붙인다.
                   .addtxt <- function(add) {
                     if (!length(add)) return(character(0))
                     j <- paste(add, collapse = "+")
                     # 개수를 항상 앞세운다 — B1 처럼 칸이 누적형이면 개수가 사다리를 읽게 한다.
                     if (nchar(j) <= 38L) return(sprintf("%d종 · %s", length(add), j))
                     sprintf("%d종 · 막 %s", length(add), utils::tail(add, 1L))
                   }
                   .delta_of <- function(code) {
                     # ★결합 칸은 부분집합이 곧 처치다 — 축 차집합 경로를 타지 않는다.
                     if (grepl("^B4_", code)) {
                       .z <- .rf_combo(code)
                       if (!is.na(.z)) return(substr(.z, 1, 48))
                     }
                     full <- dsc[[code]] %||% "격자 밖"
                     pr <- strsplit(full, " | ", fixed = TRUE)[[1]]
                     # 3축(팩터·비중·유니버스) 또는 4축(+오버레이). 4축은 B5 처럼
                     # 오버레이만 다른 칸을 가르는 유일한 값이라 반드시 살려야 한다.
                     if (!length(pr) %in% c(3L, 4L)) return(substr(full, 1, 48))
                     .ov4 <- if (length(pr) == 4L) pr[4] else NA_character_
                     # 정규식 대신 분리·차집합 — 팩터 이름에 정규식 메타문자가 섞이면
                     # 접두 제거가 조용히 빗나간다(2026-08-31: 이스케이프로 파싱 실패).
                     cfs <- if (!is.null(cy)) trimws(vapply(cy$factors %||% list(), .rf_f2, character(1)))
                            else character(0)
                     fs  <- trimws(strsplit(pr[1], "+", fixed = TRUE)[[1]])
                     ch  <- .addtxt(setdiff(fs, union(cfs, .blkcom)))
                     if (!is.null(cy)) {
                       if (!identical(pr[2], .rf_wt(cy$weighting))) ch <- c(ch, pr[2])
                       if (!identical(pr[3], .rf_un(cy$universe)))  ch <- c(ch, pr[3])
                       .cov <- .rf_ov(cy$overlay)
                       if (!is.na(.ov4) && !identical(.ov4, .cov)) ch <- c(ch, .ov4)
                     } else {
                       # carry 가 없으면 블록 안에서 **갈리는** 축만 적는다 —
                       # 모든 칸이 공유하는 값은 매 줄에 써봐야 구분에 기여하지 않는다.
                       if (!.wt_same) ch <- c(ch, pr[2])
                       if (!.un_same) ch <- c(ch, pr[3])
                       if (!is.na(.ov4)) ch <- c(ch, .ov4)
                     }
                     if (!length(ch)) return(if (is.null(cy)) "이 블록의 공통 기저" else "승계와 동일")
                     substr(paste(ch, collapse = " · "), 1, 48)
                   }
                   # ★칸별 미달 폭은 적지 않는다(도훈 2026-08-31). 기준선은 위에 한 번 서 있고
                   #   각 칸의 t 가 옆에 있으니 차이는 읽는 사람이 본다 — 줄마다 반복하면 소음이다.
                   #   그 자리를 라벨에 준다(무엇을 바꿨는지가 실제로 궁금한 값이다).
                   it <- c(it, vapply(seq_len(k), function(i2) {
                     r <- ord[i2]
                     .cut(sprintf("%d위 %s %s · t %.2f · %s",
                                  i2, r$code, .delta_of(r$code), r$port_t, r$grade))
                   }, character(1)))
                   # 미측정 칸은 왜 안 쟀는지 적는다 — 침묵하면 "재봤는데 나빴다" 로 읽힌다
                   # 미결도 이번 블록 것을 먼저 — 지난 블록 미결이 자리를 먹으면 안 된다
                   .tm <- Filter(function(a) isTRUE(a$terminal), EN$attempts %||% list())
                   if (!is.na(.curblk) && length(.tm)) {
                     .own <- Filter(function(a) identical(sub("_.*$", "", .rf_cellcode_of(a) %||% ""), .curblk), .tm)
                     if (length(.own)) .tm <- .own
                   }
                   # 사유의 앞머리(무처치 / 구조적 미결)가 핵심이다 — 그걸 지우면 왜 안 쟀는지가 없다
                   if (length(.tm)) it <- c(it, vapply(utils::head(.tm, 2), function(a) {
                     rs <- a$terminal_reason %||% "사유 미기록"
                     rs <- if (grepl("^무처치", rs)) "carry 와 동일 — 처치 미전달로 미측정"
                           else if (grepl("^구조적 미결", rs)) "구조적 미결 — 이 기저에서 전달 불가"
                           else substr(rs, 1, 44)
                     .cut(sprintf("미결 %s — %s", .rf_cellcode_of(a) %||% paste0("n", a$n), rs))
                   }, character(1)))
                   it }),

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
                sprintf("%d칸 소진 시 큐 다음 논문 착수 요청이 발송됩니다", S$maxa))))
  # ★NULL 섹션 제거 — 승자 산출물이 없는 예전 entry 는 그 칸이 NULL 로 남는다.
  secs <- Filter(Negate(is.null), secs)
  .sent <- tg_agent_brief(agent = "AlphaSearch", title = ttl, sections = secs, charts = ch)
  # ★승자 셀의 [팩터 분석] — FF3/FF5/Carhart + Fama-MacBeth
  if (!is.null(.win_dir) &&
      (file.exists(file.path(.win_dir, "analysis_multifactor.csv")) ||
       file.exists(file.path(.win_dir, "analysis_fmb_summary.csv"))))
    tryCatch(tg_pass_analysis(sprintf("%s %s", base_id, best$code), .win_dir),
             error = function(e) cat("[rf_notify] 팩터분석 발송 실패:", conditionMessage(e), "\n"))
  # ★발송 결과를 그대로 돌려준다 — 호출자(러너)가 "보냈다" 를 지어내지 않게.
  invisible(isTRUE(.sent$ok %||% TRUE))
}
