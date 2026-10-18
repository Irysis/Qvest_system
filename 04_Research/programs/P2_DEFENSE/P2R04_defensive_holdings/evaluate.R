## P2R04 평가 — 엔진 자체 구성 위 방어적 보유(방어 팩터 틸트 4종 · 비대칭 원천 ③) × 엔진 2(E2 DNN 원형 EW · E3 B6_36 엔트로피 비중) vs 같은 배치
##   엔진 자체 구성 RX0 → 사전등록 규칙(stage_artifacts prereg.json rules · final_selection_rule)을 기계 적용(R2). 수치는 전부 R 계약 산출(dp_build 보는 창 패킷 ·
##   mc_card · rk_S · rk_pair_alpha · beta_controlled_alpha · matched_controls 크기 바스켓 · behavior_card 위기 포착 — 손계산 없음 · AX-008). 이 파일이 더하는 것은
##   규칙 적용 · 공통 창 사본 · β 짝 사본 · 빠른 급락 분류(같은 칸 산출물의 벤치 일수익) · 셀 로그 · 보유 대조 · 기록 파싱 · 진단 읽기뿐.
##   도우미 = P2R03 evaluate.R(픽스처 34 · 리허설 통과판)을 이어받았다. 장치가 '얼마나 드느냐'(시변 노출)에서 '무엇을 드느냐'(선택 기울기 · Σw = 1)로
##   바뀐 데 맞춰 뺀 것: 오버레이 집행 줄 · kind 일치 · lag-1 칸 짝 · lag 꼬리표 · 같은 선정 집합(변형 보유 ⊆ RX0 — 선택을 바꾸는 장치라 정의상 깨진다) ·
##   현금 타이밍 · HM 타이밍(노출 경로가 고정이라 무의미) · 대조 읽기. 더한 것: ⑩ 구성 증거(사양 = RX0 + 장치 팩터 꼬리 m 회 반복 · 셀 로그 팩터 적재 줄 ·
##   보는 창 보유가 RX0 와 다른 보유일 ≥ 1 — 무처치 = 미시험) · ⑭ 선택 귀속(MC8 라벨 = mc8_label_required ∧ 진단 패킷 위기 분해의 '선택' 항이 깊은 위기
##   과반에서 RX0 보다 개선(변형 − RX0 > 0 · 엄격 · 문턱 없음) — C-028) · 진단 칸 13개(철학 P1 R-20261018-003 · 판단 Superfan T1 R-20261018-004 — 결측 짝 E2 C1~C4 · 용량 짝
##   E2 · E3 W1~W4 · 희석 짝 E2 N0 · 판정 표 밖)와 진단 읽기 · 크기 × β 짝(C-017 · 결론 이름 규칙) · 유동성 귀속(C-020) · 국면별 월 차이 ·
##   기준점 두 개(C-024 · 엔진 대비 · 시장 대비) · 상태 미전환 최대 하락 위기 기록(C-019) · RX0 동일성(C-025 · P2R03 RX0 대비) · A 거리(C-031 · 칸마다
##   gv3 A 하한 값과 문턱 거리) · R7 판독(C-029 · 'S · 위기 방어 개선이 잡음 이내') · 보는 창 파일의 τ_D 이후 날짜 가림 + 쓰기 전 전수 검사.
## 실행: Rscript evaluate.R [--cells-only] [--shard=i/K]      (측정 = measure.sh · 리허설 = rehearse.R · 픽스처 = evaluate_fixture.R)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

P2R04_ROUND_ID <- "P2R04_defensive_holdings"
## 장치 → 방어 팩터(팩터 DB · 원값 = 방어 쪽이 높게 저장 · compute_defense.R) — 사양 · 등록 · 판정이 같은 표를 쓴다(DESIGN §3).
##   kind · id = 장치 칸 사양이 RX0 사양의 factors 끝에 붙이는 항목 그대로({"kind":"db","id":<팩터>} · DESIGN §10)
P2R04_DEVICES <- list(
  H1 = list(kind = "db", id = "D04_Downside_Beta", name = "하방β", raw = "−(시장 하락일만으로 추정한 β)",
            basis = "Ang, Chen & Xing (2006) Downside Risk, RFS 19(4)"),
  H2 = list(kind = "db", id = "D03_RealVol", name = "저변동", raw = "−(252일 실현 변동성)",
            basis = "Blitz & van Vliet (2007) The Volatility Effect, JPM 34(1) · Frazzini & Pedersen (2014) JFE 111(1) — P2R02 C4 재시험"),
  H3 = list(kind = "db", id = "D07_Beta_Asymmetry", name = "β 비대칭", raw = "상승β − 하락β(클수록 오를 때 더 오르고 내릴 때 덜 내림)",
            basis = "Ang, Chen & Xing (2006) 비대칭 β — 철학 '비대칭'의 종목 수준 대응"),
  H4 = list(kind = "db", id = "Q08_Composite_Quality", name = "퀄리티", raw = "복합 퀄리티(GPA · ROE · ROA · 발생액)",
            basis = "Asness, Frazzini & Pedersen (2019) Quality minus junk, RAS 24 — P2R02 C5 재시험"))
## 진단 칸(철학 P1 R-20261018-003 · 판단 Superfan T1 R-20261018-004 수용 · cells[].diagnostic = true · 판정 표 · 장치 검증 · 최종 선택 밖)
##   결측 짝 Ck(E2) = DNN 100% + 장치 팩터(혼합 가중 0 — 팩터 결측 종목 제외 효과만 · C-016) · 용량 짝 Wk(E2 · E3) = 장치 팩터 몫 = 도구 상자 기본
##   (E3 RX0 사양의 base_weight 위에 장치 팩터 1회 = 12.5% · C-018) · 희석 짝 N0(E2) = 무작위 순열 팩터(rf_cell_engine kind null_perm) 몫 = E2 장치 칸의 몫
##   (50% · C-021). 판정 칸 장치 몫 = E2 · E3 모두 50%(E3 은 장치 팩터 반복 나열 · base_weight 0.25). 가중은 사양에서 재도출해 대조한다(숫자를 박지 않는다)
P2R04_DIAG_ENGINE <- "E2"                                                        # 결측 · 희석 짝의 엔진 = 진단 읽기 (a) · (c) 의 정의 엔진
P2R04_DIAGNOSTICS <- c(
  setNames(lapply(names(P2R04_DEVICES), function(h) list(reading = "missing", pair = h, engines = P2R04_DIAG_ENGINE, weight = 0,
                                                          note = "결측 짝(C-016) — DNN 100% + 장치 팩터 · 혼합 가중 0 · 팩터 결측 종목 제외 효과만")), sub("^H", "C", names(P2R04_DEVICES))),
  setNames(lapply(names(P2R04_DEVICES), function(h) list(reading = "capacity", pair = h, engines = c("E2", "E3"), weight_toolbox_on = "E3",
                                                          note = "용량 짝(C-018 · R-20261018-004) — 장치 팩터 몫 = 도구 상자 기본(E3 RX0 base_weight 위 장치 팩터 1회)")), sub("^H", "W", names(P2R04_DEVICES))),
  list(N0 = list(reading = "dilution", pair = NA_character_, engines = P2R04_DIAG_ENGINE, kind = "null_perm", weight_like = list(engine = P2R04_DIAG_ENGINE, component = names(P2R04_DEVICES)[1]),
                 note = "희석 짝(C-021) — 무작위 순열 팩터(null_perm) 몫 = E2 장치 칸의 몫")))
## 용량 읽기 표(C-018 · R-20261018-004 · 사전 고정 · 위에서 아래로 첫 일치 · NA = 상관없음) — 네 칸의 통과(p2_cell_pass): E2 · E3 장치 칸(50%) · E2 · E3 용량 짝(12.5%)
P2R04_CAPACITY_TABLE <- data.table(
  e2_50 = c(TRUE,  TRUE,  TRUE, TRUE,  FALSE, FALSE, FALSE),
  e3_50 = c(TRUE,  TRUE,  TRUE, FALSE, TRUE,  FALSE, FALSE),
  e2_12 = c(TRUE,  FALSE, NA,   NA,    NA,    FALSE, NA),
  e3_12 = c(TRUE,  FALSE, NA,   NA,    NA,    FALSE, NA),
  label = c("같은 처치 두 구성 통과 · 용량 무관(12.5% 도 통과)", "같은 처치 두 구성 통과 · 용량 의존(12.5% 들만 미달)",
            "같은 처치 두 구성 통과(12.5% 엇갈림)", "구성 의존(E2 50% 만 통과 · E3 50% 미달)", "구성 의존(E3 50% 만 통과 · E2 50% 미달)",
            "이 형태 미달(네 칸 모두 미달)", "과용량 의심(희석 과다 — 50% 미달 ∧ 12.5% 통과)"))
P2R04_FULL_AUDIENCE <- "사람 쪽 판정 전용(τ_D 2022-12-31 이후 · 전기간 포함) — 보는 창 리뷰어(철학 P1 · P2 · P4 · 판단 Superfan · 처방 레인) 열람 금지(C-031)"
## 사전등록 final_selection_rule 에 있어야 하는 키(DESIGN §10 — P2R03 와 같은 이름 + ⑭ · 기록 키) · 없으면 평가하지 않는다
P2R04_FS_KEYS <- c("calmar_norm", "port_t_norm", "w_calmar", "w_port_t", "tie_eps", "uc_floor", "majority_share", "crisis_improve_min",
                   "alpha_t_floor", "alpha_margin_frac", "single_name_loss_floor", "bull_ratio", "fast_window_days", "fast_drop",
                   "mc8_label_required", "state_unturned_max_drop_crises")
## 칸 판정 어휘(사전 고정 · p2_cell_verdict 가 이 중 하나만 낸다) · 이 라운드의 이름(C-024 — '방어만 · 복리 없음' = '저변동 기계') ·
##   selection_unmeasured = ③ · ④ 통과인데 ⑭ 가 미측정(MC8 라벨 insufficient · 대조 상태 오류 · 분해 필드 부재 · 깊은 위기 짝 < 2 — 격리 교차 점검 v1 필수 3)
P2R04_VERDICTS <- c("pass", "not_decisive", "exposure_only", "selection_unmeasured", "size_or_exposure_defense", "fast_unmeasured", "beta_unmeasured",
                    "defense_but_strength_or_path", "untested")
P2R04_VERDICT_NAMES <- c(pass = "통과", not_decisive = "결정 미달", exposure_only = "노출 방어(β 짝 미통과)",
                         selection_unmeasured = "선택 귀속 미측정 — 방어 이름 보류",
                         size_or_exposure_defense = "크기 · 노출 방어(⑭ 미통과)", fast_unmeasured = "빠른 급락 미측정", beta_unmeasured = "β 대조 미측정",
                         defense_but_strength_or_path = "저변동 기계(방어만 · 복리 없음)", untested = "미시험")
## 라운드 판정 라벨의 판정어별 칸 수 표기(짧은 이름 · 격리 교차 점검 v1 권고 2 — '결정 대조 미측정'을 반증과 섞지 않게)
P2R04_VERDICT_SHORT <- c(pass = "통과", not_decisive = "결정 미달", exposure_only = "노출 방어", selection_unmeasured = "⑭ 미측정",
                         size_or_exposure_defense = "크기 · 노출 방어", fast_unmeasured = "빠른 급락 미측정", beta_unmeasured = "β 짝 미측정",
                         defense_but_strength_or_path = "저변동 기계", untested = "미시험")
## MC8 귀속 확정 라벨(matched_controls.R mc_attribution nested_majority_placebo_v2) — 이 밖(insufficient · 라벨 없음 · 모르는 값) = ⑭ 미측정
P2R04_MC8_LABELS <- c("selection_defense", "size_defense", "exposure_defense", "no_defense")
## 대조 함수가 있는 운영 핀 종류 — 사전등록에 이 밖의 종류가 있으면 불일치로 센다(대조 없이 통과하지 않는다 · 양성 대조 없는 계기 금지)
P2R04_PIN_KINDS <- c("files", "catalog_entries", "overlay_arms", "factor_registry_entries", "packages", "r_version")
## 보는 창 파일에서 빼는 칸 항목(시험 창 증분 알파 · 판정 표 행 · 셀 로그의 전 구간 셈) · τ_D 이후 날짜 가림 표기
P2R04_VISIBLE_DROP <- c("alpha_test_window", "tbl", "cell_log_full_period")
P2R04_REDACT <- "[τ_D 이후 날짜 가림]"
## RX0 동일성(C-025)의 대조 원천 — P2R03 같은 엔진 RX0 측정 결과(산출물 경로가 든 json · 읽기만)
P2R04_P2R03_RX0 <- "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/results/P2R03_%s_RX0.json"

## 보는 창 밖 작업 사본 표식(격리 교차 점검 v1 권고 7) — 공통 창 사본 · β 짝 사본 폴더는 전기간 수익 · 보유 · authoritative_remeasure.json 사본을 담는다.
##   칸 평가 full/ 표식과 같은 문구(P2R04_FULL_AUDIENCE)를 쓴다 · 상위 폴더(original · common_*)에는 visible* 하위 폴더(보는 창 패킷)만 열람 가능하다는 줄을 덧붙인다
P2R04_FULL_MARK <- "NO_VISIBLE_REVIEW.txt"
P2R04_FULL_MARK_PARENT <- "이 폴더의 visible* 하위 폴더(보는 창 패킷)만 보는 창 리뷰어 열람 가능 — artifacts · rx0_artifacts · rx0_beta_scaled = 전기간 사본(열람 금지)"
.p2_mark_full <- function(dir, note = NULL) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(c(P2R04_FULL_AUDIENCE, note), file.path(dir, P2R04_FULL_MARK), useBytes = TRUE)
  invisible(dir)
}

## ── 순수 도우미(픽스처 검사 대상 · 계약 호출 없음) ─────────────────────────────
.p2_rows_dt <- function(x) if (is.data.frame(x)) as.data.table(x) else if (!length(x)) data.table() else
  rbindlist(lapply(x, function(r) as.data.table(lapply(r, function(v) if (is.null(v) || !length(v)) NA else v[[1]]))), fill = TRUE)
.p2_key <- function(x) paste(as.character(x$peak_date), as.character(x$trough_date))
## 과반(majority_share — '비율이 이 값을 넘어야 과반') — 위기 · 깊은 위기 · β 짝 · 빠른 급락 · 강세 구간 · 사이클 · 회복 · 크기 × β 판정이 이 한 줄을 쓴다 · 비유한 = 거짓
p2_maj <- function(share, maj) { s <- suppressWarnings(as.numeric(share)); m <- suppressWarnings(as.numeric(maj))
  length(s) == 1L && length(m) == 1L && is.finite(s) && is.finite(m) && s > m }
## 공통 창 사본 — P2R03 p2_trim_artifacts 그대로(02 · 03 · 05 는 start 이후 · 04 는 start 이하 마지막 리밸부터 · NAV · 벤치 재기준 · 나머지 복사)
p2_trim_artifacts <- function(src_dir, out_dir, start) {
  start <- as.Date(start)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(src_dir, full.names = TRUE)) if (!dir.exists(f) && !grepl("^0[2-5]_.*[.]csv$", basename(f))) file.copy(f, out_dir, overwrite = TRUE)
  rd <- function(n, tick = FALSE) { p <- file.path(src_dir, n)
                                    x <- if (tick) fread(p, colClasses = list(character = "ticker")) else fread(p)
                                    x[, date := as.Date(date)]; x }
  pr <- rd("03_period_returns.csv")[date >= start]
  br <- rd("05_benchmark_returns.csv")[date >= start]
  nv <- rd("02_nav.csv")[date >= start]
  H  <- rd("04_holdings.csv", tick = TRUE)
  h0 <- suppressWarnings(max(H$date[H$date <= start]))
  H  <- H[date >= (if (is.finite(h0)) h0 else start)]
  if (!nrow(pr) || !nrow(nv) || !nrow(br)) stop("[p2_trim] start ", format(start), " 이후 행이 없다: ", src_dir)
  setorder(nv, date); setorder(br, date)
  if ("nav_net" %in% names(nv)) {
    g0 <- if ("nav_gross" %in% names(nv)) nv$nav_gross[1] else NA_real_; n0 <- nv$nav_net[1]
    nv[, nav_net := nav_net / n0]
    if ("nav_gross" %in% names(nv)) nv[, nav_gross := nav_gross / g0]
    if ("cum_cost" %in% names(nv) && "nav_gross" %in% names(nv)) nv[, cum_cost := nav_gross - nav_net]
    if ("drawdown_net" %in% names(nv)) nv[, drawdown_net := nav_net / cummax(nav_net) - 1]
  }
  if ("benchmark_nav" %in% names(br) && "benchmark_ret" %in% names(br)) br[, benchmark_nav := cumprod(1 + benchmark_ret)]
  for (z in list(list(pr, "03_period_returns.csv"), list(br, "05_benchmark_returns.csv"), list(nv, "02_nav.csv"), list(H, "04_holdings.csv")))
    fwrite(z[[1]], file.path(out_dir, z[[2]]))
  .p2_mark_full(out_dir)                                                         # 공통 창 사본(시작 이후 전 구간) — 보는 창 리뷰어 열람 금지 표식
  invisible(list(start = start, holdings_from = if (is.finite(h0)) h0 else start, n_pr = nrow(pr)))
}
## β 짝 사본(헌장 빈칸 8 · P2R03 그대로) — 기준 칸의 기간수익 · NAV 를 k(< 1)배 노출로(잔여 1−k = 현금 · 수익 0) · 보유 비중도 k 배 ·
##   벤치 · 나머지 파일은 그대로. 같은 계약(dp_build)으로 패킷을 만들어 'β 만 낮춘 기준'과 비교한다.
p2_beta_scaled_copy <- function(src_dir, out_dir, k) {
  if (!is.finite(k) || k <= 0 || k > 1) stop("[p2_beta] k 는 (0, 1]: ", k)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(src_dir, full.names = TRUE)) if (!dir.exists(f) && !grepl("^0[234]_.*[.]csv$", basename(f))) file.copy(f, out_dir, overwrite = TRUE)
  pr <- fread(file.path(src_dir, "03_period_returns.csv")); pr[, date := as.Date(date)]; setorder(pr, date)
  rc <- intersect(c("ret_net", "ret_gross", "ret"), names(pr))
  for (cn in rc) set(pr, j = cn, value = k * pr[[cn]])
  nv <- fread(file.path(src_dir, "02_nav.csv")); nv[, date := as.Date(date)]; setorder(nv, date)
  if ("nav_net" %in% names(nv) && "ret_net" %in% names(pr)) {
    m <- match(nv$date, pr$date); r <- pr$ret_net[m]; r[!is.finite(r)] <- 0
    nv[, nav_net := nav_net[1] * cumprod(1 + r)]
    if ("nav_gross" %in% names(nv)) { rg <- if ("ret_gross" %in% names(pr)) pr$ret_gross[m] else r; rg[!is.finite(rg)] <- 0; nv[, nav_gross := nav_gross[1] * cumprod(1 + rg)] }
    if ("cum_cost" %in% names(nv) && "nav_gross" %in% names(nv)) nv[, cum_cost := nav_gross - nav_net]
    if ("drawdown_net" %in% names(nv)) nv[, drawdown_net := nav_net / cummax(nav_net) - 1]
  }
  H <- fread(file.path(src_dir, "04_holdings.csv"), colClasses = list(character = "ticker"))
  for (cn in intersect(c("target_weight", "actual_weight"), names(H))) set(H, j = cn, value = k * as.numeric(H[[cn]]))
  fwrite(pr, file.path(out_dir, "03_period_returns.csv")); fwrite(nv, file.path(out_dir, "02_nav.csv")); fwrite(H, file.path(out_dir, "04_holdings.csv"))
  .p2_mark_full(dir = out_dir)                                                   # β 짝 사본(전 구간) — 보는 창 리뷰어 열람 금지 표식
  invisible(list(k = k, n_pr = nrow(pr)))
}
## β 짝 계획(헌장 빈칸 8) — k = 변형 β / RX0 β(보는 창 behavior.stats.beta) · 0 < k < 1 = RX0 를 k 배 노출로 낮춘 사본 · k ≥ 1 = 사본 = RX0 ·
##   k 비유한 · k ≤ 0 · RX0 β ≤ 0 = 미측정('β 대조 미측정' = 통과 불가). force_k = 리허설 전용(본 실행은 비운다)
p2_beta_plan <- function(beta_v, beta_r, force_k = NULL) {
  bv <- suppressWarnings(as.numeric(beta_v)); br <- suppressWarnings(as.numeric(beta_r))
  k <- if (!is.null(force_k)) suppressWarnings(as.numeric(force_k))[1] else
    if (length(bv) == 1L && length(br) == 1L && is.finite(bv) && is.finite(br) && br > 0) bv / br else NA_real_
  mode <- if (!is.finite(k) || k <= 0) "unmeasured" else if (k >= 1) "rx0" else "scaled"
  list(k = k, mode = mode, forced = !is.null(force_k),
       comparator = switch(mode, rx0 = "RX0(k ≥ 1)", scaled = "RX0 × k", unmeasured = "미측정"))
}
## 크기 × β 짝 계획(C-017) — k = 변형 β / 크기 바스켓 β(같은 계약 월 β) · k < 1 = 바스켓을 k 배로 낮추고 나머지 현금 · k ≥ 1 = 바스켓 그대로(차입하지 않는다)
p2_size_beta_plan <- function(beta_v, beta_b) {
  bv <- suppressWarnings(as.numeric(beta_v)); bb <- suppressWarnings(as.numeric(beta_b))
  k <- if (length(bv) == 1L && length(bb) == 1L && is.finite(bv) && is.finite(bb) && bb > 0) bv / bb else NA_real_
  mode <- if (!is.finite(k) || k <= 0) "unmeasured" else if (k < 1) "scaled" else "basket"
  list(k = k, scale = if (identical(mode, "unmeasured")) NA_real_ else min(k, 1), mode = mode)
}
## 위기 짝 비율 — metric 이 기준 − tol 보다 낮은 위기의 비율 · subset = 판정에 쓸 위기 키(NULL = 짝 전부) — P2R03 그대로
p2_crisis_majority <- function(cr_m, cr_r, tol, metric = "dd_capture", subset = NULL) {
  cm <- .p2_rows_dt(cr_m); cr <- .p2_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !(metric %in% names(cm)) || !(metric %in% names(cr)))
    return(list(n_pair = 0L, n_better = 0L, share = NA_real_, unpaired = nrow(cm) + nrow(cr)))
  cm[, k := .p2_key(cm)]; cr[, k := .p2_key(cr)]
  J <- merge(cm[, .(k, m = as.numeric(get(metric)))], cr[, .(k, r = as.numeric(get(metric)))], by = "k")
  unp <- (nrow(cm) - nrow(J)) + (nrow(cr) - nrow(J))
  if (!is.null(subset)) J <- J[k %in% subset]
  J <- J[is.finite(m) & is.finite(r)]
  nb <- sum(J$m < J$r - tol)
  list(n_pair = nrow(J), n_better = nb, share = if (nrow(J)) nb / nrow(J) else NA_real_, unpaired = unp, per_crisis = J)
}
## 크기 × β 짝 판정 부분(C-017) — 깊은 위기에서 변형 dd_capture < 사본 − tol 인 위기 과반(짝 ≥ 2) · 결론 이름 규칙 입력(통과 조건 아님)
p2_size_beta_core <- function(cr_v, cr_c, deep, tol, maj) {
  mj <- p2_crisis_majority(cr_v, cr_c, tol, "dd_capture", subset = deep)
  list(n_pair = mj$n_pair, n_better = mj$n_better, share = mj$share, ok = mj$n_pair >= 2L && p2_maj(mj$share, maj),
       status_pairs = if (mj$n_pair >= 2L) "ok" else "unmeasured(짝 < 2)", per_crisis = mj$per_crisis)
}
## 시장 대비 기준점(C-024) — 위기 dd_capture < 1 − tol 인 위기 비율(벤치의 하락 포착 = 정의상 1 · matched_controls s_bm 과 같은 기준) · subset = 위기 키
p2_vs_market <- function(cr, tol, subset = NULL) {
  D <- .p2_rows_dt(cr)
  if (!nrow(D) || !all(c("peak_date", "trough_date", "dd_capture") %in% names(D))) return(list(n = 0L, n_better = 0L, share = NA_real_))
  D[, k := .p2_key(D)]
  if (!is.null(subset)) D <- D[k %in% subset]
  v <- as.numeric(D$dd_capture); v <- v[is.finite(v)]
  list(n = length(v), n_better = sum(v < 1 - tol), share = if (length(v)) mean(v < 1 - tol) else NA_real_)
}
## 깊은 위기 — 두 칸 모두에 있는 위기 중 벤치 낙폭(bm_dd) 크기가 그 집합 중앙값 이상인 위기의 키 — P2R03 그대로
p2_deep_crisis_keys <- function(cr_m, cr_r) {
  cm <- .p2_rows_dt(cr_m); cr <- .p2_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !("bm_dd" %in% names(cr))) return(character(0))
  cm[, k := .p2_key(cm)]; cr[, k := .p2_key(cr)]
  J <- cr[k %in% cm$k, .(k, depth = abs(as.numeric(bm_dd)))][is.finite(depth)]
  if (!nrow(J)) return(character(0))
  J[depth >= stats::median(depth), k]
}
## 빠른 급락(헌장 빈칸 6 · Mishkin & White 2002 NBER WP 8992 p.7 · P2R03 그대로) — 위기 [고점, 저점] 안에서 벤치가 win 거래일 창 안에 drop 이상 하락한
##   구간이 있는 위기의 키. br = 같은 칸 산출물의 벤치 일수익(date · benchmark_ret) · 수준 = 누적곱(창 안 비율은 종가 비율과 같다).
##   위기 고점 · 저점이 벤치 날짜에 없으면 그 위기는 분류 못 함(unclassified — 빠름 집합에 넣지 않는다 · 기록).
p2_fast_crash_keys <- function(br, crises, win = 21L, drop = -0.20) {
  b <- as.data.table(br)[, .(date = as.Date(date), r = as.numeric(benchmark_ret))][order(date)]
  b[!is.finite(r), r := 0]; lvl <- cumprod(1 + b$r)
  me <- b[, .(d = max(date)), by = .(ym = format(date, "%Y-%m"))]$d                # 월말 거래일(월간 리밸의 신호일)
  cr <- .p2_rows_dt(crises)
  if (!nrow(cr) || !nrow(b)) return(list(keys = character(0), table = data.table(), unclassified = character(0), no_month_end = character(0)))
  rows <- lapply(seq_len(nrow(cr)), function(i) {
    i0 <- match(as.Date(as.character(cr$peak_date[i])), b$date); i1 <- match(as.Date(as.character(cr$trough_date[i])), b$date)
    k <- .p2_key(cr[i])
    if (is.na(i0) || is.na(i1) || i1 < i0) return(data.table(k = k, max_drop = NA_real_, fast = NA, seg_start = as.Date(NA), seg_end = as.Date(NA), month_ends_inside = NA_integer_))
    best <- 0; sa <- i0; se <- i0
    for (a in i0:i1) { e <- min(i1, a + as.integer(win)); j <- which.min(lvl[a:e]); v <- lvl[a + j - 1L] / lvl[a] - 1
                       if (v < best) { best <- v; sa <- a; se <- a + j - 1L } }
    data.table(k = k, max_drop = best, fast = best <= drop + 1e-12,                  # 1e-12 = 부동소수 여유(결정 수치 아님 — 정확히 −20% 경계)
               seg_start = b$date[sa], seg_end = b$date[se], month_ends_inside = sum(me >= b$date[i0] & me < b$date[i1]))
  })
  T <- rbindlist(rows)
  list(keys = T[fast %in% TRUE, k], table = T, unclassified = T[is.na(fast), k], win = as.integer(win), drop = drop,
       no_month_end = T[fast %in% TRUE & month_ends_inside %in% 0L, k])               # 위기 안 월말 0 — 일화 단위 판에서 뺀다(C-047 · 2008-11)
}
## 강세 구간별 참여(헌장 빈칸 7 · P2R03 그대로) — 두 칸의 강세 국면을 (start_ym, end_ym) 으로 짝짓고, 변형 상승 포착 ≥ 기준 − (1 − ratio) × |기준| 인
##   구간 비율(양수 기준이면 '기준의 ratio 이상' · 음수 기준이면 기준보다 |기준|×(1−ratio) 까지 나빠도 됨 — 기준을 이기라고 요구하지 않는다).
##   짝 < min_pairs 이면 비율 NA(미시험)
p2_bull_segments <- function(bull_m, bull_r, ratio = 0.8, min_pairs = 2L) {
  bm <- .p2_rows_dt(bull_m); br <- .p2_rows_dt(bull_r)
  need <- c("start_ym", "end_ym", "up_capture")
  if (!nrow(bm) || !nrow(br) || !all(need %in% names(bm)) || !all(need %in% names(br)))
    return(list(n_pair = 0L, n_ok = 0L, share = NA_real_, unpaired = nrow(bm) + nrow(br)))
  bm[, k := paste(start_ym, end_ym)]; br[, k := paste(start_ym, end_ym)]
  J <- merge(bm[, .(k, m = as.numeric(up_capture))], br[, .(k, r = as.numeric(up_capture))], by = "k")
  unp <- (nrow(bm) - nrow(J)) + (nrow(br) - nrow(J))
  J <- J[is.finite(m) & is.finite(r)]
  J[, thr := r - (1 - ratio) * abs(r)][, ok := m >= thr]
  list(n_pair = nrow(J), n_ok = sum(J$ok), share = if (nrow(J) >= min_pairs) mean(J$ok) else NA_real_, unpaired = unp,
       ratio = ratio, min_pairs = as.integer(min_pairs), per_phase = J)
}
## β 비대칭(헌장 빈칸 3 · 8) — 하락장 β < 상승장 β · 비유한 = NA(미시험)
p2_beta_asym <- function(beta_down, beta_up) {
  bd <- suppressWarnings(as.numeric(beta_down)); bu <- suppressWarnings(as.numeric(beta_up))
  if (length(bd) != 1L || length(bu) != 1L || !is.finite(bd) || !is.finite(bu)) return(NA)
  bd < bu
}
## β 비대칭의 변화량(⑤ 장치 검증 · 철학 P1 C-20261017-044) — 하락/상승 β 비가 같은 엔진 RX0 보다 낮아지는가. 비는 정적 축소(β 짝 사본 = k 배)에
##   불변이라 변화량만이 장치가 만든 비대칭이다. 상승장 β ≤ 0 · 비유한 = NA(미시험)
p2_beta_ratio_delta <- function(bd_v, bu_v, bd_r, bu_r) {
  x <- suppressWarnings(as.numeric(c(bd_v, bu_v, bd_r, bu_r)))
  if (length(x) != 4L || any(!is.finite(x)) || x[2] <= 0 || x[4] <= 0) return(list(ratio = NA_real_, ratio_rx0 = NA_real_, delta = NA_real_, ok = NA))
  rv <- x[1] / x[2]; rr <- x[3] / x[4]
  list(ratio = rv, ratio_rx0 = rr, delta = rv - rr, ok = rv < rr)
}
## 사이클 짝 · 사이클 복리 — P2R03 그대로(직전 위기 바닥 연월 이후 시작 · 이 위기 고점 연월까지 끝난 강세 중 마지막 · 강세 1회 사용 · 짝 2 미만 NA)
p2_cycle_pairs <- function(bull, crises) {
  b <- .p2_rows_dt(bull); cr <- .p2_rows_dt(crises)
  emp <- data.table(k = character(0), bull = character(0), b_st = numeric(0), c_st = numeric(0))
  if (!nrow(cr)) return(list(pairs = emp, unpaired = character(0)))
  cr[, k := .p2_key(cr)][, pym := substr(as.character(peak_date), 1, 7)][, tym := substr(as.character(trough_date), 1, 7)]
  cr <- cr[order(as.character(peak_date))]
  if (nrow(b)) b[, bid := paste(start_ym, end_ym)][, s := as.character(start_ym)][, e := as.character(end_ym)]
  used <- character(0); rows <- list(); unp <- character(0)
  for (i in seq_len(nrow(cr))) {
    lo <- if (i > 1L) cr$tym[i - 1L] else ""
    cand <- if (nrow(b)) b[s >= lo & e <= cr$pym[i] & !(bid %in% used)] else b
    if (!nrow(cand)) { unp <- c(unp, cr$k[i]); next }
    p <- cand[order(e, s)][.N]
    used <- c(used, p$bid)
    rows[[length(rows) + 1L]] <- data.table(k = cr$k[i], bull = p$bid, b_st = as.numeric(p$st_cum), c_st = as.numeric(cr$st_cum[i]))
  }
  list(pairs = if (length(rows)) rbindlist(rows) else emp, unpaired = unp)
}
p2_cycle_compound <- function(bull_m, cr_m, bull_r, cr_r, min_pairs = 2L) {
  pm <- p2_cycle_pairs(bull_m, cr_m); pr <- p2_cycle_pairs(bull_r, cr_r)
  M <- pm$pairs[, .(k, bull, cyc = (1 + b_st) * (1 + c_st) - 1)]
  R <- pr$pairs[, .(k, bull, cyc = (1 + b_st) * (1 + c_st) - 1)]
  K <- merge(M[, .(k, bull)], R[, .(k, bull)], by = c("k", "bull"))
  J <- merge(M, R, by = c("k", "bull"), suffixes = c("_m", "_r"))[is.finite(cyc_m) & is.finite(cyc_r)]
  list(n_pair = nrow(J), n_ge = sum(J$cyc_m >= J$cyc_r), share = if (nrow(J) >= min_pairs) mean(J$cyc_m >= J$cyc_r) else NA_real_,
       min_pairs = as.integer(min_pairs), unpaired_crises = sort(unique(c(pm$unpaired, pr$unpaired))),
       pair_mismatch = (nrow(M) - nrow(K)) + (nrow(R) - nrow(K)), per_cycle = J)
}
## 집중 손실(헌장 빈칸 1) — P2R03 그대로(깊은 위기가 표에 빠지면 partial → 미측정 · 0 으로 접지 않는다)
p2_top_loss <- function(top_losers, deep_peaks, floor) {
  TL <- .p2_rows_dt(top_losers)
  if (!nrow(TL) || !all(c("peak_date", "contrib") %in% names(TL)))
    return(list(status = "unmeasured", n_breach = NA_integer_, missing_deep = as.character(deep_peaks)))
  TL[, contrib := as.numeric(contrib)][, peak_date := as.character(peak_date)]
  per <- TL[is.finite(contrib), .(top1 = min(contrib), top3 = sum(sort(contrib)[seq_len(min(3L, .N))])), by = peak_date]
  deep <- per[peak_date %in% as.character(deep_peaks)]
  miss <- setdiff(as.character(deep_peaks), per$peak_date)
  list(status = if (length(miss)) "partial" else "ok", per_crisis = per, n_breach = sum(deep$top1 < floor), missing_deep = miss,
       deep_top1_min = if (nrow(deep)) min(deep$top1) else NA_real_)
}
p2_conc_status <- function(tl) if (isTRUE(tl$n_breach > 0L)) "breach" else if (identical(tl$status, "ok")) "clear" else "unmeasured"
## 알파 비열등(헌장 빈칸 4C) — t > t_floor ∧ 증분 ≥ −margin_frac × max(엔진 α, 0)(엔진 α ≤ 0 이면 감소 허용 0) · 입력 NA → NA
p2_alpha_ok <- function(pa_vis, t_floor, engine_alpha, margin_frac) {
  t <- suppressWarnings(as.numeric(pa_vis$t)); d <- suppressWarnings(as.numeric(pa_vis$d_alpha)); ea <- suppressWarnings(as.numeric(engine_alpha))
  if (!length(t) || !length(d) || !is.finite(t) || !is.finite(d) || !length(ea) || !is.finite(ea)) return(NA)
  (t > t_floor) && (d >= -margin_frac * max(ea, 0))
}
## 회복 지연 꼬리표(헌장 빈칸 5 · 판정 보조) — 두 칸 모두의 위기에서 변형의 회복 관측(거래일 · 미회복이면 관측 하한)이 RX0 보다 긴 위기 비율이 과반
p2_recovery_tag <- function(cr_m, cr_r, maj) {
  cm <- .p2_rows_dt(cr_m); cr <- .p2_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !("st_recovery_obs" %in% names(cm)) || !("st_recovery_obs" %in% names(cr)))
    return(list(status = "unmeasured", tag = FALSE))
  cm[, k := .p2_key(cm)]; cr[, k := .p2_key(cr)]
  if (!"st_recovery_censored" %in% names(cm)) cm[, st_recovery_censored := NA]
  if (!"st_recovery_censored" %in% names(cr)) cr[, st_recovery_censored := NA]
  J <- merge(cm[, .(k, m = as.numeric(st_recovery_obs), mc = as.logical(st_recovery_censored))],
             cr[, .(k, r = as.numeric(st_recovery_obs), rc = as.logical(st_recovery_censored))], by = "k")
  ## 미회복(검열) 위기 — 관측이 비었어도 '아직 회복 못 함' = 관측 하한 무한대로 비교한다 · 둘 다 미회복 = 비교 불가(제외)
  J[, `:=`(m = fifelse(!is.finite(m) & mc %in% TRUE, Inf, m), r = fifelse(!is.finite(r) & rc %in% TRUE, Inf, r))]
  J <- J[!is.na(m) & !is.na(r) & !(is.infinite(m) & is.infinite(r))]
  if (!nrow(J)) return(list(status = "unmeasured", tag = FALSE))
  sh <- mean(J$m > J$r)
  list(status = "ok", n_pair = nrow(J), n_longer = sum(J$m > J$r), share = sh, tag = p2_maj(sh, maj), n_censored_variant = sum(is.infinite(J$m)), per_crisis = J)
}
## 셀 로그 적재 줄(⑩ 구성 증거) — rf_cell_engine 의 마지막 요약 줄 '[rf_cell_engine] cell=<code> | univ=<u> | factors=<id+id…|none> | wt=<w> | months=N | rows=M'
##   (팩터 결합 · 패널 병합이 끝난 뒤에 찍힌다 — 패널이 비면 그 전에 멈춘다). 여러 줄이면 마지막 줄. months · rows 는 전 구간 셈이라 보는 창 파일에 싣지 않는다
p2_parse_cell_log <- function(lines) {
  lines <- sub("\r$", "", as.character(lines))
  rx <- "^\\[rf_cell_engine\\] cell=([^ |]+) \\| univ=([^ |]+) \\| factors=([^ |]+) \\| wt=([^ |]+) \\| months=([0-9]+) \\| rows=([0-9]+)[[:space:]]*$"
  s <- grep(rx, lines, value = TRUE)
  if (!length(s)) return(list(found = FALSE, n_lines = 0L))
  n <- length(s); s <- s[n]
  g <- function(i) sub(rx, paste0("\\", i), s)
  fs <- g(3L)
  list(found = TRUE, n_lines = n, cell = g(1L), univ = g(2L), factors = if (identical(fs, "none")) character(0) else strsplit(fs, "+", fixed = TRUE)[[1]],
       wt = g(4L), months = as.integer(g(5L)), rows = as.integer(g(6L)))
}
## 팩터 방향 경로 줄(기록) — factor_db_connector align_factor_direction 이 load_month_factors 1회(신호일 1 · 팩터 1)마다 'PIT-safe: sig_date=…' 다음
##   'loaded-factor direction: IC-inferred=a / registry-fallback=b / default-fallback=c (n_factors=n)' 를 찍는다. 셀 엔진은 사양 순서대로 팩터마다 전
##   신호일을 돈다 → 신호일이 되돌아가면 다음 팩터(블록). 장치 팩터 = 마지막 블록(사양 factors 끝)
p2_parse_direction_lines <- function(lines) {
  lines <- sub("\r$", "", as.character(lines))
  rs <- "^\\[align_factor_direction\\] PIT-safe: sig_date=([0-9]{4}-[0-9]{2}-[0-9]{2}).*$"
  rd <- "^\\[align_factor_direction\\] loaded-factor direction: IC-inferred=([0-9]+) / registry-fallback=([0-9]+) / default-fallback=([0-9]+) \\(n_factors=([0-9]+)\\).*$"
  is_s <- grepl(rs, lines); is_d <- grepl(rd, lines)
  emp <- data.table(block = integer(0), sig_date = as.Date(character(0)), ic = integer(0), reg = integer(0), def = integer(0), n = integer(0))
  cur <- NA_character_; prev <- as.Date(NA); blk <- 0L; out <- list()
  for (i in which(is_s | is_d)) {
    if (is_s[i]) { cur <- sub(rs, "\\1", lines[i]); next }
    if (is.na(cur)) next
    d <- as.Date(cur); cur <- NA_character_
    if (is.na(prev) || d <= prev) blk <- blk + 1L
    prev <- d
    v <- as.integer(regmatches(lines[i], regexec(rd, lines[i]))[[1]][2:5])
    out[[length(out) + 1L]] <- data.table(block = blk, sig_date = d, ic = v[1], reg = v[2], def = v[3], n = v[4])
  }
  if (length(out)) rbindlist(out) else emp
}
## 장치 팩터 방향 경로(기록 · 판정 아님) — 장치 블록의 신호일 중 평가 창(창 시작에 유효한 신호일 ~ τ_D)에서 방향을 IC 로 정한 신호일 · 레지스트리 대체 ·
##   기본 대체 · 데이터 없음 셈. 레지스트리 대체는 원값과 표기가 어긋나 공격 쪽으로 뒤집힐 수 있다(_design_notes/defense_direction_agreement.md) → 꼬리표
p2_direction_record <- function(D, block, from, tau) {
  D <- as.data.table(D)
  if (!nrow(D)) return(list(status = "absent"))
  nb <- max(D$block); b0 <- suppressWarnings(as.integer(block))
  if (length(b0) != 1L || is.na(b0) || b0 < 1L || b0 > nb) return(list(status = "block_mismatch", n_blocks = nb, block = b0))
  x <- D[block == b0 & sig_date <= as.Date(tau)]
  if (!is.null(from) && length(from) && !is.na(from)) {
    f0 <- suppressWarnings(max(x$sig_date[x$sig_date <= as.Date(from)]))
    if (is.finite(f0)) x <- x[sig_date >= f0]
  }
  if (!nrow(x)) return(list(status = "empty", n_blocks = nb, block = b0))
  alt <- sum(x$reg > 0L | x$def > 0L)
  list(status = "ok", n_blocks = nb, block = b0, n_sig = nrow(x), ic_inferred = sum(x$ic > 0L), registry_fallback = sum(x$reg > 0L),
       default_fallback = sum(x$def > 0L), no_data = sum(x$n == 0L), first = format(min(x$sig_date)), last = format(max(x$sig_date)),
       tag = if (alt > 0L) sprintf("팩터 방향 대체 경로 %d 신호일(평가 창) — 레지스트리 표기는 원값과 어긋나 공격 쪽일 수 있다(defense_direction_agreement.md)", alt) else NA_character_)
}
## 사양 factors 의 꼬리 — 마지막 항목(kind · id)과 끝에서부터 그와 같은 항목이 연속한 수 m · 그 앞(바탕) id. 장치 몫을 키우려 같은 항목을 반복 나열한다
##   (E3 50% = RX0 3팩터 + 장치 6회 · base_weight 0.25 · R-20261018-004). 꼬리는 장치와 무관하게 정한다(장치 대조는 사양 대조 한 곳에서만 — 세 대조 비중복)
.p2_spec_tail <- function(spec_factors) {
  ids <- vapply(spec_factors %||% list(), function(f) as.character(f$id %||% NA_character_), character(1))
  kds <- vapply(spec_factors %||% list(), function(f) as.character(f$kind %||% NA_character_), character(1))
  n <- length(ids)
  if (!n) return(list(ids = ids, kinds = kds, m = 0L, base = character(0), tail_id = NA_character_, tail_kind = NA_character_))
  same <- !is.na(ids) & !is.na(kds) & ids == ids[n] & kds == kds[n]
  r <- rle(rev(same)); m <- if (isTRUE(r$values[1])) r$lengths[1] else 0L
  list(ids = ids, kinds = kds, m = as.integer(m), base = utils::head(ids, n - m), tail_id = ids[n], tail_kind = kds[n])
}
## ⑩ 구성 증거(사양 · 셀 로그) — 서로 겹치지 않는 세 대조:
##   사양  = 변형 사양 factors 꼬리 항목 = 장치 항목(kind · id) · m ≥ 1 회 연속 ∧ 그 앞(바탕)에는 장치 팩터 없음 ∧ RX0 사양 factors = 바탕(DESIGN §10 'RX0 + 장치 팩터')
##   변형 로그 = 적재 줄 있음 ∧ cell = 그 칸 ∧ 적재 팩터 = 변형 사양 factors(장치 팩터 적재)
##   RX0 로그 = 적재 줄 있음 ∧ cell = RX0 칸 ∧ 적재 팩터 = 바탕(장치 팩터 없음)
p2_construction_check <- function(lv, lr, dev, spec_v, spec_r, expect_cell, expect_cell_rx0) {
  tv <- .p2_spec_tail(spec_v); sid_v <- tv$ids; base_v <- tv$base
  sid_r <- vapply(spec_r %||% list(), function(f) as.character(f$id %||% NA_character_), character(1))
  okS <- tv$m >= 1L && identical(tv$tail_id, dev$id) && identical(tv$tail_kind, dev$kind) && !((dev$id %||% "") %in% base_v) && identical(sid_r, base_v)
  okV <- isTRUE(lv$found) && identical(lv$cell, expect_cell) && identical(lv$factors, sid_v)
  okR <- isTRUE(lr$found) && identical(lr$cell, expect_cell_rx0) && identical(lr$factors, base_v)
  pj <- function(x) if (length(x)) paste(x, collapse = "+") else "none"
  why <- c(if (!okS) sprintf("사양: 변형 factors %s · RX0 factors %s · 장치 %s:%s 꼬리 %d회(변형 = RX0 + 장치 팩터 꼬리여야 함)", pj(sid_v), pj(sid_r),
                             dev$kind %||% "?", dev$id %||% "?", tv$m),
           if (!okV) sprintf("변형 로그: 적재 줄 %s · cell %s(기대 %s) · 적재 %s(기대 %s)", isTRUE(lv$found), lv$cell %||% "-", expect_cell, pj(lv$factors), pj(sid_v)),
           if (!okR) sprintf("RX0 로그: 적재 줄 %s · cell %s(기대 %s) · 적재 %s(기대 %s)", isTRUE(lr$found), lr$cell %||% "-", expect_cell_rx0, pj(lr$factors), pj(base_v)))
  keep <- c("found", "n_lines", "cell", "univ", "factors", "wt")
  list(ok = okS && okV && okR, why = if (length(why)) paste(why, collapse = " / ") else NA_character_,
       checks = list(spec = okS, variant_log = okV, rx0_log = okR), device = dev[c("kind", "id")], device_count = tv$m, spec_factors = sid_v, rx0_spec_factors = sid_r,
       variant_log = lv[intersect(names(lv), keep)], rx0_log = lr[intersect(names(lr), keep)])
}
## 혼합 가중(기록 · 진단 칸 대조) — rf_cell_engine §4 Score = w0·z_base + (1−w0)·mean(z_factors)(w0 = base_weight) → 장치 팩터 몫 = (1 − w0) × m / n
##   (m = 장치 항목 반복 수 · n = 팩터 수) · w0 없으면 rowMeans(기저 + 팩터) = m / (1 + n). E2 = (1 − 0.5)·1/1 = 0.5 · E3 = (1 − 0.25)·6/9 = 0.5 ·
##   도구 상자 기본(E3 RX0 위 1회) = (1 − 0.5)·1/4 = 0.125
p2_blend_weight <- function(base_weight, n_factors, n_device = 1L) {
  w0 <- suppressWarnings(as.numeric(base_weight %||% NA))[1]; n <- as.integer(n_factors); m <- as.integer(n_device)
  bad <- !length(n) || is.na(n) || n < 1L || !length(m) || is.na(m) || m < 1L || m > n
  dw <- if (bad) NA_real_ else if (is.finite(w0)) (1 - w0) * m / n else m / (1 + n)
  ## 구성 몫(기록) — DNN(기저) 몫 · 기존 팩터 몫(장치 아닌 팩터) · 장치 몫의 합 = 1
  ds <- if (bad) NA_real_ else if (is.finite(w0)) w0 else 1 / (1 + n)
  os <- if (bad) NA_real_ else if (is.finite(w0)) (1 - w0) * (n - m) / n else (n - m) / (1 + n)
  list(base_weight = w0, n_factors = n, n_device = m, device_weight = dw, dnn_share = ds, other_share = os,
       rule = "rf_cell_engine.R §4 Score = w0·z_base + (1−w0)·mean(z_factors)")
}
## 두 몫의 비를 작은 정수 비로(표시용 · 결정 수치 아님) — 1:1 · 4:3 처럼 · 분모 20 안에 정확한 정수 비가 없으면 소수 · 한쪽 0 = '기존 팩터 없음'
p2_ratio_str <- function(a, b) {
  a <- suppressWarnings(as.numeric(a))[1]; b <- suppressWarnings(as.numeric(b))[1]
  if (!length(a) || !length(b) || !is.finite(a) || !is.finite(b)) return(NA_character_)
  if (b <= 0) return("기존 팩터 없음")
  r <- a / b
  for (q in seq_len(20L)) { p <- round(r * q); if (p >= 1 && abs(p / q - r) < 1e-9) return(sprintf("%d:%d", as.integer(p), q)) }
  sprintf("%.3f:1", r)
}
## 진단 칸의 장치 항목 — 결측 · 용량 짝 = 짝 장치의 팩터 · 희석 짝 = 사양 끝 항목이 null_perm(seed 유한)일 때 그 항목(아니면 NULL = 미시험)
p2_diag_device <- function(comp, spec_factors) {
  dg <- P2R04_DIAGNOSTICS[[comp]]
  if (is.null(dg)) return(NULL)
  if (!is.na(dg$pair %||% NA_character_)) return(P2R04_DEVICES[[dg$pair]])
  f <- utils::tail(spec_factors %||% list(), 1L)
  if (!length(f)) return(NULL)
  f <- f[[1]]; sd0 <- suppressWarnings(as.numeric(f$seed %||% NA))
  if (!identical(f$kind, dg$kind) || is.null(f$id) || length(sd0) != 1L || !is.finite(sd0)) return(NULL)
  list(kind = dg$kind, id = as.character(f$id), name = "무작위 순열(희석 짝)")
}
## 진단 칸 기대 장치 몫(사양에서 재도출 · 숫자를 박지 않는다) — weight(고정 · 결측 짝 0) · weight_toolbox_on(그 엔진 RX0 사양 base_weight 위 장치 팩터 1회 =
##   도구 상자 기본) · weight_like(그 판정 칸 사양의 장치 몫). cells = 사전등록 칸 목록(판정 칸에서 찾는다) · 못 구하면 NA(= 진단 칸 미시험)
p2_diag_expect_weight <- function(comp, cells, root) {
  dg <- P2R04_DIAGNOSTICS[[comp]]                                                # ★ [[ ]] 정확 일치 — `$weight` 는 weight_toolbox_on · weight_like 에 부분 일치한다
  if (is.null(dg)) return(NA_real_)
  if (!is.null(dg[["weight"]])) return(as.numeric(dg[["weight"]]))
  sp_of <- function(eng, cp) { z <- Filter(function(c0) identical(c0$engine, eng) && identical(c0$component, cp) && !isTRUE(c0$diagnostic), cells)
                               if (length(z)) tryCatch(fromJSON(file.path(root, z[[1]]$path), simplifyVector = FALSE), error = function(e) NULL) else NULL }
  if (!is.null(dg[["weight_toolbox_on"]])) {
    s <- sp_of(dg[["weight_toolbox_on"]], "RX0"); if (is.null(s)) return(NA_real_)
    return(p2_blend_weight(s$base_weight, length(s$factors %||% list()) + 1L, 1L)$device_weight)
  }
  wl <- dg[["weight_like"]]; s <- sp_of(wl$engine, wl$component); dev <- P2R04_DEVICES[[wl$component]]
  if (is.null(s) || is.null(dev)) return(NA_real_)
  tv <- .p2_spec_tail(s$factors)
  if (!identical(tv$tail_id, dev$id) || !identical(tv$tail_kind, dev$kind)) return(NA_real_)
  p2_blend_weight(s$base_weight, length(tv$ids), tv$m)$device_weight
}
## 보유 대조(⑩ 구성 증거 · 기록 '보유 겹침률' 월별 요약) — 보는 창(date ≤ τ)에서 두 칸 모두 보유가 있는 보유일마다 이름 겹침 |V∩R|/max(|V|,|R|) ·
##   비중 겹침 Σ min(ŵ_V, ŵ_R)(보유 안 정규화 — 1 − active share) · 다름 = 종목 집합이 다르거나 비중이 하나라도 다름(엔진 결정론 — 같은 입력이면 비트 동일).
##   한쪽에만 있는 보유일은 다름으로 세지 않는다(결측은 처치가 아니다 · 따로 센다)
p2_holdings_overlap <- function(H_var, H_rx0, tau) {
  tau <- as.Date(tau)
  pick <- function(H) { H <- as.data.table(H); if (!nrow(H) || !all(c("date", "ticker", "w") %in% names(H))) return(data.table(date = as.Date(character(0)), ticker = character(0), w = numeric(0)))
                        H[is.finite(w) & w > 0 & as.Date(date) <= tau, .(w = sum(w)), by = .(date = as.Date(date), ticker = as.character(ticker))] }
  hv <- pick(H_var); hr <- pick(H_rx0)
  if (!nrow(hv) || !nrow(hr)) return(list(status = "unmeasured", n_dates = 0L, n_differ = NA_integer_))
  dv <- sort(unique(hv$date)); dr <- sort(unique(hr$date)); dd <- dv[dv %in% dr]
  if (!length(dd)) return(list(status = "unmeasured", n_dates = 0L, n_differ = NA_integer_, n_only_variant = length(dv), n_only_rx0 = length(dr)))
  P <- rbindlist(lapply(as.list(dd), function(d) {
    a <- hv[date == d]; b <- hr[date == d]; u <- union(a$ticker, b$ticker)
    wa <- setNames(a$w, a$ticker)[u]; wa[is.na(wa)] <- 0; wb <- setNames(b$w, b$ticker)[u]; wb[is.na(wb)] <- 0
    data.table(date = d, n_var = nrow(a), n_rx0 = nrow(b), name_overlap = length(intersect(a$ticker, b$ticker)) / max(nrow(a), nrow(b)),
               weight_overlap = sum(pmin(wa / sum(wa), wb / sum(wb))), differ = !setequal(a$ticker, b$ticker) || any(wa != wb))
  }))
  list(status = "ok", n_dates = nrow(P), n_differ = sum(P$differ), share_differ = mean(P$differ),
       n_only_variant = sum(!(dv %in% dr)), n_only_rx0 = sum(!(dr %in% dv)),
       name_overlap_mean = mean(P$name_overlap), name_overlap_median = stats::median(P$name_overlap), name_overlap_min = min(P$name_overlap),
       weight_overlap_mean = mean(P$weight_overlap), weight_overlap_median = stats::median(P$weight_overlap), weight_overlap_min = min(P$weight_overlap),
       window = c(format(min(P$date)), format(max(P$date))), per_date = P)
}
## ⑩ 처치 전달 — 보는 창 보유가 RX0 와 다른 보유일 ≥ 1(무처치 = 미시험)
p2_treatment_delivered <- function(ov) identical(ov$status, "ok") && isTRUE(ov$n_differ > 0L)
## ⑭ 선택 귀속(라벨) — 변형 칸 보는 창 패킷의 MC8 귀속 라벨이 사전등록 요구 라벨과 같아야 통과. 라벨이 확정 라벨(P2R04_MC8_LABELS) 밖(insufficient = 위기 2 미만 ·
##   라벨 없음 · 모르는 값)이거나 대조 상태(controls.status)가 ok 가 아니면(no_holdings · no_basket · no_crises · not_applicable_long_short · 오류) = 미측정
##   (통과 불가 · 라벨 그대로 기록 · 격리 교차 점검 v1 필수 3) · 규칙 없음 = no_rule(통과 불가)
p2_selection_attr <- function(label, required, controls_status = "ok") {
  lb <- as.character(label %||% NA_character_)[1]; rq <- as.character(unlist(required) %||% NA_character_)[1]
  cs <- as.character(controls_status %||% NA_character_)[1]
  st <- if (is.na(rq) || !nzchar(rq)) "no_rule" else if (!identical(cs, "ok")) "unmeasured" else if (is.na(lb) || !(lb %in% P2R04_MC8_LABELS)) "unmeasured" else "ok"
  list(label = lb, required = rq, controls_status = cs, status = st, ok = identical(st, "ok") && identical(lb, rq))
}
## ⑭ 위기 분해(C-028) — 진단 패킷 exposure.crises 의 위기별 'selection_sum'(tilt_attribution 사전 적재 기계: 활성 = 시장 β + 동일가중−시총가중(크기) +
##   무신호 틸트 + 선택 + 비용 — β · 크기를 함께 통제한 뒤의 선택 항 · 위기 일간 기여의 산술합)이 깊은 위기에서 변형 − RX0 > 0(엄격 부등호 · 문턱 없음)인
##   위기 비율이 과반(> majority_share · 짝 ≥ 2). ★문턱을 두지 않는다 — selection_sum 은 수익 단위(일간 기여의 합)이고 crisis_improve_min 0.03 은 낙폭 포착
##   비율(dd_capture) 단위라 이 합에 쓸 근거가 없다(격리 교차 점검 v1 필수 1 · 조정자 결정 2026-10-18). 필드가 없거나 비거나 깊은 위기 짝 < 2 = 미측정(통과 불가)
p2_selection_decomp <- function(ex_v, ex_r, deep_peaks, maj) {
  V <- .p2_rows_dt(ex_v); R <- .p2_rows_dt(ex_r); need <- c("peak_date", "selection_sum")
  if (!nrow(V) || !nrow(R) || !all(need %in% names(V)) || !all(need %in% names(R)))
    return(list(status = "unmeasured", tag = "선택 항 분해 미측정(패킷 exposure.crises.selection_sum 없음)", n_pair = 0L, share = NA_real_, ok = FALSE))
  J <- merge(V[, .(peak_date = as.character(peak_date), sv = as.numeric(selection_sum))], R[, .(peak_date = as.character(peak_date), sr = as.numeric(selection_sum))], by = "peak_date")
  J <- J[peak_date %in% as.character(deep_peaks) & is.finite(sv) & is.finite(sr)]
  if (nrow(J) < 2L) return(list(status = "unmeasured", tag = "선택 항 분해 미측정(깊은 위기 짝 < 2)", n_pair = nrow(J), share = NA_real_, ok = FALSE, per_crisis = J))
  J[, better := sv - sr > 0]
  list(status = "ok", tag = NA_character_, n_pair = nrow(J), n_better = sum(J$better), share = mean(J$better), ok = p2_maj(mean(J$better), maj),
       rule = "깊은 위기마다 selection_sum 변형 − RX0 > 0(엄격 · 문턱 없음 — 수익 단위) · 과반 > majority_share · 짝 ≥ 2", per_crisis = J)
}
## ⑭ 통과 = MC8 라벨 일치 ∧ 위기 분해 과반 — 둘 다 기록 · 상태는 먼저 걸린 쪽 · measured = 두 부분 모두 측정됨(아니면 '⑭ 미측정' — 판정어 selection_unmeasured)
p2_selection_rule <- function(attr, decomp) {
  st <- if (!identical(attr$status, "ok")) attr$status else if (!identical(decomp$status, "ok")) "unmeasured(선택 항 분해)" else "ok"
  c(attr[c("label", "required")], list(label_status = attr$status, label_ok = isTRUE(attr$ok), controls_status = attr$controls_status %||% NA_character_,
                                       decomposition = decomp, status = st, measured = identical(st, "ok"),
                                       ok = isTRUE(attr$ok) && isTRUE(decomp$ok)))
}
## 기록용 위기(state_unturned_max_drop_crises — '상태 미전환 최대 하락 위기' · C-019) — 위기마다 짝 여부 · 깊음 · 빠름 · 하락 포착(변형 · RX0 · β 짝 사본) ·
##   RX0 · β 짝을 tol 넘게 이겼나
p2_crisis_record <- function(cr_m, cr_r, cr_b, keys, tol, deep = character(0), fast = character(0)) {
  keys <- as.character(unlist(keys))
  if (!length(keys)) return(data.table())
  kv <- function(x) { D <- .p2_rows_dt(x); if (!nrow(D) || !all(c("peak_date", "trough_date", "dd_capture") %in% names(D))) return(setNames(numeric(0), character(0)))
                      setNames(as.numeric(D$dd_capture), .p2_key(D)) }
  M <- kv(cr_m); R <- kv(cr_r); B <- kv(cr_b)
  at <- function(v, k) if (k %in% names(v)) unname(v[[k]]) else NA_real_
  rbindlist(lapply(keys, function(k) {
    m <- at(M, k); r <- at(R, k); b <- at(B, k)
    data.table(crisis = k, in_pairs = is.finite(m) && is.finite(r), deep = k %in% deep, fast = k %in% fast,
               dd_capture = m, dd_capture_rx0 = r, dd_capture_beta_copy = b,
               beats_rx0 = if (is.finite(m) && is.finite(r)) m < r - tol else NA, beats_beta_copy = if (is.finite(m) && is.finite(b)) m < b - tol else NA)
  }))
}
## 위기 중 보유의 크기 분위(기록 · 패킷 exposure.by_size_decile — 위기 시작일 as-of 시가총액 분위 1~10 · n = 그 위기에 든 종목 수) — 위기별 종목 가중 평균 분위
p2_size_profile <- function(bsd) {
  B <- .p2_rows_dt(bsd)
  if (!nrow(B) || !all(c("size_decile", "n", "peak_date") %in% names(B))) return(data.table())
  B[, `:=`(peak_date = as.character(peak_date), size_decile = suppressWarnings(as.numeric(size_decile)), n = as.numeric(n))]
  B[, .(n_names = sum(n), n_unknown = sum(n[!is.finite(size_decile)]),
        mean_decile = if (any(is.finite(size_decile))) sum((size_decile * n)[is.finite(size_decile)]) / sum(n[is.finite(size_decile)]) else NA_real_), by = peak_date]
}
p2_size_compare <- function(bsd_v, bsd_r, deep_peaks = character(0)) {
  V <- p2_size_profile(bsd_v); R <- p2_size_profile(bsd_r)
  if (!nrow(V)) return(list(status = "absent"))
  J <- if (nrow(R)) merge(V, R, by = "peak_date", all.x = TRUE, suffixes = c("", "_rx0")) else copy(V)[, `:=`(n_names_rx0 = NA_real_, n_unknown_rx0 = NA_real_, mean_decile_rx0 = NA_real_)]
  dm <- function(v) { v <- v[is.finite(v)]; if (length(v)) mean(v) else NA_real_ }
  list(status = "ok", per_crisis = J, deep_mean_decile = dm(J[peak_date %in% as.character(deep_peaks), mean_decile]),
       deep_mean_decile_rx0 = dm(J[peak_date %in% as.character(deep_peaks), mean_decile_rx0]))
}
## 유동성 분위(C-020 기록) — 20일 평균 거래대금(t−1 · 셀 엔진 .adv20_l1 과 같은 정의)의 그날 측정 유니버스 10분위(진단 패킷 크기 분위와 같은 경계 규약) · 유니버스 10 미만 = NA
p2_liq_deciles <- function(x, univ) {
  u <- suppressWarnings(as.numeric(univ)); u <- u[is.finite(u)]; x <- suppressWarnings(as.numeric(x))
  if (length(u) < 10L) return(rep(NA_integer_, length(x)))
  bp <- stats::quantile(u, probs = seq_len(9) / 10, names = FALSE, type = 7)
  ifelse(is.finite(x), findInterval(x, bp) + 1L, NA_integer_)
}
## 국면별 월 차이(C-020 · 늘 켜진 틸트의 횡보 세금) — 월 분류 = 위기(고점 월 ~ 저점 월) 우선 → 강세 구간(start_ym ~ end_ym) → 그 밖 · d = 변형 − RX0 월 수익
.p2_months <- function(a, b) { a <- suppressWarnings(as.Date(paste0(substr(a, 1, 7), "-01"))); b <- suppressWarnings(as.Date(paste0(substr(b, 1, 7), "-01")))
  if (!length(a) || !length(b) || is.na(a) || is.na(b) || b < a) character(0) else format(seq(a, b, by = "month"), "%Y-%m") }
p2_regime_diff <- function(ym, d, crises, bulls) {
  cr <- .p2_rows_dt(crises); bl <- .p2_rows_dt(bulls)
  cm <- if (nrow(cr)) unique(unlist(lapply(seq_len(nrow(cr)), function(i) .p2_months(as.character(cr$peak_date[i]), as.character(cr$trough_date[i]))))) else character(0)
  bm <- if (nrow(bl) && all(c("start_ym", "end_ym") %in% names(bl))) unique(unlist(lapply(seq_len(nrow(bl)), function(i) .p2_months(as.character(bl$start_ym[i]), as.character(bl$end_ym[i]))))) else character(0)
  D <- data.table(ym = as.character(ym), d = suppressWarnings(as.numeric(d)))[is.finite(d)]
  D[, cls := fifelse(ym %in% cm, "crisis", fifelse(ym %in% bm, "bull", "other"))]
  one <- function(c0) { v <- D[cls == c0, d]; list(n = length(v), mean = if (length(v)) mean(v) else NA_real_) }
  list(n_months = nrow(D), crisis = one("crisis"), bull = one("bull"), other = one("other"),
       rule = "월 분류 = 위기(고점 월 ~ 저점 월) 우선 → 강세 구간(start_ym ~ end_ym) → 그 밖 · 차이 = 변형 − RX0 월 수익(계약 bc_monthly)")
}
## RX0 동일성(C-025 기록) — 보는 창 보유(보유일별 집합 · 비중) · 순수익(일별 ret_net 정확 비교 → 다른 달 수)만 센다(값은 싣지 않는다)
p2_rx0_identity_core <- function(H4, H3, pr4, pr3, tau) {
  tau <- as.Date(tau)
  ov <- p2_holdings_overlap(H4, H3, tau)
  a <- as.data.table(pr4)[as.Date(date) <= tau, .(date = as.Date(date), r4 = as.numeric(ret_net))]
  b <- as.data.table(pr3)[as.Date(date) <= tau, .(date = as.Date(date), r3 = as.numeric(ret_net))]
  J <- merge(a, b, by = "date")
  M <- if (nrow(J)) J[, .(diff = any(xor(is.na(r4), is.na(r3)) | (!is.na(r4) & !is.na(r3) & r4 != r3))), by = .(ym = format(date, "%Y-%m"))] else data.table(ym = character(0), diff = logical(0))
  hs <- identical(ov$status, "ok") && identical(ov$n_differ, 0L) && identical(as.integer(ov$n_only_variant), 0L) && identical(as.integer(ov$n_only_rx0), 0L)
  only <- (nrow(a) - nrow(J)) + (nrow(b) - nrow(J))
  list(holdings_same = hs, holdings_dates = ov$n_dates, holdings_dates_differ = ov$n_differ,
       holdings_dates_only_p2r04 = ov$n_only_variant %||% NA_integer_, holdings_dates_only_p2r03 = ov$n_only_rx0 %||% NA_integer_,
       returns_same = nrow(M) > 0L && !any(M$diff) && only == 0L, months_compared = nrow(M), months_differ = sum(M$diff), days_only_one_side = only)
}
## 칸 통과(사전 고정) = ① ∧ ② ∧ ③ ∧ ④ ∧ ⑤ ∧ ⑥ ∧ ⑦ ∧ ⑨ ∧ ⑩ ∧ ⑫ ∧ ⑬ ∧ ⑭(⑧ = 장치 검증 제외 · ⑪ = 꼬리표)
p2_cell_pass <- function(f) {
  isTRUE(f$crisis) && isTRUE(f$deep) && isTRUE(f$beta_deep) && isTRUE(f$fast) && isTRUE(f$beta_ratio) && isTRUE(f$bull) &&
    isTRUE(f$alpha) && isTRUE(f$cycle) && isTRUE(f$construction) && isTRUE(f$S) && isTRUE(f$path) && isTRUE(f$selection)
}
## 칸 판정 어휘(사전 고정 · 위에서 아래로 첫 해당):
##   pass · beta_unmeasured(β 사본 실패 · ③ 짝 < 2) · fast_unmeasured(③ 통과 · ④ 짝 < 2) · exposure_only(① ② 통과 · ③ 미통과) ·
##   selection_unmeasured(③ ④ 통과 · ⑭ 미측정 — 방어 이름 보류 · 통과 불가 · 격리 교차 점검 v1 필수 3) ·
##   size_or_exposure_defense(③ ④ 통과 · ⑭ 측정됨 · 미통과 — 크기 방어 또는 노출 방어) · defense_but_strength_or_path(① ~ ④ · ⑭ 통과 · 나머지 미달 — 이 라운드
##   이름 '저변동 기계' · C-024) · not_decisive(그 밖) · untested 는 판정 전 실패(.p2_untested). f$selection_measured = ⑭ 두 부분(라벨 · 분해) 모두 측정됨
p2_cell_verdict <- function(f) {
  r3 <- f$beta_deep %||% NA; r4 <- f$fast %||% NA; s14 <- isTRUE(f$selection); m14 <- isTRUE(f$selection_measured)
  dec <- isTRUE(f$crisis) && isTRUE(f$deep) && isTRUE(r3) && isTRUE(r4)
  if (isTRUE(f$pass)) "pass" else
  if (isTRUE(f$beta_unmeasured) || is.na(r3)) "beta_unmeasured" else
  if (is.na(r4) && isTRUE(r3)) "fast_unmeasured" else
  if (isTRUE(f$crisis) && isTRUE(f$deep) && !isTRUE(r3)) "exposure_only" else
  if (isTRUE(r3) && isTRUE(r4) && !m14) "selection_unmeasured" else
  if (isTRUE(r3) && isTRUE(r4) && !s14) "size_or_exposure_defense" else
  if (dec && s14) "defense_but_strength_or_path" else "not_decisive"
}
## 결론 이름(DESIGN §8.2 + C-017 이름 규칙 · 판정 아님) — '방어'는 ③ ∧ ④ ∧ ⑤(수준) ∧ ⑭ 일 때만 · 그 위에 크기 × β 짝까지 넘을 때만 '선택(특성) 방어'.
##   미측정(③ · ④ NA · ⑤ 수준 NA · ⑭ 미측정 · 크기 × β 미측정)은 기전 이름으로 접지 않고 '보류'로 둔다(실패 의미 고정 — NA = 미측정 꼬리표)
p2_defense_name <- function(r3, r4, level, s14, sb_ok, sb_status, s14_measured = TRUE) {
  if (is.na(r3 %||% NA) || is.na(r4 %||% NA)) return("방어 이름 보류(③ · ④ β 짝 미측정)")
  if (!isTRUE(r3) || !isTRUE(r4)) return("방어 이름 없음(③ · ④ β 짝 미통과)")
  if (is.na(level %||% NA)) return("방어 이름 보류(⑤ 수준 미측정)")
  if (!isTRUE(level)) return("노출(β) 방어(⑤ 수준 역행 — 하락 β ≥ 상승 β)")
  if (!isTRUE(s14_measured)) return("방어 이름 보류(⑭ 선택 귀속 미측정)")
  if (!isTRUE(s14)) return("크기 방어 또는 노출 방어(⑭ 미통과)")
  if (!identical(sb_status, "ok")) return("방어(크기 × β 짝 미측정 — '선택(특성) 방어' 이름 보류)")
  if (!isTRUE(sb_ok)) return("크기 × β 방어(크기 × β 짝 미통과 — '선택(특성) 방어' 이름 불가)")
  "선택(특성) 방어"
}
## 라운드 판정 — 장치 × 엔진 표(tested · pass · excluded = 집중 손실 · 집중 손실 미측정 · verdict = 칸 판정어). supported = 두 엔진 통과 ∧ 제외 아님인 장치 ≥ 1 ·
##   label = '판정(판정 칸/전체 칸 · 판정어별 칸 수)' — 표에 verdict 열이 있으면 판정어별 칸 수를 붙여 '결정 대조 미측정'(β 짝 · 빠른 급락 · ⑭)이 반증과
##   섞여 보이지 않게 한다(격리 교차 점검 v1 권고 2 · 예 'falsified(판정 8/8 · β 짝 미측정 8)'). 진단 칸은 이 표에 들지 않는다
p2_verdict_counts <- function(v) {
  v <- as.character(v[!is.na(v)])
  if (!length(v)) return("")
  k <- c(intersect(P2R04_VERDICTS, unique(v)), setdiff(unique(v), P2R04_VERDICTS))
  paste(vapply(k, function(z) sprintf("%s %d", if (z %in% names(P2R04_VERDICT_SHORT)) P2R04_VERDICT_SHORT[[z]] else z, sum(v == z)), character(1)), collapse = " · ")
}
p2_round_verdict <- function(TB) {
  nt <- nrow(TB); nj <- if (nt) sum(TB$tested) else 0L
  vc <- if (nt && "verdict" %in% names(TB)) p2_verdict_counts(TB$verdict) else ""
  lab <- function(v) if (nzchar(vc)) sprintf("%s(판정 %d/%d · %s)", v, as.integer(nj), as.integer(nt), vc) else sprintf("%s(판정 %d/%d)", v, as.integer(nj), as.integer(nt))
  if (!nt || !any(TB$tested))
    return(list(verdict = "untested", label = lab("untested"), n_judged = nj, n_total = nt, both = character(0), one = character(0), excluded = character(0),
                verdict_counts = vc))
  if (!"excluded" %in% names(TB)) TB[, excluded := FALSE]
  agg <- TB[, .(n_pass = sum(tested & pass), ex = any(excluded & pass)), by = device]
  both <- agg[n_pass == 2L & !ex, device]; one <- agg[n_pass == 1L, device]; exc <- agg[n_pass == 2L & ex, device]
  v <- if (length(both)) "supported" else if (length(one) || length(exc)) "partial" else "falsified"
  list(verdict = v, label = lab(v), n_judged = nj, n_total = nt, both = both, one = one, excluded = exc, verdict_counts = vc)
}
## 최종 선택 — 검증 장치 중 보는 창 S 의 RX0 대비 증분(두 엔진 평균)이 가장 큰 1개 · 동률(최대와의 차 < tie)이면 ③ · ④ 비율 합(두 엔진 평균) — P2R03 그대로
p2_select <- function(xs_by_device, tie = 1e-12) {
  if (!length(xs_by_device)) return(list())
  sc <- lapply(names(xs_by_device), function(dv) {
    xs <- xs_by_device[[dv]]
    list(device = dv, dS = mean(vapply(xs, function(x) as.numeric(x$non_inferiority$S - x$non_inferiority$S_rx0), numeric(1))),
         r34 = mean(vapply(xs, function(x) as.numeric((x$rules$beta_deep$share %||% NA) + (x$rules$fast$share %||% NA)), numeric(1))))
  })
  dS <- vapply(sc, `[[`, numeric(1), "dS"); r34 <- vapply(sc, `[[`, numeric(1), "r34")
  top <- is.finite(dS) & (max(dS, na.rm = TRUE) - dS) < tie                     # tie = 부동소수 여유(결정 수치 아님)
  o <- order(!top, -ifelse(top, r34, dS), -dS)
  sc <- sc[o]
  if (sum(top) >= 2L) sc[[1]]$tie_break <- "r34"
  sc
}
## ── 진단 읽기(판정 아님 · 보는 창) ──
##   위기별 승리 = 같은 짝 표(k · m · r)에서 m < r − tol. a 가 이긴 위기 중 b 도 이긴 위기(both) · b 는 그 위기를 못 이김(a_only) · b 표에 그 위기가 없음(unknown)
.p2_wins <- function(D, tol) { D <- as.data.table(D %||% data.table()); if (!nrow(D) || !all(c("k", "m", "r") %in% names(D))) return(NULL)
                               D[is.finite(m) & is.finite(r) & m < r - tol, k] }
p2_read_overlap_wins <- function(a_pc, b_pc, tol) {
  wa <- .p2_wins(a_pc, tol)
  if (is.null(wa)) return(list(status = "unmeasured", n_a = NA_integer_, both = character(0), a_only = character(0), unknown = character(0)))
  wb <- .p2_wins(b_pc, tol); kb <- if (is.null(wb)) character(0) else as.character(as.data.table(b_pc)$k)
  list(status = if (is.null(wb)) "b_unmeasured" else "ok", n_a = length(wa), both = intersect(wa, wb %||% character(0)),
       a_only = setdiff(intersect(wa, kb), wb %||% character(0)), unknown = setdiff(wa, kb))
}
## (a) 결측 짝(C-016) — 장치 Hk 의 깊은 위기 β 짝 승리 위기마다 Ck 도 그 위기에서 β 짝을 이겼나 → 둘 다 = '결측 패턴 방어' · Hk ③ 승리 중 결측 패턴 아닌 위기 수
p2_read_missing <- function(h, c0, tol) {
  if (!isTRUE(h$tested)) return(list(status = "unmeasured", why = "장치 칸 미시험"))
  if (!isTRUE(c0$tested)) return(list(status = "unmeasured", why = paste("결측 짝 미시험:", c0$why %||% "칸 없음")))
  ov <- p2_read_overlap_wins(h$rules$beta_deep$per_crisis, c0$rules$beta_deep$per_crisis, tol)
  list(status = ov$status, device = h$device, diag_cell = c0$cell %||% NA_character_, n_win = ov$n_a, missing_pattern = ov$both, n_missing_pattern = length(ov$both),
       not_missing = ov$a_only, n_not_missing = length(ov$a_only), unknown = ov$unknown,
       tag = if (length(ov$both)) sprintf("결측 패턴 방어 %d/%s 위기(β 짝 승리 중 결측 짝도 이김)", length(ov$both), format(ov$n_a)) else NA_character_)
}
## (b) 용량 짝(C-018 · R-20261018-004) — E2 · E3 장치 칸(50%) · E2 · E3 용량 짝(12.5%) 네 칸의 통과(p2_cell_pass)를 사전 고정 표(P2R04_CAPACITY_TABLE)에 대본다.
##   가중 대조: 두 장치 칸 몫이 같고(같은 처치) 두 용량 짝 몫이 같고 용량 짝 < 장치 칸이어야 읽는다(아니면 '미측정(가중 불일치)') · 미시험 칸 = '미측정'
p2_capacity_label <- function(e2_50, e3_50, e2_12, e3_12, table = P2R04_CAPACITY_TABLE) {
  x <- c(e2_50 = e2_50, e3_50 = e3_50, e2_12 = e2_12, e3_12 = e3_12)
  if (length(x) != 4L || anyNA(x)) return(NA_character_)
  for (i in seq_len(nrow(table))) {
    pat <- unlist(table[i, .(e2_50, e3_50, e2_12, e3_12)])
    if (all(is.na(pat) | pat == x)) return(table$label[i])
  }
  NA_character_
}
p2_read_capacity <- function(e2h, e3h, e2w, e3w) {
  f <- function(x) if (isTRUE(x$tested)) isTRUE(x$pass) else NA
  w <- function(x) suppressWarnings(as.numeric(x$construction$blend$device_weight %||% NA))[1]
  W <- c(e2_50 = w(e2h), e3_50 = w(e3h), e2_12 = w(e2w), e3_12 = w(e3w))
  wok <- all(is.finite(W)) && abs(W[["e2_50"]] - W[["e3_50"]]) < 1e-9 && abs(W[["e2_12"]] - W[["e3_12"]]) < 1e-9 && W[["e2_12"]] < W[["e2_50"]]   # 1e-9 = 부동소수 여유
  P <- c(e2_50 = f(e2h), e3_50 = f(e3h), e2_12 = f(e2w), e3_12 = f(e3w))
  lab <- if (anyNA(P)) "미측정(네 칸 중 미시험)" else if (!wok) "미측정(가중 불일치 — 같은 처치 50% · 12.5% 구성 아님)" else
         p2_capacity_label(P[["e2_50"]], P[["e3_50"]], P[["e2_12"]], P[["e3_12"]]) %||% "미측정(표 밖)"
  ## 구성 차이 혼재(격리 교차 점검 v1 권고 6) — E3 용량 짝 W 는 방어 몫만이 아니라 DNN : 기존 팩터 비도 장치 칸과 다르다(사양에서 재도출 · E2 W 는 DNN 만 줄인 순수 대비)
  cmp <- function(x) { b <- x$construction$blend; if (is.null(b)) NA_character_ else p2_ratio_str(b$dnn_share, b$other_share) }
  r50 <- cmp(e3h); r12 <- cmp(e3w)
  note <- if (!is.na(r50) && !is.na(r12) && !identical(r50, r12))
    sprintf("E3 용량 짝 W 는 방어 몫 외에 DNN : 기존 팩터 비율도 %s → %s 로 바뀐다(구성 차이 혼재 — 용량 읽기는 이 차이를 함께 읽는다)", r50, r12) else NA_character_
  list(passes = as.list(P), weights = as.list(W), weights_ok = wok, label = lab, e3_composition = c(e3_50 = r50, e3_12 = r12), composition_note = note,
       verdicts = c(e2_50 = e2h$verdict %||% NA_character_, e3_50 = e3h$verdict %||% NA_character_, e2_12 = e2w$verdict %||% NA_character_, e3_12 = e3w$verdict %||% NA_character_))
}
## (c) 희석 짝(C-021) — Hk 의 ① 개선 위기(RX0 − tol 미만) 중 N0 도 개선한 위기 = '희석 몫'
p2_read_dilution <- function(h, n0, tol) {
  if (!isTRUE(h$tested)) return(list(status = "unmeasured", why = "장치 칸 미시험"))
  if (!isTRUE(n0$tested)) return(list(status = "unmeasured", why = paste("희석 짝 미시험:", n0$why %||% "칸 없음")))
  ov <- p2_read_overlap_wins(h$rules$crisis$per_crisis, n0$rules$crisis$per_crisis, tol)
  list(status = ov$status, device = h$device, n_improve = ov$n_a, dilution_share = ov$both, n_dilution = length(ov$both),
       not_dilution = ov$a_only, n_not_dilution = length(ov$a_only), unknown = ov$unknown,
       tag = if (length(ov$both)) sprintf("희석 몫 %d/%s 위기(① 개선 중 무작위 순열 팩터도 개선)", length(ov$both), format(ov$n_a)) else NA_character_)
}
p2_diag_summary <- function(x) if (!isTRUE(x$tested)) list(tested = FALSE, why = x$why %||% NA_character_) else
  list(tested = TRUE, verdict = x$verdict, treatment_delivered = x$treatment_delivered %||% NA,
       crisis = list(share = x$rules$crisis$share, ok = x$rules$crisis$ok), deep = list(share = x$rules$deep$share, ok = x$rules$deep$ok),
       beta_deep = list(status = x$rules$beta_deep$status, share = x$rules$beta_deep$share, ok = x$rules$beta_deep$ok))
## 진단 읽기 묶음 — OUT(판정 칸) · DOUT(진단 칸) 의 칸 결과(engine · device = 부품 이름)에서 장치마다 (a)(b)(c) + 희석 짝 ① · ② · ③ 요약
p2_readings <- function(OUT, DOUT, tol, devices = names(P2R04_DEVICES), diag_engine = P2R04_DIAG_ENGINE) {
  fnd <- function(L, eng, comp) { z <- Filter(function(x) identical(x$engine, eng) && identical(x$device, comp), L); if (length(z)) z[[1]] else list(tested = FALSE, why = "칸 없음") }
  cof <- function(rd, h) { z <- names(Filter(function(d) identical(d$reading, rd) && identical(d$pair, h), P2R04_DIAGNOSTICS)); if (length(z)) z[1] else NA_character_ }
  engs <- unique(vapply(OUT, function(x) as.character(x$engine %||% NA_character_), character(1)))
  other <- setdiff(engs[!is.na(engs)], diag_engine)[1]
  oe <- if (length(other) && !is.na(other)) other else ""
  n0c <- names(Filter(function(d) identical(d$reading, "dilution"), P2R04_DIAGNOSTICS))[1]
  n0 <- fnd(DOUT, diag_engine, n0c)
  list(diag_engine = diag_engine, other_engine = if (nzchar(oe)) oe else NA_character_,
       missing = setNames(lapply(devices, function(h) p2_read_missing(fnd(OUT, diag_engine, h), fnd(DOUT, diag_engine, cof("missing", h)), tol)), devices),
       capacity = setNames(lapply(devices, function(h) p2_read_capacity(fnd(OUT, diag_engine, h), fnd(OUT, oe, h),
                                                                         fnd(DOUT, diag_engine, cof("capacity", h)), fnd(DOUT, oe, cof("capacity", h)))), devices),
       dilution = list(n0 = p2_diag_summary(n0), by_device = setNames(lapply(devices, function(h) p2_read_dilution(fnd(OUT, diag_engine, h), n0, tol)), devices)))
}
## A 거리(C-031 기록 · 판정 아님) — 보는 창 gv3 A 하한(CAGR ≥ cagr_min · Sharpe ≥ sharpe_min · Calmar ≥ 같은 창 벤치 Calmar · PORT_t ≥ port_t_b · grade_v3
##   gv3_thresholds = tier_graduation 정본)과 S ≥ a_boundary 의 값 · 문턱 · 거리(값 − 문턱 · 양수 = 충족). 값 = 보는 창 패킷 performance(gv3_window 계약 산출)
p2_a_distance <- function(perf, bench_calmar, th, S = NA_real_, a_boundary = NA_real_) {
  v <- function(k) suppressWarnings(as.numeric(perf[[k]] %||% NA))[1]
  one <- function(x, t) { x <- suppressWarnings(as.numeric(x))[1]; t <- suppressWarnings(as.numeric(t))[1]
                          list(value = x, threshold = t, distance = x - t, meets = is.finite(x) && is.finite(t) && x >= t) }
  list(cagr = one(v("cagr"), th$cagr_min), sharpe = one(v("sharpe"), th$sharpe_min), calmar = one(v("calmar"), bench_calmar),
       port_t = one(v("port_t"), th$port_t_b), S = one(S, a_boundary))
}
## R7 판독(C-029 · lean-loop 예산 — 'S · 위기 방어 개선이 잡음 이내')
##   판정된 장치 = 두 구성(E2 · E3) 모두에서 tested ∧ ③(β 짝 깊은 위기)이 측정됨(status ok · 짝 ≥ 2 · 비율 유한) ∧ S 증분 유한인 장치. ③ 미측정(beta_unmeasured 등)인
##   구성이 하나라도 있으면 그 장치는 분모에서 빠진다(③ NA 를 '과반 아님'으로 접어 '잡음 이내'로 새지 않게 — 격리 교차 점검 v2 권고 1 (a) · 조정자 결정 2026-10-18).
##   판정된 장치 < 2 = '판독 불가'(NA — 부분 판정으로 프로그램 예산을 소모하지 않는다 · 2 = 다른 판정의 '짝 ≥ 2' 관례) · 판정된 장치 ≥ 2 면
##   검증 0 ∧ 판정된 장치 중 두 구성 모두 ③ 비율 > majority_share 인 장치 0 ∧ 판정된 장치의 S 증분(두 구성 평균) 최대 < tie_eps = '잡음 이내'(아니면 '잡음 밖').
##   판정된 장치 수 · 빠진 장치와 이유를 함께 싣는다
p2_noise_reading <- function(OUT, validated, tie_eps, maj, devices = names(P2R04_DEVICES)) {
  per <- lapply(devices, function(dv) {
    xs <- Filter(function(x) identical(x$device, dv), OUT)
    tst <- vapply(xs, function(x) isTRUE(x$tested), logical(1))
    st3 <- vapply(xs, function(x) as.character(x$rules$beta_deep$status %||% NA_character_)[1], character(1))
    np3 <- vapply(xs, function(x) suppressWarnings(as.integer(x$rules$beta_deep$n_pair %||% NA))[1], integer(1))
    sh3 <- vapply(xs, function(x) suppressWarnings(as.numeric(x$rules$beta_deep$share %||% NA))[1], numeric(1))
    dS <- vapply(xs, function(x) if (isTRUE(x$tested)) suppressWarnings(as.numeric(x$non_inferiority$S - x$non_inferiority$S_rx0))[1] else NA_real_, numeric(1))
    r3m <- tst & st3 %in% "ok" & !is.na(np3) & np3 >= 2L & is.finite(sh3)                # ③ 측정됨(구성마다)
    judged <- length(xs) == 2L && all(r3m) && all(is.finite(dS))
    why <- if (length(xs) != 2L) sprintf("구성 칸 %d개(2개여야 함)", length(xs)) else if (!all(tst)) "미시험 구성 있음" else
           if (!all(r3m)) sprintf("③ 미측정 구성 있음(%s)", paste(ifelse(is.na(st3), "NA", st3), collapse = " / ")) else if (!all(is.finite(dS))) "S 증분 비유한" else NA_character_
    list(device = dv, n_cells = length(xs), r3_status = unname(st3), r3_share = unname(sh3), r3_measured = unname(r3m), judged = judged, dropped_why = why,
         r3_both = judged && all(vapply(sh3, p2_maj, logical(1), maj = maj)), dS_mean = if (judged) mean(dS) else NA_real_)
  })
  jd <- vapply(per, function(p) isTRUE(p$judged), logical(1)); nb <- sum(jd)
  dmv <- vapply(per, function(p) p$dS_mean, numeric(1))[jd]; n3 <- sum(vapply(per, function(p) isTRUE(p$r3_both), logical(1))[jd])
  dmax <- if (any(is.finite(dmv))) max(dmv[is.finite(dmv)]) else NA_real_
  c1 <- !length(validated); c2 <- n3 == 0L; c3 <- is.finite(dmax) && dmax < as.numeric(tie_eps)
  readable <- nb >= 2L
  res <- if (!readable) NA else c1 && c2 && c3
  dropped <- lapply(per[!jd], function(p) list(device = p$device, why = p$dropped_why))
  list(result = res, label = if (!readable) sprintf("판독 불가(판정된 장치 %d/%d < 2 — 두 구성 tested ∧ ③ 측정)", nb, length(devices)) else if (isTRUE(res)) "잡음 이내" else "잡음 밖",
       judged_devices = sprintf("%d/%d", nb, length(devices)), n_devices_judged_both = nb, n_devices = length(devices),
       judged = vapply(per[jd], function(p) p$device, character(1)), dropped = dropped,
       components = list(no_validated = c1, no_device_r3_both = c2, max_dS_below_tie = c3),
       n_validated = length(validated), n_device_r3_both = n3, max_dS = dmax, tie_eps = as.numeric(tie_eps), per_device = per,
       rule = paste0("R7 판독(C-029) — 판정된 장치(두 구성 tested ∧ ③ 측정 · 짝 ≥ 2 ∧ S 증분 유한) < 2 = 판독 불가 · 아니면 검증 0 ∧ 판정된 장치 중 두 구성 ",
                     "③ 비율 > majority_share 인 장치 0 ∧ 판정된 장치 S 증분(두 구성 평균) 최대 < tie_eps = 잡음 이내"))
}
## 사전등록 final_selection_rule 키 결손
p2_fs_missing <- function(FS) setdiff(P2R04_FS_KEYS, names(FS %||% list()))
## 사전등록 칸 목록 검사(DESIGN §10 + 진단 칸) — code = P2R04_<engine>_<component> · 판정 엔진 2개 · 엔진마다 RX0 1칸 · 부품 ∈ RX0 ∪ 장치 표 ∪ 진단 표 ·
##   reference = (component == RX0) · diagnostic = (component ∈ 진단 표) · 진단 칸은 진단 표의 engines 안에만 · 엔진마다 같은 장치 집합 · 진단 짝 장치가
##   장치 집합 안. 반환 = 문제 설명(없으면 길이 0)
p2_cells_check <- function(cells, devices = P2R04_DEVICES, diags = P2R04_DIAGNOSTICS, diag_engine = P2R04_DIAG_ENGINE) {
  if (!length(cells)) return("칸 없음")
  f <- function(k) vapply(cells, function(z) as.character(z[[k]] %||% NA_character_), character(1))
  cd <- f("code"); en <- f("engine"); cp <- f("component")
  rf <- vapply(cells, function(z) isTRUE(z$reference), logical(1)); dg <- vapply(cells, function(z) isTRUE(z$diagnostic), logical(1))
  bad <- character(0)
  if (anyNA(cd) || anyNA(en) || anyNA(cp)) bad <- c(bad, "code · engine · component 결측")
  if (anyDuplicated(cd)) bad <- c(bad, "code 중복")
  wrong <- !is.na(cd) & cd != paste0("P2R04_", en, "_", cp)
  if (any(wrong)) bad <- c(bad, paste("code ≠ P2R04_<engine>_<component>:", paste(cd[wrong], collapse = ",")))
  if (any(rf != (cp %in% "RX0"))) bad <- c(bad, "reference ≠ (component == RX0)")
  if (any(dg != (cp %in% names(diags)))) bad <- c(bad, "diagnostic ≠ (component ∈ 진단 표)")
  unk <- setdiff(unique(cp[!is.na(cp)]), c("RX0", names(devices), names(diags))); if (length(unk)) bad <- c(bad, paste("장치 · 진단 표에 없는 부품:", paste(unk, collapse = ",")))
  out_eng <- dg & !is.na(cp) & !mapply(function(e, k) isTRUE(e %in% (diags[[k]]$engines %||% character(0))), en, cp)
  if (any(out_eng)) bad <- c(bad, paste("진단 칸이 진단 표 engines 밖:", paste(cd[out_eng], collapse = ",")))
  ue <- unique(en[!is.na(en) & !dg])
  if (length(ue) != 2L) bad <- c(bad, sprintf("판정 엔진 %d개(2개여야 함 — 장치 검증 = 두 엔진 통과)", length(ue)))
  for (e in ue) { ce <- cp[en %in% e & !dg]; if (sum(ce %in% "RX0") != 1L) bad <- c(bad, sprintf("%s RX0 %d칸(1칸이어야 함)", e, sum(ce %in% "RX0")))
                  if (anyDuplicated(ce)) bad <- c(bad, sprintf("%s 부품 중복", e)) }
  ds <- unique(lapply(ue, function(e) sort(setdiff(cp[en %in% e & !dg], "RX0"))))
  if (length(ds) > 1L) bad <- c(bad, "엔진마다 장치 집합이 다르다")
  dset <- if (length(ds)) ds[[1]] else character(0)
  pr <- unique(unlist(lapply(cp[dg & !is.na(cp)], function(k) diags[[k]]$pair %||% NA_character_)))
  pr <- pr[!is.na(pr)]
  if (length(setdiff(pr, dset))) bad <- c(bad, paste("진단 짝 장치가 판정 장치 집합 밖:", paste(setdiff(pr, dset), collapse = ",")))
  de <- unique(en[dg & !is.na(en)])
  if (length(setdiff(de, en[!dg & cp %in% "RX0"]))) bad <- c(bad, paste("진단 칸 엔진에 RX0 칸 없음:", paste(setdiff(de, en[!dg & cp %in% "RX0"]), collapse = ",")))
  bad
}
## τ_D 이후 날짜 가림(보는 창 파일 · C-031) — 문자열 안 'YYYY-MM-DD' · 'YYYY-MM'(dp_scan_dates 와 같은 무늬)이 τ_D 뒤면 가린다(오류 문구가 시험 창 날짜를
##   실어 나르는 길을 막는다). Date 값은 건드리지 않는다 — 남으면 쓰기 전 전수 검사(dp_scan_dates)가 멈춘다
.p2_redact_chr <- function(s, tau) {
  tau <- as.Date(tau); ok <- !is.na(s)
  if (!any(ok)) return(s)
  tau_ym <- format(tau, "%Y-%m"); x <- s[ok]
  m <- gregexpr("(19|20)[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])", x)
  regmatches(x, m) <- lapply(regmatches(x, m), function(v) { if (!length(v)) return(v); d <- suppressWarnings(as.Date(v))
                                                              ifelse(!is.na(d) & d > tau, P2R04_REDACT, v) })
  m2 <- gregexpr("(?<![0-9-])(19|20)[0-9]{2}-(0[1-9]|1[0-2])(?![0-9-])", x, perl = TRUE)
  regmatches(x, m2) <- lapply(regmatches(x, m2), function(v) if (!length(v)) v else ifelse(v > tau_ym, P2R04_REDACT, v))
  s[ok] <- x; s
}
p2_redact_after_tau <- function(x, tau) {
  tau <- as.Date(tau)
  if (is.character(x)) return(.p2_redact_chr(x, tau))
  if (is.data.table(x)) { x <- copy(x); for (cc in names(x)) if (is.character(x[[cc]])) set(x, j = cc, value = .p2_redact_chr(x[[cc]], tau)); return(x) }
  if (is.data.frame(x)) { for (cc in names(x)) if (is.character(x[[cc]])) x[[cc]] <- .p2_redact_chr(x[[cc]], tau); return(x) }
  if (is.list(x) && length(x)) { x[] <- lapply(x, p2_redact_after_tau, tau = tau); return(x) }
  x
}
## 보는 창 판정 칸 — 사람 쪽 항목(시험 창 증분 알파 · 판정 표 행 · 셀 로그 전 구간 셈 · 공통 창 사본의 전 구간 행 수)을 빼고 τ_D 이후 날짜를 가린다
p2_visible_only <- function(x, tau) {
  for (k in P2R04_VISIBLE_DROP) x[[k]] <- NULL
  if (is.list(x$trim)) for (s in names(x$trim)) if (is.list(x$trim[[s]])) x$trim[[s]]$n_pr <- NULL
  p2_redact_after_tau(x, tau)
}
## 핀 대조 — precheck.R(측정 직전)과 evaluate.R 시작부(샤드 포함)가 같은 함수를 쓴다. 사양 · 운영 경로 · 비중 카탈로그 엔트리 · 오버레이 카탈로그 arm ·
##   팩터 레지스트리 엔트리({id, entry[, path]} · 기본 경로 .cache/factor_db/factor_registry.json) · 패키지 · R 판 · 평가 경로 · 행동 카드 설정 사본.
##   대조 함수가 없는 핀 종류는 불일치로 센다(P2R04_PIN_KINDS 밖 — 대조 없이 통과하지 않는다). 반환 = 불일치 설명(없으면 길이 0)
p2_pin_mismatches <- function(pre, root) {
  md5 <- function(f) unname(as.character(tools::md5sum(file.path(root, f))))
  cj <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
  bad <- character(0)
  for (c0 in pre$cells) if (!identical(md5(c0$path), c0$md5)) bad <- c(bad, paste("사양 md5:", c0$code))
  op <- pre$operational_pins
  if (is.null(op)) return(c(bad, "운영 핀 없음"))
  unk <- setdiff(names(op), P2R04_PIN_KINDS)
  if (length(unk)) bad <- c(bad, paste("대조 함수 없는 운영 핀 종류(침묵 통과 금지):", paste(unk, collapse = ",")))
  for (f in op$files) if (!identical(md5(f$path), f$md5)) bad <- c(bad, paste("운영 경로 md5:", f$path))
  if (length(op$catalog_entries)) {
    wc <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries, error = function(e) list())
    for (pin in op$catalog_entries) {
      ent <- Filter(function(z) identical(z$catalog_id, pin$catalog_id), wc)
      if (!length(ent) || !identical(ent[[1]]$status, pin$status) || !identical(cj(ent[[1]]$resolver), cj(pin$resolver)))
        bad <- c(bad, paste("비중 카탈로그 엔트리:", pin$catalog_id))
    }
  }
  if (length(op$overlay_arms)) {
    oc <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE)$arms, error = function(e) list())
    for (pin in op$overlay_arms) {
      ent <- Filter(function(z) identical(z$id, pin$id), oc)
      if (!length(ent) || !identical(cj(ent[[1]]), cj(pin$entry))) bad <- c(bad, paste("오버레이 카탈로그 arm:", pin$id))
    }
  }
  FRC <- list()
  for (pin in op$factor_registry_entries) {
    fp <- pin$path %||% ".cache/factor_db/factor_registry.json"
    if (is.null(FRC[[fp]])) FRC[[fp]] <- tryCatch(jsonlite::fromJSON(file.path(root, fp), simplifyVector = FALSE), error = function(e) list())
    ent <- FRC[[fp]][[pin$id %||% ""]]
    if (is.null(ent) || !identical(cj(ent), cj(pin$entry))) bad <- c(bad, paste("팩터 레지스트리 엔트리:", pin$id %||% "?"))
  }
  for (pk in names(op$packages)) {
    v <- tryCatch(as.character(utils::packageVersion(pk)), error = function(e) NA_character_)
    if (!identical(v, op$packages[[pk]])) bad <- c(bad, paste(pk, "판"))
  }
  if (!identical(R.version.string, op$r_version)) bad <- c(bad, "R 판")
  for (f in pre$evaluation$files %||% list()) if (!identical(md5(f$path), f$md5)) bad <- c(bad, paste("평가 경로 md5:", f$path))
  if (!is.null(pre$behavior_card_cfg) && !identical(md5(pre$behavior_card_cfg$path), pre$behavior_card_cfg$md5)) bad <- c(bad, "행동 카드 설정 사본 md5")
  bad
}
## 데이터 지문(fingerprint.sh — measure.sh 와 같은 정의) · 줄을 '|' 로 잇는다. 비교는 이름을 지운 문자열로(P3R03 오표시 = 이름 붙은 벡터 · identical 거짓)
p2_fingerprint <- function(rd, mode = "equality") {
  o <- tryCatch(suppressWarnings(system2("bash", c(shQuote(file.path(rd, "fingerprint.sh")), mode), stdout = TRUE, stderr = TRUE)),
                error = function(e) paste("error:", conditionMessage(e)))
  paste(o, collapse = "|")
}
p2_fp_same <- function(a, b) identical(unname(as.character(a)), unname(as.character(b)))

## ── 계약 호출 기록 도우미(보는 창 · 판정 아님 · 실패 = 그 기록만 미측정 꼬리표) ─────────────
## 크기 × β 짝(C-017) — 변형 보는 창 보유로 MC8 크기 바스켓(matched_controls mc_size_basket · .mc_basket_returns = size_matched 와 같은 수익)을 만들고,
##   변형 β / 바스켓 β(같은 계약 월 β · behavior_card .bc_beta)로 낮춘(나머지 현금) 사본의 위기 낙폭 포착(behavior_card bc_attach_controls)을 깊은 위기에서
##   변형과 비교한다. 이 짝까지 과반에서 넘을 때만 결론 이름 '선택(특성) 방어'. 적재 = τ_D 까지(수익 · 벤치 · 보유 절단 · 바스켓 날짜 단정)
p2_size_beta_record <- function(X, dir, PM, cr_v, deep, tol, maj) {
  E <- X$env$E; TAU <- X$tau
  rd <- .dp_read(E, dir)
  prv <- rd$pr[date <= TAU][order(date)]; brv <- rd$br[date <= TAU][order(date)]; Hv <- rd$H[date <= TAU]
  uni <- as.character(rd$spec$universe %||% rd$man$universe_id %||% NA_character_)[1]
  if (is.na(uni) || !nzchar(uni)) stop("유니버스 미상")
  if (is.null(X$env$raw)) X$env$raw <- mc_load_raw(X$root, from = "1999-11-01", hygiene = TRUE)
  cfg <- E$mc_cfg(X$root)
  win <- E$.mc_windows(prv$date, Hv$date, rd$src$exec_price)
  sb <- E$mc_size_basket(Hv, X$env$raw, cfg, uni)
  if (!nrow(sb$members)) stop("크기 바스켓을 못 만들었다(모든 리밸)")
  bk <- E$.mc_basket_returns(sb$members, win, X$env$raw)
  if (!nrow(bk) || max(bk$date) > TAU) stop("바스켓 수익이 비었거나 τ_D 를 넘는다")
  M <- merge(E$bc_monthly(bk[, .(date, r = ret)], "r")[, .(ym, s = r)], E$bc_monthly(brv[, .(date, r = benchmark_ret)], "r")[, .(ym, k = r)], by = "ym")
  bb <- E$.bc_beta(M$s, M$k); bv <- rk_getf(PM, "behavior.stats.beta")
  plan <- p2_size_beta_plan(bv, bb)
  base <- list(beta_variant = bv, beta_basket = bb, basket_rebalances_ok = sum(sb$diag$status == "ok"), basket_rebalances = nrow(sb$diag))
  if (identical(plan$mode, "unmeasured")) return(c(list(status = "unmeasured", tag = "크기 × β 짝 미측정", why = "β 비 비유한 또는 ≤ 0"), base, plan))
  CR <- .p2_rows_dt(PM$behavior$crises)
  if (!nrow(CR)) return(c(list(status = "unmeasured", tag = "크기 × β 짝 미측정", why = "위기 없음"), base, plan))
  CR[, `:=`(peak_date = as.Date(as.character(peak_date)), trough_date = as.Date(as.character(trough_date)))]
  att <- E$bc_attach_controls(list(crises = CR, cfg = list(majority_share = maj)), list(size_beta = bk[, .(date, ret = plan$scale * ret)]),
                              brv[, .(date, benchmark_ret)], tol = 0)$controls$size_beta
  if (!identical(att$status, "ok")) return(c(list(status = "unmeasured", tag = "크기 × β 짝 미측정", why = paste("대조 위기 포착:", att$status %||% "?")), base, plan))
  pc <- as.data.table(att$per_crisis)
  CRc <- copy(CR)[, dd_capture := pc$control_dd_capture[match(peak_date, as.Date(pc$peak_date))]]
  c(list(status = "ok", tag = NA_character_), base, plan, p2_size_beta_core(cr_v, CRc, deep, tol, maj))
}
## 유동성 패널(C-020) — RAWDATA 를 τ_D 에서 자른 뒤 20일 평균 거래대금(Close × Vol) t−1(셀 엔진 .adv20_l1 과 같은 식 · C10) · 무거래일 판정용 Vol
p2_liq_panel <- function(root, tau) {
  L <- as.data.table(arrow::read_parquet(file.path(root, ".cache/RAWDATA.parquet"), col_select = c("Date", "Ticker", "Close", "Vol")))
  if (!inherits(L$Date, "Date")) L[, Date := as.Date(Date)]
  L <- L[Date <= as.Date(tau)]
  setorder(L, Ticker, Date)
  L[, adv20_l1 := shift(frollmean(as.numeric(Close) * as.numeric(Vol), 20L, align = "right"), 1L), by = Ticker]
  L <- L[, .(Date, Ticker = as.character(Ticker), Vol = as.numeric(Vol), adv20_l1)]
  setkey(L, Date, Ticker)
  L
}
## 유동성 귀속(C-020 기록) — 위기마다 그 위기 보유창에 든 종목의 유동성 분위(위기 첫 보유일 as-of · 측정 유니버스 = 위생 멤버) · 무거래일 비율(보유 종목 × 위기 거래일 중 Vol ≤ 0)
p2_liquidity_record <- function(X, dir, crises, deep_peaks) {
  E <- X$env$E; TAU <- X$tau
  if (is.null(X$env$raw)) X$env$raw <- mc_load_raw(X$root, from = "1999-11-01", hygiene = TRUE)
  if (!"HYG" %in% names(X$env$raw)) stop("위생 멤버십(HYG) 없음 — 측정 유니버스 분위를 정할 수 없다")
  if (is.null(X$env$liq)) X$env$liq <- p2_liq_panel(X$root, TAU)
  L <- X$env$liq; RW <- X$env$raw
  rd <- .dp_read(E, dir)
  prv <- rd$pr[date <= TAU]
  Hv <- rd$H[date <= TAU & is.finite(target_weight) & target_weight > 0, .(exec_date = date, Ticker = as.character(ticker))]
  win <- E$.mc_windows(prv$date, unique(Hv$exec_date), rd$src$exec_price)
  CR <- .p2_rows_dt(crises)
  if (!nrow(CR)) stop("위기 없음")
  rows <- lapply(seq_len(nrow(CR)), function(i) {
    p0 <- as.Date(as.character(CR$peak_date[i])); t0 <- as.Date(as.character(CR$trough_date[i]))
    D <- win[date > p0 & date <= t0]
    if (!nrow(D)) return(NULL)
    PR <- merge(D, Hv, by = "exec_date", allow.cartesian = TRUE)
    if (!nrow(PR)) return(NULL)
    d0 <- min(D$date); tk <- unique(PR$Ticker)
    hyg <- RW$Ticker[as.integer(RW$Date) == as.integer(d0) & RW$HYG %in% TRUE]
    U <- L[.(d0)][Ticker %in% hyg & is.finite(adv20_l1) & adv20_l1 > 0]
    dec <- p2_liq_deciles(U$adv20_l1[match(tk, U$Ticker)], U$adv20_l1)
    Z <- L[.(PR$date, PR$Ticker), nomatch = NA]
    v <- Z$Vol[is.finite(Z$Vol)]
    data.table(peak_date = format(p0), asof = format(d0), n_names = length(tk), n_unknown = sum(is.na(dec)),
               mean_decile = if (any(!is.na(dec))) mean(dec, na.rm = TRUE) else NA_real_,
               n_holding_days = nrow(PR), n_vol_known = length(v), zero_vol_share = if (length(v)) mean(v <= 0) else NA_real_)
  })
  T <- rbindlist(rows)
  if (!nrow(T)) stop("위기 보유창 없음")
  dm <- function(v) { v <- v[is.finite(v)]; if (length(v)) mean(v) else NA_real_ }
  list(status = "ok", per_crisis = T, deep_mean_decile = dm(T[peak_date %in% as.character(deep_peaks), mean_decile]),
       deep_zero_vol_share = dm(T[peak_date %in% as.character(deep_peaks), zero_vol_share]),
       rule = "유동성 = 20일 평균 거래대금(Close × Vol) t−1 · 위기 첫 보유일 as-of 위생 멤버 10분위 · 무거래일 = 보유 종목 × 위기 거래일 중 Vol ≤ 0")
}
## 국면별 월 차이 입출력 — 두 칸의 보는 창 월 수익(계약 bc_monthly) 차이를 패킷 위기 · 강세 국면으로 나눈다
p2_regime_months <- function(X, am, ar, PM) {
  E <- X$env$E; mon <- function(d) { rd <- .dp_read(E, d); E$bc_monthly(rd$pr[date <= X$tau, .(date, r = ret_net)], "r") }
  D <- merge(mon(am)[, .(ym, s = r)], mon(ar)[, .(ym, b = r)], by = "ym")[order(ym)]
  p2_regime_diff(D$ym, D$s - D$b, PM$behavior$crises %||% list(), PM$behavior$bull_phases %||% list())
}
## RX0 동일성 입출력(C-025) — P2R04 RX0 산출물 vs P2R03 같은 엔진 RX0 산출물(측정 결과 json 의 artifacts) · 같음/다름 + 다른 달 수
p2_rx0_identity <- function(X, art4, json3) {
  if (!file.exists(json3)) return(list(status = "absent", p2r03 = json3))
  j <- fromJSON(json3, simplifyVector = FALSE)
  if (!isTRUE(j$ok) || is.null(j$artifacts)) return(list(status = "p2r03_not_ok", p2r03 = json3))
  E <- X$env$E; d4 <- E$ta_resolve_artifact(art4)$dir; d3 <- E$ta_resolve_artifact(j$artifacts)$dir
  rp <- function(d) { x <- fread(file.path(d, "03_period_returns.csv")); x[, date := as.Date(date)]; x }
  c(list(status = "ok", p2r03 = sub(paste0("^", X$root, "/"), "", json3)), p2_rx0_identity_core(.p2_read_holdings(d4), .p2_read_holdings(d3), rp(d4), rp(d3), X$tau))
}

## ── 칸 평가(보는 창 / 사람 쪽 파일 분리 · C-031) — round_kit rk_eval_cell 과 같은 계약 호출 · 저장만 둘로 나눈다 ─────────
##   results/<code>/visible/{diagnosis_packet.json, eval_visible.json}(보는 창 리뷰어 열람 가능) ·
##   results/<code>/full/{behavior_card.json, eval_full.json}(사람 쪽 · 열람 금지 표식). 반환 = 둘을 합친 목록(메모리에서만)
p2_cell_join <- function(v, f) c(v, list(test = f$test, full = f$full))
## 칸 평가 안전 호출 — 진단 패킷 · 행동 카드 · 축 감사의 stop 이 라운드 판정 전체를 멈추지 않게 그 칸만 status = eval_error 로 접는다(진단 칸도 같다)
##   (짝 판정은 평가 상태 단정에서 미시험 · 보는 창 파일은 끝에 쓰므로 부분 저장은 캐시가 되지 않는다)
p2_eval_cell <- function(root, res_dir, cell, env, tau)
  tryCatch(.p2_eval_cell_core(root, res_dir, cell, env, tau),
           error = function(e) { cat(sprintf("[P2R04 평가] %s — 칸 평가 오류: %s\n", cell$code, .p2_redact_chr(conditionMessage(e), as.Date(tau))))
                                 list(code = cell$code, status = "eval_error", err = conditionMessage(e)) })
.p2_eval_cell_core <- function(root, res_dir, cell, env, tau) {
  out_dir <- file.path(res_dir, cell$code)
  fv <- file.path(out_dir, "visible", "eval_visible.json"); ff <- file.path(out_dir, "full", "eval_full.json")
  if (file.exists(fv) && file.exists(ff)) return(p2_cell_join(fromJSON(fv, simplifyVector = FALSE), fromJSON(ff, simplifyVector = FALSE)))
  rj <- file.path(res_dir, paste0(cell$code, ".json"))
  if (!file.exists(rj)) return(list(code = cell$code, status = "not_measured"))
  r <- fromJSON(rj, simplifyVector = FALSE)
  if (!isTRUE(r$ok)) return(list(code = cell$code, status = "measure_failed", err = r$err %||% NA))
  dir.create(file.path(out_dir, "visible"), recursive = TRUE, showWarnings = FALSE); dir.create(file.path(out_dir, "full"), recursive = TRUE, showWarnings = FALSE)
  if (is.null(env$raw)) env$raw <- mc_load_raw(root, from = "1999-11-01", hygiene = TRUE)
  t0 <- Sys.time()
  ax <- rk_axis_audit(root, r$artifacts)
  vis <- dp_build(r$artifacts, root = root, cell_spec = file.path(root, cell$path), raw = env$raw, bcfg = env$BCFG_L)
  dp_write(vis, file.path(out_dir, "visible"))
  card <- mc_card(r$artifacts, root = root, raw = env$raw, bcfg = env$BCFG_L)
  mc_write(card, file.path(out_dir, "full"), root = root)
  tp <- tryCatch(rk_test_perf(env$E, root, r$artifacts, tau), error = function(e) list(status = paste("error:", conditionMessage(e))))
  ar <- fromJSON(file.path(r$artifacts, "authoritative_remeasure.json"), simplifyVector = FALSE)
  g <- function(p) rk_getf(vis, p)
  v <- list(code = cell$code, engine = cell$engine %||% NA, component = cell$component %||% NA, diagnostic = isTRUE(cell$diagnostic),
            status = if (isTRUE(ax$ok)) "evaluated" else "axis_violation", artifacts = r$artifacts, axis = ax,
            effective_start = ar$measurement_axis$effective_start[c("status", "date")],
            visible = list(window = vis$window, uc = g("behavior.summary.bull_up_capture_median"), dc = g("behavior.summary.crisis_cum_capture_median"),
                           dc_strong = g("behavior.dc_strong_max"), cagr = g("performance.strategy.cagr"), calmar = g("performance.strategy.calmar"),
                           port_t = g("performance.strategy.port_t"), mdd = g("performance.strategy.mdd"), sharpe = g("performance.strategy.sharpe"),
                           cdar = g("behavior.stats.cdar"), beta = g("behavior.stats.beta"), beta_down = g("behavior.stats.beta_down"), beta_up = g("behavior.stats.beta_up"),
                           dd_capture_median = g("behavior.summary.crisis_dd_capture_median"), dd_capture_worst = g("behavior.summary.crisis_dd_capture_worst"),
                           n_crisis = g("behavior.summary.n_crisis"), n_bull = g("behavior.summary.n_bull"), verdict = vis$behavior$verdict,
                           attribution = vis$controls$attribution$label %||% NA, exposure_mean = g("controls.exposure_profile.mean"),
                           turnover_annual = g("profile.turnover_annual"), cost_drag_annual = g("profile.cost_drag_annual")),
            eval_seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  f <- list(code = cell$code, audience = P2R04_FULL_AUDIENCE,
            test = list(uc = card$test$bull_up_capture_median %||% NA, dc = card$test$crisis_cum_capture_median %||% NA,
                        n_bull = card$test$n_bull %||% NA, n_crisis = card$test$n_crisis %||% NA, verdict = card$test$verdict %||% NA,
                        dc_strong = card$dc_strong_max %||% NA, perf = tp),
            full = list(grade = ar$essence_grade, S = ar$grade_v3$S %||% NA, cr = card$overall$verdict, attribution = card$controls$attribution$overall$label %||% NA,
                        cdar = card$stats$cdar %||% NA, effective_start = ar$measurement_axis$effective_start$date %||% NA))
  writeLines(toJSON(f, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), ff, useBytes = TRUE)
  writeLines(toJSON(v, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), fv, useBytes = TRUE)   # 보는 창 파일을 마지막에(캐시 = 둘 다 있을 때)
  writeLines(P2R04_FULL_AUDIENCE, file.path(out_dir, "full", "NO_VISIBLE_REVIEW.txt"), useBytes = TRUE)
  cat(sprintf("[P2R04 평가] %s — 보는 창 UC %.3f · DC %.3f · CAGR %.3f · CDaR %.3f · 귀속 %s · 축 %s · %.0f초\n", cell$code, v$visible$uc, v$visible$dc,
              v$visible$cagr, v$visible$cdar, v$visible$attribution, ax$ok, v$eval_seconds))
  p2_cell_join(v, f)
}

## ── 판정 1칸(장치 × 엔진 vs 같은 엔진 RX0) — 본 실행 · 진단 칸 · 등록 전 리허설(rehearse.R)이 같은 함수를 쓴다 ─────────────────
##   X = list(root · res(읽기 — 칸 평가 패킷 · 셀 로그) · out(쓰기 — 공통 창 · β 짝 사본과 그 패킷) · env(E · BCFG_L · raw · liq) · fs · tau · ea(엔진 알파 캐시 환경))
##   opts: role("judge" 기본 · "diagnostic" = 진단 칸 — 장치 = 진단 표 · 혼합 가중 대조 · 보유 같음이어도 계속(무처치는 그 진단의 답) · 크기 × β · 유동성 ·
##         국면 월 기록 생략) · expect_weight(진단 칸 기대 장치 가중) · 리허설 전용 force_start · force_k · expect_cell · expect_cell_rx0 · log · log_rx0
##   실패 의미(사전 고정): 평가 상태 · 장치(진단) 표 · 사양 읽기 · ⑩ 구성 증거(사양 · 셀 로그) · 진단 칸 가중 · 실효 시작 · 공통 창 · ⑩ 처치 전달(판정 칸 —
##   보유 차이 0 = 무처치) · 패킷 · 위기 짝 · 판정 입력(①②⑤⑥⑦⑨⑫⑬ · 알파 · 엔진 알파) = 미시험 / β 사본 실패 · ③ 짝 < 2 = 'β 대조 미측정'(통과 불가) /
##   빠른 급락 짝 < 2 = '빠른 급락 미측정'(통과 불가) / ⑭ 라벨 없음 · 다름 = 통과 불가(라벨 기록) / 집중 손실 표 결손 = '집중 손실 미측정'(제외) /
##   크기 × β · 유동성 · 국면 월 계산 실패 = 그 기록만 미측정 꼬리표('크기 × β 짝 미측정' · '유동성 귀속 미측정')
.p2_untested <- function(out, why) {
  out$tested <- FALSE; out$pass <- FALSE; out$verdict <- "untested"; out$verdict_name <- P2R04_VERDICT_NAMES[["untested"]]; out$why <- why
  out$tbl <- data.table(engine = out$engine, device = out$device, tested = FALSE, pass = FALSE, excluded = FALSE, verdict = "untested")
  out
}
.p2_read_holdings <- function(dir) {
  x <- fread(file.path(dir, "04_holdings.csv"), colClasses = list(character = "ticker"))
  x[, date := as.Date(date)]; x[, w := as.numeric(get(intersect(c("target_weight", "actual_weight"), names(x))[1]))]; x
}
.p2_read_lines <- function(p) if (length(p) == 1L && !is.na(p) && file.exists(p)) readLines(p, warn = FALSE, encoding = "UTF-8") else character(0)
p2_pk_read <- function(X, code, sub = "visible") {
  p <- file.path(X$res, code, sub, "diagnosis_packet.json"); if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL
}
p2_pk_build <- function(X, spec_path, art, od) {
  if (is.null(X$env$raw)) X$env$raw <- mc_load_raw(X$root, from = "1999-11-01", hygiene = TRUE)
  v <- dp_build(art, root = X$root, cell_spec = file.path(X$root, spec_path), raw = X$env$raw, bcfg = X$env$BCFG_L)
  dp_write(v, od); fromJSON(file.path(od, "diagnosis_packet.json"), simplifyVector = FALSE)
}
## 엔진 자체 β-통제 알파(보는 창 · RX0 월 수익 대 벤치 · 계약 beta_controlled_alpha) — 알파 비열등 여유의 기준 · 엔진 자격 기록
p2_eng_alpha <- function(X, dir) {
  E <- X$env$E; rd <- .dp_read(E, dir); mon <- function(d, col) E$bc_monthly(d[, .(date, r = get(col))], "r")
  D <- merge(mon(rd$pr[, .(date, ret_net)], "ret_net")[, .(ym, s = r)], mon(rd$br[, .(date, benchmark_ret)], "benchmark_ret")[, .(ym, k = r)], by = "ym")
  D <- D[ym <= format(X$tau, "%Y-%m")]
  a <- tryCatch(beta_controlled_alpha(D$s, D$k, periods_per_year = 12, nw_lag = 3L), error = function(e) NULL)
  list(alpha_ann = a$alpha_ann %||% NA_real_, t = a$t_alpha %||% NA_real_, n = a$n %||% NA_integer_)
}
p2_eval_pair <- function(X, eng, dev, cm, cr, em, er, opts = list()) {
  FS <- X$fs; TAU <- X$tau; g <- rk_getf
  MAJ <- as.numeric(FS$majority_share); tol <- as.numeric(FS$crisis_improve_min)
  role <- opts$role %||% "judge"; diag <- identical(role, "diagnostic")
  out <- list(engine = eng, device = dev, role = role, cell = cm$code, rx0 = cr$code, status = em$status %||% NA, status_rx0 = er$status %||% NA)
  if (!identical(em$status, "evaluated") || !identical(er$status, "evaluated"))
    return(.p2_untested(out, sprintf("평가 상태 %s · %s", em$status %||% "NA", er$status %||% "NA")))
  sp <- tryCatch(list(v = fromJSON(file.path(X$root, cm$path), simplifyVector = FALSE), r = fromJSON(file.path(X$root, cr$path), simplifyVector = FALSE)),
                 error = function(e) list(error = conditionMessage(e)))
  if (!is.null(sp$error)) return(.p2_untested(out, paste("사양 읽기 실패:", sp$error)))
  dvt <- if (diag) p2_diag_device(dev, sp$v$factors) else P2R04_DEVICES[[dev]]
  if (is.null(dvt)) return(.p2_untested(out, if (diag) paste("진단 칸 장치 해석 실패(진단 표 · 사양 끝 항목):", dev) else paste("장치 표에 없는 부품:", dev)))
  out$device_factor <- dvt[intersect(names(dvt), c("kind", "id", "name"))]
  ## ⑩ 구성 증거 — 사양(변형 = RX0 + 장치 팩터 꼬리 m 회) · 셀 로그 적재 줄(변형 = 사양 factors · RX0 = 장치 팩터 없음)
  ## ★ opts 는 [[ ]](정확 일치) — `opts$log` 는 log_rx0 에, `opts$expect_cell` 은 expect_cell_rx0 에 부분 일치한다(한쪽만 넘기면 엉뚱한 값)
  Lv <- .p2_read_lines(opts[["log"]] %||% file.path(X$res, paste0(cm$code, ".log"))); Lr <- .p2_read_lines(opts[["log_rx0"]] %||% file.path(X$res, paste0(cr$code, ".log")))
  lv <- p2_parse_cell_log(Lv); lr <- p2_parse_cell_log(Lr)
  cs <- p2_construction_check(lv, lr, dvt, sp$v$factors, sp$r$factors, opts[["expect_cell"]] %||% cm$code, opts[["expect_cell_rx0"]] %||% cr$code)
  cs$blend <- p2_blend_weight(sp$v$base_weight, length(cs$spec_factors), cs$device_count)
  if (diag) { ew <- suppressWarnings(as.numeric(opts$expect_weight %||% NA))[1]; dw <- cs$blend$device_weight
              cs$blend$expected <- ew; cs$blend$ok <- is.finite(ew) && is.finite(dw) && abs(dw - ew) < 1e-9 }   # 1e-9 = 부동소수 여유(결정 수치 아님)
  out$construction <- cs
  out$cell_log_full_period <- list(variant = lv[intersect(names(lv), c("months", "rows"))], rx0 = lr[intersect(names(lr), c("months", "rows"))])
  if (!isTRUE(cs$ok)) return(.p2_untested(out, paste("구성 증거 불일치(⑩) —", cs$why)))
  if (diag && !isTRUE(cs$blend$ok))
    return(.p2_untested(out, sprintf("진단 칸 혼합 가중 불일치 — 장치 가중 %s(기대 %s · 진단 표 %s)", format(cs$blend$device_weight), format(cs$blend$expected), dev)))
  ## 실효 시작
  dm <- X$env$E$ta_resolve_artifact(em$artifacts)$dir; dr <- X$env$E$ta_resolve_artifact(er$artifacts)$dir
  esm <- em$effective_start; esr <- er$effective_start
  out$effective_start <- list(variant = esm, rx0 = esr)
  if (!identical(esm$status, "ok") || !identical(esr$status, "ok"))
    return(.p2_untested(out, sprintf("실효 시작 상태 %s · %s", esm$status %||% "NA", esr$status %||% "NA")))
  ## 창 — 실효 시작이 같으면 원 산출 · 다르면(또는 리허설 강제) 공통 창 사본(늦게 시작한 칸의 첫 기간수익일 · 실패 = 미시험) — 패킷 전에 디렉터리만 정한다
  common <- !is.null(opts$force_start) || !identical(esm$date, esr$date)
  W <- tryCatch({
    if (!common) list(sub = "original", window = "original", am = dm, ar = dr)
    else {
      cs0 <- if (!is.null(opts$force_start)) as.Date(opts$force_start) else {
        late <- if (as.Date(esm$date) > as.Date(esr$date)) dm else dr
        min(as.Date(fread(file.path(late, "03_period_returns.csv"))$date)) }
      sub <- paste0("common_", format(cs0, "%Y%m%d")); base <- file.path(X$out, cm$code, sub)
      am <- file.path(base, "artifacts"); ar <- file.path(base, "rx0_artifacts")
      tr <- list(variant = p2_trim_artifacts(dm, am, cs0), rx0 = p2_trim_artifacts(dr, ar, cs0))
      .p2_mark_full(base, P2R04_FULL_MARK_PARENT)                                # 공통 창 상위 폴더 — visible* 만 보는 창
      list(sub = sub, window = paste0("common_from_", format(cs0)), am = am, ar = ar, base = base, trim = tr)
    }
  }, error = function(e) list(error = conditionMessage(e)))
  if (!is.null(W$error)) return(.p2_untested(out, paste("공통 창 실패:", W$error)))
  out$window <- W$window; out$trim <- W$trim
  am <- W$am; ar <- W$ar
  ## ⑩ 처치 전달 — 보는 창 보유가 RX0 와 다른 보유일 ≥ 1(판정 칸: 무처치 = 미시험 · 진단 칸: 같음도 그 진단의 답 — 계속)
  ov <- tryCatch(p2_holdings_overlap(.p2_read_holdings(am), .p2_read_holdings(ar), TAU), error = function(e) list(status = paste("오류:", conditionMessage(e))))
  out$holdings_overlap <- ov[setdiff(names(ov), "per_date")]
  out$holdings_overlap_per_date <- ov$per_date
  out$treatment_delivered <- p2_treatment_delivered(ov)
  if (!out$treatment_delivered && (!diag || !identical(ov$status, "ok")))
    return(.p2_untested(out, sprintf("무처치(⑩) — 보는 창 보유가 RX0 와 다른 보유일 %s/%s(보유 대조 %s)", format(ov$n_differ %||% NA), format(ov$n_dates %||% NA), ov$status %||% "NA")))
  ## 보는 창 패킷(원 창 = 칸 평가 패킷 · 공통 창 = 사본에 같은 계약)
  P <- tryCatch({
    if (!common) list(PM = p2_pk_read(X, cm$code), PRX = p2_pk_read(X, cr$code))
    else list(PM = p2_pk_build(X, cm$path, am, file.path(W$base, "visible")), PRX = p2_pk_build(X, cr$path, ar, file.path(W$base, "visible_rx0")))
  }, error = function(e) list(error = conditionMessage(e)))
  if (!is.null(P$error)) return(.p2_untested(out, paste("보는 창 패킷 실패:", P$error)))
  PM <- P$PM; PRX <- P$PRX
  if (is.null(PM) || is.null(PRX)) return(.p2_untested(out, "보는 창 패킷 없음"))
  ## 팩터 방향 경로(기록) — 장치 블록 = 변형 적재 팩터 수(사양 끝)
  out$construction$factor_direction <- tryCatch(p2_direction_record(p2_parse_direction_lines(Lv), length(lv$factors), PM$window[[1]] %||% NA, TAU),
                                                error = function(e) list(status = paste("오류:", conditionMessage(e))))
  ek <- paste(eng, W$sub)
  if (is.null(X$ea[[ek]])) assign(ek, tryCatch(p2_eng_alpha(X, ar), error = function(e) list(alpha_ann = NA_real_, t = NA_real_, n = NA_integer_, err = conditionMessage(e))), envir = X$ea)
  ea <- X$ea[[ek]]
  ## ① · ② 위기 짝 · 깊은 위기(RX0 대비)
  crm <- PM$behavior$crises %||% list(); crr <- PRX$behavior$crises %||% list()
  maj <- p2_crisis_majority(crm, crr, tol, "dd_capture")
  deep <- p2_deep_crisis_keys(crm, crr)
  dmj <- p2_crisis_majority(crm, crr, tol, "dd_capture", subset = deep)
  out$crisis_pairs <- list(n_pair = maj$n_pair, unpaired = maj$unpaired, n_deep = dmj$n_pair, deep_keys = deep)
  if (!identical(as.integer(maj$unpaired), 0L)) return(.p2_untested(out, sprintf("위기 짝 불일치 %s(같은 창이면 0)", format(maj$unpaired))))
  if (maj$n_pair < 2L || dmj$n_pair < 2L) return(.p2_untested(out, sprintf("판정 위기 짝 < 2(전체 %d · 깊은 %d)", maj$n_pair, dmj$n_pair)))
  ## 빠른 급락 분류(같은 칸 RX0 산출물의 벤치 일수익 · 사전등록 창 · 문턱)
  fk <- tryCatch(p2_fast_crash_keys(fread(file.path(ar, "05_benchmark_returns.csv")), crr, as.integer(FS$fast_window_days), as.numeric(FS$fast_drop)),
                 error = function(e) list(keys = character(0), table = data.table(), unclassified = NA_character_, no_month_end = character(0), err = conditionMessage(e)))
  ## β 짝 사본 — k = 변형 β / RX0 β(보는 창) · k < 1 이면 RX0 를 k 배 노출로 낮춘 사본 · k ≥ 1 이면 사본 = RX0
  bm <- g(PM, "behavior.stats.beta"); br0 <- g(PRX, "behavior.stats.beta")
  bp <- p2_beta_plan(bm, br0, opts$force_k); k <- bp$k
  PB <- NULL; berr <- NULL
  if (identical(bp$mode, "unmeasured")) berr <- sprintf("k 비유한 또는 ≤ 0(%s)", format(k))
  else if (identical(bp$mode, "rx0")) PB <- PRX
  else PB <- tryCatch({
    bdir <- file.path(X$out, cm$code, W$sub, "rx0_beta_scaled")
    .p2_mark_full(file.path(X$out, cm$code, W$sub), P2R04_FULL_MARK_PARENT)       # β 짝 상위 폴더(original · common_*) — visible* 만 보는 창
    p2_beta_scaled_copy(ar, bdir, k)
    p2_pk_build(X, cr$path, bdir, file.path(X$out, cm$code, W$sub, "visible_rx0_beta"))
  }, error = function(e) { berr <<- conditionMessage(e); NULL })
  cbp <- if (!is.null(PB)) PB$behavior$crises %||% list() else list()
  emp <- list(n_pair = 0L, share = NA_real_)
  b3 <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = deep) else emp
  b4 <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = fk$keys) else emp
  r3 <- if (!is.null(PB) && b3$n_pair >= 2L) p2_maj(b3$share, MAJ) else NA
  r4 <- if (!is.null(PB) && b4$n_pair >= 2L) p2_maj(b4$share, MAJ) else NA
  ## 기록 판(판정 아님): ④ 일화 단위 판(위기 안 월말 0 인 급락 제외 · C-047 · 2008-11) · 느린 약세(분류된 위기 중 빠름 아님)의 β 짝 비율
  b4x <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = setdiff(fk$keys, fk$no_month_end)) else emp
  slow_keys <- if (nrow(fk$table)) fk$table[fast %in% FALSE, k] else character(0)
  bsl <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = slow_keys) else emp
  ## ⑤ β 비대칭(장치 검증 = 하락/상승 β 비의 변화량 · 방어 주장 = 수준) · ⑥ 강세 구간별 · ⑦ 알파 · ⑨ 사이클 · ⑫ S · ⑬ 경로
  bdu <- c(down = g(PM, "behavior.stats.beta_down"), up = g(PM, "behavior.stats.beta_up"))
  bdr <- c(down = g(PRX, "behavior.stats.beta_down"), up = g(PRX, "behavior.stats.beta_up"))
  r5d <- p2_beta_ratio_delta(bdu[["down"]], bdu[["up"]], bdr[["down"]], bdr[["up"]])
  r5 <- r5d$ok
  r5_level <- p2_beta_asym(bdu[["down"]], bdu[["up"]])
  bs <- p2_bull_segments(PM$behavior$bull_phases %||% list(), PRX$behavior$bull_phases %||% list(), as.numeric(FS$bull_ratio), 2L)
  ucm <- g(PM, "behavior.summary.bull_up_capture_median"); ucr <- g(PRX, "behavior.summary.bull_up_capture_median")
  pa <- tryCatch(rk_pair_alpha(X$env$E, am, ar, TAU),
                 error = function(e) list(visible = list(d_alpha = NA_real_, t = NA_real_, n = NA_integer_, err = conditionMessage(e)), test = NULL))
  aok <- p2_alpha_ok(pa$visible, as.numeric(FS$alpha_t_floor), ea$alpha_ann, as.numeric(FS$alpha_margin_frac))
  cyc <- p2_cycle_compound(PM$behavior$bull_phases %||% list(), crm, PRX$behavior$bull_phases %||% list(), crr)
  cmv <- g(PM, "performance.strategy.calmar"); crv <- g(PRX, "performance.strategy.calmar")
  ptm <- g(PM, "performance.strategy.port_t"); ptr <- g(PRX, "performance.strategy.port_t")
  mvb <- c(g(PM, "behavior.summary.mdd_vs_bench"), g(PRX, "behavior.summary.mdd_vs_bench"))
  cdr <- c(g(PM, "behavior.stats.cdar"), g(PRX, "behavior.stats.cdar"))
  inp <- c(b = maj$share, d = dmj$share, beta_ratio = r5d$ratio, beta_ratio_rx0 = r5d$ratio_rx0, bull_share = bs$share, uc = ucm, cycle = cyc$share,
           calmar = cmv, calmar_rx0 = crv, port_t = ptm, port_t_rx0 = ptr, mdd_vs_bench = mvb, cdar = cdr)
  ## 진단 칸이 RX0 와 보유가 같으면(무처치 = 그 진단의 답) 증분 월 수익이 0 이라 증분 알파 t 가 0/0 — 그 경우만 알파 NA 를 미시험으로 접지 않는다(⑦ = 거짓)
  alpha_degenerate <- diag && !isTRUE(out$treatment_delivered) && is.na(aok)
  out$alpha_degenerate <- alpha_degenerate
  if (any(!is.finite(inp)) || (is.na(aok) && !alpha_degenerate)) {
    out$inputs <- c(as.list(inp), list(alpha_t = pa$visible$t, engine_alpha = ea$alpha_ann, cycle_pairs = cyc$n_pair, bull_pairs = bs$n_pair))
    return(.p2_untested(out, sprintf("판정 입력 NA(%s)", paste(c(names(inp)[!is.finite(inp)], if (is.na(aok)) "alpha"), collapse = ","))))
  }
  Sm <- rk_S(cmv, ptm, FS); Sr <- rk_S(crv, ptr, FS)
  r12 <- if (Sr > 0) Sm >= Sr - as.numeric(FS$tie_eps) else cmv >= crv
  r13 <- mvb[1] <= mvb[2] && cdr[1] <= cdr[2]
  ## ⑭ 선택 귀속 — 변형 칸 보는 창 패킷의 MC8 라벨(크기 · 평균 노출 짝 플라시보를 위기 과반에서 넘었나) = mc8_label_required ∧
  ##   위기 분해 '선택' 항(β · 크기 통제 뒤)이 깊은 위기 과반에서 RX0 보다 개선(변형 − RX0 > 0 · 문턱 없음 · C-028) — 둘 다 기록
  deep_peaks <- vapply(strsplit(deep, " "), `[`, "", 1)
  s14 <- p2_selection_rule(p2_selection_attr(PM$controls$attribution$label, FS$mc8_label_required, PM$controls$status %||% NA_character_),
                           p2_selection_decomp(PM$exposure$crises %||% list(), PRX$exposure$crises %||% list(), deep_peaks, MAJ))
  RL <- list(
    crisis    = c(maj, list(ok = p2_maj(maj$share, MAJ))),
    deep      = c(dmj, list(deep_keys = deep, ok = p2_maj(dmj$share, MAJ))),
    beta_deep = list(k = k, k_forced = bp$forced, comparator = bp$comparator, n_pair = b3$n_pair, share = b3$share,
                     status = if (!is.null(berr)) "unmeasured" else if (is.na(r3)) "unmeasured(짝 < 2)" else "ok", why = berr, ok = isTRUE(r3), per_crisis = b3$per_crisis),
    fast      = list(keys = fk$keys, table = fk$table, unclassified = fk$unclassified, n_pair = b4$n_pair, share = b4$share, classify_error = fk$err %||% NA_character_,
                     status = if (!is.null(berr)) "unmeasured" else if (is.na(r4)) "unmeasured(짝 < 2)" else "ok", ok = isTRUE(r4), per_crisis = b4$per_crisis,
                     record_excluding_no_month_end = list(excluded = fk$no_month_end, n_pair = b4x$n_pair, share = b4x$share)),
    slow      = list(keys = slow_keys, n_pair = bsl$n_pair, share = bsl$share, ok = if (bsl$n_pair >= 2L) p2_maj(bsl$share, MAJ) else NA, per_crisis = bsl$per_crisis,
                     note = "기록 — 느린 약세(빠름으로 분류되지 않은 위기)의 β 짝 비율(판정 아님)"),
    beta_asym = list(beta = c(variant = bm, rx0 = br0), down = bdu[["down"]], up = bdu[["up"]], rx0_down = bdr[["down"]], rx0_up = bdr[["up"]],
                     ratio = r5d$ratio, ratio_rx0 = r5d$ratio_rx0, delta = r5d$delta, ok = isTRUE(r5),
                     level_ok = r5_level, claim_tag = if (isTRUE(r5_level)) NA_character_ else "노출(β) 방어 — 비대칭 역행(하락 β ≥ 상승 β) · 방어 주장 불가(헌장 빈칸 3 · 8)"),
    bull      = c(bs[setdiff(names(bs), "per_phase")], list(uc_median = ucm, uc_median_rx0 = ucr, uc_floor = FS$uc_floor, per_phase = bs$per_phase,
                                                            ok = p2_maj(bs$share, MAJ) && ucm >= as.numeric(FS$uc_floor))),
    cycle     = c(cyc[setdiff(names(cyc), "per_cycle")], list(per_cycle = cyc$per_cycle, ok = p2_maj(cyc$share, MAJ))),
    path      = list(mdd_vs_bench = mvb, cdar = cdr, ok = r13),
    construction = list(checks = cs$checks, device = cs$device, holdings_differ = ov$n_differ, holdings_dates = ov$n_dates, ok = TRUE),
    selection = c(s14, list(share_beats_size_exposure = g(PM, "controls.attribution.share_beats_size_exposure"),
                            share_beats_exposure = g(PM, "controls.attribution.share_beats_exposure"),
                            n_crisis = g(PM, "controls.attribution.n_crisis"))))
  out$rules <- RL
  se <- if (is.finite(pa$visible$t) && pa$visible$t != 0) pa$visible$d_alpha / pa$visible$t else NA_real_
  mg <- as.numeric(FS$alpha_margin_frac) * max(ea$alpha_ann, 0)
  out$alpha_non_loss <- list(d_alpha = pa$visible$d_alpha, t = pa$visible$t, se = se, n = pa$visible$n, window = pa$visible$window, engine_alpha = ea,
                             t_floor = FS$alpha_t_floor, margin_frac = FS$alpha_margin_frac, margin = mg,
                             margin_over_se = if (is.finite(se) && se > 0) mg / se else NA_real_, ok = isTRUE(aok))
  out$alpha_test_window <- pa$test                                              # 사람 쪽 파일로만 나간다(본 실행이 분리 · p2_visible_only)
  out$non_inferiority <- list(S = Sm, S_rx0 = Sr, calmar = cmv, calmar_rx0 = crv, port_t = ptm, port_t_rx0 = ptr,
                              basis = if (Sr > 0) "S_vis − tie_eps" else "Calmar(S_rx0 = 0)", ok = isTRUE(r12))
  ## ⑧ 집중(깊은 위기 한 종목 기여) — 제외 판정 · ⑪ 회복 꼬리표 · 귀속(기록)
  tl <- p2_top_loss(PM$exposure$top_losers %||% list(), deep_peaks, as.numeric(FS$single_name_loss_floor))
  tl0 <- p2_top_loss(PRX$exposure$top_losers %||% list(), deep_peaks, as.numeric(FS$single_name_loss_floor))
  conc <- tryCatch(rk_concentration(am, TAU), error = function(e) list(visible = list(error = conditionMessage(e))))
  cst <- p2_conc_status(tl)
  out$concentration <- list(status = cst, visible = conc$visible, eff_n_mean = c(g(PM, "profile.eff_n_mean"), g(PRX, "profile.eff_n_mean")),
                            top_loss = tl[setdiff(names(tl), "per_crisis")], top_loss_rx0 = tl0[setdiff(names(tl0), "per_crisis")], per_crisis = tl$per_crisis,
                            concentration_loss_tag = identical(cst, "breach"), unmeasured_tag = identical(cst, "unmeasured"))
  out$recovery <- p2_recovery_tag(crm, crr, MAJ)
  ## 기준점 두 개(C-024) — 엔진 대비(① · ② = RX0 − tol) · 시장 대비(dd_capture < 1 − tol)
  out$reference_points <- list(engine = list(all = maj$share, deep = dmj$share),
                               market = list(all = p2_vs_market(crm, tol), deep = p2_vs_market(crm, tol, deep)),
                               market_rx0 = list(all = p2_vs_market(crr, tol), deep = p2_vs_market(crr, tol, deep)))
  out$attribution <- list(label = s14$label, label_rx0 = as.character(PRX$controls$attribution$label %||% NA)[1],
                          share_beats_size_exposure = RL$selection$share_beats_size_exposure, share_beats_exposure = RL$selection$share_beats_exposure,
                          share_beats_bench = g(PM, "controls.attribution.share_beats_bench"), median_placebo_p = g(PM, "controls.attribution.median_placebo_p"),
                          beta_copy_deep = RL$beta_deep$share,
                          reading = if (is.na(r3)) "β 짝 미측정 — 방어 이름 보류" else
                                    if (isTRUE(s14$ok) && isTRUE(r3)) "선택 방어 후보 — MC8 선택 귀속 ∧ 위기 분해 선택 항 ∧ β 짝 통과" else
                                    if (isTRUE(r3) && !isTRUE(s14$measured)) sprintf("β 짝 통과 · ⑭ 미측정(%s) — 방어 이름 보류", s14$status) else
                                    if (isTRUE(r3)) sprintf("β 짝 통과 · ⑭ 미통과(MC8 %s · 분해 %s) — 크기 방어 또는 노출 방어", s14$label, format(s14$decomposition$ok)) else
                                    "β 짝 미통과 — 노출(β) 방어 또는 방어 없음")
  ## 기록(판정 아님) — 상태 미전환 최대 하락 위기(C-019) β 짝 승패 · 위기 중 크기 분위 · 회전 · 비용 · 노출 · 롤링
  out$record <- list(state_unturned_max_drop = p2_crisis_record(crm, crr, cbp, FS$state_unturned_max_drop_crises, tol, deep, fk$keys),
                     size_decile = p2_size_compare(PM$exposure$by_size_decile %||% list(), PRX$exposure$by_size_decile %||% list(), deep_peaks),
                     rolling = PM$behavior$rolling, turnover_annual = c(variant = g(PM, "profile.turnover_annual"), rx0 = g(PRX, "profile.turnover_annual")),
                     cost_drag_annual = c(variant = g(PM, "profile.cost_drag_annual"), rx0 = g(PRX, "profile.cost_drag_annual")),
                     exposure_mean = c(variant = g(PM, "controls.exposure_profile.mean"), rx0 = g(PRX, "controls.exposure_profile.mean")),
                     crisis_dd_capture_median = c(variant = g(PM, "behavior.summary.crisis_dd_capture_median"), rx0 = g(PRX, "behavior.summary.crisis_dd_capture_median")))
  ## 판정 칸만(진단 칸 생략) — 크기 × β 짝(C-017) · 유동성 귀속(C-020) · 국면별 월 차이(C-020) · 실패 = 그 기록만 미측정 꼬리표
  if (!diag) {
    out$size_beta <- tryCatch(p2_size_beta_record(X, am, PM, crm, deep, tol, MAJ),
                              error = function(e) list(status = "unmeasured", tag = "크기 × β 짝 미측정", why = conditionMessage(e)))
    out$liquidity <- tryCatch(list(variant = p2_liquidity_record(X, am, crm, deep_peaks), rx0 = p2_liquidity_record(X, ar, crr, deep_peaks)),
                              error = function(e) list(status = "unmeasured", tag = "유동성 귀속 미측정", why = conditionMessage(e)))
    out$regime_months <- tryCatch(p2_regime_months(X, am, ar, PM), error = function(e) list(status = "unmeasured", why = conditionMessage(e)))
  }
  out$conclusion_name <- p2_defense_name(r3, r4, r5_level, s14$ok, out$size_beta$ok %||% NA, out$size_beta$status %||% (if (diag) "skipped_diagnostic" else "unmeasured"),
                                         s14_measured = isTRUE(s14$measured))
  out$pass <- p2_cell_pass(list(crisis = RL$crisis$ok, deep = RL$deep$ok, beta_deep = r3, fast = r4, beta_ratio = r5, bull = RL$bull$ok, alpha = aok,
                                cycle = RL$cycle$ok, construction = RL$construction$ok, S = r12, path = r13, selection = s14$ok))
  out$verdict <- p2_cell_verdict(list(pass = out$pass, beta_unmeasured = !is.null(berr), beta_deep = r3, fast = r4, crisis = RL$crisis$ok, deep = RL$deep$ok,
                                      selection = s14$ok, selection_measured = isTRUE(s14$measured)))
  out$verdict_name <- P2R04_VERDICT_NAMES[[out$verdict]]
  out$tested <- TRUE
  out$tbl <- data.table(engine = eng, device = dev, tested = TRUE, pass = out$pass, excluded = !identical(cst, "clear"), verdict = out$verdict)
  out
}
## 판정 1칸 안전 호출 — 이름 붙은 분기 밖의 예기치 않은 오류도 그 칸만 미시험으로 접는다(오류 문구 기록 · 라운드 평가는 계속)
p2_eval_pair_safe <- function(X, eng, dev, cm, cr, em, er, opts = list())
  tryCatch(p2_eval_pair(X, eng, dev, cm, cr, em, er, opts),
           error = function(e) .p2_untested(list(engine = eng, device = dev, role = opts$role %||% "judge", cell = cm$code, rx0 = cr$code,
                                                 status = em$status %||% NA, status_rx0 = er$status %||% NA), paste("평가 오류:", conditionMessage(e))))

if (sys.nframe() == 0L) {   # ── 본 실행(스크립트로 불렸을 때만 — 픽스처 · 리허설 · precheck 는 위 함수만 적재) ──
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/contracts/beta_controlled_alpha.R")
source("02_Infrastructure/programs/program_registry.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
CELLS_ONLY <- "--cells-only" %in% commandArgs(trailingOnly = TRUE)
RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE", P2R04_ROUND_ID)
PR <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE", P2R04_ROUND_ID, "prereg.json")
if (!file.exists(PR)) stop("[P2R04 평가] 사전등록 없음 — 평가하지 않는다(R2)")
reg <- pr_load(ROOT); rr <- Filter(function(r) identical(r$round_id, P2R04_ROUND_ID), pr_get(reg, "P2_DEFENSE")$rounds)
if (!length(rr) || !identical(rr[[1]]$prereg_md5, rk_md5(PR))) stop("[P2R04 평가] 사전등록 md5 불일치(R2)")
pre <- fromJSON(PR, simplifyVector = FALSE)
if (!identical(pre$round_id, P2R04_ROUND_ID)) stop("[P2R04 평가] 사전등록 round_id ≠ ", P2R04_ROUND_ID)
BCFG <- file.path(ROOT, pre$behavior_card_cfg$path)
if (!identical(rk_md5(BCFG), pre$behavior_card_cfg$md5)) stop("[P2R04 평가] 행동 카드 설정 사본 변경")
pin <- p2_pin_mismatches(pre, ROOT)                                            # 평가 시점 핀 전체 재대조(샤드 포함)
if (length(pin)) stop("[P2R04 평가] 핀 불일치 — 평가하지 않는다:\n", paste0("  · ", pin, collapse = "\n"))
pc <- file.path(RD, "results", "precheck.json")
if (!file.exists(pc) || !isTRUE(fromJSON(pc)$ok)) stop("[P2R04 평가] precheck 통과 기록이 없다 — 측정 조건 미확인")
TAU <- as.Date(pre$tau_d); FS <- pre$final_selection_rule
fsm <- p2_fs_missing(FS); if (length(fsm)) stop("[P2R04 평가] final_selection_rule 키 결손 — 평가하지 않는다: ", paste(fsm, collapse = ","))
cbad <- p2_cells_check(pre$cells); if (length(cbad)) stop("[P2R04 평가] 사전등록 칸 목록 불일치:\n", paste0("  · ", cbad, collapse = "\n"))
RES <- file.path(RD, "results")
env <- new.env(); env$E <- .dp_deps(ROOT); env$BCFG_L <- env$E$bc_cfg(ROOT, path = BCFG); env$raw <- NULL; env$liq <- NULL
CELLS <- if (CELLS_ONLY) rk_shard(pre$cells) else pre$cells
EVS <- lapply(CELLS, function(cl) p2_eval_cell(ROOT, RES, cl, env, TAU)); names(EVS) <- vapply(CELLS, function(z) z$code, character(1))
for (cd in names(EVS)) if (!is.null(EVS[[cd]]$artifacts)) {                    # 칸 평가 캐시 = 현 측정 산출물(재측정 뒤 옛 캐시 혼입 차단)
  rj <- file.path(RES, paste0(cd, ".json"))
  a0 <- if (file.exists(rj)) fromJSON(rj, simplifyVector = FALSE)$artifacts else NULL
  if (!identical(EVS[[cd]]$artifacts, a0)) stop(sprintf("[P2R04 평가] %s 칸 평가 캐시의 산출물 ≠ 현 측정 산출물 — results/%s/ 를 지우고 다시 평가", cd, cd))
}
cat(sprintf("[P2R04 평가] 칸 평가 %d/%d(진단 칸 포함)\n", sum(vapply(EVS, function(e) e$status %in% c("evaluated", "axis_violation"), logical(1))), length(EVS)))
if (CELLS_ONLY) quit(status = 0)

JCELLS <- Filter(function(z) !isTRUE(z$diagnostic), pre$cells); DCELLS <- Filter(function(z) isTRUE(z$diagnostic), pre$cells)
cell_of <- function(eng, comp) Filter(function(z) identical(z$engine, eng) && identical(z$component, comp), pre$cells)[[1]]
dfr <- Filter(function(cl) { j <- file.path(RES, paste0(cl$code, ".json")); if (!file.exists(j)) return(FALSE)
                             r <- fromJSON(j, simplifyVector = FALSE); !isTRUE(r$ok) && !is.null(r$deferred) }, JCELLS)
if (length(dfr)) stop("[P2R04 평가] 측정 연기 칸 — 재측정(measure.sh) 뒤 평가: ", paste(vapply(dfr, function(z) z$code, ""), collapse = ","))
fp_of <- function(code, tag) { f <- file.path(RES, sprintf("%s.fp_%s", code, tag)); if (file.exists(f)) paste(readLines(f, warn = FALSE), collapse = "|") else NA_character_ }
FP_EVAL <- p2_fingerprint(RD, "equality")
X <- list(root = ROOT, res = RES, out = RES, env = env, fs = FS, tau = TAU, ea = new.env())
ENGINES <- unique(vapply(JCELLS, function(z) z$engine, character(1)))
DEVS <- sort(unique(setdiff(vapply(JCELLS, function(z) z$component, character(1)), "RX0")))
OUT <- list(); TBL <- list(); FPG <- list()
for (eng in ENGINES) {
  cr <- cell_of(eng, "RX0")
  codes <- unname(c(vapply(DEVS, function(dv) cell_of(eng, dv)$code, character(1)), cr$code))
  fps <- unname(unlist(lapply(codes, function(cd) c(fp_of(cd, "start"), fp_of(cd, "end")))))
  if (anyNA(fps) || length(unique(fps)) != 1L) stop(sprintf("[P2R04 평가] %s 묶음 데이터 지문 불일치 또는 부재 — 그 묶음을 재측정한 뒤 평가(rules.vintage_group)", eng))
  FPG[[eng]] <- list(measure = fps[1], eval_matches_measure = p2_fp_same(fps[1], FP_EVAL))
  for (dv in DEVS) {
    cm <- cell_of(eng, dv)
    od <- p2_eval_pair_safe(X, eng, dv, cm, cr, EVS[[cm$code]], EVS[[cr$code]])
    TBL[[cm$code]] <- od$tbl; OUT[[cm$code]] <- od
  }
}
## 진단 칸(판정 표 밖) — 같은 엔진 RX0 대비 같은 판정 함수(role diagnostic) · 지문이 엔진 묶음과 다르면 그 진단만 미시험(판정은 멈추지 않는다)
DOUT <- list()
for (cl in DCELLS) {
  cr <- cell_of(cl$engine, "RX0"); fpd <- c(fp_of(cl$code, "start"), fp_of(cl$code, "end"))
  DOUT[[cl$code]] <- if (anyNA(fpd) || is.null(FPG[[cl$engine]]) || !all(fpd == FPG[[cl$engine]]$measure))
    .p2_untested(list(engine = cl$engine, device = cl$component, role = "diagnostic", cell = cl$code, rx0 = cr$code), "진단 칸 데이터 지문 ≠ 엔진 묶음 지문(또는 부재)") else
    p2_eval_pair_safe(X, cl$engine, cl$component, cl, cr, EVS[[cl$code]], EVS[[cr$code]],
                      opts = list(role = "diagnostic", expect_weight = p2_diag_expect_weight(cl$component, pre$cells, ROOT)))
}
## 기록 계산은 안전 호출 — 비싼 짝 평가 뒤에 기록 하나의 예외가 판정 전체를 멈추지 않는다(실패 = 그 기록만 오류 표기)
.safe_rec <- function(expr) tryCatch(expr, error = function(e) list(status = "error", why = conditionMessage(e)))
READ <- .safe_rec(p2_readings(OUT, DOUT, as.numeric(FS$crisis_improve_min), DEVS))
## A 거리(C-031 · 칸마다 · 판정 아님) — 칸 평가 보는 창 패킷(원 창)의 gv3 A 하한 값 · 문턱(grade_v3 gv3_thresholds · gv3_cfg) · 거리
GV3 <- .safe_rec(list(th = env$E$gv3_thresholds(ROOT), cfg = env$E$gv3_cfg(ROOT)))
ADIST <- setNames(lapply(names(EVS), function(cd) .safe_rec({
  pk <- p2_pk_read(X, cd)
  if (is.null(pk)) list(status = "no_packet") else if (identical(GV3$status, "error")) list(status = "unmeasured", why = GV3$why) else {
    S <- env$E$gv3_S(rk_getf(pk, "performance.strategy.calmar"), rk_getf(pk, "performance.strategy.port_t"), GV3$th, GV3$cfg$weights)
    c(list(status = "ok", window = unlist(pk$window)), p2_a_distance(pk$performance$strategy, rk_getf(pk, "performance.benchmark.calmar"), GV3$th, S, GV3$cfg$a_boundary)) }
})), names(EVS))
RXI <- setNames(lapply(ENGINES, function(eng) tryCatch(p2_rx0_identity(X, EVS[[cell_of(eng, "RX0")$code]]$artifacts, file.path(ROOT, sprintf(P2R04_P2R03_RX0, eng))),
                                                      error = function(e) list(status = paste("오류:", conditionMessage(e))))), ENGINES)
TB <- rbindlist(TBL)                                                             # 판정 표 = 장치 칸(엔진 × 장치 · 진단 칸 없음)
rv <- p2_round_verdict(TB)
validated <- rv$both
xs_by <- setNames(lapply(validated, function(dv) Filter(function(x) identical(x$device, dv), OUT)), validated)
sel <- p2_select(xs_by)
NOISE <- .safe_rec(p2_noise_reading(OUT, validated, FS$tie_eps, FS$majority_share, DEVS))   # R7 판독(C-029)
excl <- lapply(rv$excluded, function(dv) list(device = dv, concentration = unique(vapply(Filter(function(x) identical(x$device, dv), OUT),
                                                                                         function(x) as.character(x$concentration$status %||% "NA"), character(1)))))
## 칸 요약 표(보는 창 · 실패 지도 입력) — 판정 · 이름 · 귀속 · 보유 겹침 · 상태 미전환 최대 하락 위기 β 짝 승패 · 크기 × β · 진단 칸 포함(role)
SUMMARY <- rbindlist(lapply(c(OUT, DOUT), function(x) {
  su <- as.data.table(x$record$state_unturned_max_drop %||% data.table())
  data.table(role = x$role %||% "judge", engine = x$engine, device = x$device, factor = x$device_factor$id %||% NA_character_, cell = x$cell, tested = isTRUE(x$tested),
             verdict = x$verdict %||% NA_character_, verdict_name = x$verdict_name %||% NA_character_, pass = isTRUE(x$pass),
             conclusion_name = x$conclusion_name %||% NA_character_, attribution = x$attribution$label %||% NA_character_,
             selection_status = x$rules$selection$status %||% NA_character_, selection_decomp_ok = x$rules$selection$decomposition$ok %||% NA,
             beta_deep = x$rules$beta_deep$status %||% NA_character_, fast = x$rules$fast$status %||% NA_character_,
             size_beta = x$size_beta$status %||% NA_character_, size_beta_ok = x$size_beta$ok %||% NA,
             holdings_differ = x$holdings_overlap$n_differ %||% NA_integer_, holdings_dates = x$holdings_overlap$n_dates %||% NA_integer_,
             name_overlap_mean = x$holdings_overlap$name_overlap_mean %||% NA_real_, name_overlap_min = x$holdings_overlap$name_overlap_min %||% NA_real_,
             state_unturned_beats_beta = if (nrow(su) && "beats_beta_copy" %in% names(su)) paste(ifelse(is.na(su$beats_beta_copy), "NA", su$beats_beta_copy), collapse = ",") else NA_character_,
             concentration = x$concentration$status %||% NA_character_)
}), fill = TRUE)
VIS <- list(schema = "p2r04_evaluation_visible_v1", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = rk_md5(PR),
            evaluate_md5 = rk_md5(file.path(RD, "evaluate.R")), tau_d = pre$tau_d, devices = P2R04_DEVICES, diagnostics_def = P2R04_DIAGNOSTICS,
            verdict_names = as.list(P2R04_VERDICT_NAMES), cells = lapply(OUT, p2_visible_only, tau = TAU), diagnostics = lapply(DOUT, p2_visible_only, tau = TAU),
            readings = p2_visible_only(READ, TAU), rx0_identity = RXI, a_distance = ADIST, noise_reading = NOISE, capacity_table = P2R04_CAPACITY_TABLE,
            table = TB, summary = SUMMARY,
            verdict = rv$verdict, verdict_label = rv$label, n_judged = rv$n_judged, n_total = rv$n_total, pass_both = rv$both, pass_one = rv$one,
            excluded = excl, validated = validated, selected = sel, engine_alpha = as.list(X$ea),
            fingerprint = list(eval = FP_EVAL, eval_record = p2_fingerprint(RD, "record"), groups = FPG),
            precheck = list(ok = isTRUE(fromJSON(pc)$ok), at = fromJSON(pc)$at, prereg_md5 = fromJSON(pc)$prereg_md5))
## 보는 창 파일 전수 검사(C-031) — 메타(평가 · precheck 시각 · 지문) 밖에서 τ_D 이후 날짜가 하나라도 남으면 쓰지 않는다
bad_dates <- dp_scan_dates(VIS[setdiff(names(VIS), c("evaluated_at", "precheck", "fingerprint"))], TAU)
if (length(bad_dates)) stop(sprintf("[P2R04 평가] 보는 창 파일에 τ_D 이후 날짜 %d개 — 쓰지 않는다(C-031 · 가림 결함)", length(bad_dates)))
FULL <- list(schema = "p2r04_evaluation_full_v1", audience = P2R04_FULL_AUDIENCE, evaluated_at = VIS$evaluated_at, prereg_md5 = VIS$prereg_md5,
             cells = lapply(names(EVS), function(cd) { x <- c(OUT, DOUT)[[cd]]
                                                        list(code = cd, test = EVS[[cd]]$test, full = EVS[[cd]]$full, alpha_test_window = x$alpha_test_window %||% NULL,
                                                             cell_log_full_period = x$cell_log_full_period %||% NULL, why = x$why %||% NULL) }))   # 셀 로그 셈 · 미시험 사유 원문 = 사람 쪽
writeLines(toJSON(FULL, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RES, "evaluation_full.json"), useBytes = TRUE)
writeLines(toJSON(VIS, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RES, "evaluation_visible.json"), useBytes = TRUE)
for (x in c(OUT, DOUT)) cat(sprintf("[P2R04 평가] %s%s %s(%s) — %s · %s%s · 창 %s · ① %s ② %s ③ %s ④ %s ⑤ %s ⑥ %s ⑦ %s ⑨ %s ⑩ %s ⑫ %s ⑬ %s ⑭ %s(%s · %s) · 집중 %s · 보유 다름 %s/%s · 크기 × β %s\n",
                           if (identical(x$role, "diagnostic")) "[진단] " else "", x$engine, x$device, x$device_factor$id %||% "-", x$verdict, x$verdict_name %||% "-",
                           if (!isTRUE(x$tested)) paste0("(", .p2_redact_chr(x$why %||% "-", TAU), ")") else "", x$window %||% "-",
                           isTRUE(x$rules$crisis$ok), isTRUE(x$rules$deep$ok), x$rules$beta_deep$status %||% "-", x$rules$fast$status %||% "-",
                           isTRUE(x$rules$beta_asym$ok), isTRUE(x$rules$bull$ok), isTRUE(x$alpha_non_loss$ok), isTRUE(x$rules$cycle$ok),
                           isTRUE(x$rules$construction$ok), isTRUE(x$non_inferiority$ok), isTRUE(x$rules$path$ok), isTRUE(x$rules$selection$ok),
                           x$rules$selection$label %||% "-", x$rules$selection$status %||% "-", x$concentration$status %||% "-",
                           format(x$holdings_overlap$n_differ %||% NA), format(x$holdings_overlap$n_dates %||% NA), x$size_beta$status %||% "-"))
for (h in DEVS) cat(sprintf("[P2R04 평가] 진단 읽기 %s — 결측 짝 %s · 용량 짝 %s · 희석 몫 %s\n", h, READ$missing[[h]]$tag %||% READ$missing[[h]]$status %||% "-",
                            READ$capacity[[h]]$label %||% "-", READ$dilution$by_device[[h]]$tag %||% READ$dilution$by_device[[h]]$status %||% "-"))
pj <- function(x) if (length(x)) paste(x, collapse = ",") else "-"
cat(sprintf("[P2R04 평가] R7 판독 %s(%s) — 판정된 장치 %s · 빠진 장치 %s · 검증 0 %s · ③ 두 구성 과반 장치 0 %s · S 증분 최대 < tie_eps %s\n",   # %||% = 길이 0 인수로 줄이 사라지지 않게
            NOISE$label %||% "-", format(NOISE$result %||% NA), NOISE$judged_devices %||% "-",
            if (length(NOISE$dropped)) paste(vapply(NOISE$dropped, function(z) sprintf("%s(%s)", z$device, z$why), character(1)), collapse = " · ") else "-",
            format(NOISE$components$no_validated %||% NA), format(NOISE$components$no_device_r3_both %||% NA), format(NOISE$components$max_dS_below_tie %||% NA)))
cat(sprintf("[P2R04 평가] 판정 %s · 두 엔진 통과 %s · 한 엔진 %s · 집중 제외 %s · 선택 %s · 평가 지문 = 측정 지문 %s · RX0 동일성 %s\n", rv$label, pj(rv$both), pj(rv$one),
            pj(rv$excluded), if (length(sel)) sel[[1]]$device else "-",
            paste(vapply(names(FPG), function(e) sprintf("%s:%s", e, FPG[[e]]$eval_matches_measure), ""), collapse = " "),
            paste(vapply(names(RXI), function(e) sprintf("%s:보유 %s · 수익 %s(다른 달 %s)", e, format(RXI[[e]]$holdings_same %||% NA), format(RXI[[e]]$returns_same %||% NA),
                                                          format(RXI[[e]]$months_differ %||% NA)), ""), collapse = " ")))
}
