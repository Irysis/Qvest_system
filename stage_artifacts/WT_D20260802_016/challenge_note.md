# challenge_note.md — WT-D20260802_016 Self-Adversarial Challenge (v8.2)

finalize 직전 자체 적대검증. 대상 = 복권형 제외-필터 x overlay(M4xR05_V5) 포함판 paired 실측 (사전등록 preregistration.json 고정 후 단일 primary).

## C1. 사전등록 parity STOP 발동 (cor 0.668 < 0.95) [PARTIAL — 기준 설계 오류 인정 + 배선 무결 실증]

- 제기: 사전등록 STOP 조건(overlay-ON 무필터판 vs book ret_L5_V5 cor ≥ 0.95)이 발동했다. 배선 결함이면 전 측정 무효다.
- 처리: PARTIAL — STOP 규정("STOP 후 배선 진단 보고")을 이행했고, 진단 2축이 배선 무결을 실증:
  - **정렬 축**: β-스캔(메모리 mandate "북↔벤치 realized_ym 1개월 지연 — merge 전 β스캔 필수" 이행) — `return_ym+k` 조인이 k=0에서만 cor 0.71 (k=±1: ≤0.10, realized_ym 조인: 0.06). 월 정렬 정확.
  - **exposure 축**: 행-수준 cor(내 e, book 실현 ret_L5_V5/ret_orig) = **0.9996**, max|diff| 0.035, 잔차는 overlay 스위칭 비용 항으로 설명(resid–db_R05_V5 cor −0.81). |e−ratio|>0.05 행 0건.
  - 미달 원인 = 내 기준의 보조가정 오류: book ret_orig는 AR *전략 계층*(월평균 +1.81%p 고수익)이고 내 base는 WT-014가 확립한 *parity 스크린 계층* — 계층이 다른 두 시계열에 identity를 요구한 것. primary(양팔 동일 exposure 하 paired Δ)는 계층 수준 identity에 의존하지 않는다(d_ov = e×d_bare 항등).
- 합리화 자기검증: "기준이 틀렸으니 무시"가 아니라 STOP → 진단 → 실증 → 문서화 경로로 처리. 발동 사실·원인·증거를 validation JSON `overlay_parity_diagnosis`에 전량 기록. No Silent Override 준수.

## C2. primary paired t 1.551 — 통계 확증 보통 [ACCEPT]

- 제기: 닫힘 기준(t<1)은 비발동이나 t 1.55는 자본 근거 수준이 아니다. WT-014 bare(1.565)와 사실상 동일 — overlay를 얹어도 확증 수준이 오르지 않았다.
- 처리: ACCEPT — 헤드라인에 병기. 본 라운드의 질문은 "관문 통과 여부"(닫힘 회피 + ΔIR 기준)였고 그 답만 주장. 자본 주장 0, 실배치 결정 = governor + 도훈 수동.

## C3. 상호작용 t −1.14 — 점추정은 부분 중복 방향 [ACCEPT]

- 제기: overlay가 필터 ΔIR을 0.169→0.128로 −24% 축소. "축이 달라 독립"이라는 사전 가설을 무비판 채택하지 말라.
- 처리: ACCEPT — 실측 그대로 기록: 축소의 산술 주인은 e̅ 0.79 재가중(d_ov=e×d_bare)이고 상호작용은 미유의(t −1.14). MDD 축도 부분 중복 실측: 필터 MDD 편익 11.4pp → overlay 위 7.3pp (36% 흡수, 64% 잔존). "완전 독립"도 "완전 중복"도 아닌 부분 독립이 정직한 결론.

## C4. CRISIS 역효과 부호 잔존 (t −1.59) [ACCEPT]

- 제기: 판별 질문의 답이 "반쪽"이다 — overlay는 CRISIS 역효과의 크기만 61% 흡수(−0.33→−0.13%/월, e̅ 0.38), 부호·t는 남는다. β 축소는 산술상 부호를 못 바꾼다(e>0).
- 처리: ACCEPT — regime_scope에 실측 반영. 국면조건부 필터 해제(CRISIS off)는 사후 선택이라 본 라운드 채택 금지 — next_probe 사전등록 라운드로만.

## C5. exposure 타이밍 변형에 paired Δ가 둔감 (0.121~0.128) [ACCEPT — 해석 제한]

- 제기: leak/lag1 exposure 변형에서 paired Δ가 거의 불변이다. 이는 "타이밍 강건"이지만 뒤집으면 "overlay 타이밍은 필터-Δ 판정에 정보량이 적다"는 뜻 — overlay-ON 판정의 부가정보가 크지 않을 수 있다.
- 처리: ACCEPT — 단 절대 수준(base absSR 0.874 strict vs 0.795 leak vs 0.711 lag1)은 타이밍에 민감하고 strict가 최선 = PIT 방향으로 look-ahead 이득 부재 실증(인플레 −9.0%, clean). 판정 정보의 본체는 국면 재가중(CRISIS e̅ 0.38)이며 이는 실측대로 보고.

## C6. 회전 13.5x/yr — 상한 11.0/yr 초과 [ACCEPT — 귀속 명기]

- 제기: 측정 계층의 연회전이 상한을 넘는다.
- 처리: ACCEPT — 귀속: incumbent parity 스크린 계층의 속성(무필터 13.81, WT-014 동일 실측)이고 필터는 −0.27 감소 방향. 필터가 회전을 늘린다는 증거 없음. overlay β-schedule 회전은 book 계층 별도(양팔 동일, 라벨). 실배치 판단 시 book-계층 회전은 production 실측이 권위.

## C7. 신규 발굴 0 — wt_type=discovery 정합 [ACCEPT — 정직 표기]

- 제기: alpha 신호가 WT-014 상속(cor 1.0)인데 discovery로 위장하면 STR_1715 사고(WT-D20260427_016) 재연이다.
- 처리: ACCEPT — alpha_discovery_count=0 + discovery_of=WT-D20260802_014 명기 + governance_log에 reclassify_note 기록. certificate 미발급이 정상 산출임을 선언.

## 종합

- HIGH severity 0 / PIT C1~C15 hard 위반 0 / AX hard FAIL 0 → escalate 트리거 비발동.
- PIT C5 검증: assert_overlay_pit HARD PASS + **위반 주입(컷오프를 홀딩월 말로 이동) 시 stop() 발화 실증** — 가드 생존 확인. strict-PIT A/B: leak 열세(−9.0%) — look-ahead 인플레 부재.
- 판정 요지: 실배치 관문 통과(닫힘 비발동 + ΔIR 기준 충족 + 편익 76% 보존) / CRISIS 크기 흡수·부호 잔존 / MDD 부분 독립. 자본 주장 없음.
- 합리화 스캔: answer-principles 회피표현 목록 전수 대조 — 미사용 확인.
