##=============================================================================
## style_brief_lib.R — 스타일 국면 브리핑 표시층 (FF5 + 스마트베타) · 2026-09-24 도훈 지시
##   "스타일 국면 브리핑 26년 8월 기준으로 고정된 부분 수정해줘"
##
## 결함: 브리핑의 제목·'최근 12개월 평균'·국면 판독·부활 워치·차트가 월간 파일의 마지막
##   **완결월**(ym 2026-08)에 묶여 9월 한 달 내내 같은 값이 발송됐다. 진행월 MTD 는 별도 절로만 붙었다.
## 수리: 12개월 창 = **완결 11개월 + 진행월 MTD** — 월평균 환산 = (11개월 합 + MTD) / 12.
##   FF5 5팩터 · 스마트베타 7스타일이 이 파일의 sw_window12() **하나**를 쓴다(브리핑·차트 공용).
##   진행월 MTD 가 없거나 낡았거나(as_of 가 완결월 말 이전·같음) 불연속이면 완결 12개월로 폴백하고
##   라벨·제목에 그 사유를 적는다(침묵 폴백 금지).
## ★표시층 전용 — 월간 파일(ff5_kr_monthly / smartbeta_kr_monthly)은 **완결월만** 발행하는 트래커
##   규약 불변(ff5_kr_tracker.R §1 · smartbeta_kr_tracker.R §3 '부분월 발행 오염' 가드). 진행월은 여기서만 합친다.
## ★PIT: 진행월 MTD = 트래커가 as_of(직전 영업일)까지의 확정 종가로 만든 값(신호 = 직전 월말).
##   as_of 가 오늘 이후(미래)이거나, 오늘이면서 KST 16시 전(장중 미확정 봉)이면 버린다.
## 라벨: diagnostic_monitoring — 시장 리뷰 전용(전략/자본 인용 금지).
## 검사: 08_Tests/ops/test_style_brief_mtd_window.R (양성 대조 + 위반 주입).
##=============================================================================

.SW_FF5 <- c("MKT", "SMB", "HML", "RMW", "CMA")
.SW_SB  <- c("VAL", "QUAL", "MOM", "LOWVOL", "SIZE", "DIV", "EREV")
.SW_SB_KO <- c(VAL = "가치포워드", QUAL = "퀄리티", MOM = "모멘텀", LOWVOL = "저변동성",
               SIZE = "소형주", DIV = "고배당", EREV = "이익전망수정")
.SW_SB_BETA_KO <- c(VAL = "가치", QUAL = "퀄리티", MOM = "모멘텀", LOWVOL = "저변동성",
                    SIZE = "소형주", DIV = "고배당", EREV = "이익전망수정")
.SW_IDX_KO <- c(KOSPI200 = "코스피200", KOSDAQ150 = "코스닥150", KOSPI = "코스피", KOSDAQ = "코스닥")
.SW_TITLE_HEAD <- "스타일 국면 브리핑 — FF5 + 스마트베타"
.SW_CONFIRM_HOUR_KST <- 16L      # 장 마감(15:30) 후 확정 — 그 전의 '오늘' as_of 는 장중 봉
.SW_REASON_KO <- c(absent = "진행월 MTD 없음", stale = "진행월 MTD 낡음", gap = "진행월 MTD 불연속(완결월 결손)",
                   inconsistent = "진행월 MTD 라벨 불일치", future = "진행월 MTD 미래 날짜",
                   intraday = "진행월 MTD 장중 미확정", short = "완결월 표본 부족")

## 월 수익률 % 표기 — 도훈 지시 07-18 규약 그대로(브리핑 fmt 원형)
sw_fmt <- function(v) if (length(v) == 0L || is.na(v)) "NA" else sprintf("%+.2f%%", v * 100)

sw_next_ym <- function(ym) format(seq(as.Date(paste0(ym, "-01")), by = "1 month", length.out = 2L)[2L], "%Y-%m")

sw_read_json <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::fromJSON(path), error = function(e) NULL)
}

## 진행월 MTD 판정 — ok=TRUE 일 때만 창에 합친다. reason ∈ names(.SW_REASON_KO) ∪ "ok"
sw_mtd_state <- function(mtd, last_ym, now = Sys.time(), tz = "Asia/Seoul",
                         confirm_hour = .SW_CONFIRM_HOUR_KST) {
  mk <- function(ok, reason, a = as.Date(NA), nd = NA_integer_)
    list(ok = ok, reason = reason, as_of = a, n_days = nd, last_ym = last_ym,
         mtd_ym = if (is.na(a)) NA_character_ else format(a, "%Y-%m"))
  ## [[ ]] = 정확 일치(리스트 $ 는 부분 일치 — 키 접두만 같은 항목을 집을 수 있다)
  if (is.null(mtd) || !is.list(mtd) || is.null(mtd[["as_of"]]) || length(mtd[["as_of"]]) != 1L) return(mk(FALSE, "absent"))
  a <- suppressWarnings(tryCatch(as.Date(as.character(mtd[["as_of"]])), error = function(e) as.Date(NA)))
  if (is.na(a)) return(mk(FALSE, "absent"))
  nd <- if (is.null(mtd[["n_days"]]) || length(mtd[["n_days"]]) != 1L) NA_integer_ else suppressWarnings(as.integer(mtd[["n_days"]]))
  mym <- format(a, "%Y-%m")
  if (!is.null(mtd[["ym"]]) && length(mtd[["ym"]]) == 1L && !identical(as.character(mtd[["ym"]]), mym))
    return(mk(FALSE, "inconsistent", a, nd))
  if (is.na(last_ym)) return(mk(FALSE, "short", a, nd))
  if (mym <= last_ym) return(mk(FALSE, "stale", a, nd))                 # as_of 가 완결월 말 이전(·같음)
  if (!identical(mym, sw_next_ym(last_ym))) return(mk(FALSE, "gap", a, nd))   # 사이에 빈 완결월
  today <- as.Date(format(now, "%Y-%m-%d", tz = tz))
  if (a > today) return(mk(FALSE, "future", a, nd))
  if (a == today && as.integer(format(now, "%H", tz = tz)) < confirm_hour) return(mk(FALSE, "intraday", a, nd))
  mk(TRUE, "ok", a, nd)
}

sw_reason_ko <- function(st) {
  r <- unname(.SW_REASON_KO[st$reason])
  if (is.na(r)) r <- st$reason
  if (st$reason %in% c("stale", "future", "intraday", "gap") && !is.na(st$as_of)) r <- sprintf("%s(as_of %s)", r, format(st$as_of))
  r
}

## ★12개월 창 (FF5·스마트베타 공용 · 브리핑·차트 공용) — 완결 (n-1)개월 + 진행월 MTD, 월평균 = 합 / n.
##   MTD 판정 불가 → 완결 n개월(폴백 사유는 label/short/state$reason).
##   결측: 열별로 관측된 값만 평균(분모 = 관측 수) — 결측이 없으면 정확히 (11개월 합 + MTD) / 12.
sw_window12 <- function(monthly, cols, mtd, now = Sys.time(), n = 12L) {
  m <- as.data.frame(monthly)
  if (!"ym" %in% names(m)) stop("sw_window12: monthly 에 ym 열이 없다")
  cols <- intersect(cols, names(m))
  m <- m[order(m$ym), c("ym", cols), drop = FALSE]
  last_ym <- if (nrow(m)) max(m$ym) else NA_character_
  st <- sw_mtd_state(mtd, last_ym, now)
  if (isTRUE(st$ok) && nrow(m) < n - 1L) { st$ok <- FALSE; st$reason <- "short" }   # 완결 11개월도 없으면 창 불성립
  use_mtd <- isTRUE(st$ok)
  base <- utils::tail(m, if (use_mtd) n - 1L else n)
  mv <- NULL
  if (use_mtd) mv <- vapply(cols, function(cc) { x <- mtd[[cc]]
    if (is.null(x) || length(x) != 1L || is.na(x)) NA_real_ else as.numeric(x) }, numeric(1))
  vals <- vapply(cols, function(cc) {
    v <- c(base[[cc]], if (use_mtd) mv[[cc]])
    if (all(is.na(v))) NA_real_ else sum(v, na.rm = TRUE) / sum(!is.na(v))
  }, numeric(1))
  need <- if (use_mtd) n - 1L else n
  if (nrow(base) < need) vals[] <- NA_real_
  mmdd <- if (use_mtd) format(st$as_of, "%m-%d") else NA_character_
  label <- if (use_mtd) {
    if (is.na(st$n_days)) sprintf("최근 12개월(진행월 MTD 포함, ~%s)", mmdd)
    else sprintf("최근 12개월(진행월 MTD %d거래일 포함, ~%s)", st$n_days, mmdd)
  } else if (nrow(base)) {
    sprintf("최근 12개월(완결 %s~%s · %s)", base$ym[1L], base$ym[nrow(base)], sw_reason_ko(st))
  } else sprintf("최근 12개월(%s)", sw_reason_ko(st))
  list(values = vals, mode = if (use_mtd) "mtd" else "complete", state = st, last_ym = last_ym,
       months = c(base$ym, if (use_mtd) sprintf("%s(MTD)", st$mtd_ym)), n = n,
       mtd_values = mv, label = label,
       short = if (use_mtd) "12개월+MTD" else "12개월(완결)",   # 국면 판독 줄 표기(한 줄 ≤80자 규율)
       mmdd = mmdd)
}

## 제목 — 기준일 = MTD as_of(직전 영업일) · 폴백이면 완결월 기준 + 사유
sw_brief_title <- function(w) {
  if (identical(w$mode, "mtd"))
    sprintf("%s (%s 기준 · 완결월 %s)", .SW_TITLE_HEAD, format(w$state$as_of), w$last_ym)
  else sprintf("%s (완결월 %s 기준 · %s)", .SW_TITLE_HEAD, w$last_ym, sw_reason_ko(w$state))
}

## 브리핑 조립 — ff5_brief_send.R 가 이 함수의 산출을 그대로 발송(또는 드라이런)한다.
##   입력은 전부 인자(파일 I/O 0) — 검사가 운영 코드 그 자체를 합성 입력으로 돌린다.
sw_compose_brief <- function(FF, SB = NULL, mtd5 = NULL, sbm = NULL, ib = NULL, now = Sys.time()) {
  fmt <- sw_fmt
  pos <- function(x) length(x) == 1L && !is.na(x) && x > 0
  side <- function(x, neg, posl) if (length(x) != 1L || is.na(x)) "?" else if (x < 0) neg else posl
  FF <- as.data.frame(FF); FF <- FF[order(FF$ym), , drop = FALSE]
  L <- FF[nrow(FF), , drop = FALSE]
  wf <- sw_window12(FF, .SW_FF5, mtd5, now)
  r5 <- wf$values
  mtd_ok <- identical(wf$mode, "mtd")
  tag <- wf$short
  kv5 <- function(v) list("시장초과 MKT" = fmt(v[["MKT"]]), "소형-대형 SMB" = fmt(v[["SMB"]]),
                          "가치-성장 HML" = fmt(v[["HML"]]), "수익성 RMW" = fmt(v[["RMW"]]),
                          "투자보수 CMA" = fmt(v[["CMA"]]))
  lv <- vapply(.SW_FF5, function(cc) if (cc %in% names(L)) as.numeric(L[[cc]]) else NA_real_, numeric(1))

  regime_line <- sprintf("%s 주도 / %s 우위 / 퀄리티 %s (%s)", side(r5[["SMB"]], "대형", "소형"),
                         side(r5[["HML"]], "성장", "가치"),
                         if (is.na(r5[["RMW"]])) "?" else if (r5[["RMW"]] > 0) "강세" else "약세", wf$label)
  revive_fire <- pos(r5[["SMB"]]) && pos(r5[["HML"]])
  revive_watch <- if (revive_fire) sprintf("SMB·HML %s 동반 양전 — 소형/가치 반전 신호, 매장 팩터 un-bury 검토 발화", tag)
                  else sprintf("반전 신호 없음 (SMB·HML %s 동반 양전 시 발화)", tag)

  sections <- list(
    list(heading = sprintf("FF5 최근 완결월 (%s)", L$ym), type = "kv", kv = kv5(lv)),
    list(heading = sprintf("FF5 %s 평균", wf$label), type = "kv", kv = kv5(r5)))
  ## 진행월 MTD (직전영업일까지 — 도훈 지시 07-18) — 판정 통과분만(낡은 MTD 를 '진행월'로 싣지 않는다)
  if (mtd_ok)
    sections[[length(sections) + 1L]] <- list(
      heading = sprintf("진행월 MTD (직전영업일 %s, %s거래일)", format(wf$state$as_of),
                        if (is.na(wf$state$n_days)) "?" else as.character(wf$state$n_days)),
      type = "kv", kv = kv5(wf$mtd_values))
  charts <- "outputs/ff5_kr/charts/ff5_rolling12.png"

  ws <- NULL; wsc <- NULL; sb_line <- NULL; r12 <- NULL
  if (!is.null(SB) && nrow(SB) >= 11L) {
    SB <- as.data.frame(SB); SB <- SB[order(SB$ym), , drop = FALSE]
    sty <- intersect(.SW_SB, names(SB))
    ws <- sw_window12(SB, sty, sbm, now)
    wsc <- sw_window12(SB, sty, NULL, now)          # 완결 12개월 — MTD 부호반전 비교 기준(자기포함 회피)
    r12 <- ws$values
    if (length(r12) && any(!is.na(r12))) {
      kvl <- as.list(vapply(r12, fmt, character(1))); names(kvl) <- .SW_SB_KO[names(r12)]
      sections[[length(sections) + 1L]] <- list(heading = sprintf("스마트베타 %s 평균 초과수익", ws$label),
                                                type = "kv", kv = kvl)
      top <- names(r12)[which.max(r12)]; bot <- names(r12)[which.min(r12)]
      sb_line <- sprintf("스마트베타: %s 최강 / %s 최약 (%s 유니버스 대비)", .SW_SB_KO[top], .SW_SB_KO[bot], ws$label)
      ## v3 최근동향 차트 (도훈 지시): 정렬 막대 + 24개월 히트맵 (장기 소형패널은 rolling12 파일로 별도 보관)
      charts <- c(charts, "outputs/smartbeta_kr/charts/smartbeta_recent_bars.png",
                  "outputs/smartbeta_kr/charts/smartbeta_heatmap24.png")
    } else r12 <- NULL
  }
  ## 지수 팩터 민감도 (도훈 지시 07-18) — 창은 index_factor_beta.json 이 이미 '36개월+MTD' 로 동적
  bn <- .SW_IDX_KO
  if (!is.null(ib) && !is.null(ib$betas)) {
    items_ff <- tryCatch(vapply(names(bn), function(ix) { b <- ib$betas[[ix]]
      v <- c(SMB = b$SMB, HML = b$HML, RMW = b$RMW, CMA = b$CMA)
      tk <- vapply(names(v), function(f) sprintf("%s %+.2f", f, v[f]), character(1))
      tk[which.max(v)] <- sprintf("<b>%s</b>", tk[which.max(v)])   # 양수 최대 볼드 (도훈 07-18)
      sprintf("%s: %s (MKT %.2f)", bn[ix], paste(tk, collapse = " · "), b$MKT) }, character(1)),
      error = function(e) NULL)
    if (!is.null(items_ff)) {
      sections[[length(sections) + 1L]] <- list(
        heading = sprintf("지수 팩터 민감도 (FF5·%s)", if (is.null(ib$window)) "36개월" else ib$window),
        type = "bullet", items = unname(items_ff))
      charts <- c(charts, "outputs/ff5_kr/charts/index_factor_beta.png")
    }
    if (!is.null(ib$sb_betas)) {
      krs <- .SW_SB_BETA_KO
      items_sb <- tryCatch(vapply(names(bn), function(ix) { v <- unlist(ib$sb_betas[[ix]])
        ip <- which.max(v); im <- which.min(v)                 # 양수 최대(볼드) + 음수 최대 병기
        sprintf("%s: <b>%s %+.2f</b> · %s %+.2f", bn[ix],
                krs[names(v)[ip]], v[ip], krs[names(v)[im]], v[im]) }, character(1)),
        error = function(e) NULL)
      if (!is.null(items_sb)) {
        sections[[length(sections) + 1L]] <- list(heading = "지수 스마트베타 민감도 (양수최대·음수최대, 시장통제)",
                                                  type = "bullet", items = unname(items_sb))
        charts <- c(charts, "outputs/ff5_kr/charts/index_smartbeta_beta.png")
      }
    }
  }
  ## 국면 판독 v3 — 12개월 창 = 완결 11개월 + 진행월 MTD (폴백 시 완결 12개월 · 표기 = tag)
  jd <- sprintf("FF5 %s: %s 주도(SMB %s)·%s 우위(HML %s)·퀄리티 %s(RMW %s)", tag,
                side(r5[["SMB"]], "대형", "소형"), fmt(r5[["SMB"]]),
                side(r5[["HML"]], "성장", "가치"), fmt(r5[["HML"]]),
                if (pos(r5[["RMW"]])) "강세" else "약세", fmt(r5[["RMW"]]))
  if (!is.null(r12)) {
    top12 <- names(r12)[which.max(r12)]; bot12 <- names(r12)[which.min(r12)]
    jd <- c(jd, sprintf("스타일 %s: 최강 %s %s · 최약 %s %s", ws$short,
                        .SW_SB_KO[top12], fmt(r12[[top12]]), .SW_SB_KO[bot12], fmt(r12[[bot12]])))
    if (identical(ws$mode, "mtd")) {
      mv <- ws$mtd_values; rc <- wsc$values[names(mv)]
      if (any(!is.na(mv))) {
        topm <- names(mv)[which.max(mv)]
        flip <- names(mv)[!is.na(mv) & !is.na(rc) & sign(mv) != sign(rc) & abs(mv) > 0.02]
        fl_txt <- if (!length(flip)) "없음" else paste(head(.SW_SB_KO[flip], 3), collapse = "·")
        if (length(flip) > 3) fl_txt <- sprintf("%s 외%d", fl_txt, length(flip) - 3)
        jd <- c(jd, sprintf("진행월 MTD(~%s): 최강 %s %s · 완결 12개월 대비 부호반전 %d개(%s)",
                            ws$mmdd, .SW_SB_KO[topm], fmt(mv[[topm]]), length(flip), fl_txt))
      }
    }
    if (!is.null(ib) && !is.null(ib$sb_betas)) {
      bt <- tryCatch(vapply(names(bn), function(ix) as.numeric(unlist(ib$sb_betas[[ix]])[top12]), numeric(1)),
                     error = function(e) NULL)
      if (!is.null(bt) && any(!is.na(bt)))
        jd <- c(jd, sprintf("지수 함의: %s 국면 지속 시 %s 우위(β%+.1f)·%s 역풍(β%+.1f) — 반전 시 역전",
                            .SW_SB_KO[top12], bn[names(bn)[which.max(bt)]], max(bt, na.rm = TRUE),
                            bn[names(bn)[which.min(bt)]], min(bt, na.rm = TRUE)))
    }
  }
  early <- mtd_ok && pos(wf$mtd_values[["SMB"]]) && pos(wf$mtd_values[["HML"]])
  jd <- c(jd, if (revive_fire) sprintf("부활 워치: <b>발화</b> — SMB·HML %s 동반 양전(매장 팩터 un-bury 검토)", tag)
    else if (early) "부활 워치: <b>MTD 조기신호 점등</b> — 진행월 SMB·HML 양전(완결 시 발화 후보)"
    else sprintf("부활 워치: 반전 신호 없음(SMB·HML %s 동반 양전 시 발화)", tag))
  sections[[length(sections) + 1L]] <- list(heading = "국면 판독", type = "bullet", items = jd)

  list(title = sw_brief_title(wf), sections = sections, charts = charts,
       footer = "diagnostic_monitoring · 시장 리뷰 전용(전략/자본 인용 금지) · ff5_kr + smartbeta_kr",
       regime_line = regime_line, revive_watch = revive_watch, sb_line = sb_line,
       w_ff = wf, w_sb = ws, w_sb_complete = wsc)
}

## 드라이런 본문 — 제목·절·차트 목록(발송 없음). charts_root = 존재 확인 기준 디렉터리
sw_dryrun_lines <- function(out, charts_root = ".") {
  ln <- c(sprintf("TITLE: %s", out$title), "")
  for (i in seq_along(out$sections)) {
    s <- out$sections[[i]]
    ln <- c(ln, sprintf("[절 %d · %s] %s", i, s$type, s$heading))
    if (identical(s$type, "kv")) ln <- c(ln, sprintf("  %s: %s", names(s$kv), unlist(s$kv)))
    else if (identical(s$type, "bullet")) ln <- c(ln, sprintf("  - %s", s$items))
    else ln <- c(ln, sprintf("  %s", paste(unlist(s$body), collapse = " ")))
    ln <- c(ln, "")
  }
  ex <- file.exists(file.path(charts_root, out$charts))
  mt <- ifelse(ex, format(file.mtime(file.path(charts_root, out$charts)), "%Y-%m-%d %H:%M"), "-")
  ln <- c(ln, sprintf("CHARTS (%d/%d 존재 — 발송 대상은 존재분만):", sum(ex), length(ex)),
          sprintf("  %s [%s · %s]", out$charts, ifelse(ex, "존재", "부재"), mt), "",
          sprintf("FOOTER: %s", out$footer),
          sprintf("WINDOW FF5: mode=%s · %s · months=%s", out$w_ff$mode, out$w_ff$label,
                  paste(out$w_ff$months, collapse = ",")))
  if (!is.null(out$w_sb))
    ln <- c(ln, sprintf("WINDOW SB : mode=%s · %s · months=%s", out$w_sb$mode, out$w_sb$label,
                        paste(out$w_sb$months, collapse = ",")))
  c(ln, sprintf("regime_line: %s", out$regime_line), sprintf("revive_watch: %s", out$revive_watch),
    sprintf("sb_line: %s", if (is.null(out$sb_line)) "-" else out$sb_line))
}
