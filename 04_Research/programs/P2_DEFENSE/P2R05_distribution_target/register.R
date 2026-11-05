## P2R05 분포 표적(비대칭 원천 ① · 종목 수준 꼬리 학습) × β 짝 — 2002.06975 DNN5 의 표적만 분포로 바꾼(같은 31 특징 · 같은 순위 재척도 5일 표적 · 같은 1,000일 창 ·
##   같은 일정 · 같은 시드 — 출력층 3(τ 0.1 · 0.5 · 0.9) · 합성 pinball · 행별 재배열) 분위 DNN 의 왼꼬리로 고른 보유가 같은 β 의 정적 현금 사본(β 짝)보다
##   깊은 위기 · 빠른 급락에서 덜 빠지고(③ · ④) 크기 · 노출 짝을 넘는 선택 방어(⑭)이며 강세 참여 · 알파 · 복리를 지키는가(⑤ ~ ⑬) · 꼬리 계기(⑮) = 시험 조건
##   설계 = DESIGN_draft.md(v0 + §0b v1 결정) · Q 자율 판단 J-20261018-006(라운드 선택 · J-005 대체) · 앞 라운드 P2R04 = falsified(10-18 15:59 평가)
## 칸 = 16: E2 묶음 11(RX0 + 재시드 RX0S + 변형 V1 · V2 + 진단 Q50 · N1 · N2 · S1 · S2 · W2 + 비교 기준 LV) · E3 묶음 5(RX0 + RX0S + 변형 V1 · V2 + 비교 기준 LV).
##   판정 표 = 변형 4칸(소비 규칙 2 × 구성 2)뿐 · 시행 수 가산 = 변형 4 · RX0 2 · 재시드 2 · 진단 6 · 비교 기준 2 = 무가산
##   (비교 기준 LV = 조정자 10-18 · 판단 T2 C-20261018-038 · 재시드 RX0S = 판단 T1 R-20261018-007 C-054 · 055 · 056)
## 실행:
##   Rscript register.R --draft      초안 — 준비물 목록(다른 구현 에이전트 산출 포함)을 한 번에 대조한 뒤 싼 기계 점검(사양 16 · DT 엔진 검사 · DT 시험 증거 · 평가 경로 · 리허설 ·
##                                   규칙 상수 = P2R04 v3 값 · 규칙 문장 승계 대조 · 판정 구현 정합 · 판단 원장) → 검사 실행 → prereg_draft.json · 하나라도 실패면 쓰지 않는다
##   Rscript register.R --register   등록 — 마지막 점검받은 초안 md5 = 초안 · 사양 · DT 엔진 · DT 시험 증거 · 운영 경로 · 패키지 · 리허설 · 행동 카드 사본 · 철학 Superfan P1 수령 ·
##                                   도전 응답 · 열린 보류 요청 0 · 구현 에이전트 열람 기입 · 설계 입력 md5 · 커밋 상태를 확인한 뒤에만 사전등록 두 사본 + 등록부 pr_record_round
##   ★R2: 측정 결과(results/P2R05_*.json)가 하나라도 있거나 사전등록이 이미 있으면 사전등록을 바꾸지 않는다.
##   ★사양(specs/)은 이 파일이 쓰지 않는다 — make_specs.py(결정론 생성기)가 만든 16개를 P2R05_CONST$spec_checks 로 검사만 한다
##     (RX0 = P2R04 RX0 와 code · label 밖 동일 · 변형 · 진단 = base_signal.path(W2 = engine_blend) · 이름 · 서술 · 회계 밖 RX0 와 동일 · LV = P2R04 W2 와 code · label 밖 동일 ·
##      시행 회계 = 변형만 앞선 사전등록 계보 최댓값 + 4 · 축 파서 rx_validate).
##   ★판정 규칙 상수(final_selection_rule) · 규칙 문장(rules)의 정본 = round_rules.R::p2r05_final_selection_rule · p2r05_rules — 이 파일은 source 해서 쓰고 값을 박지 않는다
##     (P2R04 v3 사전등록 값 · 문장과 같은지만 대조해 기록한다 — DESIGN §0b 결정 10 '규칙 상수는 P2R04 v3 그대로 · 문구 대조로 묶는다').
##   ★DT 엔진 검사 = engine_checks.R(P2R05_DTC · precheck.R · warm_engine.R 과 같은 정의).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
if (!file.exists(file.path(ROOT, "02_Infrastructure/hooks/qvest_hook_router.py"))) stop("[P2R05] 프로젝트 루트 표지 없음: ", ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

## ── 상수 · 검사 함수(순수 — root 인자 밖의 바깥 변수를 참조하지 않는다) ─────────────────────────────────────────
##   precheck.R --dry 가 이 대입문 하나만 골라 평가한다(칸 계획 · 운영 경로 목록 · 사양 검사의 단일 정본). 바꾸면 precheck · 등록이 같이 바뀐다.
P2R05_CONST <- local({
  PROGRAM <- "P2_DEFENSE"; ROUND <- "P2R05_distribution_target"
  RD_REL <- "04_Research/programs/P2_DEFENSE/P2R05_distribution_target"
  DESIGN_REL <- paste0(RD_REL, "/DESIGN_draft.md")
  P2R04_RD <- "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings"
  P2R04_SPECS <- paste0(P2R04_RD, "/specs")
  P2R04_PREREG <- "stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings/prereg.json"
  CRISIS_TYPE <- c(json = "04_Research/programs/P2_DEFENSE/_design_notes/crisis_type_classify.json",
                   md = "04_Research/programs/P2_DEFENSE/_design_notes/crisis_type_classify.md")   # Q 의 위기 유형 탐침(설계 입력 · md5 핀 · 내용은 이 파일이 읽지 않는다)
  ## 그 밖의 설계 입력(격리 점검 v1 권고 2 — 판정 구현이 읽거나 규칙 문장이 근거로 드는 노트 · md5 핀 · 커밋 대상 · 내용은 이 파일이 읽지 않는다)
  ##   onset_state_classify.json = evaluate.R p5_load_onset 이 읽는다 · state_turn_classify.md = final_selection_rule 기록 위기 목록의 원천 ·
  ##   crisis_type_asof.{R,md,json} = rules.pause_report · DESIGN §0b 26('진행 중 상관 상태는 반증')의 근거(Q 가 커밋)
  DESIGN_NOTES <- c(onset_state_classify_json = "04_Research/programs/P2_DEFENSE/_design_notes/onset_state_classify.json",
                    state_turn_classify_md = "04_Research/programs/P2_DEFENSE/_design_notes/state_turn_classify.md",
                    crisis_type_asof_R = "04_Research/programs/P2_DEFENSE/_design_notes/crisis_type_asof.R",
                    crisis_type_asof_md = "04_Research/programs/P2_DEFENSE/_design_notes/crisis_type_asof.md",
                    crisis_type_asof_json = "04_Research/programs/P2_DEFENSE/_design_notes/crisis_type_asof.json")
  CHARTER_OPEN <- c("CHARTER-GAPS-4-20261018", "CHARTER-GAPS-5-20261018", "CHARTER-GAPS-6-20261018")   # 열린 헌장 결정(기본값 = 현행 헌장 · 이 라운드 판정 규칙 불변 · 6 = 곧 연다)
  HOLDS <- c("C-20261018-046")                                                   # 판단 원장 보류(저변동 틸트 류 P4 · A 승격 전 도훈 확인)
  SPECS_GEN <- paste0(RD_REL, "/make_specs.py")
  FACTOR_REGISTRY <- "02_Infrastructure/factor_db/factor_registry.json"
  ## 평가 경로(결과 전에 고정 · evaluate.R 시작부가 재대조) — evaluate.R · evaluate_fixture.R · round_rules.R = 판정 구현 쪽(에이전트 B) · 나머지 = 측정 기계(이 디렉터리)
  EVALF <- c("evaluate.R", "evaluate_fixture.R", "round_rules.R", "precheck.R", "engine_checks.R", "measure.sh", "measure_now.sh", "measure_now_vram.sh",
             "fingerprint.sh", "warm_cache.sh", "warm_engine.R")
  PIN_CATS <- "lean:entropy"                                                     # E3 RX0 비중(엔진 정의)
  PKGS <- c("bbdetection", "PerformanceAnalytics", "data.table", "arrow")        # P2R04 그대로(arrow = 팩터 적재 · 예측표 읽기)
  TESTF <- c("08_Tests/programs/test_round_kit_pair_alpha.R", "08_Tests/reinforcement/test_rf_cell_engine_smoke.R",
             "08_Tests/factor_db/test_fdc_read_fastpath.R", paste0(RD_REL, "/evaluate_fixture.R"))
  ## 구성(DESIGN §2.3) — 원형 = P2R04 RX0 · 비교 기준 원형 = P2R04 W2(저변동 D03 12.5%)
  ENG <- list(E2 = list(src = "P2R04_E2_RX0", lv_src = "P2R04_E2_W2", base_weighting = "EW(동일 비중 · 25종) · 팩터 없음 · DNN 몫 100%"),
              E3 = list(src = "P2R04_E3_RX0", lv_src = "P2R04_E3_W2", base_weighting = "lean:entropy(엔진 자체 엔트로피 비중 · 순위 버퍼 2배 · B6_36 정의) · 기존 팩터 3 · DNN 몫 50%"))
  ## 소비 규칙(DESIGN §3.4) — 변형 칸(시행 수 가산 · 판정 · 선택 대상)
  VAR <- list(
    V1 = list(name = "꼬리 거부", form = "제약형",
              rule = "q̂10 이 그날 엔진 적격 집합 하위 20%(순위/N ≤ 0.2 · 동률 평균)면 NA(후보 제외) · 나머지 = q̂50 순위",
              basis = "Abe & Nakagawa (2020) arXiv:2002.06975 — 논문 자체의 정렬 단위(상/하위 5분위) · Bassett, Koenker & Kordas (2004) Pessimistic Portfolio Allocation and Choquet Expected Utility, JFEC 2(4) — '기대 수익 조건 아래 꼬리 위험'의 쌍대형(제약형)"),
    V2 = list(name = "꼬리 순위", form = "목적형",
              rule = "점수 = q̂10(예측 VaR(10%) 최소화 = 비관 점수 λ = 1 · 모수 없음)",
              basis = "Bassett, Koenker & Kordas (2004) — Choquet 비관 효용의 꼬리 분위(목적형) · Atilgan, Bali, Demirtas & Gunaydin (2020) Left-tail momentum, JFE 135(3) — 좌꼬리 위험이 낮은 종목의 이후 수익"))
  ## 진단 칸(E2 · 판정 표 밖 · 시행 수 무가산 · DESIGN §4) — tag 는 사양 label 에 있어야 한다(make_specs.py 와 같은 문자열)
  DIAG <- list(
    Q50 = list(rule = "Q50", control = "center_only", engines = "E2", pair = c("V1", "V2"), tag = "중앙값만(꼬리 미사용)", reads = "중심 효과",
               purpose = "추정 대상 '평균 → 중앙값'만의 효과(꼬리 미사용) · V1 − Q50 = 거부의 효과"),
    N1 = list(rule = "N1", control = "tail_perm", engines = "E2", pair = "V1", tag = "무정보 꼬리 순열 짝(V1)", reads = "희석",
              purpose = "하방 폭 s 를 신호일 안 순열 → V1 — 같은 비율 무작위 제외(희석 · 선정 교란)의 몫"),
    N2 = list(rule = "N2", control = "tail_perm", engines = "E2", pair = "V2", tag = "무정보 꼬리 순열 짝(V2)", reads = "희석",
              purpose = "q̂50 − s_perm — 중심은 두고 꼬리 정보만 지운 V2"),
    S1 = list(rule = "S1", control = "vol_proxy", engines = "E2", pair = "V1", tag = "변동성 순위 대응 짝(V1)", reads = "변동성 누출",
              purpose = "s 값을 직전 실현 변동성 순위대로 재배정 → V1 — 꼬리 정보가 변동성 누출인가(같은 주변분포 · 순서만 σ)"),
    S2 = list(rule = "S2", control = "vol_proxy", engines = "E2", pair = "V2", tag = "변동성 순위 대응 짝(V2)", reads = "변동성 누출",
              purpose = "q̂50 − s_σ — 같은 질문(V2)"),
    W2 = list(rule = NULL, blend = c("RX0", "V2"), control = "capacity_pair", engines = "E2", pair = "V2", pair_e3 = TRUE, tag = "용량 짝(V2 · 50%)", reads = "용량",
              purpose = "engine_blend [engine.R · engine_V2.R] = 0.5 rank-Z(평균) + 0.5 rank-Z(q̂10) — E3 의 처치 몫 50% 를 E2 에서 재현('용량 의존'과 '구성 의존'을 가른다)"))
  ## 비교 기준 칸(진단 형식 · 판정 표 밖 · 무가산 · 선택 대상 아님 · 2계층 풀 미등재 — 조정자 10-18 · 판단 T2 C-20261018-038)
  CMP <- list(LV = list(control = "lowvol_screen", engines = c("E2", "E3"), tag = "비교 기준 LV", factor = "D03_RealVol", challenge = "C-20261018-038",
                        purpose = "P2R04 W2(저변동 D03_RealVol 12.5% 스크린) 사양을 같은 배치에서 재측정 — V 칸 방어를 '저변동 스크린이면 되는가'와 나란히 읽는 기준(판정 아님)"))
  ## 재시드 짝(진단 형식 · 판정 표 밖 · 무가산 · 선택 대상 아님 — 판단 T1 R-20261018-007 C-054 · 055 · 056 수용 · 조정자 10-18) — 엔진 = 원본 RX0 와 .SEED_BASE 한 줄만 다른 사본
  RSD <- list(RX0S = list(control = "seed_pair", engines = c("E2", "E3"), tag = "재시드 짝", pair = "RX0", review = "R-20261018-007",
                          challenge = c("C-20261018-054", "C-20261018-055", "C-20261018-056"),
                          purpose = "RX0 와 시드만 다른 평균 표적 DNN — RX0 대비 위기 포착 차의 시드 잡음 띠(판정 아님 · 읽기 · 결론 범위 8)"))
  N_ROUND <- length(ENG) * length(VAR)                                           # 시행 수 가산 칸 = 변형 칸
  .or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  md5f <- function(f) if (file.exists(f)) unname(as.character(tools::md5sum(f))) else NA_character_
  cj <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
  read_spec <- function(f) tryCatch(jsonlite::fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  normp <- function(p) sub("/+$", "", gsub("\\\\", "/", as.character(p)))
  .dtc <- function(root) { e <- new.env(parent = globalenv()); sys.source(file.path(root, RD_REL, "engine_checks.R"), envir = e, keep.source = FALSE); e$P2R05_DTC }
  ## 운영 경로 = P2R04 사전등록 운영 경로(그대로 승계 · 손으로 옮겨 적지 않는다) + DT 엔진 파일(템플릿 · 생성기 · 차분 검사기 · 매니페스트 · 생성 엔진 7)
  ops <- function(root, dtc = .dtc(root)) {
    P4 <- read_spec(file.path(root, P2R04_PREREG))
    if (is.null(P4) || !length(P4$operational_pins$files)) stop("[P2R05] P2R04 사전등록 운영 경로를 읽지 못했다: ", P2R04_PREREG)
    unique(c(vapply(P4$operational_pins$files, function(z) as.character(z$path), character(1)), dtc$ops_rel(root)))
  }
  ## 칸 계획 — 엔진마다 RX0 → 재시드 RX0S → 변형 → 진단 → 비교 기준(측정 순서 = 이 순서 · measure.sh 가 같은 목록을 사전등록과 대조)
  plan <- function() {
    out <- list()
    for (e in names(ENG)) {
      out[[length(out) + 1L]] <- list(code = sprintf("P2R05_%s_RX0", e), engine = e, component = "RX0", role = "reference")
      for (g in names(RSD)) if (e %in% RSD[[g]]$engines)
        out[[length(out) + 1L]] <- list(code = sprintf("P2R05_%s_%s", e, g), engine = e, component = g, role = "reseed", rsd = g)
      for (v in names(VAR)) out[[length(out) + 1L]] <- list(code = sprintf("P2R05_%s_%s", e, v), engine = e, component = v, role = "variant", rule = v)
      for (g in names(DIAG)) if (e %in% DIAG[[g]]$engines)
        out[[length(out) + 1L]] <- list(code = sprintf("P2R05_%s_%s", e, g), engine = e, component = g, role = "diagnostic", diag = g, rule = DIAG[[g]]$rule)
      for (g in names(CMP)) if (e %in% CMP[[g]]$engines)
        out[[length(out) + 1L]] <- list(code = sprintf("P2R05_%s_%s", e, g), engine = e, component = g, role = "comparison", cmp = g)
    }
    out
  }
  ## 시행 회계 — 계보마다 앞선 모든 사전등록 칸의 n_family 최댓값(이 라운드 사전등록은 뺀다 · P2R03 · P2R04 nf_prior 와 같은 규칙 · make_specs.py 와 같은 규칙)
  nf_prior <- function(root, fam) {
    pp <- Sys.glob(file.path(root, "stage_artifacts/programs/*/*/prereg.json"))
    pp <- pp[basename(dirname(pp)) != ROUND]
    v <- unlist(lapply(pp, function(p) {
      d <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
      ok <- Filter(function(z) is.numeric(z$n_family) && !is.null(z$path) &&
                     identical(.or(read_spec(file.path(root, z$path))$selection_accounting$family_root, NA_character_), fam), .or(d$cells, list()))
      vapply(ok, function(z) as.integer(z$n_family), integer(1))
    }))
    if (length(v)) max(v) else 0L
  }
  ## 사양 기계 검사(칸 계획 전부) — 반환 = list(ok, errors, cells(칸 기록 · 사전등록 cells 의 원천), n_round, n_cells)
  spec_checks <- function(root, epoch_id) {
    if (!exists("rx_validate", mode = "function")) source(file.path(root, "02_Infrastructure/programs/rx_round.R"))
    DTC <- .dtc(root)
    err <- character(0); add <- function(...) err <<- c(err, paste0(...))
    strip <- function(s, drop) s[setdiff(names(s), drop)]
    SRC <- lapply(ENG, function(g) read_spec(file.path(root, P2R04_SPECS, paste0(g$src, ".json"))))
    LVS <- lapply(ENG, function(g) read_spec(file.path(root, P2R04_SPECS, paste0(g$lv_src, ".json"))))
    for (e in names(ENG)) {
      if (is.null(SRC[[e]])) add(e, ": 원형 사양 판독 실패 — ", ENG[[e]]$src)
      if (is.null(LVS[[e]])) add(e, ": 비교 기준 원형 사양 판독 실패 — ", ENG[[e]]$lv_src)
    }
    if (length(err)) return(list(ok = FALSE, errors = err, cells = list(), n_round = N_ROUND, n_cells = 0L))
    cells <- list(); pl <- plan(); NFP <- list()
    for (p in pl) {
      code <- p$code; cmp <- identical(p$role, "comparison")
      src <- if (cmp) LVS[[p$engine]] else SRC[[p$engine]]
      orig <- if (cmp) ENG[[p$engine]]$lv_src else ENG[[p$engine]]$src
      fam <- as.character(.or(src$selection_accounting$family_root, NA_character_))
      rp <- sprintf("%s/specs/%s.json", RD_REL, code); f <- file.path(root, rp)
      s <- if (file.exists(f)) read_spec(f) else NULL
      if (is.null(s)) { add(code, ": 사양 없음 또는 JSON 판독 실패"); next }
      if (!identical(s$code, code)) add(code, ": code 불일치(", .or(s$code, "NULL"), ")")
      if (!identical(s$fixed_axes$measurement_axis, epoch_id)) add(code, ": 측정 축 ", .or(s$fixed_axes$measurement_axis, "NULL"), " ≠ 활성 epoch ", epoch_id)
      if (!is.null(s$overlay) || !is.null(s$overlay_shift)) add(code, ": 오버레이 키가 있다(이 라운드는 오버레이 없음)")
      axn <- intersect(c("factors", "weighting", "universe", "rebalance", "defense_sleeve", "cap_core"), names(s))
      v <- tryCatch(rx_validate(Filter(Negate(is.null), s[axn]), root), error = function(z) list(ok = FALSE, errors = conditionMessage(z)))
      if (!isTRUE(v$ok)) add(code, ": 축 검증(rx_validate) 실패 — ", paste(v$errors, collapse = " | "))
      rx_path <- normp(src$base_signal$path)
      dg <- if (!is.null(p$diag)) DIAG[[p$diag]] else NULL
      if (p$role %in% c("reference", "comparison")) {
        ## RX0 · LV = 원형 사양과 code · label 밖 동일
        if (!identical(cj(strip(s, c("code", "label"))), cj(strip(src, c("code", "label"))))) add(code, ": 원형 ", orig, " 사양과 code · label 밖이 다르다")
        want_tag <- if (cmp) paste0(orig, " 사양 사본") else paste0(orig, " 사양 복사")
        if (!grepl(want_tag, .or(s$label, ""), fixed = TRUE)) add(code, ": label 에 '", want_tag, "' 없음")
        if (cmp && !grepl(CMP[[p$cmp]]$tag, .or(s$label, ""), fixed = TRUE)) add(code, ": label 에 '", CMP[[p$cmp]]$tag, "' 없음")
        eng_files <- rx_path
      } else {
        ## 변형 · 진단 = base_signal(분위 엔진 경로 · W2 = engine_blend) · 이름 · 서술 · 회계 밖 RX0 와 동일
        bs <- s$base_signal
        if (!is.null(dg$blend)) {
          want <- c(rx_path, normp(file.path(root, DTC$rel_engine("V2"))))
          got <- vapply(.or(bs$paths, list()), function(z) normp(z), character(1))
          if (!identical(.or(bs$kind, ""), "engine_blend") || !identical(sort(names(bs)), c("kind", "paths")) || !identical(got, want))
            add(code, ": base_signal ≠ engine_blend [RX0 엔진 · ", DTC$rel_engine("V2"), "]")
          eng_files <- want
        } else {
          want_rel <- if (identical(p$role, "reseed")) DTC$rx0s_rel(root) else DTC$rel_engine(p$rule)   # 재시드 = 매니페스트의 engine_RX0S.R
          want <- normp(file.path(root, want_rel))
          if (!identical(.or(bs$kind, ""), .or(src$base_signal$kind, "")) || !identical(names(bs), names(src$base_signal)) || !identical(normp(.or(bs$path, "")), want))
            add(code, ": base_signal.path ≠ ", want_rel, "(kind · 키는 RX0 그대로)")
          eng_files <- want
        }
        s2 <- s; s2$base_signal <- src$base_signal
        keep <- c("code", "label", "idea", "selection_accounting")
        if (!identical(cj(strip(s2, keep)), cj(strip(src, keep)))) add(code, ": RX0 사양과 base_signal · 이름 · 서술 · 회계 밖이 다르다")
        eb <- basename(eng_files[length(eng_files)])
        if (!grepl(eb, .or(s$label, ""), fixed = TRUE) || !grepl(eb, .or(s$idea, ""), fixed = TRUE)) add(code, ": label · idea 에 엔진 파일 이름(", eb, ") 없음")
      }
      ## 시행 회계
      sa <- s$selection_accounting; n0 <- NA_integer_; nf <- NULL; pairs <- NULL
      if (identical(p$role, "variant")) {
        if (is.null(NFP[[fam]])) NFP[[fam]] <- nf_prior(root, fam)
        n0 <- NFP[[fam]]
        if (!identical(sa$selection_type, "sweep") || !identical(sa$family_root, fam)) add(code, ": 시행 회계 selection_type · family_root 불일치")
        if (!identical(as.character(unlist(sa$lineage)), c(paste0("RX_", ROUND), as.character(unlist(src$selection_accounting$lineage)))))
          add(code, ": 시행 회계 lineage ≠ RX_", ROUND, " + RX0 계보")
        if (!identical(suppressWarnings(as.integer(sa$n_family_at_registration)), as.integer(n0 + N_ROUND)))
          add(code, sprintf(": 시행 회계 n_family %s ≠ 앞선 사전등록 계보 최댓값 %d + 이 라운드 변형 칸 %d", format(.or(sa$n_family_at_registration, "NULL")), n0, N_ROUND))
        if (!nzchar(.or(sa$n_trials_basis, ""))) add(code, ": 시행 회계 n_trials_basis 없음")
        if (length(setdiff(names(sa), c("selection_type", "family_root", "lineage", "n_family_at_registration", "n_trials_basis")))) add(code, ": 변형 시행 회계에 모르는 키")
        if (!grepl(VAR[[p$rule]]$name, .or(s$label, ""), fixed = TRUE)) add(code, ": label 에 규칙 이름 '", VAR[[p$rule]]$name, "' 없음")
        nf <- as.integer(n0 + N_ROUND)
      } else if (p$role %in% c("diagnostic", "reseed")) {
        dd <- if (identical(p$role, "reseed")) RSD[[p$rsd]] else dg            # 진단 · 재시드 = 같은 진단 회계 형식
        sa0 <- src$selection_accounting; sa0$remeasure_of <- NULL; sa0$n_trials_note <- NULL
        pairs <- c(sprintf("P2R05_%s_%s", p$engine, dd$pair), if (isTRUE(dd$pair_e3)) sprintf("P2R05_E3_%s", dd$pair))
        want_sa <- c(sa0, list(diagnostic_of = if (length(pairs) == 1L) pairs else as.list(pairs), control = dd$control))
        got_sa <- sa[intersect(names(sa), names(want_sa))]
        if (!identical(cj(got_sa[names(want_sa)]), cj(want_sa)) || !nzchar(.or(sa$n_trials_note, "")) || !grepl("^DESIGN §", .or(sa$design_ref, "")) ||
            length(setdiff(names(sa), c(names(want_sa), "design_ref", "n_trials_note"))))
          add(code, ": 진단 시행 회계 ≠ RX0 회계(무가산 · remeasure_of 제외) + diagnostic_of · control · design_ref · n_trials_note")
        if (!grepl(dd$tag, .or(s$label, ""), fixed = TRUE)) add(code, ": label 에 '", dd$tag, "' 없음")
      }
      rel_files <- sub(paste0("^", normp(root), "/"), "", eng_files)
      cells[[code]] <- list(code = code, engine = p$engine, component = p$component, role = p$role, path = rp, md5 = md5f(f),
                            rule = p$rule, control = if (!is.null(dg)) dg$control else if (cmp) CMP[[p$cmp]]$control else if (identical(p$role, "reseed")) RSD[[p$rsd]]$control else NULL,
                            diagnostic_of = pairs, blend = if (!is.null(dg$blend)) dg$blend else NULL,
                            n_family = nf, n_prior = n0, n_factors = length(s$factors), base_weight = suppressWarnings(as.numeric(s$base_weight)),
                            engine_files = rel_files, engine_md5 = unname(vapply(file.path(root, rel_files), md5f, character(1))),
                            spec_copy_of = if (p$role %in% c("reference", "comparison")) orig else NULL,
                            remeasure_of = if (identical(p$role, "reference")) src$selection_accounting$remeasure_of else NULL,
                            factor = if (cmp) CMP[[p$cmp]]$factor else NULL,
                            challenge = if (cmp) CMP[[p$cmp]]$challenge else if (identical(p$role, "reseed")) RSD[[p$rsd]]$challenge else NULL)
    }
    list(ok = !length(err), errors = err, cells = cells, n_round = N_ROUND, n_cells = length(pl))
  }
  list(PROGRAM = PROGRAM, ROUND = ROUND, RD_REL = RD_REL, DESIGN_REL = DESIGN_REL, P2R04_RD = P2R04_RD, P2R04_SPECS = P2R04_SPECS, P2R04_PREREG = P2R04_PREREG,
       CRISIS_TYPE = CRISIS_TYPE, DESIGN_NOTES = DESIGN_NOTES, CHARTER_OPEN = CHARTER_OPEN, HOLDS = HOLDS, SPECS_GEN = SPECS_GEN, FACTOR_REGISTRY = FACTOR_REGISTRY, EVALF = EVALF,
       PIN_CATS = PIN_CATS, PKGS = PKGS, TESTF = TESTF, ENG = ENG, VAR = VAR, DIAG = DIAG, CMP = CMP, RSD = RSD, N_ROUND = N_ROUND,
       ops = ops, plan = plan, nf_prior = nf_prior, spec_checks = spec_checks, dtc = .dtc)
})
K <- P2R05_CONST

source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/contracts/measurement_axis.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
args <- commandArgs(trailingOnly = TRUE)
MODE <- if ("--register" %in% args) "register" else if ("--draft" %in% args) "draft" else stop("usage: register.R --draft | --register")
PROGRAM <- K$PROGRAM; ROUND <- K$ROUND
DRAFT_VERSION <- 3L                                                             # 초안을 고쳐 다시 쓸 때 올린다(검토판 보존본과 짝) · v2 = 격리 교차 점검 v1(revise · prereg_draft_review_v1.md) 반영 · v3 = 격리 교차 점검 v2(revise · prereg_draft_review_v2.md) 반영
rel <- function(p) sub(paste0("^", ROOT, "/"), "", gsub("\\\\", "/", p))
P <- rx_paths(PROGRAM, ROUND, ROOT); RD <- P$round_dir
if (!identical(rel(RD), K$RD_REL)) stop("[P2R05] 라운드 디렉터리 해석 불일치: ", RD)
PR <- file.path(P$prereg_dir, "prereg.json"); DR <- file.path(RD, "prereg_draft.json")
.measured_any <- function() length(Sys.glob(file.path(RD, "results", "P2R05_*.json"))) > 0L
if (.measured_any()) stop("[P2R05] 측정 결과가 생긴 뒤에는 사전등록을 바꿀 수 없다(R2)")
if (file.exists(PR)) stop("[P2R05] 사전등록이 이미 있다(R2) — 대체는 측정 전 · 별도 절차로만")
DTC <- K$dtc(ROOT)                                                              # engine_checks.R — P2R05_DTC
LEDGER <- file.path(ROOT, "06_Registry/q_judgment_ledger.json")
DECREG <- file.path(ROOT, "06_Registry/decision_register.json")
J_ROUND_SELECTION <- "J-20261018-006"                                           # 라운드 선택(판단 원장 · J-005 대체 — 판단 T1 R-20261018-007 · 아래에서 존재 · 종류를 단정)
P1_FILE_RX <- "^04_Research/programs/_supervision/superfan/philosophy/[^/]+_P1_P2R05\\.md$"
BCP <- file.path(RD, "behavior_card_cfg_at_prereg.json")
REH <- file.path(RD, "rehearsal", "summary.json")
EXPO_AGENTS <- file.path(RD, "exposures_agents.json")                          # 구현 에이전트 A · B 열람 기록(Q 가 각 보고에서 옮긴다 · 없으면 --register 거부)
EXPO_REQUIRED <- c(A = "구현 에이전트 A", B = "구현 에이전트 B")
cj <- function(x) as.character(toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
P4PRE <- fromJSON(file.path(ROOT, K$P2R04_PREREG), simplifyVector = FALSE)

## ── 준비물 목록(쓰기 전 · 한 번에) — 다른 구현 에이전트 산출(엔진 · 판정 구현 · 리허설)이 없으면 무엇이 없는지 전부 적고 멈춘다 ──
.readiness <- function() {
  miss <- character(0)
  inv <- DTC$inventory(ROOT)
  if (length(inv$missing)) miss <- c(miss, paste0("DT 엔진(구현 에이전트 A): ", inv$missing))
  for (f in K$EVALF) if (!file.exists(file.path(RD, f))) miss <- c(miss, sprintf("평가 경로(%s): %s/%s", if (f %in% c("evaluate.R", "evaluate_fixture.R", "round_rules.R")) "판정 구현 · 에이전트 B" else "측정 기계", K$RD_REL, f))
  rr <- file.path(RD, "round_rules.R")
  if (file.exists(rr)) {
    E <- new.env(parent = globalenv())
    e <- tryCatch({ sys.source(rr, envir = E, keep.source = FALSE); NULL }, error = function(z) conditionMessage(z))
    if (!is.null(e)) miss <- c(miss, paste("round_rules.R 적재 실패:", e))
    else for (fn in c("p2r05_final_selection_rule", "p2r05_rules")) if (!exists(fn, envir = E, mode = "function", inherits = FALSE)) miss <- c(miss, paste0("round_rules.R 함수 없음: ", fn, "()"))
  }
  if (!file.exists(REH)) miss <- c(miss, paste0("리허설 요약 ", rel(REH), "(Rscript rehearse.R — evaluate.R 생긴 뒤)"))
  for (t in K$TESTF) if (!file.exists(file.path(ROOT, t))) miss <- c(miss, paste0("검사 파일: ", t))
  TEV <- DTC$test_evidence_check(ROOT)                                           # DT 시험 증거(격리 점검 v1 권고 9) — 없음 · 실패 = 준비물 미비
  if (length(TEV$pending)) miss <- c(miss, paste0("DT 시험 증거(구현 에이전트 A — tests/run_all_tests.R 느린 판): ", TEV$pending))
  if (length(TEV$errors)) miss <- c(miss, TEV$errors)
  for (f in K$DESIGN_NOTES) if (!file.exists(file.path(ROOT, f))) miss <- c(miss, paste0("설계 입력 노트(격리 점검 v1 권고 2): ", f))
  L <- tryCatch(fromJSON(LEDGER, simplifyVector = FALSE), error = function(z) NULL)
  j <- Filter(function(x) identical(x$id, J_ROUND_SELECTION), L$judgments %||% list())
  if (!length(j) || !identical(j[[1]]$kind, "round_selection")) miss <- c(miss, paste0("판단 원장 라운드 선택 판단 ", J_ROUND_SELECTION, "(kind round_selection)"))
  if (!file.exists(file.path(ROOT, K$DESIGN_REL))) miss <- c(miss, paste0("설계 문서: ", K$DESIGN_REL))
  miss
}
## 판정 구현 정합 — 격리 환경에 evaluate.R 도우미만 적재(본 실행 블록은 sys.nframe 가드)해 사전등록이 평가 시작부 단정을 통과하는지 결과 전에 확인.
##   함수 이름 = P2R05 판 우선 · P2R04 판 다음(판정 구현 쪽이 어느 이름을 쓰든) · 없으면 그 항목 '미확인'(= 정합 실패로 센다)
.eval_consistency <- function(pre_like) {
  E <- new.env(parent = globalenv())
  e <- tryCatch({ source(file.path(RD, "evaluate.R"), local = E); NULL }, error = function(z) conditionMessage(z))
  if (!is.null(e)) stop("[P2R05] evaluate.R 적재 실패 — 정합 확인 불가: ", e)
  pick <- function(c) { h <- c[vapply(c, function(n) exists(n, envir = E, inherits = FALSE), logical(1))]; if (length(h)) h[1] else NA_character_ }
  fk <- pick(c("P2R05_FS_KEYS", "P2R04_FS_KEYS")); cc <- pick(c("p2r05_cells_check", "p2_cells_check")); pm <- pick(c("p2r05_pin_mismatches", "p2_pin_mismatches"))
  out <- list(evaluate_md5 = rk_md5(file.path(RD, "evaluate.R")), names = list(fs_keys = fk, cells_check = cc, pin_mismatches = pm))
  out$fs_keys <- if (!is.na(fk)) { m <- setdiff(get(fk, envir = E), names(pre_like$final_selection_rule)); if (length(m)) paste("결손:", paste(m, collapse = ",")) else "ok" } else "미확인(FS 키 목록 없음)"
  out$cells_check <- if (!is.na(cc)) { m <- get(cc, envir = E)(pre_like$cells); if (length(m)) paste(m, collapse = " / ") else "ok" } else "미확인(칸 검사 함수 없음)"
  out$pins <- if (!is.na(pm)) { m <- get(pm, envir = E)(pre_like, ROOT); if (length(m)) paste(m, collapse = " / ") else "ok" } else "미확인(핀 대조 함수 없음)"
  out$ok <- all(vapply(out[c("fs_keys", "cells_check", "pins")], function(x) identical(x, "ok"), logical(1)))
  out
}
## round_rules.R 호출 — 형식 인자 이름으로 맞춰 넘기고(root · bcfg_path · …), 안 되면 P2R04 관례(root, bcfg_path) 위치 인자로 한 번 더
.call_rr <- function(fn, ctx) {
  fm <- names(formals(fn))
  r <- tryCatch(do.call(fn, ctx[intersect(fm, names(ctx))]), error = function(e) e)
  if (!inherits(r, "error")) return(r)
  r2 <- tryCatch(fn(ctx$root, ctx$bcfg_path), error = function(e) e)
  if (!inherits(r2, "error")) return(r2)
  stop(sprintf("[P2R05] round_rules.R 함수 호출 실패(형식 인자 %s): %s", paste(fm, collapse = ","), conditionMessage(r)))
}
## 규칙 상수 대조 — P2R04 v3 사전등록 final_selection_rule 의 숫자 키 · 판정 어휘 · 기록 위기 목록 = 같은 값(DESIGN §5 · §12 '그대로') · ⑮ tail_instrument 신설 형식
.fs_check <- function(FS, eng_taus) {
  F4 <- P4PRE$final_selection_rule; bad <- character(0)
  num <- names(F4)[vapply(F4, function(v) is.numeric(v) && length(v) == 1L, logical(1))]
  for (k in num) if (!isTRUE(all.equal(suppressWarnings(as.numeric(FS[[k]])), as.numeric(F4[[k]])))) bad <- c(bad, sprintf("%s = %s ≠ P2R04 %s", k, format(FS[[k]] %||% "NULL"), format(F4[[k]])))
  for (k in c("mc8_label_required", "state_unturned_max_drop_crises"))
    if (!identical(as.character(unlist(FS[[k]])), as.character(unlist(F4[[k]])))) bad <- c(bad, sprintf("%s ≠ P2R04 사전등록 값", k))
  ti <- FS$tail_instrument
  if (!is.list(ti)) bad <- c(bad, "tail_instrument(⑮ 꼬리 계기) 없음 — DESIGN §12")
  else {
    for (k in c("tau", "nw_lag", "t_min")) { x <- suppressWarnings(as.numeric(ti[[k]])); if (length(x) != 1L || !is.finite(x)) bad <- c(bad, paste0("tail_instrument$", k, " 가 유한 숫자 1개가 아니다")) }
    for (k in c("ref", "t_min_source")) if (!nzchar(as.character(ti[[k]] %||% "")[1])) bad <- c(bad, paste0("tail_instrument$", k, " 없음"))
    if (length(eng_taus) && is.finite(suppressWarnings(as.numeric(ti$tau))) && !any(abs(as.numeric(ti$tau) - eng_taus) < 1e-12))
      bad <- c(bad, sprintf("tail_instrument$tau %s 가 엔진 분위 집합(.DT_TAUS %s)에 없다", format(ti$tau), paste(eng_taus, collapse = ",")))
  }
  txt <- setdiff(names(F4), c(num, "mc8_label_required", "state_unturned_max_drop_crises"))
  list(bad = bad, numeric_keys = num, text_changed = txt[!vapply(txt, function(k) identical(cj(FS[[k]]), cj(F4[[k]])), logical(1))])
}
## 판정 구현 쪽 문장에 있어야 하는 것(조정자 10-18 — 이 파일은 옮기기만 한다 · 없으면 초안을 쓰지 않는다):
##   같은 추첨 선택 꼬리표(DESIGN §0b 18 · 철학 C-063 — 선택된 V 의 β 짝 승리가 같은 추첨 판독에서 과반 미만이면 P4 · A 후보 전 도훈 확인) · 계기 → 다음 행동(§0b 15 · T1 C-055)
.rr_required <- function(FS, RULES) {
  txt <- paste(cj(FS), cj(RULES))
  c(if (!grepl("같은 추첨", txt, fixed = TRUE)) "선택 꼬리표 '같은 추첨 판독 과반 미만 → P4 · A 후보 전 도훈 확인'(DESIGN §0b 18 · 철학 C-063) 문장이 round_rules.R 에 없다",
    if (!("instrument_action" %in% names(RULES))) "계기 → 다음 행동 표(rules.instrument_action · DESIGN §0b 15 · 판단 T1 C-055) 가 round_rules.R 에 없다")
}
## 규칙 문장 승계 대조 — P2R04 v3 규칙 키는 모두 있어야 하고(DESIGN §5 '그대로 잇는다') ⑮ 문장이 있어야 한다. 같은 문장 · 바뀐 문장 · 새 키를 기록(문구 대조)
.rules_check <- function(RULES) {
  R4 <- P4PRE$rules; bad <- character(0)
  miss <- setdiff(names(R4), names(RULES)); if (length(miss)) bad <- c(bad, paste("P2R04 v3 규칙 키 결손:", paste(miss, collapse = ",")))
  if (!any(c("tail_instrument", "tail_meter", "tail") %in% names(RULES))) bad <- c(bad, "⑮ 꼬리 계기 규칙 문장(rules.tail_instrument) 없음 — DESIGN §5")
  nn <- intersect(names(R4), names(RULES))
  same <- nn[vapply(nn, function(k) identical(cj(RULES[[k]]), cj(R4[[k]])), logical(1))]
  list(bad = bad, inheritance = list(source = list(prereg = K$P2R04_PREREG, md5 = rk_md5(file.path(ROOT, K$P2R04_PREREG))),
                                     identical = as.list(same), changed = as.list(setdiff(nn, same)), added = as.list(setdiff(names(RULES), names(R4)))))
}
.factor_ids <- function(sc) sort(unique(unlist(lapply(sc$cells, function(z) {
  s <- fromJSON(file.path(ROOT, z$path), simplifyVector = FALSE)
  vapply(Filter(function(f) identical(f$kind, "db"), s$factors %||% list()), function(f) as.character(f$id), character(1)) }))))
.ops_pins <- function(sc) {
  OPS <- K$ops(ROOT, DTC)
  miss <- OPS[!file.exists(file.path(ROOT, OPS))]
  if (length(miss)) stop("[P2R05] 운영 경로 파일 없음: ", paste(miss, collapse = ", "))
  wc <- fromJSON(file.path(ROOT, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries
  ents <- lapply(K$PIN_CATS, function(cid) { e <- Filter(function(z) identical(z$catalog_id, cid), wc)
    if (!length(e)) stop("[P2R05] 비중 카탈로그 엔트리 없음: ", cid)
    if (!identical(e[[1]]$status, "active")) stop("[P2R05] 비중 카탈로그 엔트리 status ≠ active: ", cid)
    list(catalog_id = cid, status = e[[1]]$status, resolver = e[[1]]$resolver) })
  FR <- fromJSON(file.path(ROOT, K$FACTOR_REGISTRY), simplifyVector = FALSE)
  fre <- lapply(.factor_ids(sc), function(id) { if (is.null(FR[[id]])) stop("[P2R05] 팩터 레지스트리에 없는 팩터: ", id)
    list(id = id, path = K$FACTOR_REGISTRY, entry = FR[[id]]) })
  ## ★운영 핀 종류 = P2R04 와 같은 다섯(files · catalog_entries · factor_registry_entries · packages · r_version) — 판정 구현의 핀 대조가 모르는 종류를 거부한다.
  ##   DT 엔진 구조 기록(매니페스트 · 정적 PIT · 상수 · 리허설 요약)은 최상위 engines 절(precheck · 등록이 대조)
  list(files = lapply(OPS, function(f) list(path = f, md5 = rk_md5(file.path(ROOT, f)))), catalog_entries = ents, factor_registry_entries = fre,
       packages = setNames(lapply(K$PKGS, function(p) as.character(utils::packageVersion(p))), K$PKGS),
       r_version = R.version.string)
}
.eval_pins <- function() lapply(K$EVALF, function(f) { p <- file.path(RD, f)
  if (!file.exists(p)) stop("[P2R05] 평가 경로 파일 없음(판정 구현 · 측정 절차를 결과 전에 고정해야 한다): ", rel(p))
  list(path = rel(p), md5 = rk_md5(p)) })
.rehearsal <- function() {
  if (!file.exists(REH)) stop("[P2R05] 리허설 요약이 없다 — Rscript rehearse.R 먼저")
  s <- fromJSON(REH, simplifyVector = FALSE)
  if (!isTRUE(s$pass)) stop("[P2R05] 리허설 실패 — 등록하지 않는다")
  for (f in c("evaluate.R", "round_rules.R", "rehearse.R")) {
    k <- c(evaluate.R = "evaluate_md5", round_rules.R = "round_rules_md5", rehearse.R = "rehearse_md5")[[f]]
    if (!identical(s[[k]], rk_md5(file.path(RD, f)))) stop("[P2R05] 리허설 뒤 ", f, " 이 바뀌었다 — 다시 리허설")
  }
  list(script = list(path = rel(file.path(RD, "rehearse.R")), md5 = rk_md5(file.path(RD, "rehearse.R"))), summary = list(path = rel(REH), md5 = rk_md5(REH)),
       evaluate_md5 = s$evaluate_md5, round_rules_md5 = s$round_rules_md5, pass = TRUE, inputs = s$inputs, seconds = s$seconds)
}
## 철학 Superfan P1 수령 확인(P2R03 · P2R04 와 같은 방식 · 거부권이 아니라 '건너뛸 수 없음' — 응답은 수용 · 반박 모두 가능 · superfan_protocol §11)
.p1_check <- function() {
  L <- tryCatch(fromJSON(LEDGER, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(L)) return(list(ok = FALSE, why = "판단 원장 판독 실패"))
  rv <- Filter(function(r) identical(r$role, "philosophy") && identical(r$trigger, "P1") && identical(r$round, ROUND), L$reviews %||% list())
  if (!length(rv)) return(list(ok = FALSE, why = sprintf("이 라운드(%s)의 철학 P1 리뷰가 원장에 없다", ROUND)))
  fl <- vapply(rv, function(r) as.character(r$file %||% NA_character_), character(1))
  bad_f <- fl[is.na(fl) | !grepl(P1_FILE_RX, fl, perl = TRUE) | !file.exists(file.path(ROOT, fl))]
  if (length(bad_f)) return(list(ok = FALSE, why = paste("P1 리뷰 파일이 없거나 이름 형식(…/philosophy/<시각>_P1_P2R05.md)이 아니다:", paste(bad_f, collapse = ","))))
  ids <- unique(unlist(lapply(rv, function(r) unlist(r$challenges))))
  ch <- Filter(function(c) c$id %in% ids && (c$grade %||% "") %in% c("challenge", "stop"), L$challenges %||% list())
  open <- vapply(Filter(function(c) identical(c$status, "open") || !length(c$responses), ch), function(c) c$id, character(1))
  hold <- vapply(Filter(function(c) isTRUE(c$hold_request) && !(c$status %in% c("accepted", "withdrawn", "escalated", "settled")), ch), function(c) c$id, character(1))
  if (length(open)) return(list(ok = FALSE, why = paste("응답 없는 도전:", paste(open, collapse = ","))))
  if (length(hold)) return(list(ok = FALSE, why = paste("열린 보류 요청:", paste(hold, collapse = ","))))
  list(ok = TRUE, reviews = vapply(rv, function(r) r$id, character(1)), files = fl, n_challenges = length(ch),
       statuses = setNames(vapply(ch, function(c) c$status %||% NA_character_, character(1)), vapply(ch, function(c) c$id, character(1))),
       checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
}
## 판단 · 리뷰 연결 — 라운드 선택 판단(고정 id)을 원장에서 단정하고, 대체 사슬(supersedes — J-006 → J-005)을 따라가 이 라운드 리뷰
##   (round = ROUND 또는 사슬의 어느 판단을 대상으로 한 리뷰)를 원장에서 읽는다
.sel_chain <- function(L) { out <- character(0); id <- J_ROUND_SELECTION
  while (length(id) == 1L && !is.na(id) && nzchar(id) && !(id %in% out)) { out <- c(out, id)
    j <- Filter(function(x) identical(x$id, id), L$judgments %||% list()); id <- if (length(j)) as.character(j[[1]]$supersedes %||% NA_character_)[1] else NA_character_ }
  out }
.judgments <- function() {
  L <- fromJSON(LEDGER, simplifyVector = FALSE)
  j <- Filter(function(x) identical(x$id, J_ROUND_SELECTION), L$judgments %||% list())
  if (!length(j) || !identical(j[[1]]$kind, "round_selection")) stop("[P2R05] 판단 원장에 라운드 선택 판단 ", J_ROUND_SELECTION, "(kind round_selection)이 없다")
  chain <- .sel_chain(L)
  tgt <- function(r) any(chain %in% unlist(r$scope %||% list()))
  rv <- Filter(function(r) identical(r$round, ROUND) || tgt(r), L$reviews %||% list())
  list(round_selection = J_ROUND_SELECTION, supersedes_chain = as.list(chain), ledger = rel(LEDGER),
       design = list(path = K$DESIGN_REL, md5 = rk_md5(file.path(ROOT, K$DESIGN_REL))),
       reviews = lapply(rv, function(r) list(id = r$id, role = r$role, trigger = r$trigger, file = r$file %||% NA_character_)))
}
## 철학 Superfan P4(주기 · 프로그램 단위 — 진행 중이면 '미도착' 기록 · 등록 전에 도착하면 열람 항목으로) — 라운드 선택 판단 시각 뒤의 P4 리뷰
.p4_reviews <- function() {
  L <- tryCatch(fromJSON(LEDGER, simplifyVector = FALSE), error = function(e) list())
  j <- Filter(function(x) identical(x$id, J_ROUND_SELECTION), L$judgments %||% list()); t0 <- if (length(j)) as.character(j[[1]]$at %||% "") else ""
  Filter(function(r) identical(r$role, "philosophy") && identical(r$trigger, "P4") && as.character(r$at %||% "") >= t0, L$reviews %||% list())
}
## 보류 · 열린 결정(기록 — 판정 조건 아님): 판단 원장 보류 id 의 상태 · decision_register 열린 헌장 결정의 상태(id · status · default 만 읽는다)
.holds <- function() {
  L <- tryCatch(fromJSON(LEDGER, simplifyVector = FALSE), error = function(e) list())
  lapply(K$HOLDS, function(id) { c0 <- Filter(function(c) identical(c$id, id), L$challenges %||% list())
    list(id = id, source = rel(LEDGER), found = length(c0) > 0L, status = if (length(c0)) c0[[1]]$status %||% NA_character_ else NA_character_,
         hold_request = if (length(c0)) isTRUE(c0[[1]]$hold_request) else NA,
         what = "저변동 틸트 류 P4 · A 승격 전 도훈 확인(철학 Superfan 보류 요청)",
         applies = paste0("이 라운드의 LV 칸(", paste(sprintf("P2R05_%s_LV", K$CMP$LV$engines), collapse = " · "),
                          ")은 비교 기준일 뿐 승격 대상이 아니다 — 판정 표 밖 · 선택 대상 아님 · 2계층 모듈 풀 미등재(QVEST_RP_REGISTER=0)")) })
}
.charter_open <- function() {
  D <- tryCatch(fromJSON(DECREG, simplifyVector = FALSE)$items, error = function(e) list())
  lapply(K$CHARTER_OPEN, function(id) { x <- Filter(function(z) identical(z$id, id), D %||% list())
    list(id = id, found = length(x) > 0L, status = if (length(x)) x[[1]]$status %||% NA_character_ else NA_character_,
         default_until_decided = if (length(x)) x[[1]]$default_until_decided %||% NA_character_ else NA_character_,
         note = "기본값 = 현행 헌장 · 이 라운드 판정 규칙 불변(결정이 나도 이 사전등록은 바꾸지 않는다 — 다음 라운드부터)") })
}
## 설계 입력 md5 — 있으면 핀(없으면 '없음' 기록 · 등록 때 초안과 같아야 한다)
.design_files <- function() c(list(list(key = "design", path = K$DESIGN_REL, md5 = rk_md5(file.path(ROOT, K$DESIGN_REL)))),
                              lapply(names(K$CRISIS_TYPE), function(k) { p <- K$CRISIS_TYPE[[k]]
                                list(key = paste0("crisis_type_classify_", k), path = p, md5 = if (file.exists(file.path(ROOT, p))) rk_md5(file.path(ROOT, p)) else NA_character_) }),
                              lapply(names(K$DESIGN_NOTES), function(k) { p <- K$DESIGN_NOTES[[k]]   # 격리 점검 v1 권고 2
                                list(key = k, path = p, md5 = if (file.exists(file.path(ROOT, p))) rk_md5(file.path(ROOT, p)) else NA_character_) }),
                              list(list(key = "specs_generator", path = K$SPECS_GEN, md5 = rk_md5(file.path(ROOT, K$SPECS_GEN))),
                                   list(key = "p2r04_prereg", path = K$P2R04_PREREG, md5 = rk_md5(file.path(ROOT, K$P2R04_PREREG)))))
## 구현 에이전트 열람(exposures_agents.json — {"agents": [{"who", "what", "when"}]}) · 에이전트 A · B 가 없으면 pending 항목(--register 거부)
##   구현 에이전트 C 는 아래 사전등록 본문의 긴 판 하나만 싣는다(격리 점검 v1 권고 8(i) — 파일의 짧은 판은 같은 열람의 부분집합 · 옮기지 않고 표식만)
EXPO_SELF <- "구현 에이전트 C"
.agent_exposures <- function() {
  x <- if (file.exists(EXPO_AGENTS)) tryCatch(fromJSON(EXPO_AGENTS, simplifyVector = FALSE)$agents, error = function(e) NULL) else NULL
  x <- Filter(function(z) nzchar(as.character(z$who %||% "")) && nzchar(as.character(z$what %||% "")), x %||% list())
  x <- Filter(function(z) !startsWith(as.character(z$who), EXPO_SELF), x)
  out <- lapply(x, function(z) list(what = z$what, when = z$when %||% "2026-10-18", who = z$who, source = rel(EXPO_AGENTS)))
  for (k in names(EXPO_REQUIRED)) if (!any(vapply(x, function(z) startsWith(as.character(z$who), EXPO_REQUIRED[[k]]), logical(1))))
    out[[length(out) + 1L]] <- list(what = paste0("미기입 — Q 가 ", EXPO_REQUIRED[[k]], " 의 보고(연 것 · 보는 창 · 시험 창 수치 열람 여부)를 ", rel(EXPO_AGENTS), " 에 옮긴다"),
                                    when = "2026-10-18", who = EXPO_REQUIRED[[k]], pending = TRUE)
  out
}
## 격리 교차 점검 노출(격리 점검 v1 권고 8(iv) — 점검 에이전트도 같은 하네스) · 리뷰 파일마다 §0 '노출 고지' 줄을 그대로 옮긴다(파일 md5 로 묶음 · 줄이 없으면 표식)
##   등록할 초안의 점검(마지막 판)은 초안 뒤에 생기므로 이 목록에 없다 — 등록 때 reviewed_drafts(리뷰 경로)로 묶인다
.review_exposures <- function() {
  fs <- sort(Sys.glob(file.path(RD, "prereg_draft_review_v*.md")))
  lapply(fs, function(f) {
    L <- readLines(f, encoding = "UTF-8", warn = FALSE)
    h <- L[startsWith(trimws(L), "- 노출 고지")]
    v <- sub("^prereg_draft_review_v([0-9]+)\\.md$", "\\1", basename(f))
    list(what = if (length(h)) paste0("격리 교차 점검 v", v, " 노출 고지(", rel(f), " §0 원문): ", trimws(sub("^[^:]*:", "", h[1])))
                else paste0("격리 교차 점검 v", v, "(", rel(f), ") — '노출 고지' 줄 없음(Q 확인)"),
         when = format(file.mtime(f), "%Y-%m-%d"), who = paste0("격리 교차 점검 에이전트 v", v), file_md5 = rk_md5(f))
  })
}
## 커밋 확인 대상 — 비중 카탈로그 · 팩터 레지스트리 파일은 빼고 쓰이는 엔트리를 내용으로 핀한다(P2R04 승계) · DT 엔진 파일 · 설계 입력 포함
.commit_paths <- function() unique(c(K$TESTF, K$RD_REL, K$ops(ROOT, DTC), DTC$rel_file("pc_rehearsal"),
                                     Filter(function(p) file.exists(file.path(ROOT, p)), c(unname(K$CRISIS_TYPE), unname(K$DESIGN_NOTES), DTC$TEST_EVIDENCE))))   # 설계 입력 · DT 시험 증거(격리 점검 v1 권고 2 · 9)
.uncommitted <- function() {
  s <- suppressWarnings(system2("git", c("-C", ROOT, "status", "--porcelain", "--", .commit_paths()), stdout = TRUE, stderr = FALSE))
  st <- attr(s, "status")
  if (!is.null(st) && !identical(as.integer(st), 0L)) stop("[P2R05] git status 실패(rc ", st, ") — 커밋 상태를 확인할 수 없다")
  s <- s[nzchar(s)]; s[!grepl("prereg_draft|results/|rehearsal/out|warm/", s)]
}
.git_head <- function() {
  h <- suppressWarnings(system2("git", c("-C", ROOT, "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE))
  st <- attr(h, "status"); if ((!is.null(st) && !identical(as.integer(st), 0L)) || !length(h)) NA_character_ else h[1]
}
.run_test <- function(path) {
  o <- suppressWarnings(system2("Rscript", c("--no-environ", shQuote(path)), stdout = TRUE, stderr = TRUE))   # QM_ROOT = 위 Sys.setenv 상속(system2(env=) 금지 · r-portability ①)
  j <- grep('^\\{"test"', o, value = TRUE, perl = TRUE)
  if (length(j)) { r <- fromJSON(j[length(j)]); return(list(path = rel(path), md5 = rk_md5(path), pass = r$pass, fail = r$fail)) }
  list(path = rel(path), md5 = rk_md5(path), pass = NA, fail = NA)
}
## 사전등록 cells — 칸 기록(spec_checks)에서. reference = RX0 · diagnostic = 진단 6 + 비교 기준 2 + 재시드 2(판정 표 밖) · comparison · reseed = 표식 · n_family = 변형만
.cells_of <- function(sc) unname(lapply(sc$cells, function(z) {
  base <- list(code = z$code, engine = z$engine, component = z$component, path = z$path, md5 = z$md5,
               n_family = if (identical(z$role, "variant")) z$n_family else NA, reference = identical(z$role, "reference"),
               diagnostic = z$role %in% c("diagnostic", "comparison", "reseed"))
  extra <- switch(z$role,
    reference = list(spec_copy_of = z$spec_copy_of, remeasure_of = z$remeasure_of, engine_file = z$engine_files, engine_md5 = z$engine_md5, base_weight = z$base_weight),
    reseed = list(reseed = TRUE, control = z$control, diagnostic_of = z$diagnostic_of, challenge = z$challenge, engine_file = z$engine_files, engine_md5 = z$engine_md5,
                  base_weight = z$base_weight),
    variant = list(rule = z$rule, engine_file = z$engine_files, engine_md5 = z$engine_md5, base_weight = z$base_weight),
    diagnostic = list(control = z$control, diagnostic_of = z$diagnostic_of, rule = z$rule, blend = z$blend, engine_file = z$engine_files, engine_md5 = z$engine_md5,
                      base_weight = z$base_weight),
    comparison = list(comparison = TRUE, control = z$control, spec_copy_of = z$spec_copy_of, factor = z$factor, challenge = z$challenge,
                      engine_file = z$engine_files, engine_md5 = z$engine_md5, base_weight = z$base_weight))
  c(base, Filter(Negate(is.null), extra))
}))

if (MODE == "register") {
  if (!file.exists(DR)) stop("[P2R05] 초안이 없다 — --draft 먼저")
  REVIEWED <- Sys.glob(file.path(RD, "prereg_draft_reviewed_v*.json"))
  if (!length(REVIEWED)) stop("[P2R05] 격리 교차 점검 보존본이 없다 — 점검 뒤 등록")
  .last_rev <- file.path(RD, sprintf("prereg_draft_reviewed_v%d.json", DRAFT_VERSION))
  if (!file.exists(.last_rev)) stop(sprintf("[P2R05] 등록할 초안 v%d 의 점검받은 보존본(prereg_draft_reviewed_v%d.json)이 없다 — 점검 뒤 보존하고 등록", DRAFT_VERSION, DRAFT_VERSION))
  if (!identical(rk_md5(DR), rk_md5(.last_rev))) stop("[P2R05] 등록할 초안 md5 ≠ 마지막으로 점검받은 보존본 md5 — 점검받지 않은 초안은 등록하지 않는다")
  pre <- fromJSON(DR, simplifyVector = FALSE)
  if (!length(pre$changes_after_review)) stop("[P2R05] 교차 점검 반영 기록(changes_after_review)이 비었다")
  sc <- K$spec_checks(ROOT, ma_epoch(root = ROOT)$id)
  if (!isTRUE(sc$ok)) stop("[P2R05] 사양 검사 실패:\n", paste(sc$errors, collapse = "\n"))
  if (length(pre$cells) != sc$n_cells) stop("[P2R05] 초안 칸 수 ", length(pre$cells), " ≠ 칸 계획 ", sc$n_cells)
  for (c in pre$cells) if (!identical(rk_md5(file.path(ROOT, c$path)), c$md5)) stop("[P2R05] 사양 md5 ≠ 초안: ", c$code)
  DTE <- DTC$run_all(ROOT, pins = pre$engines, run_diff = TRUE)
  if (!isTRUE(DTE$ok)) stop("[P2R05] DT 엔진 검사 실패(초안 핀 대조 포함):\n", paste(c(DTE$errors, DTE$why_pending), collapse = "\n"))
  PYV <- DTC$python_versions(ROOT)
  if (!identical(cj(PYV[DTC$PY_KEYS]), cj(pre$engines$python[DTC$PY_KEYS]))) stop("[P2R05] 파이썬 판(torch · numpy · pandas · pyarrow) ≠ 초안")
  now <- .ops_pins(sc)
  for (f in pre$operational_pins$files) {
    m <- Filter(function(z) identical(z$path, f$path), now$files)
    if (!length(m) || !identical(m[[1]]$md5, f$md5)) stop("[P2R05] 운영 경로 md5 ≠ 초안(초안 뒤 구현이 바뀌었다): ", f$path)
  }
  if (length(now$files) != length(pre$operational_pins$files)) stop("[P2R05] 운영 경로 목록 ≠ 초안(핀 목록이 바뀌었다 — 초안을 다시 쓴다)")
  if (!identical(now$packages, pre$operational_pins$packages) || !identical(now$r_version, pre$operational_pins$r_version)) stop("[P2R05] 패키지 · R 판 ≠ 초안")
  if (!identical(cj(now$catalog_entries), cj(pre$operational_pins$catalog_entries))) stop("[P2R05] 비중 카탈로그 엔트리 ≠ 초안")
  if (!identical(cj(now$factor_registry_entries), cj(pre$operational_pins$factor_registry_entries))) stop("[P2R05] 팩터 레지스트리 엔트리 ≠ 초안")
  for (f in pre$evaluation$files) if (!identical(rk_md5(file.path(ROOT, f$path)), f$md5)) stop("[P2R05] 평가 경로 md5 ≠ 초안: ", f$path)
  for (t in pre$tests) if (!identical(rk_md5(file.path(ROOT, t$path)), t$md5) || !identical(as.integer(t$fail), 0L)) stop("[P2R05] 검사 파일 변경 또는 실패: ", t$path)
  TDV <- DTC$test_evidence_check(ROOT, pins = pre$tests_dt$files)               # DT 시험 증거 md5 = 초안 핀 · 통과(격리 점검 v1 권고 9)
  if (is.null(pre$tests_dt$files) || !isTRUE(TDV$ok)) stop("[P2R05] DT 시험 증거 ≠ 초안 핀 또는 실패 — 초안을 다시 쓴다:\n  · ", paste(c(if (is.null(pre$tests_dt$files)) "초안에 tests_dt 없음", TDV$pending, TDV$errors), collapse = "\n  · "))
  rh <- .rehearsal()
  if (!identical(rh$evaluate_md5, pre$rehearsal$evaluate_md5) || !identical(rh$summary$md5, pre$rehearsal$summary$md5) ||
      !identical(rh$script$md5, pre$rehearsal$script$md5)) stop("[P2R05] 리허설 기록(evaluate · 요약 · 리허설 스크립트 md5) ≠ 초안")
  if (!identical(rk_md5(file.path(ROOT, pre$behavior_card_cfg$path)), pre$behavior_card_cfg$md5)) stop("[P2R05] 행동 카드 설정 사본 md5 ≠ 초안")
  dnow <- .design_files()
  for (d in pre$design_inputs$files) { m <- Filter(function(z) identical(z$key, d$key), dnow)
    if (!length(m) || !identical(as.character(m[[1]]$md5), as.character(d$md5 %||% NA_character_))) stop("[P2R05] 설계 입력 md5 ≠ 초안(초안 뒤 바뀌었거나 새로 생겼다 — 초안을 다시 쓴다): ", d$path) }
  if (any(vapply(pre$exposures, function(x) isTRUE(x$pending), logical(1)))) stop("[P2R05] 열람 기록 미기입(pending) — ", rel(EXPO_AGENTS), " 를 채우고 초안을 다시 쓴다")
  cc <- .eval_consistency(pre)
  if (!isTRUE(cc$ok)) stop("[P2R05] 판정 구현(evaluate.R)과 사전등록이 맞지 않는다 — 등록하지 않는다: FS ", cc$fs_keys, " · 칸 ", cc$cells_check, " · 핀 ", cc$pins)
  p1 <- .p1_check()                                                              # 철학 P1 수령 · 도전 응답 — 건너뛸 수 없게(도훈 10-17 '철학 Superfan 역할이 검토에서 끝이냐')
  if (!isTRUE(p1$ok)) stop("[P2R05] 철학 Superfan P1 조건 미충족 — 등록하지 않는다: ", p1$why)
  unc <- .uncommitted()
  if (length(unc)) stop("[P2R05] 커밋되지 않은 고정 대상이 있다 — 커밋 뒤 등록:\n", paste(unc, collapse = "\n"))
  pre$status <- "registered"; pre$registered_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); pre$draft_md5 <- rk_md5(DR)
  pre$philosophy_p1 <- p1; pre$evaluate_consistency <- cc
  pre$reviewed_drafts <- lapply(sort(REVIEWED), function(f) list(path = rel(f), md5 = rk_md5(f),
                                                                  review = { m <- sub("_reviewed_", "_review_", sub("\\.json$", ".md", f)); if (file.exists(m)) rel(m) else NA_character_ }))
  pre$git_head_at_register <- .git_head()
  dir.create(P$prereg_dir, recursive = TRUE, showWarnings = FALSE)
  RCOPY <- file.path(RD, "prereg.json")
  tryCatch({
    writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), PR, useBytes = TRUE)
    if (!isTRUE(file.copy(PR, RCOPY, overwrite = TRUE)) || !identical(rk_md5(RCOPY), rk_md5(PR))) stop("라운드 디렉터리 사본 쓰기 실패 · md5 불일치")
    pr_record_round(PROGRAM, list(round_id = ROUND, prereg = rel(PR), prereg_md5 = rk_md5(PR), status = "registered",
                                  n_variants = length(Filter(function(z) !isTRUE(z$reference) && !isTRUE(z$diagnostic), pre$cells)),
                                  n_diagnostic = length(Filter(function(z) isTRUE(z$diagnostic) && !isTRUE(z$comparison) && !isTRUE(z$reseed), pre$cells)),
                                  n_comparison = length(Filter(function(z) isTRUE(z$comparison), pre$cells)),
                                  n_reseed = length(Filter(function(z) isTRUE(z$reseed), pre$cells)),
                                  variants = unname(vapply(pre$cells, function(z) z$code, character(1)))), root = ROOT)
  }, error = function(e) { unlink(c(PR, RCOPY)); stop("[P2R05] 등록 중단 — 사전등록 두 사본을 되돌렸다(등록부 미기록): ", conditionMessage(e)) })
  cat(sprintf("[P2R05] 사전등록 %s (md5 %s) · 사본 %s · 칸 %d(변형 %d · 기준 %d · 재시드 %d · 진단 %d · 비교 기준 %d) · HEAD %s\n", rel(PR), rk_md5(PR), rel(RCOPY), length(pre$cells),
              length(Filter(function(z) !isTRUE(z$reference) && !isTRUE(z$diagnostic), pre$cells)), length(Filter(function(z) isTRUE(z$reference), pre$cells)),
              length(Filter(function(z) isTRUE(z$reseed), pre$cells)),
              length(Filter(function(z) isTRUE(z$diagnostic) && !isTRUE(z$comparison) && !isTRUE(z$reseed), pre$cells)), length(Filter(function(z) isTRUE(z$comparison), pre$cells)),
              pre$git_head_at_register))
  quit(status = 0)
}

## ── 초안 ─────────────────────────────────────────────────────────────────────
##   순서 = 준비물 목록(없는 것 전부) → 싼 결정론 점검(사양 · DT 엔진 · 평가 경로 · 리허설 · 규칙 상수 · 판단 원장 · 판정 구현 정합) → 비싼 검사 실행(약 5분) 나중
RDY <- .readiness()
if (length(RDY)) stop("[P2R05] 초안 준비물이 없다 — 초안을 쓰지 않는다(", length(RDY), "건):\n  · ", paste(RDY, collapse = "\n  · "))
if (DRAFT_VERSION > 1L && !file.exists(file.path(RD, sprintf("prereg_draft_reviewed_v%d.json", DRAFT_VERSION - 1L))))
  stop(sprintf("[P2R05] 초안 v%d 을 쓰기 전에 점검받은 v%d 초안을 prereg_draft_reviewed_v%d.json 으로 보존해야 한다(현 prereg_draft.json 을 그대로 복사)",
               DRAFT_VERSION, DRAFT_VERSION - 1L, DRAFT_VERSION - 1L))
EP <- ma_epoch(root = ROOT)
sc <- K$spec_checks(ROOT, EP$id)
if (!isTRUE(sc$ok)) stop("[P2R05] 사양 검사 실패 — 초안을 쓰지 않는다:\n", paste(sc$errors, collapse = "\n"))
DTE <- DTC$run_all(ROOT, pins = NULL, run_diff = TRUE)
if (!isTRUE(DTE$ok)) stop("[P2R05] DT 엔진 검사 실패 — 초안을 쓰지 않는다:\n", paste(c(DTE$errors, DTE$why_pending), collapse = "\n"))
PYV <- DTC$python_versions(ROOT)
if (!isTRUE(PYV$ok)) stop("[P2R05] 파이썬 판 조회 실패 — ", PYV$why)
ENG_REC <- c(DTE$record, list(python = PYV, rx0_engine = list(path = DTC$RX0_SRC, md5 = rk_md5(file.path(ROOT, DTC$RX0_SRC)))))
EVP <- .eval_pins(); REHS <- .rehearsal(); JD <- .judgments(); OPP <- .ops_pins(sc)
if (!file.exists(BCP)) file.copy(file.path(ROOT, "06_Registry/behavior_card.json"), BCP, overwrite = FALSE)   # 리허설이 먼저 만들었으면 그 사본(같은 원본)
source(file.path(RD, "round_rules.R"))                                          # p2r05_final_selection_rule · p2r05_rules(판정 구현 쪽 정본)
CELLS <- .cells_of(sc)
## round_rules.R 호출 맥락 — 형식 인자 이름이 같은 것만 넘긴다(p2r04_prereg = 경로 문자열 · plan 은 판정 구현 쪽 자기 표를 쓰게 넘기지 않는다)
CTX <- list(root = ROOT, bcfg_path = BCP, p2r04_prereg = file.path(ROOT, K$P2R04_PREREG))
FS <- .call_rr(p2r05_final_selection_rule, CTX)
ETAUS <- suppressWarnings(as.numeric(ENG_REC$constants[[".DT_TAUS"]] %||% numeric(0)))
FSC <- .fs_check(FS, ETAUS)
if (length(FSC$bad)) stop("[P2R05] final_selection_rule ≠ P2R04 v3 사전등록(DESIGN §5 · §12 '그대로' + ⑮ 신설):\n  · ", paste(FSC$bad, collapse = "\n  · "))
RULES <- .call_rr(p2r05_rules, CTX)
RC <- .rules_check(RULES)
if (length(RC$bad)) stop("[P2R05] 규칙 문장(p2r05_rules) 승계 결손:\n  · ", paste(RC$bad, collapse = "\n  · "))
RRQ <- .rr_required(FS, RULES)
if (length(RRQ)) stop("[P2R05] 판정 구현 쪽 문장 결손(조정자 10-18 — round_rules.R 에 넣는다 · 이 파일은 옮기기만 한다):\n  · ", paste(RRQ, collapse = "\n  · "))
CC <- .eval_consistency(list(cells = CELLS, final_selection_rule = FS, operational_pins = OPP, evaluation = list(files = EVP), engines = ENG_REC,
                             behavior_card_cfg = list(path = rel(BCP), md5 = rk_md5(BCP))))
if (!isTRUE(CC$ok)) stop("[P2R05] 판정 구현(evaluate.R)과 초안이 맞지 않는다 — 초안을 쓰지 않는다:\n  FS 키: ", CC$fs_keys, "\n  칸 목록: ", CC$cells_check, "\n  핀: ", CC$pins)
TESTS <- lapply(file.path(ROOT, K$TESTF), .run_test)
for (t in TESTS) if (!identical(as.integer(t$fail), 0L) || !is.finite(as.numeric(t$pass))) stop("[P2R05] 검사 실패 — 초안을 쓰지 않는다: ", t$path, " (", t$pass, "/", t$fail, ")")
TEV <- DTC$test_evidence_check(ROOT)                                            # DT 시험 증거(격리 점검 v1 권고 9) — 준비물 목록이 이미 단정 · 여기서는 핀 기록
if (!isTRUE(TEV$ok)) stop("[P2R05] DT 시험 증거 미비 · 실패 — 초안을 쓰지 않는다:\n  · ", paste(c(TEV$pending, TEV$errors), collapse = "\n  · "))

ROLE_N <- table(factor(vapply(sc$cells, function(z) z$role, ""), levels = c("reference", "reseed", "variant", "diagnostic", "comparison")))
N_DIAG <- as.integer(ROLE_N[["diagnostic"]]); N_CMP <- as.integer(ROLE_N[["comparison"]]); N_REF <- as.integer(ROLE_N[["reference"]]); N_RSD <- as.integer(ROLE_N[["reseed"]])
GROUP_N <- table(vapply(sc$cells, function(z) z$engine, ""))                  # 엔진 묶음 칸 수(E2 11 · E3 5)
N0 <- unique(vapply(Filter(function(z) identical(z$role, "variant"), sc$cells), function(z) as.integer(z$n_prior), integer(1)))
CODES <- function(role, eng = NULL, comp = NULL) unname(vapply(Filter(function(z) identical(z$role, role) && (is.null(eng) || identical(z$engine, eng)) &&
                                                                       (is.null(comp) || z$component %in% comp), sc$cells), function(z) z$code, character(1)))
P4R <- .p4_reviews()
DESIGN_TXT <- sprintf("%s(md5 %s)", K$DESIGN_REL, rk_md5(file.path(ROOT, K$DESIGN_REL)))
R7_TXT <- paste0("계상 사유(조정자 10-18 · 철학 Superfan P2 R-20261018-006 · 판단 T2 R-20261018-005 수용 · DESIGN §0b 12): R7 = 두 성분 — 등록 판독(S 포함)은 P2R04 잡음 밖",
                 "(H4 E2 수익 쪽)이라 계수 0 · 방어 성분(검증 0 ∧ 두 구성 ③ 과반 0)은 P2R03 · P2R04 연속 2회 잡음. P2R05 는 P2R04 결론 범위 5 의 등록된 다음 단계이자 마지막 미측정 원천 ① 의 ",
                 "첫 측정이라 P2 로 연다(이웃 변형 아님) · P2R05 도 방어 성분 잡음이면 P2 를 멈추고(paused) 이유와 함께 도훈께 보고(자율 판단 체계 §4 · 철학 C-20261018-045) · ",
                 "P2 정지 시 다음 프로그램 = P1 다른 기저 수익 엔진(헌장 빈칸 4 '독립 엔진' — 방어 결과가 DNN 엔진의 위기 약점에 묶여 있다) → 그 뒤 P4(골격 유지 · 저변동 류 승격 보류 C-20261018-046 · ",
                 "DESIGN §0b 16 · 판단 T1 C-20261018-056)")
STOP4_TXT <- paste0("P2 정지 보고 4요소(사전 고정 · 철학 C-20261018-064 · DESIGN §0b 19): (1) 레버 × 위기 유형 승패 지도 (2) 철학 머리 문장 성적표와 미측정 형태 목록(막힌 이유 — ",
                    "주간 집행 = 셀 엔진 주간 신호 미구현 · 위기 진행 중 as-of 결합 = 상관 상태로는 반증(_design_notes/crisis_type_asof — 진행 중 ρ̄20 백분위가 두 묶음을 못 가름) · ",
                    "시작 시점 as-of 도 못 가름(crisis_type_classify) · 다른 기저 엔진 = 재료 큐) (3) P4 함의 1줄 (4) 철학 P4 첨부(격리 점검 v1 권고 1(a) · DESIGN §0b 26 · rules.pause_report 와 같은 판)")
V1FORM_TXT <- paste0("V1 = Q50(같은 추첨 중앙값) 순위 보존형 — 꼬리 하위 20% 만 거부하고 중심(q̂50) 순위를 그대로 둔다(RX0 순위가 아니다 · 철학 C-20261018-063 · DESIGN §0b 3 · 11) · ",
                     "V2 = 대체형 — 엔진 점수를 꼬리 점수로 바꾼다(알파 위험 = ⑦)")
SAME_DRAW_TXT <- paste0("같은 추첨 판독(기록 · 비용 0 · 철학 C-20261018-063 · DESIGN §0b 18): 변형(분위 모형)과 RX0(평균 모형)는 같은 시드 · 다른 출력층 초기화(CPU 실측 — ",
                        "은닉층 초기값 · 미니배치 순서 같음 · CPU dropout 마스크 다름) · CUDA dropout 흐름은 공유 추정(코드 구조 추론 · 미실측 — DT README §7 · tests/_out/rng_stream_facts.json) — ",
                        "시드 띠(RX0S · 시드 전체 교체)가 실제 차이를 잰다(보수적으로 넓게) · 두 구성(E2 · E3)은 같은 추첨이라 ",
                        "'두 구성 통과'가 추첨 운을 거르지 못한다 — V 칸을 Q50 기반 β 사본(Q50 × k' · k' = β_V/β_Q50)으로 다시 재고 ⑤ ⑥ ⑦ 을 V − Q50 로 낸다 · ",
                        "선택 꼬리표: 선택된 V 의 β 짝 승리가 같은 추첨 판독에서 과반 미만이면 P4 · A 후보 전 도훈 확인(정본 문장 = round_rules.R)")
ch <- function(item, change, reason) list(item = item, change = change, reason = reason)
## 격리 교차 점검 반영 기록(초안 v2 부터) — 측정 기계 · 등록 쪽(구현 에이전트 C) 항목만. 판정 구현 · 설계 문서 쪽 항목(v1 필수 1 ~ 4 · 권고 1(b) · 3 · 5 ~ 7 · 선택 2 ~ 6)은
##   Q 가 REVIEW_CHANGES_Q 에 덧붙인다(같은 목록 = changes_after_review · 비어 있으면 --register 거부)
REVIEW_CHANGES_C <- if (DRAFT_VERSION >= 2L) lapply(list(
  ch("격리 점검 v1 권고 1(a) — 정지 보고 (2) 문구 두 판", "purpose · 결론 범위 13 · budget.stop_report(STOP4_TXT) = '위기 진행 중 as-of 결합 = 상관 상태로는 반증(_design_notes/crisis_type_asof)' — rules.pause_report · §0b 26 과 같은 판",
     "한 사전등록 안에 '상태 정의 미측정' 과 '상관 상태로는 반증' 두 판"),
  ch("권고 1(c) — changes_after_superfan 옛 이름", "'V1 = 엔진 보존형' → 'V1 = Q50(같은 추첨 중앙값) 순위 보존형'", "vocabulary · 결론 범위 14 정정판과 같게"),
  ch("권고 1(d) — expectations.V2 옛 이름", "'저변동 기계' → '꼬리 회피 기계(방어만 · 복리 없음)'(DESIGN §6 옛 이름을 옮기며 바꿈 표기)", "채점 대상 문장 · P2R05 어휘"),
  ch("권고 1(e) — reseed.note · 같은 추첨 문장(SAME_DRAW_TXT)", paste0("사실대로 — CPU 실측: 은닉층 초기값 · 미니배치 순서 같음 · 출력층 초기화 · CPU dropout 마스크 다름 · CUDA dropout 흐름 공유 = 코드 구조 추론(미실측) · ",
                                                                   "reseed.rng_facts(rng_stream_facts.json md5 · 사실 필드) 핀 · RX0S 띠 = V − RX0 시드 잡음을 보수적으로 넓게"),
     "DT README §7 · tests/_out/rng_stream_facts.json 이 이미 확인한 사실 · DESIGN §3.1 정정 = Q(설계 입력 핀 갱신)"),
  ch("권고 2 — 설계 입력 핀 빈칸", "design_inputs.files 에 onset_state_classify.json · state_turn_classify.md · crisis_type_asof.{R,md,json} md5 · 커밋 대상(.commit_paths) · 준비물 목록",
     "evaluate.R p5_load_onset 이 읽는 판본 · 규칙 근거 파일이 핀 밖이었다"),
  ch("권고 4 — 측정 중 GPU", paste0("measure.sh 폴백(RX0 · RX0S 가 캐시 적중을 못 보이면 V1 단독 = 분위 재학습) 앞에 precheck.R --gpu-gate(다른 Type C 0 까지 대기 · 끄지 않는다 · 최대 2시간 = ",
                                    "refresh_barrier 최대 대기와 같은 운영 값) · 마감 · 조회 실패 = 측정 중단(gpu_busy · rc 9) → warm_cache.sh 로 다시 워밍(--rewarm) 안내"),
     "워밍 센티널이 쓰이면 레인이 자동 재개된다(lane_hold_wait.sh) — 측정 중 GPU 겹침(P2R03 10-18 VRAM 사건 재발 경로)"),
  ch("권고 8 — exposures", paste0("(i) 구현 에이전트 C 를 긴 판 하나로(exposures_agents.json 짧은 판은 옮기지 않음) (ii) Q 목록에 crisis_type_asof 탐침 (iii) Q 목록에 판단 T1 R-20261018-004 · ",
                                  "철학 P2 R-20261018-002 (iv) MEMORY 색인 노출 문장 — 구현 에이전트 C · 설계 초안 에이전트 · 격리 점검(리뷰 §0 원문) · A · B 는 exposures_agents.json 그대로"),
     "열람 기록 완결"),
  ch("권고 9 — DT 시험 증거 핀", "tests_dt = DT 시험 결과 JSON 8(rule_smoke · diff_check_mutation · static_pit · py_e2e · engine_dryrun · pc_mutation · rng_stream_facts · template_diff_check) + README md5 · 통과 기록 — 준비물 · --register · precheck(본 · 워밍 대조)가 다시 대조",
     "test_summary.json 은 마지막 --fast 판 · 정적 PIT(.R)는 내장 파이썬을 못 본다"),
  ch("선택 1 — 머리 주석", "precheck.R · measure.sh · register.R 머리 '사양 14' → 16", "칸 16")), function(z) c(z, list(by = "구현 에이전트 C(측정 기계 · 등록)", review = "prereg_draft_review_v1.md"))) else list()
REVIEW_CHANGES_Q <- if (DRAFT_VERSION >= 2L) lapply(list(              # 판정 구현(구현 에이전트 B · Q 지시) · 설계 문서(Q) 쪽 반영
  ch("격리 점검 v1 필수 1 — '꼬리 회피 기계' 정의 두 판", paste0("판정어 · 결론 꼬리표 한 함수(p5_machine): ⑮ 통과 ∧ ①②③④ ∧ ⑭ ∧ ⑤(수준 ∧ Δ) 통과 ∧ ⑥⑦⑨⑫⑬ 중 하나 미달 · ",
                                                            "미통과 칸에서 ⑤(수준 또는 Δ) 미달 = 새 판정어 asymmetry_unmet('β 비대칭 미달' · 첫 일치 — ⑥ 등이 함께 미달이어도) · ⑤ 수준만 미달인 칸은 통과(⑤ 수준은 통과 조건 밖 · 이름 '노출(β) 방어(⑤ 수준 역행)') · ⑤ Δ 만 미달 = β 비대칭 미달 ∧ 방어 이름 유지(승계 이름 규칙 · v2 필수 2 정정) · 판정어 순서 = 통과 → ⑮ 미달 미시험(계기) → … → 결정 미달 → β 비대칭 미달 → 꼬리 회피 기계 · ",
                                                            "notify.R '복리 미달' → '복리 없음' · 픽스처 N45(⑤ Δ만 · ⑤ 수준만 · ⑮ 만 · ① ⑥ · ⑥ 만 · ⑥ ∧ ⑮) · DESIGN §10.3 같은 문장"),
     "규칙 문장(③④⑭ ∧ ⑥⑦⑨⑫⑬ 하나 미달)과 판정어 함수가 ⑤ · ⑮ 를 달리 다뤄 판정어와 꼬리표가 엇갈렸다(리뷰 재현 R1)"),
  ch("필수 2 — LV '원천 ① 증분 없음' 정의 두 판", "Vk β 짝 승리 위기 ⊆ LV 승리 위기 ∧ 그 위기들에서 tol 안일 때만 · LV 가 못 이긴 깊은 위기를 Vk 가 이기면 'LV 대비 증분 있음' · Vk 승리 0 = 'LV 대비 판독 해당 없음' · 코드 · 규칙 두 곳 · 픽스처 N25 에 리뷰 재현 R2 · R2b",
     "comparison.reading 의 ⊆ 조건이 규칙 문장 · 코드 · 픽스처에 없었다"),
  ch("필수 3 — 결론 범위 옛 문장 둘", "'단일 시드라 시드 잡음 띠가 없다' → 재시드 칸 2 · 시드 띠 · '시드 미결' 꼬리표 / '결합은 사전 분류된 위기 유형 기전' → '위기 유형은 사후로만 보인다(crisis_type_classify · crisis_type_asof) → 결합 기전 없음 · 결합은 별도 사전등록 · 결합 칸 자체 판정 · P4/A/BOOK 전 도훈 확인' · 픽스처 N31 이 새 문구 있음 · 옛 문구 없음 둘 다 단정 · DESIGN §10.8 같은 정정",
     "§0b 14 · 26 과 정반대 문장이 규칙에 남아 있었다"),
  ch("필수 4 — ⑮ 예측표를 측정에 묶기", "evaluate.R 이 측정에 묶인 워밍 센티널(results/warm_sentinel.json)의 qpred{path, md5} 파일 1개만 읽는다(p5_qpred_bound) · 필드 없음 = '예측표 미묶임' → ⑮ 미측정 → V 칸 미시험(계기) · 파일 없음 · md5 불일치 = 평가 중단(사유 기록) · 폴더의 다른 파일 = '판본 다른 예측표 n개' 기록만 · 픽스처 5경우(정상 · 절대 경로 · 미묶임 · md5 불일치 · 파일 없음)",
     "폴더 전체를 읽어 재워밍이 남긴 옛 판본이 평가를 멈추거나 사람 쪽 꼬리 기록을 지울 수 있었다(리뷰 재현 R6 · R6b)"),
  ch("권고 1(b) — '꼭대기 시작 위기' 이름 · 출처 파일", "'상태 미전환 최대 하락 위기'(출처 state_turn_classify.md = final_selection_rule 근거와 같음) · onset_state_classify.json 은 '시작 시점 분류 기록'으로 이름 분리", "허용된 이름 밖 · 결론 범위 10 의 출처 파일 오기"),
  ch("권고 3 — 같은 추첨 꼬리표의 E3", "같은 추첨 판독 · 선택 꼬리표 = Q50 이 있는 구성(E2)만 · E3 = 해당 없음(꼬리표 판정에서 뺀다) — 규칙 문장 두 곳", "'과반 미만 또는 미측정'이 E3 를 미측정으로 읽을 여지"),
  ch("권고 5 — '수평 불일치' 기준", "거부 집합의 다음 보유월 하위 분위 적중 ≤ 기저(1/분위 수)면 '수평 불일치' · 기록 없음 = '수평 판독 미측정'(기존 기록 · 새 숫자 없음) · 결론 문장에 유동성 십분위(V · S · Q50 · RX0 나란히) · 보유 겹침(RX0 대비 · Q50 대비) 실음 · DESIGN §10.5 같은 기준",
     "기준 · 판정 경로가 없는 사후 재량 문장이었다"),
  ch("권고 6 — 유동성 기록 범위", "규칙 문장을 코드와 맞춤(십분위 = Q50 · S1 · S2 · 3분위 귀속 = S1 · S2 · Q50 · LV)", "규칙 '유동성 기록 생략' ↔ 코드 Q50 · S1 · S2 십분위 측정"),
  ch("권고 7 — 다음 행동 A 문구", "''이 학습 설정은 종목 왼꼬리를 배우지 못함(계기 실패 · 원천 ① 반증 아님)' 기록'", "결론 범위 4 와 같은 뜻 · hypothesis_index 오독 방지"),
  ch("권고 1(e) 설계 쪽 — DESIGN §3.1 공통 난수 사실", "CPU 실측(은닉층 초기값 · 미니배치 순서 같음 · 출력층 초기화가 난수를 더 씀 · CPU dropout 다름) · CUDA dropout 흐름 공유는 코드 구조 추정(미실측) → 재시드 칸이 실제 차이를 잰다 · 같은 추첨 판독은 이 문제가 없다",
     "설계 입력 문장이 구현 에이전트 A 의 실측(README §7 · rng_stream_facts.json)과 달랐다"),
  ch("선택 3 — 예측표 읽기", "mmap = FALSE(Windows 매핑 잔존 시 교체 실패 방지 · DT README §9)", "운영 안정")), function(z) c(z, list(by = "Q(판정 구현 = 구현 에이전트 B · 설계 문서 = Q)", review = "prereg_draft_review_v1.md"))) else list()
REVIEW_CHANGES_Q2 <- if (DRAFT_VERSION >= 3L) lapply(list(            # 격리 교차 점검 v2 반영(구현 에이전트 B — 판정 구현 + register.R · measure.sh · DESIGN 문장 · C 작업 종료 · Q 지시 10-18)
  ch("격리 점검 v2 필수 1 — ⑮ 예측표 셀 로그 대조(v1 필수 4 의 나머지)",
     paste0("evaluate.R p5_qpred_log_check: 분위 엔진 칸(V1 · V2 · Q50 · N1 · N2 · S1 · S2 · W2 의 V2 성분 · 재시드 제외) 셀 로그 '[DT qpred] path=' 줄 = 묶인 판(경로 정규화 · md5 — 다르면 평가 중단 · 사유 기록) · ",
            "줄 없음(기저 캐시 적중) = 기록 · 같은 평가 안에서 그 기저 캐시를 실행한 칸의 예측표가 묶인 판이면 연쇄 대조 통과 · 아니면 '⑮ 예측표 셀 로그 대조 불가' 꼬리표(⑮ 판정 유지 · ",
            "워밍은 셀 기저 캐시를 시드하지 않는다 — warm_engine.R 확인) · rules.tail_instrument · failure_semantics · conclusion_names 꼬리표 · 픽스처 N47(같음 · 다름 · md5 다름 · 줄 없음 연쇄 · 대조 불가 · 미묶임) · ",
            "measure.sh:139 문구 = 실제 대조('평가가 칸 셀 로그의 예측표 경로를 묶인 판과 대조해 다르면 멈춘다')"),
     "센티널 판(워밍 Q50 실행분)과 측정 칸이 실제로 쓴 예측표를 대조하는 계기가 없었고 운영 안내는 있다고 적었다(리뷰 재현 · 폴백 · 묶음 사이 다시 워밍 경로)"),
  ch("필수 2 — 이름 문장을 코드에 맞춤(v1 필수 1 의 나머지 · 코드 불변)",
     paste0("결론 범위 3 = rules.conclusion_names 한 정의 · rules.conclusion_names ⑤ 괄호('방어' 이름 = ⑤ 수준만 · Δ 만 미달인 칸은 방어 이름 유지) · β 비대칭 미달 정확 조건(미통과 칸 ⑤ 수준 또는 Δ 미달 · ",
            "⑥ 등과 함께여도) · ⑤ 수준만 미달 = 통과 · DESIGN §10.3 · 변경 기록 v1 필수 1 문장 · 초안 점검(최상위 결론 범위 · conclusion_names 에 옛 정의 문구 없음 단정) · 픽스처 N31 문구 단정"),
     "결론 범위 3 이 옛 정의 그대로였고 괄호 '⑤(수준 ∧ Δ — 방어 이름 조건)' · '⑤ 만 미달 = 방어 이름 없음' 이 코드(p2_defense_name = ⑤ 수준)와 달랐다 — Δ 미달 칸의 방어 이름을 거두는 쪽은 승계 규칙 변경이라 하지 않음"),
  ch("권고 1(a)(b)(c)(d) — 옛 문장 잔여",
     paste0("결론 범위 5 '약하면' → 기준 문장(거부 집합 하위 분위 적중 ≤ 기저 · 기록 없음 = 미측정) · 결론 범위 10 출처 = state_turn_classify.md · evaluate.R 사유 문자열 '꼭대기 시작' → '시작 시점 분류' · ",
            "comparison.reading · expectations.LV = rules.diagnostics_reading 정본 + 같은 첫 일치 문장 · 결론 범위 6 끝 문장 = rules.conclusion_scope 와 같은 문장(위기 유형은 사후로만 보인다 → 결합 기전 없음)"),
     "변경 기록이 고쳤다고 적은 항목 일부가 사전등록 다른 절에 옛 문구로 남아 있었다"),
  ch("권고 2 — DESIGN 옛 문장 8곳", "§0b 4 · 7 · 8 · 11 · 15 · 18 · 19 · §10.3 에 '(→ n · 사전등록 문장으로 대체)' 표시 · 머리말 '§0b 안에서는 뒤 번호 · 사전등록 문장이 이긴다'",
     "설계 입력 핀으로 함께 얼린다"),
  ch("권고 3 — LV 이름 첫 일치 순서", "rules.diagnostics_reading · conclusion_names 에 코드 순서((1) 미결 (2) 해당 없음 (3) 증분 있음 (4) 증분 없음)를 첫 일치로 명시", "두 경우가 두 이름에 함께 걸리는 문장(리뷰 재현 L1 · L2)"),
  ch("권고 5 — 측정 묶음 센티널 사본 실패 의미", "measure.sh 의 results/warm_sentinel.json 사본 cp 실패 = 측정 중단(센티널 sentinel_copy_failed · rc 11) · notify_done.sh · notify.R 사유 추가",
     "사본이 없으면 평가가 night_state 판(측정 뒤 다시 워밍되면 다른 판)으로 묶는다"),
  ch("권고 6 — 리허설 묶음 경로 · 셀 로그 대조", "rehearse.R R4 = 합성 센티널(qpred 상대 경로 · md5) → p5_warm_resolve → p5_qpred_bound → p5_tail_block · R10 = 셀 로그 대조(같음 · 다름 · 줄 없음 연쇄 · 대조 불가)",
     "리허설이 p5_qpred_bound 를 거치지 않았다"),
  ch("선택 4 — notify.R 판정어 이름", "asymmetry_unmet 이름 = 판정 구현 P2R05_VERDICT_NAMES 와 같은 글자 · 주석 정정", "주석은 '같은 이름'이라 적었으나 글자가 달랐다")),
  function(z) c(z, list(by = "구현 에이전트 B(판정 구현 · v2 에서 register.R · measure.sh · DESIGN 문장 포함 — C 작업 종료 · Q 지시)", review = "prereg_draft_review_v2.md"))) else list()
pre <- list(
  schema = "rx_prereg_v1", program = PROGRAM, round_id = ROUND, status = "draft", draft_version = DRAFT_VERSION,
  drafted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  judgments = JD,
  exposures = c(   # DESIGN §8.3 + 조정자 지시(10-18) + 구현 에이전트 3 — Q 의 P2R04 exposures 는 그대로 승계(표식)
    lapply(P4PRE$exposures, function(x) c(x, list(inherited_from = "P2R04 사전등록 exposures(Q 는 같은 노출 상태 그대로)"))),
    list(
      list(what = "P2R04 결과 열람 — 보는 창 평가(evaluation_visible.json) · 실패 지도(failure_map) · 전기간 누적 차트 렌더링 확인", when = "2026-10-18", who = "Q(세션)"),
      list(what = "판단 Superfan T2 R-20261018-005(P2R04 판정 해석 리뷰) · 철학 Superfan P2 R-20261018-006(P2R04 방향 판정) — 둘 다 P2R04 보는 창 수치 인용", when = "2026-10-18", who = "Q(세션)"),
      list(what = "판단 Superfan T1 R-20261018-007(라운드 선택 J-20261018-005 리뷰 · C-054 ~ 059 · J-20261018-006 으로 대체)", when = "2026-10-18", who = "Q(세션)"),
      list(what = "철학 Superfan P1 R-20261018-008(설계 정렬 리뷰 · C-063 ~ 071) — 보는 창 수치 인용 없음 · 설계만", when = "2026-10-18", who = "Q(세션)"),
      list(what = paste0("Q 가 계산한 위기 유형 탐침 04_Research/programs/P2_DEFENSE/_design_notes/crisis_type_classify.{md,json} — 위생 유니버스 일수익만 · ≤ 2022-12-31 · ",
                         "전략 성과 무관 · 결과 뒤 질문이라 측도 · 판정식을 계산 전 고정 · 반증 판정 '지지' 1/6 · 시작 시점 as-of 는 못 가름"), when = "2026-10-18", who = "Q(세션)"),
      list(what = paste0("Q 가 계산한 위기 진행 중 as-of 상태 탐침 04_Research/programs/P2_DEFENSE/_design_notes/crisis_type_asof.{R,md,json} — 벤치 · 위생 유니버스 일수익만 · ≤ 2022-12-31 · ",
                         "10-18 Q 계산 · 전략 성과 무관 · 판정 = 진행 중 ρ̄20 백분위가 두 묶음(systemic · dispersed)을 못 가름(상관 상태로는 반증) — rules.pause_report · DESIGN §0b 26 · ",
                         "정지 보고 (2) 의 근거(격리 점검 v1 권고 8(ii))"), when = "2026-10-18", who = "Q(세션)"),
      list(what = paste0("판단 Superfan T1 R-20261018-004 · 철학 Superfan P2 R-20261018-002 — P2R03 RX0 보는 창 계약 산출 수치 인용(expectations.note 기준선의 출처 · ",
                         "S · Calmar · CAGR · Sharpe · β 비 · 포착 · α · 회전 · 위기 목록 — 격리 점검 v1 권고 8(iii))"), when = "2026-10-18", who = "Q(세션)")),
    if (length(P4R)) lapply(P4R, function(r) list(what = paste0("철학 Superfan P4 ", r$id, "(주기 · 프로그램 단위 · ", r$file %||% "파일 없음", ")"), when = substr(r$at %||% "", 1L, 10L), who = "Q(세션)"))
    else list(list(what = "철학 Superfan P4(주기 · 프로그램 단위) — 진행 중 · 이 초안 시점 원장에 없음(등록 전에 도착하면 초안을 다시 써 이 자리에 옮긴다)", when = "2026-10-18",
                   who = "Q(세션)", awaiting = TRUE)),
    list(
      list(what = paste0("설계 초안 에이전트(DESIGN §8.3) — P2R03 DESIGN · prereg rules 문장 · specs · measure_now_vram.sh · lane_pause.py / P2R04 DESIGN · register.R · evaluate.R · ",
                         "round_rules.R · measure.sh · precheck.R · specs / 판단 T1 R-20261018-004 · 철학 P2 R-20261018-002(보는 창 수치) / 헌장 · 자율 판단 체계 · research-program SKILL / ",
                         "engine.R · dnn_rolling.py · schedule.parquet · diag.parquet(시간 · 행 수 열만) · rf_cell_engine.R · rf_base_cache.R · measurement_axis.R · ",
                         "distribution_target_screen.R(머리) / 등록부 P2 블록 · reinforce_auto_config.json 레인 블록 / nvidia-smi · 문헌 · ",
                         "구 축 · 전기간 수치 = hypothesis_index 조회의 L-AR-20260822_193000 lesson_text(FQ-233 arm B 전기간 PORT_t · MDD · Calmar) · 같은 조회 출력의 다른 계열 제목 · ",
                         "measurement-graduation.md 08-22 패널 통계 · 기억 카드(v8.4 평균 표적 꼬리) — 설계 근거엔 기전 문장만 · 이름만 = P2R03 results/ 파일 목록 · ",
                         "열지 않음 = P2R03 evaluation_visible · full · results/<칸>/ · 로그 · visual/ · authoritative_remeasure.json · 모든 pred.parquet / ",
                         "하네스 자동 주입 MEMORY 색인 문장 노출(같은 하네스 공통 — 시험 창 시장 사실 · 기간 미표기 요약 문장 포함 · 격리 점검 v1 권고 8(iv)) — 설계 근거엔 기전 문장만"),
           when = "2026-10-18", who = "설계 초안 에이전트")),
    .agent_exposures(),
    list(
      list(what = paste0("구현 에이전트 C(측정 기계 — 사양 16 · make_specs.py · engine_checks.R · precheck · warm_cache.sh · warm_engine.R · measure · fingerprint · notify · register · rehearse 골격) — ",
                         "DESIGN_draft.md 전문 두 번(§0b 의 P2R04 판정 보는 창 기록 문장 · §0b 7 위기 유형 ρ̄_W 값 · §6 RX0 보는 창 기준선 수치 포함) · ",
                         "P2R04 register.R(expectations 의 P2R02 구 축 보는 창 비율 문장 포함) · precheck.R · measure*.sh · fingerprint.sh · notify*.{sh,R} · rehearse.R · round_rules.R · ",
                         "specs(RX0 · H1 · N0 · W2 · E3 H1 · W1) · evaluate.R 정의부(함수 목록 · p2_cells_check · p2_pin_mismatches · p2_fingerprint) · ",
                         "P2R04 사전등록 prereg.json(구조 · exposures · operational_pins · cells · final_selection_rule · rules 키 · budget · tests 통과 수 · 리허설 요약 필드 — 결과 수치 없음) / ",
                         "P2R03 lane_pause.py · measure_now_vram.sh / 하네스 코드(rf_cell_engine.R · rf_cell_worker.R · run_paper_replication.R 적재 · 측정 축 주입부 · measurement_axis.R · ",
                         "backtest_harness.R 머리 · config.R 캐시 경로 · refresh_barrier.sh 종료 코드 · lookahead_detector.R 머리 · 패턴 목록 + RX0 engine.R 정적 검사 1회 · rx_round.R · program_registry.R · ",
                         "round_kit.R · eval_parallel.sh · detached_env.sh · measure_round_cell.R · r-portability.md) · RP_AUTO_2002_06975/engine.R 3판 코드 / ",
                         "구현 에이전트 A 산출(engines_manifest.json · template_diff_check.R 머리 · 엔진 상수 · CODE_VERSION · 예측표 · 진행 줄 · diag 열 이름 줄 — 코드만) · ",
                         "구현 에이전트 B 산출(round_rules.R 머리 · 칸 표 · final_selection_rule · 키 이름 줄 — 코드만) / 판단 원장 구조(id · kind · role · trigger · round · scope · file · at · ",
                         "status · hold_request · 응답 수 필드만 — J-20261018-001 ~ 006 · R-20261018-005 ~ 008 · C-20261018-038 · 045 · 046 · 063 ~ 071) · decision_register 의 ",
                         "CHARTER-GAPS-4 · 5 · 6 상태 · 앞선 사전등록 cells 의 n_family(계보 최댓값 계산) · reinforce_auto_config.json replication_lane(켜짐 · 정지 · 재개 기록) · ",
                         "nvidia-smi(GPU 메모리 · Type C 표) · _design_notes 파일 목록(crisis_type_classify · onset_state_classify · state_turn_classify · crisis_type_asof 는 md5 만) — ",
                         "판정 규칙 · 상수 · 기대 문장 미작성(DESIGN · round_rules.R 옮김) / 초안 v1 뒤(격리 점검 v1 반영): 격리 교차 점검 리뷰 prereg_draft_review_v1.md(권고 · 선택 · §0 노출 고지 — ",
                         "사전등록 · DESIGN 의 보는 창 수치 인용 문장 포함) · DT README 머리 목차 · §7 · §8 · §9 항목 13(공통 난수 사실 · RX0S · 정적 PIT 사각) · DT tests/_out 결과 JSON 의 머리 스칼라(ok · n · n_ok · 뮤턴트 이름 · ",
                         "양성 대조 발화 · rng_stream_facts 사실 필드 — 합성 데이터 시험 · 성과 수치 없음) · exposures_agents.json(A · B · C 항목) · Q 의 lane_hold_wait.sh 머리 · 라운드 디렉터리 파일 목록 · ",
                         "DT engine_template.R 예측표 쓰기 구역 · evaluate.R 의 p5_warm_resolve · p5_qpred_bound · p5_tail_instrument 코드(워밍 센티널 qpred 계약 확인 — 코드만) · ",
                         "열지 않음 = P2R03 · P2R04 results/ · evaluate*.log · failure_map · visual/ · ROUND_REPORT · stage_artifacts/replication · authoritative_remeasure.json · ",
                         "판단 원장 도전 · 리뷰 본문(Superfan) · 모든 예측 · 진단 parquet · 하네스 자동 주입 MEMORY 색인 문장 노출(시험 창 시장 사실 · 기간 미표기 요약 — 예: 2026-06~07 KOSPI200 급락 · ",
                         "DNN 계열 α t · MDD 요약 · 격리 점검 v1 권고 8(iv)) — 설계 · 상수 · 판정 문장에 쓰지 않음 · 시험 창(2023~) 전략 성과 수치 열람: 아니오"),
           when = "2026-10-18", who = "구현 에이전트 C(측정 기계)",
           merged = "exposures_agents.json 의 구현 에이전트 C 짧은 판(Q 기록 — 같은 열람의 부분집합)을 이 긴 판 하나로(격리 점검 v1 권고 8(i))")),
    .review_exposures(),
    list(
      list(assessment = paste0("Q 는 시험 창 수치를 본 상태다(τ_D 노출 · P2R04 exposures 승계). 판정 · 선택 규칙은 보는 창(≤ 2022-12-31) 지표로만 쓰고 시험 창은 사람 쪽 보고 전용이다. ",
                               "P2R04 판정 뒤 등록(DESIGN §0b 결정 10) — 규칙 상수는 P2R04 v3 그대로라 P2R04 결과가 상수를 바꾸지 않았음을 문구 대조로 묶는다(final_selection_rule 숫자 키 = P2R04 값 기계 대조 · ",
                               "rules_inheritance 같은 문장 · 바뀐 문장 · 새 키 기록). 소비 규칙 2종 · 진단 6 · 비교 기준 2 · 재시드 2 는 원리(DESIGN §3 · §4) · 판단 T2 C-038 · 판단 T1 C-054 로 골랐고 ",
                               "시험 창 성과로 고르지 않았다.")))),
  purpose = paste0("평균 대신 분포를 배우게 하면(같은 특징 · 같은 학습 일정 · 표적만 분포 — 비대칭 원천 ① 분포 표적 · DESIGN §1) 그 분포의 왼꼬리로 고른 보유가 같은 β 의 정적 현금 사본(β 짝)보다 ",
                   "깊은 위기 · 빠른 급락에서 덜 빠지고(③ · ④) 크기 · 노출 짝을 넘는 선택 방어(⑭)이면서 엔진의 강세 참여 · 알파 · 복리를 지키는가 — 순위 표적의 왼꼬리는 시장 공통 충격을 뺀 ",
                   "상대 꼬리라 β 짝이 지울 수 없는 선택 성분을 겨눈다(§3.2 · 부록 A). 처치 = 보유 선택만(완전 투자 · 시점 신호 없음 — D4 시장 수준 꼬리 사이징과 다른 물체 · §1.3). ",
                   V1FORM_TXT, ". 등록부 P2_DEFENSE · 병목 = 급락기 낙폭(엔진 = 시장 동행). ", R7_TXT, " · ", STOP4_TXT),
  conclusion_scope = c(   # DESIGN §10(정본 = 이 사전등록) + §0b(6 ~ 22 정정판 — 1 · 3 · 4 와 표 7행의 옛 문장은 대체됐다 · 철학 C-066) + 조정자 지시
    paste0("1 이 결과는 '2002.06975 DNN5 · 31 특징 · 순위 재척도 5일 표적의 조건부 분위(τ 0.1 · 0.5 · 0.9 · 합성 pinball · 분위 모형 단일 시드) × 두 소비 규칙(V1 거부 · V2 q10 순위) × ",
           "같은 DNN 기저의 두 구성(E2 · E3) · 이 축(", EP$id, ") · 월간 집행'의 효과다 — 분포 표적 학습 일반으로 넓히지 않는다. 두 구성은 같은 학습 추첨이라 '두 구성 통과'는 독립 엔진 강건성도, ",
           "추첨 운을 거른 결과도 아니다(같은 추첨 판독 · 결론 범위 15). 반증이면 교훈 카드 · hypothesis_index 에 '원천 ① 첫 측정 — 이 형태 반증'으로 적는다(C-009 · 금지 목록화 방지)."),
    paste0("2 이름 규칙: '방어'는 ③ ∧ ④ ∧ ⑤(수준) ∧ ⑭ 일 때만 · '선택(특성) 방어'는 크기 × β 짝까지 넘을 때만 · '꼬리 학습 방어'는 진단 읽기 '꼬리 고유'(Vk 승리 ∧ 그 위기에서 Sk · Nk · Q50 ",
           "모두 미승 ∧ 꼬리 증분 — 정의 = 판정 구현 쪽 rules · DESIGN §0b 17 · 20) 일 때만 · 같은 위기를 S 짝이 이겼으면 '변동성 대리 방어' · Q50 이 이겼으면 '중심 표적 효과' · N 짝이 이겼으면 '희석 몫' · ",
           "LV 대비 이름 = rules.diagnostics_reading 첫 일치('원천 ① 증분 없음(저용량 변동성 스크린과 같음)'은 Vk β 짝 승리 깊은 위기 ≥ 1 ∧ ⊆ LV 승리 위기 ∧ 그 위기들에서 tol 안일 때만 · ",
           "Vk 승리 0 = 'LV 대비 판독 해당 없음' · DESIGN §0b 8) · 시드 띠 안 결정 = '시드 미결' 꼬리표 · ⑭ 미측정(selection_unmeasured)이면 방어 이름 보류(크기 · 노출 방어로 접지 않는다)."),
    paste0("3 '꼬리 회피 기계(방어만 · 복리 없음)' = rules.conclusion_names 의 한 정의(판정어 · 결론 꼬리표 공용 p5_machine — 격리 점검 v1 필수 1 · v2 필수 2): ⑮ 통과 ∧ ① ∧ ② ∧ ③ ∧ ④ ∧ ⑭ ∧ ",
           "⑤(수준 ∧ Δ) 를 넘었으나 ⑥ · ⑦ · ⑨ · ⑫ · ⑬ 중 하나 이상 미달인 미통과 칸. 판정어 첫 일치: 통과 → ⑮ 미달 = 미시험(계기) → β 대조 미측정 → 빠른 급락 미측정 → 노출 방어 → ",
           "⑭ 미측정 → 크기 · 노출 방어 → 결정 미달(① ~ ④ 중 미달) → β 비대칭 미달(미통과 칸에서 ⑤ 수준 또는 Δ 미달 — ⑥ 등이 함께 미달이어도) → 꼬리 회피 기계. ",
           "통과 조건(13개 · ⑤ = Δ)은 그대로 — ⑤ 수준만 미달이고 나머지가 모두 통과면 그 칸은 통과다(⑤ 수준은 통과 조건 밖 · 이름 '노출(β) 방어(⑤ 수준 역행)') · ",
           "⑤ Δ 만 미달 = 판정어 β 비대칭 미달 ∧ 방어 이름 유지(승계 이름 규칙 — '방어'는 ⑤ 수준만 본다)."),
    "4 ⑮ 꼬리 계기 미달 = 미시험(계기) — 원천 ① 의 반증이 아니라 '이 학습 설정이 종목 왼꼬리를 배우지 못했다'(V 칸 4개 모두 미시험) · 처분 = 계기 → 다음 행동 표(rules.instrument_action).",
    paste0("5 5일 분포 예측을 월간 보유로 소비한다(엔진 changed(3) 승계) — 거부 집합의 다음 보유월 하위 분위 적중 ≤ 기저(1/분위 수)이면 V 칸 결론에 '수평 불일치' · ",
           "전이 기록이 없으면 '수평 판독 미측정'(rules.conclusion_names 수평 꼬리표 · 기존 기록 · 새 숫자 없음 · 격리 점검 v2 권고 1(a))."),
    paste0("6 합집합 결합 금지(DESIGN §0b 9 · 판단 T2 C-20261018-003 · C-20261018-038 · 철학 P1 C-019): P2R03 D5 · D7(2008 · 2020 2차 다리 승)과 P2R04 H2 · W2(2011 · 2021 승)를 합치면 ",
           "깊은 위기 4/4 가 기계적으로 나온다 — 위기별 승패 지도의 합집합으로 결합 · 선택 규칙을 짜지 않는다 · 이 라운드 비교 기준 LV 와의 결합도 같다. 위기 유형은 사후로만 보인다",
           "(crisis_type_classify · crisis_type_asof — 시작 시점 · 진행 중 as-of 모두 못 가름) → 결합 기전 없음 · 결합은 별도 사전등록 · 결합 칸 자체 판정 · P4/A/BOOK 전 도훈 확인(rules.conclusion_scope 와 같은 문장)."),
    "7 기준점 둘(엔진 대비 · 시장 대비)을 함께 적는다 — 순위 표적은 등가중 횡단면 대비 상대 꼬리라 시장(KOSPI200 · 시총가중) 대비 방어와 같지 않다.",
    paste0("8 시드 띠(DESIGN §0b 14 · 판단 T1 C-20261018-054 — 열린 질문 2 결정을 뒤집음): 같은 구성 재시드 칸(", paste(CODES("reseed"), collapse = " · "),
           " — RX0 와 .SEED_BASE 한 줄만 다른 평균 DNN) 대 RX0 의 위기별 |포착 차| · S 띠 = |S 차| — 띠 안 결정에 '시드 미결' 꼬리표(판정 불변) · 분위 모형 자체의 재시드는 없다(V 칸 = 단일 시드)."),
    paste0("9 희석 몫(무작위 제외 · N1 · N2)을 결론 문장에 적는다 — P2R04 무작위 순열 N0 의 위기 개선은 비깊은 위기 한정(깊은 위기 1/4)이라 '엔진 보유가 위기에 무작위보다 약하다'는 병목 밖 위기의 ",
           "이야기다. 엔진 안 처치의 근거는 희석이 아니라 (i) 원천 ① 미측정(프론티어 ①) (ii) 외부 틸트가 이름 70~80% 를 바꿔 알파 · 강세를 잃었다는 것 (iii) P2R04 의 '늘 켜짐 대 조건부' 대조다 ",
           "(DESIGN §0b 6 · T2 C-038 · 철학 C-066 — 옛 §0b 1 · 3 문장 대체)."),
    paste0("10 위기 유형별 β 짝 승패는 기록뿐(판정 · 선택 · 결합에 쓰지 않는다 · DESIGN §0b 10 — 옛 §0b 4 대체 · 철학 N-⑦): 이름은 설계 노트 · 기전 탐침의 것만 — '상태 미전환 최대 하락 위기'",
           "(state_turn_classify.md — final_selection_rule 근거와 같은 파일 · onset_state_classify.json 은 시작 시점 분류 기록 · 격리 점검 v2 권고 1(b)) · 'systemic / dispersed'(crisis_type_classify — ",
           "위기 구간 평균 쌍별 상관 ρ̄_W · 판정 창 7위기 중앙값 문턱 · 경계 위기 2011-05 는 경계 표시와 함께) · 같은 줄에 ⑤ · ⑭(C-067)."),
    "11 V · S · Q50 · RX0 의 위기 중 보유 유동성 · 크기 십분위를 나란히 결론 문장에 적는다(DESIGN §0b 5 · C-069 — 순위 표적 + 거래대금 특징이 얇은 거래 종목을 '안전'으로 배울 통로).",
    paste0("12 비교 기준 LV(", paste(CODES("comparison"), collapse = " · "), " — P2R04 W2 저변동 스크린 사본)는 판정 표 밖 · 선택 대상 아님 · 승격 대상 아님(판단 원장 보류 C-20261018-046 — ",
           "저변동 틸트 류 P4 · A 승격 전 도훈 확인) · LV 대비 판독은 LV 가 β 짝을 이긴 깊은 위기에서만(아니면 'LV 대비 판독 미결' · 판단 T1 C-058 · DESIGN §0b 8 · 17)."),
    paste0("13 ", R7_TXT, " · ", STOP4_TXT, "."),
    paste0("14 ", V1FORM_TXT, " — 두 형태의 RX0 대비 · Q50 대비 보유 겹침을 결론 문장에(DESIGN §0b 11 · 21 · C-068 · 헌장 빈칸 '엔진 보존의 단위' — CHARTER-GAPS-5 · 기본값 = 결과 판정 그대로)."),
    paste0("15 ", SAME_DRAW_TXT, "."),
    "16 열린 헌장 결정 CHARTER-GAPS-4 · 5 · 6(6 = 엔진 동일성 · '추첨 행운' 실패 형태 · '학습 방어' 이름은 비학습 판을 넘어야 하는가 — DESIGN §0b 22) — 기본값 = 현행 헌장 · 이 라운드 판정 불변."),
  candidates = list(   # DESIGN §3.5
    estimand = list(
      selected = list(list(item = "분위 회귀(다분위 머리 · 합성 pinball)", reason = "같은 표적 변수의 추정 대상만 바꾼다 · 분위는 pinball 로 elicitable(Gneiting 2011)")),
      excluded = list(
        list(item = "분포 회귀(문턱별 이진 · CDF 머리 — Chernozhukov, Fernández-Val & Melly 2013 · Barunik & Hanus 2022)", reason = "순위 표적은 주변분포가 균등이라 분위와 같은 정보(역함수) · 시행 수 · 극단 문턱 라벨 희소(DIST-AR-056 'UNDERPOWERED_LABEL')"),
        list(item = "ES 머리", reason = "ES 단독은 손실 함수가 없다(Gneiting 2011) · (VaR, ES) 공동 점수(Fissler & Ziegel 2016)에는 함수 선택 모수"),
        list(item = "모수 분포(가우스 혼합 · 왜도 t 우도)", reason = "모양 가정 · 유계 순위 표적과 맞지 않는다"),
        list(item = "절대 수익 표적의 분위", reason = "열린 질문 1 결정 — 처치 2개 · β · 총변동 재학습의 사전 확률(P2R04 가 같은 축을 쟀다)"),
        list(item = "하락 주 조건부 표적", reason = "학습 표본 선택이라 '표적만 바꾸는 처치'가 아니다(다음 탐침)"),
        list(item = "9 분위(십분위) 머리", reason = "열린 질문 4 결정 — 세 머리로 충분 · 머리 수 격자 금지"))),
    consumption = list(
      selected = lapply(names(K$VAR), function(v) list(code = v, name = K$VAR[[v]]$name, form = K$VAR[[v]]$form, rule = K$VAR[[v]]$rule, basis = K$VAR[[v]]$basis)),
      excluded = list(
        list(item = "2단 풀(q50 상위 50 → q10 상위 25)", reason = "풀 크기 2배는 관례 모수 · V1 과 같은 원리(제약형)"),
        list(item = "혼합 (q10 + q50)/2(λ 0.5)", reason = "λ 근거 없음 · 격자 금지(열린 질문 3 결정)"),
        list(item = "하방 폭 s 상위 20% 거부", reason = "중심과 무관하게 폭으로 거부하면 고중심 종목을 깎는다(알파 위험) · 제약형 대표 = V1"),
        list(item = "예측 왜도(Kelley) 순위", reason = "양의 왜도 = 복권형 · 기대수익 낮음(Bali, Cakici & Whitelaw 2011) · 방어 표적 아님 — 기록만"),
        list(item = "분위로 비중 조절", reason = "사이징 = 과거 negative 형태(CLAUDE.md) · 이 라운드는 선택만"),
        list(item = "종목 q10 평균으로 총노출 조절", reason = "시변 노출 = D4 와 같은 물체(C-009)"),
        list(item = "상태 조건부 꼬리 거부(V3 — 위기 진행 중 as-of 상태)", reason = "이번엔 넣지 않음 — 계기 → 다음 행동 표의 다음 장치(DESIGN §0b 15 · 판단 T1 C-055)"))),
    configurations = list(selected = c("E2", "E3"), reason = "P2R03 · P2R04 와 같은 두 구성(같은 DNN 기저 · 같은 학습 추첨 · 독립 엔진 아님) — 비교 가능")),
  measurement_axis = list(epoch = EP$id), tau_d = "2022-12-31",
  reference = list(
    baseline = paste0("같은 구성 RX0(평균 표적 · 같은 배치 재측정 · P2R04_E?_RX0 사양 사본 · 시행 수 무가산 · 카탈로그 미등재(QVEST_RP_REGISTER=0)) — 반증 · 비열등 · β 짝 원천 · ",
                      "DNN 평균 캐시 적중을 기대하나 데이터 판본이 바뀌면 그 달만 재학습(워밍 ⑥ · 내용 주소 키)"),
    beta_copy = P4PRE$reference$beta_copy, matched_controls = P4PRE$reference$matched_controls, size_beta_copy = P4PRE$reference$size_beta_copy,
    same_draw = SAME_DRAW_TXT,
    no_lag1 = "lag-1 스트레스판 없음 — 시점 신호(오버레이)가 없다 · 처치 = 그 신호일 횡단면 안 선택(C5 · C9 해당 없음 · DESIGN §8.1)",
    missing_pair = paste0("결측 짝 해당 없음 — 분위 엔진의 예측 행 = RX0 와 같은 코드 경로의 같은 Xp(템플릿 차분 대조 · DESIGN §3.1) · 팩터 결합 결측 없음 · ",
                          "V1 의 제외는 처치 자체이고 무작위 제외 효과는 N1 이 잰다")),
  variants = lapply(setNames(names(K$VAR), names(K$VAR)), function(vk) { v <- K$VAR[[vk]]
    list(name = v$name, form = v$form, rule = v$rule, basis = v$basis,
         delta = lapply(setNames(names(K$ENG), names(K$ENG)), function(e) { z <- sc$cells[[sprintf("P2R05_%s_%s", e, vk)]]
           list(base_signal_path = z$engine_files, engine_md5 = z$engine_md5, base_weight = z$base_weight) })) }),
  diagnostics = list(
    n = N_DIAG, engines = "E2", codes = CODES("diagnostic"),
    accounting = "시행 수 무가산(n_family = NA · 사양 회계 = RX0 회계 + diagnostic_of · control · design_ref · n_trials_note) · DSR 표본 아님 · 선택 대상 아님 · 판정 표 밖 · 2계층 모듈 풀 미등재",
    items = lapply(K$DIAG, function(d) list(control = d$control, tag = d$tag, reads = d$reads, purpose = d$purpose, pair = d$pair, pair_e3 = isTRUE(d$pair_e3), blend = d$blend)),
    constants_source = paste0("순열 주 시드 · σ 창 · 최소 관측 = 엔진 상수(.DT_PERM_SEED · .DT_SIGMA_WIN · .DT_SIGMA_MIN — engines.constants 기록 · DESIGN §4 · §12) · ",
                              "월 하위 시드 = 엔진 시작 달 대비 순번(rf_cell_engine null_perm 규약 승계) · 끝나면 전역 난수 상태 복원 · σ = 직전 일 로그수익 표준편차(창 끝 t−1 · 수정 종가 · ",
                              "σ 결측 = 그날 s 중앙값)"),
    reading = "rules.diagnostics_reading(사전 고정 · 판정 아님 · DESIGN §5.1)"),
  comparison = list(
    n = N_CMP, codes = CODES("comparison"), control = K$CMP$LV$control, factor = K$CMP$LV$factor, challenge = K$CMP$LV$challenge, purpose = K$CMP$LV$purpose,
    spec_copy_of = lapply(K$ENG, function(g) g$lv_src),
    accounting = "진단 형식(사양 = P2R04 W2 사본 · 시행 회계 원본 그대로 · 사전등록 n_family = NA) · 시행 수 무가산 · DSR 표본 아님 · 선택 대상 아님 · 판정 표 밖 · 2계층 모듈 풀 미등재 · 승격 대상 아님(C-20261018-046)",
    reading = paste0("정본 = rules.diagnostics_reading(첫 일치 — (1) 'LV 대비 판독 미결': 변형 칸 · LV 판정 계산 없음 · LV 위기 표 없음 · LV β 짝 승리 깊은 위기 0 · 그 위기에 변형 포착 결손 ",
                     "(2) 'LV 대비 판독 해당 없음': Vk β 짝 승리 깊은 위기 0 (3) 'LV 대비 증분 있음': Vk 승리 위기 ⊄ LV 승리 위기 ∨ LV 승리 위기에서 Vk 포착 < LV 포착 − tol ",
                     "(4) 그 밖(Vk 승리 ≥ 1 ∧ ⊆ LV 승리 위기 ∧ tol 안) = '원천 ① 증분 없음(저용량 변동성 스크린과 같음)') · 포착 비교는 LV 가 β 짝을 이긴 깊은 위기에서만 — DESIGN §0b 8 · 17 · 격리 점검 v2 권고 1(d) · 3"),
    measure_order = "엔진 묶음 안에서 변형 · 진단 뒤(측정 순서 = 사전등록 cells 순서) — 평균 DNN(engine.R) 기저라 DT 워밍과 무관하게 기저 캐시 적중 기대(데이터 판본이 바뀌면 그 달만 재학습)"),
  reseed = list(
    n = N_RSD, codes = CODES("reseed"), control = K$RSD$RX0S$control, review = K$RSD$RX0S$review, challenge = K$RSD$RX0S$challenge, purpose = K$RSD$RX0S$purpose,
    engine = list(path = ENG_REC$rx0s$path, md5 = ENG_REC$rx0s$md5, source = DTC$RX0_SRC, seed_line = ENG_REC$rx0s$seed_line, code_version = ENG_REC$rx0s$code_version),
    accounting = "진단 형식(사양 = 같은 구성 RX0 사양 사본 · base_signal.path 만 재시드 엔진 · 회계 = RX0 회계 + diagnostic_of · control · design_ref · n_trials_note) · 시행 수 무가산 · 선택 대상 아님 · 판정 표 밖 · 2계층 모듈 풀 미등재",
    warm = "워밍 ② — engine_RX0S.R 단독 전 달(새 시드 → 전 달 새 학습 · GPU · 분위 워밍 뒤 · 한 번에 엔진 하나) · 센티널 reseed 블록(캐시 a/b · cuda)",
    band = "시드 띠 = 위기마다 |포착(RX0S) − 포착(RX0)| · S 띠 = |S(RX0S) − S(RX0)| — 띠 안 결정 '시드 미결' 꼬리표(판정 불변 · 정본 = rules.record · conclusion_names)",
    measure_order = "엔진 묶음마다 RX0 다음 단독(RX0 → RX0S → 나머지)",
    note = paste0("공통 난수 사실(DT README §7 · tests/_out/rng_stream_facts.json · CPU 실측 · 격리 점검 v1 권고 1(e)): 같은 시드에서 은닉층 5개 초기값 · 미니배치 순서 = 같음 · ",
                  "출력층 초기화 · 초기화 뒤 CPU 생성기 상태 · CPU dropout 마스크 = 다름(난수 상태만 맞추면 같다 — 차이의 원천 = 출력층 초기화의 추가 소비) · ",
                  "CUDA = 초기화는 CPU 생성기 · dropout 은 CUDA 생성기라 dropout 흐름을 공유하는 것으로 코드 구조상 추론(미실측 · GPU 예약) — ",
                  "그래서 RX0S(시드 전체 교체) 띠는 V − RX0 결정의 시드 잡음을 넓게(보수적으로) 잡는다 · DESIGN §3.1 '공통 난수 아님' 문장 정정 = Q(설계 입력 핀)"),
    rng_facts = list(path = DTC$RNG_FACTS, md5 = rk_md5(file.path(ROOT, DTC$RNG_FACTS)),
                     fields = (function(j) j[intersect(names(j), c("hidden_init_equal", "output_row0_equal", "cpu_rng_state_after_init_equal", "batch_order_equal",
                                                                  "cpu_first_step_hidden_output_equal", "cpu_hidden_output_equal_when_rng_state_aligned",
                                                                  "model_built_on", "device", "torch", "ok"))])(fromJSON(file.path(ROOT, DTC$RNG_FACTS), simplifyVector = FALSE)),
                     cuda = "공유 추정(코드 구조 추론 · 미실측)")),
  adaptations = c(
    paste0("분위 엔진 = RX0 엔진(RP_AUTO_2002_06975/engine.R 3판) 템플릿 사본에서 지정 구역만(파이썬 출력층 · 손실 · 양성 대조 · 캐시 명세 · R 규칙 블록 · 실행 끝 패널 삭제) 바꾼 ",
           "자기완결 파일 7개(", DTC$DT_DIR, "/engine_{", paste(DTC$RULES, collapse = ","), "}.R) — make_engines.R 결정론 생성 · 파일끼리 .DT_RULE 한 줄만 다르다 · ",
           "템플릿 차분 대조(template_diff_check.R rc 0) · 정적 PIT(lookahead_detector) · 매니페스트 md5 = 사전등록 핀(engines 절 · DESIGN §7.1)"),
    paste0("재시드 엔진 = 원본 RX0 엔진과 .SEED_BASE 한 줄만 다른 사본(", ENG_REC$rx0s$path %||% DTC$RX0S_DEFAULT, " · 같은 CODE_VERSION · 시드가 캐시 키를 가른다 · engine_checks.R rx0s_check · 템플릿 차분 검사기)"),
    paste0("분위 예측 캐시 = 내용 주소(CODE_VERSION ", DTC$CODE_VERSION, " + 과제 + X · y · Xp 바이트 + 종목) — 규칙과 무관해 7 엔진이 한 번 학습한 예측을 공유 · 셀 기저 캐시 키 = 엔진 파일 md5(파일마다 따로 · ",
           "무효화 키 누락 없음) · 워밍 = engine_Q50.R 단독 1회 → engine_RX0S.R 단독 1회(셀 엔진 밖 · warm_cache.sh · DESIGN §7.3 · §0b 14)"),
    "V1 의 NA = 셀 엔진 후보 패널에서 빠진다(rf_cell_engine.R PANEL · !is.na(.base_sig)) — 두 구성 공통",
    "W2 = 셀 엔진 engine_blend(두 엔진 신호를 각각 그 신호일 횡단면 rank-Z → 평균 · 공통 (Date, Ticker) — rf_cell_engine.R 기저 신호 블록)",
    paste0("셀 엔진 경로의 DNN 첫 신호 = 2005-01-31(셀 엔진이 .RP_START_DATE 를 기저 엔진에 넘기지 않음 → 엔진 기본값) — 측정 축 실효 시작과 약 6개월 차이 · RX0 · 변형 · 진단 공통이라 ",
           "비교 무영향 · 기록만(하네스 변경 = 라운드 밖 · DESIGN §2.1) · 워밍 드라이버도 넘기지 않는다(월 순번 k · 시드가 셀 측정과 같아야 캐시 키가 맞는다)"),
    "E3 의 처치 몫 = 구조상 50%(base_weight 0.5 × DNN) — 용량 짝 W2 가 '용량 의존'과 '구성 의존'을 가른다(DESIGN §2.3)"),
  cells = CELLS,
  fast_crash_prior = c(P4PRE$fast_crash_prior[setdiff(names(P4PRE$fast_crash_prior), "inherited_from")],
                       list(inherited_from = list(prereg = K$P2R04_PREREG, md5 = rk_md5(file.path(ROOT, K$P2R04_PREREG)), upstream = P4PRE$fast_crash_prior$inherited_from,
                                                  note = "DESIGN §5 ④ — 빠른 급락 정의 = Mishkin & White 2002 · 21거래일 −20% · P2R04 표 그대로"))),
  rules = RULES, rules_source = paste0("round_rules.R::p2r05_rules (md5 ", rk_md5(file.path(RD, "round_rules.R")), ")"),
  rules_inheritance = RC$inheritance,
  expectations = list(   # Q 사전 기대(측정 전 고정 · DESIGN §6 · §0b 7 · 15 · 20 · 보는 창 · 채점 대상) — 결과 뒤 고쳐 쓰지 않는다
    note = paste0("기준선(새 epoch · P2R03 RX0 보는 창 계약 산출 — 판단 T1 R-20261018-004 · 철학 P2 R-20261018-002 인용값): E2 RX0 S 0.623 · Calmar 0.297 · CAGR 15.9% · Sharpe 0.736 · ",
                  "하락/상승 β 비 1.26(역비대칭) · 강세 상승 포착 중앙 1.42 · β-통제 α 10.8%/년(t 2.91) · 2008-05 · 2020-01 포착 1.064 · 1.157 / E3 RX0 0.842 · 0.422 · 22.7% · 0.916 · ",
                  "0.98 · 1.76 · 16.8%/년(3.88) · 0.961 · 1.224 · E2 회전 연 2,218% · 비용 끌림 3.3%/년 · 보는 창 LT 위기 7 · 깊은 위기 4(2008-05 · 2011-05 · 2020-01 · 2021-06) · ",
                  "빠른 급락 4(2008-05 · 2008-11 · 2011-05 · 2020-01)"),
    by_crisis_type = paste0("깊은 위기별(DESIGN §0b 7 · 위기 유형 = crisis_type_classify.json): systemic 2(2008-05~10 · 2020-01~03 — 높은 상관) = V 가 두 위기 모두 β 사본에 진다(확신 0.7 — ",
                            "모두 같이 빠지는 위기에서 상대 꼬리 정보가 줄어든다) · dispersed 2(2011-05~09 · 2021-06~2022-09 — 낮은 상관) = V2 1~2 승 · V1 0~1 승(S 짝이 같이 이기면 '변동성 대리') · ",
                            "③ 기대 개수 = V 칸 모두 ≤ 2/4(과반 미달 · 확신 0.65)"),
    tail_instrument = "⑮ 통과(높은 확률) · 다만 D^σ 는 0 근처 — 순위 분산은 변동성이 강하게 예측한다(지속성 · FQ-233 arm C 교훈)",
    Q50 = "RX0 와 거의 같다(보유 겹침 높음 · 위기 포착 차 < tol) — 무처치에 가까움(BHT 2024 유동 표본 평균 ≈ 중앙값 · 순위 표적은 오른꼬리가 잘려 있다)",
    V1 = "① 소폭 개선 · ⑤ Δ < 0 · ⑥ ⑦ 비열등 · ③ 불확실 · 전달량이 작을 수 있다(q10 하위 5분위의 다수는 중심이 낮은 종목) — 최빈 '결정 미달' 또는 '노출 방어'(제약형 · Q50 순위 보존)",
    V2 = paste0("① ② 개선 · β 하락 · ⑤ Δ < 0 · ⑥ ⑦ 위험 · ③ 불확실 — 최빈 '노출 방어' 또는 '꼬리 회피 기계(방어만 · 복리 없음)'(P2R05 결론 이름 · 격리 점검 v1 권고 1(d) — ",
                "DESIGN §6 의 옛 이름 '저변동 기계'를 옮기며 바꿈) · 근거: 저분산 종목 쏠림 · 꼬리 단독 정렬은 롱숏 수익이 약하다(BHT 2024) · ",
                "국내 저위험 이상(P2R04 방향 확인)은 알파 손실을 줄일 수 있다 · 위기 민감도 낮은 종목은 평균 수익이 낮다(Chabi-Yo 외 2018)"),
    appendix_a = "부록 A 예측(철학 C-065 · DESIGN §0b 20): V2 상승 β > S2 상승 β ∧ ⑥ V2 ≥ S2 — 꼬리가 변동성 순서와 다르게 '강세에 뒤처지는 저β'를 거른다면",
    S = "S1 · S2 가 V1 · V2 와 같은 위기를 이긴다 — 최빈 '변동성 대리'",
    N = "N1 · N2 는 Q50 근처 · 무작위(무정보)",
    E3 = "E2 보다 약한 효과(처치 몫 50% · 순위 버퍼) — 단일 구성 통과 가능(구조)",
    LV = paste0("비교 기준(판정 아님) — P2R04 W2 와 같은 사양의 같은 배치 재측정 · V 칸 방어의 LV 대비 이름 = rules.diagnostics_reading(정본 · 첫 일치 — '원천 ① 증분 없음(저용량 변동성 스크린과 같음)'은 ",
                "Vk β 짝 승리 깊은 위기 ≥ 1 ∧ ⊆ LV 승리 위기 ∧ 그 위기들에서 LV 를 tol 넘게 못 이길 때만 · Vk 승리 0 = 해당 없음)(기록)"),
    RX0S = "RX0 대비 위기 포착 차 = 시드 띠 — V 칸 결정이 이 띠 밖이어야 '시드 미결' 꼬리표가 붙지 않는다(판정 불변)",
    overall = paste0("확률(판단 원장 J-20261018-006 · DESIGN §0b 15): supported 0.10 · partial 0.25 · falsified 0.60 · 미시험(⑮) 0.05 — 최빈 = falsified('노출(β) 방어' 또는 '변동성 대리') · ",
                     "반증(가설 H 기각) = 꼬리 계기 통과 ∧ 두 규칙 모두 ③ 또는 ⑭ 미달 · 계기 실패 = 미시험 · 처분 = 계기 → 다음 행동 표(rules.instrument_action)"),
    falsification = "결과 뒤 기대를 고쳐 쓰지 않는다 — 기대와 실측의 차이는 판정 뒤 교훈 단계에서만 적는다"),
  final_selection_rule = FS,
  final_selection_rule_check = list(source = "round_rules.R::p2r05_final_selection_rule", p2r04_prereg = K$P2R04_PREREG, numeric_keys_equal = as.list(FSC$numeric_keys),
                                    text_changed = as.list(FSC$text_changed), tail_instrument_new = TRUE,
                                    required_sentences = "같은 추첨 선택 꼬리표 · 계기 → 다음 행동(rules.instrument_action) — round_rules.R 에 있음을 초안이 기계 확인(.rr_required)"),
  axis_audit = P4PRE$axis_audit,
  behavior_card_cfg = list(path = rel(BCP), md5 = rk_md5(BCP), same_as_p2r04 = identical(rk_md5(BCP), P4PRE$behavior_card_cfg$md5)),
  operational_pins = OPP,
  engines = ENG_REC,
  warm = list(
    script = paste0(K$RD_REL, "/warm_cache.sh"), driver = paste0(K$RD_REL, "/warm_engine.R"), sentinel = "04_Research/programs/_lib/night_state/p2r05_warm.done", schema = "p2r05_warm_v1",
    order = paste0("DESIGN §7.3 · §0b 14 순서 — ① 정적 검사 · 등록 · 커밋 · 핀(precheck.R --warm: 템플릿 차분 · 매니페스트 · 정적 PIT · 상수 · 재시드 엔진 시드 한 줄 · 양성 대조 리허설 요약 · 사전등록 커밋) ",
                   "② 양성 대조 · 뮤테이션 리허설 결과 확인(같은 검사 안) ③ GPU 게이트(precheck.R --gpu-gate — nvidia-smi 표의 Type C 0 까지 대기 · 끄지 않는다 · memory.used 기록) · CUDA 가용 ",
                   "④ engine_Q50.R 단독(셀 엔진 밖 · PYTORCH_CUDA_ALLOC_CONF=roundup_power2_divisions:2 · 다른 칸 동시 실행 금지 = GPU 잠금 · 분위 캐시 전 달 · 학습 달 전부 cuda · 예측표) ",
                   "⑤ engine_RX0S.R 단독(같은 설정 · 새 시드 전 달 · cuda) ⑥ RX0 엔진(engine.R) 단독 — 평균 캐시 전 달 확인(적중이면 GPU 미사용 · 바뀐 달만 재학습) → 센티널(분위 a/b · 재시드 a/b)"),
    gpu_plan = "분위 261개월 + 재시드 261개월 = 각 약 230분(DESIGN §2.2 실측 속도 · 워커 8) — 계획 ≈ 8시간 · 한 번에 엔진 하나",
    monitor = "엔진 진행 줄의 월당 학습 초(추정) > 실행 중앙값 × 3(DESIGN §7.3 운영 감시 문턱) = 경고 줄 · 진행 줄 정체 · CPU 학습도 경고 — 끄지 않는다(워커를 줄인 재기동 판단 = Q 운영)",
    freshness = paste0("측정 직전 precheck.R --warm-check — 센티널 유효(상태 ok · 사전등록 md5 · 엔진 md5 = 핀(규칙 7 · 재시드) · CODE_VERSION · 분위 · 재시드 캐시 전 달 · cuda · 양성 대조 · RX0 확인 · ",
                       "워밍 중 데이터 불변) ∧ 워밍 끝 데이터 지문(fingerprint.sh dnn_input = RAWDATA · 재무 원값 · 컨센서스) = 현재 — 다르면 측정하지 않는다(measure.sh --rewarm = 다시 워밍 · ",
                       "바뀐 달만 재학습) · 센티널 사본 = results/warm_sentinel.json(측정에 묶인 워밍 기록 · 구성 증거 ⑩(a) 입력)"),
    lane = "레인 GPU 배분 = 도훈 확인(열린 질문 6) — warm_cache.sh 는 레인을 멈추지 않는다 · 레인이 켜져 있으면 --allow-lane-on 없이 시작하지 않는다(GPU 게이트가 다른 연산 0 을 따로 본다)"),
  operational_memo = paste0("GPU 배분 = 도훈 확인 사항(열린 질문 6 · 조정자 10-18) — 워밍(분위 + 재시드 · 계획 ≈ 8시간) 직전에 레인 정지 여부를 묻는다 · warm_cache.sh 는 레인을 멈추지 않고 어떤 프로세스도 ",
                            "끄지 않는다 · 측정은 워밍 센티널이 신선할 때만(measure.sh)"),
  evaluation = list(files = EVP, note = paste0("판정 구현(evaluate.R) · 픽스처 · 규칙 상수(round_rules.R) · precheck · DT 엔진 검사(engine_checks.R) · 측정 절차(measure*.sh) · 워밍(warm_cache.sh · warm_engine.R) · ",
                                               "데이터 지문(fingerprint.sh)을 결과 전에 고정 — evaluate.R 은 시작부(샤드 포함)에서 이 md5 와 운영 핀 전체를 재대조한다")),
  evaluate_consistency = CC,                                                    # 초안 시점 판정 구현 정합(등록 때 다시 확인해 덮는다)
  rehearsal = REHS,
  philosophy_p1 = .p1_check(),                                                  # 초안 시점 값 — 등록 때 다시 확인해 덮는다(--register)
  tests = TESTS,
  tests_dt = list(   # 격리 점검 v1 권고 9 — DT 엔진 시험 결과(구현 에이전트 A · tests/run_all_tests.R 느린 판)의 파일 md5 · 통과 기록
    files = TEV$record,
    note = paste0("rule_smoke · diff_check_mutation(차분 검사기 양방향) · static_pit(정적 PIT — engine_checks.R 의 정적 검사는 .R 만 보므로 내장 파이썬 추출본 검사의 증거는 이 결과뿐 · ",
                  "DT README §9 항목 13) · py_e2e · engine_dryrun · pc_mutation(양성 대조 뮤테이션 — 정답 통과 · 뮤턴트 전부 실패) · rng_stream_facts(공통 난수 사실 · reseed.note 근거) · ",
                  "template_diff_check(차분 · 재시드 · 매니페스트) + DT README(§7 사실 문장) — tests/_out/test_summary.json 은 마지막 --fast 판이라 핀하지 않는다 · ",
                  "--register · precheck(본 대조 · 워밍 대조)가 md5 를 다시 대조한다(다르면 등록 · 워밍 · 측정하지 않는다)")),
  precheck = sprintf(paste0("측정 직전 precheck.R 가 (1) evaluate.R 의 핀 대조 함수 ∪ precheck.R 의 같은 정의로 사양 %d · 운영 경로(DT 엔진 파일 · 재시드 엔진 포함) · 팩터 레지스트리 엔트리 · 비중 카탈로그 1 · ",
                            "패키지 · R 판 · 평가 경로 · 행동 카드 설정 사본과 등록부 사전등록 md5 를 다시 대조하고 (2) DT 엔진 — 템플릿 차분 rc 0(재시드 엔진 대 원본 = 시드 한 줄 포함) · 생성 엔진 7 · ",
                            "재시드 엔진 md5 = 매니페스트 = 사전등록 핀 · 정적 PIT · CODE_VERSION · 규칙 상수 · 양성 대조 리허설 요약 md5 = 핀 · 파이썬 판 = 핀 (3) 러너 축 — 06_Registry/reinforce_program.json ",
                            "fixed_axes.n_max · commission_bps = 사양 fixed_axes 값(%s · %s bps · 키 값 대조) (4) 사전등록 두 사본이 git 에 커밋돼 있고 작업 트리 변경이 없으며 두 md5 가 같은지 본다",
                            "(등록 → 커밋 → 워밍 → 측정) — 하나라도 어긋나면 측정하지 않는다 · 이어서 measure.sh 가 워밍 센티널 신선도(precheck.R --warm-check)를 단정한다"),
                     length(CELLS), paste(unique(vapply(sc$cells, function(z) format(fromJSON(file.path(ROOT, z$path), simplifyVector = FALSE)$fixed_axes$n_max), "")), collapse = "/"),
                     paste(unique(vapply(sc$cells, function(z) format(fromJSON(file.path(ROOT, z$path), simplifyVector = FALSE)$fixed_axes$commission_bps), "")), collapse = "/")),
  data_note = paste0("데이터 판본: RAWDATA · 벤치 퀀티 단일 · 측정 축 ", EP$id, "(동전주 바닥 — 수정주가 수준은 이후 기업행위를 반영한다 · PIT 경계 기록) · DNN 평균 예측 · 재시드 예측 = RP_AUTO_2002_06975 ",
                     "내용 주소 캐시(재시드 엔진이 같은 작업 폴더를 쓰면 같은 캐시 폴더 · 시드가 키를 가른다 · 바뀐 달만 재학습) · 분위 예측 = ", DTC$CACHE_DIR, "(워밍이 채운다 · 내용 주소) · ",
                     "예측표 = ", DTC$QPRED_DIR, "(⑮ · 기록의 입력 · 실현 라벨 미포함 — 평가가 RAWDATA 로 재도출) · 팩터 DB 월 스냅샷 · IC 월간 이력 = equality 지문 대상(E3 · LV 팩터 원천 · 방향 원천) · ",
                     "팩터 레지스트리 = 쓰는 엔트리 내용 핀"),
  design_inputs = list(
    files = .design_files(),
    charter_open = .charter_open(),
    text = paste0(DESIGN_TXT, " · Q 의 위기 유형 탐침 _design_notes/crisis_type_classify.{md,json}(md5 핀 · 위기 유형별 β 짝 승패 기록의 분류 입력 · 판정 조건 아님) · ",
                  "설계 노트(md5 핀 · 커밋 대상 · 격리 점검 v1 권고 2): onset_state_classify.json(evaluate.R p5_load_onset 입력) · state_turn_classify.md(final_selection_rule 기록 위기 목록 ",
                  "'상태 미전환 최대 하락 위기'의 원천) · crisis_type_asof.{R,md,json}(rules.pause_report · DESIGN §0b 26 '위기 진행 중 상관 상태로는 반증'의 근거 · Q 가 커밋) · ",
                  "P2R04 사전등록(규칙 상수 · 문장 · 빠른 급락 표 · 운영 경로 승계) · 판단 원장 ", J_ROUND_SELECTION, "(J-20261018-005 대체) · 판단 T1 R-20261018-004 · 007 · ",
                  "판단 T2 R-20261018-005 · 철학 P2 R-20261018-006 · 철학 P1 R-20261018-008 · 측정 · 평가 계약 코드 — 시험 창 성과 미사용")),
  holds = .holds(),
  budget = list(variants = K$N_ROUND, reference_remeasure = N_REF, reseed = N_RSD, diagnostic = N_DIAG, comparison = N_CMP, diagnostic_lag1 = 0L, cells = length(CELLS), rounds = 1L,
                groups = as.list(GROUP_N),
                gpu = "분위 모델 261개월 1회 + 재시드 RX0 261개월 1회(각 약 230분 · 계획 합 ≈ 8시간 · 한 번에 엔진 하나 · 워커 8 · GPU 단독 점유 — DESIGN §7.3 · §0b 14) · 나머지 칸 = 캐시 적중",
                note = sprintf("변형 %d 만 시행 수 가산(계보 2002.06975 · %s → %s) · RX0 %d · 재시드 %d · 진단 %d · 비교 기준 %d = 무가산 · lag-1 진단 없음 · DSR 표본 = 변형 칸", K$N_ROUND,
                               paste(N0, collapse = "/"), paste(N0 + K$N_ROUND, collapse = "/"), N_REF, N_RSD, N_DIAG, N_CMP),
                r7 = R7_TXT, stop_report = STOP4_TXT),
  changes_after_superfan = list(   # 설계 단계 반영(P2R04 판정 · 판단 T1 · T2 · 철학 P1 · P2) — DESIGN §0b 정정판(6 ~ 22) 기준
    ch("P2R04 판정(10-18 15:59 · 보는 창) — DESIGN §0b 2 변동성 대리 짝 필수", "S1 · S2 유지(진단 읽기 '변동성 누출' · '꼬리 고유')", "P2R04 저변동 · 하방β 틸트 = 노출(β) 방어 — V2 가 변동성 순서를 재학습했다면 같은 결말"),
    ch("§0b 5 유동성 이동 감시", "결론 범위 11 — V · S · Q50 · RX0 위기 중 보유 유동성 · 크기 십분위 나란히(C-069)", "P2R04 틸트가 보유를 덜 유동적인 쪽으로 옮겼다"),
    ch("판단 Superfan T2 R-20261018-005(C-036 · 037 · 038) — §0b 6 ~ 10(옛 §0b 1 · 3 · 4 대체 · 철학 C-066 표시)",
       "결론 범위 9(희석 = 비깊은 위기 한정 · 엔진 안 처치 근거 정정) · 10(위기 이름 = 상태 미전환 최대 하락 위기 · systemic / dispersed) · 6(합집합 결합 금지 명시) · LV 2칸(비교 기준) · 기대 by_crisis_type",
       "희석 몫은 비깊은 위기 한정이었고(깊은 위기 1/4) 위기 이름은 설계 노트 · 기전 탐침의 것만 쓴다"),
    ch("철학 Superfan P2 R-20261018-006 · 철학 N-⑤ ⑥ ⑧ · C-045 — §0b 11 ~ 13", "결론 범위 13 · 14(R7 두 성분 · P2 정지 조건 · V1 = Q50(같은 추첨 중앙값) 순위 보존형 · V2 = 대체형 · 보유 겹침 기록) · 기록 추가(판정 여유 · Dimson β 짝 판 = 판정 구현 쪽)",
       "방어 성분 연속 2회 잡음 뒤 계상 · 처치 세기의 사전 기준"),
    ch("판단 Superfan T1 R-20261018-007(C-054 · 055 · 056 · 057 · 058 · 059) — §0b 14 ~ 17 · J-20261018-006 이 J-005 대체",
       paste0("재시드 칸 2(", paste(CODES("reseed"), collapse = " · "), " · 진단 · 무가산 · 워밍 ⑤ · GPU ≈ 8시간) · 결론 범위 8(시드 띠 · 열린 질문 2 결정 뒤집음) · ",
              "계기 → 다음 행동 표(rules.instrument_action — 판정 구현 쪽) · P2 정지 시 다음 프로그램 = P1 다른 기저 수익 엔진 · D^w · LV 읽기 범위 · R7 방어 성분 기계 판정(판정 구현 쪽)"),
       "처치가 DNN 을 다시 배우는 첫 P2 라운드라 판정 · R7 판독이 시드 변동을 품는다"),
    ch("철학 Superfan P1 R-20261018-008(C-063 · 064 · 065 수용 · 노트 066 ~ 070 · 071 지지) — §0b 18 ~ 22",
       "결론 범위 15(같은 추첨 판독 · 선택 꼬리표 — 정본 문장 = round_rules.R · 초안이 기계 확인) · 13(P2 정지 보고 4요소) · 14 · purpose(V1 = Q50(같은 추첨 중앙값) 순위 보존형) · D^H(판정 구현 쪽) · CHARTER-GAPS-6",
       "두 구성 통과가 추첨 운을 거르지 못한다 · 정지 보고의 형식을 사전 고정한다"),
    ch("열린 질문 1 ~ 12 결정(DESIGN §0b 표 · 2 와 7 정정)", "순위 표적만 · 시드 짝 이 라운드 안(2 — 뒤집음) · V2 λ = 1 · 머리 3 · 거부 20% · GPU 배분 = 도훈 확인 · R7 = P2 · 방어 성분 연속 2(7) · ⑮ 시험 조건 · Q50 진단 · P2R04 판정 뒤 등록 · DT_2002_06975 · 5일 표적 월간 집행",
       "Q 결정(10-18 저녁 · P2R04 판정 뒤 · T1 R-007 · 철학 C-066 반영)"),
    ch("측정 기계(구현 에이전트 C)", "워밍 센티널(분위 · 재시드 두 캐시) · GPU 잠금 · 신선도 단정 · RX0 → RX0S 단독 뒤 RX0 셀 로그가 DNN 캐시 적중(trained 0)을 못 보이면 분위 엔진 첫 칸 단독 · 셀 목록 = 사전등록 대조(measure.sh)",
       "같은 GPU 에 학습 둘이 겹치면 VRAM 을 넘는다(DESIGN §7.3 · P2R03 10-18 04시 사건)")),
  changes_after_review = c(REVIEW_CHANGES_C, REVIEW_CHANGES_Q, REVIEW_CHANGES_Q2))   # 격리 교차 점검 반영(측정 기계 · 등록 쪽 = C · 판정 구현 · 설계 쪽 = Q · v2 = B) — 비어 있으면 --register 거부
## 등록 전 점검(격리 점검 v2 필수 2) — 최상위 결론 범위에 '꼬리 회피 기계' 옛 정의 문구가 남아 있으면 초안을 쓰지 않는다(rules.conclusion_names 한 정의와 두 판이 된다)
OLD_MACHINE_TXT <- "③ · ④ · ⑭ 를 넘었으나 ⑥ · ⑦ · ⑨ · ⑫ · ⑬ 중 하나라도 못 넘으면"
if (any(grepl(OLD_MACHINE_TXT, c(unlist(pre[["conclusion_scope"]]), unlist(pre[["rules"]][["conclusion_names"]])), fixed = TRUE)))
  stop("[P2R05] 결론 범위 · rules.conclusion_names 에 '꼬리 회피 기계' 옛 정의 문구가 있다 — 한 정의(p5_machine)로 고친 뒤 초안(격리 점검 v2 필수 2)")
writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), DR, useBytes = TRUE)
cat(sprintf("[P2R05] 초안 v%d %s (md5 %s) · 칸 %d(변형 %d + 기준 %d + 재시드 %d + 진단 %d + 비교 기준 %d) · 검사 %s · DT 시험 증거 %d(통과 %d · md5 핀) · 시행 회계 %s · 규칙 문장 = round_rules.R(같은 문장 %d · 바뀐 문장 %d · 새 키 %d) · 판정 구현 정합 %s · 철학 P1 %s · 열람 미기입 %d · 철학 P4 %s\n",
            pre$draft_version, rel(DR), rk_md5(DR), length(CELLS), K$N_ROUND, N_REF, N_RSD, N_DIAG, N_CMP,
            paste(vapply(TESTS, function(t) sprintf("%s %s/%s", basename(t$path), t$pass, t$fail), ""), collapse = " · "),
            length(TEV$record), sum(vapply(TEV$record, function(z) isTRUE(z$pass), logical(1))),
            paste(N0 + K$N_ROUND, collapse = "/"), length(RC$inheritance$identical), length(RC$inheritance$changed), length(RC$inheritance$added),
            if (isTRUE(CC$ok)) "ok" else "불일치", if (isTRUE(pre$philosophy_p1$ok)) "수령" else paste0("미수령(", pre$philosophy_p1$why, ")"),
            sum(vapply(pre$exposures, function(x) isTRUE(x$pending), logical(1))), if (length(P4R)) paste(vapply(P4R, function(r) r$id, ""), collapse = ",") else "미도착"))
