# FQ-062 Challenge Note — Self-Adversarial (Opus 4.8 native)

**라운드**: lw_nls-clean detoned 잔차-crowding (risk_monitoring lane, method_frontier)
**verdict**: KILL_lw_nls_incidental · metric_type = spectral_diagnostic
**pin_tag**: fq062_20260719_130727 · n_windows 201 (2009-10..2026-06) · p 180-318 · n=60 (p>n)

falsification-first 라운드의 verdict를 스스로 적대적으로 검증한다. 자본/성과 주장 없음(위험-축 진단) — 적대검증의 초점은 "KILL이 성급하거나 아티팩트에 기댄 판정인가"이다.

---

## 자기비평 (devil's advocate) ≥3

### C1. "상관 축에서 mfix pearson 0.53 = 유의 발산인데, 규칙상 DIVERGENT_pursue여야 하는 것 아닌가? KILL은 발산을 explain-away한 것 아닌가?" — **분류: PARTIAL**
- **인정**: 리터럴하게 자동 규칙(near-identical = cor>0.95)만 보면 상관 mfix 0.53<0.95 → DIVERGENT로 읽힌다. 나는 basis-split(공분산 near-identical vs 상관 발산)을 기전으로 해소해 KILL로 판정했다 — 이건 자동 임계가 아니라 JUDGMENT다. 투명 병기 의무.
- **반론(REBUTTAL 축, 3근거)**:
  1. **학술**: FQ-062 가설의 명제어는 "잔차 dispersion 보존"이다. Dispersion 보존은 공분산-고유값 성질이고, lw_nls(Ledoit-Wolf 2020)는 표본 공분산 **고유벡터를 정확히 보존**(Sig=U diag(dtilde) U')한다. 따라서 이 명제의 **충실한 테스트 축은 공분산**이며, 거기서 PC1-AR pearson 1.000(완전 동일)·잔차 mfix 0.958(near-identical)로 **가설 기전이 반증**된다. 상관 축은 cov2cor가 고유벡터를 회전시킨 **다른 객체**다.
  2. **정량**: 대각통제 probe(run_02b) — lw_nls 상관을 sample-vol로 재스케일하면 발산이 0.53→0.64로 이동. 즉 상관-발산은 (a) lw_nls-vol 대각(~0.11) + (b) cov2cor 잔차-부분공간 회전의 합성이며, 어느 성분도 "off-diagonal co-movement dispersion 보존"이 아니다. 공분산에서 near-identical이라는 사실이 이를 확정한다(같은 잔차 concentration이 cov2cor 후에만 갈림 = 순수 normalization 효과).
  3. **일반성(L-code 정합)**: 상관-발산은 lw_nls 특이성이 아니다 — **어떤** 공분산 수축 추정기든 cov2cor에서 sample과 갈린다(수축→대각 이질화→정규화 회전). lw_nls의 "비선형 dispersion 보존"이 그 발산의 원인이라는 증거는 없다. 따라서 lw_nls를 특권적 후보로 세운 근거가 소멸.
- **처리**: verdict를 KILL로 두되 limitations에 "리터럴 DIVERGENT 판독 가능성"을 명시(완료). 상관-발산은 **별개 후보(목적-빌드 잔차-상관 denoiser)** 의 followup으로 리다이렉트 — lw_nls 부활 아님. → PARTIAL 인정 + 판정 유지.

### C2. "RMT no-op을 근거로 전제를 반증했는데, 이건 .rmt_denoise 구현의 한계일 뿐 RMT 개념의 반증이 아니다. p>n용 올바른 RMT(bulk-clip)는 flatten할 것이고 그러면 lw_nls가 그 대비 우위일 수 있다." — **분류: PARTIAL**
- **인정**: 정당한 지적. FQ-062가 baseline으로 명시한 코드는 `.rmt_denoise`(hrp_core.R:67)이고 그건 q<1에서 no-op이 맞다(201/201 실측). 하지만 "RMT 개념 일반"은 p>n에서도 bulk를 clip하는 변형(예: eigenvalue > λ_plus만 유지, 나머지 평균)이 가능하다 — 그건 미측정.
- **반론**: 그러나 (i) FQ-062의 wall_check ③은 **`.rmt_denoise` 대비** A/B를 명시했고 그 baseline은 no-op이다. (ii) 더 중요한 건 C1의 공분산-축 near-identical — 이건 RMT를 아예 경유하지 않고 **sample 대비 직접** lw_nls가 incidental임을 보인다. 즉 "올바른 RMT가 flatten할 것"이 사실이어도, lw_nls의 detoned 잔차 concentration이 **plain sample**과 near-identical이므로 lw_nls의 순 가치(=RMT가 버리는 걸 lw_nls가 살린다)는 성립 못 한다. RMT 변형 논쟁과 무관하게 lw_nls≈sample.
- **처리**: next_probes에 "올바른 p>n RMT/목적-빌드 denoiser" 각도를 P1으로 등재(완료) — 단 그건 **RMT/denoiser 후보의 몫**이지 lw_nls 부활이 아니다. → PARTIAL 인정 + lw_nls-KILL 유지.

### C3. "월간 60m 단일 측정틀. 일간·다른 윈도·다른 잔차 지표(top-k 변화, tail-conditional)에서 lw_nls가 갈릴 수 있는데 1틀로 KILL은 AX-000 위반(조기 단정)." — **분류: REBUTTAL(부분 인정)**
- **반론(3축)**:
  1. **구조적 이유**: lw_nls의 고유벡터 정확 보존은 윈도·cadence와 무관한 **대수적 성질**이다. 공분산 detoned 잔차 concentration이 near-identical인 건 "비선형 수축이 고유값을 부드럽게 재배열하나 고유벡터·잔차 부분공간은 sample과 공유"하기 때문 — 이건 일간/다른 윈도서도 이식될 구조. next_probes P2에 값싼 일간 재현을 명시했으나 결론 이식 예상.
  2. **AX-000 정합**: KILL은 **lw_nls-특이 가설**의 반증이지 "detoned 잔차-crowding monitoring 아이디어"의 사망 선고가 아니다. 아이디어는 P1(목적-빌드 denoiser)·P3(신용/대차 crowding=FQ-005)로 **살아서 리다이렉트**된다. 탐색 계속(next_probes 3건·followup 조건 명시).
  3. **부활 조건 명시**: "tail-conditional 잔차 스펙트럼(극단국면 조건부)"을 lw_nls 재검토의 유일 부활 신호로 사전등록(revival_or_followup_conditions) — 새 측정틀이 나오면 시스템이 먼저 깨움(INV-7).
- **처리**: 일간 재현을 저비용 후속으로 남기되(P2), 구조적 이식성 근거로 본 라운드 KILL을 확정. → REBUTTAL + 부활조건 사전등록.

### C4 (추가). "PIT/vintage 무결성은?" — **분류: ACCEPT-clean**
- 상관/공분산은 trailing 60m rolling만(C1). 멤버십·size는 window-end 스냅샷(PIT, forward 정보 없음). 유동성 필터는 미적용(진단 대상이 tradeable 포트가 아닌 지수-멤버 스펙트럼 — 편향 없음, C10 무관). RAWDATA는 fq062_20260719_130727로 pin(§7), 파생 산출 전체에 pin_tag 기록. fdb_daily 미접근(rawdata 일간 직접). → 무결성 이슈 없음.

---

## Self-rationalization auto-detection
"미미/관행적/보수적이면 OK/유사/거의" 등 회피표현 스캔 — verdict·mechanism에서 정량 근거(pearson 1.000/0.958/0.53·대각통제 0.53→0.64·201/201 no-op) 없이 결론 내린 곳 없음. basis-split JUDGMENT는 "explain-away"가 아니라 **가설 명제어(dispersion 보존)의 충실한 축 선택**으로 정당화 — C1 REBUTTAL 3근거로 방어. 상관-발산의 "정보성 없음"은 **미증명으로 정직 라벨**(limitations #4), "different≠uninformative" 명시.

## Q-Lead escalate trigger 점검
- Σ PD violation: 해당 없음(진단 라운드, weight/Σ 소비 없음). HIGH≥5/AX hard FAIL≥3/PIT hard violation: 없음. → escalate 불요.

## 결론
KILL_lw_nls_incidental 유지. PARTIAL 인정 2건(C1 리터럴 판독 병기·C2 올바른-RMT 각도)은 **별개 후보 followup**으로 흡수되며 lw_nls 특이 가설의 반증을 뒤집지 않음. C3는 구조적 이식성으로 rebut + 부활조건 사전등록. 정직 라벨: 상관-발산은 실재하나 lw_nls 특이 기전이 아니며 정보성 미입증.
