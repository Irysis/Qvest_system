source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ068A1A_20260808_FMB_RETRACTS_POOLED_T",
  verdict_type = "config_scoped_negative",
  layer = "1_재료",
  mechanism_diagnosis = paste(
    "★직전 라운드(FQ-068a1)의 '반도체 내 PPI-민감도 음의 기울기 유의(pooled t -2.35)' 를 **철회한다**.",
    "Fama-MacBeth(월별 횡단면 회귀 → 계수 시계열 NW lag3 t)로 재추정: 최소 5종목 **t -1.51**(163개월) · 최소 8종목 **t -1.91**(124개월) · 사이즈(log Size) 통제 후 **t -1.90**(124개월). 전부 문턱 2.0 미달.",
    "⇒ pooled OLS 의 t -2.35 는 **횡단면 상관 미보정으로 부풀려진 값**이었다. 직전 라운드에서 '클러스터 SE 미보정' 단서를 달아둔 바로 그 경우가 실현됐다.",
    "★FQ-068 아크 종합(4설계): R1 섹터타이밍 INCONCLUSIVE(설계 원리적 불가·271년 필요) / R2 전표본 횡단면 NEGATIVE_POWERED(IC 0.04 면 기대 t 3.40 인데 관측 -0.0112) / R2a 하위군분할 INCONCLUSIVE 3/3 / R2a1 전표본 상호작용은 군차이 미확립(F p 0.129) + 단일 기울기도 FMB 에서 소멸.",
    "⇒ **미국 반도체 PPI 는 이 형태들(민감도 x 모멘텀 부호)로 KR 반도체 횡단면에 자본급 정보를 주지 않는다.** 검정력이 충분했던 유일 설계(R2)가 음성이었고 나머지는 미확립이거나 보정에서 소멸했다.",
    "★기전 진단(재료 한계의 소재지): PPI 발표지연 중앙 43일·최대 105일인데 현물 DRAM 가격은 매일 공개된다. PIT-안전 형태의 PPI 는 **구조적으로 낡은 정보**이며, 한계는 데이터 품질이 아니라 **발표 지연 구조**에 있다.",
    "★방법론 부수 확립: pooled OLS 는 이 패널 형태에서 t 를 과대 산출한다(-2.35 vs FMB -1.90). 횡단면 회귀 결과는 FMB 또는 이중 클러스터로만 보고할 것."),
  next_probes = c(
    "FQ-068a1b 발표지연 우회 재료 — 기전이 '지연' 을 지목했으므로 답은 신선한 원천이다. 관세청 반도체 수출 통계(월간·지연 짧음, 2026-08-02 에 API 200 및 1.36M행 수집 전례) · DXI 지수 · TSMC 월매출. 같은 기전을 신선한 재료로 재시험하며, 재료 교체는 분할이 아니라 전표본 검정력을 유지한다",
    "FQ-068c 소비면 전환(이월) — 랭킹 음성/미확립이면 exclusion 면이 남는다('랭킹 死 → 필터 生' 실증 전례). 'PPI 하락 국면 고민감도 종목 제외' 는 전표본을 쓰므로 검정력 유지",
    "FQ-069 BSI 업종별(대체 lane) — 반도체 PPI 아크가 재료 한계를 지목했으므로, 같은 sector-tilt 축의 다른 재료로 넘어가는 선택지. ECOS 512Y, 게이트 없음"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "위험모델", "타모드이식"),
  frontier_update = "FQ-068a1 의 pooled t 철회(FMB -1.90) · FQ-068 아크 4설계 전부 자본급 신호 없음 · 기전 = 발표지연 구조 · 방법론: 횡단면 회귀는 FMB/이중클러스터로만 보고 · FQ-068a1b/FQ-069 로 분기",
  live_trigger = "FQ-068a1b 에서 신선한 원천(관세청 수출 등)이 같은 기전으로 유의하면 '지연이 한계였다' 가 확증되고, 미달이면 기전 자체가 KR 횡단면에 없다는 뜻",
  evidence_refs = c("stage_artifacts/fq068_precheck/np_fq068a1a.R",
                    "stage_artifacts/fq068_precheck/np_fq068a1.R")
)
cat("[close_fq068a1a] RC_OK\n")
