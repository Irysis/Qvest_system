source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NPC2C3_20260808_TIER_DRAG_IS_ERA_SPECIFIC",
  verdict_type = "capability_established",
  layer = "4_construction",
  mechanism_diagnosis = paste(
    "R4 mid_universe 실패의 tier-beta 성분을 직접 계량했다(tier EW 수익 - cap-w 유니버스 벤치).",
    "R4 OOS 창(2012-12~2026-06, 163m): MEGA -0.0123(t -0.57) · MID -0.0470(t -1.51) · OTHER -0.0341(t -0.83).",
    "2017+ mega 레짐(115m): MID -0.0488 · OTHER -0.0679. ⇒ MID tier EW 포트는 R4 창에서 연 -4.70% 기계적 drag 를 졌고 R4 자신의 진단(tier-beta 지배)이 정량 뒷받침된다.",
    "★그러나 전 구간 439개월에서는 MID drag = +0.0006 (사실상 0) 이고 2025+ 제외 420개월에서는 +0.0080 이다.",
    "⇒ MID tier 는 구조적으로 불리한 자리가 아니라 2012~2026(특히 2017+) 측정 시대에 불리했다. 알파 좌표 지도에서 MID 구성을 '구조적으로 안 되는 곳'으로 접어둘 근거가 없다.",
    "부수: MEGA drag 는 전 구간 -0.0342(t -2.24)로 유일하게 유의하다 — MEGA 내부에서 시총가중이 이긴다는 NP-157c2c(+0.0556)와 정합(동일가중 MEGA 포트는 cap-w 벤치에 진다).",
    "★한계: drag 의 t 는 -1.51 로 유의하지 않다. 오늘 아크 전반과 동일하게 점추정 진술이다."),
  next_probes = c(
    "NP-c2c3a MID 구성 재도전의 조건 — drag 가 시대 의존이므로 MID 라운드는 '언제 측정하느냐'가 판정을 좌우한다. NP-c5 사전등록 문턱(핸디캡 정상화) 통과 후 R4 mid 변형을 재측정하면 tier-beta 를 걷어낸 신호 실력이 드러난다. 문턱 전 재측정은 같은 시대 오염을 반복",
    "NP-c2c3b 신호 성분 분리 — R4 mid 변형의 cap-w 성과에서 계량된 drag(-0.0470/yr)를 차감했을 때 남는 부분이 baseline momentum(1.277)을 넘는지. 넘으면 신호는 살아있고 벽은 전적으로 tier-beta, 안 넘으면 신호도 부족",
    "NP-c2c3c OTHER tier 의 2017+ drag(-0.0679)가 MID(-0.0488)보다 큰 이유 — 이 저장소 전략 대부분이 OTHER 에 사는데 그 tier 의 시대 drag 가 더 크다. 기존 기각들의 기계적 성분이 R4 보다 클 가능성"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "타모드이식", "monitoring"),
  frontier_update = "R4 mid 실패의 기계적 성분 계량(-4.70%/yr) · MID drag 는 시대 의존(전 구간 +0.0006) = 구조적 불리 아님 · MEGA drag 유일 유의(-0.0342 t -2.24) · NP-c2c3a/b/c 신규",
  live_trigger = "NP-c5 핸디캡 정상화 문턱 통과 시 MID/OTHER 구성 라운드 재개 — 그 전 재측정은 같은 시대 오염 반복",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_c2c3_tier_drag.R",
                    "stage_artifacts/fq141_precheck_20260808/np157c2c_tier_d.csv",
                    "04_Research/method_frontier/wt006_exog_forecast/R4_synthesis.json")
)
cat("[close_np_c2c3] RC_OK\n")
