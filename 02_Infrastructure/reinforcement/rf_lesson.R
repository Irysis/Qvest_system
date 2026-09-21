#==============================================================================
# rf_lesson.R — 무인 셀의 **기전 서술** 교훈 생성 (v10.2 2026-09-03 · Phase 4)
#
# ★왜: 무인 레인의 교훈 269건 중 247건(92%)이 지표 되풀이였다
#   ("[무인 병렬 B1_1] Grade F · PORT_t -0.028 · SR 0.358 · ...").
#   essence 에 이미 있는 숫자를 문자열로 옮겨 적은 것이라 한계 정보량이 0이고,
#   그래서 rf_preflight 가 직전 교훈을 주입해도 읽을 재료가 없었다.
#
# ★LLM 을 쓰지 않는다 — 필요한 것은 전부 essence + carry 비교에서 결정론적으로 나온다.
#   ①5조건 중 무엇이 막았나 ②carry 대비 위험·수익이 어느 방향으로 얼마나 ③처치가 전달됐나
#
# 문턱 정본 = 02_Infrastructure/worktask/constraint_defaults.json::tier_graduation
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFL_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

.rfl_thresholds <- function(root = .RFL_ROOT()) {
  p <- file.path(root, "02_Infrastructure/worktask/constraint_defaults.json")
  g <- tryCatch(fromJSON(p, simplifyVector = FALSE)$tier_graduation, error = function(e) NULL)
  num <- function(x, d) { v <- suppressWarnings(as.numeric(x)); if (length(v) && is.finite(v)) v else d }
  list(port_t = num(g[["min_portfolio_alpha_t_nw"]], 2.95),
       oos    = num(g[["min_oos_retention"]],        0.70),
       sharpe = num(g[["grade_a_min_sharpe"]],       0.80),
       cagr   = num(g[["grade_a_min_cagr"]],         0.16),
       calmar = num(g[["min_calmar"]],               0.64))
}

#' 5조건 중 막은 것들 — 값/문턱을 함께 낸다(어느 축이 얼마나 모자란지가 기전이다)
rfl_binding <- function(es, root = .RFL_ROOT()) {
  th <- .rfl_thresholds(root)
  f <- function(k) suppressWarnings(as.numeric(es[[k]] %||% NA))
  z <- list(
    list(n = "port_t", v = f("port_t"),         t = th$port_t),
    list(n = "calmar", v = f("calmar"),         t = th$calmar),
    list(n = "sharpe", v = f("net_sharpe"),     t = th$sharpe),
    list(n = "cagr",   v = f("cagr"),           t = th$cagr),
    list(n = "oos",    v = f("oos_retention"),  t = th$oos))
  miss <- Filter(function(x) !is.finite(x$v) || x$v < x$t, z)
  list(n_met = length(z) - length(miss),
       text = if (!length(miss)) "5조건 전부 충족" else
         paste(vapply(miss, function(x)
           sprintf("%s(%s/%.2f)", x$n, if (is.finite(x$v)) sprintf("%.3f", x$v) else "NA", x$t),
           character(1)), collapse = "·"))
}

#' carry 대비 이동 — 위험과 수익이 **어느 쪽으로 더** 움직였는지가 대칭/비대칭 판별이다
rfl_shift <- function(es, carry_es = NULL) {
  if (!is.list(carry_es)) return("carry 없음(최초 칸)")
  g <- function(o, k) suppressWarnings(as.numeric(o[[k]] %||% NA))
  m0 <- g(carry_es, "mdd"); m1 <- g(es, "mdd")
  c0 <- g(carry_es, "cagr"); c1 <- g(es, "cagr")
  if (!all(is.finite(c(m0, m1, c0, c1)))) return("carry 지표 결측 — 이동 판정 불가")
  dm <- if (m0 != 0) (m1 - m0) / abs(m0) else NA_real_
  dc <- if (c0 != 0) (c1 - c0) / abs(c0) else NA_real_
  verdict <- if (!is.finite(dm) || !is.finite(dc)) "판정 불가" else
    if (dm < 0 && dc >= 0) "위험만 줄었다(비대칭 성공)" else
    if (dm < 0 && dc < 0)  { if (abs(dc) > abs(dm)) "위험보다 수익을 더 잃었다(대칭 축소의 전형)"
                             else "위험을 더 줄였다(부분 비대칭)" } else
    if (dm >= 0 && dc > 0) "수익만 늘었다(위험 축 미개입)" else "양쪽 다 악화"
  sprintf("carry 대비 MDD %.3f→%.3f(%+.1f%%) · CAGR %.3f→%.3f(%+.1f%%) → %s",
          m0, m1, 100 * dm, c0, c1, 100 * dc, verdict)
}

#' 교훈 1줄 — 기전을 특정한다. 지표 되풀이가 아니다.
rf_lesson_text <- function(code, grade, es, carry_es = NULL, treatment = NA, root = .RFL_ROOT()) {
  b <- rfl_binding(es, root)
  sprintf("[%s] Grade %s · 구속 %s (5조건 중 %d 충족) · %s%s",
          code, as.character(grade %||% "NA"), b$text, b$n_met, rfl_shift(es, carry_es),
          if (isTRUE(treatment)) " · 처치 전달 확인" else
            if (identical(treatment, FALSE)) " · ★처치 미전달" else "")
}

#' next_probe ≥2 — 같은 사실에서 기계적으로 파생한다(C/F 는 2건 이상이 계약이다)
rf_next_probes <- function(es, carry_es = NULL, block = NA_character_, root = .RFL_ROOT()) {
  th <- .rfl_thresholds(root)
  f <- function(k) suppressWarnings(as.numeric(es[[k]] %||% NA))
  p <- character(0)
  if (!is.finite(f("calmar")) || f("calmar") < th$calmar) {
    sh <- rfl_shift(es, carry_es)
    p <- c(p, if (grepl("대칭 축소의 전형", sh))
      "위험 축소를 총노출 스칼라에서 종목축(cross_sectional)으로 옮겨 상방 보존폭을 잰다"
      else "위험 축(Calmar) 미달 — 낙폭 기전을 바꾼 팔로 재측정")
  }
  if (!is.finite(f("port_t")) || f("port_t") < th$port_t)
    p <- c(p, "신호 축 미달 — 멀티팩터 깊이/직교 사슬 시드를 바꿔 재측정")
  if (!is.finite(f("oos_retention")) || f("oos_retention") < th$oos)
    p <- c(p, "OOS 소멸 — 기간 안정성 축(부기간 IR 분해)에서 원인을 특정")
  if (is.finite(f("cagr")) && f("cagr") >= th$cagr && (!is.finite(f("calmar")) || f("calmar") < th$calmar))
    p <- c(p, "CAGR 은 문턱을 넘었다 — 남은 격차는 전부 MDD 다. 수익 축을 더 밀지 말 것")
  if (!is.na(block)) p <- c(p, sprintf("격자 다음 축(%s) 에서 이 구성 위에 처치를 얹는다", block))
  unique(p)[seq_len(max(2L, min(4L, length(unique(p)))))]
}


#' 블록 순서 결정 — ★사전 선언 규칙이다. 결과를 보고 규칙을 고쳐 쓰지 않는다.
#'   규칙: 수익 축이 이미 문턱을 넘었는데 위험 축이 막고 있으면 **위험 축 블록을 앞으로** 당긴다.
#'   근거: 비중·유니버스는 MDD 를 거의 안 움직인다(실측). 그 축을 먼저 돌면 오버레이 없는
#'   구성을 최적화하게 되고, 마지막에 얹은 오버레이가 그 최적화를 무너뜨린다.
#'   결합(combination) 블록은 언제나 마지막이다 — 다른 축 승자를 조합하는 블록이라 순서가 고정이다.
rf_block_order_decide <- function(entry, prog, root = .RFL_ROOT()) {
  th  <- .rfl_thresholds(root)
  ids <- vapply(prog$blocks, function(b) as.character(b$id %||% ""), character(1))
  axs <- vapply(prog$blocks, function(b) as.character(b$axis %||% ""), character(1))
  if (!length(ids)) return(list(order = character(0), reason = "격자 블록 없음", adaptive = FALSE))
  ats <- Filter(function(a) is.list(a$essence) &&
                  is.finite(suppressWarnings(as.numeric(a$essence$port_t %||% NA))),
                entry$attempts %||% list())
  if (!length(ats)) return(list(order = ids, reason = "측정 0 — 기본 순서", adaptive = FALSE))
  v    <- vapply(ats, function(a) as.numeric(a$essence$port_t), numeric(1))
  best <- ats[[which.max(v)]]$essence
  cg   <- suppressWarnings(as.numeric(best$cagr   %||% NA))
  cl   <- suppressWarnings(as.numeric(best$calmar %||% NA))
  ## ★분모(낙폭)를 치는 축은 이제 둘이다 — **구조적 방어(B7)를 먼저**, 오버레이(B5)를 그 다음.
  ##   왜 순서를 바꿨나(실측 2026-09-21): 오버레이는 137칸을 태우고 적대검증 **pass 0**
  ##   (fail 11 · not_candidate 31) — 노출 타이밍 주장이 T3 노출-짝지은 플라시보를 한 번도 못 넘었다.
  ##   구속 축을 먼저 치라는 이 규칙의 취지는 옳은데, 우선 슬롯을 **전멸이 확인된 축**이 독점하면
  ##   그 취지가 예산 낭비로 뒤집힌다. B7 은 같은 분모를 치되 타이밍 주장이 없어 T3 대상이 아니다.
  ##   ★B5 를 빼지는 않는다 — 순서만 뒤로 간다(측정은 그대로 남는다).
  risk <- c(ids[axs == "structural_defense"], ids[axs == "risk_overlay"])
  comb <- ids[axs == "combination"]
  if (length(risk) && is.finite(cg) && cg >= th$cagr && (!is.finite(cl) || cl < th$calmar)) {
    rest <- setdiff(ids[-1L], c(risk, comb))
    return(list(order = c(ids[1L], risk, rest, comb), adaptive = TRUE,
      ## ★처방이 다른 블록을 지목했어도 여기서는 위험 축이 이긴다. 다만 그 사실을
      ##   기록한다 — 충돌이 보이지 않으면 다음에 판단할 수 없다(rf_lesson_pref_conflict).
      reason = sprintf(paste("CAGR %.3f >= %.2f 충족 · Calmar %.3f < %.2f 미달 →",
                             "위험 축(%s)을 2번째로. 비중·유니버스는 MDD 를 거의 안 움직이므로",
                             "그 축을 먼저 돌면 출하되지 않는 구성을 최적화하게 된다."),
                       cg, th$cagr, cl, th$calmar, paste(risk, collapse = ","))))
  }
  ## ── 기전 처방을 읽는다 ((다)안 2026-09-04) ────────────────────────────────
  ##   위험 축 규칙이 안 섰을 때만 본다 — 구속 축(Calmar)을 먼저 치는 건 예산 문제라
  ##   그 규칙이 서면 그게 이긴다. 여기까지 왔다는 건 수익 축이 아직 미충족이라는 뜻이고,
  ##   그때는 기전이 "무엇을 다음에 재야 하는가" 를 더 잘 안다.
  pref <- NULL
  if (!identical(tolower(Sys.getenv("QVEST_RF_ORDER_PREF", "on")), "off")) {
    pref <- tryCatch({
      ## ★기전이 **실제로 만든 설계 파일**을 본다 — L-code 본문에서 블록 코드를 긁으면
      ##   과거 셀 언급(B1_10 등)을 목표로 오인한다(실측: 처방이 B1 로 잡혔다).
      ##   .cache/rf_block_design/<base>_<BLK>.json 은 기전 레인이 "다음은 이 블록" 이라고
      ##   판단해 칸까지 짜 놓은 산출물이다 — 의도가 가장 분명한 신호다.
      d <- file.path(root, ".cache/rf_block_design")
      fs <- list.files(d, pattern = "[.]json$", full.names = TRUE)
      fs <- fs[startsWith(basename(fs), paste0(entry$base_id, "_"))]
      if (!length(fs)) NULL else {
        fs <- fs[order(file.info(fs)$mtime)]
        b <- sub("^.*_(B[0-9]+)[.]json$", "\\1", basename(fs[length(fs)]))
        if (nzchar(b) && b %in% ids) b else NULL
      }
    }, error = function(e) NULL)
  }
  if (!is.null(pref) && !identical(pref, ids[1L])) {
    rest <- setdiff(ids[-1L], c(pref, comb))
    return(list(order = c(ids[1L], pref, rest, comb), adaptive = TRUE,
      mechanism_pref = pref,
      reason = sprintf(paste("기전 처방이 %s 를 지목 — 위험 축 규칙(Calmar 미달)이 서지 않아",
                             "처방을 따른다. CAGR %.3f · Calmar %.3f.",
                             "★순서 결정기는 처방이 **시험하려는 명제**를 전제로 깔지 않는다."),
                       pref, cg, cl)))
  }
  list(order = ids, adaptive = FALSE, mechanism_pref = pref %||% NA_character_,
       reason = sprintf("기본 순서 — CAGR %.3f · Calmar %.3f (수익 축 미충족이면 위험 축을 앞당길 근거가 없다)%s",
                        cg, cl, if (!is.null(pref)) sprintf(" · 기전 처방(%s)은 이미 1번째", pref) else ""))
}
cat("[rf_lesson.R] Loaded — rf_lesson_text() / rf_next_probes() / rfl_binding() / rfl_shift()\n")
