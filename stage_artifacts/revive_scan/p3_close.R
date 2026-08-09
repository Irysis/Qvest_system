## 되살림 스크린 종결 — 오염 영향 상한 확정 + close_round
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/revive_scan")
say  <- function(fmt, ...) { cat(sprintf(paste0("[cl] ", fmt, "\n"), ...)); flush.console() }

V <- list(
  round_id = "REVIVE_SCAN_20260809",
  origin = "FQ-187 next_probe ③ — '실패 판정이 오염 기인일 수 있다'(tail_asym 0.996→1.132 사례의 일반화)",
  as_of = "2026-08-09", metric_type = "canonical_screen_diag", capital_claim = FALSE,
  verdict = "NO_REVIVABLE_CANDIDATES — 오염의 PORT_t 억압력이 문턱 근방 실패를 뒤집기에 부족",

  contamination_window = list(
    finding = "★오염은 **2026 에 국한**된다",
    by_year = "gap 중앙 2015~2025 = 0.0037~0.0057 (p99 초과일 0~2일) vs **2026 = 0.0198 (3.62배), p99 초과 27/147일 = 18.4%**",
    monthly = "월 벤치 sd: 2026 **0.2483** vs 2025 이전 0.0707 = **3.51배**. 2026 = 7개월 = 전체의 **1.64%**",
    meaning = "2025 이전 판정은 오염 무관 — 재검 범위가 '측정 창이 2026 을 포함한 라운드' 로 좁혀진다"),

  suppression_bound = list(
    mechanism = "오염은 활성수익 sd(분모)를 부풀려 PORT_t 를 **억누른다** ⇒ 제거 시 t 가 오른다(되살림 방향)",
    analytic_worst = "벤치 sd 3.51배 × 비중 1.64% → 전체 sd 1.089배 → PORT_t **8.2% 억압** · 되살림 구간 [2.708, 2.95)",
    simulated = "실제 벤치 계열로 가짜 알파 200회 모의: t(포함) 3.924 → t(제외) 4.067 = **+4.5%** · 되살림 구간 **[2.823, 2.95)**",
    key = "★상한이 4.5~8.2% 다. 문턱 2.95 를 넘기려면 원값이 최소 2.708 이어야 한다."),

  candidate_census_and_identity_check = list(
    raw_hits = "원장 192 항목에서 PORT_t 2.0~2.95 언급 **22건** · ratio 0.80~1.00 **1건**",
    band_filter = "되살림 구간 [2.823, 2.95) 진입 = **3건** (FQ-103 · FQ-127 · FQ-161)",
    identity_check = "★★3건 전부 동일값 **2.879** 를 인용 — 정체 검사 결과 **실패 판정이 아니라 성공 라운드의 기준선(base)**",
    what_2879_is = "WT-014 MAX5 유니버스-필터 라운드의 **base** PORT_t. 필터 적용 후 **3.620** 으로 통과했다(ΔIR +0.1692, abs MDD −55.9%→−44.4%). FQ-127 은 그 base 가 재구성본이라 production base(6.830)에서 부호가 뒤집힌다는 별건 경고, FQ-161 은 그 사례를 비교 기준선으로 인용.",
    verdict = "★진짜 되살림 후보 **0건**. 내 정규식이 base 를 후보로 오인했다 — 오늘 세 번째 '존재 검사 vs 정체 검사' 사례."),

  generalizable_finding = list(
    title = "★오염의 되살림 위험은 **통계량 종류에 의존**한다",
    mean_based = "PORT_t(평균 기반 t): 억압 ≤ 8.2% — 되살림 후보 0",
    tail_moment_based = "tail_asym(꼬리 확률): **+13.7%**(0.996→1.132) · 적률 왜도: **+94%**(0.299→0.581 역방향)",
    why = "2026 은 일수의 1.7% 지만 그 중 18.4% 가 p99 초과 극단일이다. 평균 기반 통계는 극단일에 둔감하고, 꼬리·적률 기반은 지배당한다.",
    rule = "★**오염 기인 실패 의심은 꼬리·적률 기반 판정에 한정해 적용**하라. PORT_t 등 평균 기반 판정은 1.6% 오염으로 뒤집히지 않는다.",
    consequence = "FQ-187 이 제안한 '과거 문턱 근방 실패 전수 재검' 은 **평균 기반 판정에 대해서는 불필요**로 확정. 꼬리·적률 기반 판정만 대상."),

  honest_caveats = c(
    "억압 상한은 '활성수익 sd 가 벤치 sd 팽창을 그대로 물려받는' 최악 가정 — 실제 전략은 벤치와 상관이 1 미만이라 더 작다",
    "모의 검증은 벤치 상관 0.9 · 초과 0.5%/월 단일 설정 — 다른 알파 프로파일에서는 다를 수 있다",
    "원장 본문 정규식 추출이라 산출물에만 있고 원장에 안 적힌 판정은 놓친다(census 한계)",
    "★2026 오염 자체는 미수리 — 칩 task_5452df6a. 수리 후 실제 값이 바뀌면 이 상한 계산도 갱신 필요"),

  artifacts = c("p0_census.R/gap_by_year.csv/cand_port_t.csv", "p1_max_effect.R/p1_sim.csv", "p2_identity.R"))
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), file.path(OUT, "validation.json"))
say("validation.json 기록 — %s", V$verdict)

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "REVIVE_SCAN_20260809", verdict_type = "capability_established",
  mechanism_diagnosis = paste0(
    "2026 벤치 오염이 PORT_t 를 억누를 수 있는 상한은 4.5~8.2% 다 — 2026 이 표본의 1.64% 뿐이고, ",
    "평균 기반 t 통계는 소수 극단일에 둔감하기 때문이다. 되살림 가능 구간 [2.823, 2.95) 에 들어온 후보 3건은 ",
    "정체 검사 결과 전부 **실패 판정이 아니라 성공 라운드(WT-014 MAX5 필터)의 기준선 2.879** 였다. ",
    "★그러나 같은 오염이 tail_asym 은 13.7%, 적률 왜도는 94% 움직였다 — 2026 은 일수의 1.7% 지만 그 중 18.4% 가 ",
    "p99 초과 극단일이라 **꼬리·적률 기반 통계는 지배당하고 평균 기반은 안 당한다**. 되살림 위험은 통계량 종류에 의존한다."),
  next_probes = c(
    "★꼬리·적률 기반 판정 전수 재검 — 평균 기반은 불필요로 확정됐으나 꼬리·적률 기반은 오염 민감도가 10~20배다. 그런 판정이 원장에 몇 건인지 census.",
    "2026 오염 수리(칩 task_5452df6a) 후 상한 재계산 — 수리로 실제 값이 바뀌면 이 억압 상한도 갱신되어야 한다.",
    "★원장 인용 규약 — 내 정규식이 '성공 라운드의 base' 를 '실패 판정' 으로 오인했다. 원장에 수치를 적을 때 **base/verdict 를 구분하는 접두**(예: base_PORT_t / verdict_PORT_t)가 있으면 기계 판독이 가능해진다.",
    "gap 기반 오염 검사기를 상시 배터리로 — 이번에 |BM_Ret − median(종목 Ret)| 이 크기 휴리스틱 없이 결함을 잡았다. 위반 주입 포함해 배터리 편입.",
    "다른 오염 축 — gap 은 벤치-종목 괴리만 본다. 종목 계열 자체의 오염(예: 스플릿 미조정)은 이 검사가 못 잡는다."),
  consumer_surfaces = c(
    "①팩터 랭킹 — 평균 기반 판정은 오염 무관 확정. 재검 불필요",
    "②유니버스 필터 — 해당 없음",
    "③오버레이/국면 — 해당 없음",
    "④위험모델 — 2026 변동성 추정치는 오염 영향권. 수리 전까지 인용 주의",
    "⑤monitoring — ★gap 기반 오염 검사기 배터리 편입이 가장 실행 가능한 산출",
    "⑥선별 라벨 — negative 라벨: '평균 기반 판정은 2026 오염으로 뒤집히지 않음(상한 8.2%)'",
    "⑦타 모드 — 통계량-종류별 오염 민감도 규약을 FR·RAMP 에 이식"),
  frontier_update = "신규 FQ 등재 없음 — 후보 0 확정이 곧 판정이며 별도 추적 대상이 생기지 않았다",
  live_trigger = paste0("재개 조건: ①2026 오염 수리 후 실제 값 변동폭이 8.2% 를 넘을 때 ",
    "②꼬리·적률 기반 판정 census 에서 문턱 근방 실패가 발견될 때 ③2026 외 연도에서 gap 이상이 발견될 때. ",
    "★'후보 0' 은 **평균 기반 판정 한정**이며 꼬리·적률 기반은 여전히 열려 있다."),
  layer = "측정무결성",
  evidence_refs = c("stage_artifacts/revive_scan/validation.json", "stage_artifacts/revive_scan/gap_by_year.csv",
                    "stage_artifacts/FQ187/validation.json", "stage_artifacts/FQ182/p5_bench_stock_gap.csv"))
say("=== 종결 ===")
