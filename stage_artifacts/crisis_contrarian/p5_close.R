## 위기신호 역방향 — P5: 판정 기록 + 원장 등재 + close_round
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/crisis_contrarian")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p5] ", fmt, "\n"), ...)); flush.console() }
R <- fread(file.path(OUT, "p4_mechanical_cells.csv"))

V <- list(
  round_id = "CRISIS_CONTRARIAN_20260809",
  origin = "도훈 지시 2026-08-09 — 위기신호 발현 시 비중 확대 (시장 선행 논리)",
  as_of = "2026-08-09", metric_type = "canonical_screen_diag", capital_claim = FALSE,
  prereg_ref = "preregistration.json (측정 전 작성)",
  verdict = "K2_INCONCLUSIVE_DIRECTIONALLY_FAVORABLE",

  stage_1_label_engine = list(
    finding = "라벨 엔진 산출물로는 가설을 시험할 수 없다",
    evidence = "msm Crisis(n=124) 주변 벤치 연율: 전전월 +16.37 · 전월 +18.19 · 당월 +21.29 · 익월 +31.65 vs 비-Crisis +9.57/+9.69/+6.82/+2.70. 네 구간 전부 높다 = 하락 국면이 아니라 고수익 국면 표시.",
    pit_status = "미해결 — vintage 저장 전무(regime_vintage/vintage/msm_vintage 부재), 단일 *_latest.parquet. 전표본 smoothing 지문과 정합하나 확정 못함.",
    production_check = "msm_hybrid Target_Weight=0 이 124개월(29%)에 걸려 있으나 소비자는 bootstrap.sh·daily_refresh.sh·telegram_notify.R 등 ops/보고 경로뿐 — 비중 산출 **미배선**. 라이브 결함 아님."),

  stage_2_mechanical = list(
    why = "기계적 정의는 월말 관측 가능·재적합 여지 0 이라 PIT 논쟁이 원천 소멸한다",
    grid = "S1 당월수익 {−5,−10,−15}% · S2 3개월누적 {−10,−15,−20}% · S3 12개월낙폭 {−10,−20,−30}% (사전등록, argmax 금지)",
    cells = 9L, significant = 0L, underpowered = 9L,
    direction_all_positive = TRUE,
    f1_diff_range_ann_pct = c(min(R$f1_diff_ann), max(R$f1_diff_ann)),
    max_t = max(abs(R$f1_t)),
    required_range_ann_pct = c(min(R$required_ann), max(R$required_ann)),
    cells_table = R[, .(family, threshold_pct, n_on, f1_diff_ann, f1_t, required_ann, verdict)]),

  key_structural_finding = list(
    title = "★효과가 있다면 그것은 **빈도가 아니라 크기**다 — 그래서 구조적으로 저검정력이다",
    evidence = "익월 양수 비율(적중률) ON vs OFF: 얕은 문턱은 동률(0.52 vs 0.52~0.53), **깊은 문턱은 오히려 ON 이 낮다**(S1−15% 0.38 · S2−20% 0.39 · S3−30% 0.47). 그런데 평균 차이는 전부 양(+).",
    reading = "하락 뒤 반등은 **더 자주** 오지 않고 **더 크게** 온다. 분산이 커지므로 같은 평균 효과라도 t 가 안 나온다. 이는 도훈 가설이 틀렸다는 뜻이 아니라, **이 판정량(월간 벤치 평균)으로는 원리적으로 확정 불가**하다는 뜻이다.",
    implication_for_portfolio = "평균은 오르되 분산도 커지므로 Sharpe 개선은 **별개 질문**이다. 비중 확대 규칙을 설계하려면 수익 평균이 아니라 위험조정 기준으로 재판정해야 한다."),

  power_limit = list(
    statement = "★439개월·월간 벤치(sd 8.18%)·사건 30~80개월 조합에서 필요 효과는 연 24.6~87.7% 다. 관측 4.7~23.4% 는 그 아래다.",
    conclusion = "이 가설은 **월간 시장-타이밍 프레임으로는 구조적으로 판정 불가**다. 검정력을 못 올리면 몇 번을 재도 같은 라벨이 나온다.",
    honest_note = "9/9 셀이 같은 방향인 것을 부호검정으로 읽지 말 것 — 셀들이 서로 포함관계·시간중첩이라 독립 9회가 아니다."),

  productive_redirection = list(
    title = "★프레임 전환 — 시장 타이밍(1계열)이 아니라 횡단면(300종목×월)으로",
    rationale = "이 시스템의 검정력은 횡단면에 있다. '언제 시장에 더 들어갈까' 는 표본이 439개인데, '위기 직후 어떤 종목이 더 반등하나' 는 표본이 수만이다.",
    concrete = "기계적 하락 신호 ON 인 달의 **다음달 횡단면**에서 어떤 팩터의 IC 가 커지는가(국면-조건부 팩터 자격). 이는 배분이 아니라 **선별** 축이라 제약 조건 안이고, 기존 하네스가 그대로 쓰인다.",
    caution = "국면-조건부 분할은 이 저장소에서 검정력 파괴가 반복 실증된 축이다 — 착수 전 required_effect 필수(n_ON×종목수로 유효표본이 회복되는지 먼저 확인)."),

  self_correction_logged = "중간 보고에서 '도훈 직관이 forward 축에서 확인됐다' 고 말했으나, 그 라벨이 위기 라벨인지 확인 전이었다. P3 에서 아님이 드러나 즉시 정정했다. forward 수치 자체는 실측이나 가설 지지 근거가 아니다.",
  artifacts = c("preregistration.json","findings_interim.json","p0_dup_check.R","p1_label_census_power.R",
                "p2_forward.R","p2_forward_cells.csv","p3_pit_gate.R","p4_mechanical.R","p4_mechanical_cells.csv"))
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), file.path(OUT, "validation.json"))
say("validation.json 기록")

## ── 원장 등재 (ID 하드코딩 금지 — 최대+1 계산 후 재읽기 확인) ──────────────────
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
nums <- suppressWarnings(as.integer(sub("^FQ-0*([0-9]+).*$", "\\1", ids))); nums <- nums[is.finite(nums)]
free <- character(0); k <- max(nums)
while (length(free) < 2L) { k <- k + 1L; c0 <- sprintf("FQ-%03d", k); if (!(c0 %in% ids)) free <- c(free, c0) }
say("배정 ID: %s", paste(free, collapse=", "))

new <- list(
  list(id = free[1], lane = "regime_contrarian",
    title = "★위기신호 역방향 소비의 **횡단면** 판본 — 하락 직후 반등을 어떤 종목이 가져가는가 (도훈 발안)",
    hypothesis = paste0(
      "도훈 발안(2026-08-09): '시장은 선행하므로 위기신호 발현 시점엔 이미 반영이 끝났다 — 방어가 아니라 공격이어야 한다'. ",
      "월간 시장-타이밍 프레임에서 기계적 하락 정의 9셀 전부 방향은 양(+)(연 +4.7~+23.4%)이나 **전건 검정력 미달**(max |t| 1.06, 필요 연 24.6~87.7%). ",
      "구조 진단: 하락 뒤 반등은 더 **자주**가 아니라 더 **크게** 온다(깊은 문턱에서 적중률은 오히려 하락 0.38~0.47) ⇒ 분산이 커져 평균 검정이 원리적으로 안 된다. ",
      "⇒ 프레임을 횡단면으로 옮긴다: 기계적 하락 신호 ON 인 달의 **다음달 횡단면**에서 어떤 팩터의 IC/PORT_t 가 커지는가. 배분이 아니라 **선별** 축."),
    ev_rationale = "검정력이 439개(월)에서 수만(종목×월)로 회복된다. 기존 하네스·패널 전량 재사용. 도훈 직접 발안이라 소비면 전개 의무 대상.",
    wall_check = "제약 조건 안 — 선별 축이므로 max 25·long-only·[0,0.20]·Σw=1 불변. '비중 확대' 는 overlay 승수 상한 안에서만 논의하며 레버리지 도입 금지(INV-7).",
    data_gate = "없음 (벤치·팩터 패널 기지불)",
    owner = "UNCLAIMED — CRISIS_CONTRARIAN_20260809 이 발행. 착수 세션은 'CLAIMED <session> <ts>' 로 갱신 후 시작(배정 규약).",
    status = "frontier_open",
    next_action = "①착수 전 required_effect — n_ON(월) × 월평균 종목수로 유효표본 회복 확인, 미달이면 착수 전 폐기 ②S3 12개월낙폭 −20%(n_ON 69) 기준 ON/OFF 팩터 IC 대비 ③위험조정(Sharpe) 기준 재판정 — 평균 개선이 분산 증가를 이기는지",
    source_refs = list("stage_artifacts/crisis_contrarian/validation.json",
                       "stage_artifacts/crisis_contrarian/p4_mechanical_cells.csv")),
  list(id = free[2], lane = "measurement_integrity",
    title = "국면 라벨 산출물의 PIT vintage 부재 — 전표본 재적합 여부 확정",
    hypothesis = paste0(
      "unified_regime_signal.parquet · msm_hybrid_latest.parquet 는 **단일 latest 파일**이고 vintage 디렉토리가 전무하다. ",
      "행동 지문은 look-ahead 와 정합한다: msm 'Crisis' 월이 전전월·전월·당월·익월 **전부** 비-Crisis 보다 고수익(+16.4/+18.2/+21.3/+31.7 vs +9.6/+9.7/+6.8/+2.7) ",
      "— 전표본 smoothing 이면 나오는 모양이다. regime_ensemble.R 에 rolling 배관은 있으나 실제 산출이 filtered 인지 smoothed 인지 미확정. ",
      "★이 라벨을 소비하는 어떤 측정도 확정 전까지 자본 주장 불가."),
    ev_rationale = "이 저장소는 동일 계열로 3회 데였다(저장 패널 동월 look-ahead 2.08x · FRED vintage 미저장 FQ-137 · overlay 동월 누출). 확정은 저비용(코드 1개 판독 + filtered 재산출 A/B).",
    wall_check = "측정무결성 라운드 — 자본 주장 없음. 결과가 look-ahead 확정이면 해당 라벨 소비 측정 전량 재검 대상.",
    data_gate = "없음",
    owner = "UNCLAIMED — ★인접: 병렬 세션 stage_artifacts/fq143_tail_overlay_20260809/{p2_label_source.R,p3_eligibility_pit.R} 가 오늘 라벨 출처·PIT 자격을 다룬다. 착수 전 그 세션과 범위 대조 필수.",
    status = "frontier_open",
    next_action = "①regime_ensemble.R 에서 filtered vs smoothed 확정 ②filtered-only 재산출 후 동일 4구간 프로파일 A/B ③차이가 크면 기존 라벨 소비 측정 목록 회수",
    source_refs = list("stage_artifacts/crisis_contrarian/p3_pit_gate.R",
                       "stage_artifacts/crisis_contrarian/findings_interim.json")))
for (e in new) { Q$entries[[length(Q$entries)+1L]] <- e; say("  %s 등재", e$id) }
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
id2 <- vapply(read_frontier_queue()$entries, function(e) as.character(e$id)[1], character(1))
say("재읽기 확인: %s=%s · %s=%s", free[1], free[1] %in% id2, free[2], free[2] %in% id2)

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "CRISIS_CONTRARIAN_20260809", verdict_type = "ceiling_reached_frontier_open",
  mechanism_diagnosis = paste0(
    "도훈 가설은 기각되지 않았고 지지되지도 않았다 — 월간 시장-타이밍 프레임으로는 **원리적으로 판정 불가**다. ",
    "기계적 하락 정의 9셀 전부 방향은 양(+)(연 +4.7~+23.4%)이나 필요 효과가 연 24.6~87.7% 라 전건 검정력 미달(max |t| 1.06). ",
    "구조 원인이 명확하다: 하락 뒤 반등은 더 자주가 아니라 **더 크게** 온다 — 깊은 문턱에서 익월 적중률이 오히려 낮아지는데(0.38~0.47 vs 0.53) 평균 차이는 양(+)이다. ",
    "분산이 함께 커지므로 평균 검정의 t 가 구조적으로 안 나온다. 한편 라벨 엔진 산출물은 시험 자격 자체가 없다 — ",
    "msm 'Crisis' 월이 전·당·익월 전부 고수익이라 위기를 표시하지 않으며 PIT vintage 도 부재하다."),
  next_probes = c(
    paste0(free[1], " 횡단면 판본 — 검정력이 439개월에서 수만(종목×월)로 회복된다. 하락 신호 ON 다음달 횡단면에서 어떤 팩터 IC 가 커지는가(배분 아닌 선별 축)."),
    paste0(free[2], " 라벨 PIT vintage 확정 — filtered vs smoothed. 확정 전까지 라벨 소비 측정은 자본 주장 불가."),
    "위험조정 재판정 — 평균 개선이 분산 증가를 이기는지. 평균 기준 판정량은 이 가설에 부적합할 수 있다.",
    "일간 데이터로 사건·전방창 세분 — 월간 439 관측이 병목이므로 관측 단위를 내려 검정력 확보 가능성 확인.",
    "비대칭 소비 — '확대' 가 아니라 '축소하지 않음'(방어 오버레이의 국면별 무력화)만으로도 같은 효과의 일부를 얻는지. 실행 위험이 훨씬 낮은 형태."),
  consumer_surfaces = c(
    "①팩터 랭킹 — 하락 직후 국면-조건부 팩터 자격(횡단면 판본의 1급 면)",
    "②유니버스 필터 — 미측정", "③오버레이/국면 입력 — 본 가설의 원 소비면. 월간 프레임 판정 불가로 보류",
    "④위험모델 — 반등 분산 증가는 tail 채널 입력 후보", "⑤monitoring — 기계적 하락 신호는 PIT 자명해 tripwire 로 즉시 사용 가능",
    "⑥선별 라벨 — 미측정", "⑦타 모드 — FR/RAMP 의 국면 입력으로 이식 가능(단 위 판정 한계 승계)"),
  frontier_update = paste0(free[1], " · ", free[2], " 신규 등재 (기록 후 재읽기로 존재 확인)"),
  live_trigger = paste0(
    "월간 타이밍 프레임 재개 조건: ①일간·주간으로 관측단위를 내려 필요 효과가 관측 범위 안으로 들어올 때 ",
    "②위험조정 판정량에서 방향이 유지될 때 ③", free[2], " 에서 PIT-안전 라벨이 확보돼 사건 정의가 넓어질 때. ",
    "그 전까지 이 방향은 **판정 불가**이지 기각이 아니다."),
  layer = "③오버레이/국면 + 측정무결성",
  evidence_refs = c("stage_artifacts/crisis_contrarian/validation.json",
                    "stage_artifacts/crisis_contrarian/p4_mechanical_cells.csv",
                    "stage_artifacts/crisis_contrarian/findings_interim.json"))
say("=== P5 완료 ===")
