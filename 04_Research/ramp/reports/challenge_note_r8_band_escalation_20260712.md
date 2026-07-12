# Self-Adversarial Challenge — RAMP R8: EW-basis oos band escalation 보강증거 3종 (FQ-016)

- **작성**: 2026-07-12 Q-Lead (RAMP orchestrator, Opus 4.8 native adversarial round — v8.2 Codex Round 대체, AX-008 3-source 중 1)
- **대상 산출**: `outputs/ramp/r8_band_escalation_{prereg,,evidence}_20260712.*` · `r8_placebo_null_20260712.parquet` · runner `02_Infrastructure/ramp/run_ramp_r8_band_escalation.R` · L-code(적립 예정)
- **사전등록**: `r8_band_escalation_prereg_20260712.json` (config_hash `c6986525de94c3f6`, 측정 전 sha256 동결). record_type = **판정 절차 보완**(re-sweep 아님, n_trials R7 family=20 불변)
- **parity 무오염 실증**: 후보 시계열 = R7 `.cache/_ramp_r7_20260712.rds` PR[[capwrepro_W36_K20]] (=R6 Ppure_W36_K20). R7 stored E2 대비 EWuni Δ=0·ew_oos Δ=0·cap-w_t Δ=0·cap-w_oos Δ=0. e2 real 재스크린 EW PORT_t=3.9191 = cache 3.9191 (Δ=0.000) — 재구성 파이프라인 bit-consistent.

## 핵심 판정 (사전등록 그대로)
- **EW-oos = 0.5064 ∈ [0.5, 0.7) → band escalation ELIGIBLE**. R7이 0.7 단일 문턱으로 미적용한 §3 절차를 실행.
- **보강증거 2/3 → band_escalated (조건부 PASS)**:
  - **e1 trailing PORT_t>0 = TRUE**: EW-active 3분할 last-third IRf=0.6343>0 ∧ nwt=1.4647>0 (thirds 4.20/1.72/1.46).
  - **e2 placebo p<0.05 = TRUE**: 월-셔플 60회, real EW PORT_t=3.919 vs null mean=−2.379(sd 0.783, max −1.141), **p(null≥real)=0.0000**.
  - **e3 book-marginal = FALSE**: marginal ΔIR(w=0.05)=−0.0052(<0) ∧ cap-w active-cor=0.324(≥0.30). 둘 다 미충족.
- **자본 게이트(cap-w authoritative) = FAIL 불변**: PORT_t 2.61<2.95 · oos −0.08<0.7 · calmar 0.45<0.64 (3/3 HARD FAIL).
- **VERDICT**: EW-basis 조건부 band-PASS = **D3형(벤치-상대 배포성) 도훈 결정 재료 자격 회복** — **자본 게이트 통과 아님**.

## 스스로 제기한 약점 (≥3) — ACCEPT / PARTIAL / REBUTTAL

### W1. "e3 후보↔book 월-정합 불완전(KOSPI cor 0.9377<0.98)이 e3=FALSE를 무효화" **[PARTIAL]**
- 제기: offset −2에서도 KOSPI-KOSPI fingerprint cor 0.94(월말 vs 첫거래일 수익창 불일치) — cor 0.324/ΔIR −0.005가 정합 노이즈 산물일 수 있다.
- 검증: (a) e3는 **두 조건 모두** 미충족 — ΔIR(=ΔSR>0 조건)은 후보 **실net을 실book에 블렌드**한 값이라 basis/정합에 robust(w=0.05/0.10/0.20 전부 음: −0.005/−0.014/−0.045). (b) cor를 정합-무관에 가까운 EW-active로 잡으면 −0.13(탈상관 통과)이나 **ΔIR가 여전히 음** → cor basis 선택 무관하게 e3 FAIL. (c) e3는 **비-dispositive** — escalation은 e1+e2(book 무관)로 이미 2/3. → 정합 caveat는 실재하나 판정 뒤집지 못함.
- 분류 **PARTIAL**: 정합 caveat ACCEPT(보고 병기) + e3 FAIL은 ΔIR<0로 robust·비-dispositive REBUT.

### W2. "e2 placebo null이 강한 음(−2.38)인 건 universe mismatch 기계적 산물" **[REBUTTAL]**
- 제기: 월-셔플은 source-월 종목을 target-월 수익에 붙여 universe가 어긋남 → 기계적으로 PORT_t를 깎았을 뿐, 신호 실재의 증거가 아니다.
- 검증: universe mismatch가 null을 깎았다 해도 **real(정합) +3.92는 null 분포 전체(max −1.14) 밖** — 정합된 신호만이 알파를 내고 어떤 무작위-월 신호도 근접 못 함. p=0/60. 이는 "신호(팩터 횡단정합)가 실재하는가"의 정확한 null이며 강한 확증. mismatch는 있으면 오히려 **보수(하방)** 방향 → real 지배는 더 견고. KR 대형/중형 지수멤버 지속성 높아 target-월 universe 교집합 충분(top-25 pickable).
- 분류 **REBUTTAL**: 신호 실재 강확증. **단 정직 scope**: e2는 EW-active 신호가 spurious 아님을 입증하지, cap-w 배포성을 입증하지 않는다(band-evidence 정확 해석).

### W3. "진단 basis(EW)에 §3 escalation 적용→'PASS'는 cap-w 자본 게이트 우회" **[REBUTTAL]**
- 제기: authoritative oos용 escalation을 EW 진단 oos에 적용해 pass로 포장하면 cap-w HARD FAIL 우회 유인.
- 검증: 3중 방벽 — (a) cap-w authoritative 자본 게이트 3/3 HARD FAIL(2.61/−0.08/0.45) 명시·불변 보고. (b) band_escalated 결과는 **D3형(벤치-상대 배포성 결정 재료)** 라벨 — 자본 아님(v8.3 M2 EW=진단 basis 정합). (c) VERDICT 첫 줄 "자본 게이트 통과 아님" 명기. 어떤 경로로도 자본 편입 없음. escalation은 R7이 건너뛴 절차의 **진단-basis 완결**이지 자본 승격 아님.
- 분류 **REBUTTAL**: D3≠졸업 + cap-w FAIL 불변 + 첫줄 명시. 우회 프레임 성립 안 함.

### W4. "문턱/후보를 결과에 맞춰 조정(자기합리화)" **[기각]**
- 제기: band [0.5,0.7)·2/3·e1(last3>0)·e2(p<.05)·e3(ΔIR>0∧|cor|<.30)를 사후 맞췄을 수 있다.
- 검증: 전부 measurement-graduation §3 / essence_score.R(267-287행) / v3verify(run_ramp_shumulvey_v3verify.R 29-31행) 기성 컨벤션 — prereg(config_hash c6986525de94c3f6) 측정 전 sha256 동결. 후보 시계열 R7 bit-identical(Δ=0 4종). **re-sweep 아님**(n_trials family=20 불변, escalation=판정 절차). e2 seed=1000+d 결정적(재현).
- 분류 **기각**: 사전동결·bit-identical·비-sweep.

### W5. "D3형 재료가 cap-tier 국소화(OTHER 90.6%) 때문에 실행 불가능하면 무의미" **[PARTIAL ACCEPT]**
- 제기: EW-real 알파는 벤치 저비중 소형지수 tier에 국소화(R7 실측) — D3-material이라도 현 cap-w book엔 못 담는다.
- 검증: 정확한 scope 확정 — e1+e2는 **EW-basis 신호가 실재**함을 입증(placebo p=0), 그러나 e3(book-marginal) FAIL + cap-w FAIL은 **현 cap-w book으로 추출 불가**를 입증. D3-material = "EW/소형 유니버스 대비 벤치라면 실재하는 escalation-급 알파 = 도훈 결정 입력"이지 "현 book 실행 가능"이 아님. 메타: band escalation이 **신호 실재는 확증하면서 동시에 cap-w 추출 불가(국소화 벽)도 확증** — 두 결론이 상충 아니라 정합(project-captier-alpha-localization).
- 분류 **PARTIAL ACCEPT**: D3-material은 국소화 caveat 하의 결정 입력. book-actionable 아님 — 보고 명시.

### W6. "e1 trailing이 last3 PORT_t=1.46(sub-2 비유의)로 technicality PASS" **[ACCEPT caveat]**
- 제기: 기준이 '>0'이라 통과하나 trailing 신호가 4.20→1.72→1.46로 **감쇠** — 약한 pass.
- 검증: §3 e1 기준은 명시적 '>0'(졸업의 >2.95보다 낮은 바 = band는 낮은 문턱). 규칙 자체 기준으로 PASS(0.634>0·1.465>0). **단 감쇠 프로파일은 정직 caveat** — EW-active 알파도 시간에 따라 약화(post-2017 감쇠 정합). 보고 병기.
- 분류 **ACCEPT caveat**: 규칙대로 PASS이나 trailing 약화 명시.

## 자기합리화 detect
- 문턱 이동 없음: band/2·3/e1·e2·e3 전부 §3·essence_score·v3verify 기성 컨벤션, 측정 전 sha256 동결.
- 거짓 성공 점검: band_escalated를 "졸업"으로 승격할 유인 차단 — cap-w 자본 게이트 3/3 FAIL 명시·D3≠자본·첫줄 명시. e3 FAIL 정직 보고(성공 3/3로 위장 안 함).
- 과대 판결 점검: "EW-basis 조건부 PASS"는 **진단 basis + D3 재료**에 한정. cap-w 자본·book-marginal은 FAIL. 신호 실재(e2 p=0)와 추출 불가(e3·cap-w FAIL)를 동시 정직 보고.

## 최종 분류
**PARTIAL ACCEPT** — 2/3 band_escalated 판정은 견고(e1+e2 clean·book 무관, e2 placebo p=0/60 강력, e3 ΔIR<0로 robust FAIL·비-dispositive). 프레임(D3-material, **자본 아님**)은 3중 방벽으로 정직. 적대 라운드가 판정을 뒤집지 못하고 scope를 정밀화: **(a) e3 정합 caveat(비-dispositive); (b) e1 trailing 감쇠(규칙대로 PASS이나 약화); (c) cap-tier 국소화로 D3-material은 결정 입력이지 book-actionable 아님.** 메타 결론: **R7의 EW-real 종결은 절차 미완이었고, R8이 §3 escalation으로 완결 — EW-basis 신호 실재는 조건부 PASS(D3 재료 자격 회복)이나, cap-w 자본 게이트·book-marginal FAIL 불변으로 현 book 추출은 불가**(신호 실재 ∧ 추출 불가 동시 확증 = cap-tier 국소화 벽, project-captier-alpha-localization). 잔존 frontier = 비-수익 원천(FQ-001 DART insider) — return-derived cap-w 추출 벽은 R4~R8 일관.
