## FQ-180 종결 — 실행가능 영역 지도 판정 + 레인 닫힘 문서화 + close_round
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ180")
say  <- function(fmt, ...) { cat(sprintf(paste0("[cl] ", fmt, "\n"), ...)); flush.console() }
G <- fread(file.path(OUT, "feasibility_grid.csv"))

V <- list(
  round_id = "FQ-180", parent = "FQ-176 → FQ-178+179",
  origin_chain = "도훈 발안(위기신호 역방향) → 배분축 판정불가 → 선별축 이분 판정불가 → 선별축 연속 판정불가 → 본 라운드(실행가능 영역 지도)",
  as_of = "2026-08-09", metric_type = "canonical_screen_diag", capital_claim = FALSE,
  round_type = "메타-절차 — 새 가설 검정 아님. 이 레인을 더 두드릴 자리가 남았는지 지도로 확정.",
  verdict = "LANE_CONFIG_CLOSED",

  reframing = paste0(
    "★FQ-180 원 프레이밍('어떤 문턱이 검정력을 주나')을 착수 시 갱신했다. ",
    "FQ-178 이 병목을 **검정력 → 효과 크기**로 바꿨기 때문이다(연속화로 MDE 10배 개선했는데도 미달). ",
    "따라서 질문은 '어떤 신호정의·문턱에서도 관측 효과가 자기 MDE 를 넘지 못하나' 가 됐다."),

  grid = list(
    cells = 42L,
    signals = c("mret","cum3","cum6","dd12","dd24","dd36","ddvol"),
    modes = c("continuous(HAC NW6 회귀)", "binary(하위 5/10/20/30/40 백분위 문턱, 에피소드-클러스터 보정)"),
    target = "FQ-178 사전등록 합성축 스프레드 (quality_growth − value) — family 1 유지",
    statistic = "ratio = |관측효과| / 자기 MDE(=2×se)"),

  result = list(
    max_ratio = 0.833, max_cell = "ddvol / continuous (변동성-조정 12개월 낙폭)",
    n_cells_above_1 = 0L, n_cells = 42L,
    runner_up = "dd12 / continuous 0.682 · mret / binary 40% 0.479 · ddvol / binary 20% 0.443",
    verdict_rule = "사전 고정: max(ratio) < 1.0 ⇒ 이 측정 프레임 구성상 닫힘",
    reading = "★42개 구성 어디에서도 관측 효과가 검출 하한에 닿지 않는다. 최선(0.833)조차 20% 부족."),

  tradeoff_measured = list(
    question = "문턱을 낮추면 에피소드는 늘지만 효과가 희석되는가",
    by_threshold = "5%: epi 7.4 · effect 0.0437 · ratio 0.289 | 10%: 12.3 · 0.0172 · 0.156 | 20%: 20.6 · 0.0201 · 0.223 | 30%: 23.9 · 0.0196 · 0.229 | 40%: 27.9 · 0.0189 · 0.224",
    cor_epi_effect = -0.147, cor_epi_ratio = 0.378,
    reading = paste0("★트레이드오프는 **약하다**. 에피소드↔효과 상관 −0.147 로 희석은 있으나 미미하고, ",
      "에피소드↔ratio 는 **+0.378 로 양수** — 문턱을 낮춰 사건을 늘리는 쪽이 순효과로 **유리**하다. ",
      "내 사전 우려('낮추면 효과가 줄어 순 검정력 개선 보장 없음')는 실측으로 **부분 반증**됐다. ",
      "다만 유리한 방향으로도 최대 0.833 에 그친다.")),

  continuous_vs_binary = list(
    cont_better_in = c("dd12 (0.682 vs 0.263)", "dd24 (0.314 vs 0.271)", "ddvol (0.833 vs 0.443)"),
    binary_better_in = c("cum3", "cum6", "dd36", "mret"),
    reading = "★연속화가 보편 우위가 아니다 — 7신호 중 3종에서만 우세. FQ-178 의 '연속화가 답' 은 **dd12 한정 관측의 일반화였다**(그 자체는 옳았으나 범위 한정 필요)."),

  decision = list(
    action = "이 레인(국면-조건부 선별 rank-IC, KR 2003~2026, 합성축 스프레드)에 대한 **반복 라운드를 멈춘다**",
    why_this_is_valuable = "폐기 판정 자체가 의사결정 가치다 — 같은 자리를 다시 두드리는 비용을 없앤다. 저검정력이 하루 3회 재현된 패턴의 기계적 종결.",
    what_is_NOT_concluded = c(
      "★방향이 틀렸다는 뜻이 아니다 — 42셀 중 대다수가 사전등록 방향과 같은 부호였다",
      "★도훈 원 가설(배분·총노출)에 대한 판정이 아니다 — 이 레인은 전부 **선별** 축이었다",
      "★다른 국면 축(유동성·수급·변동성 레짐)이나 다른 표적(합성축 아닌 구성)은 미측정")),

  revival_conditions_INV7 = c(
    "표본 확장 — 2003~2026 밖(더 긴 KR 역사 또는 타 시장)에서 심도 변동이 큰 구간이 늘 때. 필요 개선은 ratio 0.833 → 1.0 = 효과 20%↑ 또는 유효표본 44%↑",
    "효과 크기를 키우는 구성 — 합성축 성분 교체, 또는 낙폭 아닌 국면 축(유동성·수급). 현재 1sd당 spread sd 의 0.07배가 병목",
    "ddvol(변동성-조정 낙폭) 연속 — 그리드 최선(0.833)이므로 새 데이터가 오면 **첫 사전등록 대상**. ★단 이는 sweep max 이므로 지금 승격하면 사후선택이다",
    "판정량 교체 — rank-IC 는 ADVISORY 다. PORT_t 등 실현 수익 기반으로 재면 신호대잡음이 달라질 수 있다(미측정)"),

  honest_caveats = c(
    "그리드 42셀은 sweep 이다 — max(ratio) 셀을 챔피언으로 읽으면 안 된다. 판정은 '어느 셀도 1.0 미달' 이라는 **집합 수준 진술**이다",
    "이분 셀의 에피소드-클러스터 보정은 se × sqrt(n_on/n_epi) 근사다 — 정밀 클러스터 추정이 아니다. 보수적 방향",
    "합성축은 FQ-176 의 비유의 방향 패턴에서 도출됐다 — 표적 자체가 최적이 아닐 수 있다",
    "심도 신호는 전부 벤치 수익에서 파생 — 상류(bench 구성)는 이 라운드의 검증 대상 밖"),

  artifacts = c("p0_grid.R", "feasibility_grid.csv", "p0.rds"))
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), file.path(OUT, "validation.json"))
say("validation.json 기록 — %s", V$verdict)

source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-180")
Q$entries[[i]]$status <- "lane_config_closed_20260809"
Q$entries[[i]]$owner <- "COMPLETE — Q-Lead session 2026-08-09"
Q$entries[[i]]$result_ref <- "stage_artifacts/FQ180/validation.json"
Q$entries[[i]]$next_action <- paste0(
  "★판정 LANE_CONFIG_CLOSED. 신호 7종 × (연속 + 이분 5문턱) = **42셀 전부 미달**, max ratio **0.833**(ddvol/연속), ratio>=1.0 셀 **0개**. ",
  "★착수 시 프레이밍 갱신: FQ-178 이 병목을 검정력→**효과 크기**로 바꿨으므로 질문을 '어느 구성에서도 효과가 자기 MDE 를 넘지 못하나' 로 재설정. ",
  "★트레이드오프 실측: 에피소드↔효과 상관 −0.147(희석 미미) · 에피소드↔ratio **+0.378(양수)** ⇒ 문턱을 낮추는 쪽이 순효과 유리 — 내 사전 우려는 부분 반증. 그래도 최대 0.833. ",
  "★연속화는 보편 우위 아님 — 7신호 중 3종(dd12·dd24·ddvol)만 우세. FQ-178 의 '연속화가 답' 은 dd12 한정 관측의 일반화였다. ",
  "⇒ **이 레인 반복 라운드 정지**. 단 ①방향이 틀렸다는 뜻 아님(대다수 셀이 사전등록 부호와 일치) ②도훈 원 가설(배분·총노출) 판정 아님(전부 선별 축) ③타 국면축·타 판정량 미측정. ",
  "부활 = 효과 20%↑ 또는 유효표본 44%↑ / 표본 확장 / 판정량을 PORT_t 로 교체 / ddvol-연속을 첫 사전등록(★sweep max 이므로 지금 승격은 사후선택).")
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
say("원장 기록 완료 · 재읽기 status=%s", read_frontier_queue()$entries[[i]]$status)

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "FQ-180", verdict_type = "config_scoped_negative",
  mechanism_diagnosis = paste0(
    "국면-조건부 선별 레인은 이 측정 프레임에서 구성상 닫혔다. 신호 7종 × 연속/이분 5문턱 = 42셀 어디에서도 ",
    "관측 효과가 자기 검출하한(MDE)에 닿지 않으며 최선조차 0.833 으로 20% 부족하다. ",
    "병목은 검정력이 아니라 효과 크기다 — FQ-178 이 연속화로 MDE 를 10배 낮췄는데도 미달이었고, ",
    "본 라운드에서 문턱을 낮춰 에피소드를 늘리는 것이 순효과로 유리함(cor 에피소드↔ratio +0.378)이 확인됐는데도 상한이 0.833 이다. ",
    "즉 더 두드릴 자리가 이 프레임 안에는 남아 있지 않다."),
  next_probes = c(
    "판정량 교체 — rank-IC 는 ADVISORY 다. PORT_t(실현 초과수익) 기반으로 같은 국면 조건을 재면 신호대잡음 구조가 달라질 수 있다. 미측정 축이며 이 레인의 유일한 미검 차원.",
    "★배분 축 복귀 — 도훈 원 가설(위기 시 총노출 확대)은 네 라운드 모두 미시험이다. 선별 축이 닫힌 것이 배분 축을 함의하지 않는다. 월간 프레임은 판정 불가였으므로 일간/주간 관측단위로 내려야 한다.",
    "다른 국면 축 — 낙폭이 아니라 유동성 고갈·수급 급변·변동성 레짐으로 국면을 정의하면 사건 구조(에피소드 수·효과 크기)가 달라진다. 낙폭 축만 42셀 소진했을 뿐이다.",
    "사전 검정력 게이트의 절차 편입 — 본 3라운드 아크가 검증한 방법(측정 전 MDE 산출 → 자격 미달 폐기 → 실행가능 영역 지도)을 RAMP·factor-rotation 사전등록에 배선한다. 결과보다 방법이 자산이다.",
    "게이트 보수성 자기점검 — FQ-178 에서 사전 Bartlett 추정(se 0.33)이 실제 HAC(0.098)보다 3배 보수적이었다. 게이트가 과도하게 보수적이면 살릴 수 있는 라운드를 죽인다."),
  consumer_surfaces = c(
    "①팩터 랭킹 — 국면-조건부 가중 근거 없음(확정). 무조건부 IC 는 불변",
    "②유니버스 필터 — 라우팅할 양성 신호 없음",
    "③오버레이/국면 — 원 가설이 겨눈 면. 선별 축은 닫혔고 **배분 축은 미시험**으로 남는다",
    "④위험모델 — 미측정(낙폭 심도의 tail 채널 이식은 별개 축)",
    "⑤monitoring — ★즉시 사용 가능: 심도 계열 7종 전부 PIT 자명해 국면 서술자로 등재 가능",
    "⑥선별 라벨 — ★negative 라벨 확정 등재: '낙폭 기반 국면-조건부 선별은 KR 2003~2026·rank-IC 판정량에서 42구성 전부 검출 불가'",
    "⑦타 모드 — 실행가능 영역 지도 절차를 RAMP·FR 사전등록에 편입"),
  frontier_update = "FQ-180 status=lane_config_closed_20260809 (기록 후 재읽기 확인)",
  live_trigger = paste0("부활 조건(INV-7): ①효과 20%↑ 또는 유효표본 44%↑ 를 주는 표본 확장(2003~2026 밖) ",
    "②판정량을 PORT_t 로 교체 ③합성축 성분 교체로 효과 크기 증대 ④ddvol-연속(그리드 최선 0.833)을 새 데이터 위 첫 사전등록. ",
    "★닫힘은 **이 config·이 판정량 한정**이며 방향의 판결이 아니다 — 42셀 대다수가 사전등록 부호와 일치했다."),
  layer = "①재료/선별 + 측정무결성",
  evidence_refs = c("stage_artifacts/FQ180/validation.json", "stage_artifacts/FQ180/feasibility_grid.csv",
                    "stage_artifacts/FQ178/validation.json", "stage_artifacts/FQ176/validation.json",
                    "stage_artifacts/crisis_contrarian/validation.json"))
say("=== FQ-180 종결 ===")
