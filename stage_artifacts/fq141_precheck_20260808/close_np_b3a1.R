source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NPB3A1_20260808_AXIS_MERGE",
  verdict_type = "capability_established",
  layer = "8_위험모델감시",
  mechanism_diagnosis = paste(
    "감시 통합 가능성을 사전 규칙(|cor|>=0.7 통합 · <0.4 별도)으로 판정했다.",
    "cor(d, size_eff) = -0.847 월별 · -0.803 6m 롤링, 시대별 안정(2010-16 -0.873 · 2017-26 -0.834) ⇒ 벤치 핸디캡 d 와 사이즈 효과(소형-대형)는 부호만 반대인 동일 축이다. 기전상 정합 — d 는 큰 게 작은 걸 이길 때 커지고 그것이 사이즈 효과의 음수다.",
    "★그러나 cor(d, band) = +0.069(6m +0.062) · cor(size_eff, band) = -0.201/-0.345 ⇒ 111-145 밴드는 별개 축이다.",
    "★자기 정정: 한 시간 전 발행한 qepm/observability/bench_handicap_watch_latest.json 이 '이 감시가 4개 게이트를 제어한다'고 기재했으나 밴드는 커버되지 않는다. 통제 게이트를 3 으로 줄이고 밴드를 gates_NOT_controlled 로 이동했다.",
    "= 발행 직후 검증이 미검 주장 1건을 잡아낸 사례. 오늘 세션의 '자동/즉석 주장도 검증 대상' 계통과 동일.",
    "한계: size_eff 계열은 rk>300 요건상 2010-01 부터만 산출 가능(199개월). 1990~2009 구간의 축 동일성은 미검."),
  next_probes = c(
    "NP-b3a1a 밴드 전용 관측면 설계 — 111-145 가 별개 축이므로 자체 트리거가 필요하다. 단 NP-b2b3a 가 '2017+ 휴면'으로 판정했으므로 우선 재활성 조건(무엇이 관측되면 되살아나는가)을 정의해야 관측면이 성립한다. 조건 없이 계열만 찍는 것은 소비자 없는 관측",
    "NP-b3a1b 1990~2009 구간 축 동일성 — size_eff 를 극단 버킷(rk>300)이 아니라 상대 분위(상위/하위 10%)로 재정의하면 전 구간 산출이 가능하다. 동일성이 전 구간에서 유지되는지 확인해야 통합이 시대-국소가 아님을 보장",
    "NP-b3a1c 통합의 실무 귀결 — d 와 size_eff 가 같은 축이면 '사이즈 노출 조절'과 '핸디캡 대기'는 같은 결정이다. 두 언어로 나뉘어 있던 논의(구성 vs 타이밍)를 하나로 합쳐 서술할지 판단"),
  consumer_surfaces = c("monitoring", "선별라벨", "위험모델", "팩터랭킹"),
  frontier_update = "감시 축 통합 판정(d ≡ -size_eff, |cor| 0.85) · watch 파일 통제 게이트 4->3 자기정정 · 밴드는 별도 축 확정 · NP-b3a1a/b/c 신규",
  live_trigger = "bench_handicap_watch 가 NORMALIZED 로 전환되면 사이즈 효과 부호 복귀도 동시 성립으로 읽어도 된다(동일 축) — 단 밴드 재활성은 별도 확인 필요",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_b3a1_axis_merge.R",
                    "qepm/observability/bench_handicap_watch_latest.json")
)
cat("[close_np_b3a1] RC_OK\n")
