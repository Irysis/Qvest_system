## rf_block_insights.R — 블록 텔레그램 '이번 배치에서 알게 된 것' 의 규칙 기반 생성기 (2026-09-04)
##
## 왜 새로 짰나 (도훈 지적 "내용이 너무 획일화"): 구판 rf_insights() 는 entry **전체** 표에 고정 규칙
##   5개를 대는 구조라 블록이 바뀌어도 같은 세 문장이 나왔다(칼마/요구 CAGR · OOS · A등급 0건).
##   실측(09-04 21:41 · 22:04 · 22:33 텔레그램): 세 블록의 이 섹션이 사실상 동일.
##
## 원칙: ① **이 블록**을 직전 최고(누적 기저)와 대조한다 ② 수치엔 이름을 붙인다 ③ 증거가 있는 절만
##   낸다(빈 절은 채우지 않는다 — 채움말이 획일화의 절반이었다) ④ LLM 없음 — 전부 계약 산출물의 재도출.
##
## 절(있을 때만): 판정 · 무엇이 갈랐나 · 위험·수익 교환 · 군집/단조 · 경계까지 · 앞 처방 대비 ·
##              미측정/강등 · 승격 사슬 · 라운드 전체
##
## 공개 함수: rf_block_insights(S, blk, root, parent_S)  → list(label = character lines)
##            rf_block_insights_body(S, root, force_block) → 텔레그램 text 본문(HTML) 또는 ""
suppressMessages({ library(data.table); library(jsonlite) })
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

.bi_esc <- function(x) { x <- as.character(x); x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE); gsub(">", "&gt;", x, fixed = TRUE) }
.bi_fin <- function(v) v[is.finite(v)]
.bi_pc  <- function(x) sprintf("%.1f%%", 100 * x)
.bi_pp  <- function(x) sprintf("%+.1f%%p", 100 * x)
.bi_blkname <- c(B1 = "멀티팩터", B2 = "비중방법론", B3 = "유니버스", B5 = "리스크오버레이", B4 = "결합")
.bi_axis    <- c(B1 = "팩터", B2 = "비중", B3 = "유니버스", B5 = "오버레이", B4 = "결합")

#' 셀 spec 파일 (러너와 같은 후보 경로 — 재구현이 아니라 같은 위치를 본다)
.bi_spec <- function(root, base_id, code) {
  for (f in c(file.path(root, ".cache/rf_parallel", sprintf("spec_%s__%s.json", code, substr(base_id, 1, 48))),
              file.path(root, ".cache", sprintf("rf_cell_spec_%s__%s.json", code, substr(base_id, 1, 48))))) {
    if (file.exists(f)) return(tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL))
  }
  NULL
}

#' 처치 문자열("팩터 | 비중 | 유니버스 | 오버레이")을 4칸으로 쪼갠다
.bi_parts <- function(s) {
  p <- trimws(strsplit(as.character(s %||% ""), " | ", fixed = TRUE)[[1]])
  length(p) <- 4L; p[is.na(p)] <- ""; p
}

#' 두 칸의 처치 차이 — 다른 칸만 "축: A → B"
.bi_diff <- function(da, db) {
  a <- .bi_parts(da); b <- .bi_parts(db)
  nm <- c("팩터", "비중", "유니버스", "오버레이")
  out <- character(0)
  for (k in 1:4) if (!identical(a[k], b[k]) && (nzchar(a[k]) || nzchar(b[k]))) {
    ## 라벨 헬퍼가 이미 "비중 …" "오버레이 …" 를 붙이므로 그 축은 접두를 뺀다(“비중 비중 cvar” 방지)
    pre <- if (k %in% c(2L, 4L) && (startsWith(a[k], nm[k]) || startsWith(b[k], nm[k]))) "" else paste0(nm[k], " ")
    out <- c(out, sprintf("%s%s → %s", pre, if (nzchar(a[k])) a[k] else "없음", if (nzchar(b[k])) b[k] else "없음"))
  }
  out
}

#' 가장 큰 '한 점' 군집 — PORT_t 폭 width 안에 드는 최대 부분집합
.bi_cluster <- function(pt, width = 0.15) {
  v <- sort(.bi_fin(pt)); if (length(v) < 3L) return(NULL)
  best <- NULL
  for (i in seq_along(v)) { j <- max(which(v <= v[i] + width)); k <- j - i + 1L
    if (is.null(best) || k > best$k) best <- list(k = k, lo = v[i], hi = v[j]) }
  best
}

#' 핵심: 한 블록의 절들
rf_block_insights <- function(S, blk, root, parent_S = NULL) {
  tab <- S$tab; E <- S$entry; base_id <- as.character(E$base_id %||% "")
  parts <- list()
  if (is.null(tab) || !nrow(tab) || is.na(blk) || !nzchar(blk)) return(parts)
  inblk <- tab[grepl(paste0("^", blk, "_"), code)]
  if (!nrow(inblk)) return(parts)
  fin_blk <- inblk[is.finite(port_t)]
  if (!nrow(fin_blk)) return(parts)
  desc <- tryCatch(rf_cell_desc(base_id), error = function(e) list())
  dtxt <- function(cd) as.character(desc[[cd]] %||% "")

  ## ── 기저(직전 최고): 이 블록 앞 칸들의 최고, 첫 블록이면 부모 승자 ──
  prior <- tab[n < min(inblk$n) & is.finite(port_t)]
  base <- NULL; base_from <- ""
  if (nrow(prior)) { base <- prior[which.max(port_t)]; base_from <- "직전 최고" }
  else if (!is.null(E$parent) && !is.null(parent_S) && nrow(parent_S$tab)) {
    pb <- parent_S$tab[is.finite(port_t)]
    if (nrow(pb)) { base <- pb[which.max(port_t)]; base_from <- "부모 승자" }
  }
  best  <- fin_blk[which.max(port_t)]
  worst <- fin_blk[which.min(port_t)]

  ## ── 1. 판정 ──
  rng_pt  <- max(fin_blk$port_t) - min(fin_blk$port_t)
  mdd_ok  <- .bi_fin(fin_blk$mdd); rng_mdd <- if (length(mdd_ok) >= 2) max(mdd_ok) - min(mdd_ok) else NA_real_
  axis_line <- if (is.finite(rng_mdd) && rng_pt >= 0.5 && rng_mdd < 0.06)
      sprintf("이 축은 초과수익을 움직이고 낙폭은 못 움직였다 (PORT_t 폭 %.2f · MDD 폭 %.1f%%p)", rng_pt, 100 * rng_mdd)
    else if (is.finite(rng_mdd) && rng_mdd >= 0.08 && rng_pt < 0.5)
      sprintf("이 축은 낙폭을 움직였고 초과수익은 거의 그대로다 (MDD 폭 %.1f%%p · PORT_t 폭 %.2f)", 100 * rng_mdd, rng_pt)
    else if (is.finite(rng_mdd) && rng_pt >= 0.5 && rng_mdd >= 0.08)
      sprintf("초과수익과 낙폭이 함께 움직였다 (PORT_t 폭 %.2f · MDD 폭 %.1f%%p)", rng_pt, 100 * rng_mdd)
    else sprintf("초과수익도 낙폭도 거의 안 움직였다 (PORT_t 폭 %.2f · MDD 폭 %s)", rng_pt,
                 if (is.finite(rng_mdd)) sprintf("%.1f%%p", 100 * rng_mdd) else "n/a")
  hd <- sprintf("%s %d칸 — 최고 %s PORT_t %.3f · Calmar %.3f · MDD %s",
                .bi_blkname[[blk]] %||% blk, nrow(inblk), best$code, best$port_t,
                best$calmar %||% NA_real_, if (is.finite(best$mdd)) .bi_pc(best$mdd) else "n/a")
  vs <- if (!is.null(base)) sprintf("%s %s(PORT_t %.3f) 대비 ΔPORT_t %+.3f · ΔCalmar %+.3f · ΔMDD %s → %s",
                base_from, base$code, base$port_t, best$port_t - base$port_t,
                (best$calmar %||% NA_real_) - (base$calmar %||% NA_real_),
                if (is.finite(best$mdd) && is.finite(base$mdd)) .bi_pp(best$mdd - base$mdd) else "n/a",
                if (best$port_t > base$port_t + 1e-9) "기저를 넘었다" else "기저를 못 넘었다")
        else "대조할 기저 없음(첫 블록 · 부모 없음)"
  parts[["판정"]] <- c(hd, vs, axis_line)

  ## ── 2. 무엇이 갈랐나 (최고 vs 최저 처치 차이) ──
  if (nrow(fin_blk) >= 2 && !identical(best$code, worst$code)) {
    dd <- .bi_diff(dtxt(worst$code), dtxt(best$code))
    l2 <- sprintf("최저 %s(PORT_t %.3f · MDD %s) → 최고 %s(PORT_t %.3f · MDD %s)",
                  worst$code, worst$port_t, if (is.finite(worst$mdd)) .bi_pc(worst$mdd) else "n/a",
                  best$code, best$port_t, if (is.finite(best$mdd)) .bi_pc(best$mdd) else "n/a")
    if (length(dd)) l2 <- c(l2, sprintf("갈린 처치: %s", paste(dd, collapse = " · ")))
    else l2 <- c(l2, "처치 기록으로는 두 칸이 같다 — 차이가 처치 밖(난수·창)에 있거나 기록이 비어 있다")
    parts[["무엇이 갈랐나"]] <- l2
  }

  ## ── 3. 위험·수익 교환 (기저 대비 각 칸) ──
  if (!is.null(base) && is.finite(base$mdd) && is.finite(base$calmar)) {
    sc <- fin_blk[is.finite(mdd) & is.finite(calmar)]
    if (nrow(sc)) {
      dPT <- sc$port_t - base$port_t; dM <- sc$mdd - base$mdd; dC <- sc$calmar - base$calmar
      scale_like <- dM < -0.02 & dPT < 0 & abs(dC) < 0.03
      real_risk  <- dM < -0.02 & dC > 0.03
      ret_only   <- dPT > 0.1 & dM >= -0.01
      l3 <- character(0)
      if (any(scale_like)) l3 <- c(l3, sprintf("노출 축소 서명 %d칸(%s) — 낙폭과 초과수익을 같은 비율로 깎아 Calmar 가 안 움직였다",
                                              sum(scale_like), paste(sc$code[scale_like], collapse = "·")))
      if (any(real_risk)) { i <- which(real_risk)[which.max(dC[real_risk])]
        l3 <- c(l3, sprintf("낙폭을 줄이면서 Calmar 를 올린 칸 %d개 — 최선 %s (MDD %s · ΔCalmar %+.3f)",
                            sum(real_risk), sc$code[i], .bi_pp(dM[i]), dC[i])) }
      if (any(ret_only)) l3 <- c(l3, sprintf("수익만 올린 칸 %d개(%s) — 낙폭은 그대로",
                                            sum(ret_only), paste(sc$code[ret_only], collapse = "·")))
      if (!length(l3)) l3 <- sprintf("기저 대비 어느 칸도 낙폭 2%%p 이상 줄이거나 PORT_t 0.1 이상 올리지 못했다 (ΔPORT_t %.3f~%.3f)",
                                     min(dPT), max(dPT))
      parts[["위험·수익 교환"]] <- l3
    }
  }

  ## ── 4. 군집·단조 ──
  l4 <- character(0)
  cl <- .bi_cluster(fin_blk$port_t)
  if (!is.null(cl) && cl$k >= 3L && cl$k >= ceiling(nrow(fin_blk) / 2)) {
    inset <- fin_blk[port_t >= cl$lo - 1e-9 & port_t <= cl$hi + 1e-9]
    ax <- switch(blk, B2 = 2L, B3 = 3L, B5 = 4L, 1L)
    trt <- unique(vapply(inset$code, function(cd) .bi_parts(dtxt(cd))[ax], character(1)))
    trt <- trt[nzchar(trt)]
    l4 <- c(l4, sprintf("%d칸이 PORT_t %.3f~%.3f 한 점(폭 %.2f) — 라벨은 %d개, 처치의 효과는 하나%s",
                        cl$k, cl$lo, cl$hi, cl$hi - cl$lo, length(trt),
                        if (length(trt) >= 2) sprintf(" (%s)", paste(utils::head(trt, 4), collapse = " / ")) else ""))
  }
  if (identical(blk, "B1") && nrow(fin_blk) >= 4) {
    nf <- vapply(fin_blk$code, function(cd) { f <- .bi_parts(dtxt(cd))[1]
      if (!nzchar(f) || grepl("없음", f)) 0L else length(strsplit(f, "+", fixed = TRUE)[[1]]) }, integer(1))
    if (length(unique(nf)) >= 3) { r <- suppressWarnings(stats::cor(nf, fin_blk$port_t, method = "spearman"))
      if (is.finite(r) && r <= -0.7) l4 <- c(l4, sprintf("팩터 수와 PORT_t 가 단조 역상관 (Spearman %.2f) — 결합이 더할수록 희석 (팩터 %d~%d종)", r, min(nf), max(nf)))
      if (is.finite(r) && r >= 0.7)  l4 <- c(l4, sprintf("팩터 수와 PORT_t 가 단조 양상관 (Spearman %.2f) — 아직 결합 여지가 남았다", r)) }
  }
  if (length(l4)) parts[["군집·단조"]] <- l4

  ## ── 5. 경계까지 (블록 최고 기준) ──
  l5 <- character(0)
  if (is.finite(best$port_t)) l5 <- c(l5, sprintf("PORT_t %.3f → 문턱 2.95 까지 %+.3f", best$port_t, 2.95 - best$port_t))
  if (is.finite(best$calmar) && is.finite(best$mdd) && is.finite(best$cagr))
    l5 <- c(l5, sprintf("Calmar %.3f → 문턱 0.64: MDD %s 를 유지하면 CAGR %.1f%% 가 필요하다 (현재 %s)",
                        best$calmar, .bi_pc(best$mdd), 100 * 0.64 * best$mdd, .bi_pc(best$cagr)))
  ## 롤링·방어 (권위 재측정 산출물 — 있을 때만)
  art <- tryCatch({ a <- Filter(function(x) identical(as.integer(x$n %||% -1L), as.integer(best$n)), E$attempts)
                    if (length(a)) as.character(a[[1]]$artifacts %||% "") else "" }, error = function(e) "")
  if (nzchar(art) && file.exists(file.path(art, "authoritative_remeasure.json"))) {
    A <- tryCatch(fromJSON(file.path(art, "authoritative_remeasure.json"), simplifyVector = TRUE), error = function(e) NULL)
    rg <- A$rolling_grade; ds <- A$defensive_score
    if (!is.null(rg) && identical(as.character(rg$status %||% ""), "ok")) {
      cur <- rg$current %||% list()
      l5 <- c(l5, sprintf("롤링 %d개월 창: 통과율 생애 %.0f%% · 최근 %.0f%% · 현재 창 Calmar %s · 회복→붕괴 %d회",
                          as.integer(rg$window_months %||% 36L), 100 * as.numeric(rg$pass_life %||% NA), 100 * as.numeric(rg$pass_recent %||% NA),
                          if (is.finite(as.numeric(cur$calmar %||% NA))) sprintf("%.2f", as.numeric(cur$calmar)) else "n/a",
                          as.integer(rg$prior_recoveries %||% 0L)))
    }
    if (!is.null(ds) && identical(as.character(ds$status %||% ""), "ok")) {
      dn <- ds$down %||% list()
      l5 <- c(l5, sprintf("벤치 하락월 %d개: 초과수익 %+.2f%%p · 적중 %.0f%% · 하방 포착 %.2f → 방어형 %s",
                          as.integer(dn$n %||% 0L), 100 * as.numeric(dn$excess %||% NA), 100 * as.numeric(dn$hit %||% NA),
                          as.numeric(dn$capture %||% NA), if (isTRUE(ds$defensive)) "예" else "아니오"))
    }
  }
  if (length(l5)) parts[["경계까지"]] <- l5

  ## ── 6. 앞 처방 대비 (설계가 있었던 블록만) ──
  st <- tryCatch({ suppressMessages(source(file.path(root, "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE))
                   rfbd_action_status(root, base_id, blk, E$attempts) }, error = function(e) NULL)
  if (!is.null(st) && !identical(as.character(st$status %||% "no_design"), "no_design")) {
    verdict <- if (!is.null(base)) (if (best$port_t > base$port_t + 1e-9) "지지(기저를 넘었다)" else "반증(기저를 못 넘었다)") else "대조 기저 없음"
    parts[["앞 처방 대비"]] <- c(sprintf("집행 %s — %s", as.character(st$status), .bi_esc(as.character(st$detail %||% ""))),
                                sprintf("처방의 기대 대비 결과: %s", verdict))
  }

  ## ── 7. 미측정·강등 ──
  l7 <- character(0)
  tm <- Filter(function(a) isTRUE(a$terminal) && grepl(paste0("^", blk, "_"), as.character(a$cell_code %||% "")), E$attempts %||% list())
  for (a in utils::head(tm, 3)) {
    rs <- as.character(a$terminal_reason %||% "사유 미기록")
    rs <- if (grepl("^무처치", rs)) "carry 와 동일 — 처치 미전달" else if (grepl("^구조적 미결", rs)) "구조적 미결 — 이 기저에서 전달 불가" else substr(rs, 1, 110)
    l7 <- c(l7, sprintf("미측정 %s — %s", as.character(a$cell_code), .bi_esc(rs)))
  }
  for (cd in inblk$code) { sp <- .bi_spec(root, base_id, cd)
    if (!is.null(sp$carry_degraded)) {
      .eq <- as.character(sp$carry_degraded$loo_equivalent %||% "")[1]   # B4 강등(2026-09-13) — '−비중' 칸과 동치면 명시
      l7 <- c(l7, sprintf("%s: 승계 비중 %s 이 이 유니버스에서 불가 — EW 로 강등해 측정 (블록 내 비교 시 비중이 다름)%s",
                          cd, .bi_esc(as.character(sp$carry_degraded$from %||% "?")),
                          if (!is.na(.eq) && nzchar(.eq)) sprintf(" · 구성 = %s(−비중 칸)과 동일", .bi_esc(.eq)) else "")) } }
  if (length(l7)) parts[["미측정·강등"]] <- l7

  ## ── 8. 승격 사슬 (부모가 있을 때) ──
  if (!is.null(E$parent) && !is.null(parent_S) && nrow(parent_S$tab)) {
    pt <- parent_S$tab[is.finite(port_t)]; pbest <- pt[which.max(port_t)]
    ebest <- tab[is.finite(port_t)][which.max(port_t)]
    l8 <- sprintf("부모 최고 %s PORT_t %.3f → 이 사슬(깊이 %s) 최고 %s %.3f — 다음 승격 조건 %s",
                  pbest$code, pbest$port_t, as.character(E$parent$depth %||% "?"), ebest$code, ebest$port_t,
                  if (ebest$port_t > pbest$port_t + 1e-9) "충족 중" else "미충족")
    b4 <- pt[grepl("^B4_", code)]
    if (nrow(b4) >= 2) {
      full <- b4[1]; lbl <- c("팩터", "비중", "유니버스", "오버레이"); neg <- character(0); this_ax <- .bi_axis[[blk]] %||% ""
      for (k in seq_along(lbl)) { r <- if (nrow(b4) >= k + 1L) b4[k + 1L] else NULL
        if (is.null(r) || !is.finite(r$port_t)) next
        d <- full$port_t - r$port_t
        if (d < 0) neg <- c(neg, sprintf("%s %+.3f", lbl[k], d))
        if (identical(lbl[k], this_ax) && !is.null(base))
          l8 <- c(l8, sprintf("부모 LOO 에서 %s 축은 %s(Δ%+.3f) — 이 블록에서는 기저 대비 %+.3f 로 %s",
                              lbl[k], if (d < 0) "순손실" else "기여", d, best$port_t - base$port_t,
                              if ((d < 0) == (best$port_t - base$port_t > 0)) "뒤집혔다" else "같은 방향이다")) }
      if (length(neg)) l8 <- c(l8, sprintf("부모 라운드 LOO 순손실 축: %s", paste(neg, collapse = " · ")))
    }
    parts[["승격 사슬"]] <- l8
  }

  ## (구판 rf_insights 의 entry 전체 규칙은 넣지 않는다 — 블록이 바뀌어도 같은 줄이 나와 획일화의 원천이었다)
  parts
}

#' 텔레그램 text 본문 — ▸ 라벨 + 줄, 절 사이 구분선. 절이 없으면 ""(호출자가 구판 폴백)
rf_block_insights_render <- function(parts, max_chars = Inf) {
  if (!length(parts)) return("")
  chunk <- function(nm) { ln <- parts[[nm]]; ln <- ln[nzchar(ln)]
    paste0("<b>▸ ", nm, "</b>\n", paste(ln, collapse = "\n\n")) }
  keep <- names(parts)
  ## ★글자 예산 (Telegram 4096자/메시지): 뒤 절부터 뺀다 — 절 순서가 곧 우선순위다
  repeat {
    body <- paste(vapply(keep, chunk, character(1)), collapse = "\n\n─────\n\n")
    if (nchar(gsub("</?b>", "", body)) <= max_chars || length(keep) <= 1L) return(body)
    keep <- keep[-length(keep)]
  }
}

#' 본문용 요약(판정 + 무엇이 갈랐나)과 후속 메시지용 전체판을 나눈다
rf_block_insights_split <- function(parts, short_max = 520L, full_max = 3600L) {
  if (!length(parts)) return(list(short = "", full = ""))
  sh <- parts[intersect(c("판정", "무엇이 갈랐나"), names(parts))]
  list(short = rf_block_insights_render(sh, short_max), full = rf_block_insights_render(parts, full_max),
       n_parts = length(parts))
}

#' 호출 편의: 현재 블록·부모 표를 스스로 구해 본문을 낸다
rf_block_insights_body <- function(S, root, force_block = Sys.getenv("QVEST_RF_FORCE_BLOCK", "")) {
  tab <- S$tab
  blk <- if (nzchar(force_block)) force_block else {
    m <- tab[n <= S$used]; if (nrow(m)) sub("_.*$", "", m[which.max(n)]$code) else NA_character_ }
  if (is.na(blk)) return("")
  pS <- NULL
  if (!is.null(S$entry$parent)) pS <- tryCatch(rf_notify_table(as.character(S$entry$parent$base_id)), error = function(e) NULL)
  rf_block_insights_render(rf_block_insights(S, blk, root, pS))
}

#' 현재 블록의 parts (notify 가 요약/전체 두 번 쓰기 위해)
rf_block_insights_parts <- function(S, root, force_block = Sys.getenv("QVEST_RF_FORCE_BLOCK", "")) {
  tab <- S$tab
  blk <- if (nzchar(force_block)) force_block else {
    m <- tab[n <= S$used]; if (nrow(m)) sub("_.*$", "", m[which.max(n)]$code) else NA_character_ }
  if (is.na(blk)) return(list())
  pS <- NULL
  if (!is.null(S$entry$parent)) pS <- tryCatch(rf_notify_table(as.character(S$entry$parent$base_id)), error = function(e) NULL)
  rf_block_insights(S, blk, root, pS)
}
