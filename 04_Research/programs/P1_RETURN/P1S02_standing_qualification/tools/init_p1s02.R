#!/usr/bin/env Rscript
## P1S02(P1 상설 자격 판 2 · round_core v3) 사양 만들기 — 등록 전에 한 번 돈다(사양이 이미 있으면 멈춘다).
##   실행: Rscript 04_Research/programs/P1_RETURN/P1S02_standing_qualification/tools/init_p1s02.R   (작업 디렉터리 = 저장소 루트)
##   하는 일: ① 시드 칸 사양 2개(등록된 생성 함수 rc_p1_cell_spec · rc_standing_seed_respec — 재량 없음) ② round_spec.json(rc_init_standing_p1 · 판 2)
##            ③ 등록 전 사양 후처리 — pins.files(판정에 닿는 파일 — 판 1 목록 + rf_base_align.R + 점검 v1 F-2 의 셋) · 점검 · 감독 반영 기록
##            (rejudge_prior_editions 는 기본값 false 그대로 — 판단 T1 C-20261111-079 · 판 1 항목을 이어받지 않는다)
##   규칙 · 문턱 · 표준 구성 생성 함수는 판 1(P1S01)과 같다. 달라진 것은 DESIGN.md §2.
##   초안 v2(11-12) — 격리 교차 점검 v1(prereg_draft_review_v1.md · revise) · 철학 P1 R-20261111-009 · 판단 T1/T4 R-20261111-010/011 반영(문장 · 핀 · 시험만 · 규칙 · 문턱 · 시드 사양 불변).
suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))
stopifnot(identical(RC_VERSION, "v3"))
root <- rc_root()
rd <- "04_Research/programs/P1_RETURN/P1S02_standing_qualification"
fam <- "2002.06975"
paper <- list(url = "https://arxiv.org/abs/2002.06975",
              title = "Cross-sectional Stock Price Prediction using Deep Learning for Actual Investment Management", paper_key = fam)
nf <- as.integer(rc_standing_nf_prior(fam, root))        # 계보 앞선 사전등록 · 상설 원장 회계 최댓값 — 시드 = 무가산(그대로)
basis <- sprintf("P1S02 시드(같은 판본 기준 재측정 — 시행 수 무가산 · P2R04 RX0 선례): 계보 %s 앞선 사전등록 · 상설 원장 회계 최댓값 %d 그대로", fam, nf)
dir.create(file.path(rd, "specs"), recursive = TRUE, showWarnings = FALSE)
f2 <- file.path(rd, "specs/P1S02_E2_C0.json"); f3 <- file.path(rd, "specs/P1S02_E3_RX0.json")
if (file.exists(f2) || file.exists(f3)) stop("시드 칸 사양이 이미 있다 — 덮어쓰지 않는다")
rc_json_write(rc_p1_cell_spec("P1S02_E2_C0", "04_Research/strategies/RP_AUTO_2002_06975/engine.R", paper, fam, nf, basis, root = root), f2)
rc_json_write(rc_standing_seed_respec("04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs/P0R01_E3_C0.json", "P1S02_E3_RX0", nf, basis, root), f3)
seeds <- list(list(code = "P1S02_E2_C0", engine = "E2", role = "reference", spec = f2),
              list(code = "P1S02_E3_RX0", engine = "E3", role = "reference", spec = f3))

purpose <- paste0(
  "P1 엔진 자격 규칙(P1R01 승계 · 판 1 과 같은 규칙 · 같은 문턱)을 판 2 로 다시 등록한다. 판 1(P1S01)은 첫 실측정에서 측정 경로 불일치 셋",
  "(기저 신호 격자 · 측정 시작일 미전달 · 폭)이 드러나 판정 0건으로 보류됐다(도훈 결정 P1S01-SEEDS-SKIP-TO-EDITION2-20261111). ",
  "판 2 는 판정 경로를 고친 뒤(셀 엔진 달 스냅 · 측정 시작일 전달 · 기저 캐시 판 v3 · 시드 엔진 스케줄 · 코어 v3 의 입구 사유와 측정 관문) ",
  "같은 규칙으로 레인 엔진과 시드를 표준 구성(P0R01 C0 형식 · 활성 측정 축)으로 잰다. 시드 = P1R01 자격 엔진 E2 · E3 의 활성 epoch 같은 판본 재측정.")
hypothesis <- paste0(
  "자격 = 보는 창 β-통제 t(α) ≥ tier_graduation 하한 ∧ 보는 창 상승 포착 ≥ 0.55(P1R01 승계 · 위기별 하락노출 · 시험 창 α 는 보고 전용). ",
  "기대: 레인 엔진 대다수는 미달(수익 엔진은 드물다 — P1R01 · 1계층 1차 라운드 기록). 시드 E2 · E3 은 자격 유지 예상",
  "(같은 사양의 보는 창 결과를 본 상태 — 노출 고지 · 판 2 에서는 기저 신호가 6개월 앞당겨지지만 2005-01 이후 262개월은 같은 학습 창 · 같은 시드라 ",
  "거의 같은 신호가 예상된다 — 차이 = 앞에 붙는 6개월 · 실효 시작 · 자료 판). ",
  "판정은 엔진마다 독립 · 선택 없음(자격 목록 = P4 후보).")

exposures <- list(
  "Q 는 시험 창(2023~) 성과를 본 상태다 — 판정 규칙은 보는 창 열만 쓴다(코어 검사 rc_rules_test_window_use · 시험 창 α 는 보고 전용).",
  "Q 는 시드와 같은 사양(E2 · E3 × 활성 epoch — P2R03 · P2R04 RX0 칸)의 보는 창 결과를 본 상태다 — 규칙 · 문턱은 P1R01 승계로 고정(재량 없음). 판 2 의 시드는 기저 신호 시작이 6개월 앞당겨진다 — 2005-01 이후 262개월은 같은 학습 창 · 같은 시드라 그 결과와 거의 같은 신호가 예상된다(차이 = 앞에 붙는 6개월 · 실효 시작 · 자료 판).",
  "레인 산출(재료 큐 인계 항목 · 충실도 감사 판정)을 본 상태다 — 입구 규칙은 성과 필드를 쓰지 않는다(레인 권위 기록 파일은 논문 메타를 읽으려 열지만 등급 · PORT_t · CR 필드는 쓰지 않는다 · 시험의 성과 무관 음성 대조).",
  "방향 층 정책(허용 = engine_native · factor_db_static)은 엔진 코드의 정적 특성(정본 커넥터 · 부호 층 사용)으로만 정했다 — 성과와 무관(판 1 과 같다).",
  "(판 1 고지 승계) Q 는 v10.2 전수점검에서 이 계보(2002.06975) 저장 기록의 등급 분포(전 기간 등급 포함)를 본 상태다 — 규칙 · 문턱은 P1R01 승계 그대로이고 입구 규칙은 성과 수치를 읽지 않는다.",
  "(판 1 고지 승계) Q 는 시드 E3 와 같은 사양의 전 기간 재채점 기록이 있다는 것을 안다(값은 여기 적지 않는다) — 그 지식이 첫 사슬 기저 선택에 들어가지 않게 첫 사슬 기저 규칙을 판정 전에 결론 범위에 적었다.",
  "Q 는 판 1 의 1908.01112 측정 2회(측정 무효 · 판정 없음)의 로그와 기저 캐시 신호일(날짜 · 개수)을 본 상태다 — 성과 값은 산출되지 않았다.",
  "판정 경로 변경(달 스냅 · 측정 시작일 전달 · 캐시 판 · 시드 엔진 스케줄 · 코어 v3 입구 사유 · 측정 관문)은 엔진 신호일 격자 · 개수 · 코드 구조만 보고 정했다(기저 캐시 33개의 날짜 · 개수 집계 · 성과 미열람 — 판단 Superfan T4 R-20261111-008 확인). 바뀐 경로로 잰 시드 · 레인 엔진 결과는 등록 시점에 없다.",
  "Q 는 등록 전 입구 미리보기(scan --dry-run · 사유 코드별 디렉터리 수만 · 성과 수치 없음)를 본 상태이며, 미리보기 뒤 입구 규칙을 바꾸지 않았다.")

conclusion_scope <- list(
  "자격 엔진 목록 = P4 수익 엔진 후보(활성 측정 축 · 같은 epoch 비교만). 자격 ≠ 권위 등급 · Judge · BOOK.",
  "미달 = 표준 구성(롱온리 ≤25종 EW · 15bps · 활성 축 · 월말 신호 · 월간 집행)에서 이 규칙 미달 — 논문 기전 전체의 기각이 아니다(충실구현 등급은 레인 기록).",
  paste0("입구 제외(사유 코드) = 측정하지 않음 — 판정이 아니다. 정책이 바뀌면(새 판) 다시 볼 수 있다. 판 2 에서 더한 사유 셋: ",
         "portfolio_only_base(점수 패널 없이 포트폴리오만 내는 엔진 — 비중을 점수로 읽지 않는다) · ",
         "breadth_insufficient(필요조건 — 레인 점수 패널의 보는 창 폭이 보유 상한 × 배수에 못 미친다 · 패널을 못 읽으면 막지 않는다) · ",
         "base_off_month_grid(레인 점수 패널의 보는 창에 신호일이 2개 이상인 달력 월이 하나라도 있는 엔진 — 주간 · 일간 신호, 달력 월과 어긋난 20거래일 격자도 해당 · ",
         "셀 경로가 월말 표본이 되므로 판정하지 않는다 · 측정 축은 주간 신호면 주간 리밸이고 셀 엔진의 주간 신호는 아직 없다). ",
         "포트폴리오 전용 엔진의 길은 새 판이 아니라 기여 층별이다 — 예측 = 레인 출력 계약(점수 패널) 뒤 새 인계로 같은 판 · ",
         "구성 규칙 = 비중 카탈로그 → 사슬 비중 걸음(그 걸음의 판정에 헌장 빈칸 1 · 3 · 8) · 노출 규칙 = P2 상설 판(아직 없음)."),
  paste0("측정 관문(코어 v3): 기저 정합 진단(base_alignment · month_snap_v1)이 없는 측정 · 기저가 점수 패널이 아닌 측정 · ",
         "한 달에 엔진 신호가 둘 이상(n_superseded > 0)이거나 거래일 달력에 없는 날짜의 신호가 있는(n_offcal > 0) 측정은 판정으로 가지 않는다(측정 실패로 닫힌다 — 판정이 아니다)."),
  paste0("기저 신호는 달 스냅을 지난다 — 월말 거래일 d 의 기저 = 직전 월말 뒤부터 d 까지의 엔진 신호 중 가장 늦은 것(모수 없음 · 월말 격자 엔진은 항등). ",
         "분기 · 60거래일 격자 엔진은 신호가 있는 달에만 갈아탄다(사이 달은 하네스가 보유를 이월한다). ",
         "월말이 아닌 날의 신호는 그 달 월말로 옮겨 쓴다 — 지연 최대 약 21거래일."),
  paste0("판 1(P1S01)은 판정 0건으로 보류 고정이다. 판 2 는 판 1 의 항목을 이어받지 않는다(rejudge_prior_editions = false) — ",
         "시드는 엔진이 바뀌어(스케줄 수리) 새 항목이고, 판 1 의 레인 항목 1908.01112 는 점수 패널 패치로 엔진이 바뀐 뒤 레인 재측정 · 인계를 거쳐 온다. ",
         "같은 칸을 두 판이 판정하면 기저 풀은 최신 판의 판정을 읽는다(코어 v3 — 읽을 수 있는 원장만 본다)."),
  paste0("뒤 판이 앞 판의 판정을 다시 재는 것은 판정 결과와 무관하게 정한 측정 경로 결함의 수리일 때만이다 — ",
         "고르지 않고 전 항목 · 뒤집힌 판정(미달 → 통과)은 표식 · 시드도 판마다 시행으로 센다."),
  "자격 = 수익 엔진 자격(보는 창 β-통제 알파 ∧ 강세 참여 하한 — 헌장 원칙 5 · 6 쪽). 위기 방어 · 꾸준함(헌장 §5 빈칸 18 — 낙폭 경로 · 회복)은 판정하지 않는다 — 통과를 철학 적합으로 보고하지 않는다(위기 하락노출은 보고 열 · 방어는 P4 사슬 몫).",
  "시드 E2 · E3 = 같은 계보(2002.06975) 두 구성 — 독립 엔진 둘로 세지 않는다(헌장 빈칸 17). 시드 자격은 같은 epoch 재판정이지 새 기저가 아니다. 첫 강화 사슬의 단독 기저는 2002.06975 계보 밖 상설 자격 엔진이다 — 이 계보는 엔진 결합(blend) 블록의 상대로만 쓴다.",
  "E3 = 조립 칸(엔진 + as-of IC 정렬 DB 팩터 3 · entropy · 순위 버퍼) · 계보 시행에서 고른 칸이다 — E3 자격은 선택 보정 전 값이고 엔진 기저 자격이 아니다.",
  paste0("시드 엔진은 판 2 에서 스케줄이 고쳐졌다(FIDELITY changed(17)) — 측정 시작일(축 시작)을 받아 첫 신호가 2004-07 월말이다(시작일을 받지 않던 앞선 측정은 2005-01 월말). ",
         "판 2 시드 재측정은 같은 추첨의 재현이다(2005-01 이후 같은 학습창 · 입력 · 시드) — 앞선 같은 사양 측정(P2R03 · P2R04 기준 칸)과 맞아도 시드 강건성 증거가 아니다",
         "(헌장 빈칸 21 — 시드 미결 그대로). 창이 다르므로 값 비교는 같은 판 안에서만 한다."),
  paste0("학습 난수가 있는 엔진(E2 · E3 의 DNN · 학습 난수가 있는 레인 엔진)의 자격 = 시드 미결(재시드 띠 미측정 — 헌장 빈칸 21)이고, 원장에 학습 난수 꼬리표가 없다. ",
         "소형주 착시(유동성 구간 귀속) · 크기 짝 선택 알파 = 미측정."),
  paste0("기저 풀(코어 v3 rc_p4_base_pool)은 이 판의 보는 창 열 가운데 상승 포착 중앙값만 읽는다. 현금 기계 검사(헌장 빈칸 24)는 q_uc 와 같은 조건이라 통과 엔진에서는 늘 '아님'이다. ",
         "강세 구간별 참여(빈칸 7) · 사이클 조건 · 숨은 현금 날(칸 감사는 보유가 있는 날만 센다) · 집중(빈칸 1)은 재지 않는다. ",
         "빈칸 14~24 의 새 상설 판 적용은 빈칸 24 에서 미집행이다 — 기저 엔진의 강세 참여 단위가 헌장 결정 전이다."),
  paste0("위기 하락노출(원장 · 통과 보고)은 시장 대비 원값이다 — MC8 귀속 · 하락/상승 β 가 없다. 낮은 값은 β 축소(빈칸 3 · 8) · 크기(빈칸 14) · 숨은 현금에서도 나오므로 ",
         "방어 근거로 쓰지 않는다. 등록부 defensive 방향 상수로 들어온 엔진은 저변동 기계(원칙 5)일 수 있고, 방향 값은 원장에 없다."),
  paste0("자격 지표 하나가 계산되지 않아도 다른 지표가 미달이면 미달로 판정한다(어느 값이 와도 미달 — 3치 논리). ",
         "모든 자격 지표가 통과이거나 미정인데 하나라도 계산되지 않으면 판정하지 않고 다시 평가한다."),
  paste0("실효 시작 규칙의 보유 수는 수치 먼지 비중도 센다(코어 v3 알려진 한계) — 실효 시작 날짜는 판정 전 점검에서 본다. ",
         "후보 폭 검사는 보는 창에 하루만 넘으면 통과하는 필요조건이다."),
  "변형 스위치(.RP_VARIANT)가 있는 엔진은 셀 경로에서 엔진 기본 변형으로 돈다 — 기본값 = 레인 대표 변형은 등록 시점 7개 엔진 모두 일치이고 코어가 기계로 확인하지 않는다(판정 전 점검에서 본다).",
  paste0("원장의 보는 창 열은 판 1 과 같다(t(α) · 연 α · β · PORT_t · 월 수 · 상승 포착 · CAGR · 위기 하락노출) — 판 1 이 판 2 로 미룬 열 확장(집중 · 숨은 현금 날 · 강세 구간별 참여 · MC8 귀속 · 하락/상승 β · 팩터 방향)은 ",
         "판 2 에서도 집행하지 않았다(판 2 의 범위 = 측정 경로 정합). 그동안 통과 엔진은 철학 P2 가 진단 패킷(results/<code>/visible/)으로 판독하고, 사슬 판 등록은 그 판독 없이 기저를 받지 않는다. ",
         "통과 엔진마다 철학 P2 의 한 줄(방향 · 실패 형태 · 귀속)을 그 엔진의 다음 일 요약에 반드시 싣는다(통과 보고의 판정 줄에 귀속 없는 위기 하락노출이 실린다 — 다음 코어 판에서 가른다) · ",
         "열 확장은 원장 밖 읽기 전용 사이드카로 한다(판 재등록 불필요 · 판정에 쓰지 않는다) · ",
         "첫 사슬 판은 기저의 철학 판독 영수증을 읽는 코어 판(기저 풀 사유 philosophy_unread)으로 등록한다."))

tests <- list("08_Tests/programs/test_round_core_v3.R", "08_Tests/programs/test_round_core_v3_v2parity.R",
              "08_Tests/reinforcement/test_rf_cell_base_alignment.R", "08_Tests/reinforcement/test_rf_base_align.R",
              "08_Tests/reinforcement/test_rf_base_cache_key.R", "08_Tests/reinforcement/test_rf_base_cache_seed.R",
              "08_Tests/programs/test_round_core_v3_diag_contract.R")   # 뒤 셋 = 점검 v1 R-6(기저 캐시 판 v3 · 진단 계약)
sp_path <- rc_init_standing_p1(rd, "P1S02_standing_qualification", seeds, purpose, hypothesis, edition = 2L,
                               scan = list(orientation_admit = list("engine_native", "factor_db_static")),
                               exposures = exposures, conclusion_scope = conclusion_scope, tests = tests, root = root)
sp <- rc_json_read(sp_path)
## rejudge_prior_editions = 기본값 false 그대로(판단 T1 C-20261111-079 — 판 1 원장 = 판정 0건 · 판 2 효과 동일 · 다시 재기 조건은 결론 범위 문장)
sp[["pins"]] <- list(
  files = list("02_Infrastructure/reinforcement/rf_base_cache.R", "02_Infrastructure/reinforcement/rf_base_align.R",
               "02_Infrastructure/replication/replication_harness.R", "02_Infrastructure/contracts/backtest_result_contract.R",
               "02_Infrastructure/validation/lookahead_detector.R", "02_Infrastructure/contracts/save_bt_result.R",
               "02_Infrastructure/reinforcement/rf_rebalance.R", "02_Infrastructure/factor_db/factor_db_connector.R",
               "02_Infrastructure/portfolio/weight_catalog.R", "02_Infrastructure/factor_db/factor_combinable.R",
               "02_Infrastructure/factor_db/factor_z_standard.R", "02_Infrastructure/portfolio/advanced_weights.R",
               "02_Infrastructure/methods/method_registry.R"),
  basis = paste0("pins.R '핀 = 판정에 닿는 전체' — 판 1 목록(격리 교차 점검 권고 R-3 · R-6) 승계 + 판 2 에서 판정 경로에 들어온 rf_base_align.R(달 스냅). ",
                 "판 2 점검 v1 F-2 로 더한 셋: factor_z_standard.R(위생 유니버스 멤버십 — 모든 칸의 유니버스) · advanced_weights.R(시드 E3 의 entropy 비중) · ",
                 "method_registry.R(카탈로그 비중의 정규화 · 실패 시 등가중 대체). ",
                 "입구 breadth_insufficient 가 배수를 읽는 measurement_axis.R 과 러너 · 셀 엔진 · 워커는 코어 기본 핀에 있다. ",
                 "제외 = audit_bt_result.R(감사 표만) · rf_sleeve.R(방어 슬리브 없는 칸에서 무동작) · 비중 카탈로그 등록부 JSON(항목이 늘 때마다 판이 멈춘다 — 판 1 과 같이 코드 weight_catalog.R 만) · ",
                 "factor_dup_scan.R(dedup 을 켤 때만) · F1. QT_to_xts.r(형 변환 도구) · refresh_barrier.R(운영 관문 · 값에 닿지 않음) · ",
                 "factor_registry.json(E3 의 DB 팩터는 방향 ic_asof 기본이라 등록부 방향을 읽지 않는다 · 자료면)."))
sp[["changes_after_review"]] <- list(
  "격리 교차 점검 v1(prereg_draft_review_v1.md · revise) → 초안 v2: F-2 핀 3 · R-1 시드 서술 · R-2 입구 · 관문 문장 · R-3 실효 시작 먼지 · 폭 필요조건 · 달 스냅 지연 · R-4 판 1 항목 · R-6 시험 3 · S-3 성과 필드 문장.",
  "사양 밖(판 폴더 도구 · DESIGN): F-1 tick_hold 를 판 폴더 커밋에 넣은 뒤 등록 · R-5 판정 전 점검 기대값 인자 · S-1 scan 순서 · S-2 --eval 의 평가 캐시 · S-4 생성 규칙문 문장 뜻(DESIGN §6).")
sp[["changes_after_superfan"]] <- list(
  "철학 P1 R-20261111-009: C2 대안 (1)~(4) · 노출 고지 2번째 줄 정정 · C1 (다) 판독 목록(DESIGN §5) · C1 (가) · C3 판 2 동안의 대체(결론 범위 원장 열 줄) · C4 길 문장(빈칸 1 · 3 · 8).",
  "판단 T1/T4 R-20261111-010 · 011: C-079 rejudge_prior_editions = false + 다시 재기 조건 줄 · C-080 3치 논리 줄 · C-085 등록 전 리허설(rehearsal/) · C-086 감시 셸 순서 · 창 · C-081 판정 전 점검 기대값 · C-087 사이드카 · C-088 다음 코어 판 후보(DESIGN §6).")
rc_standing_validate(sp, root)
rc_json_write(sp, sp_path)
cat(sprintf("[init_p1s02] 사양 %s · 시드 n_family %d · 생성 함수 핀 %s\n", sp_path, nf, sp[["standing_cfg"]][["generator_pin"]][["fn_md5"]]))
