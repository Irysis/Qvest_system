source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NPB3A1B_20260808_AXIS_MERGE_FULLRANGE",
  verdict_type = "capability_established",
  layer = "8_위험모델감시",
  mechanism_diagnosis = paste(
    "직전 라운드의 축 통합(d = -size_eff)은 199개월(2010+) 근거였다. rk>300 절대순위 요건 때문이다. 상대분위 정의로 재산출해 439개월 전 구간에서 검증했다.",
    "cor(d, size_rel) 전 구간 -0.747 · 시대별 1990-99 -0.812 / 2000-09 -0.725 / 2010-16 -0.764 / 2017-26 -0.711 — 네 시대 전부 사전규칙 문턱(|cor|>=0.7) 통과. 통합은 시대-국소가 아니다.",
    "정의 정합: cor(size_rel, size_abs) = +0.909 (겹침 199개월) — 두 정의가 같은 것을 잰다.",
    "상대분위가 일관되게 약간 낮다(-0.747 vs 절대순위 -0.847). 절대순위(rk>300)가 극단 꼬리를 잡아 d 와 더 붙는 반면 상대분위(하위10%)는 유니버스가 작던 시절 덜 극단적인 종목까지 포함한다. 통합 판정은 동일하되 감시 민감도는 절대순위 쪽이 높다.",
    "★기전이 명확하므로 우연의 일치가 아니다 — d 는 시총가중이 동일가중을 이기는 정도이고 사이즈 효과는 그 반대편을 재므로 정의상 겹친다. 439개월 4시대 일관성이 이를 확인한다.",
    "⇒ 오늘 나눠 논의해온 '구성(사이즈 노출)'과 '타이밍(핸디캡 대기)'은 하나의 결정이며, MID/OTHER 라운드 재개 시점은 감시 하나로 결정된다."),
  next_probes = c(
    "NP-b3a1b1 감시 정의 선택 — 통합이 확인됐으므로 watch 가 어떤 size 정의를 병기할지 결정. 절대순위가 민감(cor -0.847)하나 유니버스 크기 변화에 노출되고, 상대분위는 안정하나 둔감(-0.747). 감시 목적(조기 발화 vs 오발 억제)에 따라 갈린다",
    "NP-b3a1b2 통합의 서술 반영 — layer_bottleneck_map 의 ⑤비중(사이즈 노출)과 ④construction(핸디캡) 행이 같은 축을 따로 서술하고 있다면 통합해 기술. 지도가 자율 라운드 선택 근거이므로 축 중복은 우선순위를 왜곡한다",
    "NP-b3a1a 이월 — 111-145 밴드는 별개 축(cor 0.07)이므로 자체 재활성 조건 정의가 선행돼야 관측면이 성립한다"),
  consumer_surfaces = c("monitoring", "위험모델", "선별라벨", "팩터랭킹"),
  frontier_update = "축 통합 전 구간 검증 통과(4시대 |cor| 0.711~0.812) · 정의 정합 0.909 · watch 에 근거 추가 · NP-b3a1b1/b2 신규",
  live_trigger = "감시 NORMALIZED 전환 = 사이즈 효과 부호 복귀와 동일 사건(전 구간 확인) — MID/OTHER 라운드 재개 트리거로 단일 사용 가능",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_b3a1b_fullrange.R",
                    "qepm/observability/bench_handicap_watch_latest.json")
)
cat("[close_np_b3a1b] RC_OK\n")
