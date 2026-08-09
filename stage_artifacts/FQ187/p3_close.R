## FQ-187 종결 — 아크 최종 판정 + 원장 + close_round
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ187")
say  <- function(fmt, ...) { cat(sprintf(paste0("[cl] ", fmt, "\n"), ...)); flush.console() }

V <- list(
  round_id = "FQ-187", parent = "FQ-182 (REFUTED)",
  origin = "도훈 지시 2026-08-09 '집요하게 더 검증해봐' — 아크 7번째이자 최종 라운드",
  as_of = "2026-08-09", metric_type = "canonical_screen_diag", capital_claim = FALSE,
  verdict = "ARC_RESOLVED — 도훈 원 가설 불지지 확정 (정제 데이터 9/9)",

  cleaning = list(
    C1 = "2026 전체 제외 (벤치sd/종목중앙sd 2.15배 = 계열 고유 결함)",
    C2 = "벤치-종목 괴리 상위 오염일 제거 (gap > p99 = 0.0468)",
    retained = "8541 / 8751 일 = 97.6%",
    window = "1991-01-17 ~ 2025-12-30"),

  headline_1_allocation_final = list(
    result = "★정제 후 w*(ON) < w*(OFF) **9/9 셀** · 부호 뒤집힌 셀 **0**",
    cells = "−10%/g2 −0.780 · −10%/g5 −0.589 · −10%/g10 −0.295 · −20%/g2 −0.234 · −20%/g5 −0.094 · −20%/g10 −0.047 · −30%/g2 −0.311 · −30%/g5 −0.125 · −30%/g10 −0.062",
    key = "★정제하면 오히려 **더 강해진다**(−10%/g2: −0.696→−0.780 · −30%/g2: −0.150→−0.311). 오염이 결론을 만든 게 아니라 **가리고 있었다**.",
    cost_correction = paste0("★Q-Lead 정정: '매일 리밸 15bps×250회 = 연 37.5%' 는 **틀렸다**. ",
      "dd252<=−20% 는 지속 상태라 상태전환이 175회(**연 5.0회**)뿐이고 연 비용 **0.18%**(−30%는 0.11%). ",
      "비용은 문제가 아니다 — **기대값 자체가 반대 방향**이라 비용을 논하기 전에 진다.")),

  headline_2_my_discarded_primary_was_masked = list(
    finding = "★★내가 '실패' 판정하고 버린 tail_asym 이 **오염에 눌려 있었다**",
    ratios = "R0 원본 0.996(미달) → C1 2026 제외 **1.132** → C1+C2 **1.008** (전부 thr −20%)",
    meaning = "원판 0.996 은 오염 때문에 문턱 아래로 눌린 값. 정제하면 문턱을 넘는다.",
    rule = "★**실패 판정이 오염 때문일 수 있다** — 1급이 문턱 근방에서 떨어지면 데이터 정합을 먼저 의심할 것. 앞으로 매번 확인할 축.",
    but = "되살려도 쓸 수 없다 — 아래 참조"),

  headline_3_tailasym_hard_test = list(
    circular_shift_null = "2000 draw · 관측 +0.0208 vs 귀무 평균 −0.0001/sd 0.0068 → **p_one 0.0000 · p_two 0.0010** = 실재",
    episode_cluster = "ON 1989일이 병합 에피소드 **17개** → se 팽창 **10.82배** → ratio **0.109** = 소멸",
    which_null_is_right = paste0("★두 결과가 충돌한다. **순환이동이 더 원칙적** — 신호의 시계열 구조를 유지한 채 대응만 끊는다. ",
      "클러스터 se 는 '에피소드 내 모든 날이 동일 관측(정보 0)' 가정인데 일간 자기상관 0.012 라 과하다. 진실은 사이."),
    horizon = "★★h=1 전용: h=1 p 0.007 · h=2 0.073 · h=3 0.077 · h=5 0.257 · **h=10 −0.0145(p 0.853)** · h=20 −0.0226 · h=60 −0.0570",
    verdict = "실재하나 **h=1 전용이고 h>=10 부호 반대** — 배분 지평에서는 반대 신호. 3문턱 중 −20% 1셀뿐.",
    why_unusable = "★평균은 전 구간 비유의 — 꼬리 비대칭이 **중앙부에서 상쇄**된다는 뜻. 노출 결정에 쓸 정보가 아니다."),

  headline_4_depth_monotonicity_dead = list(
    claim = "FQ-182 에서 유일하게 기계적 설명을 견딘 생존 실",
    clean_measurement = "Bowley(강건) 기준 OFF +0.0039 · (−20,−10] **−0.0422** · (−30,−20] +0.0093 · (−40,−30] **−0.0686** · (−100,−40] +0.0945",
    verdict = "★**비단조** — 깊이 단조성은 적률(m3)에서만 보이고 강건 지표에서는 사라진다. 적률은 이미 실격(단일일 99.3% 지배). 생존 실 끊김."),

  arc_final_7_rounds = list(
    rounds = c("①배분 월간 = 판정불가", "②선별 이분 = 판정불가(에피소드 4)", "③선별 연속 = 판정불가(효과 크기)",
               "④선별 42구성 지도 = LANE_CONFIG_CLOSED", "⑤배분 일간 = 착수전폐기(관측단위 하향은 정보 미증가)",
               "⑥분포 형태 = REFUTED(단일 오염일 99.3%)", "⑦정제 재검 = **불지지 확정 9/9**"),
    answer = paste0("★'위기신호 발현 시 총노출 확대' 는 **지지되지 않는다**. ",
      "단 도훈 직관이 완전히 빗나간 것은 아니다 — 위기 뒤 분포는 실제로 달라진다. ",
      "다만 변화가 **양방향**이고(상방꼬리 3.09배 vs 하방 1.85배), 평균은 안 움직이며, 변동성만 2~3배 커진다. ",
      "결과적으로 **어떤 위험회피 수준에서도 줄이는 것이 최적**이다."),
    what_persistence_bought = c(
      "①2026 벤치 데이터 결함 검거 — 안 팠으면 못 찾았다(칩 task_5452df6a, 타 라운드에도 영향)",
      "②'실패 판정이 오염 때문일 수 있다' 는 새 축 — tail_asym 0.996→1.132",
      "③결론이 정제 후 **더 강해짐** — 반대였다면 아크 전체를 다시 해야 했다")),

  honest_caveats = c(
    "정제는 2026 제외 + gap>p99 제거 2종뿐 — 다른 오염 축은 미검",
    "w* 계산은 실측 경험분포 위 CRRA 수치최적화이며 백테스트가 아니다(metric_type=canonical_screen_diag)",
    "블록부트 P(차이>0) 0.28~0.31 — 음의 차이도 유의하지 않다. 근거는 9/9 일관성과 기전 명확성",
    "tail_asym h=1 실재는 순환이동 귀무 기준이며 에피소드-클러스터 기준으로는 소멸. 두 se 규약의 중간이 진실",
    "★타 계열 tail_asym 재현은 미측정 — FQ-182 의 other_markets 는 skew 기준이었다"),

  artifacts = c("p0_clean_rerun.R/p0_clean_grid.csv", "p1_tailasym_hard.R/p1.rds",
                "p2_clean_allocation.R/p2_clean_allocation.csv"))
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), file.path(OUT, "validation.json"))
say("validation.json 기록 — %s", V$verdict)

source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-187")
Q$entries[[i]]$status <- "arc_resolved_not_supported_20260809"
Q$entries[[i]]$owner <- "COMPLETE — Q-Lead session 2026-08-09 (도훈 '집요하게 더 검증' 지시 수행)"
Q$entries[[i]]$result_ref <- "stage_artifacts/FQ187/validation.json"
Q$entries[[i]]$next_action <- paste0(
  "★아크 최종 판정 — 도훈 원 가설(위기 시 총노출 확대) **불지지 확정**. 정제(2026 제외 + gap>p99 제거, 97.6% 유지) 후 ",
  "w*(ON) < w*(OFF) **9/9 셀**, 부호 뒤집힌 셀 0, 그리고 **정제하면 오히려 강해진다**(−10%/g2 −0.696→−0.780). ",
  "⇒ 오염이 결론을 만든 게 아니라 가리고 있었다. ",
  "★★부수 1급 = **내가 버린 tail_asym 이 오염에 눌려 있었다**(0.996 미달 → 정제 1.132/1.008 통과). ",
  "**실패 판정이 오염 때문일 수 있다** — 1급이 문턱 근방에서 떨어지면 데이터 정합을 먼저 의심하는 축 신설. ",
  "단 되살려도 사용 불가: 순환이동 귀무 p<0.001 로 실재하나 **h=1 전용**(h=2 p 0.073 · h=5 0.257 · **h>=10 부호 반대**), ",
  "에피소드-클러스터(병합17개, se 10.8배)로는 ratio 0.109 소멸, 평균은 전 구간 비유의(꼬리 비대칭이 중앙부에서 상쇄). ",
  "★생존 실이던 깊이 단조성도 **Bowley 기준 비단조**(−0.042/+0.009/−0.069/+0.095) — 적률에서만 보이던 것. ",
  "★비용 정정: 'h=1 이라 연 37.5% 비용' 은 틀렸다 — dd 는 지속 상태라 전환 연 5.0회, 연 비용 0.18%. **비용이 아니라 기대값이 반대**다.")
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
say("원장 기록 · 재읽기 status=%s", read_frontier_queue()$entries[[i]]$status)

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "FQ-187", verdict_type = "config_scoped_negative",
  mechanism_diagnosis = paste0(
    "위기 뒤 수익 분포는 실제로 달라지지만 변화가 양방향이다 — 상방 꼬리 3.09배, 하방 1.85배, 변동성 2~3배, ",
    "그리고 평균은 전 구간 비유의다. 꼬리 비대칭(tail_asym)은 순환이동 귀무에서 p<0.001 로 실재하나 h=1 전용이고 ",
    "h>=10 에서는 부호가 반대이며, 평균이 안 움직인다는 것은 그 비대칭이 중앙부에서 상쇄된다는 뜻이다. ",
    "결과적으로 실측 경험분포 위 CRRA 최적 노출은 정제 데이터 9/9 셀에서 위기 상태가 더 낮고, 정제할수록 격차가 커진다. ",
    "★오염(2026 벤치 결함)은 결론을 만든 것이 아니라 가리고 있었다."),
  next_probes = c(
    "★타 계열 tail_asym 재현 — FQ-182 의 other_markets 는 skew 기준이었다. h=1 꼬리 비대칭이 KR 고유인지 미측정.",
    "2026 벤치 결함 해소(칩 task_5452df6a) 후 2026 포함 재측정 — 본 라운드는 제외로 답했으나 포함판이 정본이 되어야 한다.",
    "★'실패 판정의 오염 기인' 스크린 — tail_asym 0.996→1.132 사례를 일반화해, 과거 문턱 근방 실패 판정들이 데이터 오염 때문이었는지 전수 재검. 되살아나는 후보가 있을 수 있다.",
    "위기 뒤 **축소**의 최적 크기 — 이 아크는 '확대 불지지' 를 확정했다. 반대 방향(얼마나 줄일 것인가)은 미측정이며 현행 β_R05 오버레이 대비 증분이 있는지가 질문.",
    "에피소드-클러스터 se 규약 확정 — 순환이동(p<0.001)과 클러스터(ratio 0.109)가 10배 갈린다. 어느 것을 정본으로 할지 규약이 없다."),
  consumer_surfaces = c(
    "①팩터 랭킹 — 해당 없음(배분 축)",
    "②유니버스 필터 — 해당 없음",
    "③오버레이/국면 — ★원 가설이 겨눈 면. **확대 근거 없음 확정**. 다만 '축소' 방향은 미측정(next_probe ④)",
    "④위험모델 — 변동성 2~3배 증가는 강건하나 leverage effect 재확인이고 실현변동성 대비 증분 미미(ΔR2 +0.0027)",
    "⑤monitoring — dd252 는 PIT 자명, 국면 서술자로 사용 가능(2026 결함 해소 후)",
    "⑥선별 라벨 — negative 라벨 2종: '적률 왜도는 단일 관측 지배 위험' + '문턱 근방 실패는 오염 기인 의심'",
    "⑦타 모드 — moment_fragility 계약 + 오염 스크린(gap 기반)을 FR·RAMP 에 이식"),
  frontier_update = "FQ-187 status=arc_resolved_not_supported_20260809 (기록 후 재읽기 확인)",
  live_trigger = paste0("재개 조건: ①2026 결함 해소 후 포함판 재측정에서 부호가 바뀔 때 ",
    "②타 계열에서 h=1 꼬리 비대칭이 재현되고 h 확장에서도 유지될 때 ③에피소드-클러스터 se 규약이 순환이동 쪽으로 확정될 때. ",
    "★불지지는 **'확대' 방향 한정**이며 '축소' 최적 크기는 미측정이다 — 방향 자체가 닫힌 것이 아니다."),
  layer = "③오버레이/국면 + 측정무결성",
  evidence_refs = c("stage_artifacts/FQ187/validation.json", "stage_artifacts/FQ187/p2_clean_allocation.csv",
                    "stage_artifacts/FQ182/validation.json", "stage_artifacts/FQ182/p5_bench_stock_gap.csv"))
say("=== FQ-187 종결 ===")
