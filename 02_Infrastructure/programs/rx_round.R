#==============================================================================
# rx_round.R — 처방 루프 v0 라운드 도구 (S2 파일럿 · v10.01 · 2026-10-13 · D7 별도 모듈 — 기존 러너 무수정)
#
# 왜: 설계 §3.3 루프(진단 → ① 분석가 → ② 처방 담당 → 사전등록 → 측정 → ③ 리뷰어 → 교훈)를 프로그램 라운드로 돈다.
#   에이전트는 청정 레인(programs/rx_lane.sh — 자동 기억 차단 · R6 읽기 가드 · 작업 디렉터리만)에서
#   τ_D 이전 재료(진단 패킷 · 논문 · 헌장 · 도구 상자)만 본다. 수치는 R 계약이 내고(AX-008) 에이전트는 인용만 한다.
#   설계 = 04_Research/01_reports/l1_prescription_redesign_20261013/README.md · 절차 = research-program SKILL §2
#
# 무엇을 하나:
#   rx_paths        라운드 디렉터리(에이전트 작업 디렉터리 = 04_Research/programs/<프로그램>/<round>/lane_<역할> — R6 가 여는 저장소 안 ·
#                   성과 경로 정규식 밖) · 정본 사전등록 = stage_artifacts/programs/<프로그램>/<round>/prereg.json(SKILL)
#   rx_toolbox_md   처방 도구 상자(셀 사양 축 어휘) — 등록부에서 생성 · 설명문의 수치는 stat_redactor 로 가린다(카탈로그 basis 에 성과 수치가 있다)
#   rx_charter_md   헌장 · 목표 · 규칙 — 등급 v3 산식 문턱은 grade_v3.R 이 읽는 정본에서 · S ≥ 1 목표 산술은 R 이 계산한다
#   rx_prepare_lane 작업 디렉터리에 재료 복사 + 프롬프트 파일
#   rx_parse_json   에이전트 출력의 마지막 ```json 블록
#   rx_validate     처방 구현(셀 사양 delta)을 **엔진의 파서**로 검증(rf_sl_parse · rf_rb_parse · rf_cc_parse · 카탈로그 · 등록부)
#   rx_compile_spec 기저 셀 사양 + delta → 처방 셀 사양(고정 축 · 기저 신호는 바꾸지 않는다)
#
# 경계: 측정 = rf_cell_worker.R(정본 러너 run_paper_replication · close_t1). 등급 = essence(v3). 이 파일은 수치를 만들지 않는다
#   (예외: 헌장의 S ≥ 1 필요 Calmar 산술 — 등급 산식의 역산이고 산출물에 식을 함께 적는다).
# 공개: rx_paths · rx_toolbox_md · rx_charter_md · rx_prepare_lane · rx_parse_json · rx_validate · rx_compile_spec
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.rx_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.rx_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry"))) return(sub("/+$", "", p))
  }
  stop("[rx_round] 프로젝트 루트 해석 실패")
}

# 청정 레인 R6 성과 경로 정규식 — 가드 설정 사본을 읽어 작업 디렉터리 경로가 걸리지 않는지 확인한다
.rx_r6_regex <- function(root) {
  p <- fromJSON(file.path(root, "02_Infrastructure/hooks/policies/arm_gen_read_guard.json"), simplifyVector = TRUE)
  p$clean_lane$target_regex
}

#' 라운드 경로 — 작업 디렉터리는 R6 가 여는 곳이어야 한다(저장소 안 · 성과 경로 정규식 밖)
rx_paths <- function(program, round_id, root = NULL) {
  root <- .rx_root(root)
  if (!grepl("^[A-Za-z0-9_]+$", program) || !grepl("^[A-Za-z0-9_]+$", round_id))
    stop("[rx_round] program · round_id 는 영숫자 · 밑줄만")
  rd <- file.path(root, "04_Research/programs", program, round_id)
  rx <- .rx_r6_regex(root)
  lane <- function(role) {
    p <- file.path(rd, paste0("lane_", role))
    if (grepl(rx, p, perl = TRUE, ignore.case = TRUE)) stop("[rx_round] 작업 디렉터리가 R6 성과 경로 정규식에 걸린다: ", p)
    p
  }
  list(root = root, round_dir = rd, lane = lane,
       prereg_dir = file.path(root, "stage_artifacts/programs", program, round_id),
       specs_dir = file.path(rd, "specs"))
}

# 수치 가림(stat_redactor 정본 — 훅 · 청정 레인과 같은 규칙) · 한 번 싣고 재사용
.RXR <- new.env(parent = emptyenv())
.rx_redact <- function(x, root) {
  if (!isTRUE(.RXR$loaded) || !identical(.RXR$root, root)) {
    e <- new.env(parent = globalenv())
    sys.source(file.path(root, "02_Infrastructure/programs/stat_redactor.R"), envir = e, keep.source = FALSE)
    .RXR$e <- e; .RXR$root <- root; .RXR$loaded <- TRUE
  }
  .RXR$e$rf_b1_redact_stats(x)
}

# 엔진 어휘(소비자 함수 · 상수) — 사적 환경에 한 번
.RX <- new.env(parent = emptyenv())
.rx_engine <- function(root) {
  if (isTRUE(.RX$loaded) && identical(.RX$root, root)) return(.RX$e)
  e <- new.env(parent = globalenv())
  for (f in c("rf_sleeve.R", "rf_rebalance.R", "rf_capcore.R")) {
    p <- file.path(root, "02_Infrastructure/reinforcement", f)
    if (!file.exists(p)) stop("[rx_round] 엔진 부품 없음: ", p)
    invisible(utils::capture.output(suppressMessages(sys.source(p, envir = e, keep.source = FALSE))))
  }
  .RX$e <- e; .RX$root <- root; .RX$loaded <- TRUE
  e
}

# 오버레이 어휘 — 카탈로그 active arm 중 엔진이 집행할 수 있는 것(빌트인 kind 또는 overlay_arms/<kind>.R)
.RX_OV_BUILTIN <- c("vol_scale", "ewma_vol", "har_vol", "turbulence", "ml_tail_gate",
                    "ts_mom_gate", "dd_recovery", "vol_x_turb", "dd_brake", "vol_x_dd")    # rf_cell_engine.R .OV_BUILTIN 사본(검사가 대조)
.rx_overlay_vocab <- function(root) {
  oc <- fromJSON(file.path(root, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE)
  rows <- lapply(oc$arms, function(a) {
    k <- as.character(.rx_or(a$kind, "")); id <- as.character(.rx_or(a$id, ""))
    exe <- k %in% .RX_OV_BUILTIN || file.exists(file.path(root, "02_Infrastructure/reinforcement/overlay_arms", paste0(k, ".R")))
    data.table(arm_id = id, kind = k, family = as.character(.rx_or(a$family, "")), status = as.character(.rx_or(a$status, "")),
               executable = exe, basis = as.character(.rx_or(a$basis, "")))
  })
  rbindlist(rows)[status == "active" & executable == TRUE]
}
.rx_weight_vocab <- function(root) {
  wc <- fromJSON(file.path(root, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)
  rbindlist(lapply(wc$entries, function(z) data.table(catalog_id = z$catalog_id, family = .rx_or(z$family, ""),
                                                      label = .rx_or(z$label, ""), status = .rx_or(z$status, ""),
                                                      notes = as.character(.rx_or(z$notes, "")))))[status == "active"]
}
.rx_factor_vocab <- function(root) {
  fr <- fromJSON(file.path(root, "02_Infrastructure/factor_db/factor_registry.json"), simplifyVector = FALSE)
  out <- rbindlist(lapply(names(fr), function(k) { z <- fr[[k]]
    data.table(id = k, name = as.character(.rx_or(z$name, "")), category = as.character(.rx_or(z$category, "")),
               direction = as.character(.rx_or(z$direction, "")), definition = as.character(.rx_or(z$definition, ""))) }))
  # custom 범주 = 측정된 전략 신호의 자동 등록(등록 조건 자체가 전기간 등급 B+ · 정의문에 등급 · 시험 창 날짜) — 처방 입력에서 뺀다(R4)
  out[category != "custom"]
}

#' 처방 도구 상자(마크다운) — 셀 사양 축 어휘 · 설명문 수치는 가린다
rx_toolbox_md <- function(root = NULL) {
  root <- .rx_root(root); en <- .rx_engine(root)
  ov <- .rx_overlay_vocab(root); wt <- .rx_weight_vocab(root); fa <- .rx_factor_vocab(root)
  R <- function(x) .rx_redact(x, root)
  L <- character(0); a <- function(...) L <<- c(L, paste0(...))
  a("# 처방 도구 상자 — 셀 사양 축 어휘 (v10.01 · 처방 루프 v0)")
  a(""); a("> 처방의 **구현**은 아래 축의 값만 바꿀 수 있다(셀 사양 delta). 바꾸지 않은 축은 기저 그대로다.",
         " 설명문 안의 숫자는 가렸다(<stat>) — 과거 측정 수치는 처방 입력이 아니다.")
  a(""); a("## 0. 바꿀 수 없는 것 (고정 축 · 헌법)")
  a("- 롱온리(w ≥ 0) · 보유 ≤ 25종 · 측정 유니버스 K200∪KQ150(시점별 멤버십) · 비용 15bps · 유동성 하한(20일 평균 거래대금 t-1) · 시그널 = 월말(리밸은 월간 이하 빈도로만 바꿀 수 있다) · 집행 close_t1",
    " · 기저 신호(논문 엔진)와 그 가중(base_weight) · PIT C1~C15")
  a("- 노출 축소(현금)는 오버레이 층으로만 생긴다(Σw ≤ 1). 다른 축은 Σw = 1 이다.")
  a(""); a("## 1. factors — 기저 신호에 결합할 팩터 목록(0개 이상 · 팩터 DB id)")
  a("- 형식: `\"factors\": [{\"kind\": \"db\", \"id\": \"<팩터 id>\"}, ...]` · 빈 목록 = 논문 신호만.")
  a("- 결합: 기저 신호 가중 고정 · 나머지를 팩터들이 나눈다. 팩터 값 = 팩터 DB 의 정렬 z-점수(방향 정렬 · PIT 적재).")
  a(""); a("| id | 이름 | 범주 | 방향 | 정의 |"); a("|---|---|---|---|---|")
  for (i in seq_len(nrow(fa))) a("| ", fa$id[i], " | ", gsub("\\|", "/", fa$name[i]), " | ", fa$category[i], " | ", fa$direction[i], " | ",
                                 gsub("\\|", "/", R(substr(fa$definition[i], 1, 160))), " |")
  a(""); a("## 2. weighting — 선정된 종목 안의 비중")
  a("- 형식: `{\"kind\": \"ew\"}` · `{\"kind\": \"score_tilt\"}` · `{\"kind\": \"rank_weight\"}` · `{\"kind\": \"rank_weight_sqrt\"}` · `{\"kind\": \"inv_vol\", \"window\": <일수>}` · `{\"kind\": \"catalog\", \"catalog_id\": \"<id>\", \"label\": \"<라벨>\"}`")
  a(""); a("| catalog_id | 계열 | 라벨 |"); a("|---|---|---|")
  for (i in seq_len(nrow(wt))) a("| ", wt$catalog_id[i], " | ", wt$family[i], " | ", wt$label[i], " |")
  a(""); a("## 3. universe — 후보 범위(측정 유니버스 안에서만 좁힌다)")
  a("- `{\"kind\": \"k200_kq150\"}`(기본) · `{\"kind\": \"index\", \"flag\": \"K200\"|\"KQ150\"}` · `{\"kind\": \"size_band\", \"q_lo\": a, \"q_hi\": b}`(그날 횡단면 t-1 시총 분위 (a, b]) · `{\"kind\": \"sector_neutral\"}`(업종별 선정)")
  a(""); a("## 4. rebalance — 집행 주기 · 회전 통제")
  a("- `{\"kind\": \"interval\", \"k\": ≥2, \"phase\": 0..k-1}`(k개월마다) · `{\"kind\": \"rank_buffer\", \"mult\": >1}`(보유 종목은 순위가 mult×25 밖으로 밀릴 때까지 유지)",
    " · `{\"kind\": \"no_trade_band\" | \"turnover_cap\", \"stat\": \"expanding_median\"|\"expanding_quantile\", \"q\": (0,1), \"min_hist\": ≥3}`(자기 과거 거리의 확장창 통계 문턱)",
    " · 지원 kind(엔진 정본): ", paste(en$RF_RB_KINDS, collapse = ", "))
  a(""); a("## 5. overlay — 시변 노출(현금) 층 · 여러 층을 곱할 수 있다")
  a("- 형식: `\"overlay\": {\"kind\": \"<kind>\", \"arm_id\": \"<arm_id>\"}` 또는 층 목록 `[{...}, {...}]`. 신호는 보유 시작 전 데이터만(C5 · 엔진이 집행).")
  a("- 오버레이 처방은 노출 짝 대조(같은 평균 노출의 벤치 · R5)를 넘어야 '기전 방어'다 — 노출을 줄였을 뿐이면 '노출 방어'로 기록된다.")
  a(""); a("| arm_id | kind | 계열 | 방법 |"); a("|---|---|---|---|")
  for (i in seq_len(nrow(ov))) a("| ", ov$arm_id[i], " | ", ov$kind[i], " | ", ov$family[i], " | ", gsub("\\|", "/", R(substr(ov$basis[i], 1, 220))), " |")
  a(""); a("## 6. defense_sleeve — 보유 25종 중 k 자리를 방어 팩터 상위로 교체(총 종목 수 · 노출 불변)")
  a("- 형식: `{\"kind\": \"factor_topk\", \"k\": <정수>, \"select\": \"ic_bad_rank_asof\", \"rank\": <정수>, \"exclude\": \"\"|\"base_factors\"}`",
    " — 방어 팩터는 규칙이 고른다: 셀 시작일까지(as-of)의 KOSPI200 약세 보유월 횡단면 IC 순위. `factor_id` 로 직접 지정도 가능.",
    " · 지원 kind: ", paste(en$.RF_SL_KINDS, collapse = ", "), "(antidefense · random_beta_matched = 대조용) · select: ", paste(en$.RF_SL_SELECTS, collapse = ", "))
  a(""); a("## 7. cap_core — 벤치 인지 코어-위성(비중 단계 뒤)")
  a("- 형식: `{\"k\": <정수 ≥0>, \"satellite\": \"floor\"}` — 코어 = 그 시그널일 K200 t-1 시총 상위 k종(벤치 비중 근사) · 위성 = 이 전략 보유(합집합 ≤ 25 절단).",
    " 벤치를 덜 벗어나 '시장보다 더 빠지는' 위험을 줄이는 대신 알파 희석. k = 0 = 무처치.")
  txt <- paste(L, collapse = "\n")
  .rx_assert_clean(txt, root, "toolbox")
  txt
}

# 처방 입력 문서 검사(fail-closed) — τ_D 초과 날짜 · 등급 판정 표기가 있으면 멈춘다(R4: 처방 입력엔 τ_D 이전 정보만)
.rx_assert_clean <- function(txt, root, what) {
  tau <- as.Date(fromJSON(file.path(root, "06_Registry/behavior_card.json"), simplifyVector = TRUE)$tau_d)
  # 비정상 UTF-8 바이트(pdftotext 산출 등)가 있으면 정규식이 그 문자열을 건너뛴다(경고만 내고 미검사 = 거짓 통과) — 먼저 정리한다
  txt <- iconv(paste(txt, collapse = "\n"), from = "UTF-8", to = "UTF-8", sub = "")
  if (is.na(txt)) stop("[rx_round] ", what, " 인코딩 판독 불가 — 검사할 수 없다(fail-closed)")
  d <- regmatches(txt, gregexpr("(19|20)\\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\\d|3[01])", txt))[[1]]
  bad <- d[suppressWarnings(as.Date(d)) > tau]
  ym <- regmatches(txt, gregexpr("(?<![0-9-])(19|20)\\d{2}-(0[1-9]|1[0-2])(?![0-9-])", txt, perl = TRUE))[[1]]
  bad <- c(bad, ym[ym > format(tau, "%Y-%m")])
  gr <- regmatches(txt, gregexpr("(등급|Grade|grade)\\s*[ABCF](?![A-Za-z])", txt, perl = TRUE))[[1]]
  if (length(bad) || length(gr))
    stop(sprintf("[rx_round] %s 에 처방 입력 금지 정보: τ_D 초과 날짜 %s · 등급 표기 %s", what,
                 paste(utils::head(unique(bad), 5), collapse = ","), paste(utils::head(unique(gr), 5), collapse = ",")))
  invisible(TRUE)
}

#' 헌장 · 목표 · 규칙(마크다운) — 등급 문턱은 정본에서 · S ≥ 1 필요 Calmar 는 등급 산식의 역산(R 계산 · 식 병기)
rx_charter_md <- function(pk, root = NULL) {
  root <- .rx_root(root)
  g <- new.env(parent = globalenv())
  invisible(utils::capture.output(suppressMessages(sys.source(file.path(root, "02_Infrastructure/contracts/grade_v3.R"), envir = g, keep.source = FALSE))))
  th <- g$gv3_thresholds(root); cf <- g$gv3_cfg(root); w <- cf$weights
  bcj <- fromJSON(file.path(root, "06_Registry/behavior_card.json"), simplifyVector = TRUE)
  pt <- .rx_or(pk$performance$strategy$port_t, NA_real_)
  need_cal <- if (is.finite(pt) && pt > 0) th$calmar_a * (pt / th$port_t_a)^(-w$port_t / w$calmar) else NA_real_
  cagr <- .rx_or(pk$performance$strategy$cagr, NA_real_)
  need_mdd <- if (is.finite(need_cal) && is.finite(cagr) && need_cal > 0) cagr / need_cal else NA_real_
  f3 <- function(x) if (is.finite(x)) formatC(x, format = "f", digits = 3) else "—"
  L <- character(0); a <- function(...) L <<- c(L, paste0(...))
  a("# 헌장 · 목표 · 규칙 — 처방 루프 v0")
  a(""); a("## 1. 투자철학 (도훈)")
  a("- 남들 다 깨질 때 방어해 복리를 극대화한다 — **위기 하락 포착률을 낮추되 강세 상승 포착률 ≥ ", bcj$uc_floor, "** 를 지킨다(비대칭).",
    " 정적 노출 축소(현금 비중만 늘리기)로는 비대칭이 생기지 않는다.")
  a("- 꾸준한 우상향 — 장기 정체(수년 수중)를 싫어한다. 성과보다 PIT(미래참조 없음)가 우선이다.")
  a(""); a("## 2. 등급 v3 (권위 · essence) — 이 처방이 겨냥하는 수치 산식")
  a("- 종합점수 S = (Calmar / ", th$calmar_a, ")^", w$calmar, " × (PORT_t / ", th$port_t_a, ")^", w$port_t,
    " · A = S ≥ 1 + 하한(PORT_t ≥ ", th$port_t_b, " · CAGR ≥ ", th$cagr_min, " · Sharpe ≥ ", th$sharpe_min,
    " · Calmar ≥ 같은 창 벤치 Calmar) + 위기 복원력(CR) 노치 + OOS 관문.")
  a("- PORT_t = 일별 (전략 순수익 − KOSPI200) 평균의 Newey-West t(lag 3). 위험 축 = Calmar(최대낙폭은 직접 걸리지 않는다).")
  a("- **보는 창 기준 산술(참고 · R 계산)**: 보는 창 PORT_t = ", f3(pt), " 이면 S ≥ 1 에 필요한 Calmar = ", th$calmar_a, " × (", f3(pt), "/", th$port_t_a,
    ")^(−", w$port_t, "/", w$calmar, ") = ", f3(need_cal), " → 보는 창 CAGR ", f3(cagr), " 를 유지하면 최대낙폭 ≤ ", f3(need_mdd), " 가 필요하다.",
    " PORT_t 가 떨어지면 필요한 Calmar 는 올라간다(교환).")
  a(""); a("## 3. 정보 경계 τ_D = ", pk$tau_d, " (절대)")
  a("- 당신이 보는 수치는 전부 ", pk$window[1], " ~ ", pk$window[2], " 구간에서 R 계약이 계산한 것이다. 그 뒤(시험 창)는 등급 · 사람 쪽 판정에만 쓴다.")
  a("- 2023년 이후의 시장 사건 · 성과는 사전학습으로 알고 있더라도 **근거로 쓰지 마라**(처방이 시험 창에 맞춰지면 시험이 무효가 된다).")
  a(""); a("## 4. 리서치 규칙 (설계 §3.4 — 증거로 인정되는 것)")
  a("- R2 사전등록: 처방전(가설 · 기대 방향 · 반증 조건 · 최종 후보 선택 규칙)은 측정 **전에** 파일로 고정된다. 결과를 본 뒤 고쳐 쓸 수 없다.")
  a("- R3 시행 회계: 측정한 변형은 전부 계보 시행 수에 더해져 등급 DSR 에 반영된다 — 같은 기전의 파라미터 변형을 여럿 내지 마라(서로 다른 기전 1~3건).")
  a("- R5 노출 짝 · MC8 크기 짝: 방어 처방은 '같은 평균 노출의 벤치' 와 '같은 크기 분포 · 평균 노출의 무작위 포트폴리오' 보다 덜 빠져야 실력(선택·기전 방어)이다.",
    " 크기 방어 · 노출 방어는 기록하되 실력으로 세지 않는다.")
  a("- R6 지속성: 방어 개선은 여러 위기에 걸쳐 나타나야 한다(한 위기 맞춤 금지).")
  a("- AX-008: 수치는 R 계약 산출만 인용한다 — 새로 계산 · 추정하지 마라. 숫자가 필요하면 '측정 필요'라고 적어라.")
  a("- PIT C1~C15: 처방 규칙의 모든 입력은 결정 시점 이전 데이터여야 한다(오버레이 신호 = 보유 시작 전 · 재무 = 공시 지연 · 팩터 선정 통계 = as-of).")
  txt <- paste(L, collapse = "\n")
  .rx_assert_clean(txt, root, "charter")
  txt
}

#' 작업 디렉터리 준비 — files = list(<대상 이름> = <원본 경로> | I(<문자열 내용>)) · 프롬프트는 prompt.md
rx_prepare_lane <- function(lane_dir, files, prompt, root = NULL) {
  root <- .rx_root(root)
  .rx_assert_clean(prompt, root, "prompt")
  dir.create(lane_dir, recursive = TRUE, showWarnings = FALSE)
  for (nm in names(files)) {
    src <- files[[nm]]; dst <- file.path(lane_dir, nm)
    if (inherits(src, "AsIs")) { .rx_assert_clean(as.character(src), root, nm); writeLines(enc2utf8(as.character(src)), dst, useBytes = TRUE) }
    else { if (!file.exists(src)) stop("[rx_round] 재료 없음: ", src); file.copy(src, dst, overwrite = TRUE) }
  }
  writeLines(enc2utf8(prompt), file.path(lane_dir, "prompt.md"), useBytes = TRUE)
  invisible(file.path(lane_dir, "prompt.md"))
}

#' 에이전트 출력의 마지막 ```json 블록
rx_parse_json <- function(txt) {
  txt <- gsub("\r\n", "\n", paste(txt, collapse = "\n"), fixed = TRUE)
  m <- gregexpr("(?s)```json[ \\t]*\\n(.*?)\\n```", txt, perl = TRUE)      # (?s) — 블록은 여러 줄이다
  blk <- regmatches(txt, m)[[1]]
  if (!length(blk)) stop("[rx_round] 출력에 ```json 블록이 없다")
  body <- sub("(?s)^```json[ \\t]*\\n", "", sub("(?s)\\n```$", "", blk[length(blk)], perl = TRUE), perl = TRUE)
  fromJSON(body, simplifyVector = FALSE)
}

#' 처방 구현 검증 — 축 이름 · 값을 **엔진이 읽는 함수와 등록부**로 확인한다(침묵 무처치 차단)
#' @return list(ok, errors, delta = 정규화된 delta)
rx_validate <- function(impl, root = NULL) {
  root <- .rx_root(root); en <- .rx_engine(root)
  ok_axes <- c("factors", "weighting", "universe", "rebalance", "overlay", "defense_sleeve", "cap_core")
  err <- character(0); add <- function(...) err <<- c(err, paste0(...))
  if (!is.list(impl) || !length(impl)) return(list(ok = FALSE, errors = "구현(delta)이 비었다", delta = NULL))
  bad <- setdiff(names(impl), ok_axes)
  if (length(bad)) add("바꿀 수 없는 축/모르는 키: ", paste(bad, collapse = ","))
  if (!is.null(impl$factors)) {
    fv <- .rx_factor_vocab(root)$id
    ids <- vapply(impl$factors, function(z) as.character(.rx_or(z$id, "")), character(1))
    kinds <- vapply(impl$factors, function(z) as.character(.rx_or(z$kind, "")), character(1))
    if (any(kinds != "db")) add("factors.kind 는 db 만")
    if (any(!ids %in% fv)) add("팩터 DB 에 없는 id: ", paste(ids[!ids %in% fv], collapse = ","))
  }
  if (!is.null(impl$weighting)) {
    k <- as.character(.rx_or(impl$weighting$kind, ""))
    if (!k %in% c("ew", "score_tilt", "rank_weight", "rank_weight_sqrt", "inv_vol", "catalog")) add("weighting.kind 미지원: ", k)
    if (identical(k, "catalog") && !(as.character(.rx_or(impl$weighting$catalog_id, "")) %in% .rx_weight_vocab(root)$catalog_id))
      add("비중 카탈로그 active 에 없는 id: ", .rx_or(impl$weighting$catalog_id, ""))
  }
  if (!is.null(impl$universe)) {
    k <- as.character(.rx_or(impl$universe$kind, ""))
    if (!k %in% c("k200_kq150", "index", "size_band", "sector_neutral")) add("universe.kind 미지원(이 기저): ", k)
    if (identical(k, "index") && !(as.character(.rx_or(impl$universe$flag, "")) %in% c("K200", "KQ150"))) add("universe.flag 는 K200|KQ150")
    if (identical(k, "size_band")) { lo <- suppressWarnings(as.numeric(impl$universe$q_lo)); hi <- suppressWarnings(as.numeric(impl$universe$q_hi))
      if (!(is.finite(lo) && is.finite(hi) && lo >= 0 && hi <= 1 && lo < hi)) add("size_band 는 0 ≤ q_lo < q_hi ≤ 1") }
  }
  if (!is.null(impl$rebalance)) { e <- tryCatch({ en$rf_rb_parse(impl$rebalance); NULL }, error = function(z) conditionMessage(z)); if (!is.null(e)) add(e) }
  if (!is.null(impl$defense_sleeve)) { e <- tryCatch({ en$rf_sl_parse(impl$defense_sleeve); NULL }, error = function(z) conditionMessage(z)); if (!is.null(e)) add(e) }
  if (!is.null(impl$cap_core)) { e <- tryCatch({ en$rf_cc_parse(impl$cap_core); NULL }, error = function(z) conditionMessage(z)); if (!is.null(e)) add(e) }
  if (!is.null(impl$overlay)) {
    ov <- .rx_overlay_vocab(root)
    lay <- if (!is.null(impl$overlay$kind)) list(impl$overlay) else impl$overlay
    for (z in lay) {
      id <- as.character(.rx_or(z$arm_id, "")); k <- as.character(.rx_or(z$kind, ""))
      hit <- ov[arm_id == id]
      if (!nrow(hit)) add("오버레이 arm 이 active · 집행 가능 목록에 없다: ", id)
      else if (!identical(hit$kind[1], k)) add("오버레이 kind 불일치: ", id, " 의 kind 는 ", hit$kind[1])
    }
  }
  list(ok = !length(err), errors = err, delta = impl)
}

#' 기저 셀 사양 + delta → 처방 셀 사양(기저 신호 · 고정 축은 그대로)
rx_compile_spec <- function(base_spec, delta, code, label, idea, selection_accounting, root_paper = NULL) {
  s <- base_spec
  for (k in names(delta)) s[[k]] <- delta[[k]]
  s$code <- code; s$label <- label; s$block <- "RX"; s$idea <- idea
  s$selection_accounting <- selection_accounting
  if (!is.null(root_paper)) s$root_paper <- root_paper
  s$preflight <- NULL                          # 구 격자 사전 점검 블록(기저 칸 것) — 처방 칸에는 사전등록이 정본
  s
}
