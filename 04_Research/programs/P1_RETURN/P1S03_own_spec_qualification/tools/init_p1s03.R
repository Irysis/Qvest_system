#!/usr/bin/env Rscript
## P1S03(P1 상설 자격 · 자체 사양 입구 갈래 판 1 · round_core v4) 사양 만들기 — 등록 전에 한 번 돈다(사양이 이미 있으면 멈춘다).
##   실행: Rscript 04_Research/programs/P1_RETURN/P1S03_own_spec_qualification/tools/init_p1s03.R   (작업 디렉터리 = 저장소 루트)
##   하는 일: ① 시드 칸 사양 1개(등록된 생성 함수 rc_standing_seed_respec — 재량 없음) ② round_spec.json(rc_init_standing_p1 · 갈래 own_spec · 판 1)
##            ③ 등록 전 사양 후처리 — pins.files(판정에 닿는 파일 — 판 2 목록 + 자체 사양 생성기 둘 + 결합용 뷰 설정)
##   규칙 · 문턱 · 표준 구성 생성 함수 = P1 템플릿(P1R01 승계 · 판 1 · 판 2 · P1R03 · P1R04 와 같다). 설계 = DESIGN.md.
suppressMessages(source("04_Research/programs/_lib/round_core/v4/load.R"))
stopifnot(identical(RC_VERSION, "v4"))
root <- rc_root()
rd <- "04_Research/programs/P1_RETURN/P1S03_own_spec_qualification"
fam <- "FC:value"
like <- "04_Research/programs/P1_RETURN/P1R03_factor_family_composites/specs/P1R03_FVALU_C0.json"
nf <- as.integer(rc_standing_nf_prior(fam, root))        # 계보 앞선 사전등록 · 상설 원장 회계 최댓값(P1R03 T0 1 · P1R04 T1 변형 2) — 시드 = 무가산(그대로)
basis <- sprintf("P1S03 시드(같은 판본 기준 재측정 — 시행 수 무가산 · P2R04 RX0 · P1S02 시드 선례): 계보 %s 앞선 사전등록 · 상설 원장 회계 최댓값 %d 그대로", fam, nf)
dir.create(file.path(rd, "specs"), recursive = TRUE, showWarnings = FALSE)
f1 <- file.path(rd, "specs/P1S03_FVALU_RX0.json")
if (file.exists(f1)) stop("시드 칸 사양이 이미 있다 — 덮어쓰지 않는다")
rc_json_write(rc_standing_seed_respec(like, "P1S03_FVALU_RX0", nf, basis, root), f1)
seeds <- list(list(code = "P1S03_FVALU_RX0", engine = "FVALU", role = "reference", spec = f1))

purpose <- paste0(
  "P1 엔진 자격 규칙(P1R01 승계 · 판 1 · 판 2 · P1R03 · P1R04 와 같은 규칙 · 같은 문턱)을 자체 사양 입구 갈래(track own_spec)의 판 1 로 등록한다. ",
  "입구 = 팩터 척추 생성기가 만든 점수 패널 엔진(04_Research/strategies/FC_* · own_spec.json — 카테고리 등가중 합성 T0 · 시점별 IC 가중 결합 T1 · 같은 생성기로 늘어날 결합기 단계)이고, ",
  "표준 구성(롱온리 25종 등가중 · 15bps · 유동성 2억 원 · 활성 측정 축)으로 재서 기저 풀(P4 강화 사슬의 기저 · 블렌딩 부품)의 자격을 준다. ",
  "기저 풀 자격 = 상설 판 통과만(도훈 결정 P4-BASE-POOL-GRADE-PATH-TAU-20261111) — P1R03 · P1R04 라운드 판정은 연구 질문(합성 · 결합 개선)의 판정이고 기저 자격을 주지 않는다. ",
  "시드 = P1R03 자격 엔진 FVALU(밸류 카테고리 등가중)의 같은 판본 재측정 — 이 판 경로가 아는 답(앞선 측정의 자격)을 통과시키는지 보는 양성 대조다(사다리 루프 ① 기준점부터).")
hypothesis <- paste0(
  "자격 = IS β-통제 t(α) ≥ tier_graduation 하한 ∧ IS 상승 포착 ≥ 0.55(P1R01 승계 · 위기별 하락노출 · OOS α 는 보고 전용). ",
  "기대: 시드 FVALU 는 자격 유지(앞선 측정과 같은 엔진 · 같은 표준 구성 · IS 구간 자료는 수정주가 이음매 수리의 영향 밖 — 차이 = 자료 판 · 팩터 DB 판). ",
  "입구로 들어오는 엔진(T0 14 + 토탈 · T1 14 + 토탈)의 판정은 엔진마다 독립 · 선택 없음(자격 목록 = P4 기저 후보). ",
  "같은 카테고리의 T0 · T1 은 같은 계보(family_root FC:<카테고리>)다 — 독립 원천 둘로 세지 않는다.")

exposures <- list(
  "Q 는 P1R03 의 IS 판정 파일(evaluation_visible.json — 자격 8/15)과 그 파일에 코어 v3 결함으로 남은 보고 규칙 열(test_hold — 자격 칸의 OOS 연 알파 > 0 여부)을 본 상태다(P1R04 노출 고지와 같다). 규칙 · 문턱은 P1 템플릿 승계로 고정(재량 없음) · 코어 v4 는 그 열을 IS 파일에서 뺀다.",
  "Q 는 P1R03 산출물(T0 15 엔진)의 IS 구간 NAV · 위기 하락노출 · 보유를 P1R04 차트 배치 시험(가짜 짝 · IS 전용 · 판정 무관)에서 본 상태다 — OOS 구간은 그리지 않았다.",
  "P1R04(T1 15 + 같은 배치 T0 기준 15)는 등록됐고 측정 전이다 — 그 결과는 이 판 등록 시점에 없다.",
  "팩터 방향 격리 재판정(밸류 · 성장 · 컨센서스 · 쏠림 73 · 성과 무참조 · 11-13)의 결과(불일치 3 · 불명 9)를 본 상태다 — 입구 · 판정 규칙에 쓰지 않는다(결론 범위 방향 줄).",
  "입구 규칙(자체 사양 입구 기본값 RC_STANDING_SCAN_OWN_DEFAULT · 방향 층 engine_native + orientation_layer)은 코어 v4 의 정적 검사(생성기 재생성 md5 · 본문 실행 단정)로만 정했다 — 성과와 무관.",
  "Q 는 등록 전 입구 미리보기(scan --dry-run · 사유 코드별 디렉터리 수 · 성과 수치 없음)를 본 상태이며, 미리보기 뒤 입구 규칙을 바꾸지 않았다.")

conclusion_scope <- list(
  "자격 엔진 목록 = P4 기저 후보(활성 측정 축 · 같은 epoch 비교만). 자격 ≠ 권위 등급 · Judge · BOOK.",
  "미달 = 표준 구성(롱온리 ≤25종 EW · 15bps · 활성 축 · 월말 신호 · 월간 집행)에서 이 규칙 미달 — 그 카테고리 · 결합 방식의 기각이 아니다(연구 질문의 판정은 P1R03 · P1R04 라운드).",
  "입구 제외(사유 코드) = 측정하지 않음 — 판정이 아니다. 자체 사양 입구 사유: own_spec_missing(사양 없음 · 판독 불가 · core md5 ≠ spec_md5) · own_generator_unknown(생성기 목록 밖 — 새 결합기 생성기는 새 판) · own_generator_mismatch(생성기 · 엔진 md5 불일치 · 재생성 본문 불일치 — 손 편집 · 부호 층 변조).",
  "시드 FVALU = 양성 대조 — 미달이면 다른 판정을 읽기 전에 판 경로(측정 · 자료 판 · 입구)를 먼저 확인한다. 통과해도 새 증거가 아니다(같은 엔진 · 같은 규칙의 재측정).",
  "측정 자료 판: RAWDATA 2026-03-30 수정주가 이음매 수리(11-13 수리 세션) 뒤 측정분만 기저 자격을 받는다(판 표식 contracts/factor_db_vintage.R) — 판 폴더 tick_hold 는 수리 완료 신호와 P1R04 측정이 끝난 뒤에 지운다(한 번에 무거운 작업 하나).",
  "같은 카테고리의 T0 · T1 은 같은 계보다 — 둘 다 통과해도 독립 원천 둘이 아니다. 원천 셈 = P1R03 결론 범위 셈법(토탈 ≠ 원천 · 저위험 4 카테고리(방어 · 위험 · 유동성 · 국면) = 한 원천).",
  "기저 풀(코어 v4 rc_p4_base_pool)은 통과 칸에 철학 P2 판독(상설 pass 기록의 P2 또는 원천 라운드 영수증 results/philosophy_receipt.json)과 저위험 확인(카테고리가 방어 · 위험 · 국면과 겹치는 엔진 — 토탈 포함 — 은 엔진 단위 release_decision)을 요구한다. P1R03 저β 5(방어 · 위험 · 유동성 · 쏠림 · 토탈)는 도훈 결정 LOWBETA-ENGINES-BASE-USE-20261113 으로 기저 사용 허용 · 표기 '저β 수익 엔진' · 방어 주장 없음. T1 의 같은 카테고리 엔진은 그 결정을 승계하지 않는다(P1R04 철학 C-20261113-027 · 별도 확인).",
  "'방어' 표기는 크기 × β 짝 대조 통과 ∧ 최대낙폭이 시장보다 뚜렷이 작을 때만이다(도훈 결정 CHARTER-GAP-LOWBETA-DEFENSE-LABEL-20261113) — 이 판의 위기 하락노출 열(원장 · 통과 보고)은 시장 대비 원값이라 방어 근거로 쓰지 않는다.",
  "팩터 방향: 밸류 · 컨센서스 · 쏠림(과 토탈)에는 방향 격리 재판정 불일치 구성원이 하나씩 있다(V23_RAFI_Weight · C08_Coverage · CR05_Short_Pressure_Proxy). 이 판의 결과는 등록부 방향 결과다. 등록부를 방향 정책 경로로 고치면 그 카테고리 엔진은 새 엔진(md5 변경 · 시행 +1)으로 다시 입구를 지난다.",
  "자격 = 수익 엔진 자격(IS β-통제 알파 ∧ 강세 참여 하한 — 헌장 원칙 5 · 6 쪽). 위기 방어 · 꾸준함은 판정하지 않는다 — 통과를 철학 적합으로 보고하지 않는다(위기 하락노출 = 보고 열 · 방어 = P4 사슬 몫).",
  paste0("자격 지표 하나가 계산되지 않아도 다른 지표가 미달이면 미달로 판정한다(어느 값이 와도 미달 — 3치 논리). ",
         "모든 자격 지표가 통과이거나 미정인데 하나라도 계산되지 않으면 판정하지 않고 다시 평가한다."),
  "T1 엔진은 정보계수 이력이 36개월 미만인 팩터에 가중 0 을 주고, 카테고리 전체가 가중 0 이면 그 달은 등가중 점수를 쓴다 — 초기 몇 해의 T1 은 T0 에 가깝거나 일부 카테고리에 쏠린다(엔진 규칙 · 판정 무관).",
  "시험: 이 판은 새 시험 묶음을 돌리지 않는다(도훈 11-12 · 11-13 — 등록 시험은 직전 결과 + 핀 동일로 갈음). 코어 v4 시험 46/46(11-13 출시 전 · 격리 점검) · 엔진 PIT 값 검사(T0 test_fc_engine_gen.R · T1 test_fc_combiner_gen.R — P1R03 · P1R04 등록 때)를 핀(코어 매니페스트 · 생성기 md5)과 입구의 재생성 md5 대조가 잇는다.")

tests <- list()
sp_path <- rc_init_standing_p1(rd, "P1S03_own_spec_qualification", seeds, purpose, hypothesis, edition = 1L,
                               scan = list(source = "own_spec"), exposures = exposures, conclusion_scope = conclusion_scope, tests = tests, root = root)
sp <- rc_json_read(sp_path)
sp[["pins"]] <- list(
  files = list("02_Infrastructure/reinforcement/rf_base_cache.R", "02_Infrastructure/reinforcement/rf_base_align.R",
               "02_Infrastructure/replication/replication_harness.R", "02_Infrastructure/contracts/backtest_result_contract.R",
               "02_Infrastructure/validation/lookahead_detector.R", "02_Infrastructure/contracts/save_bt_result.R",
               "02_Infrastructure/reinforcement/rf_rebalance.R", "02_Infrastructure/factor_db/factor_db_connector.R",
               "02_Infrastructure/portfolio/weight_catalog.R", "02_Infrastructure/factor_db/factor_combinable.R",
               "02_Infrastructure/factor_db/factor_z_standard.R", "02_Infrastructure/portfolio/advanced_weights.R",
               "02_Infrastructure/methods/method_registry.R",
               "02_Infrastructure/factor_db/fc_engine_gen.R", "02_Infrastructure/factor_db/fc_combiner_gen.R", "06_Registry/factor_combinable.json"),
  basis = paste0("pins.R '핀 = 판정에 닿는 전체' — 판 2(P1S02) 목록 승계 + 자체 사양 입구의 판정 경로: 생성기 둘(fc_engine_gen.R · fc_combiner_gen.R — 입구가 엔진 본문을 다시 만들어 대조하는 함수 · ",
                 "코어 v4 README '생성기 변경을 새 판으로 묶으려면 판 작성자가 pins.files 에 넣는다') · 결합용 뷰 설정(06_Registry/factor_combinable.json — 엔진 입력 뷰의 정의 · P1R03 · P1R04 와 같다). ",
                 "제외 = factor_registry.json(공유 등록부 — 다른 세션이 맞춤 팩터를 수시로 더한다 · 엔진은 own_spec 의 부호 s_reg 를 고정하고 본문 실행 단정이 뷰 부호와 대조해 어긋나면 멈추므로 조용히 바뀌지 않는다) · ",
                 "결합용 뷰 저장본 · IC 원장(자료면 — 측정 셸의 데이터 지문 · 기저 캐시 키 · 판 표식이 다룬다)."))
rc_standing_validate(sp, root)
rc_json_write(sp, sp_path)
cat(sprintf("[init_p1s03] 사양 %s · 시드 n_family %d · 생성 함수 핀 %s · 갈래 %s · 판 %s\n", sp_path, nf, sp[["standing_cfg"]][["generator_pin"]][["fn_md5"]],
            sp[["standing_cfg"]][["track"]], sp[["standing_cfg"]][["edition"]]))
