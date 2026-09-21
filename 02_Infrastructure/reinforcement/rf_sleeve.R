#==============================================================================
# rf_sleeve.R — B7 구조적 방어 슬리브 (도훈 지시 2026-09-21)
#
# 왜 이 축인가 (실측):
#   · 분모(MDD)를 치는 유일한 축이던 B5 오버레이는 137칸을 태우고 적대검증 **pass 0**
#     (fail 11 · not_candidate 31). 노출 타이밍 주장은 노출-짝지은 플라시보(T3)를 못 넘었다.
#   · 방어 팩터를 B1 복합점수에 얹는 방식은 **67칸 이미 시험**됐고 MDD 0.53~0.67 로 불변,
#     최고 Calmar 0.419. 점수 혼합은 알파를 희석할 뿐 보유 구조를 안 바꾼다.
#   · 그런데 `module_catalog.json::defensive_score` 를 보면 **B등급 ∧ 심층 capture <0.80 인
#     모듈이 89개**(최고 0.392) 실재한다 — 위기에 덜 깨지는 보유 구성은 존재한다.
#   ⇒ 비어 있는 자리 = **선정 축의 구조적 방어**. 보유 종목의 일부를 방어 슬리브에 내준다.
#
# ★설계 불변식 (이걸 깨면 B5 의 재림이 된다):
#   ① **분할 비율 k 는 정적이다.** 시점마다 k 를 바꾸면 그 순간 총노출 타이밍 주장이 되고
#      T3 플라시보에 똑같이 죽는다. k 는 전 기간 고정이고 k 자체가 시험 축이다.
#   ② 총노출은 건드리지 않는다 — Sigma w = 1 유지, 현금 없음. 바뀌는 건 **누구를 보유하는가** 뿐.
#   ③ |SEL| 은 n_max 로 보존된다. 슬리브는 25종 **안에서의 분할**이다(PIT 2-슬리브 조항과 정합).
#
# ★팩터 id 를 박지 않는다 — 선택은 규칙이 한다(`rf_sl_resolve`). 규칙은 등록부
#   `factor_evidence.json` 의 **측정된 ic_bad**(약세장 횡단면 IC)를 쓴다. 해석된 id 는 spec 에
#   기록돼 재현이 고정된다(규칙은 변해도 그 측정은 같은 팩터를 가리킨다).
#
# 공개: rf_sl_parse / rf_sl_resolve / rf_sl_select / rf_sl_turnover_overlap / rf_sl_report
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.RF_SL_KINDS <- c("factor_topk", "antidefense", "random_beta_matched")

#' 슬리브 규칙 파싱 — 미지원 종류/인자는 **조용히 무시하지 않고 멈춘다**
#'   (침묵 폴백은 '처치를 안 받은 칸'을 '처치를 받은 칸'으로 기록한다)
rf_sl_parse <- function(x) {
  if (is.null(x) || !length(x)) return(NULL)
  if (!is.list(x)) stop("[rf_sleeve] defense_sleeve 는 list 여야 한다")
  kind <- as.character(x$kind %||% "")
  if (!nzchar(kind)) return(NULL)
  if (!(kind %in% .RF_SL_KINDS))
    stop(sprintf("[rf_sleeve] 미지원 kind '%s' (지원: %s)", kind, paste(.RF_SL_KINDS, collapse = ", ")))
  k <- suppressWarnings(as.integer(x$k %||% NA_integer_))
  if (!is.finite(k) || k < 1L) stop("[rf_sleeve] k 는 1 이상 정수여야 한다")
  # ★factor_kind: 방어 팩터의 **원천**. 기본 "db"(팩터 DB · C15 경유). 엔진이 이미 지원하는
  #   다른 원천(예: 오프라인 price 팩터)도 그대로 쓸 수 있어야 한다 — 그래야 엔진 경유 검사가 선다.
  ok_args <- c("kind", "k", "select", "rank", "factor_id", "factor_kind", "beta_factor", "seed", "label", "basis")
  extra <- setdiff(names(x), ok_args)
  if (length(extra)) stop(sprintf("[rf_sleeve] 알 수 없는 인자: %s", paste(extra, collapse = ", ")))
  list(kind = kind, k = k,
       select = as.character(x$select %||% "ic_bad_rank"),
       rank = suppressWarnings(as.integer(x$rank %||% 1L)),
       factor_id = as.character(x$factor_id %||% ""),
       factor_kind = as.character(x$factor_kind %||% "db"),
       beta_factor = as.character(x$beta_factor %||% "D02_Beta"),
       seed = suppressWarnings(as.integer(x$seed %||% NA_integer_)),
       label = as.character(x$label %||% kind))
}

#' 규칙 → 방어 팩터 id. ★리터럴 금지: 등록부의 **측정값**으로 고른다.
#'   자격: 계열 ∈ {defense, risk} ∧ lifecycle active ∧ ic_bad 측정됨.
#'   정렬: ic_bad 내림차순(약세장 횡단면 IC 가 큰 순). rank 번째를 고른다.
#'   ⚠한계 명시: ic_bad 는 "약세장에서 종목을 잘 줄세운다" 이지 "상위 k종 슬리브가 덜 깨진다" 가
#'     아니다. 그 간극은 이 축의 **칸들이 직접 측정**한다(대조군 B7_40/41 이 귀속을 가른다).
rf_sl_resolve <- function(rule, root = Sys.getenv("QM_ROOT", ".")) {
  if (nzchar(rule$factor_id %||% "")) return(list(id = rule$factor_id, basis = "spec 고정"))
  if (!identical(rule$select, "ic_bad_rank"))
    stop(sprintf("[rf_sleeve] 미지원 select '%s'", rule$select))
  ev_p <- file.path(root, "06_Registry/factor_evidence.json")
  if (!file.exists(ev_p)) stop("[rf_sleeve] factor_evidence.json 부재 — 규칙이 소비할 등록부가 없다")
  EV <- fromJSON(ev_p, simplifyVector = FALSE)$factors
  cand <- data.table(
    id  = names(EV),
    cat = vapply(EV, function(e) as.character(e$category %||% ""), character(1)),
    lc  = vapply(EV, function(e) as.character(e$lifecycle_status %||% "active"), character(1)),
    ib  = vapply(EV, function(e) suppressWarnings(as.numeric(e$ic_bad %||% NA_real_)), numeric(1)),
    ig  = vapply(EV, function(e) suppressWarnings(as.numeric(e$ic_good %||% NA_real_)), numeric(1)))
  cand <- cand[cat %in% c("defense", "risk") & lc == "active" & is.finite(ib)]
  if (!nrow(cand)) stop("[rf_sleeve] 자격 팩터 0종 — 등록부 계열/측정 확인")
  setorder(cand, -ib)
  r <- max(1L, as.integer(rule$rank %||% 1L))
  if (r > nrow(cand)) stop(sprintf("[rf_sleeve] rank %d > 자격 팩터 %d종", r, nrow(cand)))
  list(id = cand$id[r], basis = sprintf("ic_bad_rank %d/%d · ic_bad %.4f (ic_good %.4f)",
                                        r, nrow(cand), cand$ib[r], cand$ig[r]))
}

#' 방어 슬리브 적용 — 알파 상위 (n_max-k) 종 + 방어 k 종.
#' @param PANEL 후보 패널 (Date,Ticker,Score + defcol[, betacol])
#' @param SEL   알파 선정 결과 (Date,Ticker,...) — |SEL| = n_max/Date
#' @param defcol 방어 팩터 값 컬럼명 · betacol 베타 컬럼명(대조군용)
#' ★핵심: 방어 k종은 **알파가 안 고른 이름 중에서** 고른다. 이미 고른 이름을 다시 세면
#'   보유가 그대로라 처치가 전달되지 않는다(그 경우는 아래 가드가 멈춘다).
rf_sl_select <- function(PANEL, SEL, rule, n_max, defcol, betacol = NULL) {
  if (is.null(rule)) return(SEL)
  stopifnot(is.data.table(PANEL), is.data.table(SEL))
  n_max <- as.integer(n_max); k <- as.integer(rule$k)
  if (k >= n_max) stop(sprintf("[rf_sleeve] k %d >= n_max %d — 알파 슬리브가 사라진다", k, n_max))
  if (!(defcol %in% names(PANEL))) stop("[rf_sleeve] 방어 팩터 컬럼 부재: ", defcol)

  n_alpha <- n_max - k
  A <- SEL[order(Date, -Score)][, head(.SD, n_alpha), by = Date]        # 알파 슬리브

  P <- PANEL[is.finite(get(defcol))]
  if (!nrow(P)) stop("[rf_sleeve] 방어 팩터가 전 시점 결측 — 처치 불가")
  P <- P[!A[, .(Date, Ticker)], on = c("Date", "Ticker")]               # 알파가 안 고른 이름만

  D <- switch(rule$kind,
    "factor_topk"  = P[order(Date, -get(defcol))][, head(.SD, k), by = Date],
    # ★부호 반전 대조. 알려진 퇴화: 방어 팩터가 알파 점수와 **강하게 역상관**이면
    #   "비선정 이름 중 방어 하위 k종" = "알파 n_alpha+1..n_max 위" 가 되어 기저 선정과 같아진다.
    #   그 경우 아래 처치 전달 가드가 멈춘다 — 통과시키면 '대조군을 쟀다'는 거짓 기록이 남는다.
    "antidefense"  = P[order(Date,  get(defcol))][, head(.SD, k), by = Date],
    "random_beta_matched" = {
      if (is.null(betacol) || !(betacol %in% names(P)))
        stop("[rf_sleeve] 베타매칭 대조에는 베타 컬럼이 필요하다: ", betacol %||% "NULL")
      # ★무신호 대조 — 방어 팩터가 고를 이름들과 **같은 베타 분포**에서 무작위로 뽑는다.
      #   "방어가 한 일" 과 "베타를 낮춘 일" 을 가르는 유일한 장치다.
      ref <- P[order(Date, -get(defcol))][, head(.SD, k), by = Date][
        , .(bmin = min(get(betacol), na.rm = TRUE), bmax = max(get(betacol), na.rm = TRUE)), by = Date]
      M <- merge(P, ref, by = "Date")
      M <- M[is.finite(get(betacol)) & get(betacol) >= bmin & get(betacol) <= bmax]
      sd <- rule$seed; if (!is.finite(sd)) sd <- 20260921L
      set.seed(sd)
      M[, .SD[sample(.N, min(k, .N))], by = Date]
    },
    stop("[rf_sleeve] kind 미지원: ", rule$kind))

  cols <- intersect(names(A), names(D))
  OUT <- rbind(A[, ..cols], D[, ..cols])
  setorder(OUT, Date, -Score)

  # ── 처치 전달 가드 — 보유가 알파 단독과 같으면 이 칸은 아무것도 재지 않는다 ──
  .key <- function(X) X[, .(s = paste(sort(as.character(Ticker)), collapse = "|")), by = Date]
  same <- merge(.key(SEL), .key(OUT), by = "Date")[, mean(s.x == s.y)]
  if (is.finite(same) && same > 0.99)
    stop(sprintf("[rf_sleeve] 처치 미전달 — 보유가 알파 단독과 %.1f%% 동일(방어 k종이 이미 알파 안에 있다)",
                 100 * same))
  OUT
}

#' 두 선정의 보유 겹침(진단) — 슬리브가 실제로 몇 %를 갈아끼웠나
rf_sl_turnover_overlap <- function(before, after) {
  if (!is.data.table(before) || !is.data.table(after)) return(NA_real_)
  B <- before[, .(t = list(as.character(Ticker))), by = Date]
  A <- after[,  .(t = list(as.character(Ticker))), by = Date]
  M <- merge(B, A, by = "Date")
  if (!nrow(M)) return(NA_real_)
  mean(vapply(seq_len(nrow(M)), function(i) {
    b <- M$t.x[[i]]; a <- M$t.y[[i]]
    length(intersect(b, a)) / max(1L, length(union(b, a)))
  }, numeric(1)))
}

rf_sl_report <- function(before, after, rule, fid, basis) {
  sprintf("defense_sleeve=%s | k=%d · 팩터 %s (%s) · 보유 겹침 %.1f%% · 종목수 %d→%d",
          rule$label %||% rule$kind, rule$k, fid, basis,
          100 * (rf_sl_turnover_overlap(before, after) %||% NA_real_),
          round(mean(before[, .N, by = Date]$N)), round(mean(after[, .N, by = Date]$N)))
}

cat("[rf_sleeve.R] Loaded — rf_sl_parse / rf_sl_resolve / rf_sl_select / rf_sl_turnover_overlap / rf_sl_report\n")
