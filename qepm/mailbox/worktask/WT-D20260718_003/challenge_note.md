# Self-Adversarial Challenge — WT-D20260718_003 (Alpha)
Transformer/foundation-model asset pricing (KR). Opus 4.8 native adversarial reasoning (v8.2, no external Codex).
finalize 직전 자기 적대검증. pin tag = frozen inputs (XATTN scores Jul-5, kns_ret/liq/bench Jul-3).

## Concern 1 — "EW-uni 2.72 살아있으니 XATTN은 작동한다, 벤치만 틀렸다" 유혹 (합리화 위험)
**제기**: dual-basis에서 cap-w PORT_t 1.31(FAIL)이지만 EW-universe PORT_t = **2.72**, oos-approx **+1.41(양수)**, cap-tier OTHER 86%. 이걸 근거로 "신호는 실재, cap-w 벤치가 mega-cap 아티팩트라 부당하게 죽였다 → 사실상 통과"로 프레이밍하고 싶어진다.
**분류: PARTIAL (부분 인정 + 명시 제한)**.
- 인정: EW-uni 생존 + OTHER 86% + oos-approx 양수는 **순수 노이즈가 아님을 실증** — 소형-tier 횡단면 신호가 실재. M2 dual-basis 의무가 잡으라는 바로 그 신호(mega-cap 벤치 아티팩트 성분).
- 그러나 **판정 반전 근거 아님**: (a) 배포 벤치 = cap-w KOSPI200(incumbent가 그것으로 측정됨) — EW-uni는 `metric_type="canonical_screen_diag"` 비바인딩(계약 명시). (b) OTHER-tier 신호는 **capacity-제약**: liq_min 2e8→5e9서 port_t 1.31→**-0.01** 붕괴(kill ③ 실측). 소형주 신호를 배포 규모로 올리면 소멸. (c) **book-marginal ΔIR +0.008~0.017 << 0.05**(모든 w) — cap-w-벤치 incumbent 북에 실질 기여 없음.
- **처리**: cap-w FAIL 판정 유지(authoritative) + EW-uni/OTHER-tier 사실을 은폐 않고 **screen-route(FR_RCMA / OVERLAY_CANDIDATE)**로 명시 라우팅(silent bury 금지, Charter §8). 근거 인용: measurement-graduation §6 "직교≠수익", v8.3 M2 dual-basis 라벨 의무.

## Concern 2 — orthogonality return-corr 0.297 = 게이트(0.30) 경계 + offset 정렬 노이즈
**제기**: return-level active-corr(XATTN, incumbent) = 0.297로 |cor|<0.30 게이트를 **간발로** 통과. 그러나 offset audit(trim)서 shift-2 corr 0.256 > shift0 0.114 — book(realized_ym) vs XATTN(decision month-end) 1~2개월 정렬 불확실 → 0.297이 정렬 아티팩트로 과대/과소일 수 있음.
**분류: ACCEPT (제한 명시) — 단 판정 무관**.
- 인정: 정렬은 clean-peak-at-0 아님(shift-2가 국소 최대). 1개월 오프셋 가능성 존재.
- 그러나 **verdict-change 없음**: 어느 offset에서도 XATTN active IR≈0(net_SR 0.35, active IR ~0)이라 blend ΔIR은 **정렬 무관하게** <0.05에 머문다(약한 sleeve가 지배). 즉 orthogonality의 borderline pass(0.297) 여부는 무의미 — **약한-직교 sleeve는 북 기여 없음**이 핵심. 직교성 게이트 통과해도 ΔIR 게이트에서 탈락.
- 처리: 직교성 결론을 "cor≈0.30 borderline, 단 sleeve 자체가 약해 ΔIR<0.05로 무력"으로 정직 기록(단일 cor 숫자로 '직교 통과' 광고 금지).

## Concern 3 — 점수-레벨 E2E 중복(0.62) = XATTN이 신규 정보 아님
**제기**: cross-sectional score rank-corr XATTN vs E2E = **+0.621 > 0.5**(kill ① 문턱). XATTN과 E2E 둘 다 direct-net-Sharpe 손실 → 사실상 같은 목적함수의 아키텍처 변주. "새 아키텍처(횡단 attention)"의 정보 증분이 estimator 대비 크지 않음.
**분류: ACCEPT**.
- XATTN은 KNS(0.48)·특히 E2E(0.62)와 점수 중복 高, IPCA(0.12)에만 직교. **6방법에 직교 신호를 더한다는 각도②의 전제 자체가 score-레벨에서 부분 반증**(E2E와 redundant). 이는 "벽=방법론 아닌 KR 구조"(6방법 공통)의 재확인 — 아키텍처를 바꿔도 같은 direct-Sharpe 신호를 재발견.
- 처리: kill ① 부분 발화(vs E2E)로 명시. "novel 아키텍처가 직교 신호 원천"이라는 강한 주장 기각.

## Concern 4 — angle ①(FM) 조기 포기 = AX-000 위반 아닌가
**제기**: foundation model 각도를 "libs missing + download 승인게이트"만으로 접었다. 3~4 시도로 dead 단정 금지(AX-000). 정말 소진했나?
**분류: REBUTTAL (근거 제시)**.
- FM 각도는 **falsified 아님 = feasibility-blocked**. (a) transformers/timesfm/chronos/huggingface_hub 全 MISSING → 대량 다운로드 필요(승인 게이트, 지시 명시 "승인 없이 대량 다운로드 금지"). (b) 외부 회의 문헌(Karaouli 2025 arxiv 2510.00742: zero-shot=pretraining-도메인 종속 / "When Directional Accuracy Lies": LoRA-TimesFM base-rate 착시) = KR 월간 횡단면에 낮은 prior. (c) 지시 자체가 "불가/고비용 시 각도②로 pivot" 승인.
- **AX-000 준수 증거**: FM을 dead로 묻지 않고 **capacity-gated FQ(HF 다운로드 승인 시 부활)**로 등재 + 경량 zero-shot 설계(incumbent-잔차 orthogonal-info 프레이밍)를 next_probe로 보존. 탐색 계속(중단 아님) — 도훈 승인/자원 게이트만 대기.

## Self-rationalization auto-detection (measurement-graduation §3)
"미미/관행/실무/보수적이면 OK/대부분 동일" 미사용 확인. "borderline"·"부분"은 정량 수치(0.297/0.62/ΔIR 0.017) 동반 — 라벨 명시. RE-VIEW 불요.

## Escalation 판정
HIGH severity concern < 5, AX axiom hard FAIL 0, PIT C1 위반 없음(PIT rolling 96mo IS, 이전 WT-D20260705_001 judge REBUTTAL로 look-ahead 부재 확인) → Q-Lead auto-escalate 미발동. 정상 종결(screen-tier NEGATIVE + FQ 라우팅).
