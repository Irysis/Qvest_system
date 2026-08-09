## FQ-182 종결 — 원장 환류 + next_probe 등재 + close_round
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[cl] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))

i <- which(ids == "FQ-182")
Q$entries[[i]]$status <- "refuted_single_day_artifact_20260809"
Q$entries[[i]]$owner  <- "COMPLETE — Q-Lead session 2026-08-09 (workflow wf_03dc6cd7-f14, 5 렌즈)"
Q$entries[[i]]$result_ref <- "stage_artifacts/FQ182/validation.json"
Q$entries[[i]]$next_action <- paste0(
  "★판정 REFUTED. ★★**Q-Lead 사전등록 위반이 이 라운드 최대 결함** — p1_forward.R 이 '1급 = tail_asym' 을 명시했는데 ",
  "ratio 0.571/0.996/0.401 로 전건 미달하자 **2급이던 skew 를 들고 보고**했다(forking path). 적대검증 other_markets 렌즈가 적발. ",
  "★그 2급도 6축 반증: ①2026-07-31 하루가 ON 왜도의 **99.3%**(상위3 제거 시 −0.068 부호 소멸) ",
  "②그 날은 **데이터 결함** — 벤치 +19.98% vs 종목중앙 +4.40%, gap 0.1558 = 36년 최대(Q-Lead 독립 검거, 칩 task_5452df6a) ",
  "③내 강건성 논증이 **항등변환**(자기-sd 표준화 차이 1.11e-16 = 정보 0) — 스케일 불변 ≠ 이상치 강건 ",
  "④3귀무 12셀 **전부 귀무 안**(p 0.096~0.163), se 1.33~1.87배 과소평가 ",
  "⑤전방창 h=1~2 전용, **h=60 에서 부호 반대로 유의**(5문턱) — 배분 지평에서는 반대 신호 ",
  "⑥타 계열 **0/5** 재현(KOSPI_small 부호 반대). ",
  "★살아남은 것: 문턱 8/8 부호 일관 + 깊이 **완전 단조**(0.151→0.558) · 경계층 −0.242≈OFF vs 심층 +0.396(기계적 선택 아님) · ",
  "당일 급락 제외 시 오히려 강화(+0.724) · EWMA잔차 Bowley +0.0737 이 3귀무 통과(단 GJR/EGARCH 귀무면 약해질 것 — 에이전트 자기비판). ",
  "★★배분 결론은 **논쟁 통계와 독립**: 경험분포 CRRA 최적 노출 w*(ON) < w*(OFF) **12셀 전부**, 왜도 포함해도 평균-분산 근사와 거의 동일(−0.277 vs −0.286).")
Q$updated <- "2026-08-09"

nums <- suppressWarnings(as.integer(sub("^FQ-0*([0-9]+).*$", "\\1", ids))); nums <- nums[is.finite(nums)]
k <- max(nums); free <- character(0)
while (length(free) < 2L) { k <- k + 1L; c0 <- sprintf("FQ-%03d", k); if (!(c0 %in% ids)) free <- c(free, c0) }
say("배정 ID: %s", paste(free, collapse=", "))

new <- list(
  list(id = free[1], lane = "regime_conditional",
    title = "★낙폭 **깊이 단조성**의 정체 — 유일하게 기계적 설명을 견딘 구조 (FQ-182 잔존)",
    hypothesis = paste0(
      "FQ-182 가 왜도 반전을 6축에서 반증했으나 **깊이 단조성**은 살아남았다: ",
      "경계층(−30%<dd<=−20%) skew **−0.242**(≈OFF −0.309) → 심층(<=−30%) **+0.396** → 초심층(<=−40%) **+0.558**, ",
      "문턱 −5~−40% 8/8 에서 skew_ON 이 깊이에 **완전 단조 증가**(0.151→0.558). ",
      "★'낙폭에서 벗어나려면 큰 양수가 필요' 라는 기계적 선택으로 설명되지 않는다 — 경계층이 OFF 와 같기 때문. ",
      "그리고 EWMA 변동성 잔차의 Bowley(+0.0737, thr−20)가 3귀무를 전부 통과했다(극단치·스케일 양쪽 둔감 판본). ",
      "단조성이 실재하는 상태의존 비대칭인지, 아니면 조건화가 만드는 편향(귀무 평균이 0 아님 — +0.238/+0.377)의 깊이 함수인지 가른다."),
    ev_rationale = "FQ-182 6축 반증에서 **유일하게 기계적 설명을 견딘 축**. 데이터·코드 전량 기지불. 저비용.",
    wall_check = paste0(
      "진단 축 — 자본 주장 없음. ★필수 통제 3종: ①**2026 제외**(데이터 결함, 칩 task_5452df6a 해결 전까지) ",
      "②GJR/EGARCH 귀무(sGARCH 는 레버리지 항이 없어 귀무가 좁다 — 에이전트 자기비판) ",
      "③적률 아닌 **Bowley/octile 을 1급으로 사전등록**(적률은 이번에 단일일 99.3% 지배로 실격). ",
      "★사전등록 1급이 실패하면 그것이 판정이다 — 2급 승격 금지(이번 라운드 위반 재발 방지)."),
    data_gate = "없음 (단 2026 구간은 칩 해결 전까지 제외)",
    owner = "UNCLAIMED — FQ-182 가 발행. 착수 세션은 'CLAIMED <session> <ts>' 로 갱신 후 시작.",
    status = "frontier_open",
    next_action = "①2026 제외 재산출 ②Bowley 를 1급으로 사전등록 ③GJR/EGARCH 귀무 ④깊이-연속 회귀(문턱 이분 아님) ⑤착수 전 MDE 산출",
    source_refs = list("stage_artifacts/FQ182/validation.json", "workflow wf_03dc6cd7-f14")),
  list(id = free[2], lane = "measurement_integrity",
    title = "★적률 기반 통계량 사용처 전수 — moment_fragility 계약 배선",
    hypothesis = paste0(
      "FQ-182 에서 3차 적률 왜도가 **단일일 99.3% 지배**로 무너졌고, Q-Lead 의 '스케일 불변이라 강건' 논증이 ",
      "**수학적 항등변환**(1.11e-16)임이 드러났다. 2026-08-09 `02_Infrastructure/contracts/moment_fragility.R` 를 신설했으나 ",
      "**호출부가 아직 0** 이다(스키마만 고치면 dead — 2026-08-08 교훈). ",
      "저장소 내 skew/kurt/적률 기반 통계량 사용처를 전수 조사하고 계약 경유로 배선한다."),
    ev_rationale = "측정 신뢰 훼손 계열. 계약은 만들었고 남은 건 배선 — '존재 = 배선 완료' 오독을 반복하지 않기 위함.",
    wall_check = "인프라 라운드 — 알파 라운드를 막는 결함은 아니나 **측정 신뢰 훼손** 범주라 즉시 수리 대상(헌법 존재의의 절). 배선 후 위반 주입 테스트 필수.",
    data_gate = "없음",
    owner = "UNCLAIMED — FQ-182 가 발행.",
    status = "frontier_open",
    next_action = "①`skew|kurt|moment` grep 전수(R·py) ②판정에 쓰는 지점 식별 ③assert_moment_robust 배선 ④배터리 편입 ⑤위반 주입 재확인",
    source_refs = list("02_Infrastructure/contracts/moment_fragility.R",
                       "08_Tests/contract_regression/test_moment_fragility.R",
                       "stage_artifacts/FQ182/validation.json")))
for (e in new) { Q$entries[[length(Q$entries)+1L]] <- e; say("  %s 등재", e$id) }
write_frontier_queue(Q)
id2 <- vapply(read_frontier_queue()$entries, function(e) as.character(e$id)[1], character(1))
say("재읽기: %s", paste(sprintf("%s=%s", free, free %in% id2), collapse=" · "))

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "FQ-182", verdict_type = "config_scoped_negative",
  mechanism_diagnosis = paste0(
    "사전등록 1급 판정량(tail_asym)이 세 문턱 전부 미달했고(ratio 0.571/0.996/0.401) 그것이 정본 판정이다. ",
    "Q-Lead 가 대체 보고한 2급(왜도 반전)은 단일 관측 지배로 무너진다 — 2026-07-31 하루가 ON 왜도의 99.3% 를 만들고, ",
    "그 날은 벤치가 +19.98% 인데 종목중앙은 +4.40% 로 36년 최대 격차를 보이는 **데이터 결함**이다. ",
    "게다가 '왜도는 스케일 불변' 이라는 강건성 논증 자체가 자기-sd 표준화에서 차이 1.11e-16 인 **항등변환**이었다 — ",
    "스케일 불변성과 이상치 강건성은 별개 축인데 둘을 혼동했다. 3종 귀무 12셀 전부 귀무 분포 안이고, ",
    "효과는 h=1~2 전용이며 h=60 에서는 부호가 반대로 유의하다. 타 계열 5개 중 재현 0."),
  next_probes = c(
    paste0(free[1], " 깊이 단조성의 정체 — 6축 반증에서 유일하게 기계적 설명을 견딘 축(경계층 −0.242≈OFF vs 심층 +0.396). 2026 제외·Bowley 1급·GJR 귀무 3통제 필수."),
    paste0(free[2], " moment_fragility 계약 배선 — 계약은 만들었으나 호출부 0. '스키마만 고치면 dead' 재발 방지."),
    "2026 벤치 결함 해소(칩 task_5452df6a) 후 아크 전체 재측정 — 본 라운드뿐 아니라 배분 계산(P2)도 2026 포함이다.",
    "★사전등록 규약 강화 — '1급 실패 시 2급 승격 금지' 를 close_round 또는 prereg 스키마 수준에서 기계화. 오늘 Q-Lead 가 위반했고 사람 규약으로는 안 막혔다.",
    "GJR/EGARCH 귀무 재검 — 에이전트 자기비판대로 sGARCH 귀무는 레버리지 항이 없어 좁다. 생존 셀(Bowley +0.0737)이 그 축에서 살아남는지."),
  consumer_surfaces = c(
    "①팩터 랭킹 — 해당 없음(벤치 계열 라운드)",
    "②유니버스 필터 — 해당 없음",
    "③오버레이/국면 — 원 가설이 겨눈 면. **노출 확대 근거 없음**(w* 12셀 전부 축소 방향). β_R05 단독 불변",
    "④위험모델 — sd 증가는 강건하나 leverage effect 재확인이고, 실현변동성 대비 증분 ΔR2 +0.0027(반대 방향 +0.1204) = 정보 주인이 따로",
    "⑤monitoring — dd252 는 PIT 자명해 국면 서술자로 사용 가능. ★단 2026 결함 해소 후",
    "⑥선별 라벨 — negative 라벨: '적률 기반 왜도는 단일 관측 지배 위험 — Bowley/octile + drop-k 병기 의무'",
    "⑦타 모드 — moment_fragility 계약을 FR·RAMP 에 이식"),
  frontier_update = paste0("FQ-182 status=refuted_single_day_artifact_20260809 · ",
                           paste(free, collapse=" · "), " 신규 등재 (기록 후 재읽기 확인)"),
  live_trigger = paste0("재개 조건: ①2026 벤치 결함 해소 후 재측정에서 깊이 단조성이 유지될 때 ",
    "②Bowley 를 1급으로 사전등록한 라운드에서 통과할 때 ③GJR/EGARCH 귀무에서도 생존할 때. ",
    "★반증은 **적률 기반 왜도 주장** 한정이며, 깊이 단조성과 sd 증가는 별개로 살아 있다."),
  layer = "③오버레이/국면 + 측정무결성",
  evidence_refs = c("stage_artifacts/FQ182/validation.json", "stage_artifacts/FQ182/p2_optimal_exposure.csv",
                    "stage_artifacts/FQ182/p5_bench_stock_gap.csv", "stage_artifacts/FQ182/literature_check.md",
                    "02_Infrastructure/contracts/moment_fragility.R"))
say("=== FQ-182 종결 ===")
