source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ068C_20260808_EXCLUSION_SURFACE_ADVERSE",
  verdict_type = "config_scoped_negative",
  layer = "3_선별",
  mechanism_diagnosis = paste(
    "FQ-068 아크의 마지막 미검 소비면(제외필터)을 측정했다 — 방향이 불리하다.",
    "설계 정직화: 국면 조건부 필터는 또 분할이므로(오늘 3회 검정력 파괴 실증) **무조건 제외**(전 403개월)로 좁혀 검정력을 유지했다. 또한 제외와 랭킹이 같은 점수를 쓰면 독립 검정이 아니므로, MAX5 선례(랭킹 死/필터 生)와 달리 여기서는 꼬리 문턱 제외를 별도 축으로 잡았다.",
    "결과: 고 PPI-베타 상위 10% 제외 → **연 -1.23%**(NW t -1.75) · 상위 20% 제외 → **연 -1.61%**(t -1.56). 제외할수록 악화하며 단조적이다.",
    "대조(저 베타 하위 10% 제외) 연 -0.48%(t -0.90) — 무엇을 빼든 분산 손실로 약간 나빠지지만 **고베타 제외가 2.5배 더 해롭다**.",
    "⇒ 고 ASP-민감도 종목은 평균적으로 **도움이 되는** 쪽이므로 제외 대상이 아니다. 제외필터 소비면에도 값이 없다.",
    "★정직 표기 2건: ① t -1.75 는 문턱 2.0 미달이다 ② 스크립트의 '필요 효과' 는 단순 SE 로 계산했는데 보고 t 는 NW 라 NEGATIVE_POWERED 라벨이 약간 낙관적이다. 정확한 서술 = '방향이 불리하고 문턱 근접, 단조성이 노이즈 아님을 시사'.",
    "★FQ-068 아크 소비면 종합(6라운드): 랭킹 = 검정력 충분한 null(3원천 일관) · 제외필터 = 방향 불리 · 섹터 타이밍 = 설계상 검출 불가 · 하위군 = 표본 부족. **재료를 config-scoped negative 로 정리한다.**"),
  next_probes = c(
    "FQ-068d 고빈도 원천(이월·저순위) — 3원천 모두 지연 39~43일이었다. 주간/일간 원천(DXI·대만 월매출 속보·현물 DRAM)은 여전히 미검이나, 기전 자체가 3원천에서 일관되게 부재했으므로 우선순위는 낮다. 부활 조건 = 다른 재료에서 ASP 사슬이 살아나는 신호",
    "FQ-069 BSI 업종별 착수 — 반도체 ASP 축을 정리했으므로 같은 sector-tilt 계열의 다른 재료로 이동. ECOS 512Y, 게이트 없음, hypothesis_index 미탐색 여부 확인 선행",
    "방법론 이월 — 오늘 아크에서 얻은 절차(전표본 우선·FMB 필수·통화/계열 사전선언·PIT 실측·빈 병합 가드·검정력 병기)를 재료 라운드 표준 체크리스트로 문서화할지 판단"),
  consumer_surfaces = c("선별라벨", "팩터랭킹", "오버레이", "타모드이식"),
  frontier_update = "FQ-068 아크 6라운드 완주 — 랭킹·제외필터·타이밍·하위군 4소비면 전부 값 없음 ⇒ 재료 config-scoped negative 정리 · 고빈도 원천만 미검 잔존 · FQ-069 로 lane 이동",
  live_trigger = "다른 재료에서 ASP→종목선택 사슬이 살아나면 FQ-068d 고빈도 원천 재검토 — 그 전에는 저EV",
  evidence_refs = c("stage_artifacts/fq068_precheck/np_fq068c.R",
                    "stage_artifacts/fq068_precheck/fq068b_prereg.json")
)
cat("[close_fq068c] RC_OK\n")
