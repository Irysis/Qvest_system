## P2R05 평가 — 원천 ① 분포 표적(같은 DNN5 · 같은 31 특징 · 같은 일정에서 출력층 · 손실만 분위로) × 소비 규칙 2(V1 꼬리 거부 · V2 꼬리 순위) ×
##   구성 2(E2 DNN 원형 EW · E3 B6_36 엔트로피 비중) vs 같은 배치 평균 표적 RX0 → 사전등록 규칙(stage_artifacts prereg.json rules · final_selection_rule)을
##   기계 적용(R2). 수치는 R 계약 산출(dp_build 보는 창 패킷 · mc_card · rk_S · rk_pair_alpha · beta_controlled_alpha · matched_controls 크기 바스켓 ·
##   behavior_card 위기 포착 · 정본 NW backtest_result_contract.R::.nw_t_mean — 손계산 없음 · AX-008). 이 파일이 더하는 것은 규칙 적용 · 공통 창 · β 짝 사본 ·
##   빠른 급락 분류 · 셀 로그 · 보유 대조 · ⑮ 꼬리 계기(예측표 + RAWDATA 라벨 재도출) · 기록 · 진단 읽기 · 결론 이름뿐.
##   P2R04 evaluate.R(픽스처 53 · 리허설 통과판)을 이어받았다. 바뀐 곳(규칙 번호별 — DESIGN_draft §0b · §4 · §5 · §10 · §12 · Q 10-18 지시 3건):
##     · 장치 H1~H4(외부 방어 팩터 틸트) → 소비 규칙 V1 · V2(엔진 안 분위 학습 — 사양은 base_signal.path 만 바뀐다)
##     · 진단 칸 C · W · N0 → Q50 · N1 · N2 · S1 · S2 · W2(E2) + 비교 기준 LV(E2 · E3 — P2R04 W2 사양 사본 · 판단 Superfan T2 C-20261018-038)
##     · ⑩ 개정((a) 엔진 핀 · 워밍 센티널 · 기저 적재 줄 (b) 템플릿 차분 대조 · months= (c) 전달량(≠ RX0 · V1 ≠ Q50) (d) 교차율 · q̂ 횡단면 표준편차)
##     · ⑮ 신설(꼬리 계기 · 시험 조건) · 칸 통과에 ⑮ 추가(13조건) · 판정어 untested_tail_instrument
##     · 진단 읽기 6종(§5.1 중심 · 희석(① 등록 + 깊은 위기 기록) · 변동성 누출 · 꼬리 고유 · 용량 + LV) · 결론 이름(§10.2 ~ 10.4 + LV)
##     · 기록 추가(§5.2 꼬리 기량 · 전이 · 귀속 · 위기 유형별 β 짝 승패 · 판정 여유 · Dimson β 짝 판) · R7 판독 두 성분(등록 · 방어 — 철학 P2 R-20261018-006)
##     · RX0 동일성 = P2R04 같은 구성 RX0 대비 · 평가 센티널 night_state/p2r05_evaluated.done(P2R04 형식) · 평가 중단 사유 results/evaluation_halt.json
##     · 재시드 칸 RX0S · 시드 띠 · 계기 → 다음 행동 표 · D^w · D^H · 꼬리 증분 · 같은 추첨 판독(Q50 × k') · P2 정지 보고 재료 · 부록 A 예측(판단 T1 R-007 · 철학 P1 R-008)
##     · 유동성 구간별 위기 손익 귀속(3분위 · 고점일 t−1 거래대금 · 계약 03 ret_gross 대조 단정 · '저유동 귀속' · '유동성 귀속 미측정' — 철학 P4 C-20261018-076)
##   판정 ①~⑭ 코드 경로 · 상수는 P2R04 그대로(β 짝 · 빠른 급락 · β 비 · 강세 · 알파 · 사이클 · S · 경로 · 집중 · 회복 · MC8 ∧ 위기 분해 선택 항 ·
##   평가 지문 = 측정 지문 · τ_D 분리 · R7 판독 · 판정어 · 라운드 판정 문장). 뺀 것: 장치 팩터 꼬리 반복 대조(LV 칸에만 남김) · 결측 짝 · 용량 4칸 표 · 희석 N0.
## 실행: Rscript evaluate.R [--cells-only] [--shard=i/K]      (측정 = measure.sh · 리허설 = rehearse.R · 픽스처 = evaluate_fixture.R)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
## bare "bash" 금지(금칙 ⑦) — WSL 있는 메인 PC 에선 System32 bash(리눅스)가 fingerprint.sh 를 못 열어 지문이 오류 문구가 됐다.
##   2026-11-08 환경 최신화 재고정(도훈 승인 "P2R05 다시 고정")에 함께 넣은 수리 — 지문 함수의 셸만 바꾼다(지문 정의 · 입력 불변).
if (!exists("qv_bash", mode = "function")) source(file.path(ROOT, "02_Infrastructure/ops/qv_bash.R"))

P2R05_ROUND_ID <- "P2R05_distribution_target"
## ── 경로 계약(DESIGN §7 · §12 — 다른 구현 에이전트 산출과 맞물리는 곳 · 이름만 맞춘다) ─────────────────────────────
P2R05_DT_DIR         <- "04_Research/strategies/DT_2002_06975"                       # 분위 엔진(템플릿 · 생성 엔진 7 · 예측표)
P2R05_RX0_ENGINE     <- "04_Research/strategies/RP_AUTO_2002_06975/engine.R"         # 평균 표적 기저(RX0 · W2 · LV)
P2R05_CODE_VERSION   <- "DT_2002_06975/dnn_quantile/rev1"                            # 분위 캐시 판본(DESIGN §7.2 · §12)
P2R05_WARM_SENTINEL  <- "04_Research/programs/_lib/night_state/p2r05_warm.done"      # 워밍 센티널(JSON · warm_cache.sh)
P2R05_EVAL_SENTINEL  <- "04_Research/programs/_lib/night_state/p2r05_evaluated.done" # 평가 센티널(P2R04 형식 한 줄)
P2R05_TEMPLATE_CHECK <- "04_Research/strategies/DT_2002_06975/template_diff_check.R" # ⑩(b) 템플릿 차분 대조(평가 때 다시 실행 · rc 0)
P2R05_QPRED_DIR      <- "04_Research/strategies/DT_2002_06975/_work/qpred"           # 예측표 *.parquet
P2R05_QPRED_COLS     <- c("Date", "Ticker", "q10", "q50", "q90", "q10_raw", "q50_raw", "q90_raw", "s_perm", "s_sigma", "sigma252")
P2R05_Q_COLS         <- c("q10", "q50", "q90", "q10_raw", "q50_raw", "q90_raw")        # 파일 간 동일성을 단정하는 q 열
P2R05_QPRED_OPT_COLS <- c("s_hist")                                                  # 선택 열(철학 P1 R-20261018-008 C-065 · 에이전트 A) — 없으면 D^H 미측정(평가 중단 아님)
P2R05_NW_SOURCE      <- "02_Infrastructure/contracts/backtest_result_contract.R"     # 정본 NW(.nw_t_mean — 정의만 파싱 · 사본 금지)
P2R05_RAWDATA        <- ".cache/RAWDATA.parquet"
P2R05_CRISIS_TYPE_NOTE <- "04_Research/programs/P2_DEFENSE/_design_notes/crisis_type_classify.json"   # 위기 유형(Q · 벤치 · 위생 유니버스 일수익)
P2R05_ONSET_NOTE     <- "04_Research/programs/P2_DEFENSE/_design_notes/onset_state_classify.json"   # 시작 시점 분류 기록(벤치만 · 결론 이름 아님 — 권고 1(b))
P2R05_BOUNDARY_EPS   <- 1e-9    # 위기 유형 '경계' = |rho_W − 문턱| < 1e-9(부동소수 여유 · Q 지시 10-18 · 결정 수치 아님)
P2R05_P2R04_RX0      <- "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/results/P2R04_%s_RX0.json"   # RX0 동일성 대조 원천(json 의 ok · artifacts 만)

## ── 소비 규칙 표(DESIGN §3.4 · 판정 칸 = 규칙 × 구성) ────────────────────────────────────────────────────────────────
P2R05_RULES <- list(
  V1 = list(engine = "engine_V1.R", name = "꼬리 거부", rule = "q̂10 이 U_d 안 하위 몫(순위/N ≤ .DT_VETO_SHARE · 동률 평균)이면 NA · 나머지 = q̂50",
            basis = "Bassett, Koenker & Kordas (2004) 비관 배분 제약형 · 거부 몫 = 논문 5분위 정렬 단위(Abe & Nakagawa 2020)"),
  V2 = list(engine = "engine_V2.R", name = "꼬리 순위", rule = "점수 = q̂10(비관 점수 λ = 1)",
            basis = "Bassett, Koenker & Kordas (2004) 목적형 · Atilgan, Bali, Demirtas & Gunaydin (2020) 좌꼬리 모멘텀"))
## ── 진단 · 비교 기준 칸 표(DESIGN §4 · Q 10-18 LV) — cells[].diagnostic = true · 판정 표 · 규칙 검증 · 최종 선택 밖 ─────────────────
P2R05_DIAG_ENGINE <- "E2"                                                       # 중심 · 희석 · 변동성 · 꼬리 고유 · 용량 읽기의 정의 구성
P2R05_DIAGNOSTICS <- list(
  Q50 = list(reading = "center",   control = "center_only",   engines = "E2", engine_file = "engine_Q50.R", pair = c("V1", "V2"),
             note = "중앙값만 — 추정 대상 '평균 → 중앙값'만의 효과(꼬리 미사용) · V1 − Q50 = 거부의 효과"),
  N1  = list(reading = "dilution", control = "tail_perm",     engines = "E2", engine_file = "engine_N1.R",  pair = "V1",
             note = "무정보 꼬리 순열 짝(V1) — s 를 신호일 안에서 무작위 순열 · q̃10 = q̂50 − s_perm 으로 V1"),
  N2  = list(reading = "dilution", control = "tail_perm",     engines = "E2", engine_file = "engine_N2.R",  pair = "V2",
             note = "무정보 꼬리 순열 짝(V2) — q̂50 − s_perm"),
  S1  = list(reading = "vol_leak", control = "vol_proxy",     engines = "E2", engine_file = "engine_S1.R",  pair = "V1",
             note = "변동성 순위 대응 짝(V1) — 그날 s 값을 직전 252거래일 실현 변동성 순위대로 재배정 · q̃10_σ = q̂50 − s_σ 로 V1"),
  S2  = list(reading = "vol_leak", control = "vol_proxy",     engines = "E2", engine_file = "engine_S2.R",  pair = "V2",
             note = "변동성 순위 대응 짝(V2) — q̂50 − s_σ"),
  W2  = list(reading = "capacity", control = "capacity_pair", engines = "E2", blend = TRUE,                pair = "V2",
             note = "용량 짝(V2) — engine_blend [engine.R(평균) · engine_V2.R] = 0.5 rank-Z(평균) + 0.5 rank-Z(q̂10) · E3 처치 몫(50%)을 E2 에서 재현"),
  LV  = list(reading = "lowvol_screen", control = "lowvol_screen", engines = c("E2", "E3"), pair = c("V1", "V2"),
             factor = list(kind = "db", id = "D03_RealVol", name = "저변동"), weight_toolbox_on = "E3",
             note = "비교 기준 — 저용량 변동성 스크린(P2R04 E2 · E3 W2 사양 사본 · RX0 엔진 + D03_RealVol 몫 = 도구 상자 기본 12.5% · 판단 Superfan T2 C-20261018-038)"),
  RX0S = list(reading = "seed_band", control = "seed_pair", engines = c("E2", "E3"), reseed = TRUE, pair = c("V1", "V2"),
              note = "재시드 짝 — RX0 와 시드만 다른 평균 DNN(판단 Superfan T1 R-20261018-007 C-054) · 시드 띠 = 위기마다 |포착(RX0S) − 포착(RX0)| · S 띠 = |S(RX0S) − S(RX0)| · control = seed_pair(측정 기계 칸 표와 같음 · Q 10-18 통합 정렬 1)"))
P2R05_P2R04_LV <- "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/results/P2R04_%s_W2.json"   # LV ↔ P2R04 W2 동일성 대조 원천(json 의 ok · artifacts 만)
## 용량 읽기 표(DESIGN §5.1 · 위에서 아래로 첫 일치 · NA = 상관없음) — 세 칸의 통과: E2_V2 · W2(용량 짝) · E3_V2
P2R05_CAPACITY_TABLE <- data.table(
  e2_v2 = c(TRUE, TRUE,  NA,    FALSE),
  w2    = c(NA,   FALSE, TRUE,  FALSE),
  e3_v2 = c(TRUE, FALSE, FALSE, FALSE),
  label = c("같은 처치가 두 구성에서 통과(E2_V2 · E3_V2)", "용량 의존(E2_V2 통과 · W2 미달 · E3_V2 미달)",
            "구성 의존(W2 통과 · E3_V2 미달)", "이 형태 미달(E2_V2 · W2 · E3_V2 모두 미달)"))
P2R05_FULL_AUDIENCE <- "사람 쪽 판정 전용(τ_D 2022-12-31 이후 · 전기간 포함) — 보는 창 리뷰어(철학 P1 · P2 · P4 · 판단 Superfan · 처방 레인) 열람 금지(C-031)"
## 사전등록 final_selection_rule 에 있어야 하는 키(P2R04 와 같은 이름 + ⑮ tail_instrument) · 없으면 평가하지 않는다
P2R05_FS_KEYS <- c("calmar_norm", "port_t_norm", "w_calmar", "w_port_t", "tie_eps", "uc_floor", "majority_share", "crisis_improve_min",
                   "alpha_t_floor", "alpha_margin_frac", "single_name_loss_floor", "bull_ratio", "fast_window_days", "fast_drop",
                   "mc8_label_required", "state_unturned_max_drop_crises", "tail_instrument")
P2R05_TAIL_KEYS <- c("tau", "ref", "nw_lag", "t_min")
## 칸 판정 어휘(사전 고정 · P2R04 + ⑮) — '방어만 · 복리 없음' 이름 = '꼬리 회피 기계'(DESIGN §10.3)
P2R05_VERDICTS <- c("pass", "not_decisive", "exposure_only", "selection_unmeasured", "size_or_exposure_defense", "fast_unmeasured", "beta_unmeasured",
                    "asymmetry_unmet", "defense_but_strength_or_path", "untested", "untested_tail_instrument")
P2R05_VERDICT_NAMES <- c(pass = "통과", not_decisive = "결정 미달", exposure_only = "노출 방어(β 짝 미통과)",
                         selection_unmeasured = "선택 귀속 미측정 — 방어 이름 보류",
                         size_or_exposure_defense = "크기 · 노출 방어(⑭ 미통과)", fast_unmeasured = "빠른 급락 미측정", beta_unmeasured = "β 대조 미측정",
                         asymmetry_unmet = "β 비대칭 미달(⑤ 수준 또는 Δ — 꼬리 회피 기계 아님)",
                         defense_but_strength_or_path = "꼬리 회피 기계(방어만 · 복리 없음 — ⑥ · ⑦ · ⑨ · ⑫ · ⑬ 중 미달)", untested = "미시험",
                         untested_tail_instrument = "미시험(꼬리 계기 — 원천 ① 반증 아님)")
P2R05_VERDICT_SHORT <- c(pass = "통과", not_decisive = "결정 미달", exposure_only = "노출 방어", selection_unmeasured = "⑭ 미측정",
                         size_or_exposure_defense = "크기 · 노출 방어", fast_unmeasured = "빠른 급락 미측정", beta_unmeasured = "β 짝 미측정",
                         asymmetry_unmet = "β 비대칭 미달", defense_but_strength_or_path = "꼬리 회피 기계", untested = "미시험", untested_tail_instrument = "꼬리 계기 미시험")
P2R05_MC8_LABELS <- c("selection_defense", "size_defense", "exposure_defense", "no_defense")
P2R05_PIN_KINDS <- c("files", "catalog_entries", "overlay_arms", "factor_registry_entries", "packages", "r_version")
P2R05_VISIBLE_DROP <- c("alpha_test_window", "tbl", "cell_log_full_period")
P2R05_REDACT <- "[τ_D 이후 날짜 가림]"
P2R05_FULL_MARK <- "NO_VISIBLE_REVIEW.txt"
P2R05_FULL_MARK_PARENT <- "이 폴더의 visible* 하위 폴더(보는 창 패킷)만 보는 창 리뷰어 열람 가능 — artifacts · rx0_artifacts · rx0_beta_scaled · rx0_dimson_scaled = 전기간 사본(열람 금지)"
## 사양 구성 키(셀 엔진 · 워커가 읽는 키 — base_signal 은 따로 대조) · fixed_axes 는 '_note' 로 끝나는 서술 키를 빼고 대조
P2R05_SPEC_KEYS <- c("fixed_axes", "base_weight", "factors", "factor2", "factor3", "weighting", "universe", "rebalance", "defense_sleeve",
                     "overlay", "overlay_cell", "overlay_shift", "overlay_strict", "cap_core", "weight_stage", "block")
## ⑮ 표적 정의 대조 — 분위 엔진 파일에 그대로 있어야 하는 줄(공백 정규화 뒤 부분 일치 · RP_AUTO_2002_06975/engine.R 3판 · 템플릿 고정 구역)
P2R05_YDEF_SNIPPETS <- c(
  calendar     = ".cal <- sort(unique(RAWDATA$Date)); .cal <- .cal[.cal >= .GRID_FROM]",
  close_rows   = ".rd <- RAWDATA[Date >= .GRID_FROM & is.finite(Close) & Close > 0, .cols, with = FALSE]",
  open_na      = ".rd[, Open := as.numeric(Open)]; .rd[!is.finite(Open) | Open <= 0, Open := NA_real_]",
  dedupe       = ".rd <- unique(.rd, by = c(\"Ticker\", \"Date\"))",
  grid         = ".G <- CJ(Ticker = .mem_tk, Date = .cal)",
  grid_join    = ".G <- .rd[.G, on = .(Ticker, Date)]",
  grid_order   = "setorder(.G, Ticker, Date)",
  label        = ".G[, lab_end := Close / shift(Open, .HORIZON - 1L) - 1, by = Ticker]",
  label_noopen = "if (!.HAS_OPEN) .G[, lab_end := Close / shift(Close, .HORIZON) - 1, by = Ticker]",
  label_set    = ".LAB <- .G[, .(s_date = shift(Date, .HORIZON), lab_i = di, y_raw = lab_end), by = Ticker]",
  label_drop   = ".LAB <- .LAB[!is.na(s_date) & is.finite(y_raw)]",
  label_join   = ".G[.LAB, on = .(Ticker, Date = s_date), c(\"y_raw\", \"lab_i\") := .(i.y_raw, i.lab_i)]",
  label_end    = "rm(.LAB); .G[, lab_end := NULL]",
  rank         = ".P[is.finite(y_raw), y := .rank01(y_raw), by = Date]")

## 보는 창 밖 작업 사본 표식(P2R04 그대로)
.p2_mark_full <- function(dir, note = NULL) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(c(P2R05_FULL_AUDIENCE, note), file.path(dir, P2R05_FULL_MARK), useBytes = TRUE)
  invisible(dir)
}

## ── 순수 도우미 — P2R04 그대로(상수 이름만 P2R05) ─────────────────────────────────────────────────────────────────
.p2_rows_dt <- function(x) if (is.data.frame(x)) as.data.table(x) else if (!length(x)) data.table() else
  rbindlist(lapply(x, function(r) as.data.table(lapply(r, function(v) if (is.null(v) || !length(v)) NA else v[[1]]))), fill = TRUE)
.p2_key <- function(x) paste(as.character(x$peak_date), as.character(x$trough_date))
p2_maj <- function(share, maj) { s <- suppressWarnings(as.numeric(share)); m <- suppressWarnings(as.numeric(maj))
  length(s) == 1L && length(m) == 1L && is.finite(s) && is.finite(m) && s > m }
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
  .p2_mark_full(out_dir)
  invisible(list(start = start, holdings_from = if (is.finite(h0)) h0 else start, n_pr = nrow(pr)))
}
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
  .p2_mark_full(dir = out_dir)
  invisible(list(k = k, n_pr = nrow(pr)))
}
p2_beta_plan <- function(beta_v, beta_r, force_k = NULL) {
  bv <- suppressWarnings(as.numeric(beta_v)); br <- suppressWarnings(as.numeric(beta_r))
  k <- if (!is.null(force_k)) suppressWarnings(as.numeric(force_k))[1] else
    if (length(bv) == 1L && length(br) == 1L && is.finite(bv) && is.finite(br) && br > 0) bv / br else NA_real_
  mode <- if (!is.finite(k) || k <= 0) "unmeasured" else if (k >= 1) "rx0" else "scaled"
  list(k = k, mode = mode, forced = !is.null(force_k),
       comparator = switch(mode, rx0 = "RX0(k ≥ 1)", scaled = "RX0 × k", unmeasured = "미측정"))
}
p2_size_beta_plan <- function(beta_v, beta_b) {
  bv <- suppressWarnings(as.numeric(beta_v)); bb <- suppressWarnings(as.numeric(beta_b))
  k <- if (length(bv) == 1L && length(bb) == 1L && is.finite(bv) && is.finite(bb) && bb > 0) bv / bb else NA_real_
  mode <- if (!is.finite(k) || k <= 0) "unmeasured" else if (k < 1) "scaled" else "basket"
  list(k = k, scale = if (identical(mode, "unmeasured")) NA_real_ else min(k, 1), mode = mode)
}
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
p2_size_beta_core <- function(cr_v, cr_c, deep, tol, maj) {
  mj <- p2_crisis_majority(cr_v, cr_c, tol, "dd_capture", subset = deep)
  list(n_pair = mj$n_pair, n_better = mj$n_better, share = mj$share, ok = mj$n_pair >= 2L && p2_maj(mj$share, maj),
       status_pairs = if (mj$n_pair >= 2L) "ok" else "unmeasured(짝 < 2)", per_crisis = mj$per_crisis)
}
p2_vs_market <- function(cr, tol, subset = NULL) {
  D <- .p2_rows_dt(cr)
  if (!nrow(D) || !all(c("peak_date", "trough_date", "dd_capture") %in% names(D))) return(list(n = 0L, n_better = 0L, share = NA_real_))
  D[, k := .p2_key(D)]
  if (!is.null(subset)) D <- D[k %in% subset]
  v <- as.numeric(D$dd_capture); v <- v[is.finite(v)]
  list(n = length(v), n_better = sum(v < 1 - tol), share = if (length(v)) mean(v < 1 - tol) else NA_real_)
}
p2_deep_crisis_keys <- function(cr_m, cr_r) {
  cm <- .p2_rows_dt(cr_m); cr <- .p2_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !("bm_dd" %in% names(cr))) return(character(0))
  cm[, k := .p2_key(cm)]; cr[, k := .p2_key(cr)]
  J <- cr[k %in% cm$k, .(k, depth = abs(as.numeric(bm_dd)))][is.finite(depth)]
  if (!nrow(J)) return(character(0))
  J[depth >= stats::median(depth), k]
}
p2_fast_crash_keys <- function(br, crises, win = 21L, drop = -0.20) {
  b <- as.data.table(br)[, .(date = as.Date(date), r = as.numeric(benchmark_ret))][order(date)]
  b[!is.finite(r), r := 0]; lvl <- cumprod(1 + b$r)
  me <- b[, .(d = max(date)), by = .(ym = format(date, "%Y-%m"))]$d
  cr <- .p2_rows_dt(crises)
  if (!nrow(cr) || !nrow(b)) return(list(keys = character(0), table = data.table(), unclassified = character(0), no_month_end = character(0)))
  rows <- lapply(seq_len(nrow(cr)), function(i) {
    i0 <- match(as.Date(as.character(cr$peak_date[i])), b$date); i1 <- match(as.Date(as.character(cr$trough_date[i])), b$date)
    k <- .p2_key(cr[i])
    if (is.na(i0) || is.na(i1) || i1 < i0) return(data.table(k = k, max_drop = NA_real_, fast = NA, seg_start = as.Date(NA), seg_end = as.Date(NA), month_ends_inside = NA_integer_))
    best <- 0; sa <- i0; se <- i0
    for (a in i0:i1) { e <- min(i1, a + as.integer(win)); j <- which.min(lvl[a:e]); v <- lvl[a + j - 1L] / lvl[a] - 1
                       if (v < best) { best <- v; sa <- a; se <- a + j - 1L } }
    data.table(k = k, max_drop = best, fast = best <= drop + 1e-12,
               seg_start = b$date[sa], seg_end = b$date[se], month_ends_inside = sum(me >= b$date[i0] & me < b$date[i1]))
  })
  T <- rbindlist(rows)
  list(keys = T[fast %in% TRUE, k], table = T, unclassified = T[is.na(fast), k], win = as.integer(win), drop = drop,
       no_month_end = T[fast %in% TRUE & month_ends_inside %in% 0L, k])
}
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
p2_beta_asym <- function(beta_down, beta_up) {
  bd <- suppressWarnings(as.numeric(beta_down)); bu <- suppressWarnings(as.numeric(beta_up))
  if (length(bd) != 1L || length(bu) != 1L || !is.finite(bd) || !is.finite(bu)) return(NA)
  bd < bu
}
p2_beta_ratio_delta <- function(bd_v, bu_v, bd_r, bu_r) {
  x <- suppressWarnings(as.numeric(c(bd_v, bu_v, bd_r, bu_r)))
  if (length(x) != 4L || any(!is.finite(x)) || x[2] <= 0 || x[4] <= 0) return(list(ratio = NA_real_, ratio_rx0 = NA_real_, delta = NA_real_, ok = NA))
  rv <- x[1] / x[2]; rr <- x[3] / x[4]
  list(ratio = rv, ratio_rx0 = rr, delta = rv - rr, ok = rv < rr)
}
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
p2_alpha_ok <- function(pa_vis, t_floor, engine_alpha, margin_frac) {
  t <- suppressWarnings(as.numeric(pa_vis$t)); d <- suppressWarnings(as.numeric(pa_vis$d_alpha)); ea <- suppressWarnings(as.numeric(engine_alpha))
  if (!length(t) || !length(d) || !is.finite(t) || !is.finite(d) || !length(ea) || !is.finite(ea)) return(NA)
  (t > t_floor) && (d >= -margin_frac * max(ea, 0))
}
p2_recovery_tag <- function(cr_m, cr_r, maj) {
  cm <- .p2_rows_dt(cr_m); cr <- .p2_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !("st_recovery_obs" %in% names(cm)) || !("st_recovery_obs" %in% names(cr)))
    return(list(status = "unmeasured", tag = FALSE))
  cm[, k := .p2_key(cm)]; cr[, k := .p2_key(cr)]
  if (!"st_recovery_censored" %in% names(cm)) cm[, st_recovery_censored := NA]
  if (!"st_recovery_censored" %in% names(cr)) cr[, st_recovery_censored := NA]
  J <- merge(cm[, .(k, m = as.numeric(st_recovery_obs), mc = as.logical(st_recovery_censored))],
             cr[, .(k, r = as.numeric(st_recovery_obs), rc = as.logical(st_recovery_censored))], by = "k")
  J[, `:=`(m = fifelse(!is.finite(m) & mc %in% TRUE, Inf, m), r = fifelse(!is.finite(r) & rc %in% TRUE, Inf, r))]
  J <- J[!is.na(m) & !is.na(r) & !(is.infinite(m) & is.infinite(r))]
  if (!nrow(J)) return(list(status = "unmeasured", tag = FALSE))
  sh <- mean(J$m > J$r)
  list(status = "ok", n_pair = nrow(J), n_longer = sum(J$m > J$r), share = sh, tag = p2_maj(sh, maj), n_censored_variant = sum(is.infinite(J$m)), per_crisis = J)
}
## 셀 로그 마지막 요약 줄 — P2R04 그대로('[rf_cell_engine] cell=… | univ=… | factors=… | wt=… | months=N | rows=M' · months · rows 는 전 구간 셈 — 보는 창 파일에 싣지 않는다)
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
## 팩터 방향 경로 줄 · 기록 — P2R04 그대로(LV 칸의 D03_RealVol 블록에만 쓴다)
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
## LV 칸 ⑩ 사양 꼬리 · 구성 증거 3대조 · 혼합 가중 — P2R04 그대로(장치 = D03_RealVol · LV 칸만 쓴다)
.p2_spec_tail <- function(spec_factors) {
  ids <- vapply(spec_factors %||% list(), function(f) as.character(f$id %||% NA_character_), character(1))
  kds <- vapply(spec_factors %||% list(), function(f) as.character(f$kind %||% NA_character_), character(1))
  n <- length(ids)
  if (!n) return(list(ids = ids, kinds = kds, m = 0L, base = character(0), tail_id = NA_character_, tail_kind = NA_character_))
  same <- !is.na(ids) & !is.na(kds) & ids == ids[n] & kds == kds[n]
  r <- rle(rev(same)); m <- if (isTRUE(r$values[1])) r$lengths[1] else 0L
  list(ids = ids, kinds = kds, m = as.integer(m), base = utils::head(ids, n - m), tail_id = ids[n], tail_kind = kds[n])
}
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
p2_blend_weight <- function(base_weight, n_factors, n_device = 1L) {
  w0 <- suppressWarnings(as.numeric(base_weight %||% NA))[1]; n <- as.integer(n_factors); m <- as.integer(n_device)
  bad <- !length(n) || is.na(n) || n < 1L || !length(m) || is.na(m) || m < 1L || m > n
  dw <- if (bad) NA_real_ else if (is.finite(w0)) (1 - w0) * m / n else m / (1 + n)
  ds <- if (bad) NA_real_ else if (is.finite(w0)) w0 else 1 / (1 + n)
  os <- if (bad) NA_real_ else if (is.finite(w0)) (1 - w0) * (n - m) / n else (n - m) / (1 + n)
  list(base_weight = w0, n_factors = n, n_device = m, device_weight = dw, dnn_share = ds, other_share = os,
       rule = "rf_cell_engine.R §4 Score = w0·z_base + (1−w0)·mean(z_factors)")
}
## 보유 대조 · 처치 전달 — P2R04 그대로
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
p2_treatment_delivered <- function(ov) identical(ov$status, "ok") && isTRUE(ov$n_differ > 0L)
## ⑭ 선택 귀속 — P2R04 그대로
p2_selection_attr <- function(label, required, controls_status = "ok") {
  lb <- as.character(label %||% NA_character_)[1]; rq <- as.character(unlist(required) %||% NA_character_)[1]
  cs <- as.character(controls_status %||% NA_character_)[1]
  st <- if (is.na(rq) || !nzchar(rq)) "no_rule" else if (!identical(cs, "ok")) "unmeasured" else if (is.na(lb) || !(lb %in% P2R05_MC8_LABELS)) "unmeasured" else "ok"
  list(label = lb, required = rq, controls_status = cs, status = st, ok = identical(st, "ok") && identical(lb, rq))
}
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
p2_selection_rule <- function(attr, decomp) {
  st <- if (!identical(attr$status, "ok")) attr$status else if (!identical(decomp$status, "ok")) "unmeasured(선택 항 분해)" else "ok"
  c(attr[c("label", "required")], list(label_status = attr$status, label_ok = isTRUE(attr$ok), controls_status = attr$controls_status %||% NA_character_,
                                       decomposition = decomp, status = st, measured = identical(st, "ok"),
                                       ok = isTRUE(attr$ok) && isTRUE(decomp$ok)))
}
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
p2_liq_deciles <- function(x, univ) {
  u <- suppressWarnings(as.numeric(univ)); u <- u[is.finite(u)]; x <- suppressWarnings(as.numeric(x))
  if (length(u) < 10L) return(rep(NA_integer_, length(x)))
  bp <- stats::quantile(u, probs = seq_len(9) / 10, names = FALSE, type = 7)
  ifelse(is.finite(x), findInterval(x, bp) + 1L, NA_integer_)
}
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
## RX0 동일성(기록) — P2R04 식 · 대조 원천 = P2R04 같은 구성 RX0(이름만 P2R05 · P2R04)
p2_rx0_identity_core <- function(H5, H4, pr5, pr4, tau) {
  tau <- as.Date(tau)
  ov <- p2_holdings_overlap(H5, H4, tau)
  a <- as.data.table(pr5)[as.Date(date) <= tau, .(date = as.Date(date), r5 = as.numeric(ret_net))]
  b <- as.data.table(pr4)[as.Date(date) <= tau, .(date = as.Date(date), r4 = as.numeric(ret_net))]
  J <- merge(a, b, by = "date")
  M <- if (nrow(J)) J[, .(diff = any(xor(is.na(r5), is.na(r4)) | (!is.na(r5) & !is.na(r4) & r5 != r4))), by = .(ym = format(date, "%Y-%m"))] else data.table(ym = character(0), diff = logical(0))
  hs <- identical(ov$status, "ok") && identical(ov$n_differ, 0L) && identical(as.integer(ov$n_only_variant), 0L) && identical(as.integer(ov$n_only_rx0), 0L)
  only <- (nrow(a) - nrow(J)) + (nrow(b) - nrow(J))
  list(holdings_same = hs, holdings_dates = ov$n_dates, holdings_dates_differ = ov$n_differ,
       holdings_dates_only_p2r05 = ov$n_only_variant %||% NA_integer_, holdings_dates_only_p2r04 = ov$n_only_rx0 %||% NA_integer_,
       returns_same = nrow(M) > 0L && !any(M$diff) && only == 0L, months_compared = nrow(M), months_differ = sum(M$diff), days_only_one_side = only)
}
## 칸 통과(사전 고정) = ① ∧ ② ∧ ③ ∧ ④ ∧ ⑤ ∧ ⑥ ∧ ⑦ ∧ ⑨ ∧ ⑩ ∧ ⑫ ∧ ⑬ ∧ ⑭ ∧ ⑮(시험 조건 — 적용 안 되는 칸은 참)(⑧ = 규칙 검증 제외 · ⑪ = 꼬리표)
p2_cell_pass <- function(f) {
  isTRUE(f$crisis) && isTRUE(f$deep) && isTRUE(f$beta_deep) && isTRUE(f$fast) && isTRUE(f$beta_ratio) && isTRUE(f$bull) &&
    isTRUE(f$alpha) && isTRUE(f$cycle) && isTRUE(f$construction) && isTRUE(f$S) && isTRUE(f$path) && isTRUE(f$selection) && isTRUE(f$tail)
}
## '꼬리 회피 기계(방어만 · 복리 없음)' — 판정어 · 결론 꼬리표가 함께 쓰는 한 정의(격리 교차 점검 v1 필수 1 · Q 10-18 · rules.conclusion_names 문장 그대로 ·
##   결론 범위 2 · 3 순서): ⑮ 통과(미달 = 미시험(계기)이 먼저) ∧ ① ∧ ②(결정 — 미달 = 결정 미달) ∧ ③ ∧ ④ ∧ ⑭(측정 ∧ 통과) ∧ ⑤(수준 ∧ Δ — '방어' 이름 조건 · 미달 = 'β 비대칭 미달')
##   ∧ ⑥ · ⑦ · ⑨ · ⑫ · ⑬ 중 하나 이상 미달
p5_machine <- function(tail, crisis, deep, r3, r4, s14m, s14, level, ratio, strength) {
  st <- strength %||% list()
  isTRUE(tail) && isTRUE(crisis) && isTRUE(deep) && isTRUE(r3) && isTRUE(r4) && isTRUE(s14m) && isTRUE(s14) && isTRUE(level) && isTRUE(ratio) &&
    !all(vapply(c("bull", "alpha", "cycle", "S", "path"), function(k) isTRUE(st[[k]]), logical(1)))
}
## 칸 판정어 — 첫 일치(P2R04 순서 + P2R05: ⑮ 미달이 통과 다음 첫째 · ① · ② 미달 = 결정 미달 · ⑤ 미달 = β 비대칭 미달 · 꼬리 회피 기계 = p5_machine) ·
##   통과 조건(p2_cell_pass 13조건)은 그대로 — 바뀐 것은 미통과 칸의 이름(라벨)뿐 · 판정 칸의 ⑮ 미달은 p5_apply_tail_gate 가 미시험으로도 바꾼다
p2_cell_verdict <- function(f) {
  r3 <- f$beta_deep %||% NA; r4 <- f$fast %||% NA; s14 <- isTRUE(f$selection); m14 <- isTRUE(f$selection_measured)
  dec <- isTRUE(f$crisis) && isTRUE(f$deep) && isTRUE(r3) && isTRUE(r4)
  if (isTRUE(f$pass)) "pass" else
  if (identical(f$tail, FALSE)) "untested_tail_instrument" else
  if (isTRUE(f$beta_unmeasured) || is.na(r3)) "beta_unmeasured" else
  if (is.na(r4) && isTRUE(r3)) "fast_unmeasured" else
  if (isTRUE(f$crisis) && isTRUE(f$deep) && !isTRUE(r3)) "exposure_only" else
  if (isTRUE(r3) && isTRUE(r4) && !m14) "selection_unmeasured" else
  if (isTRUE(r3) && isTRUE(r4) && !s14) "size_or_exposure_defense" else
  if (!dec) "not_decisive" else
  if (!isTRUE(f$level) || !isTRUE(f$beta_ratio)) "asymmetry_unmet" else
  if (p5_machine(TRUE, f$crisis, f$deep, r3, r4, m14, s14, f$level, f$beta_ratio, f$strength)) "defense_but_strength_or_path" else "not_decisive"
}
## 결론 기본 이름 — P2R04 그대로('방어'는 ③ ∧ ④ ∧ ⑤(수준) ∧ ⑭ 일 때만 · 크기 × β 짝까지 = '선택(특성) 방어') · P2R05 덧붙임은 p5_conclusion
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
## 라운드 판정 · 판정어별 칸 수 · 최종 선택 — P2R04 그대로(device = 규칙 V1 · V2)
p2_verdict_counts <- function(v) {
  v <- as.character(v[!is.na(v)])
  if (!length(v)) return("")
  k <- c(intersect(P2R05_VERDICTS, unique(v)), setdiff(unique(v), P2R05_VERDICTS))
  paste(vapply(k, function(z) sprintf("%s %d", if (z %in% names(P2R05_VERDICT_SHORT)) P2R05_VERDICT_SHORT[[z]] else z, sum(v == z)), character(1)), collapse = " · ")
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
p2_select <- function(xs_by_device, tie = 1e-12) {
  if (!length(xs_by_device)) return(list())
  sc <- lapply(names(xs_by_device), function(dv) {
    xs <- xs_by_device[[dv]]
    list(device = dv, dS = mean(vapply(xs, function(x) as.numeric(x$non_inferiority$S - x$non_inferiority$S_rx0), numeric(1))),
         r34 = mean(vapply(xs, function(x) as.numeric((x$rules$beta_deep$share %||% NA) + (x$rules$fast$share %||% NA)), numeric(1))))
  })
  dS <- vapply(sc, `[[`, numeric(1), "dS"); r34 <- vapply(sc, `[[`, numeric(1), "r34")
  top <- is.finite(dS) & (max(dS, na.rm = TRUE) - dS) < tie
  o <- order(!top, -ifelse(top, r34, dS), -dS)
  sc <- sc[o]
  if (sum(top) >= 2L) sc[[1]]$tie_break <- "r34"
  sc
}
## 위기별 승리 겹침(진단 읽기 공용) — P2R04 그대로
.p2_wins <- function(D, tol) { D <- as.data.table(D %||% data.table()); if (!nrow(D) || !all(c("k", "m", "r") %in% names(D))) return(NULL)
                               D[is.finite(m) & is.finite(r) & m < r - tol, k] }
p2_read_overlap_wins <- function(a_pc, b_pc, tol) {
  wa <- .p2_wins(a_pc, tol)
  if (is.null(wa)) return(list(status = "unmeasured", n_a = NA_integer_, both = character(0), a_only = character(0), unknown = character(0)))
  wb <- .p2_wins(b_pc, tol); kb <- if (is.null(wb)) character(0) else as.character(as.data.table(b_pc)$k)
  list(status = if (is.null(wb)) "b_unmeasured" else "ok", n_a = length(wa), both = intersect(wa, wb %||% character(0)),
       a_only = setdiff(intersect(wa, kb), wb %||% character(0)), unknown = setdiff(wa, kb))
}
p2_a_distance <- function(perf, bench_calmar, th, S = NA_real_, a_boundary = NA_real_) {
  v <- function(k) suppressWarnings(as.numeric(perf[[k]] %||% NA))[1]
  one <- function(x, t) { x <- suppressWarnings(as.numeric(x))[1]; t <- suppressWarnings(as.numeric(t))[1]
                          list(value = x, threshold = t, distance = x - t, meets = is.finite(x) && is.finite(t) && x >= t) }
  list(cagr = one(v("cagr"), th$cagr_min), sharpe = one(v("sharpe"), th$sharpe_min), calmar = one(v("calmar"), bench_calmar),
       port_t = one(v("port_t"), th$port_t_b), S = one(S, a_boundary))
}
## R7 판독 — P2R04 정의(등록 판독) + 방어 성분(철학 Superfan P2 R-20261018-006 C-045 — 검증 0 ∧ 두 구성 ③ 과반 규칙 0 · S 무관)
##   등록 판독: 판정된 규칙 = 두 구성 tested ∧ ③ 측정(status ok · 짝 ≥ 2 · 비율 유한) ∧ S 증분 유한 · < 2 = 판독 불가 · 잡음 이내 = 검증 0 ∧ ③ 두 구성 과반 0 ∧ S 증분 최대 < tie_eps
##   방어 성분: 판정된 규칙 = 두 구성 tested ∧ ③ 측정(S 무관) · < 2 = 판독 불가 · 잡음 이내 = 검증 0 ∧ ③ 두 구성 과반 0 — 방어 성분 잡음이면 P2 정지 · 도훈 보고 대상
p2_noise_reading <- function(OUT, validated, tie_eps, maj, devices = names(P2R05_RULES)) {
  per <- lapply(devices, function(dv) {
    xs <- Filter(function(x) identical(x$device, dv), OUT)
    tst <- vapply(xs, function(x) isTRUE(x$tested), logical(1))
    st3 <- vapply(xs, function(x) as.character(x$rules$beta_deep$status %||% NA_character_)[1], character(1))
    np3 <- vapply(xs, function(x) suppressWarnings(as.integer(x$rules$beta_deep$n_pair %||% NA))[1], integer(1))
    sh3 <- vapply(xs, function(x) suppressWarnings(as.numeric(x$rules$beta_deep$share %||% NA))[1], numeric(1))
    dS <- vapply(xs, function(x) if (isTRUE(x$tested)) suppressWarnings(as.numeric(x$non_inferiority$S - x$non_inferiority$S_rx0))[1] else NA_real_, numeric(1))
    r3m <- tst & st3 %in% "ok" & !is.na(np3) & np3 >= 2L & is.finite(sh3)
    judged_def <- length(xs) == 2L && all(r3m)
    judged <- judged_def && all(is.finite(dS))
    why <- if (length(xs) != 2L) sprintf("구성 칸 %d개(2개여야 함)", length(xs)) else if (!all(tst)) "미시험 구성 있음" else
           if (!all(r3m)) sprintf("③ 미측정 구성 있음(%s)", paste(ifelse(is.na(st3), "NA", st3), collapse = " / ")) else if (!all(is.finite(dS))) "S 증분 비유한" else NA_character_
    list(device = dv, n_cells = length(xs), r3_status = unname(st3), r3_share = unname(sh3), r3_measured = unname(r3m), judged = judged, judged_defense = judged_def,
         dropped_why = why, r3_both = judged_def && all(vapply(sh3, p2_maj, logical(1), maj = maj)), dS_mean = if (judged) mean(dS) else NA_real_)
  })
  jd <- vapply(per, function(p) isTRUE(p$judged), logical(1)); nb <- sum(jd)
  jdd <- vapply(per, function(p) isTRUE(p$judged_defense), logical(1)); nbd <- sum(jdd)
  dmv <- vapply(per, function(p) p$dS_mean, numeric(1))[jd]; n3 <- sum(vapply(per, function(p) isTRUE(p$r3_both), logical(1))[jd])
  n3d <- sum(vapply(per, function(p) isTRUE(p$r3_both), logical(1))[jdd])
  dmax <- if (any(is.finite(dmv))) max(dmv[is.finite(dmv)]) else NA_real_
  c1 <- !length(validated); c2 <- n3 == 0L; c3 <- is.finite(dmax) && dmax < as.numeric(tie_eps)
  readable <- nb >= 2L; readable_d <- nbd >= 2L
  res <- if (!readable) NA else c1 && c2 && c3
  res_d <- if (!readable_d) NA else c1 && (n3d == 0L)
  dropped <- lapply(per[!jd], function(p) list(device = p$device, why = p$dropped_why))
  def_lab <- if (!readable_d) sprintf("판독 불가(방어 성분 — 판정된 규칙 %d/%d < 2 · 두 구성 tested ∧ ③ 측정)", nbd, length(devices)) else
             if (isTRUE(res_d)) "방어 성분 잡음 — P2R03 · P2R04 에 이어 연속 3 → P2 정지(paused) · 도훈 보고(체계 §4)" else "잡음 밖(방어 성분)"
  list(result = res, label = if (!readable) sprintf("판독 불가(판정된 규칙 %d/%d < 2 — 두 구성 tested ∧ ③ 측정)", nb, length(devices)) else if (isTRUE(res)) "잡음 이내" else "잡음 밖",
       judged_devices = sprintf("%d/%d", nb, length(devices)), n_devices_judged_both = nb, n_devices = length(devices),
       judged = vapply(per[jd], function(p) p$device, character(1)), dropped = dropped,
       components = list(no_validated = c1, no_device_r3_both = c2, max_dS_below_tie = c3),
       n_validated = length(validated), n_device_r3_both = n3, max_dS = dmax, tie_eps = as.numeric(tie_eps), per_device = per,
       rule = paste0("R7 판독(등록 · P2R04 그대로) — 판정된 규칙(두 구성 tested ∧ ③ 측정 · 짝 ≥ 2 ∧ S 증분 유한) < 2 = 판독 불가 · 아니면 검증 0 ∧ 판정된 규칙 중 두 구성 ",
                     "③ 비율 > majority_share 인 규칙 0 ∧ 판정된 규칙 S 증분(두 구성 평균) 최대 < tie_eps = 잡음 이내"),
       defense_component = list(result = res_d, label = def_lab, judged_devices = sprintf("%d/%d", nbd, length(devices)), n_judged = nbd,
                                judged = vapply(per[jdd], function(p) p$device, character(1)),
                                n_device_r3_both = n3d, components = list(no_validated = c1, no_device_r3_both = n3d == 0L),
                                paused_and_report = isTRUE(res_d), consecutive_with = c("P2R03", "P2R04"),
                                rule = paste0("방어 성분(철학 Superfan P2 R-20261018-006 C-045 · 기계 판정 — 판단 T1 R-20261018-007) — 판정된 규칙(두 구성 tested ∧ ③ 측정 — S 무관) < 2 = 판독 불가 · ",
                                              "아니면 검증 0 ∧ 두 구성 ③ 과반 규칙 0 = '방어 성분 잡음' → P2R03 · P2R04 에 이어 연속 3 = P2 정지(paused) · 도훈 보고(체계 §4)")))
}
## 사전등록 final_selection_rule 키 결손(⑮ 하위 키 포함)
p2_fs_missing <- function(FS) {
  m <- setdiff(P2R05_FS_KEYS, names(FS %||% list()))
  ti <- FS$tail_instrument
  mt <- setdiff(P2R05_TAIL_KEYS, names(ti %||% list()))                          # 길이 0 이면 붙이지 않는다(paste0 는 길이 0 인자를 "" 로 재활용한다)
  if (!("tail_instrument" %in% m) && length(mt)) m <- c(m, paste0("tail_instrument.", mt))
  m
}
## 사전등록 칸 목록 검사(DESIGN §12 + Q 10-18 LV) — code = P2R05_<engine>_<component> · 판정 구성 2개 · 구성마다 RX0 1칸 · 규칙 V1 · V2 ·
##   reference = (component == RX0) · diagnostic = (component ∈ 진단 · 비교 기준 표) · 진단 칸은 표의 engines 안에만 · 진단 칸 control 이 있으면 표와 같아야 한다
##   (없으면 통과 — 기록) · 판정 칸에는 control 이 없어야 한다. 반환 = 문제 설명(없으면 길이 0)
p2_cells_check <- function(cells, rules = P2R05_RULES, diags = P2R05_DIAGNOSTICS) {
  if (!length(cells)) return("칸 없음")
  f <- function(k) vapply(cells, function(z) { v <- z[[k]]; if (is.null(v) || !length(v) || is.na(v[[1]])) NA_character_ else as.character(v[[1]]) }, character(1))
  cd <- f("code"); en <- f("engine"); cp <- f("component"); ct <- f("control")
  ct[!is.na(ct) & !nzchar(ct)] <- NA_character_
  rf <- vapply(cells, function(z) isTRUE(z$reference), logical(1)); dg <- vapply(cells, function(z) isTRUE(z$diagnostic), logical(1))
  dgt <- function(k) if (is.na(k)) NULL else diags[[k]]
  bad <- character(0)
  if (anyNA(cd) || anyNA(en) || anyNA(cp)) bad <- c(bad, "code · engine · component 결측")
  if (anyDuplicated(cd)) bad <- c(bad, "code 중복")
  wrong <- !is.na(cd) & cd != paste0("P2R05_", en, "_", cp)
  if (any(wrong)) bad <- c(bad, paste("code ≠ P2R05_<engine>_<component>:", paste(cd[wrong], collapse = ",")))
  if (any(rf != (cp %in% "RX0"))) bad <- c(bad, "reference ≠ (component == RX0)")
  if (any(dg != (cp %in% names(diags)))) bad <- c(bad, "diagnostic ≠ (component ∈ 진단 · 비교 기준 표)")
  unk <- setdiff(unique(cp[!is.na(cp)]), c("RX0", names(rules), names(diags))); if (length(unk)) bad <- c(bad, paste("규칙 · 진단 표에 없는 부품:", paste(unk, collapse = ",")))
  out_eng <- dg & !vapply(seq_along(cp), function(i) isTRUE(en[i] %in% (dgt(cp[i])$engines %||% character(0))), logical(1))
  if (any(out_eng)) bad <- c(bad, paste("진단 칸이 진단 표 engines 밖:", paste(cd[out_eng], collapse = ",")))
  ctl_bad <- dg & !is.na(ct) & !vapply(seq_along(cp), function(i) { tc <- dgt(cp[i])$control %||% NA_character_; is.na(tc) || identical(tc, ct[i]) }, logical(1))   # 표 control NA = 대조 안 함(현재 표에 NA 없음 — RX0S = seed_pair · Q 10-18 정렬 1)
  if (any(ctl_bad)) bad <- c(bad, paste("진단 칸 control ≠ 진단 표:", paste(cd[ctl_bad], collapse = ",")))
  if (any(!dg & !is.na(ct))) bad <- c(bad, paste("판정 칸에 control:", paste(cd[!dg & !is.na(ct)], collapse = ",")))
  ue <- unique(en[!is.na(en) & !dg])
  if (length(ue) != 2L) bad <- c(bad, sprintf("판정 구성 %d개(2개여야 함 — 규칙 검증 = 두 구성 통과)", length(ue)))
  for (e in ue) { ce <- cp[en %in% e & !dg]; if (sum(ce %in% "RX0") != 1L) bad <- c(bad, sprintf("%s RX0 %d칸(1칸이어야 함)", e, sum(ce %in% "RX0")))
                  if (anyDuplicated(ce)) bad <- c(bad, sprintf("%s 부품 중복", e))
                  if (!setequal(setdiff(ce, "RX0"), names(rules))) bad <- c(bad, sprintf("%s 규칙 집합 ≠ %s", e, paste(names(rules), collapse = "+"))) }
  de <- unique(en[dg & !is.na(en)])
  if (length(setdiff(de, en[!dg & cp %in% "RX0"]))) bad <- c(bad, paste("진단 칸 구성에 RX0 칸 없음:", paste(setdiff(de, en[!dg & cp %in% "RX0"]), collapse = ",")))
  bad
}
## τ_D 이후 날짜 가림 · 보는 창 판정 칸 — P2R04 그대로
.p2_redact_chr <- function(s, tau) {
  tau <- as.Date(tau); ok <- !is.na(s)
  if (!any(ok)) return(s)
  tau_ym <- format(tau, "%Y-%m"); x <- s[ok]
  m <- gregexpr("(19|20)[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])", x)
  regmatches(x, m) <- lapply(regmatches(x, m), function(v) { if (!length(v)) return(v); d <- suppressWarnings(as.Date(v))
                                                              ifelse(!is.na(d) & d > tau, P2R05_REDACT, v) })
  m2 <- gregexpr("(?<![0-9-])(19|20)[0-9]{2}-(0[1-9]|1[0-2])(?![0-9-])", x, perl = TRUE)
  regmatches(x, m2) <- lapply(regmatches(x, m2), function(v) if (!length(v)) v else ifelse(v > tau_ym, P2R05_REDACT, v))
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
p2_visible_only <- function(x, tau) {
  for (k in P2R05_VISIBLE_DROP) x[[k]] <- NULL
  if (is.list(x$trim)) for (s in names(x$trim)) if (is.list(x$trim[[s]])) x$trim[[s]]$n_pr <- NULL
  p2_redact_after_tau(x, tau)
}
## 핀 대조 — P2R04 그대로(precheck.R 과 evaluate.R 시작부가 같은 함수)
p2_pin_mismatches <- function(pre, root) {
  md5 <- function(f) unname(as.character(tools::md5sum(file.path(root, f))))
  cj <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
  bad <- character(0)
  for (c0 in pre$cells) if (!identical(md5(c0$path), c0$md5)) bad <- c(bad, paste("사양 md5:", c0$code))
  op <- pre$operational_pins
  if (is.null(op)) return(c(bad, "운영 핀 없음"))
  unk <- setdiff(names(op), P2R05_PIN_KINDS)
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
p2_fingerprint <- function(rd, mode = "equality") {
  o <- tryCatch(suppressWarnings(system2(qv_bash(), c(shQuote(file.path(rd, "fingerprint.sh")), mode), stdout = TRUE, stderr = TRUE)),
                error = function(e) paste("error:", conditionMessage(e)))
  paste(o, collapse = "|")
}
p2_fp_same <- function(a, b) identical(unname(as.character(a)), unname(as.character(b)))

## ── P2R05 순수 도우미 ① — 경로 · 핀 · 사양 · 셀 로그 · 워밍 센티널 · 템플릿 대조 · ⑩ 구성 증거 ──────────────────────────────────
p5_md5 <- function(f) if (length(f) == 1L && !is.na(f) && file.exists(f)) unname(as.character(tools::md5sum(f))) else NA_character_
## 저장소 상대 경로(역슬래시 → 슬래시 · 루트 접두 제거 · 대소문자 무시 — Windows)
p5_rel <- function(p, root) {
  p <- gsub("\\\\", "/", as.character(p)); r <- sub("/+$", "", gsub("\\\\", "/", as.character(root)))
  pre <- tolower(paste0(r, "/"))
  ifelse(!is.na(p) & nzchar(r) & startsWith(tolower(p), pre), substring(p, nchar(r) + 2L), p)
}
.p5_same_path <- function(a, b) identical(tolower(gsub("\\\\", "/", a)), tolower(gsub("\\\\", "/", b)))
## 부품 → 기대 기저 엔진(DESIGN §4 칸 표 · §12) — RX0 · LV = 평균 표적 엔진 · V · Q50 · N · S = 분위 엔진 파일 · W2 = engine_blend [평균, V2]
p5_expected_engines <- function(comp) {
  if (identical(comp, "RX0") || identical(comp, "LV")) return(list(kind = "engine", paths = P2R05_RX0_ENGINE))
  if (comp %in% names(P2R05_RULES)) return(list(kind = "engine", paths = file.path(P2R05_DT_DIR, P2R05_RULES[[comp]]$engine)))
  dg <- P2R05_DIAGNOSTICS[[comp]]
  if (is.null(dg)) return(NULL)
  if (isTRUE(dg$reseed)) return(list(kind = "engine", paths = character(0), reseed = TRUE))       # 재시드 = RX0 엔진이 아닌 핀 된 평균 엔진 1개(경로 이름은 대조하지 않는다)
  if (isTRUE(dg$blend)) return(list(kind = "engine_blend", paths = c(P2R05_RX0_ENGINE, file.path(P2R05_DT_DIR, P2R05_RULES$V2$engine))))
  if (!is.null(dg$engine_file)) return(list(kind = "engine", paths = file.path(P2R05_DT_DIR, dg$engine_file)))
  NULL
}
p5_spec_engines <- function(spec, root) {
  b <- spec$base_signal
  if (is.null(b)) return(list(kind = NA_character_, paths = character(0)))
  k <- as.character(b$kind %||% NA_character_)[1]
  ps <- if (identical(k, "engine_blend")) as.character(unlist(b$paths %||% list())) else as.character(b$path %||% NA_character_)[1]
  list(kind = k, paths = p5_rel(ps[!is.na(ps)], root))
}
p5_uses_dt <- function(paths) any(startsWith(tolower(gsub("\\\\", "/", paths)), tolower(paste0(P2R05_DT_DIR, "/"))))
## 사전등록 운영 핀(operational_pins.files)의 그 경로 md5 — 없거나 여럿이 다르면 NA(핀 불명)
p5_pin_md5 <- function(pre, rel) {
  fs <- Filter(function(f) .p5_same_path(as.character(f$path %||% ""), rel), pre$operational_pins$files %||% list())
  m <- unique(vapply(fs, function(f) as.character(f$md5 %||% NA_character_), character(1)))
  if (length(m) == 1L && !is.na(m)) m else NA_character_
}
## 설계 입력 핀(design_inputs 아래 어디든 {path|file, md5} 짝) — 그 파일의 md5 목록
p5_find_pin <- function(x, rel) {
  hits <- character(0)
  walk <- function(v) {
    if (!is.list(v)) return(invisible())
    p <- v[["path"]] %||% v[["file"]]; m <- v[["md5"]]
    if (is.character(p) && length(p) == 1L && is.character(m) && length(m) == 1L && endsWith(tolower(gsub("\\\\", "/", p)), tolower(rel))) hits <<- c(hits, m)
    for (z in v) walk(z)
    invisible()
  }
  walk(x); unique(hits)
}
## 사양 구성 키 대조(base_signal 밖) — 이름 정렬 뒤 JSON 비교 · fixed_axes 는 '_note' 서술 키 제외 · drop / drop_fixed = 그 칸 형식상 다를 수 있는 키
.p5_canon <- function(x) { if (is.list(x)) { if (!is.null(names(x))) x <- x[order(names(x))]; lapply(x, .p5_canon) } else x }
p5_spec_same <- function(sv, sr, drop = character(0), drop_fixed = character(0)) {
  cj <- function(x) as.character(jsonlite::toJSON(.p5_canon(x), auto_unbox = TRUE, null = "null", digits = NA))
  fx <- function(f) { if (is.null(f)) return(NULL); f[setdiff(names(f), c(drop_fixed, grep("_note$", names(f), value = TRUE)))] }
  keys <- setdiff(P2R05_SPEC_KEYS, drop)
  dif <- keys[!vapply(keys, function(k) { a <- sv[[k]]; b <- sr[[k]]; if (identical(k, "fixed_axes")) { a <- fx(a); b <- fx(b) }; identical(cj(a), cj(b)) }, logical(1))]
  list(ok = !length(dif), differ = dif)
}
.p5_factor_ids <- function(f) vapply(f %||% list(), function(z) as.character(z$id %||% NA_character_), character(1))
## 기저 적재 줄(rf_cell_engine .load_one · engine_blend) — 적중 '기저 캐시 적중 — base_v2_<md5 앞 12자>_<32자>.rds (N행)' ·
##   실행 '기저 캐시 미스 — 엔진 실행: <엔진 파일 이름> [<사유> · base_v2_<md5 앞 12자>_<32자>.rds]' · 결합 'engine_blend N개 — 공통 M행 (a + b)'
p5_parse_base_load <- function(lines) {
  lines <- sub("\r$", "", as.character(lines))
  rh <- "^\\[rf_cell_engine\\] 기저 캐시 적중 — (base_v2_([0-9a-f]{12}|nohash)_[0-9a-f]{32}\\.rds) \\(([0-9]+)행\\)[[:space:]]*$"
  rm <- "^\\[rf_cell_engine\\] 기저 캐시 미스 — 엔진 실행: ([^ ]+) \\[(.*) · (base_v2_([0-9a-f]{12}|nohash)_[0-9a-f]{32}\\.rds)\\][[:space:]]*$"
  rb <- "^\\[rf_cell_engine\\] engine_blend ([0-9]+)개 — 공통 ([0-9]+)행 \\((.*)\\)[[:space:]]*$"
  h <- grep(rh, lines, value = TRUE); m <- grep(rm, lines, value = TRUE); b <- grep(rb, lines, value = TRUE)
  L <- rbindlist(list(
    if (length(h)) data.table(kind = "hit", file = sub(rh, "\\1", h), md5_12 = sub(rh, "\\2", h), engine = NA_character_, why = NA_character_),
    if (length(m)) data.table(kind = "run", file = sub(rm, "\\3", m), md5_12 = sub(rm, "\\4", m), engine = sub(rm, "\\1", m), why = sub(rm, "\\2", m))), fill = TRUE)
  if (!nrow(L)) L <- data.table(kind = character(0), file = character(0), md5_12 = character(0), engine = character(0), why = character(0))
  B <- if (length(b)) data.table(n = as.integer(sub(rb, "\\1", b)), rows = as.integer(sub(rb, "\\2", b)), engines = sub(rb, "\\3", b)) else
    data.table(n = integer(0), rows = integer(0), engines = character(0))
  list(loads = L, blend = B)
}
## 기대 엔진(핀 md5)마다 적재 줄이 있는가 — 캐시 파일 이름의 md5 앞 12자 = 핀 md5 앞 12자 · 실행 줄이면 엔진 파일 이름도 일치 · 결합이면 engine_blend 줄(엔진 수 · 이름)
p5_base_load_check <- function(P, pins, blend = FALSE) {
  if (!length(pins)) return(list(ok = FALSE, why = "기대 엔진 핀 없음", per_engine = list()))
  per <- lapply(pins, function(p) {
    m12 <- substr(as.character(p$md5 %||% ""), 1L, 12L)
    hit <- P$loads[md5_12 == m12]
    okn <- nrow(hit) > 0L && all(hit$kind == "hit" | hit$engine %in% basename(p$path))
    list(path = p$path, md5_12 = m12, n_lines = nrow(hit), kinds = unique(hit$kind), ok = !is.na(p$md5) && nchar(m12) == 12L && okn)
  })
  okb <- !isTRUE(blend) || (nrow(P$blend) >= 1L && {
    b <- P$blend[nrow(P$blend)]
    identical(b$n, length(pins)) && setequal(trimws(strsplit(b$engines, " + ", fixed = TRUE)[[1]]), basename(vapply(pins, `[[`, "", "path"))) })
  ok <- all(vapply(per, function(z) isTRUE(z$ok), logical(1))) && okb
  list(ok = ok, blend_line = if (isTRUE(blend)) okb else NA, per_engine = per,
       why = if (ok) NA_character_ else paste(c(vapply(Filter(function(z) !isTRUE(z$ok), per), function(z) sprintf("%s 적재 줄 %d(md5 앞 12자 %s)", basename(z$path), z$n_lines, z$md5_12), ""),
                                                if (!okb) "engine_blend 줄 불일치"), collapse = " · "))
}
## 엔진 대조 — 사양 base_signal(종류 · 경로) = 부품의 기대 엔진 ∧ RX0 사양 = 평균 표적 엔진 ∧ 쓰인 엔진 파일마다 사전등록 핀 md5 = 현재 md5
p5_engine_check <- function(sv, sr, comp, pre, root) {
  xv <- p5_expected_engines(comp); xr <- p5_expected_engines("RX0")
  if (is.null(xv)) return(list(ok = FALSE, why = paste("기대 엔진 표에 없는 부품:", comp), variant_pins = list(), rx0_pins = list(), uses_dt = FALSE))
  ov <- p5_spec_engines(sv, root); or <- p5_spec_engines(sr, root)
  same <- function(a, b) length(a) == length(b) && setequal(tolower(a), tolower(b))
  okK <- identical(ov$kind, xv$kind) && identical(or$kind, xr$kind)
  pin1 <- function(p) { pm <- p5_pin_md5(pre, p); cm <- p5_md5(file.path(root, p)); list(path = p, md5 = pm, current = cm, ok = !is.na(pm) && identical(pm, cm)) }
  vp <- lapply(ov$paths, pin1); rp <- lapply(or$paths, pin1)
  okP <- if (isTRUE(xv$reseed)) length(ov$paths) == 1L && same(or$paths, xr$paths) && !.p5_same_path(ov$paths, P2R05_RX0_ENGINE) &&
                                 !identical(vp[[1]]$current, rp[[1]]$current %||% NA_character_) else same(ov$paths, xv$paths) && same(or$paths, xr$paths)
  okN <- length(vp) > 0L && length(rp) > 0L && all(vapply(c(vp, rp), function(z) isTRUE(z$ok), logical(1)))
  ok <- okK && okP && okN
  why <- c(if (!okK) sprintf("엔진 종류 %s(기대 %s) · RX0 %s", ov$kind %||% "NA", xv$kind, or$kind %||% "NA"),
           if (!okP) sprintf("엔진 경로 %s(기대 %s) · RX0 %s", paste(ov$paths, collapse = "+"),
                             if (isTRUE(xv$reseed)) "RX0 엔진과 다른 파일 · 다른 md5 의 평균 엔진 1개" else paste(xv$paths, collapse = "+"), paste(or$paths, collapse = "+")),
           if (!okN) paste("엔진 핀:", paste(vapply(Filter(function(z) !isTRUE(z$ok), c(vp, rp)), function(z) sprintf("%s(핀 %s · 현재 %s)", z$path, z$md5 %||% "없음", z$current %||% "NA"), ""), collapse = " · ")))
  list(ok = ok, why = if (length(why)) paste(why, collapse = " / ") else NA_character_, expected = xv, observed = ov, rx0_observed = or,
       variant_pins = vp, rx0_pins = rp, uses_dt = p5_uses_dt(ov$paths), checks = list(kind = okK, paths = okP, pins = okN))
}
## 워밍 센티널(JSON) — cache_months 완료(done = total ≥ 1 · "N/M" 문자열 또는 {done, total}) ∧ positive_control 통과(참 · "pass" · {pass|ok|passed: 참}) ∧ code_version 일치
.p5_cache_months <- function(x) {
  if (is.character(x) && length(x) == 1L && grepl("^[0-9]+/[0-9]+$", trimws(x))) { v <- as.numeric(strsplit(trimws(x), "/", fixed = TRUE)[[1]]); return(list(done = v[1], total = v[2])) }
  if (is.list(x) && !is.null(x[["done"]]) && !is.null(x[["total"]])) return(list(done = suppressWarnings(as.numeric(x[["done"]]))[1], total = suppressWarnings(as.numeric(x[["total"]]))[1]))
  list(done = NA_real_, total = NA_real_)
}
.p5_truthy_pass <- function(x) {
  if (is.logical(x) && length(x) == 1L) return(isTRUE(x))
  if (is.character(x) && length(x) == 1L) return(tolower(trimws(x)) %in% c("pass", "passed", "ok", "통과"))
  if (is.list(x)) { for (k in c("pass", "passed", "ok")) if (!is.null(x[[k]])) return(isTRUE(as.logical(x[[k]]))); return(FALSE) }
  FALSE
}
p5_warm_check <- function(path, code_version = P2R05_CODE_VERSION) {
  if (!file.exists(path)) return(list(ok = FALSE, status = "absent", why = "워밍 센티널 없음"))
  w <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(w)) return(list(ok = FALSE, status = "unreadable", why = "워밍 센티널 JSON 판독 실패"))
  cm <- .p5_cache_months(w[["cache_months"]]); pc <- .p5_truthy_pass(w[["positive_control"]]); cv <- as.character(w[["code_version"]] %||% NA_character_)[1]
  okC <- is.finite(cm$done) && is.finite(cm$total) && cm$total >= 1 && cm$done == cm$total
  ok <- okC && isTRUE(pc) && identical(cv, code_version)
  list(ok = ok, status = if (ok) "ok" else "mismatch", cache_done = cm$done, cache_total = cm$total, cache_complete = okC, positive_control = pc,
       code_version = cv, code_version_expected = code_version, md5 = p5_md5(path),
       why = if (ok) NA_character_ else paste(c(if (!okC) sprintf("분위 캐시 %s/%s", format(cm$done), format(cm$total)), if (!isTRUE(pc)) "양성 대조 통과 아님",
                                               if (!identical(cv, code_version)) sprintf("code_version %s(기대 %s)", cv %||% "NA", code_version)), collapse = " · "))
}
## 표적 정의 대조 대상 = 분위 엔진 파일(사양 base_signal 중 DT 폴더) — 재시드 짝(RX0S · 평균 엔진 사본)은 DT 폴더(rx0s/)에 있어도 뺀다
##   (평균 엔진에는 .DT_VETO_SHARE 가 없어 파일 간 상수 대조가 깨지고 ⑮ 가 '미측정'으로 접힌다 — 건식 실행 10-18 발견)
p5_dt_engine_files <- function(cells, root) unique(unlist(lapply(Filter(function(cl) !isTRUE(p5_expected_engines(cl$component)$reseed), cells), function(cl) {
  s <- tryCatch(fromJSON(file.path(root, cl$path), simplifyVector = FALSE), error = function(e) NULL)
  ps <- if (is.null(s)) character(0) else p5_spec_engines(s, root)$paths; ps[vapply(ps, p5_uses_dt, logical(1))] })))
## 워밍 센티널 해석(Q 10-18 통합 정렬 2) — 측정에 묶인 사본 results/warm_sentinel.json(measure.sh 가 측정 때 복사)을 먼저 읽고 없을 때만 night_state/p2r05_warm.done ·
##   두 판이 다 있고 다르면(md5) ⑩(a) 기록에 '센티널 판본 다름' 꼬리표(판정 입력 = 읽은 판 그대로 · 꼬리표는 기록만)
p5_warm_resolve <- function(res_dir, night_path, code_version = P2R05_CODE_VERSION) {
  bound <- file.path(res_dir, "warm_sentinel.json"); hb <- file.exists(bound)
  w <- p5_warm_check(if (hb) bound else night_path, code_version)
  mb <- p5_md5(bound); mn <- p5_md5(night_path); dif <- !is.na(mb) && !is.na(mn) && !identical(mb, mn)
  c(w, list(source = if (hb) "results/warm_sentinel.json" else "night_state/p2r05_warm.done", path = if (hb) bound else night_path, bound_md5 = mb, night_md5 = mn,
            version_differ = dif, version_tag = if (dif) "센티널 판본 다름" else NA_character_))
}
## 템플릿 차분 대조(⑩(b)) — 스크립트를 다시 실행해 rc 0 · runner(script) = 픽스처 주입용(기본 = Rscript)
p5_template_check <- function(root, script = P2R05_TEMPLATE_CHECK, runner = NULL) {
  p <- file.path(root, script)
  if (!file.exists(p)) return(list(ok = FALSE, rc = NA_integer_, status = "absent", why = "템플릿 차분 대조 스크립트 없음", md5 = NA_character_))
  run <- runner %||% function(f) suppressWarnings(system2("Rscript", shQuote(f), stdout = TRUE, stderr = TRUE))
  o <- tryCatch(run(p), error = function(e) structure(paste("error:", conditionMessage(e)), status = 127L))
  rc <- attr(o, "status"); rc <- if (is.null(rc)) 0L else as.integer(rc)
  list(ok = identical(rc, 0L), rc = rc, status = if (identical(rc, 0L)) "ok" else "fail", tail = utils::tail(as.character(o), 5L), md5 = p5_md5(p),
       why = if (identical(rc, 0L)) NA_character_ else sprintf("템플릿 차분 대조 rc %s", format(rc)))
}
## ⑩ 구성 증거 — 분위 엔진 · 결합 칸(V1 · V2 · Q50 · N · S · W2 · RX0 짝)
##   (a) 엔진 대조(종류 · 경로 · 핀) ∧ 사양 구성 키 동일(base_signal 밖) ∧ 셀 로그 팩터 적재 = 사양(변형 · RX0) ∧ 기저 적재 줄(변형 · RX0) ∧ 워밍 센티널(분위 엔진 칸)
##   (b) 템플릿 차분 대조 rc 0(분위 엔진 칸) ∧ months= 같음 — (c) 전달량은 창이 정해진 뒤 p5_eval_pair · (d) 교차율 · 횡단면 표준편차 = 라운드 기록(ctx$tail_d)
p5_construction_dt <- function(comp, sv, sr, lv, lr, Lv, Lr, ctx, expect_cell, expect_cell_rx0) {
  ec <- p5_engine_check(sv, sr, comp, ctx$pre, ctx$root)
  ss <- p5_spec_same(sv, sr)
  sid_v <- .p5_factor_ids(sv$factors); sid_r <- .p5_factor_ids(sr$factors)
  okV <- isTRUE(lv$found) && identical(lv$cell, expect_cell) && identical(lv$factors, sid_v)
  okR <- isTRUE(lr$found) && identical(lr$cell, expect_cell_rx0) && identical(lr$factors, sid_r)
  BLv <- p5_base_load_check(p5_parse_base_load(Lv), ec$variant_pins, blend = identical(ec$expected$kind, "engine_blend"))
  BLr <- p5_base_load_check(p5_parse_base_load(Lr), ec$rx0_pins, blend = FALSE)
  rs <- isTRUE(ec$expected$reseed)
  dt <- isTRUE(ec$uses_dt) && !rs                                                # 재시드 짝 = 평균 엔진 — 분위 캐시 워밍 · 템플릿 대조 해당 없음
  seedrec <- if (rs) { sb <- function(p) if (length(p) && !is.na(p)) .p5_const(sub("\r$", "", readLines(file.path(ctx$root, p), warn = FALSE, encoding = "UTF-8")), ".SEED_BASE") else NA_real_
                       a <- tryCatch(sb(ec$observed$paths[1]), error = function(e) NA_real_); b <- tryCatch(sb(ec$rx0_observed$paths[1]), error = function(e) NA_real_)
                       list(seed_base = a, seed_base_rx0 = b, differ = is.finite(a) && is.finite(b) && a != b,
                            note = "기록 — 엔진 파일의 .SEED_BASE 상수(다른 방식의 재시드면 NA · 판정 아님)") } else NULL
  wm <- ctx$warm %||% list(ok = FALSE, status = "absent", why = "워밍 센티널 미확인")
  tc <- ctx$template %||% list(ok = FALSE, status = "absent", why = "템플릿 차분 대조 미실행")
  okW <- !dt || isTRUE(wm$ok); okT <- !dt || isTRUE(tc$ok)
  okM <- isTRUE(lv$found) && isTRUE(lr$found) && identical(lv$months, lr$months)
  a <- isTRUE(ec$ok) && isTRUE(ss$ok) && okV && okR && isTRUE(BLv$ok) && isTRUE(BLr$ok) && okW
  b <- okT && okM
  pj <- function(x) if (length(x)) paste(x, collapse = "+") else "none"
  why <- c(if (!isTRUE(ec$ok)) ec$why, if (!isTRUE(ss$ok)) paste("사양 구성 키 다름:", paste(ss$differ, collapse = ",")),
           if (!okV) sprintf("변형 로그: 적재 줄 %s · cell %s(기대 %s) · 적재 %s(기대 %s)", isTRUE(lv$found), lv$cell %||% "-", expect_cell, pj(lv$factors), pj(sid_v)),
           if (!okR) sprintf("RX0 로그: 적재 줄 %s · cell %s(기대 %s) · 적재 %s(기대 %s)", isTRUE(lr$found), lr$cell %||% "-", expect_cell_rx0, pj(lr$factors), pj(sid_r)),
           if (!isTRUE(BLv$ok)) paste("변형 기저 적재 줄:", BLv$why), if (!isTRUE(BLr$ok)) paste("RX0 기저 적재 줄:", BLr$why),
           if (!okW) paste("워밍 센티널:", wm$why %||% wm$status), if (!okT) paste("템플릿 차분 대조:", tc$why %||% tc$status),
           if (!okM) "같은 배치 months= 불일치 또는 없음")
  keep <- c("found", "n_lines", "cell", "univ", "factors", "wt")
  list(ok = a && b, why = if (length(why)) paste(why, collapse = " / ") else NA_character_, flavor = if (rs) "reseed" else "quantile_engine", seed = seedrec,
       checks = list(a_engine = isTRUE(ec$ok), a_spec_same = isTRUE(ss$ok), a_variant_log = okV, a_rx0_log = okR, a_base_load_variant = isTRUE(BLv$ok),
                     a_base_load_rx0 = isTRUE(BLr$ok), a_warm = okW, b_template = okT, b_months_equal = okM),
       uses_dt = dt, engines = list(expected = ec$expected, observed = ec$observed, pins = c(ec$variant_pins, ec$rx0_pins)), spec_differ = ss$differ,
       base_load = list(variant = BLv[c("ok", "blend_line", "per_engine")], rx0 = BLr[c("ok", "per_engine")]),
       warm = if (dt) wm[intersect(names(wm), c("ok", "status", "cache_done", "cache_total", "positive_control", "code_version", "source", "version_differ", "version_tag"))] else list(status = "not_applicable"),
       template = if (dt) tc[intersect(names(tc), c("ok", "status", "rc", "md5"))] else list(status = "not_applicable"),
       blend_share = if (identical(ec$expected$kind, "engine_blend")) 1 / length(ec$expected$paths) else NA_real_,
       variant_log = lv[intersect(names(lv), keep)], rx0_log = lr[intersect(names(lr), keep)], record_d = ctx$tail_d)
}
## ⑩ 구성 증거 — 비교 기준 LV(P2R04 ⑩ 형식: 사양 = RX0 factors + D03_RealVol 꼬리 · 셀 로그 3대조 · 혼합 몫 = 기대(도구 상자 기본) · 기저 엔진 = RX0 엔진 핀 · months=)
p5_lv_expect_weight <- function(cells, root) {
  z <- Filter(function(c0) identical(c0$engine, P2R05_DIAGNOSTICS$LV$weight_toolbox_on) && identical(c0$component, "RX0") && !isTRUE(c0$diagnostic), cells)
  s <- if (length(z)) tryCatch(fromJSON(file.path(root, z[[1]]$path), simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (is.null(s)) return(NA_real_)
  p2_blend_weight(s$base_weight, length(s$factors %||% list()) + 1L, 1L)$device_weight
}
p5_construction_lowvol <- function(sv, sr, lv, lr, Lv, Lr, ctx, expect_cell, expect_cell_rx0, expect_weight) {
  dev <- P2R05_DIAGNOSTICS$LV$factor
  cs <- p2_construction_check(lv, lr, dev, sv$factors, sr$factors, expect_cell, expect_cell_rx0)
  bw <- p2_blend_weight(sv$base_weight, length(cs$spec_factors), cs$device_count)
  ew <- suppressWarnings(as.numeric(expect_weight %||% NA))[1]
  bw$expected <- ew; bw$ok <- is.finite(ew) && is.finite(bw$device_weight) && abs(bw$device_weight - ew) < 1e-9          # 1e-9 = 부동소수 여유(결정 수치 아님)
  ec <- p5_engine_check(sv, sr, "LV", ctx$pre, ctx$root)
  ss <- p5_spec_same(sv, sr, drop = c("factors", "base_weight"), drop_fixed = "base_weight")
  BLv <- p5_base_load_check(p5_parse_base_load(Lv), ec$variant_pins); BLr <- p5_base_load_check(p5_parse_base_load(Lr), ec$rx0_pins)
  okM <- isTRUE(lv$found) && isTRUE(lr$found) && identical(as.integer(lv$months), as.integer(lr$months))
  ok <- isTRUE(cs$ok) && isTRUE(bw$ok) && isTRUE(ec$ok) && isTRUE(ss$ok) && isTRUE(BLv$ok) && isTRUE(BLr$ok) && okM
  why <- c(if (!isTRUE(cs$ok)) cs$why, if (!isTRUE(bw$ok)) sprintf("혼합 몫 %s(기대 %s)", format(bw$device_weight), format(ew)), if (!isTRUE(ec$ok)) ec$why,
           if (!isTRUE(ss$ok)) paste("사양 구성 키 다름:", paste(ss$differ, collapse = ",")), if (!isTRUE(BLv$ok)) paste("변형 기저 적재 줄:", BLv$why),
           if (!isTRUE(BLr$ok)) paste("RX0 기저 적재 줄:", BLr$why), if (!okM) "같은 배치 months= 불일치 또는 없음")
  c(cs[setdiff(names(cs), c("ok", "why"))],
    list(ok = ok, why = if (length(why)) paste(why, collapse = " / ") else NA_character_, flavor = "lowvol_screen", blend = bw,
         checks2 = list(engine = isTRUE(ec$ok), spec_same = isTRUE(ss$ok), base_load_variant = isTRUE(BLv$ok), base_load_rx0 = isTRUE(BLr$ok), months_equal = okM),
         engines = list(expected = ec$expected, observed = ec$observed, pins = c(ec$variant_pins, ec$rx0_pins)), spec_differ = ss$differ))
}

## ── P2R05 순수 도우미 ② — ⑮ 꼬리 계기 · 표적 정의 대조 · 라벨 · 기량 · 기록 ───────────────────────────────────────────
p5_rho <- function(u, tau) u * (tau - (u < 0))                                  # pinball ρ_τ(u) = u(τ − 1{u<0}) — Koenker & Bassett (1978)
.p5_norm_ws <- function(x) { y <- gsub("[[:space:]]+", " ", trimws(as.character(x))); names(y) <- names(x); y }   # 이름 보존(as.character 가 지운다)
.p5_qcol <- function(tau) sprintf("q%02d", as.integer(round(100 * as.numeric(tau))))
.p5_hold_ym <- function(d) format(as.Date(format(as.Date(d), "%Y-%m-01")) + 32L, "%Y-%m")   # 월말 신호 d 의 보유월(다음 달)
.p5_month_floor <- function(d) as.Date(format(as.Date(d), "%Y-%m-01"))
## 보는 창 RAW — τ_D 까지(τ_D 당일 포함)의 행만 · 보는 창 기록은 이 사본으로만 만든다(τ_D 이후 행을 읽지 않는다)
p5_visible_cut <- function(RAW, tau) RAW[Date <= as.Date(tau)]
## 보는 창 신호일 — 보유월(신호 다음 달) ≤ τ_D 의 달 = 신호일 < τ_D 달의 첫날(DESIGN §5 ⑮ · §8.2 — 2005-01-31 ~ 2022-11-30)
p5_visible_signals <- function(Q, tau) Q[Date < .p5_month_floor(tau)]
## 정본 NW(.nw_t_mean) — backtest_result_contract.R 을 파싱해 그 정의만 평가(사본 금지 · b_ewcw_paired.R 과 같은 방식)
p5_nw_fun <- function(root) {
  p <- file.path(root, P2R05_NW_SOURCE)
  if (!file.exists(p)) stop("[P2R05 평가] 정본 NW 계약 없음: ", P2R05_NW_SOURCE)
  ex <- parse(file = p, encoding = "UTF-8", keep.source = FALSE); env <- new.env(parent = baseenv())
  for (e in as.list(ex)) if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) && identical(as.character(e[[2]]), ".nw_t_mean")) eval(e, envir = env)
  if (!exists(".nw_t_mean", envir = env, inherits = FALSE)) stop("[P2R05 평가] backtest_result_contract.R 에 .nw_t_mean 이 없다 — NW 식을 사본으로 만들지 않는다")
  env$.nw_t_mean
}
## 엔진 파일 상수(.HORIZON · .QUINT · .DT_VETO_SHARE) — '^이름 <- 값' 줄 하나의 값(여럿이 다르면 NA)
.p5_const <- function(L, name) {
  esc <- gsub(".", "\\.", name, fixed = TRUE)
  rx <- paste0("^", esc, "[[:space:]]*<-[[:space:]]*([0-9]+(?:\\.[0-9]+)?)L?(?:[[:space:]].*|#.*)?$")
  hit <- grep(rx, L, value = TRUE, perl = TRUE)
  v <- unique(sub(rx, "\\1", hit, perl = TRUE))
  if (length(v) == 1L) suppressWarnings(as.numeric(v)) else NA_real_
}
## 분위 엔진 파일 1개의 표적 정의 — 줄 일치(P2R05_YDEF_SNIPPETS) · 상수 · .rank01(파싱해 그 함수) · 표적 블록(라벨 줄 ~ 'rm(.LAB)' 줄)
p5_ydef_file <- function(path) {
  if (!file.exists(path)) return(list(ok = FALSE, why = "엔진 파일 없음", path = path))
  L <- sub("\r$", "", readLines(path, warn = FALSE, encoding = "UTF-8")); N <- .p5_norm_ws(L)
  sn <- .p5_norm_ws(P2R05_YDEF_SNIPPETS)
  has <- vapply(sn, function(s) any(grepl(s, N, fixed = TRUE)), logical(1))
  i0 <- which(grepl(sn[["label"]], N, fixed = TRUE)); i1 <- which(grepl(sn[["label_end"]], N, fixed = TRUE))
  i0 <- if (length(i0)) i0[1] else NA_integer_; i1 <- if (length(i1) && !is.na(i0)) i1[i1 >= i0][1] else NA_integer_
  block <- if (!is.na(i0) && !is.na(i1) && (i1 - i0) <= 8L) L[i0:i1] else character(0)
  r01 <- tryCatch({
    ex <- parse(file = path, encoding = "UTF-8", keep.source = FALSE); env <- new.env(parent = globalenv())
    for (e in as.list(ex)) if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) && identical(as.character(e[[2]]), ".rank01")) eval(e, envir = env)
    if (exists(".rank01", envir = env, inherits = FALSE) && is.function(env$.rank01)) env$.rank01 else NULL
  }, error = function(e) NULL)
  H <- .p5_const(L, ".HORIZON"); Q <- .p5_const(L, ".QUINT"); VS <- .p5_const(L, ".DT_VETO_SHARE")
  ok <- all(has) && length(block) > 0L && is.function(r01) && is.finite(H) && H >= 1
  list(ok = ok, path = path, md5 = p5_md5(path), missing = names(sn)[!has], horizon = H, quint = Q, veto_share = VS, rank01 = r01, block = block,
       why = if (ok) NA_character_ else paste(c(if (!all(has)) paste("표적 정의 줄 없음:", paste(names(sn)[!has], collapse = ",")),
                                               if (!length(block)) "표적 블록(라벨 줄 ~ rm(.LAB)) 추출 실패", if (!is.function(r01)) ".rank01 추출 실패",
                                               if (!is.finite(H)) ".HORIZON 판독 실패"), collapse = " · "))
}
## 평가 라벨(⑮ · 기록) — 엔진 표적 정의 그대로: 거래일 = RAWDATA 날짜 · 종가 > 0 행만 · 같은 (종목, 날짜) 첫 행 · 시가 0 · 결측 = NA ·
##   신호일 s 의 라벨 = 종가(s + H) / 시가(s + 1) − 1(시가 열이 없으면 종가(s + H) / 종가(s) − 1) · H = 엔진 .HORIZON
p5_labels <- function(RAW, dates, H, has_open = "Open" %in% names(RAW)) {
  emp <- data.table(Date = as.Date(character(0)), Ticker = character(0), y_raw = numeric(0), d1 = as.Date(character(0)), dH = as.Date(character(0)))
  H <- as.integer(H); if (is.na(H) || H < 1L) return(emp)
  cal <- sort(unique(as.Date(RAW$Date)))
  R <- RAW[is.finite(Close) & Close > 0, c("Date", "Ticker", "Close", if (isTRUE(has_open)) "Open"), with = FALSE]
  R <- unique(R, by = c("Ticker", "Date"))
  if (isTRUE(has_open)) { R[, Open := as.numeric(Open)]; R[!is.finite(Open) | Open <= 0, Open := NA_real_] }
  dates <- sort(unique(as.Date(dates))); i <- match(dates, cal)
  ok <- !is.na(i) & (i + H) <= length(cal)
  if (!any(ok)) return(emp)
  M <- data.table(Date = dates[ok], d0 = cal[i[ok]], d1 = cal[i[ok] + 1L], dH = cal[i[ok] + H])
  C <- R[Date %in% M$dH, .(dH = Date, Ticker, cl = as.numeric(Close))]
  if (isTRUE(has_open)) {
    E <- R[Date %in% M$d1, .(d1 = Date, Ticker, en = Open)]
    L <- merge(M, E, by = "d1", allow.cartesian = TRUE)
  } else {
    E <- R[Date %in% M$d0, .(d0 = Date, Ticker, en = as.numeric(Close))]
    L <- merge(M, E, by = "d0", allow.cartesian = TRUE)
  }
  L <- merge(L, C, by = c("dH", "Ticker"))
  L[, y_raw := cl / en - 1]
  L[is.finite(y_raw), .(Date, Ticker, y_raw, d1, dH)][order(Date, Ticker)]
}
## 표적 정의 대조 단정(합성 격자) — 엔진 파일의 표적 블록 자체를 엔진 격자 규약(거래일 완비 · 종가 > 0 · 시가 센티널 · 첫 행)으로 만든 합성 격자에 돌려
##   평가 라벨 함수(p5_labels)와 비교(시가 있음 · 없음 두 경우) + .rank01 검산(엔진 양성 대조와 같은 값). 정답 = 엔진 코드 · 피검 = 평가 코드
.p5_oracle_raw <- function() {
  d <- as.Date("2021-03-01") + c(0:4, 7:11, 14:18)
  tk <- c("A000010", "A000020", "A000030", "A000040")
  R <- CJ(Ticker = tk, Date = d)
  R[, j := match(Date, d)][, b := match(Ticker, tk)]
  R[, Close := 100 * (1 + 0.01 * b)^j][, Open := Close * (1 - 0.003 * b)]
  R <- R[!(Ticker == "A000020" & j == 3L)]                                       # 행 없음(정지 · 결측)
  R[Ticker == "A000030" & j == 2L, Open := 0]                                    # 시가 0(센티널 → NA)
  R[Ticker == "A000040" & j == 7L, Close := NA_real_]                            # 종가 결측(행 탈락)
  R[Ticker == "A000010" & j == 9L, Close := -1]                                  # 종가 음수(행 탈락)
  R <- rbind(R, copy(R[Ticker == "A000030" & j == 5L])[, Close := Close * 2])     # 중복 행(뒤 행) — 앞 행 유지
  R[, c("j", "b") := NULL]
  R[]
}
.p5_oracle_cmp <- function(R, H, block, has_open, label_fun) {
  cal <- sort(unique(R$Date))
  rd <- R[is.finite(Close) & Close > 0]
  rd <- unique(rd, by = c("Ticker", "Date"))
  if (has_open) { rd[, Open := as.numeric(Open)]; rd[!is.finite(Open) | Open <= 0, Open := NA_real_] } else rd[, Open := NA_real_]
  G <- CJ(Ticker = sort(unique(rd$Ticker)), Date = cal)
  G <- rd[G, on = .(Ticker, Date)]
  G[data.table(Date = cal, di = seq_along(cal)), on = "Date", di := i.di]
  setorder(G, Ticker, Date)
  e <- new.env(parent = globalenv()); e$.G <- G; e$.HORIZON <- as.integer(H); e$.HAS_OPEN <- isTRUE(has_open)
  eval(parse(text = block, keep.source = FALSE), envir = e)
  ref <- e$.G[is.finite(y_raw), .(Date, Ticker, y_ref = y_raw)]
  got <- label_fun(if (has_open) R else R[, setdiff(names(R), "Open"), with = FALSE], cal, H, has_open = has_open)
  J <- merge(ref, got[, .(Date, Ticker, y_raw)], by = c("Date", "Ticker"), all = TRUE)
  list(ok = nrow(ref) > 0L && nrow(J) == nrow(ref) && nrow(J) == nrow(got) && all(is.finite(J$y_ref) & is.finite(J$y_raw)) && identical(J$y_ref, J$y_raw),
       n_ref = nrow(ref), n_eval = nrow(got), n_joined = nrow(J))
}
p5_ydef_oracle <- function(rank01, H, block, label_fun = p5_labels) {
  tryCatch({
    R <- .p5_oracle_raw()
    o1 <- .p5_oracle_cmp(R, H, block, TRUE, label_fun); o2 <- .p5_oracle_cmp(R, H, block, FALSE, label_fun)
    rk <- rank01(c(3, NA, 1, 2, 2)); o3 <- isTRUE(all.equal(rk, c(1, 0.5, 0.25, 0.625, 0.625)))
    list(ok = isTRUE(o1$ok) && isTRUE(o2$ok) && o3, open = o1, no_open = o2, rank01_check = o3)
  }, error = function(e) list(ok = FALSE, why = conditionMessage(e)))
}
## 표적 정의 대조 단정(라운드 1회) — 칸 사양이 쓰는 분위 엔진 파일 전부: 줄 일치 · 상수 같음 · .rank01 같음(검산) · 합성 격자 대조
p5_ydef_check <- function(paths, root, label_fun = p5_labels) {
  if (!length(paths)) return(list(ok = FALSE, why = "분위 엔진 파일 없음(사양 base_signal)", files = list()))
  per <- lapply(paths, function(p) p5_ydef_file(file.path(root, p)))
  okf <- vapply(per, function(z) isTRUE(z$ok), logical(1))
  cst <- function(k) unique(vapply(per, function(z) as.numeric(z[[k]] %||% NA_real_), numeric(1)))
  Hs <- cst("horizon"); Qs <- cst("quint"); Vs <- cst("veto_share")
  okc <- length(Hs) == 1L && is.finite(Hs) && length(Qs) == 1L && length(Vs) == 1L
  orc <- if (all(okf) && okc) p5_ydef_oracle(per[[1]]$rank01, Hs, per[[1]]$block, label_fun) else list(ok = FALSE, why = "줄 · 상수 대조 실패로 합성 대조 생략")
  ok <- all(okf) && okc && isTRUE(orc$ok)
  list(ok = ok, horizon = if (okc) Hs else NA_real_, quint = if (okc) Qs else NA_real_, veto_share = if (okc) Vs else NA_real_, rank01 = per[[1]]$rank01,
       files = lapply(per, function(z) list(path = p5_rel(z$path, root), md5 = z$md5 %||% NA_character_, ok = isTRUE(z$ok), missing = z$missing %||% character(0))),
       oracle = orc[setdiff(names(orc), character(0))],
       why = if (ok) NA_character_ else paste(c(vapply(per[!okf], function(z) sprintf("%s: %s", basename(z$path), z$why %||% "?"), ""),
                                               if (!okc) "엔진 파일마다 상수(.HORIZON · .QUINT · .DT_VETO_SHARE)가 다르거나 판독 불가",
                                               if (!isTRUE(orc$ok)) paste("합성 격자 대조:", orc$why %||% "평가 라벨 ≠ 엔진 표적 블록")), collapse = " / "))
}
## 평가 중단(사전 고정 실패 의미 — 예측표 판본 불일치 · 판독 · 형식 실패)
p5_halt <- function(reason, detail = NULL) stop(structure(class = c("p5_halt", "error", "condition"), list(message = paste0("[P2R05 평가 중단] ", reason), call = NULL, reason = reason, detail = detail)))
.p5_as_date <- function(v) {
  if (inherits(v, "Date")) return(v)
  if (inherits(v, "POSIXt")) { tz <- attr(v, "tzone"); tz <- if (is.null(tz) || !nzchar(tz[1])) "UTC" else tz[1]; return(as.Date(format(v, "%Y-%m-%d", tz = tz))) }
  as.Date(as.character(v))
}
## 예측표 적재 — 파일마다 열 · 중복 · 보는 창 행 대조(첫 파일 기준 (신호일, 종목) 집합 · q 열 6개 정확히 같음 · 다르면 평가 중단) · 시험 창 행 대조는 기록(사람 쪽 판 쓰임 여부)
p5_qpred_load <- function(dir, tau, files = NULL) {
  tau <- as.Date(tau); vis_lt <- .p5_month_floor(tau)
  fs <- files %||% sort(list.files(dir, pattern = "\\.parquet$", full.names = TRUE))
  if (!length(fs)) return(list(status = "absent", why = "예측표 없음(_work/qpred/*.parquet)", files = list()))
  rd <- lapply(fs, function(f) {
    x <- tryCatch(as.data.table(arrow::read_parquet(f, mmap = FALSE)), error = function(e) NULL)   # mmap 금지(엔진 .dt_qread 와 대칭 · Windows 1224)
    if (is.null(x)) p5_halt("예측표 판독 실패", basename(f))
    miss <- setdiff(P2R05_QPRED_COLS, names(x)); if (length(miss)) p5_halt("예측표 열 결손", sprintf("%s: %s", basename(f), paste(miss, collapse = ",")))
    keep <- c(P2R05_QPRED_COLS, intersect(P2R05_QPRED_OPT_COLS, names(x)))
    x <- x[, keep, with = FALSE]
    x[, Date := .p5_as_date(Date)][, Ticker := as.character(Ticker)]
    for (cc in setdiff(keep, c("Date", "Ticker"))) set(x, j = cc, value = suppressWarnings(as.numeric(x[[cc]])))
    if (anyNA(x$Date) || anyNA(x$Ticker)) p5_halt("예측표 신호일 · 종목 결측", basename(f))
    if (anyDuplicated(x, by = c("Date", "Ticker"))) p5_halt("예측표 (신호일, 종목) 중복", basename(f))
    setorder(x, Date, Ticker); x
  })
  same <- function(a, b) nrow(a) == nrow(b) && identical(a$Date, b$Date) && identical(a$Ticker, b$Ticker) &&
    all(vapply(P2R05_Q_COLS, function(cc) identical(a[[cc]], b[[cc]]), logical(1)))
  V <- lapply(rd, function(x) p5_visible_signals(x, tau)); T <- lapply(rd, function(x) x[Date >= vis_lt])
  bad_v <- which(!vapply(V, function(x) same(x, V[[1]]), logical(1)))
  if (length(bad_v)) p5_halt("예측표 판본 불일치(보는 창 q 열 · (신호일, 종목) 집합)", paste(basename(fs[c(1L, bad_v)]), collapse = " vs "))
  ok_t <- all(vapply(T, function(x) same(x, T[[1]]), logical(1)))
  pick <- which(vapply(rd, function(x) all(P2R05_QPRED_OPT_COLS %in% names(x)), logical(1)))[1]; if (is.na(pick)) pick <- 1L   # 선택 열을 가진 파일 우선(q 열은 모두 같다)
  list(status = "ok", Qv = V[[pick]], Qall = if (ok_t) rd[[pick]] else NULL, full_status = if (ok_t) "ok" else "test_window_mismatch",
       optional_columns = intersect(P2R05_QPRED_OPT_COLS, names(rd[[pick]])),
       files = lapply(seq_along(fs), function(i) list(file = basename(fs[i]), md5 = p5_md5(fs[i]), n_rows = nrow(rd[[i]]), n_visible_rows = nrow(V[[i]]))),
       n_files = length(fs), visible = list(n_dates = uniqueN(V[[1]]$Date), first = format(min(V[[1]]$Date)), last = format(max(V[[1]]$Date)), n_rows = nrow(V[[1]])))
}
## ⑮ 예측표 = 측정에 묶인 판 1개(격리 교차 점검 v1 필수 4 · Q 10-18) — 워밍 센티널(p5_warm_resolve 가 읽은 판 · results/warm_sentinel.json 우선)의 qpred{path, md5}만 읽는다 ·
##   필드 없음 = '예측표 미묶임'(status unbound → ⑮ 미측정 = V 칸 미시험(계기) · 실패 의미 고정) · 묶인 파일 없음 · md5 불일치 = 평가 중단(사유 기록) ·
##   폴더의 다른 파일 = '판본 다른 예측표 n개'(기록만 · 읽지 않는다)
p5_qpred_bound <- function(root, warm, tau, qdir = file.path(root, P2R05_QPRED_DIR)) {
  wp <- warm$path %||% NA_character_
  w <- if (length(wp) == 1L && !is.na(wp) && file.exists(wp)) tryCatch(jsonlite::fromJSON(wp, simplifyVector = FALSE), error = function(e) NULL) else NULL
  qp <- w$qpred; src <- warm$source %||% NA_character_
  allf <- gsub("\\\\", "/", sort(list.files(qdir, pattern = "[.]parquet$", full.names = TRUE)))
  pv <- as.character(unlist(qp$path %||% NA_character_))[1]; mv <- as.character(unlist(qp$md5 %||% NA_character_))[1]
  if (!is.list(qp) || is.na(pv) || is.na(mv) || !nzchar(pv) || !nzchar(mv))
    return(list(status = "unbound", why = "예측표 미묶임(측정에 묶인 워밍 센티널에 qpred 경로 · md5 없음)", sentinel = src, n_files = 0L, n_other = length(allf), other = basename(allf)))
  pv <- gsub("\\\\", "/", pv); f <- if (grepl("^([A-Za-z]:)?/", pv)) pv else file.path(root, pv)
  if (!file.exists(f)) p5_halt("묶인 예측표 없음(워밍 센티널 qpred.path)", pv)
  m <- p5_md5(f)
  if (!identical(m, mv)) p5_halt("예측표 md5 ≠ 측정 묶음(워밍 센티널 qpred.md5)", sprintf("%s: 현재 %s · 묶음 %s", pv, m, mv))
  QP <- p5_qpred_load(dirname(f), tau, files = f)
  sd <- identical(.p5_npath(dirname(f), root), .p5_npath(qdir, root))
  oth <- if (sd) allf[tolower(basename(allf)) != tolower(basename(f))] else allf
  c(QP, list(bound = list(path = p5_rel(f, root), abs = gsub("/+", "/", gsub("\\\\", "/", f)), md5 = m, sentinel = src), n_other = length(oth), other = basename(oth),
             other_note = if (length(oth)) sprintf("판본 다른 예측표 %d개(기록만 · 읽지 않음)", length(oth)) else NA_character_))
}
## ⑮ 예측표 셀 로그 대조(격리 교차 점검 v2 필수 1 · Q 10-18) — 분위 엔진 칸(사양 base_signal 에 DT 분위 엔진 · 재시드 짝 제외 = V1 · V2 · Q50 · N1 · N2 · S1 · S2 · W2 의 V2 성분)의
##   셀 로그 '[DT qpred] path=<경로> rows= months=' 줄(엔진 engine_template.R 이 실행 끝에 찍는다)을 측정에 묶인 판(워밍 센티널 qpred path · md5)과 대조한다:
##   · 줄이 있고 경로(정규화 — 저장소 상대 · 슬래시 · 대소문자 · 문자열 규칙만) 또는 그 파일의 md5 가 묶인 판과 다르면 = 평가 중단(사유 기록 · 실패 의미 고정 — 측정 칸이 쓴 예측표 ≠ ⑮ 입력)
##   · 줄이 없으면(기저 캐시 적중 = 엔진 미실행) '셀 로그 예측표 줄 없음(기저 캐시 적중)' — 그 칸 기저 적재 줄의 캐시 파일(base_v2_<DT 엔진 md5 앞 12자>_<패널 지문>.rds)을
##     같은 평가의 다른 칸이 이번 측정에서 '실행'으로 만들었고 그 칸의 예측표 줄이 묶인 판이면 '같은 기저 캐시(연쇄 대조 통과)' · 아니면 '대조 불가' 꼬리표(⑮ 판정은 유지) —
##     워밍(warm_engine.R)은 셀 기저 캐시를 시드하지 않는다(엔진 월별 DNN 캐시만 데운다) → 기저 캐시가 측정 전부터 있었으면 이 평가 안에서 출처를 대조할 근거가 없다
P2R05_QPRED_LINE_RX <- "^\\[DT qpred\\] path=(.+) rows=([0-9]+) months=([0-9]+)[[:space:]]*$"
p5_qpred_lines <- function(lines) {
  L <- sub("\r$", "", as.character(lines)); h <- grep(P2R05_QPRED_LINE_RX, L, value = TRUE)
  if (!length(h)) character(0) else trimws(sub(P2R05_QPRED_LINE_RX, "\\1", h))
}
## 경로 정규화(문자열 규칙만 — 파일 시스템 조회 없음 · 프로젝트 규약 safety_guard.sh: 경로 정규화 내장 함수는 한글 경로를 깨뜨린다) — 역슬래시 → 슬래시 · 루트 기준 절대화 ·
##   겹 슬래시 · '.' · '..' 구간 정리 · 루트 접두 제거(저장소 상대) · 대소문자
.p5_dotseg <- function(p) vapply(strsplit(p, "/", fixed = TRUE), function(sg) { o <- character(0)
  for (x in sg) { if (identical(x, ".") || (!nzchar(x) && length(o))) next
    if (identical(x, "..") && length(o) && !(o[length(o)] %in% c("..", "")) && !grepl(":$", o[length(o)])) o <- o[-length(o)] else o <- c(o, x) }
  paste(o, collapse = "/") }, character(1))
.p5_npath <- function(p, root) {
  q <- gsub("\\\\", "/", as.character(p)); r <- sub("/+$", "", gsub("\\\\", "/", as.character(root)))
  a <- ifelse(grepl("^([A-Za-z]:)?/", q), q, paste0(r, "/", q))
  tolower(p5_rel(.p5_dotseg(gsub("/+", "/", a)), r))
}
p5_qpred_log_check <- function(cells, res, root, bound) {
  if (!is.list(bound) || (is.null(bound$path) && is.null(bound$abs)) || is.null(bound$md5)) return(list(status = "not_applicable", why = "묶인 예측표 없음(⑮ 미측정 경로)", per_cell = data.table()))
  B <- .p5_npath(bound$path %||% bound$abs, root); rows <- list()
  for (cl in cells) {
    if (isTRUE(p5_expected_engines(cl$component)$reseed)) next
    sp <- tryCatch(jsonlite::fromJSON(file.path(root, cl$path), simplifyVector = FALSE), error = function(e) NULL)
    dtp <- if (is.null(sp)) character(0) else { ps <- p5_spec_engines(sp, root)$paths; ps[vapply(ps, p5_uses_dt, logical(1))] }
    if (!length(dtp)) next
    m12 <- substr(vapply(dtp, function(z) p5_md5(file.path(root, z)) %||% NA_character_, character(1)), 1L, 12L)
    lf <- file.path(res, paste0(cl$code, ".log")); L <- .p2_read_lines(lf)
    rows[[cl$code]] <- list(code = cl$code, engine = cl$engine %||% NA_character_, device = cl$component %||% NA_character_, has_log = file.exists(lf), q = p5_qpred_lines(L),
                            loads = p5_parse_base_load(L)$loads[md5_12 %in% m12])
  }
  runs <- list()
  for (r in rows) if (length(r$q)) {
    for (q in r$q) {
      if (!identical(.p5_npath(q, root), B)) p5_halt("셀 로그 예측표 ≠ 측정 묶음(워밍 센티널 qpred)", sprintf("%s: %s ≠ %s", r$code, q, bound$path %||% bound$abs))
      qf <- gsub("\\\\", "/", q); if (!grepl("^([A-Za-z]:)?/", qf)) qf <- file.path(root, qf)
      mq <- p5_md5(qf); if (!is.na(mq) && !identical(mq, bound$md5)) p5_halt("셀 로그 예측표 md5 ≠ 측정 묶음(워밍 센티널 qpred)", sprintf("%s: %s", r$code, q))
    }
    for (f in r$loads[kind == "run"]$file) runs[[f]] <- r$code
  }
  P <- rbindlist(lapply(rows, function(r) {
    hit <- r$loads[kind == "hit"]$file; run <- r$loads[kind == "run"]$file
    if (!isTRUE(r$has_log)) return(data.table(code = r$code, engine = r$engine, device = r$device, n_lines = 0L, status = "no_log", cache_file = NA_character_,
                                              chained_from = NA_character_, why = "셀 로그 없음(미측정 칸 — 대조 대상 아님 · 미측정은 칸 판정이 따로 다룬다)"))
    if (length(r$q)) return(data.table(code = r$code, engine = r$engine, device = r$device, n_lines = length(r$q), status = "match", cache_file = paste(c(run, hit), collapse = ","),
                                        chained_from = NA_character_, why = NA_character_))
    ch <- hit[hit %in% names(runs)]
    if (length(ch) && !length(run))
      return(data.table(code = r$code, engine = r$engine, device = r$device, n_lines = 0L, status = "chained", cache_file = paste(hit, collapse = ","),
                        chained_from = paste(unique(unlist(runs[ch])), collapse = ","), why = "셀 로그 예측표 줄 없음(기저 캐시 적중) — 같은 기저 캐시를 이번 측정에서 실행한 칸의 예측표 = 묶인 판"))
    data.table(code = r$code, engine = r$engine, device = r$device, n_lines = 0L, status = "unverifiable", cache_file = paste(c(run, hit), collapse = ","), chained_from = NA_character_,
               why = if (length(run)) "엔진 실행 줄은 있는데 셀 로그 예측표 줄 없음 — 대조 불가" else "셀 로그 예측표 줄 없음(기저 캐시 적중) — 기저 캐시가 이번 측정 실행분이 아님(워밍은 기저 캐시를 시드하지 않는다) · 대조 불가")
  }), fill = TRUE)
  if (!nrow(P)) P <- data.table(code = character(0), engine = character(0), device = character(0), n_lines = integer(0), status = character(0), cache_file = character(0),
                                chained_from = character(0), why = character(0))
  nu <- sum(P$status == "unverifiable")
  list(status = "ok", bound = bound$path %||% bound$abs, n_cells = nrow(P), n_match = sum(P$status == "match"), n_chained = sum(P$status == "chained"), n_unverifiable = nu,
       n_no_log = sum(P$status == "no_log"), per_cell = P,
       tag = if (nu) sprintf("⑮ 예측표 셀 로그 대조 불가 %d칸(셀 로그 예측표 줄 없음 · 기저 캐시 출처 미확인 — ⑮ 판정은 유지)", nu) else NA_character_,
       rule = "셀 로그 '[DT qpred] path=' 줄 = 묶인 판(경로 · md5 — 다르면 평가 중단) · 줄 없음 = 같은 기저 캐시 연쇄 대조 또는 '대조 불가' 꼬리표 · 셀 로그 없음 = 미측정(대조 대상 아님)")
}
p5_attach_y <- function(Q, lab, rank01) {
  J <- merge(Q, lab[, .(Date, Ticker, y_raw)], by = c("Date", "Ticker"))
  J <- J[is.finite(y_raw)]
  J[, y := rank01(y_raw), by = Date]
  J[]
}
## ⑮ 꼬리 계기 — D_d = mean_i[ρ_τ(y − τ) − ρ_τ(y − q̂_τ)] · t = 정본 NW(lag = nw_lag) · 조건 t > t_min(final_selection_rule.tail_instrument)
p5_tail_instrument <- function(QY, TI, nw) {
  tau <- suppressWarnings(as.numeric(TI$tau %||% NA))[1]; lag <- suppressWarnings(as.integer(TI$nw_lag %||% NA))[1]
  tmin <- suppressWarnings(as.numeric(TI$t_min %||% NA))[1]; ref <- as.character(TI$ref %||% NA_character_)[1]
  base <- list(tau = tau, nw_lag = lag, t_min = tmin, ref = ref)                 # pass 는 여기 두지 않는다(c() 이름 중복이면 $ 가 앞 값을 읽는다)
  if (!identical(ref, "constant_tau") || !is.finite(tau) || tau <= 0 || tau >= 1 || is.na(lag) || lag < 1L || !is.finite(tmin))
    return(c(base, list(status = "unmeasured", pass = FALSE, why = "꼬리 계기 설정(tail_instrument) 해석 불가")))
  qc <- .p5_qcol(tau)
  if (is.null(QY) || !nrow(QY) || !(qc %in% names(QY))) return(c(base, list(status = "unmeasured", pass = FALSE, why = sprintf("라벨 붙은 예측 행 없음 또는 %s 열 없음", qc))))
  Dd <- QY[is.finite(y) & is.finite(get(qc)), .(n = .N, D = mean(p5_rho(y - tau, tau) - p5_rho(y - get(qc), tau))), by = Date][order(Date)]
  t <- if (nrow(Dd)) nw(Dd$D, lag = lag) else NA_real_
  st <- if (is.finite(t)) "ok" else "unmeasured"
  c(base, list(status = st, t = t, n_dates = nrow(Dd), mean_D = if (nrow(Dd)) mean(Dd$D) else NA_real_, q_col = qc,
               pass = identical(st, "ok") && t > tmin, margin = if (is.finite(t)) t - tmin else NA_real_,
               why = if (identical(st, "ok")) NA_character_ else "NW t 비유한(표본 부족 또는 분산 0)",
               window = if (nrow(Dd)) c(format(min(Dd$Date)), format(max(Dd$Date))) else NA_character_, per_date = Dd))
}
## 기록 — 분위 기량 R¹(τ) = 1 − Σρ(y − q̂τ) / Σρ(y − τ)(Koenker & Machado 1999 형식) 월별 요약 · 열 q10 · q50 · q90 → τ 0.1 · 0.5 · 0.9
.p5_taus <- function(QY) { qc <- intersect(c("q10", "q50", "q90"), names(QY)); setNames(as.numeric(sub("^q", "", qc)) / 100, qc) }
.p5_sm <- function(v) { v <- v[is.finite(v)]; if (!length(v)) list(n = 0L) else list(n = length(v), mean = mean(v), median = stats::median(v), min = min(v), max = max(v)) }
p5_r1_monthly <- function(QY) {
  tt <- .p5_taus(QY)
  lapply(setNames(names(tt), names(tt)), function(qc) {
    tau <- tt[[qc]]
    D <- QY[is.finite(y) & is.finite(get(qc)), .(num = sum(p5_rho(y - get(qc), tau)), den = sum(p5_rho(y - tau, tau))), by = Date]
    D[, r1 := 1 - num / den]
    c(list(tau = tau, pooled = if (nrow(D)) 1 - sum(D$num) / sum(D$den) else NA_real_, share_positive = if (nrow(D)) mean(D$r1 > 0) else NA_real_), .p5_sm(D$r1))
  })
}
p5_hits <- function(QY) {
  if (is.null(QY) || !nrow(QY)) return(list(n = 0L))
  one <- function(qc) { v <- QY[is.finite(y) & is.finite(get(qc)), .(h = mean(y <= get(qc))), by = Date]
                        c(list(pooled = QY[is.finite(y) & is.finite(get(qc)), mean(y <= get(qc))]), list(by_date = .p5_sm(v$h))) }
  list(n_rows = nrow(QY), n_dates = uniqueN(QY$Date), q10 = one("q10"), q50 = one("q50"), q90 = one("q90"))
}
## D^σ · D^perm — 같은 주변분포 짝(q̃10 = q̂50 − s_σ · q̂50 − s_perm) 대비 DNN q̂10 의 분위 손실 이득 · NW t(같은 lag)
p5_dalt <- function(QY, TI, nw, scol) {
  tau <- as.numeric(TI$tau); lag <- as.integer(TI$nw_lag); qc <- .p5_qcol(tau)
  if (is.null(QY) || !nrow(QY) || !(scol %in% names(QY))) return(list(status = "unmeasured", why = paste("열 없음:", scol)))
  Dd <- QY[is.finite(y) & is.finite(get(qc)) & is.finite(q50) & is.finite(get(scol)),
           .(n = .N, D = mean(p5_rho(y - (q50 - get(scol)), tau) - p5_rho(y - get(qc), tau))), by = Date][order(Date)]
  t <- if (nrow(Dd)) nw(as.numeric(Dd$D), lag = lag) else NA_real_
  list(status = if (is.finite(t)) "ok" else "unmeasured", s_col = scol, tau = tau, nw_lag = lag, t = t, mean_D = if (nrow(Dd)) mean(Dd$D) else NA_real_,
       n_dates = nrow(Dd), t_minus_t_min = if (is.finite(t)) t - as.numeric(TI$t_min) else NA_real_, per_date = Dd)
}
## D^w(판단 Superfan T1 R-20261018-007 C-059 · GPU 0) — 같은 모델의 대칭 폭 짝 q̃10_w = q̂50 − (q̂90 − q̂50) 대비 q̂10 의 분위 손실 이득 · NW t(같은 lag)
##   양수 = 왼꼬리가 대칭 폭 이상의 비대칭 정보를 가진다 · '꼬리 증분'(계기 → 다음 행동 표) = D^σ t > t_min ∧ D^w t > t_min
p5_dwidth <- function(QY, TI, nw) {
  tau <- as.numeric(TI$tau); lag <- as.integer(TI$nw_lag); qc <- .p5_qcol(tau)
  if (is.null(QY) || !nrow(QY) || !all(c("q50", "q90") %in% names(QY))) return(list(status = "unmeasured", why = "q50 · q90 열 없음"))
  Dd <- QY[is.finite(y) & is.finite(get(qc)) & is.finite(q50) & is.finite(q90),
           .(n = .N, D = mean(p5_rho(y - (q50 - (q90 - q50)), tau) - p5_rho(y - get(qc), tau))), by = Date][order(Date)]
  t <- if (nrow(Dd)) nw(as.numeric(Dd[["D"]]), lag = lag) else NA_real_
  list(status = if (is.finite(t)) "ok" else "unmeasured", ref = "q50 - (q90 - q50)", tau = tau, nw_lag = lag, t = t, mean_D = if (nrow(Dd)) mean(Dd$D) else NA_real_,
       n_dates = nrow(Dd), t_minus_t_min = if (is.finite(t)) t - as.numeric(TI$t_min) else NA_real_, per_date = Dd)
}
## 꼬리 증분(판단 T1 C-059 · 철학 P1 R-20261018-008 C-065) = D^σ ∧ D^w ∧ D^H 모두 NW t > t_min(⑮ 와 같은 t) · 하나라도 미측정 = NA
##   D^H = p5_dalt(…, "s_hist") — q̃10_H = q̂50 − s_hist(각 종목 직전 252거래일 자기 5일 순위 수익 하방 폭 순서로 s 재배정 · 예측표 선택 열)
p5_tail_increment <- function(dsig, dwid, dhist, t_min) {
  L <- list(sigma = dsig %||% list(), width = dwid %||% list(), hist = dhist %||% list())
  st <- vapply(L, function(z) as.character(z$status %||% "unmeasured")[1], character(1)); tt <- vapply(L, function(z) suppressWarnings(as.numeric(z$t %||% NA))[1], numeric(1))
  ok <- if (all(st == "ok") && all(is.finite(tt))) all(tt > t_min) else NA
  list(ok = ok, t = as.list(tt), status = as.list(st), t_min = t_min, rule = "D^σ ∧ D^w ∧ D^H 모두 NW t > t_min · 하나라도 미측정 = NA")
}
## σ 10분위 층화 R¹(τ) — 신호일마다 sigma252 십분위(P2R04 p2_liq_deciles 규약) 안에서 Σρ 를 모아 1 − Σρ(y − q̂τ) / Σρ(y − τ)
p5_sigma_strata <- function(QY, TI) {
  tau <- as.numeric(TI$tau); qc <- .p5_qcol(tau)
  X <- QY[is.finite(y) & is.finite(get(qc))]
  X[, sdec := p2_liq_deciles(sigma252, sigma252), by = Date]
  S <- X[!is.na(sdec), .(n = .N, num = sum(p5_rho(y - get(qc), tau)), den = sum(p5_rho(y - tau, tau)), D = mean(p5_rho(y - tau, tau) - p5_rho(y - get(qc), tau))), by = sdec][order(sdec)]
  S[, r1 := 1 - num / den]
  list(status = "ok", tau = tau, n_unknown_sigma = sum(is.na(X$sdec)), per_decile = S[, .(sigma_decile = sdec, n, r1, D)])
}
## ⑩(d) — 재배열 전 교차율(q10_raw > q50_raw 또는 q50_raw > q90_raw) · 재배열 뒤 위반(0 이어야 함) · q̂ 횡단면 표준편차(신호일별)
p5_crossing <- function(Q) {
  P <- Q[, .(cross = mean((q10_raw > q50_raw | q50_raw > q90_raw)[is.finite(q10_raw) & is.finite(q50_raw) & is.finite(q90_raw)]),
             viol = mean((q10 > q50 | q50 > q90)[is.finite(q10) & is.finite(q50) & is.finite(q90)]),
             sd10 = stats::sd(q10, na.rm = TRUE), sd50 = stats::sd(q50, na.rm = TRUE), sd90 = stats::sd(q90, na.rm = TRUE), n = .N), by = Date]
  ok3 <- is.finite(Q$q10_raw) & is.finite(Q$q50_raw) & is.finite(Q$q90_raw)
  list(status = "ok", crossing_pooled = if (any(ok3)) mean((Q$q10_raw > Q$q50_raw | Q$q50_raw > Q$q90_raw)[ok3]) else NA_real_, crossing_by_date = .p5_sm(P$cross),
       rearranged_violation_pooled = mean((Q$q10 > Q$q50 | Q$q50 > Q$q90)[is.finite(Q$q10) & is.finite(Q$q50) & is.finite(Q$q90)]),
       sd_q10 = .p5_sm(P$sd10), sd_q50 = .p5_sm(P$sd50), sd_q90 = .p5_sm(P$sd90), n_dates = nrow(P))
}
## V1 거부(제약형) — 그날 U_d 안 순위(동률 평균)/N ≤ 거부 몫(엔진 .DT_VETO_SHARE) · N = 유한한 q 수 · 결측 = NA
p5_veto <- function(q, share) {
  q <- suppressWarnings(as.numeric(q)); n <- sum(is.finite(q))
  out <- rep(NA, length(q)); if (!n) return(out)
  r <- frank(q, ties.method = "average", na.last = "keep")
  out[is.finite(q)] <- (r[is.finite(q)] / n) <= share
  out
}
## 상위 n(셀 엔진 rf_select_top 동점 규칙 — 점수 내림 · 20일 거래대금(t−1) 내림 · 종목코드 오름 · ok = 후보(유동성 통과 ∧ 점수 유한))
p5_top_flag <- function(score, ok, adv, tk, n) {
  f <- rep(FALSE, length(score)); idx <- which(ok %in% TRUE & is.finite(score))
  if (!length(idx) || !is.finite(n) || n < 1) return(f)
  o <- idx[order(-score[idx], -ifelse(is.finite(adv[idx]), adv[idx], -Inf), tk[idx])]
  f[utils::head(o, as.integer(n))] <- TRUE
  f
}
## 소비 규칙 점수(DESIGN §3.4 · §4 — 예측표로 재현) — Q50 · V1 · V2 · N1 · N2 · S1 · S2
p5_rule_score <- function(rule, q10, q50, s_perm, s_sigma, share) {
  switch(rule,
         Q50 = q50, V2 = q10, N2 = q50 - s_perm, S2 = q50 - s_sigma,
         V1 = ifelse(p5_veto(q10, share) %in% TRUE | !is.finite(q10), NA_real_, q50),
         N1 = ifelse(p5_veto(q50 - s_perm, share) %in% TRUE | !is.finite(q50 - s_perm), NA_real_, q50),
         S1 = ifelse(p5_veto(q50 - s_sigma, share) %in% TRUE | !is.finite(q50 - s_sigma), NA_real_, q50),
         rep(NA_real_, length(q10)))
}
.p5_bins <- function(x, univ, k) {
  u <- suppressWarnings(as.numeric(univ)); u <- u[is.finite(u)]; x <- suppressWarnings(as.numeric(x)); k <- as.integer(k)
  if (is.na(k) || k < 2L || length(u) < k) return(rep(NA_integer_, length(x)))
  bp <- stats::quantile(u, probs = seq_len(k - 1L) / k, names = FALSE, type = 7)
  ifelse(is.finite(x), findInterval(x, bp) + 1L, NA_integer_)
}
## 유동성 패널 — 20일 평균 거래대금(Close × Vol) t−1(셀 엔진 .adv20_l1 · P2R04 p2_liq_panel 과 같은 식 · C10) · 받은 RAW 만으로(보는 창 판 = τ_D 에서 자른 RAW)
p5_liq_from <- function(RAW) {
  L <- RAW[, .(Date, Ticker = as.character(Ticker), Close = as.numeric(Close), Vol = as.numeric(Vol))]
  setorder(L, Ticker, Date)
  L[, adv20_l1 := shift(frollmean(Close * Vol, 20L, align = "right"), 1L), by = Ticker]
  L <- L[, .(Date, Ticker, Vol, adv20_l1)]
  setkey(L, Date, Ticker)
  L
}
## 신호일 패널(기록 입력) — 그날 adv20_l1 · 시총 · 다음 보유월 수익(종가 d → 다음 달 마지막 거래일 종가 · 종가 > 0 행 · 첫 행)
p5_signal_panel <- function(RAW, LIQ, dates) {
  cal <- sort(unique(as.Date(RAW$Date))); dates <- sort(unique(as.Date(dates)))
  me <- tapply(seq_along(cal), format(cal, "%Y-%m"), max)
  nx <- .p5_hold_ym(dates); dn <- cal[as.integer(me[nx])]
  R <- unique(RAW[is.finite(Close) & Close > 0, .(Date, Ticker = as.character(Ticker), Close = as.numeric(Close), Size = as.numeric(Size))], by = c("Ticker", "Date"))
  P0 <- R[Date %in% dates, .(Date, Ticker, c0 = Close, Size)]
  M <- data.table(Date = dates, dn = dn)
  P1 <- R[Date %in% dn[!is.na(dn)], .(dn = Date, Ticker, c1 = Close)]
  S <- merge(merge(P0, M, by = "Date"), P1, by = c("dn", "Ticker"), all.x = TRUE)
  S[, r_next := c1 / c0 - 1]
  S <- merge(S, LIQ[Date %in% dates, .(Date, Ticker, adv20_l1)], by = c("Date", "Ticker"), all.x = TRUE)
  S[, .(Date, Ticker, Size, adv20_l1, r_next, dn)]
}
## 전이 · 귀속 기록(§5.2) — 거부 집합 · V2 상위 n 의 다음 보유월 하위 · 상위 분위 적중(분위 수 = 엔진 .QUINT · 기저 = 1/분위 수) · 깊은 위기 달 ·
##   거부 집합 크기 · 유동성 · 크기 십분위 · σ · 순열 거부 집합 Jaccard · Q50 상위 n 중 거부 몫(V1 전달량) · V1 신호 폭
p5_transfer <- function(Q, SP, prm, deep_ym = character(0)) {
  J <- merge(Q[, .(Date, Ticker, q10, q50, s_perm, s_sigma)], SP[, .(Date, Ticker, Size, adv20_l1, r_next)], by = c("Date", "Ticker"), all.x = TRUE)
  share <- as.numeric(prm$veto_share); nmax <- as.integer(prm$n_max); lmin <- as.numeric(prm$liq_min); nb <- as.integer(prm$n_bins)
  J[, liq := is.finite(adv20_l1) & adv20_l1 >= lmin]
  J[, `:=`(veto = p5_veto(q10, share), veto_sig = p5_veto(q50 - s_sigma, share), veto_perm = p5_veto(q50 - s_perm, share)), by = Date]
  J[, rbin := .p5_bins(r_next, r_next, nb), by = Date]
  J[, `:=`(liq_dec = p2_liq_deciles(adv20_l1, adv20_l1), size_dec = p2_liq_deciles(Size, Size)), by = Date]
  J[, `:=`(v2_top = p5_top_flag(q10, liq, adv20_l1, Ticker, nmax), q50_top = p5_top_flag(q50, liq, adv20_l1, Ticker, nmax)), by = Date]
  J[, hold_ym := .p5_hold_ym(Date)]
  jac <- function(a, b) { u <- sum(a | b); if (u > 0) sum(a & b) / u else NA_real_ }
  hit <- function(sel, bin, k) { s <- sel %in% TRUE & is.finite(bin); if (any(s)) mean(bin[s] == k) else NA_real_ }
  per <- J[, .(N = .N, n_liq = sum(liq), n_veto = sum(veto %in% TRUE), width_v1 = sum(!(veto %in% TRUE)), width_v1_liq = sum(!(veto %in% TRUE) & liq),
               veto_bottom = hit(veto, rbin, 1L), veto_top = hit(veto, rbin, nb), v2_bottom = hit(v2_top, rbin, 1L), v2_top_q = hit(v2_top, rbin, nb),
               veto_liq_dec = mean(liq_dec[veto %in% TRUE], na.rm = TRUE), veto_size_dec = mean(size_dec[veto %in% TRUE], na.rm = TRUE),
               jac_sigma = jac(veto %in% TRUE, veto_sig %in% TRUE), jac_perm = jac(veto %in% TRUE, veto_perm %in% TRUE),
               q50_top_vetoed = if (any(q50_top)) mean(veto[q50_top] %in% TRUE) else NA_real_, hold_ym = hold_ym[1]), by = Date][order(Date)]
  per[, deep := hold_ym %in% deep_ym]
  pool <- function(D, sel, k) { s <- D[[sel]] %in% TRUE & is.finite(D$rbin); if (any(s)) mean(D$rbin[s] == k) else NA_real_ }
  JD <- J[hold_ym %in% deep_ym]
  list(status = "ok", n_bins = nb, base_rate = 1 / nb, n_max = nmax, liq_min = lmin, veto_share = share, n_dates = nrow(per),
       veto = list(bottom = pool(J, "veto", 1L), top = pool(J, "veto", nb), bottom_by_date = .p5_sm(per$veto_bottom), top_by_date = .p5_sm(per$veto_top)),
       v2_top = list(bottom = pool(J, "v2_top", 1L), top = pool(J, "v2_top", nb), bottom_by_date = .p5_sm(per$v2_bottom), top_by_date = .p5_sm(per$v2_top_q)),
       deep = list(months = sort(unique(deep_ym)), n_dates = sum(per$deep), veto_bottom = pool(JD, "veto", 1L), veto_top = pool(JD, "veto", nb),
                   v2_bottom = pool(JD, "v2_top", 1L), v2_top = pool(JD, "v2_top", nb)),
       veto_set = list(size = .p5_sm(per$n_veto), share_of_universe = .p5_sm(per$n_veto / per$N), liquidity_decile = .p5_sm(per$veto_liq_dec),
                       size_decile = .p5_sm(per$veto_size_dec), jaccard_sigma = .p5_sm(per$jac_sigma), jaccard_perm = .p5_sm(per$jac_perm)),
       q50_top_vetoed = c(.p5_sm(per$q50_top_vetoed), list(share_dates_positive = mean(per$q50_top_vetoed > 0, na.rm = TRUE))),
       width_v1 = .p5_sm(per$width_v1), width_v1_liquid = .p5_sm(per$width_v1_liq), per_date = per)
}
## 꼬리 블록(라운드 1회 · 보는 창 판은 τ_D 에서 자른 RAW · 예측표로만) — ⑮ + 기록
p5_tail_block <- function(Q, RAW, YD, TI, nw, prm, deep_ym = character(0), window = "visible") {
  .sf <- function(expr) tryCatch(expr, error = function(e) list(status = "error", why = conditionMessage(e)))
  out <- list(window = window)
  if (is.null(Q) || !nrow(Q)) return(c(out, list(instrument = list(status = "unmeasured", why = "예측표 없음", pass = FALSE))))
  if (!isTRUE(YD$ok)) return(c(out, list(instrument = list(status = "unmeasured", why = paste("표적 정의 대조 실패 —", YD$why %||% "?"), pass = FALSE),
                                         records = list(crossing = .sf(p5_crossing(Q))))))
  lab <- tryCatch(p5_labels(RAW, unique(Q$Date), YD$horizon, has_open = "Open" %in% names(RAW)), error = function(e) NULL)
  if (is.null(lab) || !nrow(lab)) return(c(out, list(instrument = list(status = "unmeasured", why = "라벨 재도출 실패(RAWDATA)", pass = FALSE),
                                                     records = list(crossing = .sf(p5_crossing(Q))))))
  QY <- p5_attach_y(Q, lab, YD$rank01)
  ins <- p5_tail_instrument(QY, TI, nw)
  SP <- tryCatch(p5_signal_panel(RAW, prm$liq, unique(Q$Date)), error = function(e) NULL)
  QY[, hold_ym := .p5_hold_ym(Date)]
  rec <- list(labels = list(n_dates_q = uniqueN(Q$Date), n_dates_labeled = uniqueN(QY$Date), n_rows = nrow(QY), coverage = nrow(QY) / nrow(Q), horizon = YD$horizon),
              r1 = .sf(p5_r1_monthly(QY)), hits = .sf(p5_hits(QY)), d_sigma = .sf(p5_dalt(QY, TI, nw, "s_sigma")), d_perm = .sf(p5_dalt(QY, TI, nw, "s_perm")),
              d_width = .sf(p5_dwidth(QY, TI, nw)), d_hist = .sf(p5_dalt(QY, TI, nw, "s_hist")),
              sigma_strata = .sf(p5_sigma_strata(QY, TI)), crossing = .sf(p5_crossing(Q)),
              deep_month_calibration = .sf(c(list(months = sort(unique(deep_ym))), p5_hits(QY[hold_ym %in% deep_ym]))),
              transfer = if (is.null(SP)) list(status = "unmeasured", why = "신호일 패널 실패") else .sf(p5_transfer(Q, SP, prm, deep_ym)))
  list(window = window, instrument = ins, records = rec, SP = SP)
}
## E2 칸 보유 ↔ 예측표 재현(구성 재현 기록) — 보유일 → 그 이하 마지막 신호일 · 규칙 점수 상위 n(유동성 통과 · 동점 = 거래대금 · 종목코드) · 불일치 사유(동률 · 유동성 · 예측표 밖 · 점수 결측 · 그 밖)
p5_reproduce <- function(Q, SP, H, rule, prm, tau) {
  sig <- sort(unique(Q$Date))
  H <- as.data.table(H)[is.finite(w) & w > 0 & as.Date(date) <= as.Date(tau), .(date = as.Date(date), Ticker = as.character(ticker))]
  ii <- findInterval(as.numeric(H$date), as.numeric(sig)); H[, Date := sig[ifelse(ii > 0L, ii, NA_integer_)]]
  H <- H[!is.na(Date)]
  if (!nrow(H)) return(list(status = "unmeasured", why = "보는 창 보유 없음"))
  J <- merge(Q[Date %in% unique(H$Date), .(Date, Ticker, q10, q50, s_perm, s_sigma)], SP[, .(Date, Ticker, adv20_l1)], by = c("Date", "Ticker"), all.x = TRUE)
  J[, liq := is.finite(adv20_l1) & adv20_l1 >= as.numeric(prm$liq_min)]
  J[, score := p5_rule_score(rule, q10, q50, s_perm, s_sigma, as.numeric(prm$veto_share)), by = Date]
  J[, top := p5_top_flag(score, liq, adv20_l1, Ticker, as.integer(prm$n_max)), by = Date]
  J[, bound := if (any(top)) min(score[top]) else NA_real_, by = Date]
  rows <- lapply(split(H, by = "Date"), function(h) {
    d <- h$Date[1]; Jd <- J[Date == d]; rep_tk <- Jd[top == TRUE, Ticker]; held <- unique(h$Ticker)
    miss_h <- setdiff(held, rep_tk); miss_r <- setdiff(rep_tk, held)
    why <- function(tk) { z <- Jd[match(tk, Jd$Ticker)]
      ifelse(is.na(z$Ticker), "not_in_qpred", ifelse(!is.finite(z$score), "score_na", ifelse(!(z$liq %in% TRUE), "liquidity",
             ifelse(is.finite(z$bound) & abs(z$score - z$bound) < 1e-12, "tie", "other")))) }       # 1e-12 = 부동소수 여유(결정 수치 아님)
    rs <- c(why(miss_h), why(miss_r))
    data.table(Date = d, n_hold = length(held), n_rep = length(rep_tk), n_match = length(intersect(held, rep_tk)),
               match_rate = length(intersect(held, rep_tk)) / max(length(held), length(rep_tk), 1L),
               tie = sum(rs == "tie"), liquidity = sum(rs == "liquidity"), not_in_qpred = sum(rs == "not_in_qpred"), score_na = sum(rs == "score_na"), other = sum(rs == "other"))
  })
  P <- rbindlist(rows)
  list(status = "ok", rule = rule, n_dates = nrow(P), match_rate = .p5_sm(P$match_rate), share_dates_exact = mean(P$n_match == P$n_hold & P$n_hold == P$n_rep),
       mismatch = list(tie = sum(P$tie), liquidity = sum(P$liquidity), not_in_qpred = sum(P$not_in_qpred), score_na = sum(P$score_na), other = sum(P$other)), per_date = P)
}
## 예측 비대칭(Kelley 십분위 왜도 (q̂90 + q̂10 − 2q̂50) / (q̂90 − q̂10)) 의 보유 가중 평균(보유일 → 신호일 · 보는 창)
p5_kelley_hold <- function(Q, H, tau) {
  K <- Q[, .(Date, Ticker, kel = ifelse(q90 - q10 > 0, (q90 + q10 - 2 * q50) / (q90 - q10), NA_real_))]
  sig <- sort(unique(K$Date))
  H <- as.data.table(H)[is.finite(w) & w > 0 & as.Date(date) <= as.Date(tau), .(date = as.Date(date), Ticker = as.character(ticker), w)]
  ii <- findInterval(as.numeric(H$date), as.numeric(sig)); H[, Date := sig[ifelse(ii > 0L, ii, NA_integer_)]]
  J <- merge(H[!is.na(Date)], K, by = c("Date", "Ticker"), all.x = TRUE)
  if (!nrow(J)) return(list(status = "unmeasured"))
  P <- J[is.finite(kel), .(k = sum(w * kel) / sum(w), n = .N), by = date]
  list(status = "ok", n_dates = nrow(P), mean = if (nrow(P)) mean(P$k) else NA_real_, median = if (nrow(P)) stats::median(P$k) else NA_real_,
       n_names_without_q = sum(!is.finite(J$kel)))
}
## Dimson β(Dimson 1979 JFE 7(2) — 일수익 r_t 를 시장 m_{t−1} · m_t · m_{t+1} 에 회귀한 계수의 합) · k_D = β_D(변형) / β_D(RX0)
p5_dimson_beta <- function(r, m) {
  r <- suppressWarnings(as.numeric(r)); m <- suppressWarnings(as.numeric(m)); n <- length(r)
  if (n != length(m) || n < 10L) return(list(beta = NA_real_, n = n))
  X <- cbind(1, c(NA, m[-n]), m, c(m[-1L], NA))
  ok <- stats::complete.cases(X) & is.finite(r)
  if (sum(ok) < 10L) return(list(beta = NA_real_, n = sum(ok)))
  b <- stats::coef(stats::lm.fit(X[ok, , drop = FALSE], r[ok]))
  list(beta = unname(sum(b[2:4])), coef = list(lag = unname(b[2]), same = unname(b[3]), lead = unname(b[4])), n = sum(ok))
}
p5_dimson_from <- function(E, dir, tau) {
  rd <- .dp_read(E, dir)
  D <- merge(rd$pr[date <= as.Date(tau), .(date, r = as.numeric(ret_net))], rd$br[date <= as.Date(tau), .(date, m = as.numeric(benchmark_ret))], by = "date")[order(date)]
  p5_dimson_beta(D$r, D$m)
}
## 판정 여유(철학 Superfan P2 R-20261018-006 N-⑤ — 새 문턱 없음 · '경계' 판정 없음 · 양수 = 충족) — ③ · ④ 위기별 (사본 − tol) − 변형 · ⑭ 분해 차 · ⑤ −Δ · ⑮ t − t_min
p5_margins <- function(RL, tail, maj, tol) {
  pc <- function(J) { J <- as.data.table(J %||% data.table()); if (!nrow(J) || !all(c("k", "m", "r") %in% names(J))) return(data.table()) else J[, .(crisis = k, margin = (r - tol) - m)] }
  sh <- function(x) suppressWarnings(as.numeric(x %||% NA))[1] - as.numeric(maj)
  dc <- RL$selection$decomposition$per_crisis
  list(rule = "여유 = 값 − 문턱(양수 = 충족 · 새 문턱 없음 · 코드는 '경계'를 판정하지 않는다)",
       beta_deep = list(per_crisis = pc(RL$beta_deep$per_crisis), share_minus_majority = sh(RL$beta_deep$share)),
       fast = list(per_crisis = pc(RL$fast$per_crisis), share_minus_majority = sh(RL$fast$share)),
       selection_decomp = list(per_crisis = if (length(dc) && nrow(as.data.table(dc))) as.data.table(dc)[, .(crisis = peak_date, margin = sv - sr)] else data.table(),
                               share_minus_majority = sh(RL$selection$decomposition$share)),
       beta_ratio = list(margin = -suppressWarnings(as.numeric(RL$beta_asym$delta %||% NA))[1], delta = RL$beta_asym$delta %||% NA_real_),
       tail = list(margin = tail$margin %||% NA_real_, t = tail$t %||% NA_real_, t_min = tail$t_min %||% NA_real_))
}

## 같은 추첨 판독(철학 Superfan P1 R-20261018-008 C-063 · 기록 · 판정 아님) — Q50 칸(같은 분위 모델의 중앙값 순위)을 기준으로 다시 잰다:
##   k' = β(변형) / β(Q50)(RX0 β 짝과 같은 계산 경로 · p2_beta_plan) · 사본 = Q50 수익 × k'(k' ≥ 1 = Q50 그대로) · 깊은 위기 · 빠른 급락 승패 · ⑤ Δ · ⑥ 강세 · ⑦ 증분 α 를 V − Q50 로
p5_same_draw_plan <- function(PM, PQ, PRX) {
  bv <- rk_getf(PM, "behavior.stats.beta"); bq <- rk_getf(PQ, "behavior.stats.beta"); br <- rk_getf(PRX, "behavior.stats.beta")
  p <- p2_beta_plan(bv, bq)
  list(k = p$k, mode = p$mode, comparator = switch(p$mode, rx0 = "Q50(k' ≥ 1)", scaled = "Q50 × k'", "미측정"),
       beta_variant = bv, beta_q50 = bq, k_rx0 = if (is.finite(br) && br > 0) bv / br else NA_real_)
}
p5_same_draw_core <- function(PM, PQ, PQB, deep, fast_keys, tol, maj, ratio, uc_floor) {
  g <- rk_getf; emp <- list(n_pair = 0L, share = NA_real_)
  crm <- PM$behavior$crises %||% list(); cqb <- if (!is.null(PQB)) PQB$behavior$crises %||% list() else list()
  d3 <- if (!is.null(PQB)) p2_crisis_majority(crm, cqb, tol, "dd_capture", subset = deep) else emp
  d4 <- if (!is.null(PQB)) p2_crisis_majority(crm, cqb, tol, "dd_capture", subset = fast_keys) else emp
  r5 <- p2_beta_ratio_delta(g(PM, "behavior.stats.beta_down"), g(PM, "behavior.stats.beta_up"), g(PQ, "behavior.stats.beta_down"), g(PQ, "behavior.stats.beta_up"))
  bs <- p2_bull_segments(PM$behavior$bull_phases %||% list(), PQ$behavior$bull_phases %||% list(), ratio, 2L)
  ucm <- g(PM, "behavior.summary.bull_up_capture_median")
  list(deep = list(n_pair = d3$n_pair, share = d3$share, majority = if (d3$n_pair >= 2L) p2_maj(d3$share, maj) else NA, per_crisis = d3$per_crisis),
       fast = list(n_pair = d4$n_pair, share = d4$share, majority = if (d4$n_pair >= 2L) p2_maj(d4$share, maj) else NA, per_crisis = d4$per_crisis),
       beta_ratio = r5, bull = list(n_pair = bs$n_pair, share = bs$share, uc_median = ucm, uc_median_q50 = g(PQ, "behavior.summary.bull_up_capture_median"),
                                    ok = p2_maj(bs$share, maj) && isTRUE(ucm >= uc_floor), per_phase = bs$per_phase))
}
## 선택 꼬리표(사전 고정) — 선택된 규칙의 같은 추첨 판독 깊은 위기 β 짝 승리가 과반 미만(또는 미측정)이면 '같은 추첨 미확인 — P4 · A 후보 전 도훈 확인'
p5_same_draw_tag <- function(sel, OUT) {
  if (!length(sel)) return(list(status = "no_selection", tag = NA_character_))
  rk <- sel[[1]]$device; xs <- Filter(function(x) identical(x$device, rk), OUT)
  sd <- lapply(xs, function(x) x$same_draw %||% list(status = "unmeasured"))
  okc <- vapply(sd, function(s) identical(s$status, "ok"), logical(1))
  if (!any(okc)) return(list(status = "unmeasured", rule = rk, tag = "같은 추첨 미측정 — P4 · A 후보 전 도훈 확인"))
  mj <- vapply(sd[okc], function(s) isTRUE(s$deep$majority), logical(1))
  list(status = "ok", rule = rk, cells = vapply(xs[okc], function(x) as.character(x$cell %||% NA_character_), character(1)), deep_majority = mj,
       tag = if (all(mj)) NA_character_ else "같은 추첨 미확인 — P4 · A 후보 전 도훈 확인")
}

## ── P2R05 순수 도우미 ③ — 위기 유형 분류 · 진단 읽기 · 결론 이름 ─────────────────────────────────────────────────
## 위기 유형 분류(crisis_type_classify.json · Q) — type ∈ systemic · dispersed · 그 밖 = unclassified · 문턱 = rule 의 'peak >= <날짜>' 위기들의 rho_W 중앙값(파일 값으로 재계산) ·
##   경계 = |rho_W − 문턱| < eps · md5 ↔ 사전등록 design_inputs 핀(다르면 '분류 판본 다름' · 없으면 '분류 핀 없음' — 평가 중단 아님) · 파일 없음 = 미분류
p5_load_crisis_types <- function(root, pre, rel = P2R05_CRISIS_TYPE_NOTE, eps = P2R05_BOUNDARY_EPS) {
  p <- file.path(root, rel); pin <- p5_find_pin(pre$design_inputs, rel)
  if (!file.exists(p)) return(list(status = "unclassified", why = "분류 파일 없음 — 미분류(실패 아님)", path = rel, pins = pin))
  md5 <- p5_md5(p)
  tag <- if (!length(pin)) "분류 핀 없음(사전등록 design_inputs)" else if (length(pin) > 1L) "분류 핀 여럿(사전등록 design_inputs)" else if (!identical(pin, md5)) "분류 판본 다름" else NA_character_
  J <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(J) || !length(J$crises)) return(list(status = "unclassified", why = "분류 파일 판독 실패 — 미분류", path = rel, md5 = md5, pin_tag = tag))
  C <- rbindlist(lapply(J$crises, function(z) data.table(k = as.character(z$crisis %||% NA), type = as.character(z$type %||% NA), rho_W = suppressWarnings(as.numeric(z$rho_W %||% NA)),
                                                         window = as.character(z$window %||% NA))), fill = TRUE)
  C[!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{4}-[0-9]{2}-[0-9]{2}$", k) | !(type %in% c("systemic", "dispersed")), type := "unclassified"]
  rule <- as.character(J$rule %||% "")
  fm <- regmatches(rule, regexpr("peak >= [0-9]{4}-[0-9]{2}-[0-9]{2}", rule)); from <- if (length(fm)) as.Date(sub("peak >= ", "", fm)) else as.Date(NA)
  sv <- regmatches(rule, regexpr("= [0-9]+\\.[0-9]+", rule)); stated <- if (length(sv)) as.numeric(sub("= ", "", sv)) else NA_real_
  C[, peak := suppressWarnings(as.Date(substr(k, 1, 10), format = "%Y-%m-%d"))]
  th <- if (!is.na(from)) stats::median(C[!is.na(peak) & peak >= from & is.finite(rho_W), rho_W]) else NA_real_
  C[, boundary := is.finite(th) & is.finite(rho_W) & abs(rho_W - th) < eps]
  dig <- if (length(sv)) nchar(sub("^= [0-9]+\\.", "", sv)) else NA_integer_
  list(status = "ok", path = rel, md5 = md5, pins = pin, pin_tag = tag, rule = rule, threshold = th, threshold_from = if (is.na(from)) NA_character_ else format(from),
       threshold_stated = stated, threshold_stated_matches = if (is.finite(stated) && is.finite(th) && !is.na(dig)) isTRUE(round(th, dig) == stated) else NA,
       boundary_status = if (is.finite(th)) "ok" else "unmeasured(문턱 재계산 불가 — rule 에 'peak >= <날짜>' 없음)", boundary_eps = eps,
       falsification = J$falsification %||% NULL, classes = C[, .(k, type, boundary, rho_W)])
}
## 시작 시점 분류 기록(onset_state_classify.json table — from_top · 결론 이름 아님 · '상태 미전환 최대 하락 위기' = state_turn_classify.md 와 다른 기록) — 판정 창 행만 · 유형 = from_top / not_from_top
p5_load_onset <- function(root, pre, rel = P2R05_ONSET_NOTE) {
  p <- file.path(root, rel); pin <- p5_find_pin(pre$design_inputs, rel)
  if (!file.exists(p)) return(list(status = "unclassified", why = "시작 시점 분류 파일 없음", path = rel, pins = pin))
  J <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(J) || !length(J$table)) return(list(status = "unclassified", why = "시작 시점 분류 판독 실패", path = rel))
  C <- rbindlist(lapply(J$table, function(z) data.table(k = sub(" → ", " ", as.character(z$crisis %||% NA), fixed = TRUE),
                                                       from_top = if (is.null(z$from_top)) NA else as.logical(z$from_top), window = as.character(z$window %||% NA))), fill = TRUE)
  C <- C[window %in% "판정 창" & !is.na(from_top)]
  vft <- sub(" → ", " ", as.character(unlist(J$visible_from_top %||% list())), fixed = TRUE)
  md5 <- p5_md5(p)
  list(status = "ok", path = rel, md5 = md5, pins = pin, pin_tag = if (!length(pin)) "분류 핀 없음(사전등록 design_inputs)" else if (!identical(pin[1], md5) || length(pin) > 1L) "분류 판본 다름" else NA_character_,
       visible_from_top_matches_table = setequal(vft, C[from_top == TRUE, k]),
       classes = C[, .(k, type = ifelse(from_top, "from_top", "not_from_top"), boundary = FALSE)])
}
## 칸 1개의 위기 유형별 β 짝 승패(기록 · 판정 아님) — 모든 짝 위기(beta_all) · 경계 포함 판(쓰인 유형대로) · 경계 분리 판 · 깊은 위기 부분
##   같은 줄에 ⑤ Δ(칸 단위) · ⑭ 분해(깊은 위기별 변형 − RX0 선택 항 > 0)를 함께 싣는다(철학 P1 R-20261018-008 C-067)
p5_crisis_type_record <- function(pc, CL, deep_keys = character(0), tol = 0, decomp = NULL, beta_delta = NA_real_) {
  if (is.null(CL) || !identical(CL$status, "ok")) return(list(status = "unclassified", why = CL$why %||% "미분류", beta_ratio_delta = beta_delta))
  P <- as.data.table(pc %||% data.table())
  if (!nrow(P) || !all(c("k", "m", "r") %in% names(P))) return(list(status = "unmeasured", why = "β 짝 위기 표 없음(β 사본 미측정)", beta_ratio_delta = beta_delta))
  P <- P[is.finite(m) & is.finite(r)][, win := m < r - tol]
  X <- merge(P, CL$classes, by = "k", all.x = TRUE)
  X[is.na(type), type := "unclassified"][is.na(boundary), boundary := FALSE]
  X[, is_deep := k %in% deep_keys]
  DC <- as.data.table(decomp %||% data.table())
  X[, selection_better := if (nrow(DC) && all(c("peak_date", "sv", "sr") %in% names(DC))) { mi <- match(substr(k, 1, 10), as.character(DC$peak_date)); ifelse(is.na(mi), NA, DC$sv[mi] - DC$sr[mi] > 0) } else NA]
  agg <- function(D) if (!nrow(D)) data.table(type = character(0), n = integer(0), n_win = integer(0), wins = character(0), n_selection_better = integer(0)) else
    D[, .(n = .N, n_win = sum(win), wins = paste(k[win], collapse = " | "), n_selection_better = sum(selection_better %in% TRUE)), by = type][order(type)]
  S <- copy(X)[boundary %in% TRUE, type := "boundary"]
  list(status = "ok", tag = CL$pin_tag %||% NA_character_, tol = tol, beta_ratio_delta = beta_delta,
       as_written = agg(X), boundary_separate = agg(S), deep_as_written = agg(X[is_deep == TRUE]), deep_boundary_separate = agg(S[is_deep == TRUE]),
       per_crisis = X[, .(crisis = k, type, boundary, deep = is_deep, dd_capture = m, dd_capture_beta_copy = r, beats_beta_copy = win, selection_better)])
}
## P2 정지 보고 재료(철학 Superfan P1 R-20261018-008 C-064 · 4요소 · 판정 아님) — (1) 레버 × 위기 유형 승패 지도(이 라운드 칸 · 유형 = crisis_type_classify 경계 분리 판 +
##   상태 미전환 · 같은 줄에 ⑤ Δ · ⑭ — C-067) (2) 철학 머리 문장 성적표(위기 하락 포착 · 강세 참여 ≥ uc_floor · 꾸준함 = 롤링 통과) · 미측정 형태 목록 (3) P4 함의 1줄 자리
##   (4) 철학 P4 첨부 자리 + 보유 겹침(V–RX0 · V–Q50 · Q50–RX0 · RX0–RX0S — C-068) · 위기 보유 유동성 십분위(V · S · Q50 · RX0 나란히 — C-069) · ③ 미통과 Sharpe 상승 = 평시 변동성 축소(C-070)
P2R05_UNMEASURED_FORMS <- c("주간 집행 — 셀 엔진 주간 신호 미구현(MC4 하네스 ✅ · 셀 엔진 미구현)",
                            "위기 진행 중 as-of 결합 — 상관 상태로는 반증(_design_notes/crisis_type_asof — 진행 중 ρ̄20 백분위가 두 묶음을 못 가름) · 시작 시점 as-of 도 못 가름(crisis_type_classify)",
                            "다른 기저 엔진 — 재료 큐")   # 문구 = Q 10-18 통합 정렬 4
p5_pause_report <- function(OUT, DOUT, uc_floor, lqa = NULL) {
  AC <- c(OUT, DOUT)
  fr <- function(T, ty) { if (!is.data.frame(T) || !nrow(T)) return(NA_character_); z <- as.data.table(T)[type == ty]; if (nrow(z)) sprintf("%d/%d", z$n_win, z$n) else "0/0" }
  lever <- rbindlist(lapply(AC, function(x) {
    ct <- x$record$crisis_type; okc <- identical(ct$status, "ok"); su <- as.data.table(x$record$state_unturned_max_drop %||% data.table())
    data.table(cell = x$cell %||% NA_character_, role = x$role %||% NA_character_, engine = x$engine %||% NA_character_, device = x$device %||% NA_character_,
               tested = isTRUE(x$tested), rules_computed = isTRUE(x$rules_computed),
               systemic = if (okc) fr(ct$boundary_separate, "systemic") else (ct$status %||% NA_character_), dispersed = if (okc) fr(ct$boundary_separate, "dispersed") else NA_character_,
               boundary = if (okc) fr(ct$boundary_separate, "boundary") else NA_character_, systemic_as_written = if (okc) fr(ct$as_written, "systemic") else NA_character_,
               state_unturned = if (nrow(su) && "beats_beta_copy" %in% names(su)) sprintf("%d/%d", sum(su$beats_beta_copy %in% TRUE), sum(!is.na(su$beats_beta_copy))) else NA_character_,
               beta_deep_share = suppressWarnings(as.numeric(x[["rules"]]$beta_deep$share %||% NA))[1], beta_ratio_delta = suppressWarnings(as.numeric(x[["rules"]]$beta_asym$delta %||% NA))[1],
               selection_status = x[["rules"]]$selection$status %||% NA_character_, selection_ok = isTRUE(x[["rules"]]$selection$ok),
               sharpe_up_without_r3 = isTRUE(x$rules_computed) && !isTRUE(x$flags$r3) && isTRUE(x$flags$sharpe_up))
  }), fill = TRUE)
  vx <- Filter(function(x) isTRUE(x$device %in% names(P2R05_RULES)), OUT)
  num <- function(v, k) suppressWarnings(as.numeric(if (is.null(v)) NA else v[k]))[1]
  score <- rbindlist(lapply(vx, function(x) data.table(cell = x$cell, engine = x$engine, rule = x$device, tested = isTRUE(x$tested),
    crisis_dd_capture_median = num(x$record$crisis_dd_capture_median, "variant"), crisis_dd_capture_median_rx0 = num(x$record$crisis_dd_capture_median, "rx0"),
    bull_uc_median = suppressWarnings(as.numeric(x[["rules"]]$bull$uc_median %||% NA))[1], bull_uc_median_rx0 = suppressWarnings(as.numeric(x[["rules"]]$bull$uc_median_rx0 %||% NA))[1],
    uc_floor = uc_floor, bull_participation_meets_floor = isTRUE(x[["rules"]]$bull$uc_median >= uc_floor),
    steadiness_rolling_pass_life = suppressWarnings(as.numeric(x$record$rolling$pass_life %||% NA))[1], steadiness_rolling_pass_recent = suppressWarnings(as.numeric(x$record$rolling$pass_recent %||% NA))[1])), fill = TRUE)
  ovs <- function(o) if (is.list(o) && length(o)) o[intersect(names(o), c("status", "n_dates", "n_differ", "share_differ", "name_overlap_mean", "name_overlap_min", "weight_overlap_mean"))] else list(status = "absent")
  pick <- function(L, dev) Filter(function(x) identical(x$device, dev), L)
  hol <- list(variant_rx0 = setNames(lapply(vx, function(x) ovs(x$holdings_overlap)), vapply(vx, function(x) x$cell, "")),
              variant_q50 = setNames(lapply(vx, function(x) ovs(x$same_draw$holdings_overlap_vs_q50 %||% x$delivery_q50)), vapply(vx, function(x) x$cell, "")),
              q50_rx0 = setNames(lapply(pick(DOUT, "Q50"), function(x) ovs(x$holdings_overlap)), vapply(pick(DOUT, "Q50"), function(x) x$cell, "")),
              rx0_rx0s = setNames(lapply(pick(DOUT, "RX0S"), function(x) ovs(x$holdings_overlap)), vapply(pick(DOUT, "RX0S"), function(x) x$cell, "")))
  lq <- rbindlist(lapply(Filter(function(x) isTRUE(x$device %in% c(names(P2R05_RULES), "Q50", "S1", "S2")), AC), function(x)
    data.table(cell = x$cell, engine = x$engine, device = x$device, deep_liquidity_decile = suppressWarnings(as.numeric(x$liquidity$variant$deep_mean_decile %||% NA))[1],
               deep_liquidity_decile_rx0 = suppressWarnings(as.numeric(x$liquidity$rx0$deep_mean_decile %||% NA))[1], status = x$liquidity$status %||% (if (is.null(x$liquidity)) "absent" else "ok"))), fill = TRUE)
  ## 유동성 구간별 위기 손익 귀속(철학 P4 C-076) — 칸 × 위기 3분위 기여 나란히 + 판정 칸의 저 분위 개선 몫
  lqt <- if (is.null(lqa)) list(status = "absent") else setNames(lapply(names(lqa), function(e) { L <- lqa[[e]]
    if (!is.list(L) || !identical(L$status, "ok")) return(list(status = L$status %||% "unmeasured", why = L$why %||% NA_character_, tag = "유동성 귀속 미측정"))
    list(status = "ok", table = L$table, improvement = rbindlist(lapply(names(L$improvement), function(dv) { z <- L$improvement[[dv]]
      data.table(device = dv, status = z$status %||% "unmeasured", n_improvement = z$n_improvement %||% NA_integer_, n_low_attributed = z$n_low_attributed %||% NA_integer_,
                 tags = paste(z$tags %||% character(0), collapse = " · ")) }), fill = TRUE)) }), names(lqa))
  list(status = "ok", elements = c("lever_map", "philosophy_scorecard", "p4_implication", "philosophy_p4"),
       lever_map = lever, philosophy_scorecard = list(table = score, unmeasured_forms = P2R05_UNMEASURED_FORMS),
       p4_implication = NA_character_, philosophy_p4 = NA_character_, holdings_overlap = hol, liquidity_deciles = lq, liquidity_terciles = lqt,
       note = "P2 정지 보고 재료(판정 아님) — (3) P4 함의 1줄 · (4) 철학 P4 첨부는 자리만(Q · 철학 Superfan 이 채운다)")
}
## 유동성 구간별 위기 손익 귀속(철학 Superfan P4 C-20261018-076 · 기록 · 판정 아님 — 소형주 · 저유동 착시 4라운드 연속 미측정) —
##   깊은 위기 · 빠른 급락 (고점, 저점] 마다 보유 종목을 위기 고점일의 20일 평균 거래대금(t−1 = p5_liq_from 의 adv20_l1 · C10 — 고점일 당일 거래대금 제외)으로
##   그날 위생 멤버 유니버스(HYG ∧ adv20_l1 > 0 — P2R04 유동성 십분위 기록과 같은 유니버스 정의) 3분위(저 · 중 · 고 · 경계 = 유니버스 1/3 · 2/3 분위 type 7)에 놓고,
##   구간 포트폴리오 손익(보유 비중 × 일수익의 구간 합 — 진단 패킷 위기 귀속과 같은 '일간 기여의 산술합')을 분위별 기여로 나눈다.
##   보유 비중 = 측정 산출물 04_holdings 그대로(tilt_attribution ta_read_holdings) → 계약 일별 시작 비중(.ta_daily_weights — 집행 규약 · buy-and-hold 드리프트 그대로) ·
##   일수익 = 보는 창 RAWDATA Ret(결측 = 0 · 창 안 유한 수익 없는 종목 제외 — 하네스 Return.portfolio 열 규약).
##   단정: 분위별 기여 합 = 구간 재구성 손익(항등) · 재구성 손익 = 계약 03 ret_gross 의 같은 구간 합(|차| < P2R05_LIQ_RECON_TOL) — 불일치 · 결손 = '유동성 귀속 미측정'(의무 꼬리표 · 실패 아님)
P2R05_LIQ_TERCILES <- c("low", "mid", "high")                                    # 3분위(Q 지시 10-18 · 철학 P4 C-076 '저 · 중 · 고')
P2R05_LIQ_CELLS <- c("V1", "V2", "S1", "S2", "Q50", "RX0", "LV")                 # 나란히 칸(철학 P4 C-076 · 구성에 있는 칸만)
P2R05_LIQ_RECON_TOL <- 1e-10   # 재구성 대조 여유 = 진단 패킷 벤치 항등식 문턱 재사용(diagnosis_packet.R .dp_exposure 'gap > 1e-10' · 부동소수 여유 · 결정 수치 아님)
## 수익 상태(최소 — .ta_daily_weights 가 읽는 cal · tickers · R · R0 만 · ta_build_state 의 R 적재와 같은 식) — RAW = 보는 창(τ_D 에서 자른) · 달력 = RAW 전 종목 거래일(하네스 all_dates)
p5_ret_state <- function(RAW, tickers, from, cal = NULL) {
  if (is.null(cal)) cal <- sort(unique(as.Date(RAW$Date)))
  cal <- cal[cal >= as.Date(from)]
  tk <- sort(unique(as.character(tickers)))
  P <- RAW[Date >= as.Date(from) & Ticker %in% tk, .(Date, Ticker, Ret)]
  R <- matrix(NA_real_, length(cal), length(tk))
  pos <- cbind(match(P$Date, cal), match(P$Ticker, tk)); okp <- !is.na(pos[, 1]) & !is.na(pos[, 2])
  R[pos[okp, , drop = FALSE]] <- as.numeric(P$Ret[okp]); R[!is.finite(R)] <- NA_real_
  R0 <- R; R0[is.na(R0)] <- 0
  list(cal = cal, tickers = tk, R = R, R0 = R0)
}
## 위기 1개 — C = 구간 (date, Ticker, contrib) · retg = 계약 03 의 같은 구간 (date, ret_gross) · adv_held = 고점일 adv20_l1(이름 붙은 벡터) · adv_univ = 고점일 유니버스 adv20_l1
p5_liq_tercile_core <- function(C, retg, adv_held, adv_univ, tol = P2R05_LIQ_RECON_TOL) {
  C <- as.data.table(C); retg <- as.data.table(retg)
  if (!nrow(C)) return(list(status = "unmeasured", why = "구간 보유 기여 없음"))
  k <- length(P2R05_LIQ_TERCILES); u <- suppressWarnings(as.numeric(adv_univ)); u <- u[is.finite(u)]
  TT <- C[, .(contrib = sum(contrib), days_held = .N), by = Ticker]
  TT[, adv20_l1 := unname(adv_held[Ticker])]
  b <- .p5_bins(TT$adv20_l1, u, k)
  TT[, tercile := P2R05_LIQ_TERCILES[b]][is.na(tercile), tercile := "unknown"]
  BYT <- TT[, .(contrib = sum(contrib), n_names = .N), by = tercile][order(match(tercile, c(P2R05_LIQ_TERCILES, "unknown")))]
  total <- sum(C$contrib); hr <- nrow(retg) > 0L && "ret_gross" %in% names(retg)
  cs <- if (hr) sum(retg$ret_gross) else NA_real_; gap <- cs - total
  list(status = "ok", total = total, sum_terciles = sum(BYT$contrib), by_tercile = BYT, names = TT[order(tercile, Ticker)],
       contract_sum = cs, recon_gap = gap, recon_ok = is.finite(gap) && abs(gap) < tol, recon_tol = tol,
       contract_cum = if (hr) prod(1 + retg$ret_gross) - 1 else NA_real_, n_days = uniqueN(C$date), n_contract_days = nrow(retg), n_names = nrow(TT),
       n_universe = length(u), breaks = if (length(u) >= k) stats::quantile(u, probs = seq_len(k - 1L) / k, names = FALSE, type = 7) else NA_real_)
}
## 칸 1개 — 측정 산출물(형제 close_t1 판 우선 = ta_resolve_artifact) · CRK = data.table(k, peak, trough, deep, fast) · liq = p5_liq_from(보는 창 RAW) · hyg_of(d) = 그날 위생 멤버
p5_liq_tercile_cell <- function(E, dir, CRK, RAW, liq, hyg_of, tau, cal = NULL) {
  src <- E$ta_resolve_artifact(dir)
  H <- E$ta_read_holdings(src$dir)[Exec <= as.Date(tau) & is.finite(Weight) & Weight != 0]
  if (!nrow(H)) return(list(status = "unmeasured", why = "보는 창 보유 없음"))
  st <- p5_ret_state(RAW, H$Ticker, min(H$Exec), cal)
  WL <- E$.ta_daily_weights(H, st, src$exec_price)
  WL[, `:=`(date = st$cal[di], Ticker = st$tickers[ti], r = st$R0[cbind(di, ti)])][, contrib := w * r]
  PR <- fread(file.path(src$dir, "03_period_returns.csv")); PR[, date := as.Date(date)]
  per <- setNames(lapply(seq_len(nrow(CRK)), function(i) tryCatch({
    p0 <- as.Date(CRK$peak[i]); t0 <- as.Date(CRK$trough[i])
    C <- WL[date > p0 & date <= t0, .(date, Ticker, contrib)]
    rg <- if ("ret_gross" %in% names(PR)) PR[date > p0 & date <= t0 & date <= as.Date(tau), .(date, ret_gross)] else data.table()
    L0 <- liq[Date == p0]; hy <- hyg_of(p0)
    c(list(peak = format(p0), trough = format(t0), asof = format(p0), deep = isTRUE(CRK$deep[i]), fast = isTRUE(CRK$fast[i])),
      p5_liq_tercile_core(C, rg, setNames(L0$adv20_l1, as.character(L0$Ticker)), L0[Ticker %in% hy & is.finite(adv20_l1) & adv20_l1 > 0]$adv20_l1))
  }, error = function(e) list(status = "unmeasured", why = conditionMessage(e)))), CRK$k)
  list(status = "ok", exec_price = src$exec_price, basis = src$basis, per_crisis = per)
}
## 칸 대 RX0(같은 구성 · 같은 위기) — 위기마다 개선 = 구간 손익(칸) − 구간 손익(RX0) · 저 분위 개선 몫 = (저 분위 기여(칸) − 저 분위 기여(RX0)) / 개선 ·
##   개선 > 0 ∧ 몫 > majority_share(과반 — P2R04 상수)이면 그 위기 '저유동 귀속' · 재구성 대조 불일치 위기는 몫을 읽지 않는다(미측정)
p5_liq_improvement <- function(rv, rr, maj) {
  ks <- intersect(names(rv %||% list()), names(rr %||% list()))
  lo <- function(x) { z <- as.data.table(x$by_tercile %||% data.table()); z <- if (nrow(z)) z[tercile == "low"]$contrib else numeric(0); if (length(z)) z[1] else 0 }
  P <- rbindlist(lapply(ks, function(k) { a <- rv[[k]]; b <- rr[[k]]
    fl <- list(deep = isTRUE(a$deep %||% b$deep), fast = isTRUE(a$fast %||% b$fast))
    if (!identical(a$status, "ok") || !identical(b$status, "ok"))
      return(data.table(crisis = k, deep = fl$deep, fast = fl$fast, total = NA_real_, total_rx0 = NA_real_, improvement = NA_real_, low_improvement = NA_real_,
                        low_share = NA_real_, low_attributed = NA, status = "unmeasured", why = paste(c(a$why, b$why), collapse = " · ")))
    rec <- isTRUE(a$recon_ok) && isTRUE(b$recon_ok)
    imp <- a$total - b$total; li <- lo(a) - lo(b); sh <- if (rec && is.finite(imp) && imp > 0) li / imp else NA_real_
    data.table(crisis = k, deep = fl$deep, fast = fl$fast, total = a$total, total_rx0 = b$total, improvement = imp, low_improvement = li, low_share = sh,
               low_attributed = if (is.finite(sh)) sh > as.numeric(maj) else NA, status = if (rec) "ok" else "recon_mismatch", why = NA_character_) }), fill = TRUE)
  if (!nrow(P)) return(list(status = "unmeasured", tags = "유동성 귀속 미측정", per_crisis = data.table(), why = "짝 위기 없음(칸 또는 RX0 귀속 없음)"))
  ni <- sum(P$status == "ok" & is.finite(P$improvement) & P$improvement > 0); nl <- sum(P$low_attributed %in% TRUE)
  list(status = "ok", per_crisis = P, n_crisis = nrow(P), n_measured = sum(P$status == "ok"), n_improvement = ni, n_low_attributed = nl, majority_share = as.numeric(maj),
       tags = c(if (any(P$status != "ok")) sprintf("유동성 귀속 미측정(일부 위기 %d/%d — 재구성 대조 불일치 · 결손)", sum(P$status != "ok"), nrow(P)),
                if (nl > 0L) sprintf("저유동 귀속(위기 개선의 과반이 저유동 3분위 기여 — %d/%d 개선 위기)", nl, ni)))
}
## 나란히 표(칸 × 위기 · 분위 기여 · 재구성 대조) — 보고 · 정지 보고 재료
p5_liq_table <- function(per, eng) rbindlist(lapply(names(per), function(cp) { z <- per[[cp]]
  if (!identical(z$status, "ok")) return(data.table(engine = eng, device = cp, cell = z$cell %||% NA_character_, crisis = NA_character_, status = z$status %||% "unmeasured", why = z$why %||% NA_character_))
  rbindlist(lapply(names(z$per_crisis), function(k) { a <- z$per_crisis[[k]]
    if (!identical(a$status, "ok")) return(data.table(engine = eng, device = cp, cell = z$cell %||% NA_character_, crisis = k, status = a$status %||% "unmeasured", why = a$why %||% NA_character_))
    B <- as.data.table(a$by_tercile)
    g <- function(t) { v <- B[tercile == t]$contrib; if (length(v)) v[1] else 0 }; n <- function(t) { v <- B[tercile == t]$n_names; if (length(v)) as.integer(v[1]) else 0L }
    data.table(engine = eng, device = cp, cell = z$cell %||% NA_character_, crisis = k, deep = a$deep, fast = a$fast, status = "ok", total = a$total,
               low = g("low"), mid = g("mid"), high = g("high"), unknown = g("unknown"), n_low = n("low"), n_mid = n("mid"), n_high = n("high"), n_unknown = n("unknown"),
               contract_sum = a$contract_sum, recon_gap = a$recon_gap, recon_ok = a$recon_ok, contract_cum = a$contract_cum)
  }), fill = TRUE) }), fill = TRUE)
## 라운드 묶음 — 구성마다 위기 = 그 구성 RX0 보는 창 패킷의 위기 · 깊은 위기(p2_deep_crisis_keys) ∪ 빠른 급락(p2_fast_crash_keys · FS 창 · 하락폭) · 칸 = P2R05_LIQ_CELLS 중 구성에 있는 칸
p5_liq_attr_round <- function(X, EVS, cells, engines, RAW, FS, tau) {
  E <- X$env$E
  if (!"Ret" %in% names(RAW)) stop("RAWDATA Ret 열 없음 — 일수익 재구성 불가")
  if (is.null(X$env$liq)) stop("유동성 패널 없음(보는 창 RAWDATA 미적재)")
  if (is.null(X$env$raw)) X$env$raw <- mc_load_raw(X$root, from = "1999-11-01", hygiene = TRUE)
  RW <- X$env$raw
  if (!"HYG" %in% names(RW)) stop("위생 멤버십(HYG) 없음 — 유니버스 3분위를 정할 수 없다")
  hc <- new.env(); di <- as.integer(RW$Date)                                     # 고점일 위생 멤버 — 날짜마다 한 번만 훑는다(칸 × 위기 반복 조회)
  hyg_of <- function(d) { k <- as.character(as.integer(as.Date(d))); if (is.null(hc[[k]])) hc[[k]] <- RW$Ticker[di == as.integer(k) & RW$HYG %in% TRUE]; hc[[k]] }
  cal <- sort(unique(as.Date(RAW$Date)))
  cof <- function(eng, comp) { z <- Filter(function(c0) identical(c0$engine, eng) && identical(c0$component, comp), cells); if (length(z)) z[[1]] else NULL }
  setNames(lapply(engines, function(eng) tryCatch({
    cr <- cof(eng, "RX0"); if (is.null(cr)) stop("RX0 칸 없음")
    ev0 <- EVS[[cr$code]]; if (!identical(ev0$status, "evaluated")) stop(sprintf("RX0 칸 평가 상태 %s", ev0$status %||% "NA"))
    pk <- p2_pk_read(X, cr$code); if (is.null(pk)) stop("RX0 보는 창 패킷 없음")
    crr <- pk$behavior$crises %||% list(); CR <- .p2_rows_dt(crr); if (!nrow(CR)) stop("위기 없음")
    CR[, k := .p2_key(CR)]
    deep <- p2_deep_crisis_keys(crr, crr)
    fk <- p2_fast_crash_keys(fread(file.path(E$ta_resolve_artifact(ev0$artifacts)$dir, "05_benchmark_returns.csv")), crr, as.integer(FS$fast_window_days), as.numeric(FS$fast_drop))
    CRK <- CR[k %in% union(deep, fk$keys), .(k, peak = as.Date(as.character(peak_date)), trough = as.Date(as.character(trough_date)), deep = k %in% deep, fast = k %in% fk$keys)]
    CRK <- CRK[!is.na(peak) & !is.na(trough) & trough <= as.Date(tau)]
    if (!nrow(CRK)) stop("보는 창 깊은 위기 · 빠른 급락 없음")
    comps <- intersect(P2R05_LIQ_CELLS, vapply(Filter(function(c0) identical(c0$engine, eng), cells), function(c0) as.character(c0$component), character(1)))
    per <- setNames(lapply(comps, function(cp) { cc <- cof(eng, cp); tryCatch({
      ev <- EVS[[cc$code]]
      if (!identical(ev$status, "evaluated")) stop(sprintf("칸 평가 상태 %s", ev$status %||% "NA"))
      c(list(cell = cc$code), p5_liq_tercile_cell(E, ev$artifacts, CRK, RAW, X$env$liq, hyg_of, tau, cal))
    }, error = function(e) list(status = "unmeasured", cell = cc$code, why = conditionMessage(e))) }), comps)
    rest <- setdiff(comps, "RX0")
    imp <- setNames(lapply(rest, function(cp) p5_liq_improvement(per[[cp]]$per_crisis, per[["RX0"]]$per_crisis, FS$majority_share)), rest)
    list(status = "ok", crises = CRK[, .(crisis = k, peak = format(peak), trough = format(trough), deep, fast)], per_cell = per, improvement = imp, table = p5_liq_table(per, eng),
         rule = "유동성 구간별 위기 손익 귀속 — 고점일 t−1 20일 평균 거래대금 유니버스 3분위 · 구간 손익 = 계약 일별 시작 비중 × 일수익의 (고점, 저점] 산술합 · 03 ret_gross 구간 합과 대조 단정 · 기록(판정 아님)")
  }, error = function(e) list(status = "unmeasured", why = conditionMessage(e), tags = "유동성 귀속 미측정"))), engines)
}
## 칸에 붙일 귀속(결론 꼬리표 입력) — 구성 귀속이 없거나 칸 짝이 없으면 '유동성 귀속 미측정'(의무)
p5_liq_attr_for <- function(LQA, eng, dev) {
  L <- LQA[[eng]]
  if (!is.list(L) || !identical(L$status, "ok")) return(list(status = "unmeasured", tags = "유동성 귀속 미측정", why = L$why %||% "구성 귀속 없음"))
  L$improvement[[dev]] %||% list(status = "unmeasured", tags = "유동성 귀속 미측정", why = "칸 귀속 없음(나란히 칸 밖 또는 RX0)")
}
## 부록 A 예측(기대 · 채점 대상 · 판정 아님 · 철학 P1 C-065) — E2 V2 상승 β > S2 상승 β ∧ ⑥(강세 구간 비율) V2 ≥ S2
p5_appendix_a <- function(OUT, DOUT, eng = P2R05_DIAG_ENGINE) {
  v <- .p5_find(OUT, eng, "V2"); s <- .p5_find(DOUT, eng, "S2")
  if (!.p5_readable(v) || !.p5_readable(s)) return(list(status = "unmeasured", why = sprintf("%s_V2 또는 %s_S2 판정 계산 없음", eng, eng)))
  n1 <- function(z) suppressWarnings(as.numeric(z %||% NA))[1]
  bu <- c(v2 = n1(v$rules$beta_asym$up), s2 = n1(s$rules$beta_asym$up)); b6 <- c(v2 = n1(v$rules$bull$share), s2 = n1(s$rules$bull$share))
  up <- if (all(is.finite(bu))) bu[["v2"]] > bu[["s2"]] else NA; bl <- if (all(is.finite(b6))) b6[["v2"]] >= b6[["s2"]] else NA
  list(status = "ok", prediction = "V2 상승 β > S2 상승 β ∧ ⑥ V2 ≥ S2(부록 A)", up_beta = as.list(bu), bull_share = as.list(b6), up_beta_holds = up, bull_holds = bl,
       holds = if (is.na(up) || is.na(bl)) NA else up && bl)
}
## 진단 읽기(§5.1 · 판정 아님) — '승리' = 그 칸이 자기 β 짝 사본을 깊은 위기에서 tol 넘게 이김(③ 위기별 per_crisis k · m · r)
.p5_readable <- function(x) isTRUE(x$rules_computed)
.p5_find <- function(L, eng, comp) { z <- Filter(function(x) identical(x$engine, eng) && identical(x$device, comp), L); if (length(z)) z[[1]] else list(tested = FALSE, rules_computed = FALSE, rules = list(), why = "칸 없음") }
.p5_win_status <- function(x, crisis, tol) {
  if (!.p5_readable(x)) return("unknown")
  D <- as.data.table(x$rules$beta_deep$per_crisis %||% data.table())
  if (!nrow(D) || !all(c("k", "m", "r") %in% names(D)) || !(crisis %in% D$k)) return("unknown")
  z <- D[k == crisis][1]
  if (!is.finite(z$m) || !is.finite(z$r)) return("unknown")
  if (z$m < z$r - tol) "win" else "no_win"
}
p5_read_center <- function(v, q, tol) {
  if (!.p5_readable(v)) return(list(status = "unmeasured", why = "변형 칸 판정 계산 없음"))
  if (!.p5_readable(q)) return(list(status = "unmeasured", why = paste("Q50 미시험:", q$why %||% "칸 없음")))
  ov <- p2_read_overlap_wins(v$rules$beta_deep$per_crisis, q$rules$beta_deep$per_crisis, tol)
  list(status = ov$status, n_win = ov$n_a, center_effect = ov$both, n_center_effect = length(ov$both), not_center = ov$a_only, unknown = ov$unknown,
       tag = if (length(ov$both)) sprintf("중심 표적 효과 %d/%s 위기(β 짝 승리 중 Q50 도 이김)", length(ov$both), format(ov$n_a)) else NA_character_)
}
p5_read_dilution <- function(v, n, tol) {
  if (!.p5_readable(v)) return(list(status = "unmeasured", why = "변형 칸 판정 계산 없음"))
  if (!.p5_readable(n)) return(list(status = "unmeasured", why = paste("희석 짝 미시험:", n$why %||% "칸 없음")))
  reg <- p2_read_overlap_wins(v$rules$crisis$per_crisis, n$rules$crisis$per_crisis, tol)
  dp <- p2_read_overlap_wins(v$rules$deep$per_crisis, n$rules$deep$per_crisis, tol)
  list(status = reg$status, diag_cell = n$cell %||% NA_character_, n_improve = reg$n_a, dilution = reg$both, n_dilution = length(reg$both), not_dilution = reg$a_only, unknown = reg$unknown,
       tag = if (length(reg$both)) sprintf("희석 몫 %d/%s 위기(① 개선 중 무정보 꼬리 순열 짝도 개선 — 등록 판독)", length(reg$both), format(reg$n_a)) else NA_character_,
       deep_record = list(status = dp$status, n_improve = dp$n_a, dilution = dp$both, n_dilution = length(dp$both), unknown = dp$unknown,
                          note = "깊은 위기 겹침(기록 — 등록 판독은 ① 위기 수 겹침)"))
}
p5_read_volleak <- function(v, s, tol) {
  if (!.p5_readable(v)) return(list(status = "unmeasured", why = "변형 칸 판정 계산 없음"))
  if (!.p5_readable(s)) return(list(status = "unmeasured", why = paste("변동성 대리 짝 미시험:", s$why %||% "칸 없음")))
  ov <- p2_read_overlap_wins(v$rules$beta_deep$per_crisis, s$rules$beta_deep$per_crisis, tol)
  list(status = ov$status, diag_cell = s$cell %||% NA_character_, n_win = ov$n_a, vol_proxy = ov$both, n_vol_proxy = length(ov$both), not_vol = ov$a_only, unknown = ov$unknown,
       tag = if (length(ov$both)) sprintf("변동성 대리 방어 %d/%s 위기(β 짝 승리 중 S 짝도 이김)", length(ov$both), format(ov$n_a)) else NA_character_)
}
## 꼬리 고유 — Vk 의 β 짝 승리 깊은 위기마다 Sk · Nk · Q50 상태(win · no_win · unknown) · 셋 다 no_win ∧ 꼬리 증분(D^σ ∧ D^w ∧ D^H t > t_min)이면 '꼬리 학습 방어'
##   (철학 P1 R-20261018-008 C-065 — 구 조건 'D^σ t > 2' 를 꼬리 증분으로 넓힘) · tinc = p5_tail_increment(…)
p5_read_tail_unique <- function(v, s, n, q, tinc, t_min, tol) {
  if (!.p5_readable(v)) return(list(status = "unmeasured", why = "변형 칸 판정 계산 없음", per_crisis = data.table()))
  wins <- .p2_wins(v$rules$beta_deep$per_crisis, tol)
  if (is.null(wins)) return(list(status = "unmeasured", why = "β 짝 위기 표 없음", per_crisis = data.table()))
  dt_ok <- isTRUE(tinc$ok)
  P <- rbindlist(lapply(wins, function(c0) {
    ss <- .p5_win_status(s, c0, tol); ns <- .p5_win_status(n, c0, tol); qs <- .p5_win_status(q, c0, tol)
    tu <- all(c(ss, ns, qs) == "no_win") && dt_ok
    nm <- c(if (identical(ss, "win")) "변동성 대리 방어", if (identical(qs, "win")) "중심 표적 효과", if (identical(ns, "win")) "희석 몫",
            if (tu) "꼬리 학습 방어", if (!tu && !any(c(ss, qs, ns) == "win") && any(c(ss, ns, qs) == "unknown")) "판독 불가(진단 칸 위기 표 결손 · 미시험)",
            if (!tu && all(c(ss, ns, qs) == "no_win") && !dt_ok) "꼬리 고유 미확인(꼬리 증분 D^σ ∧ D^w ∧ D^H t > t_min 미충족 또는 미측정)")
    data.table(crisis = c0, s = ss, n = ns, q50 = qs, tail_unique = tu, names = paste(nm, collapse = " · "))
  }))
  if (!nrow(P)) P <- data.table(crisis = character(0), s = character(0), n = character(0), q50 = character(0), tail_unique = logical(0), names = character(0))
  list(status = "ok", n_win = length(wins), n_tail_unique = sum(P$tail_unique), tail_increment = tinc$ok %||% NA, tail_increment_t = tinc$t %||% list(), t_min = t_min, per_crisis = P,
       tag = if (sum(P$tail_unique)) sprintf("꼬리 학습 방어 %d/%d 위기(S · N · Q50 모두 미승 ∧ 꼬리 증분)", sum(P$tail_unique), length(wins)) else NA_character_)
}
## 용량(V2) — 세 칸(E2_V2 · W2 · E3_V2)의 통과를 사전 고정 표에 대본다(첫 일치 · 미시험 = 미측정 · 표 밖 = 그대로 적는다)
p5_capacity_label <- function(e2, w2, e3, table = P2R05_CAPACITY_TABLE) {
  x <- c(e2_v2 = e2, w2 = w2, e3_v2 = e3)
  if (length(x) != 3L || anyNA(x)) return(NA_character_)
  for (i in seq_len(nrow(table))) { pat <- unlist(table[i, .(e2_v2, w2, e3_v2)]); if (all(is.na(pat) | pat == x)) return(table$label[i]) }
  sprintf("표 밖(네 경우 밖 — E2_V2 %s · W2 %s · E3_V2 %s)", x[["e2_v2"]], x[["w2"]], x[["e3_v2"]])
}
p5_read_capacity <- function(e2v2, w2, e3v2) {
  f <- function(x) if (isTRUE(x$tested)) isTRUE(x$pass) else NA
  P <- c(e2_v2 = f(e2v2), w2 = f(w2), e3_v2 = f(e3v2))
  list(passes = as.list(P), label = if (anyNA(P)) "미측정(세 칸 중 미시험 — ⑮ 미달 포함)" else p5_capacity_label(P[["e2_v2"]], P[["w2"]], P[["e3_v2"]]),
       blend_share_w2 = w2$construction$blend_share %||% NA_real_,
       verdicts = c(e2_v2 = e2v2$verdict %||% NA_character_, w2 = w2$verdict %||% NA_character_, e3_v2 = e3v2$verdict %||% NA_character_))
}
## 저용량 변동성 스크린 대비(LV · 판단 Superfan T2 C-20261018-038 · 비교 범위 = 판단 T1 C-058 · 한 정의 = 격리 교차 점검 v1 필수 2 · 사전등록 comparison.reading 정의 A):
##   '원천 ① 증분 없음' ⇔ LV β 짝 승리 깊은 위기 ≥ 1 ∧ 그 위기들에서 Vk 가 LV 를 tol 넘게 못 이김 ∧ Vk β 짝 승리 깊은 위기 ≥ 1 ∧ ⊆ LV β 짝 승리 깊은 위기 ·
##   Vk 가 LV 가 못 이긴 깊은 위기를 이기거나(Vk 승리 ⊄ LV 승리) LV 승리 위기에서 Vk 포착 < LV 포착 − tol 이면 'LV 대비 증분 있음' · Vk β 짝 승리 0 = 'LV 대비 판독 해당 없음' ·
##   포착 비교 범위 = LV 가 자기 β 짝을 이긴 깊은 위기(C-058) · LV 승리 위기 0 · 그 위기에 변형 포착 결손 · LV 위기 표 없음 · 미시험 = 'LV 대비 판독 미결' ·
##   기록: Vk 의 β 짝 승리 깊은 위기 · LV 밖 승리 위기 · S 증분(Vk − RX0) 대 (LV − RX0)
p5_read_lowvol <- function(v, lv, tol) {
  und <- function(why) list(name = paste0("LV 대비 판독 미결(", why, ")"), name_status = "undetermined")
  if (!.p5_readable(v)) return(c(list(status = "unmeasured", why = "변형 칸 판정 계산 없음"), und("변형 칸 판정 계산 없음")))
  if (!.p5_readable(lv)) return(c(list(status = "unmeasured", why = paste("LV 미시험:", lv$why %||% "칸 없음")), und("LV 미시험")))
  V <- as.data.table(v$rules$beta_deep$per_crisis %||% data.table()); L <- as.data.table(lv$rules$beta_deep$per_crisis %||% data.table())
  dS <- function(x) suppressWarnings(as.numeric(x$non_inferiority$S %||% NA) - as.numeric(x$non_inferiority$S_rx0 %||% NA))[1]
  base <- list(dS_variant = dS(v), dS_lv = dS(lv), lv_cell = lv$cell %||% NA_character_, variant_wins = .p2_wins(V, tol) %||% character(0))
  lw <- .p2_wins(L, tol)
  if (is.null(lw)) return(c(base, list(status = "unmeasured", why = "LV β 짝 위기 표 없음"), und("LV β 짝 위기 표 없음")))
  if (!length(lw)) return(c(base, list(status = "ok", n_lv_win = 0L, per_crisis = data.table()), und("LV β 짝 승리 깊은 위기 0")))
  P <- rbindlist(lapply(lw, function(c0) {
    ml <- L[k == c0]$m[1]; mv <- if (nrow(V) && all(c("k", "m") %in% names(V))) V[k == c0]$m[1] else NA_real_
    data.table(crisis = c0, dd_capture_lv = ml, dd_capture = mv, variant_beats_lv = if (is.finite(mv) && is.finite(ml)) mv < ml - tol else NA,
               variant_beats_beta_copy = c0 %in% base$variant_wins)
  }))
  if (anyNA(P$variant_beats_lv)) return(c(base, list(status = "ok", n_lv_win = nrow(P), per_crisis = P), und("LV 승리 위기에 변형 포착 결손")))
  if (!length(base$variant_wins)) return(c(base, list(status = "ok", n_lv_win = nrow(P), n_variant_beats_lv = sum(P$variant_beats_lv), per_crisis = P,
                                                      name = "LV 대비 판독 해당 없음(Vk β 짝 승리 깊은 위기 0)", name_status = "not_applicable")))
  outv <- setdiff(base$variant_wins, lw)                                         # Vk 승리 ⊄ LV 승리 — LV 가 못 이긴 깊은 위기를 Vk 가 이김(필수 2 · 정의 A)
  inc <- any(P$variant_beats_lv) || length(outv) > 0L
  c(base, list(status = "ok", n_lv_win = nrow(P), n_variant_beats_lv = sum(P$variant_beats_lv), outside_lv = outv, n_outside_lv = length(outv), per_crisis = P,
               increment_kind = c(if (any(P$variant_beats_lv)) "beats_lv_in_lv_wins", if (length(outv)) "wins_outside_lv"),
               name = if (inc) "LV 대비 증분 있음" else "원천 ① 증분 없음(저용량 변동성 스크린과 같음)", name_status = if (inc) "increment" else "no_increment"))
}
## 시드 띠(판단 Superfan T1 R-20261018-007 C-054 · 기록 · 판정 아님) — 같은 구성 재시드 칸(RX0S) 대 RX0: 위기마다 |포착(RX0S) − 포착(RX0)| · S 띠 = |S(RX0S) − S(RX0)|
##   재시드 칸이 없거나 판정 계산이 없으면 '시드 띠 미측정'(실패 아님)
p5_seed_band <- function(rs) {
  if (!.p5_readable(rs)) return(list(status = "unmeasured", tag = "시드 띠 미측정", why = rs$why %||% "재시드 칸 없음"))
  P <- as.data.table(rs$rules$crisis$per_crisis %||% data.table())
  if (!nrow(P) || !all(c("k", "m", "r") %in% names(P))) return(list(status = "unmeasured", tag = "시드 띠 미측정", why = "재시드 위기 표 없음"))
  P <- P[is.finite(m) & is.finite(r), .(k, band = abs(m - r))]
  sb <- abs(suppressWarnings(as.numeric(rs$non_inferiority$S %||% NA) - as.numeric(rs$non_inferiority$S_rx0 %||% NA))[1])
  list(status = "ok", tag = NA_character_, cell = rs$cell %||% NA_character_, per_crisis = P, S_band = sb,
       note = "시드 띠 = 평균 DNN 재시드 1쌍(RX0S 대 RX0) — 분위 모델 시드 잡음의 대리(DESIGN §0b 결정 2 · 판단 T1 C-054)")
}
## 시드 미결 꼬리표 — Vk 의 위기별 β 짝 결정(③ 깊은 위기 · ④ 빠른 급락)에서 |변형 포착 − 사본 포착| < 그 위기의 시드 띠 = '시드 미결' ·
##   |S 증분(Vk − RX0)| < S 띠 = 'S 시드 미결'(부호 대칭 — 위기별 꼬리표와 같은 절댓값 형식) · 판정은 바뀌지 않는다 · 띠 없는 위기 = NA(시드 띠 미측정)
p5_seed_tags <- function(v, band) {
  if (!.p5_readable(v)) return(list(status = "unmeasured", why = "변형 칸 판정 계산 없음", tags = character(0)))
  if (!identical(band$status, "ok")) return(list(status = "unmeasured", why = band$why %||% NA_character_, tags = "시드 띠 미측정"))
  one <- function(J) { J <- as.data.table(J %||% data.table())
    if (!nrow(J) || !all(c("k", "m", "r") %in% names(J))) return(data.table(crisis = character(0), gap = numeric(0), band = numeric(0), undetermined = logical(0)))
    X <- merge(J[, .(k, gap = abs(m - r))], band$per_crisis, by = "k", all.x = TRUE)
    X[, .(crisis = k, gap, band, undetermined = ifelse(is.finite(band), gap < band, NA))] }
  D <- one(v$rules$beta_deep$per_crisis); F <- one(v$rules$fast$per_crisis)
  dS <- suppressWarnings(as.numeric(v$non_inferiority$S %||% NA) - as.numeric(v$non_inferiority$S_rx0 %||% NA))[1]
  sU <- if (is.finite(dS) && is.finite(band$S_band)) abs(dS) < band$S_band else NA
  nd <- sum(D$undetermined %in% TRUE); nf <- sum(F$undetermined %in% TRUE)
  list(status = "ok", deep = D, fast = F, n_deep = nrow(D), n_deep_undetermined = nd, n_fast = nrow(F), n_fast_undetermined = nf,
       n_band_missing = sum(is.na(D$undetermined)) + sum(is.na(F$undetermined)), S = list(dS = dS, band = band$S_band, undetermined = sU),
       tags = c(if (nd) sprintf("시드 미결 %d/%d 깊은 위기(③)", nd, nrow(D)), if (nf) sprintf("시드 미결 %d/%d 빠른 급락(④)", nf, nrow(F)), if (isTRUE(sU)) "S 시드 미결",
                if (anyNA(c(D$undetermined, F$undetermined)) || is.na(sU)) "시드 띠 미측정(일부 위기 · S)"))
}
## R7 판독에 싣는 시드 꼬리표 수 — 판정된 규칙의 칸들
p5_seed_tag_counts <- function(OUT, devs) {
  xs <- Filter(function(x) isTRUE(x$device %in% devs), OUT)
  st <- lapply(xs, function(x) x$seed_tags %||% list(status = "unmeasured"))
  ok <- vapply(st, function(s) identical(s$status, "ok"), logical(1))
  list(n_cells = length(xs), n_cells_with_band = sum(ok), n_deep_undetermined = sum(vapply(st[ok], function(s) as.integer(s$n_deep_undetermined %||% 0L), integer(1))),
       n_fast_undetermined = sum(vapply(st[ok], function(s) as.integer(s$n_fast_undetermined %||% 0L), integer(1))),
       n_S_undetermined = sum(vapply(st[ok], function(s) isTRUE(s$S$undetermined), logical(1))),
       tag = if (length(xs) && !all(ok)) "시드 띠 미측정(일부 칸)" else NA_character_)
}
## 계기 → 다음 행동(사전 고정 처분 안내 · 판정 아님 · 판단 Superfan T1 R-20261018-007) — 위에서 아래로 첫 일치(맞는 줄은 모두 적는다) ·
##   '꼬리 증분' = p5_tail_increment(D^σ ∧ D^w ∧ D^H 모두 NW t > t_min · ⑮ 와 같은 t) · '③ 통과' = 판정 계산이 된 변형 칸 중 ③ 통과 칸 ≥ 1 · ⑮ 미측정 = 해당 없음
P2R05_ACTION_TABLE <- data.table(row = c("A", "B", "C", "D"),
  condition = c("⑮ 미달", "⑮ 통과 ∧ D^σ · D^w · D^H 증분 없음", "⑮ 통과 ∧ 꼬리 증분 있음 ∧ ③ 미달", "③ 통과"),
  action = c("'이 학습 설정은 종목 왼꼬리를 배우지 못함(계기 실패 · 원천 ① 반증 아님)' 기록 · P2 정지 판독", "'꼬리 = 변동성 대리' · LV 대비 기록 · P2 정지 판독",
             "다음 장치 = 상태 조건부 꼬리 거부(V3 · 위기 진행 중 as-of 상태) · P2 가 멈추면 P4 부품 시험으로", "P3 의견서 · 후보 경로"))
p5_action_row <- function(tail, tinc, OUT, t_min) {
  inc <- tinc$ok %||% NA
  vx <- Filter(function(x) isTRUE(x$device %in% names(P2R05_RULES)), OUT)
  r3c <- vapply(vx, function(x) isTRUE(x$rules_computed) && identical(x$rules$beta_deep$status, "ok") && isTRUE(x$rules$beta_deep$ok), logical(1))
  r3any <- any(r3c); tm <- identical(tail$status, "ok"); tp <- tm && isTRUE(tail$pass)
  cond <- c(A = tm && !tp, B = tp && identical(inc, FALSE), C = tp && isTRUE(inc) && !r3any, D = tm && r3any)
  hit <- names(cond)[cond]; rw <- if (length(hit)) hit[1] else NA_character_
  list(row = rw, matches = hit, action = if (is.na(rw)) NA_character_ else P2R05_ACTION_TABLE$action[match(rw, P2R05_ACTION_TABLE$row)],
       condition = if (is.na(rw)) NA_character_ else P2R05_ACTION_TABLE$condition[match(rw, P2R05_ACTION_TABLE$row)],
       tail_status = tail$status %||% NA_character_, tail_pass = tp, tail_increment = inc, tail_increment_t = tinc$t %||% list(), t_min = t_min,
       r3_pass_cells = vapply(vx[r3c], function(x) as.character(x$cell %||% NA_character_), character(1)),
       note = if (!is.na(rw)) NA_character_ else if (!tm) "계기 미측정 — 처분 안내 해당 없음" else if (is.na(inc)) "D^σ · D^w · D^H 중 미측정 — B · C 판독 불가" else "표 밖")
}
## 진단 읽기 묶음 — 규칙마다 E2 중심 · 희석 · 변동성 · 꼬리 고유 · 구성마다 LV · 용량(V2)
p5_readings <- function(OUT, DOUT, tol, tinc, t_min, rules = names(P2R05_RULES), diag_engine = P2R05_DIAG_ENGINE) {
  pair_of <- function(reading, rk) { z <- names(Filter(function(d) identical(d$reading, reading) && rk %in% (d$pair %||% character(0)), P2R05_DIAGNOSTICS)); if (length(z)) z[1] else NA_character_ }
  q <- .p5_find(DOUT, diag_engine, "Q50")
  per <- setNames(lapply(rules, function(rk) {
    v <- .p5_find(OUT, diag_engine, rk); n <- .p5_find(DOUT, diag_engine, pair_of("dilution", rk)); s <- .p5_find(DOUT, diag_engine, pair_of("vol_leak", rk))
    list(rule = rk, engine = diag_engine, center = p5_read_center(v, q, tol), dilution = p5_read_dilution(v, n, tol), vol_leak = p5_read_volleak(v, s, tol),
         tail_unique = p5_read_tail_unique(v, s, n, q, tinc, t_min, tol))
  }), rules)
  engs <- unique(vapply(OUT, function(x) as.character(x$engine %||% NA_character_), character(1))); engs <- engs[!is.na(engs)]
  other <- setdiff(engs, diag_engine)[1]
  lvr <- setNames(lapply(engs, function(e) setNames(lapply(rules, function(rk) p5_read_lowvol(.p5_find(OUT, e, rk), .p5_find(DOUT, e, "LV"), tol)), rules)), engs)
  list(diag_engine = diag_engine, other_engine = if (length(other) && !is.na(other)) other else NA_character_, per_rule = per, lowvol = lvr,
       capacity = p5_read_capacity(.p5_find(OUT, diag_engine, "V2"), .p5_find(DOUT, diag_engine, "W2"), if (length(other) && !is.na(other)) .p5_find(OUT, other, "V2") else list(tested = FALSE)))
}
## 결론 문장에 함께 싣는 나란히 기록(결론 범위 11 · 14 — 격리 교차 점검 v1 권고 5): 깊은 위기 보유 유동성 십분위 V · S(짝) · Q50 · RX0 · 보유 이름 겹침 RX0 대비 · Q50 대비
p5_side_text <- function(side) {
  if (is.null(side)) return("")
  f3 <- function(v) format(signif(suppressWarnings(as.numeric(v %||% NA))[1], 3)); lq <- side$liq %||% list(); ov <- side$overlap %||% list()
  paste0(sprintf(" · 깊은 위기 보유 유동성 십분위 나란히 V %s · S %s · Q50 %s · RX0 %s", f3(lq$V), f3(lq$S), f3(lq$Q50), f3(lq$RX0)),
         sprintf(" · 보유 이름 겹침 RX0 대비 %s · Q50 대비 %s", f3(ov$rx0), f3(ov$q50)))
}
## 수평 판독(결론 범위 5 — 격리 교차 점검 v1 권고 5 · 기존 기록 · 새 숫자 없음): 거부 집합의 다음 보유월 하위 분위 적중(transfer.veto.bottom) ≤ 기저(base_rate = 1/분위 수)
##   = '수평 불일치'(5일 분포 예측의 왼꼬리가 월간 보유로 옮겨가지 않음) · 기록이 없으면 '수평 판독 미측정'
p5_horizon_reading <- function(tr) {
  vb <- suppressWarnings(as.numeric(tr$veto$bottom %||% NA))[1]; br <- suppressWarnings(as.numeric(tr$base_rate %||% NA))[1]
  if (!identical(tr$status %||% "ok", "ok") || !is.finite(vb) || !is.finite(br))
    return(list(status = "unmeasured", mismatch = NA, tag = "수평 판독 미측정(월 수평 전이 기록 없음)"))
  mm <- vb <= br
  list(status = "ok", mismatch = mm, veto_bottom = vb, base_rate = br, rule = "거부 집합 다음 보유월 하위 분위 적중 ≤ 기저(1/분위 수) = '수평 불일치'",
       tag = if (mm) "수평 불일치(거부 집합의 다음 보유월 하위 분위 적중 ≤ 기저 — 5일 왼꼬리가 월간 보유로 옮겨가지 않음)" else NA_character_)
}
## 결론 이름(DESIGN §10.2 ~ 10.4 + LV · 판정 아님) — 기본 이름(P2R04 규칙) + '꼬리 학습 방어'(꼬리 고유 위기 ≥ 1 ∧ 방어 이름 성립) · 위기별 이름 · 꼬리 회피 기계 ·
##   ⑮ 미시험 · LV 이름 · 희석 몫 · 유동성 · 크기 십분위 · 기준점 둘 · 단일 시드 꼬리표
p5_conclusion <- function(x, rd = NULL, lv = NULL, side = NULL, hz = NULL) {
  liqtag <- if (is.null(x$liq_attr) || !identical(x$liq_attr$status, "ok")) "유동성 귀속 미측정" else x$liq_attr$tags   # 철학 P4 C-076 — 계산 못 하면 의무 꼬리표
  qltag <- if (identical(x$qpred_log$status, "unverifiable")) "⑮ 예측표 셀 로그 대조 불가(셀 로그 예측표 줄 없음 · 기저 캐시 출처 미확인)" else NULL   # 격리 점검 v2 필수 1
  if (!.p5_readable(x)) return(list(name = paste0("미시험 — ", x$why %||% "판정 계산 없음"), granted = FALSE, tags = c(liqtag, "시드 띠 미측정(단일 시드 · 잡음 띠 미측정)")))
  f <- x$flags %||% list()
  base <- p2_defense_name(f$r3, f$r4, f$level, f$s14, f$sb_ok, f$sb_status, s14_measured = isTRUE(f$s14_measured))
  granted <- isTRUE(f$r3) && isTRUE(f$r4) && isTRUE(f$level) && isTRUE(f$s14_measured) && isTRUE(f$s14)
  machine <- p5_machine(f$tail, f$crisis, f$deep, f$r3, f$r4, f$s14_measured, f$s14, f$level, f$beta_ratio, f$strength)   # 판정어와 같은 정의(필수 1)
  tu <- rd$tail_unique; ntu <- if (is.null(tu$n_tail_unique)) 0L else as.integer(tu$n_tail_unique)
  name <- if (granted && ntu > 0L) sprintf("꼬리 학습 방어(꼬리 고유 %d/%d 위기) · %s", ntu, as.integer(tu$n_win), base) else base
  sd <- x$seed_tags
  seedtag <- if (identical(sd$status, "ok")) c(sd$tags, "시드 띠 = 평균 DNN 재시드 1쌍(RX0S) — 분위 모델 시드 잡음의 대리") else "시드 띠 미측정(단일 시드 · 잡음 띠 미측정)"
  tags <- c(if (machine) "꼬리 회피 기계(방어만 · 복리 없음)", if (!isTRUE(x$tail_gate$pass)) "미시험(꼬리 계기) — 원천 ① 반증 아님",
            if (!isTRUE(f$r3) && isTRUE(f$sharpe_up)) "Sharpe 상승 = 평시 변동성 축소(③ 미통과 — 철학 P1 C-070)",
            if (!is.null(lv$name) && !is.na(lv$name)) lv$name, if (!is.null(hz$tag) && !is.na(hz$tag)) hz$tag, qltag, liqtag, seedtag)
  dil <- rd$dilution
  liq <- x$liquidity; sz <- x$record$size_decile
  rp <- x$reference_points
  sent <- paste0(name, " · ", paste(tags, collapse = " · "),
                 " · 희석 몫 ", if (is.null(dil)) "해당 없음(이 구성 진단 칸 없음)" else if (!is.null(dil$tag) && !is.na(dil$tag)) dil$tag else sprintf("0/%s 위기", format(dil$n_improve %||% NA)),
                 sprintf(" · 깊은 위기 보유 유동성 십분위 %s(RX0 %s) · 크기 십분위 %s(RX0 %s)",
                         format(signif(liq$variant$deep_mean_decile %||% NA_real_, 3)), format(signif(liq$rx0$deep_mean_decile %||% NA_real_, 3)),
                         format(signif(sz$deep_mean_decile %||% NA_real_, 3)), format(signif(sz$deep_mean_decile_rx0 %||% NA_real_, 3))),
                 sprintf(" · 기준점 둘 — 엔진 대비 깊은 위기 %s · 시장 대비 깊은 위기 %s", format(signif(rp$engine$deep %||% NA_real_, 3)), format(signif(rp$market$deep$share %||% NA_real_, 3))),
                 p5_side_text(side))
  list(name = name, base_name = base, granted = granted, machine = machine, tags = tags, crisis_names = tu$per_crisis %||% data.table(),
       lowvol_name = lv$name %||% NA_character_, lowvol_status = lv$name_status %||% NA_character_, sentence = sent)
}

## ── 계약 호출 기록 도우미(보는 창 · 판정 아님 · 실패 = 그 기록만 미측정 꼬리표) — P2R04 그대로 ─────────────────────────
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
p2_liquidity_record <- function(X, dir, crises, deep_peaks) {
  E <- X$env$E; TAU <- X$tau
  if (is.null(X$env$raw)) X$env$raw <- mc_load_raw(X$root, from = "1999-11-01", hygiene = TRUE)
  if (!"HYG" %in% names(X$env$raw)) stop("위생 멤버십(HYG) 없음 — 측정 유니버스 분위를 정할 수 없다")
  if (is.null(X$env$liq)) stop("유동성 패널 없음(보는 창 RAWDATA 미적재)")
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
p2_regime_months <- function(X, am, ar, PM) {
  E <- X$env$E; mon <- function(d) { rd <- .dp_read(E, d); E$bc_monthly(rd$pr[date <= X$tau, .(date, r = ret_net)], "r") }
  D <- merge(mon(am)[, .(ym, s = r)], mon(ar)[, .(ym, b = r)], by = "ym")[order(ym)]
  p2_regime_diff(D$ym, D$s - D$b, PM$behavior$crises %||% list(), PM$behavior$bull_phases %||% list())
}
p2_rx0_identity <- function(X, art5, json4) {
  if (!file.exists(json4)) return(list(status = "absent", p2r04 = sub(paste0("^", X$root, "/"), "", json4)))
  j <- fromJSON(json4, simplifyVector = FALSE)
  if (!isTRUE(j$ok) || is.null(j$artifacts)) return(list(status = "p2r04_not_ok", p2r04 = sub(paste0("^", X$root, "/"), "", json4)))
  E <- X$env$E; d5 <- E$ta_resolve_artifact(art5)$dir; d4 <- E$ta_resolve_artifact(j$artifacts)$dir
  rp <- function(d) { x <- fread(file.path(d, "03_period_returns.csv")); x[, date := as.Date(date)]; x }
  c(list(status = "ok", p2r04 = sub(paste0("^", X$root, "/"), "", json4)), p2_rx0_identity_core(.p2_read_holdings(d5), .p2_read_holdings(d4), rp(d5), rp(d4), X$tau))
}

## ── 칸 평가(보는 창 / 사람 쪽 파일 분리) — P2R04 그대로 ──────────────────────────────────────────────────────────
p2_cell_join <- function(v, f) c(v, list(test = f$test, full = f$full))
p2_eval_cell <- function(root, res_dir, cell, env, tau)
  tryCatch(.p2_eval_cell_core(root, res_dir, cell, env, tau),
           error = function(e) { cat(sprintf("[P2R05 평가] %s — 칸 평가 오류: %s\n", cell$code, .p2_redact_chr(conditionMessage(e), as.Date(tau))))
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
  f <- list(code = cell$code, audience = P2R05_FULL_AUDIENCE,
            test = list(uc = card$test$bull_up_capture_median %||% NA, dc = card$test$crisis_cum_capture_median %||% NA,
                        n_bull = card$test$n_bull %||% NA, n_crisis = card$test$n_crisis %||% NA, verdict = card$test$verdict %||% NA,
                        dc_strong = card$dc_strong_max %||% NA, perf = tp),
            full = list(grade = ar$essence_grade, S = ar$grade_v3$S %||% NA, cr = card$overall$verdict, attribution = card$controls$attribution$overall$label %||% NA,
                        cdar = card$stats$cdar %||% NA, effective_start = ar$measurement_axis$effective_start$date %||% NA))
  writeLines(toJSON(f, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), ff, useBytes = TRUE)
  writeLines(toJSON(v, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), fv, useBytes = TRUE)
  writeLines(P2R05_FULL_AUDIENCE, file.path(out_dir, "full", "NO_VISIBLE_REVIEW.txt"), useBytes = TRUE)
  cat(sprintf("[P2R05 평가] %s — 보는 창 UC %.3f · DC %.3f · CAGR %.3f · CDaR %.3f · 귀속 %s · 축 %s · %.0f초\n", cell$code, v$visible$uc, v$visible$dc,
              v$visible$cagr, v$visible$cdar, v$visible$attribution, ax$ok, v$eval_seconds))
  p2_cell_join(v, f)
}

## ── 판정 1칸(규칙 × 구성 vs 같은 구성 RX0) — 본 실행 · 진단 · 비교 기준 칸 · 등록 전 리허설(rehearse.R)이 같은 함수를 쓴다 ─────────────────
##   X = list(root · res · out · env(E · BCFG_L · raw · liq) · fs · tau · ea(엔진 알파 캐시 환경))
##   opts([[ ]] 정확 일치): role("judge" = V1 · V2 · "diagnostic" = 진단 · 비교 기준) · ctx(라운드 구성 맥락: pre · root · warm · template · tail_d) ·
##     tail_ok(⑮ 통과 — 칸 통과 13번째 조건 · 적용 칸 = V · W2) · q50(V1 전달량 대조: status ok · not_applicable · unmeasured + dir · why) ·
##     expect_weight(LV 혼합 몫) · 리허설 전용 force_start · force_k · expect_cell · expect_cell_rx0 · log · log_rx0
##   실패 의미(사전 고정 · P2R04 + P2R05): 평가 상태 · 역할 · 사양 · ⑩(a)(b) · 실효 시작 · 공통 창 · ⑩(c) 무처치 · V1 ≠ Q50 미측정 · 패킷 · 위기 짝 · 판정 입력 = 미시험 /
##     β 사본 실패 · ③ 짝 < 2 = 'β 대조 미측정' / ④ 짝 < 2 = '빠른 급락 미측정' / ⑭ 미측정 = selection_unmeasured / 집중 결손 = 제외 / 기록 계산 실패 = 그 기록만 미측정
.p2_untested <- function(out, why) {
  if (is.null(out[["rules"]])) out[["rules"]] <- list()                          # $rules 부분 일치 방지(rules_computed 로 새지 않게 — R 의 $ 는 목록에서 부분 일치한다)
  out$tested <- FALSE; out$pass <- FALSE; out$verdict <- "untested"; out$verdict_name <- P2R05_VERDICT_NAMES[["untested"]]; out$why <- why
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
p2_eng_alpha <- function(X, dir) {
  E <- X$env$E; rd <- .dp_read(E, dir); mon <- function(d, col) E$bc_monthly(d[, .(date, r = get(col))], "r")
  D <- merge(mon(rd$pr[, .(date, ret_net)], "ret_net")[, .(ym, s = r)], mon(rd$br[, .(date, benchmark_ret)], "benchmark_ret")[, .(ym, k = r)], by = "ym")
  D <- D[ym <= format(X$tau, "%Y-%m")]
  a <- tryCatch(beta_controlled_alpha(D$s, D$k, periods_per_year = 12, nw_lag = 3L), error = function(e) NULL)
  list(alpha_ann = a$alpha_ann %||% NA_real_, t = a$t_alpha %||% NA_real_, n = a$n %||% NA_integer_)
}
## ⑮ 적용 칸(분위 꼬리를 소비하는 칸) — 변형 V1 · V2 + 용량 짝 W2(V2 계열)
p5_tail_applicable <- function(comp) comp %in% c(names(P2R05_RULES), "W2")
p5_eval_pair <- function(X, eng, comp, cm, cr, em, er, opts = list()) {
  FS <- X$fs; TAU <- X$tau; g <- rk_getf
  MAJ <- as.numeric(FS$majority_share); tol <- as.numeric(FS$crisis_improve_min)
  role <- opts[["role"]] %||% "judge"; diag <- identical(role, "diagnostic")
  ctx <- opts[["ctx"]] %||% list()
  out <- list(engine = eng, device = comp, role = role, cell = cm$code, rx0 = cr$code, status = em$status %||% NA, status_rx0 = er$status %||% NA, rules_computed = FALSE, rules = list())
  if (!identical(em$status, "evaluated") || !identical(er$status, "evaluated"))
    return(.p2_untested(out, sprintf("평가 상태 %s · %s", em$status %||% "NA", er$status %||% "NA")))
  is_rule <- comp %in% names(P2R05_RULES)
  if (!(is_rule || comp %in% names(P2R05_DIAGNOSTICS))) return(.p2_untested(out, paste("규칙 · 진단 표에 없는 부품:", comp)))
  if (is_rule == diag) return(.p2_untested(out, sprintf("역할 불일치 — 부품 %s · 역할 %s(규칙 = judge · 진단 · 비교 기준 = diagnostic)", comp, role)))
  sp <- tryCatch(list(v = fromJSON(file.path(X$root, cm$path), simplifyVector = FALSE), r = fromJSON(file.path(X$root, cr$path), simplifyVector = FALSE)),
                 error = function(e) list(error = conditionMessage(e)))
  if (!is.null(sp$error)) return(.p2_untested(out, paste("사양 읽기 실패:", sp$error)))
  ## ⑩ (a)(b) 구성 증거 — 분위 엔진 · 결합 칸 = 엔진 핀 · 사양 · 셀 로그 · 기저 적재 줄 · 워밍 · 템플릿 · months= / LV = P2R04 형식 + 엔진 핀 · 기저 적재 · months=
  Lv <- .p2_read_lines(opts[["log"]] %||% file.path(X$res, paste0(cm$code, ".log"))); Lr <- .p2_read_lines(opts[["log_rx0"]] %||% file.path(X$res, paste0(cr$code, ".log")))
  lv <- p2_parse_cell_log(Lv); lr <- p2_parse_cell_log(Lr)
  ec <- opts[["expect_cell"]] %||% cm$code; ecr <- opts[["expect_cell_rx0"]] %||% cr$code
  cs <- if (identical(comp, "LV")) p5_construction_lowvol(sp$v, sp$r, lv, lr, Lv, Lr, ctx, ec, ecr, opts[["expect_weight"]]) else
        p5_construction_dt(comp, sp$v, sp$r, lv, lr, Lv, Lr, ctx, ec, ecr)
  out$construction <- cs
  if (identical(comp, "LV")) out$device_factor <- P2R05_DIAGNOSTICS$LV$factor[c("kind", "id", "name")]
  out$cell_log_full_period <- list(variant = lv[intersect(names(lv), c("months", "rows"))], rx0 = lr[intersect(names(lr), c("months", "rows"))])
  if (!isTRUE(cs$ok)) return(.p2_untested(out, paste("구성 증거 불일치(⑩) —", cs$why)))
  ## 실효 시작 · 창(P2R04 그대로)
  dm <- X$env$E$ta_resolve_artifact(em$artifacts)$dir; dr <- X$env$E$ta_resolve_artifact(er$artifacts)$dir
  esm <- em$effective_start; esr <- er$effective_start
  out$effective_start <- list(variant = esm, rx0 = esr)
  if (!identical(esm$status, "ok") || !identical(esr$status, "ok"))
    return(.p2_untested(out, sprintf("실효 시작 상태 %s · %s", esm$status %||% "NA", esr$status %||% "NA")))
  common <- !is.null(opts[["force_start"]]) || !identical(esm$date, esr$date)
  W <- tryCatch({
    if (!common) list(sub = "original", window = "original", am = dm, ar = dr)
    else {
      cs0 <- if (!is.null(opts[["force_start"]])) as.Date(opts[["force_start"]]) else {
        late <- if (as.Date(esm$date) > as.Date(esr$date)) dm else dr
        min(as.Date(fread(file.path(late, "03_period_returns.csv"))$date)) }
      sub <- paste0("common_", format(cs0, "%Y%m%d")); base <- file.path(X$out, cm$code, sub)
      am <- file.path(base, "artifacts"); ar <- file.path(base, "rx0_artifacts")
      tr <- list(variant = p2_trim_artifacts(dm, am, cs0), rx0 = p2_trim_artifacts(dr, ar, cs0))
      .p2_mark_full(base, P2R05_FULL_MARK_PARENT)
      list(sub = sub, window = paste0("common_from_", format(cs0)), am = am, ar = ar, base = base, trim = tr, start = cs0)
    }
  }, error = function(e) list(error = conditionMessage(e)))
  if (!is.null(W$error)) return(.p2_untested(out, paste("공통 창 실패:", W$error)))
  out$window <- W$window; out$trim <- W$trim
  am <- W$am; ar <- W$ar
  ## ⑩(c) 전달량 — 보는 창 보유 ≠ RX0 보유인 리밸일 ≥ 1(판정 칸: 무처치 = 미시험 · 진단 칸: 같음도 그 진단의 답 — 계속) · V1 은 추가로 ≠ 같은 구성 Q50
  ov <- tryCatch(p2_holdings_overlap(.p2_read_holdings(am), .p2_read_holdings(ar), TAU), error = function(e) list(status = paste("오류:", conditionMessage(e))))
  out$holdings_overlap <- ov[setdiff(names(ov), "per_date")]
  out$holdings_overlap_per_date <- ov$per_date
  out$treatment_delivered <- p2_treatment_delivered(ov)
  if (!out$treatment_delivered && (!diag || !identical(ov$status, "ok")))
    return(.p2_untested(out, sprintf("무처치(⑩) — 보는 창 보유가 RX0 와 다른 보유일 %s/%s(보유 대조 %s)", format(ov$n_differ %||% NA), format(ov$n_dates %||% NA), ov$status %||% "NA")))
  if (identical(comp, "V1") && !diag) {
    q5 <- opts[["q50"]] %||% list(status = "not_applicable", why = "같은 구성 Q50 칸 없음")
    if (identical(q5$status, "not_applicable")) out$delivery_q50 <- list(status = "not_applicable", why = q5$why %||% "같은 구성 Q50 칸 없음")
    else if (!identical(q5$status, "ok")) return(.p2_untested(out, paste("V1 전달량(≠ Q50) 미측정 —", q5$why %||% "Q50 산출물 없음")))
    else {
      ovq <- tryCatch(p2_holdings_overlap(.p2_read_holdings(am), .p2_read_holdings(q5$dir), TAU), error = function(e) list(status = paste("오류:", conditionMessage(e))))
      out$delivery_q50 <- c(list(status = if (p2_treatment_delivered(ovq)) "ok" else "no_treatment", q50_cell = q5$cell %||% NA_character_), ovq[setdiff(names(ovq), "per_date")])
      if (!p2_treatment_delivered(ovq)) return(.p2_untested(out, sprintf("무처치(⑩ V1 = Q50) — 보는 창 보유가 Q50 와 다른 보유일 %s/%s(보유 대조 %s)",
                                                                       format(ovq$n_differ %||% NA), format(ovq$n_dates %||% NA), ovq$status %||% "NA")))
    }
  }
  ## 보는 창 패킷(P2R04 그대로)
  P <- tryCatch({
    if (!common) list(PM = p2_pk_read(X, cm$code), PRX = p2_pk_read(X, cr$code))
    else list(PM = p2_pk_build(X, cm$path, am, file.path(W$base, "visible")), PRX = p2_pk_build(X, cr$path, ar, file.path(W$base, "visible_rx0")))
  }, error = function(e) list(error = conditionMessage(e)))
  if (!is.null(P$error)) return(.p2_untested(out, paste("보는 창 패킷 실패:", P$error)))
  PM <- P$PM; PRX <- P$PRX
  if (is.null(PM) || is.null(PRX)) return(.p2_untested(out, "보는 창 패킷 없음"))
  if (identical(comp, "LV"))
    out$construction$factor_direction <- tryCatch(p2_direction_record(p2_parse_direction_lines(Lv), length(lv$factors), PM$window[[1]] %||% NA, TAU),
                                                  error = function(e) list(status = paste("오류:", conditionMessage(e))))
  ek <- paste(eng, W$sub)
  if (is.null(X$ea[[ek]])) assign(ek, tryCatch(p2_eng_alpha(X, ar), error = function(e) list(alpha_ann = NA_real_, t = NA_real_, n = NA_integer_, err = conditionMessage(e))), envir = X$ea)
  ea <- X$ea[[ek]]
  ## ① · ② 위기 짝 · 깊은 위기(P2R04 그대로)
  crm <- PM$behavior$crises %||% list(); crr <- PRX$behavior$crises %||% list()
  maj <- p2_crisis_majority(crm, crr, tol, "dd_capture")
  deep <- p2_deep_crisis_keys(crm, crr)
  dmj <- p2_crisis_majority(crm, crr, tol, "dd_capture", subset = deep)
  out$crisis_pairs <- list(n_pair = maj$n_pair, unpaired = maj$unpaired, n_deep = dmj$n_pair, deep_keys = deep)
  if (!identical(as.integer(maj$unpaired), 0L)) return(.p2_untested(out, sprintf("위기 짝 불일치 %s(같은 창이면 0)", format(maj$unpaired))))
  if (maj$n_pair < 2L || dmj$n_pair < 2L) return(.p2_untested(out, sprintf("판정 위기 짝 < 2(전체 %d · 깊은 %d)", maj$n_pair, dmj$n_pair)))
  fk <- tryCatch(p2_fast_crash_keys(fread(file.path(ar, "05_benchmark_returns.csv")), crr, as.integer(FS$fast_window_days), as.numeric(FS$fast_drop)),
                 error = function(e) list(keys = character(0), table = data.table(), unclassified = NA_character_, no_month_end = character(0), err = conditionMessage(e)))
  ## ③ · ④ β 짝 사본(P2R04 그대로) + 모든 위기 β 짝 승패(기록 · 위기 유형별 집계 입력)
  bm <- g(PM, "behavior.stats.beta"); br0 <- g(PRX, "behavior.stats.beta")
  bp <- p2_beta_plan(bm, br0, opts[["force_k"]]); k <- bp$k
  PB <- NULL; berr <- NULL
  if (identical(bp$mode, "unmeasured")) berr <- sprintf("k 비유한 또는 ≤ 0(%s)", format(k))
  else if (identical(bp$mode, "rx0")) PB <- PRX
  else PB <- tryCatch({
    bdir <- file.path(X$out, cm$code, W$sub, "rx0_beta_scaled")
    .p2_mark_full(file.path(X$out, cm$code, W$sub), P2R05_FULL_MARK_PARENT)
    p2_beta_scaled_copy(ar, bdir, k)
    p2_pk_build(X, cr$path, bdir, file.path(X$out, cm$code, W$sub, "visible_rx0_beta"))
  }, error = function(e) { berr <<- conditionMessage(e); NULL })
  cbp <- if (!is.null(PB)) PB$behavior$crises %||% list() else list()
  emp <- list(n_pair = 0L, share = NA_real_)
  b3 <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = deep) else emp
  b4 <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = fk$keys) else emp
  r3 <- if (!is.null(PB) && b3$n_pair >= 2L) p2_maj(b3$share, MAJ) else NA
  r4 <- if (!is.null(PB) && b4$n_pair >= 2L) p2_maj(b4$share, MAJ) else NA
  b4x <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = setdiff(fk$keys, fk$no_month_end)) else emp
  slow_keys <- if (nrow(fk$table)) fk$table[fast %in% FALSE, k] else character(0)
  bsl <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = slow_keys) else emp
  ball <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture") else emp
  ## ⑤ ~ ⑬(P2R04 그대로)
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
  alpha_degenerate <- diag && !isTRUE(out$treatment_delivered) && is.na(aok)
  out$alpha_degenerate <- alpha_degenerate
  if (any(!is.finite(inp)) || (is.na(aok) && !alpha_degenerate)) {
    out$inputs <- c(as.list(inp), list(alpha_t = pa$visible$t, engine_alpha = ea$alpha_ann, cycle_pairs = cyc$n_pair, bull_pairs = bs$n_pair))
    return(.p2_untested(out, sprintf("판정 입력 NA(%s)", paste(c(names(inp)[!is.finite(inp)], if (is.na(aok)) "alpha"), collapse = ","))))
  }
  Sm <- rk_S(cmv, ptm, FS); Sr <- rk_S(crv, ptr, FS)
  r12 <- if (Sr > 0) Sm >= Sr - as.numeric(FS$tie_eps) else cmv >= crv
  r13 <- mvb[1] <= mvb[2] && cdr[1] <= cdr[2]
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
    beta_all  = list(n_pair = ball$n_pair, n_better = ball$n_better %||% NA_integer_, share = ball$share, per_crisis = ball$per_crisis,
                     note = "기록 — 모든 짝 위기의 β 짝 승패(판정 아님 · 위기 유형별 집계 입력)"),
    beta_asym = list(beta = c(variant = bm, rx0 = br0), down = bdu[["down"]], up = bdu[["up"]], rx0_down = bdr[["down"]], rx0_up = bdr[["up"]],
                     ratio = r5d$ratio, ratio_rx0 = r5d$ratio_rx0, delta = r5d$delta, ok = isTRUE(r5),
                     level_ok = r5_level, claim_tag = if (isTRUE(r5_level)) NA_character_ else "노출(β) 방어 — 비대칭 역행(하락 β ≥ 상승 β) · 방어 주장 불가(헌장 빈칸 3 · 8)"),
    bull      = c(bs[setdiff(names(bs), "per_phase")], list(uc_median = ucm, uc_median_rx0 = ucr, uc_floor = FS$uc_floor, per_phase = bs$per_phase,
                                                            ok = p2_maj(bs$share, MAJ) && ucm >= as.numeric(FS$uc_floor))),
    cycle     = c(cyc[setdiff(names(cyc), "per_cycle")], list(per_cycle = cyc$per_cycle, ok = p2_maj(cyc$share, MAJ))),
    path      = list(mdd_vs_bench = mvb, cdar = cdr, ok = r13),
    construction = list(checks = cs$checks %||% cs$checks2, holdings_differ = ov$n_differ, holdings_dates = ov$n_dates,
                        delivery_q50 = out$delivery_q50$status %||% "not_applicable", ok = TRUE),
    selection = c(s14, list(share_beats_size_exposure = g(PM, "controls.attribution.share_beats_size_exposure"),
                            share_beats_exposure = g(PM, "controls.attribution.share_beats_exposure"),
                            n_crisis = g(PM, "controls.attribution.n_crisis"))))
  out$rules <- RL
  se <- if (is.finite(pa$visible$t) && pa$visible$t != 0) pa$visible$d_alpha / pa$visible$t else NA_real_
  mg <- as.numeric(FS$alpha_margin_frac) * max(ea$alpha_ann, 0)
  out$alpha_non_loss <- list(d_alpha = pa$visible$d_alpha, t = pa$visible$t, se = se, n = pa$visible$n, window = pa$visible$window, engine_alpha = ea,
                             t_floor = FS$alpha_t_floor, margin_frac = FS$alpha_margin_frac, margin = mg,
                             margin_over_se = if (is.finite(se) && se > 0) mg / se else NA_real_, ok = isTRUE(aok))
  out$alpha_test_window <- pa$test
  out$non_inferiority <- list(S = Sm, S_rx0 = Sr, calmar = cmv, calmar_rx0 = crv, port_t = ptm, port_t_rx0 = ptr,
                              sharpe = g(PM, "performance.strategy.sharpe"), sharpe_rx0 = g(PRX, "performance.strategy.sharpe"),
                              basis = if (Sr > 0) "S_vis − tie_eps" else "Calmar(S_rx0 = 0)", ok = isTRUE(r12))
  tl <- p2_top_loss(PM$exposure$top_losers %||% list(), deep_peaks, as.numeric(FS$single_name_loss_floor))
  tl0 <- p2_top_loss(PRX$exposure$top_losers %||% list(), deep_peaks, as.numeric(FS$single_name_loss_floor))
  conc <- tryCatch(rk_concentration(am, TAU), error = function(e) list(visible = list(error = conditionMessage(e))))
  cst <- p2_conc_status(tl)
  out$concentration <- list(status = cst, visible = conc$visible, eff_n_mean = c(g(PM, "profile.eff_n_mean"), g(PRX, "profile.eff_n_mean")),
                            top_loss = tl[setdiff(names(tl), "per_crisis")], top_loss_rx0 = tl0[setdiff(names(tl0), "per_crisis")], per_crisis = tl$per_crisis,
                            concentration_loss_tag = identical(cst, "breach"), unmeasured_tag = identical(cst, "unmeasured"))
  out$recovery <- p2_recovery_tag(crm, crr, MAJ)
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
  out$record <- list(state_unturned_max_drop = p2_crisis_record(crm, crr, cbp, FS$state_unturned_max_drop_crises, tol, deep, fk$keys),
                     size_decile = p2_size_compare(PM$exposure$by_size_decile %||% list(), PRX$exposure$by_size_decile %||% list(), deep_peaks),
                     rolling = PM$behavior$rolling, turnover_annual = c(variant = g(PM, "profile.turnover_annual"), rx0 = g(PRX, "profile.turnover_annual")),
                     cost_drag_annual = c(variant = g(PM, "profile.cost_drag_annual"), rx0 = g(PRX, "profile.cost_drag_annual")),
                     exposure_mean = c(variant = g(PM, "controls.exposure_profile.mean"), rx0 = g(PRX, "controls.exposure_profile.mean")),
                     crisis_dd_capture_median = c(variant = g(PM, "behavior.summary.crisis_dd_capture_median"), rx0 = g(PRX, "behavior.summary.crisis_dd_capture_median")))
  ## 판정 칸만 — 크기 × β 짝 · 유동성 귀속 · 국면 월 차이(P2R04) + Dimson β 짝 판(철학 P2 R-20261018-006 N-⑥ · 기록)
  ## 유동성 귀속 — 판정 칸 + 진단 Q50 · S1 · S2(위기 보유 유동성 십분위를 V · S · Q50 · RX0 나란히 — 철학 P1 R-20261018-008 C-069)
  if (!diag || comp %in% c("Q50", "S1", "S2"))
    out$liquidity <- tryCatch(list(variant = p2_liquidity_record(X, am, crm, deep_peaks), rx0 = p2_liquidity_record(X, ar, crr, deep_peaks)),
                              error = function(e) list(status = "unmeasured", tag = "유동성 귀속 미측정", why = conditionMessage(e)))
  if (!diag) {
    out$size_beta <- tryCatch(p2_size_beta_record(X, am, PM, crm, deep, tol, MAJ),
                              error = function(e) list(status = "unmeasured", tag = "크기 × β 짝 미측정", why = conditionMessage(e)))
    out$regime_months <- tryCatch(p2_regime_months(X, am, ar, PM), error = function(e) list(status = "unmeasured", why = conditionMessage(e)))
    ## 같은 추첨 판독(철학 P1 C-063 · 기록) — 같은 구성 Q50 칸이 있을 때만(E3 = 해당 없음)
    q5 <- opts[["q50"]] %||% list(status = "not_applicable", why = "같은 구성 Q50 칸 없음")
    out$same_draw <- if (!identical(q5$status, "ok")) list(status = if (identical(q5$status, "not_applicable")) "not_applicable" else "unmeasured", why = q5$why %||% "Q50 산출물 없음") else
      tryCatch({
        qdir <- q5$dir
        if (common) { qdir <- file.path(W$base, "q50_artifacts"); p2_trim_artifacts(q5$dir, qdir, W$start) }
        PQ <- if (!common) p2_pk_read(X, q5$cell) else p2_pk_build(X, q5$path, qdir, file.path(W$base, "visible_q50"))
        if (is.null(PQ)) stop("Q50 보는 창 패킷 없음")
        sdp <- p5_same_draw_plan(PM, PQ, PRX)
        PQB <- if (identical(sdp$mode, "rx0")) PQ else if (identical(sdp$mode, "scaled")) {
          qb <- file.path(X$out, cm$code, W$sub, "q50_beta_scaled"); .p2_mark_full(file.path(X$out, cm$code, W$sub), P2R05_FULL_MARK_PARENT)
          p2_beta_scaled_copy(qdir, qb, sdp$k); p2_pk_build(X, q5$path, qb, file.path(X$out, cm$code, W$sub, "visible_q50_beta")) } else NULL
        core <- p5_same_draw_core(PM, PQ, PQB, deep, fk$keys, tol, MAJ, as.numeric(FS$bull_ratio), as.numeric(FS$uc_floor))
        pq <- tryCatch(rk_pair_alpha(X$env$E, am, qdir, TAU)$visible, error = function(e) list(d_alpha = NA_real_, t = NA_real_, err = conditionMessage(e)))
        ovq <- tryCatch(p2_holdings_overlap(.p2_read_holdings(am), .p2_read_holdings(qdir), TAU), error = function(e) list(status = paste("오류:", conditionMessage(e))))
        c(list(status = "ok", q50_cell = q5$cell %||% NA_character_), sdp, core,
          list(alpha_vs_q50 = pq[intersect(names(pq), c("d_alpha", "t", "n", "window"))], holdings_overlap_vs_q50 = ovq[setdiff(names(ovq), "per_date")],
               rule = "같은 추첨 판독 — k' = β(변형)/β(Q50) · Q50 × k' 현금 사본(k' ≥ 1 = Q50) · 깊은 위기 · 빠른 급락 · ⑤ Δ · ⑥ · ⑦ 를 V − Q50 로(기록 · 판정 아님)"))
      }, error = function(e) list(status = "unmeasured", why = conditionMessage(e)))
    out$dimson <- tryCatch({
      dv <- p5_dimson_from(X$env$E, am, TAU); drx <- p5_dimson_from(X$env$E, ar, TAU)
      bd <- p2_beta_plan(dv$beta, drx$beta)
      PD <- if (identical(bd$mode, "rx0")) PRX else if (identical(bd$mode, "scaled")) {
        ddir <- file.path(X$out, cm$code, W$sub, "rx0_dimson_scaled")
        .p2_mark_full(file.path(X$out, cm$code, W$sub), P2R05_FULL_MARK_PARENT)
        p2_beta_scaled_copy(ar, ddir, bd$k)
        p2_pk_build(X, cr$path, ddir, file.path(X$out, cm$code, W$sub, "visible_rx0_dimson"))
      } else NULL
      cdp <- if (!is.null(PD)) PD$behavior$crises %||% list() else list()
      d3 <- if (!is.null(PD)) p2_crisis_majority(crm, cdp, tol, "dd_capture", subset = deep) else emp
      d4 <- if (!is.null(PD)) p2_crisis_majority(crm, cdp, tol, "dd_capture", subset = fk$keys) else emp
      list(status = if (is.null(PD)) "unmeasured" else "ok", beta_dimson_variant = dv$beta, beta_dimson_rx0 = drx$beta, coef_variant = dv$coef, coef_rx0 = drx$coef,
           n_days = c(variant = dv$n, rx0 = drx$n), k = k, k_dimson = bd$k, comparator = bd$comparator,
           deep = list(n_pair = d3$n_pair, share = d3$share, majority = if (d3$n_pair >= 2L) p2_maj(d3$share, MAJ) else NA, per_crisis = d3$per_crisis),
           fast = list(n_pair = d4$n_pair, share = d4$share, majority = if (d4$n_pair >= 2L) p2_maj(d4$share, MAJ) else NA, per_crisis = d4$per_crisis),
           rule = "Dimson β = 보는 창 일수익 ret_net ~ 벤치 일수익 lag −1 · 0 · +1 계수 합(Dimson 1979 JFE 7(2)) · k_D = β_D(변형)/β_D(RX0) · 기록 — 판정 아님")
    }, error = function(e) list(status = "unmeasured", why = conditionMessage(e)))
  }
  tail_ok <- if (p5_tail_applicable(comp)) isTRUE(opts[["tail_ok"]]) else TRUE
  out$flags <- list(r3 = r3, r4 = r4, crisis = isTRUE(RL$crisis$ok), deep = isTRUE(RL$deep$ok), level = r5_level, beta_ratio = isTRUE(r5),
                    s14 = isTRUE(s14$ok), s14_measured = isTRUE(s14$measured),
                    sb_ok = out$size_beta$ok %||% NA, sb_status = out$size_beta$status %||% (if (diag) "skipped_diagnostic" else "unmeasured"),
                    strength = list(bull = isTRUE(RL$bull$ok), alpha = isTRUE(aok), cycle = isTRUE(RL$cycle$ok), S = isTRUE(r12), path = isTRUE(r13)), tail = tail_ok,
                    sharpe_up = isTRUE(out$non_inferiority$sharpe > out$non_inferiority$sharpe_rx0))
  out$conclusion_name <- p2_defense_name(r3, r4, r5_level, s14$ok, out$size_beta$ok %||% NA, out$flags$sb_status, s14_measured = isTRUE(s14$measured))
  out$margins <- p5_margins(RL, opts[["tail"]] %||% list(), MAJ, tol)
  out$pass <- p2_cell_pass(list(crisis = RL$crisis$ok, deep = RL$deep$ok, beta_deep = r3, fast = r4, beta_ratio = r5, bull = RL$bull$ok, alpha = aok,
                                cycle = RL$cycle$ok, construction = RL$construction$ok, S = r12, path = r13, selection = s14$ok, tail = tail_ok))
  out$verdict <- p2_cell_verdict(list(pass = out$pass, beta_unmeasured = !is.null(berr), beta_deep = r3, fast = r4, crisis = RL$crisis$ok, deep = RL$deep$ok,
                                      selection = s14$ok, selection_measured = isTRUE(s14$measured), level = r5_level, beta_ratio = isTRUE(r5),
                                      strength = out$flags$strength, tail = tail_ok))
  out$verdict_name <- P2R05_VERDICT_NAMES[[out$verdict]]
  out$tested <- TRUE; out$rules_computed <- TRUE
  out$tbl <- data.table(engine = eng, device = comp, tested = TRUE, pass = out$pass, excluded = !identical(cst, "clear"), verdict = out$verdict)
  out
}
p5_eval_pair_safe <- function(X, eng, comp, cm, cr, em, er, opts = list())
  tryCatch(p5_eval_pair(X, eng, comp, cm, cr, em, er, opts),
           error = function(e) .p2_untested(list(engine = eng, device = comp, role = opts[["role"]] %||% "judge", cell = cm$code, rx0 = cr$code,
                                                 status = em$status %||% NA, status_rx0 = er$status %||% NA, rules_computed = FALSE), paste("평가 오류:", conditionMessage(e))))
## ⑮ 시험 조건 — 변형 칸이 판정됐는데 꼬리 계기가 미달 · 미측정이면 '미시험(꼬리 계기)'(판정 계산은 기록으로 남는다 · rules_computed 유지)
p5_apply_tail_gate <- function(x, tail) {
  x$tail_gate <- list(status = tail$status %||% "unmeasured", t = tail$t %||% NA_real_, t_min = tail$t_min %||% NA_real_, pass = isTRUE(tail$pass),
                      margin = tail$margin %||% NA_real_, why = tail$why %||% NA_character_)
  if (!isTRUE(x$tested) || isTRUE(tail$pass)) return(x)
  why <- if (identical(tail$status, "ok")) sprintf("미시험(꼬리 계기 ⑮ 미달 — NW t %s ≤ %s) · 원천 ① 반증 아님", format(signif(tail$t, 4)), format(tail$t_min)) else
         paste0("미시험(꼬리 계기 ⑮ 미측정 — ", tail$why %||% "사유 없음", ") · 원천 ① 반증 아님")
  x$tested <- FALSE; x$pass <- FALSE; x$verdict <- "untested_tail_instrument"; x$verdict_name <- P2R05_VERDICT_NAMES[["untested_tail_instrument"]]; x$why <- why
  x$tbl <- data.table(engine = x$engine, device = x$device, tested = FALSE, pass = FALSE, excluded = isTRUE(x$tbl$excluded), verdict = "untested_tail_instrument")
  x
}
## 평가 센티널(P2R04 형식 한 줄) · 평가 중단 기록
p5_sentinel_write <- function(path, status, rc, extra = "") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(sprintf("status=%s rc=%d at=%s%s", status, as.integer(rc), format(Sys.time(), "%Y-%m-%d %H:%M:%S"), if (nzchar(extra)) paste0(" ", extra) else ""), path, useBytes = TRUE)
  invisible(path)
}
p5_measured_ok <- function(res, cells) {
  ok <- vapply(cells, function(z) { j <- file.path(res, paste0(z$code, ".json")); file.exists(j) && isTRUE(tryCatch(fromJSON(j)$ok, error = function(e) FALSE)) }, logical(1))
  sprintf("ok=%d/%d", sum(ok), length(cells))
}

## ── 본 실행(스크립트로 불렸을 때만 — 픽스처 · 리허설 · precheck 는 위 함수만 적재) ──────────────────────────────────────
.p5_main <- function(CELLS_ONLY, RD, PR, RES) {
  source("02_Infrastructure/contracts/diagnosis_packet.R")
  source("02_Infrastructure/contracts/matched_controls.R")
  source("02_Infrastructure/contracts/beta_controlled_alpha.R")
  source("02_Infrastructure/programs/program_registry.R")
  source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
  if (!file.exists(PR)) stop("[P2R05 평가] 사전등록 없음 — 평가하지 않는다(R2)")
  reg <- pr_load(ROOT); rr <- Filter(function(r) identical(r$round_id, P2R05_ROUND_ID), pr_get(reg, "P2_DEFENSE")$rounds)
  if (!length(rr) || !identical(rr[[1]]$prereg_md5, rk_md5(PR))) stop("[P2R05 평가] 사전등록 md5 불일치(R2)")
  pre <- fromJSON(PR, simplifyVector = FALSE)
  if (!identical(pre$round_id, P2R05_ROUND_ID)) stop("[P2R05 평가] 사전등록 round_id ≠ ", P2R05_ROUND_ID)
  BCFG <- file.path(ROOT, pre$behavior_card_cfg$path)
  if (!identical(rk_md5(BCFG), pre$behavior_card_cfg$md5)) stop("[P2R05 평가] 행동 카드 설정 사본 변경")
  pin <- p2_pin_mismatches(pre, ROOT)
  if (length(pin)) stop("[P2R05 평가] 핀 불일치 — 평가하지 않는다:\n", paste0("  · ", pin, collapse = "\n"))
  pc <- file.path(RD, "results", "precheck.json")
  if (!file.exists(pc) || !isTRUE(fromJSON(pc)$ok)) stop("[P2R05 평가] precheck 통과 기록이 없다 — 측정 조건 미확인")
  TAU <- as.Date(pre$tau_d); FS <- pre$final_selection_rule
  fsm <- p2_fs_missing(FS); if (length(fsm)) stop("[P2R05 평가] final_selection_rule 키 결손 — 평가하지 않는다: ", paste(fsm, collapse = ","))
  cbad <- p2_cells_check(pre$cells); if (length(cbad)) stop("[P2R05 평가] 사전등록 칸 목록 불일치:\n", paste0("  · ", cbad, collapse = "\n"))
  env <- new.env(); env$E <- .dp_deps(ROOT); env$BCFG_L <- env$E$bc_cfg(ROOT, path = BCFG); env$raw <- NULL; env$liq <- NULL
  CELLS <- if (CELLS_ONLY) rk_shard(pre$cells) else pre$cells
  EVS <- lapply(CELLS, function(cl) p2_eval_cell(ROOT, RES, cl, env, TAU)); names(EVS) <- vapply(CELLS, function(z) z$code, character(1))
  for (cd in names(EVS)) if (!is.null(EVS[[cd]]$artifacts)) {
    rj <- file.path(RES, paste0(cd, ".json"))
    a0 <- if (file.exists(rj)) fromJSON(rj, simplifyVector = FALSE)$artifacts else NULL
    if (!identical(EVS[[cd]]$artifacts, a0)) stop(sprintf("[P2R05 평가] %s 칸 평가 캐시의 산출물 ≠ 현 측정 산출물 — results/%s/ 를 지우고 다시 평가", cd, cd))
  }
  cat(sprintf("[P2R05 평가] 칸 평가 %d/%d(진단 · 비교 기준 칸 포함)\n", sum(vapply(EVS, function(e) e$status %in% c("evaluated", "axis_violation"), logical(1))), length(EVS)))
  if (CELLS_ONLY) return(invisible(list(cells_only = TRUE)))

  JCELLS <- Filter(function(z) !isTRUE(z$diagnostic), pre$cells); DCELLS <- Filter(function(z) isTRUE(z$diagnostic), pre$cells)
  cell_of <- function(eng, comp) { z <- Filter(function(c0) identical(c0$engine, eng) && identical(c0$component, comp), pre$cells); if (length(z)) z[[1]] else NULL }
  dfr <- Filter(function(cl) { j <- file.path(RES, paste0(cl$code, ".json")); if (!file.exists(j)) return(FALSE)
                               r <- fromJSON(j, simplifyVector = FALSE); !isTRUE(r$ok) && !is.null(r$deferred) }, JCELLS)
  if (length(dfr)) stop("[P2R05 평가] 측정 연기 칸 — 재측정(measure.sh) 뒤 평가: ", paste(vapply(dfr, function(z) z$code, ""), collapse = ","))
  fp_of <- function(code, tag) { f <- file.path(RES, sprintf("%s.fp_%s", code, tag)); if (file.exists(f)) paste(readLines(f, warn = FALSE), collapse = "|") else NA_character_ }
  FP_EVAL <- p2_fingerprint(RD, "equality")
  X <- list(root = ROOT, res = RES, out = RES, env = env, fs = FS, tau = TAU, ea = new.env())
  ENGINES <- unique(vapply(JCELLS, function(z) z$engine, character(1)))
  RULES <- names(P2R05_RULES)
  FPG <- list()
  for (eng in ENGINES) {
    codes <- unname(c(vapply(RULES, function(rk) cell_of(eng, rk)$code, character(1)), cell_of(eng, "RX0")$code))
    fps <- unname(unlist(lapply(codes, function(cd) c(fp_of(cd, "start"), fp_of(cd, "end")))))
    if (anyNA(fps) || length(unique(fps)) != 1L) stop(sprintf("[P2R05 평가] %s 묶음 데이터 지문 불일치 또는 부재 — 그 묶음을 재측정한 뒤 평가(rules.vintage_group)", eng))
    FPG[[eng]] <- list(measure = fps[1], eval_matches_measure = p2_fp_same(fps[1], FP_EVAL))
  }
  fp_ok_diag <- function(cl) { fpd <- c(fp_of(cl$code, "start"), fp_of(cl$code, "end")); !anyNA(fpd) && !is.null(FPG[[cl$engine]]) && all(fpd == FPG[[cl$engine]]$measure) }
  ## ── 라운드 구성 맥락(⑩) — 워밍 센티널 · 템플릿 차분 대조(평가 때 다시 실행) · 분위 엔진 파일 목록
  WARM <- p5_warm_resolve(RES, file.path(ROOT, P2R05_WARM_SENTINEL))             # 측정에 묶인 사본 우선 · 두 판 다름 = '센티널 판본 다름'(Q 10-18 정렬 2)
  TEMPL <- p5_template_check(ROOT)
  DTF <- p5_dt_engine_files(pre$cells, ROOT)                                    # 분위 엔진 파일만(재시드 짝 제외)
  cat(sprintf("[P2R05 평가] 워밍 센티널 %s · 템플릿 차분 대조 %s(rc %s) · 분위 엔진 파일 %d\n", WARM$status, TEMPL$status, format(TEMPL$rc), length(DTF)))
  ## ── ⑮ 꼬리 계기 · 꼬리 기록(보는 창 — RAWDATA · 예측표를 τ_D 에서 먼저 자른다) ─────
  NW <- p5_nw_fun(ROOT)
  YD <- p5_ydef_check(DTF, ROOT)
  QP <- p5_qpred_bound(ROOT, WARM, TAU)                                           # 측정에 묶인 판 1개(필수 4) · md5 불일치 = 평가 중단 · 미묶임 = ⑮ 미측정
  QLOG <- if (identical(QP$status, "ok")) p5_qpred_log_check(pre$cells, RES, ROOT, QP$bound) else list(status = "not_applicable", why = QP$why %||% "예측표 없음", per_cell = data.table())
  cat(sprintf("[P2R05 평가] 셀 로그 예측표 대조 %s — 같음 %s · 연쇄 %s · 대조 불가 %s · 셀 로그 없음 %s\n", QLOG$status, format(QLOG$n_match %||% NA), format(QLOG$n_chained %||% NA),
              format(QLOG$n_unverifiable %||% NA), format(QLOG$n_no_log %||% NA)))
  rcols <- tryCatch(arrow::ParquetFileReader$create(file.path(ROOT, P2R05_RAWDATA))$GetSchema()$names, error = function(e) NULL)
  want <- c("Date", "Ticker", "Open", "Close", "Vol", "Size", "Ret"); want <- if (is.null(rcols)) want else intersect(want, rcols)   # Ret = 유동성 귀속 일수익 재구성(철학 P4 C-076)
  RAWF <- as.data.table(arrow::read_parquet(file.path(ROOT, P2R05_RAWDATA), col_select = tidyselect::all_of(want)))
  if (!inherits(RAWF$Date, "Date")) RAWF[, Date := as.Date(Date)]
  RAWF[, Ticker := as.character(Ticker)]
  RAWV <- p5_visible_cut(RAWF, TAU)
  env$liq <- p5_liq_from(RAWV)
  ## 유동성 구간별 위기 손익 귀속(철학 P4 C-076 · 기록 · 보는 창 RAW · 실패 = 그 기록만 '유동성 귀속 미측정')
  LQA <- tryCatch(p5_liq_attr_round(X, EVS, pre$cells, ENGINES, RAWV, FS, TAU),
                  error = function(e) setNames(lapply(ENGINES, function(eng) list(status = "unmeasured", why = conditionMessage(e), tags = "유동성 귀속 미측정")), ENGINES))
  cat(sprintf("[P2R05 평가] 유동성 3분위 귀속 %s\n", paste(vapply(names(LQA), function(e) sprintf("%s:%s", e, LQA[[e]]$status %||% "-"), ""), collapse = " ")))
  cr_e2 <- cell_of(P2R05_DIAG_ENGINE, "RX0"); pk_e2 <- if (!is.null(cr_e2)) p2_pk_read(X, cr_e2$code) else NULL
  crr0 <- pk_e2$behavior$crises %||% list(); DEEP0 <- p2_deep_crisis_keys(crr0, crr0)
  CR0 <- .p2_rows_dt(crr0); if (nrow(CR0)) CR0[, k := .p2_key(CR0)]
  DEEP_YM <- if (nrow(CR0)) unique(unlist(lapply(which(CR0$k %in% DEEP0), function(i) .p2_months(as.character(CR0$peak_date[i]), as.character(CR0$trough_date[i]))))) else character(0)
  spec_v1 <- tryCatch(fromJSON(file.path(ROOT, cell_of(P2R05_DIAG_ENGINE, "V1")$path), simplifyVector = FALSE), error = function(e) list())
  PRM <- list(veto_share = YD$veto_share, n_max = as.integer(spec_v1$fixed_axes$n_max %||% NA), liq_min = as.numeric(spec_v1$fixed_axes$liq_adv20_min %||% NA),
              n_bins = YD$quint, liq = env$liq)
  TAILV <- p5_tail_block(if (identical(QP$status, "ok")) QP$Qv else NULL, RAWV, YD, FS$tail_instrument, NW, PRM, DEEP_YM, "visible")
  if (QP$status %in% c("absent", "unbound")) TAILV$instrument <- list(status = "unmeasured", why = QP$why, pass = FALSE)
  rm(RAWV); gc(verbose = FALSE)                                                  # 보는 창 사본은 여기까지(유동성 패널 env$liq 은 남긴다)
  ## 사람 쪽 판(전 구간 · 시험 창 포함 — evaluation_full.json 전용 · 판정 · 선택 입력 아님)
  TAILF <- if (identical(QP$status, "ok") && !is.null(QP$Qall)) tryCatch({
    LIQF <- p5_liq_from(RAWF); PRMF <- PRM; PRMF$liq <- LIQF
    TF <- p5_tail_block(QP$Qall, RAWF, YD, FS$tail_instrument, NW, PRMF, DEEP_YM, "full")
    TF$test_window <- tryCatch({ Qt <- QP$Qall[Date >= .p5_month_floor(TAU)]; Tt <- p5_tail_block(Qt, RAWF, YD, FS$tail_instrument, NW, PRMF, character(0), "test")
                                 list(instrument = Tt$instrument[setdiff(names(Tt$instrument), "per_date")], hits = Tt$records$hits, r1 = Tt$records$r1) },
                               error = function(e) list(status = "error", why = conditionMessage(e)))
    TF$SP <- NULL; rm(LIQF); TF }, error = function(e) list(status = "error", why = conditionMessage(e))) else list(status = QP$full_status %||% QP$status, why = QP$why %||% "시험 창 예측표 판본 불일치")
  rm(RAWF); gc(verbose = FALSE)
  TI <- TAILV$instrument
  cat(sprintf("[P2R05 평가] ⑮ 꼬리 계기 %s — NW t %s(> %s) · 신호일 %s · 표적 정의 대조 %s · 예측표 %s(%s개)\n", if (isTRUE(TI$pass)) "통과" else "미달 · 미측정",
              format(signif(TI$t %||% NA_real_, 4)), format(TI$t_min %||% NA), format(TI$n_dates %||% NA), if (isTRUE(YD$ok)) "ok" else "실패", QP$status, format(QP$n_files %||% 0L)))
  CTX <- list(pre = pre, root = ROOT, warm = WARM, template = TEMPL,
              tail_d = if (is.list(TAILV$records$crossing)) TAILV$records$crossing[setdiff(names(TAILV$records$crossing), character(0))] else list(status = "unmeasured"))
  Q50INFO <- setNames(lapply(ENGINES, function(eng) {
    qc <- cell_of(eng, "Q50")
    if (is.null(qc)) return(list(status = "not_applicable", why = "같은 구성 Q50 칸 없음(진단 칸 = E2)"))
    ev <- EVS[[qc$code]]
    if (!identical(ev$status, "evaluated")) return(list(status = "unmeasured", why = sprintf("Q50 칸 평가 상태 %s", ev$status %||% "NA"), cell = qc$code))
    if (!fp_ok_diag(qc)) return(list(status = "unmeasured", why = "Q50 지문 ≠ 구성 판정 칸 지문(또는 부재)", cell = qc$code))
    list(status = "ok", dir = env$E$ta_resolve_artifact(ev$artifacts)$dir, cell = qc$code, path = qc$path)
  }), ENGINES)
  OUT <- list(); TBL <- list()
  for (eng in ENGINES) {
    cr <- cell_of(eng, "RX0")
    for (rk in RULES) {
      cm <- cell_of(eng, rk)
      od <- p5_eval_pair_safe(X, eng, rk, cm, cr, EVS[[cm$code]], EVS[[cr$code]],
                              opts = list(role = "judge", ctx = CTX, tail_ok = isTRUE(TI$pass), tail = TI, q50 = Q50INFO[[eng]]))   # q50 = V1 전달량(⑩) · 같은 추첨 판독(V1 · V2)
      od <- p5_apply_tail_gate(od, TI)
      TBL[[cm$code]] <- od$tbl; OUT[[cm$code]] <- od
    }
  }
  LVW <- p5_lv_expect_weight(pre$cells, ROOT)
  DOUT <- list()
  for (cl in DCELLS) {
    cr <- cell_of(cl$engine, "RX0")
    DOUT[[cl$code]] <- if (!fp_ok_diag(cl))
      .p2_untested(list(engine = cl$engine, device = cl$component, role = "diagnostic", cell = cl$code, rx0 = cr$code, rules_computed = FALSE), "진단 · 비교 기준 칸 데이터 지문 ≠ 구성 묶음 지문(또는 부재)") else
      p5_eval_pair_safe(X, cl$engine, cl$component, cl, cr, EVS[[cl$code]], EVS[[cr$code]],
                        opts = list(role = "diagnostic", ctx = CTX, tail_ok = isTRUE(TI$pass), tail = TI, expect_weight = if (identical(cl$component, "LV")) LVW else NULL))
    if (p5_tail_applicable(cl$component)) DOUT[[cl$code]] <- p5_apply_tail_gate(DOUT[[cl$code]], TI)   # W2(⑮ 적용 진단 칸)도 ⑮ 미달 = 미시험(계기)이 먼저(필수 1)
  }
  .safe_rec <- function(expr) tryCatch(expr, error = function(e) list(status = "error", why = conditionMessage(e)))
  ## 셀 로그 예측표 대조를 칸에 싣는다(격리 점검 v2 필수 1 — 대조 불가 = 결론 꼬리표 · ⑮ 판정 유지)
  qlog_of <- function(cd) { z <- as.data.table(QLOG$per_cell %||% data.table()); if (nrow(z) && cd %in% z$code) as.list(z[z$code == cd][1]) else list(status = "not_applicable") }
  for (nm in names(OUT)) OUT[[nm]]$qpred_log <- qlog_of(OUT[[nm]]$cell %||% nm)
  for (nm in names(DOUT)) DOUT[[nm]]$qpred_log <- qlog_of(DOUT[[nm]]$cell %||% nm)
  ## 유동성 귀속을 칸에 싣는다 — 판정 칸 = 결론 꼬리표 입력(liq_attr) · 모든 칸 = 기록(record$liquidity_tercile)
  for (nm in names(OUT)) { x <- OUT[[nm]]
    OUT[[nm]]$liq_attr <- p5_liq_attr_for(LQA, x$engine, x$device); OUT[[nm]]$record$liquidity_tercile <- LQA[[x$engine]]$per_cell[[x$device]] %||% list(status = "absent") }
  for (nm in names(DOUT)) { x <- DOUT[[nm]]
    DOUT[[nm]]$liq_attr <- p5_liq_attr_for(LQA, x$engine, x$device); DOUT[[nm]]$record$liquidity_tercile <- LQA[[x$engine]]$per_cell[[x$device]] %||% list(status = "absent") }
  TOL <- as.numeric(FS$crisis_improve_min)
  TINC <- p5_tail_increment(TAILV$records$d_sigma, TAILV$records$d_width, TAILV$records$d_hist, as.numeric(FS$tail_instrument$t_min))   # 꼬리 증분(D^σ ∧ D^w ∧ D^H)
  READ <- .safe_rec(p5_readings(OUT, DOUT, TOL, TINC, as.numeric(FS$tail_instrument$t_min), RULES))
  ## 시드 띠 · 시드 미결 꼬리표(판단 T1 C-054 · 판정은 바뀌지 않는다) — 같은 구성 재시드 칸(RX0S)
  BAND <- setNames(lapply(ENGINES, function(eng) .safe_rec({ rs <- Filter(function(x) identical(x$engine, eng) && identical(x$device, "RX0S"), DOUT)
    p5_seed_band(if (length(rs)) rs[[1]] else list(rules_computed = FALSE, rules = list(), why = "재시드 칸 없음")) })), ENGINES)
  for (nm in names(OUT)) OUT[[nm]]$seed_tags <- .safe_rec(p5_seed_tags(OUT[[nm]], BAND[[OUT[[nm]]$engine]] %||% list(status = "unmeasured", why = "구성 없음")))
  ## 위기 유형별 β 짝 승패(기록 · 판정 · 선택에 쓰지 않는다) — crisis_type_classify.json(Q) · onset_state_classify.json(시작 시점 분류 기록)
  CT <- .safe_rec(p5_load_crisis_types(ROOT, pre)); CO <- .safe_rec(p5_load_onset(ROOT, pre))
  ctr <- function(x, CL) .safe_rec(p5_crisis_type_record(x$rules$beta_all$per_crisis, CL, x$rules$deep$deep_keys, TOL,
                                                          decomp = x$rules$selection$decomposition$per_crisis, beta_delta = x$rules$beta_asym$delta %||% NA_real_))
  for (nm in names(OUT)) { x <- OUT[[nm]]; if (isTRUE(x$rules_computed)) { OUT[[nm]]$record$crisis_type <- ctr(x, CT); OUT[[nm]]$record$crisis_onset <- ctr(x, CO) } }
  for (nm in names(DOUT)) { x <- DOUT[[nm]]; if (isTRUE(x$rules_computed)) { DOUT[[nm]]$record$crisis_type <- ctr(x, CT); DOUT[[nm]]$record$crisis_onset <- ctr(x, CO) } }
  ## 칸별 예측표 기록 — 예측 비대칭 보유 평균(V · RX0 · 진단) · E2 보유 ↔ 예측표 재현(규칙 칸)
  QV <- if (identical(QP$status, "ok")) QP$Qv else NULL
  HREC <- setNames(lapply(pre$cells, function(cl) .safe_rec({
    ev <- EVS[[cl$code]]
    if (is.null(QV) || !identical(ev$status, "evaluated")) list(status = "unmeasured") else {
      H <- .p2_read_holdings(env$E$ta_resolve_artifact(ev$artifacts)$dir)
      rp <- if (identical(cl$engine, P2R05_DIAG_ENGINE) && cl$component %in% c("V1", "V2", "Q50", "N1", "N2", "S1", "S2") && !is.null(TAILV$SP))
              p5_reproduce(QV, TAILV$SP, H, cl$component, PRM, TAU) else list(status = "not_applicable")
      list(status = "ok", kelley = p5_kelley_hold(QV, H, TAU), reproduce = rp) }
  })), vapply(pre$cells, function(z) z$code, character(1)))
  GV3 <- .safe_rec(list(th = env$E$gv3_thresholds(ROOT), cfg = env$E$gv3_cfg(ROOT)))
  ADIST <- setNames(lapply(names(EVS), function(cd) .safe_rec({
    pk <- p2_pk_read(X, cd)
    if (is.null(pk)) list(status = "no_packet") else if (identical(GV3$status, "error")) list(status = "unmeasured", why = GV3$why) else {
      S <- env$E$gv3_S(rk_getf(pk, "performance.strategy.calmar"), rk_getf(pk, "performance.strategy.port_t"), GV3$th, GV3$cfg$weights)
      c(list(status = "ok", window = unlist(pk$window)), p2_a_distance(pk$performance$strategy, rk_getf(pk, "performance.benchmark.calmar"), GV3$th, S, GV3$cfg$a_boundary)) }
  })), names(EVS))
  RXI <- setNames(lapply(ENGINES, function(eng) tryCatch(p2_rx0_identity(X, EVS[[cell_of(eng, "RX0")$code]]$artifacts, file.path(ROOT, sprintf(P2R05_P2R04_RX0, eng))),
                                                        error = function(e) list(status = paste("오류:", conditionMessage(e))))), ENGINES)
  ## LV ↔ P2R04 W2 동일성(판단 T1 C-058 · 기록 — 같은 배치면 동일 · 판본이 바뀌었으면 다름)
  LVI <- setNames(lapply(ENGINES, function(eng) tryCatch({ lc <- cell_of(eng, "LV")
    if (is.null(lc) || is.null(EVS[[lc$code]]$artifacts)) list(status = "absent", why = "LV 칸 없음 또는 미평가") else
      p2_rx0_identity(X, EVS[[lc$code]]$artifacts, file.path(ROOT, sprintf(P2R05_P2R04_LV, eng))) }, error = function(e) list(status = paste("오류:", conditionMessage(e))))), ENGINES)
  TB <- rbindlist(TBL)
  rv <- p2_round_verdict(TB)
  validated <- rv$both
  xs_by <- setNames(lapply(validated, function(dv) Filter(function(x) identical(x$device, dv), OUT)), validated)
  sel <- p2_select(xs_by)
  NOISE <- .safe_rec(p2_noise_reading(OUT, validated, FS$tie_eps, FS$majority_share, RULES))
  if (is.list(NOISE) && !identical(NOISE$status, "error")) {                      # R7 두 성분에 시드 미결 꼬리표 수(판단 T1 C-054)
    NOISE$seed_tags <- .safe_rec(p5_seed_tag_counts(OUT, NOISE$judged %||% character(0)))
    NOISE$defense_component$seed_tags <- .safe_rec(p5_seed_tag_counts(OUT, NOISE$defense_component$judged %||% character(0)))
  }
  ACTION <- .safe_rec(p5_action_row(TI, TINC, OUT, as.numeric(FS$tail_instrument$t_min)))
  SDTAG <- .safe_rec(p5_same_draw_tag(sel, OUT))                                 # 선택 꼬리표(같은 추첨 — 철학 P1 C-063)
  if (length(sel)) sel[[1]]$same_draw_tag <- SDTAG$tag %||% NA_character_
  PAUSE <- .safe_rec(p5_pause_report(OUT, DOUT, as.numeric(FS$uc_floor), LQA))    # P2 정지 보고 재료(철학 P1 C-064 · 판정 아님) + 유동성 3분위 귀속(철학 P4 C-076)
  if (is.list(NOISE) && !identical(NOISE$status, "error")) NOISE$material_holdings_overlap <- PAUSE$holdings_overlap   # R7 판독 재료(C-068)
  APPX <- .safe_rec(p5_appendix_a(OUT, DOUT))                                    # 부록 A 예측 기록(채점 대상)
  excl <- lapply(rv$excluded, function(dv) list(device = dv, concentration = unique(vapply(Filter(function(x) identical(x$device, dv), OUT),
                                                                                           function(x) as.character(x$concentration$status %||% "NA"), character(1)))))
  ## 결론 이름(규칙 × 구성 · 판정 아님)
  HZ <- .safe_rec(p5_horizon_reading(TAILV$records$transfer))                     # 결론 범위 5 '수평 불일치'(권고 5)
  num1 <- function(v) suppressWarnings(as.numeric(v %||% NA))[1]
  side_of <- function(x) {                                                         # 결론 범위 11 · 14(권고 5) — 같은 구성 진단 칸 유동성 십분위 · 보유 겹침
    dv <- function(dev) { z <- Filter(function(d) identical(d$engine, x$engine) && identical(d$device, dev), DOUT); if (length(z)) num1(z[[1]]$liquidity$variant$deep_mean_decile) else NA_real_ }
    sp <- names(Filter(function(d) identical(d$reading, "vol_leak") && isTRUE(x$device %in% (d$pair %||% character(0))), P2R05_DIAGNOSTICS))
    list(liq = list(V = num1(x$liquidity$variant$deep_mean_decile), S = if (length(sp)) dv(sp[1]) else NA_real_, Q50 = dv("Q50"), RX0 = num1(x$liquidity$rx0$deep_mean_decile)),
         overlap = list(rx0 = num1(x$holdings_overlap$name_overlap_mean), q50 = num1(x$same_draw$holdings_overlap_vs_q50$name_overlap_mean %||% x$delivery_q50$name_overlap_mean)))
  }
  CONCL <- setNames(lapply(OUT, function(x) .safe_rec(p5_conclusion(x, if (identical(x$engine, P2R05_DIAG_ENGINE)) READ$per_rule[[x$device]] else NULL,
                                                                    READ$lowvol[[x$engine]][[x$device]], side = side_of(x), hz = HZ))), names(OUT))
  for (nm in names(OUT)) OUT[[nm]]$conclusion <- CONCL[[nm]]
  SUMMARY <- rbindlist(lapply(c(OUT, DOUT), function(x) {
    su <- as.data.table(x$record$state_unturned_max_drop %||% data.table())
    ct <- x$record$crisis_type
    cw <- if (identical(ct$status, "ok")) paste(sprintf("%s %d/%d", ct$as_written$type, ct$as_written$n_win, ct$as_written$n), collapse = " · ") else (ct$status %||% NA_character_)
    data.table(role = x$role %||% "judge", engine = x$engine, device = x$device, control = P2R05_DIAGNOSTICS[[x$device %||% ""]]$control %||% NA_character_, cell = x$cell,
               tested = isTRUE(x$tested), rules_computed = isTRUE(x$rules_computed), verdict = x$verdict %||% NA_character_, verdict_name = x$verdict_name %||% NA_character_,
               pass = isTRUE(x$pass), tail_gate = x$tail_gate$status %||% NA_character_,
               conclusion = x[["conclusion"]]$name %||% x[["conclusion_name"]] %||% NA_character_, lowvol_name = x[["conclusion"]]$lowvol_name %||% NA_character_,
               attribution = x$attribution$label %||% NA_character_, selection_status = x[["rules"]]$selection$status %||% NA_character_,
               beta_deep = x[["rules"]]$beta_deep$status %||% NA_character_, beta_deep_share = x[["rules"]]$beta_deep$share %||% NA_real_, fast = x[["rules"]]$fast$status %||% NA_character_,
               k = x[["rules"]]$beta_deep$k %||% NA_real_, k_dimson = x$dimson$k_dimson %||% NA_real_, size_beta = x$size_beta$status %||% NA_character_, size_beta_ok = x$size_beta$ok %||% NA,
               holdings_differ = x$holdings_overlap$n_differ %||% NA_integer_, holdings_dates = x$holdings_overlap$n_dates %||% NA_integer_,
               name_overlap_mean = x$holdings_overlap$name_overlap_mean %||% NA_real_, delivery_q50 = x$delivery_q50$status %||% NA_character_,
               seed_band = x$seed_tags$status %||% NA_character_, seed_deep_undetermined = x$seed_tags$n_deep_undetermined %||% NA_integer_,
               seed_S_undetermined = x$seed_tags$S$undetermined %||% NA,
               liq_attr = x$liq_attr$status %||% NA_character_, liq_low_attributed = x$liq_attr$n_low_attributed %||% NA_integer_,
               liq_improved = x$liq_attr$n_improvement %||% NA_integer_,
               crisis_type_wins = cw, state_unturned_beats_beta = if (nrow(su) && "beats_beta_copy" %in% names(su)) paste(ifelse(is.na(su$beats_beta_copy), "NA", su$beats_beta_copy), collapse = ",") else NA_character_,
               concentration = x$concentration$status %||% NA_character_)
  }), fill = TRUE)
  .tail_vis <- function(T) list(window = T$window, instrument = T$instrument, records = T$records)
  VIS <- list(schema = "p2r05_evaluation_visible_v1", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = rk_md5(PR),
              evaluate_md5 = rk_md5(file.path(RD, "evaluate.R")), tau_d = pre$tau_d, rules = P2R05_RULES, diagnostics_def = P2R05_DIAGNOSTICS,
              verdict_names = as.list(P2R05_VERDICT_NAMES), cells = lapply(OUT, p2_visible_only, tau = TAU), diagnostics = lapply(DOUT, p2_visible_only, tau = TAU),
              tail = p2_redact_after_tau(.tail_vis(TAILV), TAU), ydef = p2_redact_after_tau(YD[setdiff(names(YD), "rank01")], TAU), qpred_cell_logs = QLOG,
              qpred = p2_redact_after_tau(QP[setdiff(names(QP), c("Qv", "Qall"))], TAU), warm = p2_redact_after_tau(WARM, TAU), template_check = p2_redact_after_tau(TEMPL, TAU),
              crisis_types = p2_redact_after_tau(CT, TAU), crisis_onset = p2_redact_after_tau(CO, TAU), holdings_records = p2_redact_after_tau(HREC, TAU),
              readings = p2_visible_only(READ, TAU), conclusions = p2_redact_after_tau(CONCL, TAU), rx0_identity = RXI, lv_identity = LVI, a_distance = ADIST, noise_reading = NOISE,
              seed_band = p2_redact_after_tau(BAND, TAU), instrument_action = ACTION, action_table = P2R05_ACTION_TABLE, tail_increment = TINC,
              same_draw_tag = SDTAG, pause_report = p2_redact_after_tau(PAUSE, TAU), appendix_a = APPX, horizon = HZ,
              liquidity_terciles = p2_redact_after_tau(lapply(LQA, function(L) if (is.list(L)) L[setdiff(names(L), "per_cell")] else L), TAU),   # 칸별 위기 · 종목 표 = cells[[…]]$record$liquidity_tercile
              capacity_table = P2R05_CAPACITY_TABLE, table = TB, summary = SUMMARY,
              verdict = rv$verdict, verdict_label = rv$label, n_judged = rv$n_judged, n_total = rv$n_total, pass_both = rv$both, pass_one = rv$one,
              excluded = excl, validated = validated, selected = sel, engine_alpha = as.list(X$ea),
              round_sentence = sprintf("%s · ⑮ 꼬리 계기 %s · R7 등록 판독 %s · 방어 성분 %s · 계기 → 다음 행동 %s%s", rv$label,
                                       if (isTRUE(TI$pass)) "통과" else "미달 · 미측정(변형 칸 미시험 — 원천 ① 반증 아님)",
                                       NOISE$label %||% "-", NOISE$defense_component$label %||% "-", ACTION$row %||% "-",
                                       if (!is.null(ACTION$action) && !is.na(ACTION$action)) paste0("(", ACTION$action, ")") else paste0("(", ACTION$note %||% "-", ")")),
              fingerprint = list(eval = FP_EVAL, eval_record = p2_fingerprint(RD, "record"), groups = FPG),
              precheck = list(ok = isTRUE(fromJSON(pc)$ok), at = fromJSON(pc)$at, prereg_md5 = fromJSON(pc)$prereg_md5))
  bad_dates <- dp_scan_dates(VIS[setdiff(names(VIS), c("evaluated_at", "precheck", "fingerprint"))], TAU)
  if (length(bad_dates)) stop(sprintf("[P2R05 평가] 보는 창 파일에 τ_D 이후 날짜 %d개 — 쓰지 않는다(C-031 · 가림 결함)", length(bad_dates)))
  FULL <- list(schema = "p2r05_evaluation_full_v1", audience = P2R05_FULL_AUDIENCE, evaluated_at = VIS$evaluated_at, prereg_md5 = VIS$prereg_md5,
               cells = lapply(names(EVS), function(cd) { x <- c(OUT, DOUT)[[cd]]
                                                          list(code = cd, test = EVS[[cd]]$test, full = EVS[[cd]]$full, alpha_test_window = x$alpha_test_window %||% NULL,
                                                               cell_log_full_period = x$cell_log_full_period %||% NULL, why = x$why %||% NULL) }),
               tail_full = TAILF, qpred = QP[setdiff(names(QP), c("Qv", "Qall"))], warm = WARM, template_check = TEMPL)
  writeLines(toJSON(FULL, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RES, "evaluation_full.json"), useBytes = TRUE)
  writeLines(toJSON(VIS, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RES, "evaluation_visible.json"), useBytes = TRUE)
  for (x in c(OUT, DOUT)) cat(sprintf("[P2R05 평가] %s%s %s — %s · %s%s · 창 %s · ① %s ② %s ③ %s ④ %s ⑤ %s ⑥ %s ⑦ %s ⑨ %s ⑩ %s ⑫ %s ⑬ %s ⑭ %s(%s · %s) · ⑮ %s · 집중 %s · 보유 다름 %s/%s · 크기 × β %s\n",
                             if (identical(x$role, "diagnostic")) "[진단] " else "", x$engine, x$device, x$verdict, x$verdict_name %||% "-",
                             if (!isTRUE(x$tested)) paste0("(", .p2_redact_chr(x$why %||% "-", TAU), ")") else "", x$window %||% "-",
                             isTRUE(x[["rules"]]$crisis$ok), isTRUE(x[["rules"]]$deep$ok), x[["rules"]]$beta_deep$status %||% "-", x[["rules"]]$fast$status %||% "-",
                             isTRUE(x[["rules"]]$beta_asym$ok), isTRUE(x[["rules"]]$bull$ok), isTRUE(x$alpha_non_loss$ok), isTRUE(x[["rules"]]$cycle$ok),
                             isTRUE(x[["rules"]]$construction$ok), isTRUE(x$non_inferiority$ok), isTRUE(x[["rules"]]$path$ok), isTRUE(x[["rules"]]$selection$ok),
                             x[["rules"]]$selection$label %||% "-", x[["rules"]]$selection$status %||% "-", x$tail_gate$status %||% (if (p5_tail_applicable(x$device %||% "")) TI$status else "해당 없음"),
                             x$concentration$status %||% "-", format(x$holdings_overlap$n_differ %||% NA), format(x$holdings_overlap$n_dates %||% NA), x$size_beta$status %||% "-"))
  tg <- function(z) { t <- z$tag; if (length(t) && !is.na(t[1])) t[1] else paste0(z$status %||% "-", "(0)") }   # 꼬리표 NA = 그 읽기 0건(상태 표기)
  for (rk in RULES) { pr <- READ$per_rule[[rk]]
    cat(sprintf("[P2R05 평가] 진단 읽기 %s(E2) — 중심 %s · 희석 %s · 변동성 %s · 꼬리 고유 %s · LV E2 %s · LV E3 %s\n", rk,
                tg(pr$center), tg(pr$dilution), tg(pr$vol_leak),
                tg(pr$tail_unique), READ$lowvol$E2[[rk]]$name_status %||% READ$lowvol$E2[[rk]]$status %||% "-",
                READ$lowvol$E3[[rk]]$name_status %||% READ$lowvol$E3[[rk]]$status %||% "-")) }
  cat(sprintf("[P2R05 평가] 용량 읽기(V2) %s\n", READ$capacity$label %||% "-"))
  for (e in names(LQA)) cat(sprintf("[P2R05 평가] 유동성 3분위 귀속 %s — %s\n", e, if (!identical(LQA[[e]]$status, "ok")) paste("미측정:", .p2_redact_chr(LQA[[e]]$why %||% "-", TAU)) else
    paste(vapply(names(LQA[[e]]$improvement), function(dv) { z <- LQA[[e]]$improvement[[dv]]
      sprintf("%s 저유동 귀속 %s/%s 개선 위기(%s)", dv, format(z$n_low_attributed %||% NA), format(z$n_improvement %||% NA), z$status %||% "-") }, ""), collapse = " · ")))
  pj <- function(x) if (length(x)) paste(x, collapse = ",") else "-"
  cat(sprintf("[P2R05 평가] R7 등록 판독 %s(%s) · 방어 성분 %s — 판정된 규칙 %s · 빠진 규칙 %s\n", NOISE$label %||% "-", format(NOISE$result %||% NA),
              NOISE$defense_component$label %||% "-", NOISE$judged_devices %||% "-",
              if (length(NOISE$dropped)) paste(vapply(NOISE$dropped, function(z) sprintf("%s(%s)", z$device, z$why), character(1)), collapse = " · ") else "-"))
  cat(sprintf("[P2R05 평가] 시드 띠 %s · 시드 미결(판정된 규칙 칸) 깊은 위기 %s · 빠른 급락 %s · S %s · 계기 → 다음 행동 %s — %s\n",
              paste(vapply(names(BAND), function(e) sprintf("%s:%s", e, BAND[[e]]$status %||% "-"), ""), collapse = " "),
              format(NOISE$seed_tags$n_deep_undetermined %||% NA), format(NOISE$seed_tags$n_fast_undetermined %||% NA), format(NOISE$seed_tags$n_S_undetermined %||% NA),
              ACTION$row %||% "-", ACTION$action %||% ACTION$note %||% "-"))
  cat(sprintf("[P2R05 평가] 판정 %s · 두 구성 통과 %s · 한 구성 %s · 집중 제외 %s · 선택 %s · 평가 지문 = 측정 지문 %s · RX0 동일성(P2R04) %s\n", rv$label, pj(rv$both), pj(rv$one),
              pj(rv$excluded), if (length(sel)) sel[[1]]$device else "-",
              paste(vapply(names(FPG), function(e) sprintf("%s:%s", e, FPG[[e]]$eval_matches_measure), ""), collapse = " "),
              paste(vapply(names(RXI), function(e) sprintf("%s:보유 %s · 수익 %s(다른 달 %s)", e, format(RXI[[e]]$holdings_same %||% NA), format(RXI[[e]]$returns_same %||% NA),
                                                            format(RXI[[e]]$months_differ %||% NA)), ""), collapse = " ")))
  invisible(list(cells_only = FALSE, verdict = rv$verdict))
}

if (sys.nframe() == 0L) {
  CELLS_ONLY <- "--cells-only" %in% commandArgs(trailingOnly = TRUE)
  RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE", P2R05_ROUND_ID)
  PR <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE", P2R05_ROUND_ID, "prereg.json")
  RES <- file.path(RD, "results")
  ok_extra <- function() tryCatch(p5_measured_ok(RES, fromJSON(PR, simplifyVector = FALSE)$cells), error = function(e) "")
  rc <- tryCatch({ .p5_main(CELLS_ONLY, RD, PR, RES); if (!CELLS_ONLY) p5_sentinel_write(file.path(ROOT, P2R05_EVAL_SENTINEL), "evaluated", 0L, ok_extra()); 0L },
                 p5_halt = function(e) {
                   cat(sprintf("%s — %s\n", conditionMessage(e), .p2_redact_chr(paste(e$detail %||% "", collapse = " "), as.Date("2022-12-31"))))
                   dir.create(RES, recursive = TRUE, showWarnings = FALSE)
                   writeLines(toJSON(list(schema = "p2r05_evaluation_halt_v1", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), reason = e$reason,
                                          detail = .p2_redact_chr(paste(e$detail %||% "", collapse = " "), as.Date("2022-12-31")), cells_only = CELLS_ONLY),
                                     auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(RES, "evaluation_halt.json"), useBytes = TRUE)
                   if (!CELLS_ONLY) p5_sentinel_write(file.path(ROOT, P2R05_EVAL_SENTINEL), "eval_halted", 1L, ok_extra())
                   1L },
                 error = function(e) {
                   cat(sprintf("[P2R05 평가] 오류: %s\n", .p2_redact_chr(conditionMessage(e), as.Date("2022-12-31"))))
                   if (!CELLS_ONLY) p5_sentinel_write(file.path(ROOT, P2R05_EVAL_SENTINEL), "eval_failed", 1L, ok_extra())
                   1L })
  quit(status = rc)
}
