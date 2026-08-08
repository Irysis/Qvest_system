source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                 "02_Infrastructure/contracts/close_round.R"))

close_round(
  round_id = "R-ERAAWARE-20260808",
  verdict_type = "config_scoped_negative",

  mechanism_diagnosis = paste0(
    "계약 rds 재도출 3안(전기간 live / era-aware / 현행 유지)을 전부 실측한 결과 ",
    "**어느 안도 현행 Calmar 1.899 를 넘지 못한다**(전기간 1.761 · era-aware cut 2013~2019 전부 1.859~1.870). ",
    "기전이 명확하다: MDD 가 어느 경계에서도 23.29% 로 고정인데, 이는 **최대낙폭 사건이 2013년 이전**이라 ",
    "live-z 교체 구간 밖이기 때문이다. 반면 live 는 발화가 잦아(107 vs 73) CAGR 을 44.23%→43.3%대로 깎는다. ",
    "⇒ SR 은 7/7 경계에서 강건하게 개선(+0.026~+0.042)되지만 Calmar 는 전부 하락한다. ",
    "★일반화 가능한 교훈: **부분구간(2016+ MDD −2.42%pt) 우위가 전기간 지표로 전이되지 않는다** — ",
    "개선이 헤드라인 위험지표를 만드는 사건 구간 밖에서 발생하면 전체 지표는 오히려 나빠질 수 있다. ",
    "두 안 모두 graduation HARD(Calmar 0.64)는 여유 통과하므로 게이트가 가르는 문제가 아니라 목적함수 선택 문제다."),

  next_probes = c(
    "최대낙폭 사건(2013년 이전)을 특정하고 그 구간에서 live-z 가 무엇을 다르게 했는지 분해 — MDD 가 불변인 이유가 '동일 판정'인지 '판정은 다른데 낙폭이 다른 경로로 같아진 것'인지 갈라야 한다(전자면 진짜 무관, 후자면 우연)",
    "SR 개선 +0.026~+0.042 가 7/7 경계 강건인데 Calmar 로 상쇄되는 구조 — 목적함수를 SR 우선으로 두는 소비면(예: book-marginal ΔIR, admission)에서는 live 가 우위일 수 있으므로 ΔIR 기준으로 재채점",
    "발화 빈도 차이(107 vs 73)가 CAGR 을 깎는 경로 정량화 — 과발화라면 문턱(q20) 재조정으로 SR 이득을 지키면서 CAGR 손실을 줄일 수 있는지(문턱은 지금 두 계열 각자 역사에서 산출)",
    "R05 외 팩터로 동결/live 기준 반전이 일반적인지 — 같은 동결 패널의 다른 팩터에서도 IC 유의성 전환 시점이 있으면 개별 재도출이 아니라 패널 재빌드 문제로 격상"),

  consumer_surfaces = c(
    "계약 rds 앵커(WT-D20260702_002) — 재도출 **불가결정**, 현행 유지",
    "live_book_series.csv beta_matches_ret_net (이음매 162행 명시 — 재도출 안 하므로 이 표시가 상시 방어선)",
    "run_layer5_rerun_extended.R (z 원천 live 유지 — 신규월은 배포와 정합)",
    "book-marginal ΔIR / admission (next_probe ② 대상 — SR 우선 목적함수에서 재채점)",
    "essence_score·hurdle_gate (Calmar 0.64 여유 통과 — 이 결정은 게이트 무관)"),

  frontier_update = paste0(
    "rds 재도출은 config-scoped 미달(3안 전부 현행 Calmar 미만, 경계 7/7 강건). ",
    "미검 축 = ① MDD 불변의 성격(동일 판정 vs 우연 일치) ② SR-우선 목적함수(ΔIR)에서의 재채점 ",
    "③ 문턱 재조정으로 CAGR 손실 완화 가능성. 신호(SR 개선)는 실재하므로 방향 자체가 닫힌 것은 아니다."),

  live_trigger = paste0(
    "다음 중 하나가 발화하면 rds 재도출을 재검토한다: ",
    "① next_probe ② 의 ΔIR 재채점에서 live 가 book-marginal 기준 우위(현 판정은 Calmar 단일 목적함수에 조건부) ",
    "② 문턱 재조정으로 CAGR 손실을 줄여 Calmar 가 현행 1.899 이상 회복 ",
    "③ 2013년 이전 최대낙폭 사건 밖에서 새 낙폭이 발생해 MDD 결정 구간이 live 교체 구간으로 이동 ",
    "④ 신규 admission·PG2 교체로 어차피 incumbent_book_ir 재산출 필요 ",
    "⑤ 동일 기준 반전이 R05 외 팩터에서도 확인(패널 재빌드로 격상)")
)
