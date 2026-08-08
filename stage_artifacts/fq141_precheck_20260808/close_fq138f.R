source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ138F_20260808_POWER_FORCES_DESIGN_REVISION",
  verdict_type = "capability_established",
  layer = "1_재료",
  mechanism_diagnosis = paste(
    "★측정 전 검정력 계산이 사전등록 설계를 바꿨다 — 원 설계는 현실적 효과크기를 검출할 수 없었다.",
    "(SIG−NEU) 스프레드의 월 변동성을 무작위 25종 바스켓 쌍 120 draw 로 실측: 중앙 0.0394 (5~95% 0.0330~0.0448), 창 2019-12~2026-07.",
    "t=2.0 도달 필요 효과: n=28 부분표본 분할 DiD 월 +0.0263 = **연 +31.60%** · n=28 단일 스프레드 연 +22.35% · n=80 전표본 연 +18.70%.",
    "이 저장소 알파들의 실현 active 는 한 자릿수~낮은 두 자릿수이므로 요구치가 한참 위다. ⇒ 원 설계대로 측정하면 거의 확실히 미달이 나오고 그것은 효과 부재가 아니라 무정보다.",
    "★설계 개정: 표본을 28/52 로 쪼개는 대신 전체 80개월 스프레드 계열 s_t = SIG_t − NEU_t 를 국면 더미에 회귀해 delta(=DiD)를 전 표본으로 추정한다. 같은 추정량을 더 높은 검정력으로 얻으며 문턱 2.0 은 불변이다(검정력으로 대응하지 문턱을 낮추지 않는다).",
    "★inconclusive band 사전 고정: delta 의 t 가 미달이고 |delta| 연환산이 required_effect 미만이면 '효과 부재'가 아니라 '검정력 부족'으로 보고한다. 두 결과를 같은 문장으로 쓰지 않는다.",
    "★일반 교훈: 사전등록에 **검정력 계산을 포함하지 않으면 null 이 오독된다**. 오늘 이 라운드는 설계 3회 개정(순풍 통제 → 데이터 핀 → 검정력)을 거쳤고 셋 다 측정 전에 잡혔다."),
  next_probes = c(
    "FQ-138a 본 측정(위임 필요) — 개정된 추정식(전표본 국면 상호작용 회귀) + 위약 셔플 주입 + vintage 감도. 사전등록 완비",
    "FQ-138g 검정력 개선 여지 — 국면을 이진 더미가 아니라 연속값(mega_spread 수준)으로 쓰면 정보 손실이 줄어 유효 표본이 커진다. 단 연속화는 이진 문턱보다 함수형태 가정을 추가하므로 사전등록 시 이진을 primary·연속을 secondary 로 고정",
    "FQ-138h 검정력 계산의 일반화 — 오늘 산출한 '스프레드 월 변동성 0.0394' 는 이 유니버스·25종 구성의 상수에 가깝다. 다른 라운드의 사전등록에도 같은 방식으로 필요 효과크기를 미리 낼 수 있다(사전등록 표준 항목화 후보)"),
  consumer_surfaces = c("팩터랭킹", "오버레이", "선별라벨", "타모드이식"),
  frontier_update = "FQ-138 사전등록 3차 개정(검정력) — 추정 방식 전표본 회귀로 변경 · inconclusive band 사전 고정 · 필요 효과크기 표 기록 · FQ-138g/h 신규",
  live_trigger = "국면 ON 지속 시 표본이 매월 증가해 검정력이 개선된다 — 사전등록 고정 상태이므로 추가분은 clean OOS",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_fq138f_power.R",
                    "stage_artifacts/fq141_precheck_20260808/fq138_preregistration.json")
)
cat("[close_fq138f] RC_OK\n")
