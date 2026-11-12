# -*- coding: utf-8 -*-
"""S3 레인 출력 계약 — 후보판 생성기(운영 파일은 읽기만 · 쓰기는 이 폴더뿐).

원본 3개(레인 스크립트 · 검증기 · 충실도 감사 축 정본)를 바이트로 읽어, 정해 둔 치환쌍을 **정확히 지정 횟수만큼** 적용한
사본을 이 폴더에 쓴다. 치환이 빗나가면(0회 · 초과) 멈춘다 — 조용히 빗나간 치환은 가짜 후보판이 된다(10-15 교훈).
줄끝은 원본 그대로(셋 다 LF · 마지막 개행 유무 보존 — JSON 은 개행 없이 끝난다).
원본 md5 는 SOURCE_MD5.json 에 남긴다(교체 직전 대조 기준).

실행: python make_s3_candidates.py   (설계 = README.md §6-2 · §6-5 · BUILD_EDITION2.md S3)
"""
import hashlib, io, json, os, sys

ROOT = os.environ.get("QM_ROOT_S3", "G:/OneDrive/Quant_Module_Moltbot").replace("\\", "/")
HERE = os.path.dirname(os.path.abspath(__file__))

SRC = {
    "rf_replication_auto.sh": ROOT + "/02_Infrastructure/ops/rf_replication_auto.sh",
    "rf_replication_verify.R": ROOT + "/02_Infrastructure/ops/rf_replication_verify.R",
    "rf_fidelity_axes.json": ROOT + "/06_Registry/rf_fidelity_axes.json",
}

# ── 1. 레인 프롬프트 (rf_replication_auto.sh) ─────────────────────────────────────────────
SH = []
# (a) portfolio_spec 절 — PORTFOLIO + FACTORS 를 함께 내도 engine_direct
SH.append((r'''      (네가 만든 비중이 곧 논문 비중이다. 롱숏이면 반드시 이 값이어야 한다 —
       이게 없으면 러너가 숏 다리를 버리고 롱온리 top-N 으로 다시 구성한다.)
''', r'''      (네가 만든 비중이 곧 논문 비중이다. 롱숏이면 반드시 이 값이어야 한다 —
       이게 없으면 러너가 숏 다리를 버리고 롱온리 top-N 으로 다시 구성한다.
       점수 패널(FACTORS)을 함께 내도 engine_direct 다 — 러너는 PORTFOLIO 로 재고 FACTORS 는 점수 패널로 저장한다(아래 '산출' 절).)
''', 1))
# (b) FIDELITY 구조 필드 목록 — 7번째 키
SH.append((r'''6. variants · headline_variant · construction_source — 위 '모든 방법론' 절 ⑥(사전검사 P9 · P11). omitted 단계는 omit_code(P10).
''', r'''6. variants · headline_variant · construction_source — 위 '모든 방법론' 절 ⑥(사전검사 P9 · P11). omitted 단계는 omit_code(P10).
7. score_panel — 아래 '산출' 절의 점수 패널 계약(2026-11-12). 점수를 내지 않는 엔진도 available = false 와 reason 으로 적는다.
''', 1))
# (c) 제출 전 자가 점검 — 한 줄
SH.append((r'''  상태 플래그(관리종목·거래정지) · 커버리지 하한 · 1e-x 분모 가드가 각각 changed 또는 paper_steps note 에 적혀 있는가.
''', r'''  상태 플래그(관리종목·거래정지) · 커버리지 하한 · 1e-x 분모 가드가 각각 changed 또는 paper_steps note 에 적혀 있는가.
- 종목별 수치로 보유를 정하는 엔진이면 PORTFOLIO 와 함께 FACTORS(선정 전 후보 전체 · PORTFOLIO 와 같은 신호일)를 냈는가 ·
  롱 보유가 그날 FACTORS 안에 있는가 · FIDELITY.score_panel 을 적었는가(내보낼 값이 없으면 available = false + reason).
''', 1))
# (d) 산출 절 — '또는' → 점수 패널 계약(결합 프롬프트도 이 절부터 끝까지를 꼬리로 받는다)
SH.append((r'''## 산출 (이것만)
\`${WDIR}/engine.R\` — source 되면 \`FACTORS(Date,Ticker,Score)\` 또는
\`PORTFOLIO(Date,Ticker,Weight,Leg)\` 를 만드는 R 스크립트. 호출자가 환경에 \`RAWDATA\`·\`BM_DT\` 를 넣어준다.
''', r'''## 산출 (이것만)
\`${WDIR}/engine.R\` — source 되면 아래 산출 대입을 만드는 R 스크립트. 호출자가 환경에 \`RAWDATA\`·\`BM_DT\` 를 넣어준다.
- 보유를 엔진이 직접 만들면 \`PORTFOLIO(Date,Ticker,Weight,Leg)\`. 점수만 내고 구성을 레인 표준에 맡기면 \`FACTORS(Date,Ticker,Score)\` 만.
- ★점수 패널 계약(2026-11-12 · 설계 04_Research/01_reports/portfolio_paper_layer_split_20261112 §6-2): 엔진이 **종목별 수치**(예측값 ·
  확률 · 점수 · 신호값)로 보유를 정하면 PORTFOLIO 와 **함께** \`FACTORS(Date,Ticker,Score)\` 를 낸다. 상설 자격 판이 이 패널로 표준 구성
  (상위 N 등가중)을 다시 잰다 — PORTFOLIO 만 내면 그 엔진은 기저 후보에서 빠진다. 러너는 PORTFOLIO 로 논문 구성을 재고(engine_direct)
  FACTORS 는 점수 패널(factors_panel.parquet)로 저장한다.
  · 대상 = 그 신호일의 **선정 전 후보 전체**다. PORTFOLIO 가 고른 종목만 담은 패널은 계약 위반이다 — 롱 보유는 그날 패널의 부분집합이어야
    하고, 검증기가 신호일마다 기계로 대조한다(보유/후보 비도 기록한다). 날짜 = PORTFOLIO 의 신호일과 같은 날짜 집합.
  · 논문이 예측 **전에** 유니버스를 좁히는 규칙(예: 시장상관 상위 50 · 가격 · 규모 문턱)은 예측이 아니라 **구성 규칙**으로 신고하고, 점수는
    좁히기 전 적격 종목에 낸다. 그 계산이 과다하면 좁힌 집합으로 내고 그 사실을 신고한다(score_panel.target_set).
  · Score = 클수록 롱 후보 · 논문 정의 그대로(재척도 · 순위화 · 표준화하지 않는다). 논문 값이 작을수록 매수면 부호를 뒤집어 내고 신고한다
    (score_panel.direction · 엔진이 계산한 모형 출력의 방향 표기다 — 팩터 DB 값에 −1 을 곱하는 수동 반전 금지(C13)는 그대로다).
  · 한 모형이 예측과 구성을 다 하면(정책 학습 · end-to-end 비중) softmax 전 점수 · 정책 모수 · 포지션 값 같은 내부 종목별 값을 Score 로 낸다.
  · 내보낼 종목별 값이 없으면(구성 규칙 · 노출 규칙 논문 — 공분산 · 위험 예산 · 총노출 타이밍만 있는 경우) FACTORS 를 내지 않는다.
    비중을 Score 로 옮겨 적지 마라(지어낸 점수다).
  · 계산은 그대로다 — 점수 패널은 엔진이 이미 만든 값을 내보내는 산출이지 새 계산 · 새 선택이 아니다(PORTFOLIO 가 바뀌면 안 된다).
  · \`FACTORS <- <data.table>\` 형태로 최상위에서 대입한다(상설 판이 엔진 코드의 FACTORS 대입을 정적으로 읽는다).
  · FIDELITY.json 에 \`score_panel\` 객체를 쓴다(점수를 내든 안 내든):
      {\"available\": true|false, \"reason\": available 이 false 일 때 이유(내보낼 종목별 값이 없는 까닭),
       \"definition\": Score 가 무엇인가(논문 식 · 표 번호), \"direction\": \"higher_is_long\" 또는 \"flipped\"(뒤집었으면 이유를 changed 에),
       \"target_set\": {\"rule\": 대상 집합(예: 그날 측정 축 유니버스 적격 전체), \"narrowed\": true|false,
                      \"narrowing_rule\": 좁혔으면 그 규칙과 원문 위치, \"why\": 좁힌 이유(논문 규칙 | 계산량)},
       \"scale\": \"cardinal\"(예측 수익 · 확률처럼 간격이 뜻을 가진다) 또는 \"ordinal\"(순위 · 분위만)}
    scale 은 **논문 정의에서** 읽는다(성과를 보고 고르지 않는다). 좁히기 · 부호 반전은 changed 에도 적는다.
''', 1))

# ── 2. 충실도 감사 축 정본 (rf_fidelity_axes.json) — 신호 축 focus 끝에 한 항목 ───────────────────
AX_ANCHOR = 'C13 위반이다.",'
AX_ADD = (' ★점수 패널(2026-11-12 · 레인 출력 계약 — 설계 04_Research/01_reports/portfolio_paper_layer_split_20261112 §6-2): '
          'engine.R 이 FACTORS 를 내면 그 Score 가 **논문 신호인가**를 대조하라 — FIDELITY.score_panel.definition 이 가리키는 논문 식 · 모형 출력과 '
          '코드가 FACTORS 에 넣는 값이 같은가. 보유 비중 · 선정 뒤 표식 · 사후 순위처럼 논문 신호가 아닌 값을 Score 로 낸 것, 선정 전 후보가 아니라 '
          '고른 종목만 담은 것, 부호를 뒤집고 score_panel.direction 에 적지 않은 것, 논문이 예측 전에 유니버스를 좁히는 규칙을 신고 없이 패널 대상에 '
          '섞은 것(구성 규칙으로 신고해야 한다 · score_panel.target_set), scale(cardinal | ordinal)이 논문 정의와 다른 것은 발견이다. 종목별 수치로 '
          '보유를 정하는데 FACTORS 를 내지 않았거나 score_panel.available = false 의 reason 이 코드와 다르면(내보낼 종목별 값이 엔진 안에 있는데 '
          '없다고 적음) 그것도 발견이다.')
AX = [(AX_ANCHOR, 'C13 위반이다.' + AX_ADD + '",', 1)]

# ── 3. 레인 검증기 (rf_replication_verify.R) ───────────────────────────────────────────
V = []
V_FUNCS = r'''## ── 점수 패널 정합 · 보유/후보 비 (2026-11-12 · 레인 출력 계약 — 설계 04_Research/01_reports/portfolio_paper_layer_split_20261112 §6-2 · §6-5) ──
##   ① 정합: 보유 표(04_holdings.csv · 날짜 = 체결일)의 롱 보유(target_weight > 0)가 그 신호일 점수 패널(factors_panel.parquet — 러너가
##     유니버스 적용 뒤 저장 · 점수 유한 행)의 부분집합인가. 체결일 → 신호일 = 패널 날짜 가운데 체결일보다 앞선 마지막 날(보유 표에는
##     신호일 열이 없다 · 계약 = 패널 날짜 = PORTFOLIO 신호일 — 레인 하네스의 체결 지연이 이틀~한 달이어도 같은 대응이다 · 설계 §2-6).
##     순위 일치는 조건이 아니다(문턱 · 최적화 선정은 단조가 아니다) — 보유 종목의 점수 순위(큰 점수 = 1위)는 기록만 한다.
##   ② 보유/후보 비(§6-5): 신호일마다 롱 보유 수 / 후보 폭. 비교 기준 = 측정 축 실효 시작 배수 effective_start.breadth_mult(측정 기록의
##     measurement_axis 블록 → 블록이 없을 때만 constraint_defaults.json 활성 epoch · 새 숫자 없음). 띠: 폭 < 배수 × 보유 = below(그날은 실효
##     시작 규칙 미달) · 배수 × 보유 ≤ 폭 < 배수 × (보유 + 1) = near(한 종목만 더 보유해도 미달 — '2배 근처') · 그 밖 = ok. near · below 는 경고 기록.
##   ③ 대상: 패널이 없고 FIDELITY.score_panel.available = false = not_applicable · 신고 블록 없는 구판 엔진 = no_declaration(둘 다 대상 아님) ·
##     available = true 인데 패널이 없음 = declared_but_missing(어긋남).
##   처분: 어긋남(subset_violation · declared_but_missing)은 꼬리표 score_panel_mismatch → implementation_suspect(상설 입구 사유 · 판정 아님).
##     측정 · 소비 · 재료 인계는 그대로다 — PORTFOLIO 측정(논문 구성)은 유효하고, 못 믿게 된 것은 '선정 전 후보'라는 패널의 뜻이다.
##     경고(near · below)는 기록만 한다. 검사 자체가 실패하면 check_error 를 기록하고 꼬리표는 달지 않는다(fail-open · 저널 score_panel_check).
##   성과를 읽지 않는다 — 날짜 · 종목 · 비중 부호 · 점수 순위와 측정 축 블록의 배수만.
.v1001_breadth_mult <- function(ar_obj = NULL, root = ROOT) {
  num1 <- function(x) { x <- suppressWarnings(as.numeric(unlist(x))); if (length(x) == 1L && is.finite(x)) x else NA_real_ }
  ma <- if (is.list(ar_obj)) ar_obj$measurement_axis else NULL
  if (is.list(ma)) {
    m <- num1(ma$effective_start$breadth_mult)
    if (is.finite(m)) return(list(mult = m, source = "authoritative_remeasure.measurement_axis.effective_start.breadth_mult"))
    m <- num1(ma$effective_start_rule$breadth_mult)
    if (is.finite(m)) return(list(mult = m, source = "authoritative_remeasure.measurement_axis.effective_start_rule.breadth_mult"))
    return(list(mult = NA_real_, source = "axis_has_no_effective_start_rule"))   # 측정 축에 규칙이 없다(구 축) — 다른 축의 배수를 빌리지 않는다
  }
  m <- tryCatch({
    cd <- fromJSON(file.path(root, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$measurement_axis
    num1(cd$epochs[[as.character(cd$active)[1]]]$effective_start$breadth_mult)
  }, error = function(e) NA_real_)
  list(mult = m, source = if (is.finite(m)) "constraint_defaults.measurement_axis.epochs[active].effective_start.breadth_mult" else "unavailable")
}
.v1001_score_panel_check <- function(dir, fid = NULL, ar_obj = NULL, root = ROOT) {
  sp <- if (is.list(fid) && is.list(fid$score_panel)) fid$score_panel else NULL
  decl <- if (!is.null(sp) && length(sp$available)) isTRUE(as.logical(sp$available)[1]) else NA     # NA = 신고 블록 없음(구판 엔진)
  pf <- file.path(dir, "factors_panel.parquet")
  out <- list(schema = "score_panel_check_v1", design = "portfolio_paper_layer_split_20261112 §6-2 · §6-5",
              declared_available = decl, declared_scale = if (!is.null(sp)) as.character(sp$scale %||% NA)[1] else NA_character_,
              panel_file = file.exists(pf), mismatch = FALSE, findings = character(0), warnings = character(0))
  if (!file.exists(pf)) {
    out$status <- if (isFALSE(decl)) "not_applicable" else if (is.na(decl)) "no_declaration" else "declared_but_missing"
    if (isFALSE(decl)) out$declared_reason <- as.character(sp$reason %||% NA)[1]
    if (identical(out$status, "declared_but_missing")) {
      out$mismatch <- TRUE; out$findings <- "FIDELITY.score_panel.available = true 인데 점수 패널(factors_panel.parquet)이 없다" }
    return(out)
  }
  if (!requireNamespace("arrow", quietly = TRUE)) { out$status <- "check_error"; out$error <- "arrow 없음"; return(out) }
  P <- tryCatch(as.data.table(arrow::read_parquet(pf, col_select = c("Date", "Ticker", "Score"))), error = function(e) NULL)
  if (is.null(P)) { out$status <- "panel_unreadable"; out$warnings <- "panel_unreadable"; return(out) }
  P <- P[, .(d = as.Date(Date), t = as.character(Ticker), s = suppressWarnings(as.numeric(Score)))][!is.na(d) & !is.na(t) & is.finite(s)]
  n_dup <- nrow(P) - uniqueN(P, by = c("d", "t")); P <- unique(P, by = c("d", "t"))
  H <- tryCatch(fread(file.path(dir, "04_holdings.csv"), select = c("date", "ticker", "target_weight"),
                      colClasses = list(character = "ticker"), showProgress = FALSE), error = function(e) NULL)
  if (is.null(H) || !nrow(H)) { out$status <- "no_holdings"; return(out) }
  H <- unique(H[is.finite(target_weight) & target_weight > 0, .(x = as.Date(date), t = as.character(ticker))])
  if (!nrow(H)) { out$status <- "no_long_holdings"; return(out) }
  pd <- sort(unique(P$d)); ex <- sort(unique(H$x))
  i <- if (length(pd)) findInterval(as.numeric(ex) - 0.5, as.numeric(pd)) else rep(0L, length(ex))   # 체결일보다 앞선 패널 날짜 수
  map <- data.table(x = ex, d = as.Date(ifelse(i >= 1L, as.numeric(pd[pmax(i, 1L)]), NA_real_), origin = "1970-01-01"))
  unmapped <- map[is.na(d)]$x
  P[, rk := frank(-s, ties.method = "min"), by = d]
  B <- P[, .(breadth = .N), by = d]
  J <- merge(merge(H, map[!is.na(d)], by = "x"), P[, .(d, t, rk)], by = c("d", "t"), all.x = TRUE)
  D <- J[, .(n_long = .N, n_out = sum(is.na(rk)), out_tickers = paste(head(t[is.na(rk)], 5L), collapse = ","),
             max_rank = if (any(!is.na(rk))) as.numeric(max(rk, na.rm = TRUE)) else NA_real_,
             n_in_top_n = as.integer(sum(!is.na(rk) & rk <= .N))), by = .(d, x)]
  D <- merge(D, B, by = "d", all.x = TRUE); D[is.na(breadth), breadth := 0L]
  D[, ratio := fifelse(breadth > 0, n_long / breadth, NA_real_)]
  bm <- .v1001_breadth_mult(ar_obj, root)
  D[, band := if (is.finite(bm$mult)) fifelse(breadth < bm$mult * n_long, "below", fifelse(breadth < bm$mult * (n_long + 1), "near", "ok")) else NA_character_]
  setorder(D, d)
  viol <- D[n_out > 0]
  out$status <- "ok"
  out$n_signal_dates <- nrow(D); out$n_exec_dates <- length(ex); out$n_unmapped_exec_dates <- length(unmapped)
  out$n_panel_dates <- length(pd); out$n_panel_duplicate_rows <- as.integer(n_dup)
  out$n_violation_dates <- nrow(viol); out$n_held_outside_panel <- as.integer(sum(D$n_out))
  out$violation_examples <- if (nrow(viol)) lapply(seq_len(min(5L, nrow(viol))), function(k)
    list(signal_date = format(viol$d[k]), exec_date = format(viol$x[k]), n_out = viol$n_out[k], tickers = viol$out_tickers[k])) else list()
  out$unmapped_exec_dates <- format(head(unmapped, 5L))
  out$rank <- list(note = "보유 종목의 점수 순위(큰 점수 = 1) — 기록만(조건 아님)",
                   in_top_n_share = if (sum(D$n_long - D$n_out) > 0) sum(D$n_in_top_n) / sum(D$n_long - D$n_out) else NA_real_,
                   max_rank_median = if (any(is.finite(D$max_rank))) stats::median(D$max_rank, na.rm = TRUE) else NA_real_)
  out$holdings_to_candidates <- list(breadth_mult = bm$mult, breadth_mult_source = bm$source,
                                     ratio_median = if (any(is.finite(D$ratio))) stats::median(D$ratio, na.rm = TRUE) else NA_real_,
                                     ratio_max = if (any(is.finite(D$ratio))) max(D$ratio, na.rm = TRUE) else NA_real_,
                                     n_below = sum(D$band %in% "below"), n_near = sum(D$band %in% "near"), n_ok = sum(D$band %in% "ok"),
                                     band_rule = "below: 폭 < 배수 × 보유 · near: 배수 × 보유 ≤ 폭 < 배수 × (보유 + 1) · ok: 그 밖")
  ## 패널 날짜가 보유 신호일보다 촘촘하면(대응 가정 = '패널 날짜 = PORTFOLIO 신호일'이 깨졌을 수 있다) 경고 — 대응된 범위 안 패널 날짜 수로 센다
  md <- unique(map[!is.na(d)]$d)
  n_in_span <- if (length(md)) sum(pd >= min(md) & pd <= max(md)) else 0L
  if (n_in_span > length(md)) out$warnings <- c(out$warnings, sprintf("panel_dates_denser_than_holdings(%d 패널일 vs %d 대응 신호일)", n_in_span, length(md)))
  if (length(md) < length(ex) - length(unmapped)) out$warnings <- c(out$warnings, sprintf("exec_dates_share_signal_date(%d 체결일 → %d 신호일)", length(ex) - length(unmapped), length(md)))
  if (n_dup > 0) out$warnings <- c(out$warnings, sprintf("panel_duplicate_rows(%d)", as.integer(n_dup)))
  if (out$holdings_to_candidates$n_below > 0) out$warnings <- c(out$warnings, sprintf("holdings_breadth_below_mult(%d/%d 신호일 · 배수 %s)", out$holdings_to_candidates$n_below, nrow(D), format(bm$mult)))
  if (out$holdings_to_candidates$n_near > 0) out$warnings <- c(out$warnings, sprintf("holdings_breadth_near_mult(%d/%d 신호일 · 배수 %s)", out$holdings_to_candidates$n_near, nrow(D), format(bm$mult)))
  if (!is.finite(bm$mult)) out$warnings <- c(out$warnings, paste0("breadth_mult_unavailable(", bm$source, ")"))
  if (nrow(viol)) out$findings <- c(out$findings, sprintf("롱 보유 ⊄ 점수 패널 — %d/%d 신호일 · 패널 밖 보유 %d건(예: %s %s)", nrow(viol), nrow(D),
                                                          out$n_held_outside_panel, format(viol$d[1]), viol$out_tickers[1]))
  if (length(unmapped)) out$findings <- c(out$findings, sprintf("앞선 점수 패널 날짜가 없는 체결일 %d개(예: %s)", length(unmapped), format(unmapped[1])))
  out$mismatch <- length(out$findings) > 0L
  tryCatch(fwrite(D[, .(signal_date = d, exec_date = x, n_long, breadth, ratio, band, n_out, out_tickers, max_rank, n_in_top_n)],
                  file.path(dir, "score_panel_check_dates.csv")), error = function(e) NULL)
  out
}
## 요청 · 보고 쓰임 — 검사 결과(.SPC)의 요약. 결과가 없으면 NULL(구판과 같은 요청 · 보고)
.v1001_score_panel_req <- function(spc = if (exists(".SPC", inherits = TRUE)) .SPC else NULL) {
  if (is.null(spc)) return(NULL)
  list(status = spc$status, mismatch = isTRUE(spc$mismatch), n_signal_dates = spc$n_signal_dates %||% NULL,
       n_violation_dates = spc$n_violation_dates %||% NULL, n_below = spc$holdings_to_candidates$n_below %||% NULL,
       n_near = spc$holdings_to_candidates$n_near %||% NULL, breadth_mult = spc$holdings_to_candidates$breadth_mult %||% NULL,
       warnings = as.list(spc$warnings %||% character(0)), file = "score_panel_check.json")
}
.v1001_score_panel_extra <- function(spc = if (exists(".SPC", inherits = TRUE)) .SPC else NULL) {
  if (is.null(spc) || (!isTRUE(spc$mismatch) && !length(spc$warnings))) return(NULL)
  list(list(type = "text", emoji = "\U0001F9FE",
            heading = sprintf("점수 패널 정합 — %s", if (isTRUE(spc$mismatch)) "어긋남(구현 의심 꼬리표 · 판정 아님)" else "경고"),
            body = paste(c(spc$findings, spc$warnings), collapse = "\n")))
}
'''
V.append(('## 변형 1개의 요약 행 — 계약 산출물에서 읽기만 한다(손계산 0 · AX-008). 행동 카드는 대표처럼 산출물 옆에 쓴다(위기 방어 판정 병기).\n',
          V_FUNCS + '## 변형 1개의 요약 행 — 계약 산출물에서 읽기만 한다(손계산 0 · AX-008). 행동 카드는 대표처럼 산출물 옆에 쓴다(위기 방어 판정 병기).\n', 1))
V.append(('.impl_suspect <- isTRUE(.aud_suspect) || isTRUE(.p4_suspect)\n',
          r'''## ①-c 점수 패널 정합 · 보유/후보 비(2026-11-12 · 설계 §6-2 · §6-5 — 위 .v1001_score_panel_check 머리 주석) — 대표 산출물만(상설 입구가 읽는 산출)
.SPC <- tryCatch(.v1001_score_panel_check(dirname(ar), .fid_o, AR),
                 error = function(e) list(schema = "score_panel_check_v1", status = "check_error", error = conditionMessage(e), mismatch = FALSE,
                                          findings = character(0), warnings = character(0)))
tryCatch(write(toJSON(.SPC, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), file.path(dirname(ar), "score_panel_check.json")),
         error = function(e) jlog("score_panel_check_write_failed", err = conditionMessage(e)))
.sp_mismatch <- isTRUE(.SPC$mismatch)
jlog("score_panel_check", status = .SPC$status %||% NA, mismatch = .sp_mismatch, n_signal_dates = .SPC$n_signal_dates %||% NA,
     n_violation_dates = .SPC$n_violation_dates %||% NA, n_below = .SPC$holdings_to_candidates$n_below %||% NA,
     n_near = .SPC$holdings_to_candidates$n_near %||% NA, breadth_mult = .SPC$holdings_to_candidates$breadth_mult %||% NA,
     warnings = paste(.SPC$warnings %||% character(0), collapse = " | "), artifacts = dirname(ar))
.impl_suspect <- isTRUE(.aud_suspect) || isTRUE(.p4_suspect) || .sp_mismatch
''', 1))
V.append(('             if (isTRUE(.p4_suspect)) " · implementation_suspect(측정 뒤 보유 대조 어긋남)" else "")), root = ROOT)\n',
          '             if (isTRUE(.p4_suspect)) " · implementation_suspect(측정 뒤 보유 대조 어긋남)" else "",\n'
          '             if (isTRUE(.sp_mismatch)) " · implementation_suspect(점수 패널 정합 어긋남)" else "")), root = ROOT)\n', 1))
V.append(('implementation_suspect = .impl_suspect, holdings_claim_mismatch = isTRUE(.p4_suspect), has_short = .hs,\n',
          'implementation_suspect = .impl_suspect, holdings_claim_mismatch = isTRUE(.p4_suspect), has_short = .hs,\n'
          '                                     score_panel_mismatch = isTRUE(.sp_mismatch),\n', 1))
V.append(('  d$variants <- .v1001_variants_req()                       # 변형 측정 요약(10-17 · 없으면 NULL = 안 실린다)\n',
          '  d$variants <- .v1001_variants_req()                       # 변형 측정 요약(10-17 · 없으면 NULL = 안 실린다)\n'
          '  d$score_panel_check <- .v1001_score_panel_req()            # 점수 패널 정합 요약(11-12 · §6-2)\n', 1))
V.append(('extra = c(.v1001_grade_extra(dirname(ar)), .v1001_variants_extra(), .v1001_factor_section(dirname(ar)))',
          'extra = c(.v1001_grade_extra(dirname(ar)), .v1001_variants_extra(), .v1001_score_panel_extra(), .v1001_factor_section(dirname(ar)))', 2))
V.append(('                      flags = list(implementation_suspect = .impl_suspect, holdings_claim_mismatch = isTRUE(.p4_suspect),\n'
          '                                   has_short = isTRUE(AR$replication$has_short %||% AR$has_short),\n',
          '                      flags = list(implementation_suspect = .impl_suspect, holdings_claim_mismatch = isTRUE(.p4_suspect),\n'
          '                                   score_panel_mismatch = isTRUE(.sp_mismatch),\n'
          '                                   has_short = isTRUE(AR$replication$has_short %||% AR$has_short),\n', 1))
V.append(('  variants = .v1001_variants_req(), audit_ruling_applied = .v1001_ruling(),\n',
          '  variants = .v1001_variants_req(), audit_ruling_applied = .v1001_ruling(), score_panel_check = .v1001_score_panel_req(),\n', 1))


def md5(b):
    return hashlib.md5(b).hexdigest()


def apply(name, pairs):
    raw = io.open(SRC[name], "rb").read()
    if b"\r\n" in raw:
        sys.exit("[s3] %s 에 CRLF 가 있다 — 생성기는 LF 원본만 다룬다(치환쌍을 다시 만들 것)" % name)
    txt = raw.decode("utf-8")
    for k, (old, new, n) in enumerate(pairs, 1):
        c = txt.count(old)
        if c != n:
            sys.exit("[s3] %s 치환 %d: 기대 %d회 · 실제 %d회 — 멈춤(원본이 바뀌었으면 치환쌍을 다시 만든다)" % (name, k, n, c))
        txt = txt.replace(old, new)
    out = txt.encode("utf-8")
    assert out.endswith(b"\n") == raw.endswith(b"\n"), "마지막 개행 유무가 바뀌었다"
    assert b"\r" not in out
    io.open(os.path.join(HERE, name), "wb").write(out)
    os.makedirs(os.path.join(HERE, "orig"), exist_ok=True)
    io.open(os.path.join(HERE, "orig", name), "wb").write(raw)
    return {"source": SRC[name], "source_md5": md5(raw), "candidate_md5": md5(out), "n_pairs": len(pairs),
            "source_lines": raw.count(b"\n"), "candidate_lines": out.count(b"\n")}


rec = {"generated_by": "make_s3_candidates.py", "root": ROOT,
       "files": {"rf_replication_auto.sh": apply("rf_replication_auto.sh", SH),
                 "rf_replication_verify.R": apply("rf_replication_verify.R", V),
                 "rf_fidelity_axes.json": apply("rf_fidelity_axes.json", AX)}}
# JSON 후보는 파싱 · 축 수 · 신호 축 외 무변경을 여기서 단정한다
a0 = json.loads(io.open(SRC["rf_fidelity_axes.json"], "rb").read().decode("utf-8"))
a1 = json.loads(io.open(os.path.join(HERE, "rf_fidelity_axes.json"), "rb").read().decode("utf-8"))
assert [x["key"] for x in a0["axes"]] == [x["key"] for x in a1["axes"]]
for x0, x1 in zip(a0["axes"], a1["axes"]):
    if x0["key"] == "signal":
        assert x1["focus"].startswith(x0["focus"]) and x1["focus"] != x0["focus"]
        assert {k: v for k, v in x0.items() if k != "focus"} == {k: v for k, v in x1.items() if k != "focus"}
    else:
        assert x0 == x1
assert {k: v for k, v in a0.items() if k != "axes"} == {k: v for k, v in a1.items() if k != "axes"}
io.open(os.path.join(HERE, "SOURCE_MD5.json"), "w", encoding="utf-8", newline="\n").write(json.dumps(rec, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(rec, ensure_ascii=False, indent=2))
