# 유기적 강화 설계 — 최종판 (organic_design_final)

- 작성: 2026-09-25 16~18시 KST. 통합 설계서(v1, 17:12)에 헌법 비평(수정 필수 13 · 권고 14)과 완결성 비평(수정 필수 13 · 권고 14)을 반영했다.
- 성격: **읽기 전용 설계**다. 운영 트리·원장·레지스트리·기억 쓰기 0 · R 실행 0 · 텔레그램 0 · 커밋 0. python 과 grep 은 원장·설정·결정 레지스터 JSON 기술 집계와 코드 판독에만 썼다(결정 수치 아님).
- 동시 진행 중이라 건드리지 않은 것: C11 2단계 S9 검증 스위트 · 잔여 수리 워크플로(`rf_runner_gates.R`·`rf_factor_arms.R`·`rf_sleeve.R`·`arm_gen_read_guard`·`safety_guard`·`run_paper_replication.R` 스테이징). 이 설계의 편집은 그 배포 **뒤**에 병합한다(§8.0).
- 표기
  - [확인] 코드·설정·결정 레지스터를 직접 읽어 확인한 사실
  - [재집계] 원장 JSON 기술 집계(진단 — 결정 근거 아님, AX-008)
  - [심사 실측] 3관점 심사가 실측으로 보고한 값(재계산하지 않음)
  - [감사] 레버 감사 최종본 인용(진단)
  - [판단] Q 판단값 — 전부 config 키로 두고 부록 D 에서 분류한다(도출 / 문헌 / 관례 / 판단 → A2-c)
  - [헌Mn]·[헌Rn] = 헌법 비평 수정 필수·권고 n번 · [완Mn]·[완Rn] = 완결성 비평 수정 필수·권고 n번
- 결정에 쓰는 수치는 전부 R 계약이 산출한다. 이 문서의 수치는 설계 근거이지 판정 근거가 아니다.

### v1 → 최종판 핵심 변경

1. **유기체 O1 은 live 0, shadow 전용이다.** RUNNER-RESTART-AFTER-P0-14(16:24)가 "현행 격자로 재개 · 유기적 강화는 설계 확정 뒤 shadow 로 붙인다"로 결정했기 때문이다. v1 의 'π_DG·FIFO·쿼터 0 live'는 유기체 밖 D-G/P1-08 이행 항목으로 분리했다. D-G 가 쓰는 전기간 G2 입력은 ORGANIC-DE Q②′ 로 상정한다 [헌M1·완M5].
2. **D-E 해석을 정정했다.** B08(P0-08)은 '성과를 쓰지 않는 선정'이 아니다. **보유 시작일(start_date) 이전 창의 성과 통계**로 고르는 선정이다. 그래서 τ_D 는 B08 보다 약한 as-of 이고, 기능상 **기계 입력에만 걸린 holdout** 이다.
   - Q③ 에 (d) start_date as-of 를 추가했다.
   - τ_D 는 'lockbox 폐지 조항의 예외 요청'으로 상정한다.
   - v1 의 "lockbox 가 아니다" 선언은 삭제했다 [헌M2·M3].
3. **Q④ 를 좁혔다.** D-E-B5-MATERIALS(17:16)에 맞춰 대상을 '가림 이전 재료의 **교차 entry** 수치에 노출된 과거 칸'으로 한정했다. 자기 entry 측정표는 기결정(유지)이다. A 보류는 노출이 도출된 칸에만 건다(501칸 일괄 보류 아님) [헌M4·완M5].
4. **A 관문이 유기체 provenance 를 읽는다.** P0-14 계보 도출이 시행 로그의 `organic_measure_tag` 를 읽고, 새 보류 코드(기본 비활성)를 둔다 [헌M5].
5. **러너 정지를 막는 장치를 보강했다.**
   - 불변식 ④(빈 칸이 남아 있으면 used < 칸 수)와 ⑤(B4 전 승자 결합 칸 보존)를 추가했다. 조기 소진 대상에서 B1·B4 를 뺐다 [완M1·헌M11].
   - 롤백이 러너가 실현한 효과(소진)까지 되돌리도록 사람 호출 `rf_reopen_entry` 를 둔다 [헌M10].
6. **결정 레지스터 기록을 재설계했다.**
   - 기계 상세 기록은 `06_Registry/organic/decisions.jsonl` 에 두고, 레지스터에는 전이 단위 포인터 행만 쓴다.
   - 세 writer 가 claim 잠금 하나와 CAS 를 공유한다. 기계 id 는 `M-ORG-` 네임스페이스를 쓴다.
   - 무인 레인(`QVEST_UNATTENDED_LANE=1`)에서도 `dr_open`/`dr_resolve` 는 stop 한다.
   - 09-23 일괄 결정은 note 로 증거를 대신하는 레거시 규칙을 둔다 [헌M8·M9·완M4].
7. **정적 봉쇄와 사전등록을 고쳤다.** G2 정적 봉쇄의 면제는 원장 투영 어댑터 1파일뿐이고, 그 파일은 열 허용목록 검사를 받는다 [헌M6·완M3]. G3 는 최소 사전등록 writer 를 O0a 에 신설하고, 저장소는 `06_Registry/prereg/` 하나로 둔다 [헌M7·완M6].
8. **리플레이와 추정을 고쳤다.**
   - 리플레이는 검증된 09-18 엔진(`04_Research/meta/axiom_replay`, 재현 98.4%)을 어댑터로 재사용한다.
   - "축소 정책은 전부 리플레이할 수 있다"는 주장을 철회했다. 조기 정지형이 최고 칸을 42~58% 놓친 실측을 사전확률로 싣는다 [완M2].
   - EB 추정의 공변량 창과 결과 창을 분리했다 [완M11].
   - 정책 수준 동시 대조를 둔다. 신규 entry 를 1:1 무작위로 나눠 한쪽은 pi0 로 유지한다 [완M10].
9. **하드코딩을 정리했다.**
   - 모든 파라미터를 부록 D 에서 도출 / 문헌 / 관례 / 판단 → A2 로 분류하고, 비어 있던 키를 채웠다.
   - 근거가 틀린 값 2건(retire_weeks, yield 창 단위)을 수정하고, p_ref 는 폐지했다(D-F 비례식 그대로 사용) [헌M13·완M7·M8].
   - 실행 트리거는 전부 기존 tick 레인의 idle 분기에 둔다. 새 스케줄 작업은 0 이다 [헌M12·완M9].
10. **규모를 재추정했다.** v1 대비 2~3배로 보고(O0 5~8세션), 착수 순서·세션 상한·멈춤 조건을 명시했다. 라운드와 A 레버(P2-02·PR-L2·PR-L1)가 우선이다 [완M12·M13].

- 반영 표 = 부록 A2 · 반영하지 못했거나 부분 반영한 권고와 그 사유 = 부록 E · 파라미터 전표 = 부록 D.

### 골격 선택

| 설계 | 심사1 | 심사2 | 심사3 | 합계 | 치명 결함 |
|---|---|---|---|---|---|
| wf (PIT-우선 워크포워드) | 7 | 5.5 | 6.5 | **19.0** | AAC 필터의 τ 이후 누출(심사2) · 설계 칸 절단 · G7 owner 위조(심사3) |
| bayes (베이지안 순차 배분) | 6 | 7 | 5.5 | 18.5 | 절단 불변식 부재로 영구 정지 · 예산 핑퐁 · E1 키 불일치(심사3) |
| evo (개방형 진화) | 5 | 6.5 | 4 | 15.5 | 정본 카탈로그 쓰기 · 설계 칸 절단 · 원장 shadow entry(심사3) |

**골격 = wf.** 채택한 것: 러너 통합 방식(칸 절단 → 격자 소진 경로로 회수, `max_attempts` 무접촉), 자기 파일만 쓰기, 결정 함수 하나에 시각 (r, τ) 만 주입, π_R 음성 대조, 연구 시각 전방 채점, 정적 칸 명제, 선택 인플레 계기.
wf 의 치명 결함 수리:
- AAC 는 필터에서 빼고 진단으로만 쓴다.
- 확약 합성은 유기체 밖 C-트랙으로 분리한다.
- τ_latest 대신 τ_D 를 쓴다.
- 칸 상한은 max(격자, 설계)로 두고 B1 은 제외한다.
- 결정 레지스터 자기승인 경로를 봉쇄한다.

**접목**
- bayes: 증거 자격표(수리판), 축소 추정(구조를 Morris 모수 경험베이즈로 교체), 단일 writer·denylist 봉쇄, PT 문턱 √T 환산, N 층위와 DSR 인자 계산, decision_id 충돌 수리.
- evo: 두 단 as-of((τ₀, τ_D] 정책 판정), 외부 성적표(사람 전용·되먹임 금지), 구조 봉쇄(기저 sha 고정 + `identical(fixed_axes)` 단언 + 허용 키 스키마), 서류와 유기체 사이 한 방향 방화벽, 사다리 띠 κσ, 부활 어휘 4종, 격리 arm 부활 거부 전이표.

**버린 것(사유는 부록 A)**
- bayes: 완전 계층 Gibbs, top-two Thompson.
- evo: MAP-Elites 틈새·기술자, shadow entry, 패치 파일로 격자 편집.
- wf: AAC 필터, 탐색 층 τ_latest, S_b 부호 일치 검정.

---

## 0. 한 줄 요지 · A 에 기여하는 경로

### 0.1 한 줄 요지

강화 러너 앞에 **순수 함수 컨트롤러**를 둔다. 컨트롤러가 보는 것은 두 가지다.
- 시장 시점 **τ_D** 이하의 수익. τ_D 는 각 칸의 등급 OOS 첫 분할점 이하로 재도출해 고정한 결정 시점이다.
- 연구 시점 r 이전에 닫힌 칸.

컨트롤러는 이 정보로 **무엇을 몇 칸 잴지를 줄이거나 되돌리는 결정**만 내린다(예산·공간·구조). 선택 가치 함수는 도훈의 D-E 해석 결정 전까지 shadow 로만 돈다.

- 모든 결정은 사전등록된 정책 판(policy@sha)이 내린다. 정책은 shadow → 두 단 as-of 리플레이 → live 순서로만 오른다.
- **러너 재개 시점의 유기체는 live 0 이다**(RUNNER-RESTART-AFTER-P0-14). 성과를 소비하는 live 는 ORGANIC-DE 결정과 O2 판정이 끝난 뒤에만 켠다 [헌M1·완M5].
- 결정은 시행 로그에 먼저 쓴다(write-ahead).
  - 기계 상세 기록은 `06_Registry/organic/decisions.jsonl` 에 둔다.
  - 결정 레지스터에는 전이 단위 포인터 행만 기계 소유로 남긴다 [헌M9].
- τ_D 이후 성과는 **사람이 보는 외부 성적표**에만 나온다. 기계 입력과 킬스위치에는 들어가지 않는다. 이 구조는 기능상 **기계 입력에만 걸린 holdout** 이므로 lockbox 폐지 조항의 예외로 도훈에게 상정한다(§2.6 Q③) [헌M3].

### 0.2 설계를 정한 사실 다섯

1. **구속 축인 OOS 벽은 τ_D 이후에 있다.**
   - A 에 가려면 Calmar +0.16 과 OOS +0.36 이 동시에 필요하다.
   - OOS 벽은 2017~20·2025~26 에 공통으로 나타나는 활성 성분이다[감사]. 두 구간 모두 τ_D 이후라서 as-of 컨트롤러는 이 벽을 **직접 겨냥할 수 없다.**
   - 겨냥하는 순간 OOS retention 은 과적합 검정으로서의 의미를 잃는다. ★이것은 look-ahead 논거가 아니라 **holdout 논거**다. 그래서 §2 에서 lockbox 폐지 조항의 예외로 상정한다 [헌M3].
2. **식별 해상도는 블록 수준이다.**
   - 레버 감사 기준으로 칸 하나의 짝지은 ΔCalmar SD 는 0.03~0.07, 블록 안 arm 평균들 사이의 SD 는 0.012~0.027 이다[감사].
   - ★잡음 척도의 원천이 문서마다 다르다[헌R11].
     - 레버 감사 L70: ≈0.07
     - 플랜 L243: ≈0.1
     - 플랜 L56: ≈0.15
   - 계산 예시(arm 차이 δ=0.02, 단측 α 0.05, 검정력 0.95, arm 당 필요한 칸 수 n = 2(1.645+1.645)²(σ/δ)²):
     - σ=0.05 이면 약 **135칸**
     - σ=0.15 이면 약 1,200칸
     - [계산 — 예시일 뿐 결정 근거가 아니다]
   - **이 계산을 파라미터 근거로 쓰지 않는다**(AX-008). 실제 n 하한은 O0b 에서 as-of 풀의 잡음 척도(R 계약 산출)와 부록 D 의 검정력 규칙으로 도출한다.
   - 결론은 σ 와 무관하다: arm 수준 결정은 큰 음의 효과에만 드물게 쓴다.
3. **청정 증거 풀이 지금은 작다.**
   - close_t1 칸 1,193 에서 C1 표식 531 과 `treatment_misspecified` 25 를 빼면 637 이 남는다[재집계]. 그중 501 칸은 **LLM B1 설계를 거친 26 entry** 안에 있다[재집계].
   - 설계 재료에는 **교차 entry 수치**가 들어 있다.
     - B1 재료 29건 중 28건에 "앞선 논문들에서 이미 배운 것" 절이 있다[재집계].
     - 예시 파일 `RP_20260924_052517_7308_adapted_rulefast.materials.txt` L99~111 에는 다른 entry(4212)의 arm 전기간 수치가 실려 있다(B2_8 minvar PORT_t −0.042 등)[확인].
     - v1 의 "앞 블록 칸 서술만" 기술은 틀렸다 [헌M4].
   - D-E-B5-MATERIALS(09-25 17:16)가 이 문제를 이미 결정했다.
     - 교차 entry 수치는 D-E(arm 선정 = C1) 소재로 분류하고 가린다.
     - 자기 entry 측정표는 "강화 루프 자체라 유지"한다.
     - 그래서 안건(Q④)으로 남는 것은 **가림 이전 재료로 설계된 과거 칸**의 지위뿐이다.
   - 노출 여부는 파일별로 도출한다. 28/29 파일에 교차 절이 있으므로, 대상을 좁혀도 규모는 크게 줄지 않을 수 있다.
   - 결정 전 엄격판 청정 풀은 136칸이다(B1 29 · B2 36 · B3 23 · B4 27 · B5 20 · **B6 0**)[재집계].
   - 따라서 **성과를 소비하는 결정은 당분간 대부분 '미결'로 나온다.** O0b 산출에 블록별 '결정 가능 시점' 예측을 넣는다 [완M12].
4. **러너 정지 경로는 둘이다. 불변식으로 둘 다 막는다.**
   - `rf_grid_consumed`(`rf_spec_sig.R:180-186`)는 빈 칸과 미측정 시도가 모두 0 이면, 예산이 남아 있어도 소진으로 처리한다. 그래서 칸 절단만으로 예산이 회수된다.
   - 경로 ①: **시도가 있는 코드를 지우면** `rf_resume_cell` 이 unknown 을 내고 러너가 매 tick 그 칸을 건너뛴다. pending 이 남으므로 entry 가 영구 정지한다[확인]. → 불변식 ①
   - 경로 ② (새로 확인): 배치는 `!pending ∧ used < length(cells)` 일 때만 만들어진다(러너 `:542`).
     - `attempts_used` 가 고유 칸 코드 수보다 큰 entry 가 원장 64개 중 10~12곳 있다. 초과분은 1~5이고, 모두 과거에 소진되거나 파킹된 entry 다[재집계 — 완결성 비평 10 · 이번 재집계 12].
     - 이런 entry 를 절단해 `length(cells) ≤ used` 가 됐는데 빈 칸이 남아 있으면 이렇게 된다: 배치 0 → jobs 0 → `rf_grid_consumed` FALSE → 매 tick `halt_no_jobs`(`:1268`). 09-05 사고와 같은 모양의 영구 정지다.
     - → 불변식 ④ [완M1]
5. **이미 결정된 규율과 그 이후 결정들이 한 함수에서 만난다.**
   - 09-23 선택 규율 (A)(SEL-DISCIPLINE): 격자 선택은 전기간 데이터를 쓰고 계상한다. 기각된 (B) = "선택만 anchored IS, 채점은 전기간".
   - D-E: 평가 창을 소비하는 자동 선정은 C1/C14 대상이다.
   - ORGANIC 가드: "as-of 정보만".
   - 이후 결정 4건이 경계를 더 정했다.
     - RUNNER-RESTART-AFTER-P0-14: 유기체는 shadow 로 붙인다.
     - D-E-B5-MATERIALS: 교차 entry 수치는 D-E 소재다.
     - D-E-V6-CONDITIONAL-IC: 전기간 조건부 IC 행렬로 선정하지 않는다. 새 규칙은 새 칸에만 적용하고, 과거 칸은 표식만 단다.
     - PR-L1-A4-DISPOSITION: 해결됐다.
   - **B08(P0-08) 선례**: 정적 칸의 구성은 **보유 시작일(`fixed_axes.start_date`) as-of** 통계로 선정한다(`rf_factor_arms.R::.rff_asof`)[확인] [헌M2].
   - 자율 컨트롤러는 정의상 이 교차점에 선다. 그래서 PIT 해석은 기계 권한 밖 안건으로 올린다(§2).

### 0.3 A 기여 경로 (정직판 · 재추정)

| 경로 | 기전 | 구속 축과의 연결 | 3개월 권위 A 증분 [판단] |
|---|---|---|---|
| ① 처리량 | (a) D-G B5 축소: 유기체 밖 사람 규칙 · ORGANIC-DE Q②′ 결정 뒤 <br>(b) B3 구조 사유 축소: 새 안건 A5 · 성과 비소비 <br>(c) 유기체의 블록 축소·조기 소진: 청정 증거가 부족해 3개월 안에는 '미결'이 가장 흔할 것이다 | 천장을 옮기는 경로는 새 기저뿐이다[감사 ③-2]. 다만 기저 품질이 결과를 거의 예측하지 않는다(D10-06) | (a)+(b) 승인 시 +0.2~0.8%p · (c) ≈0 |
| ② 사전등록 레버 호스팅 | PR-L2 → PR-L1 을 레인 최우선에 두는 일은 D-G 레인 순서(사람 규칙)가 이미 보장한다. 유기체가 보태는 것은 회수 예산만큼 착수를 앞당기는 것뿐이다 | EW−CW 성분을 치는 유형은 cap_core 하나뿐이다(L1 A 사전확률 3%) | +0.1~0.4%p |
| ③ 선택 정직성 | 승자 인플레(28 entry 중 23곳[감사])를 shadow 로 계측해 A 서류에 싣는다 | A 를 만들지 않는다. 거짓 A 를 줄인다 | ≈0 (정정 방향) |
| ④ as-of 규율 | 기계 결정이 등급 OOS 창을 보지 않는다 | 새 계보의 측정 A 근접도는 **내려간다**(플랜 원칙 1) | 음 (정정) |

**합계 판단값**: +0.3~1.2%p, 중앙 약 0.5%p. 증분의 대부분은 사람 규칙 (a)(b) 의 승인 여부에 달려 있다. 유기체의 성과 소비형 결정이 3개월 안에 기여하는 몫은 ≈0 이다 [완M12]. 그래서 이 설계를 A 레버로 보고하지 않는다.

확실한 가치는 네 가지다.
- 회계와 provenance: A 서류의 selection 정직성 축을 채우고, 유기체 태그가 A 관문에 닿게 한다 [헌M5].
- 쓰이지 않는 예산의 회수를 주장이 아니라 **원장 재도출 수**로 증명하는 계기.
- 스스로를 속이지 않는 개선 계기: 내부 계기, 사람 전용 외부 성적표, 동시 대조.
- 비용: 17~25 세션과 벽시계 12주 이상이 든다(§8). 라운드·A 레버와 세션을 다투므로 §8.0 의 착수 순서와 세션 상한을 따른다 [완M13].

---

## 0.5 코드·설정 재확인 (이번 통합에서 직접 읽은 것)

| 항목 | 사실 [확인] | 설계 귀결 |
|---|---|---|
| 러너 `:366-370` | 도훈 09-04 지시 "B1 칸 수 제한을 두지 마라". 전역 상한이 B4(결합)를 잘랐던 사고 기록 | **B1 은 절단 대상 밖.** 칸 상한 = max(격자 n, 설계 칸 수) |
| 러너 `:389` | `if (length(.cc))` — 0칸 설계는 격자 폴백 | 0칸 블록은 설계 파일이 아니라 칸 조립 뒤 절단으로 구현 |
| 러너 `:416`·`:436` | 상주 칸 삽입 끝 = `:436` | 유기체 절단 삽입점 = `:436` 뒤 1줄 |
| 러너 `:446-460` | `rf_budget_auto` + `rf_budget_want = max(auto, manual)`. 감산 경로 0(`rf_runner_gates.R:92-101`) | **예산 숫자는 건드리지 않는다.** 감소는 격자 소진으로 실현(`:1263`) |
| 러너 `:541-548` | `!pending ∧ used < length(cells)` 일 때만 배치를 만든다. 빈 칸이 0 이면 `halt_no_free_cell` 이다. 빈 칸이 있어도 `used ≥ length(cells)` 이면 배치가 0 이 되어 `halt_no_jobs`(`:1268`)가 난다 | 불변식 ①(시도 코드 보존)과 **④(빈 칸>0 ⇒ used<칸 수)** 로 두 경로를 막는다. K9 로 감시한다 [완M1] |
| 러너 `:664-699` | `.winner_of` argmax `:684` · `attr(out,"best_val") <- max(v)` `:697` | 선택 값이 순위 척도로 바뀌면 carry 게이트(`:717-724`)가 무성 퇴화 → **best_val 은 `.metric(w, by)` 로 분리** |
| 러너 `:752`·`:781`·`:791` | `.wbest_val`(PORT_t)을 P0-10 바닥 게이트가 읽는다 | 같은 분리 |
| `rf_runner_gates.R:277-303·309-331` | 현행 규약 = `execution.exec_price`(`close_t1`). 칸 regime 은 `.rfg_exec_label` 로 정규화된다 | 원장 1,193칸의 regime 문자열은 전부 `close_t1_5562284e`[재집계]이고 `current_axis` 는 `exec_v2_close_t1` 이다. **문자 대조는 증거 풀을 0 으로 만든다**(심사3) → `rf_candidate_facts(a, ctx, "regime")` 를 재사용 |
| `rf_runner_gates.R:454`·`a_eligibility_gate.json` | `vintage_flag` 보류 active, flags `["*"]`, verdicts {consumed, consumed_absence, possible} | **유기체는 `vintage_flags` 에 절대 쓰지 않는다**(어떤 표식이든 A 가 자동 보류된다). 정책 태그는 시행 로그에만 |
| `rf_runner_gates.R:552-559` | ⑤ vintage_flag 는 attempt 자기 표식만 읽는다 | P0-14 구멍 실재. 러너 재개 전 필수 |
| `reinforce_ledger.R:712-716` | kinds 에 `a_eligibility`·`prereg_verdict` 는 이미 있다. 미등재 kind 는 stop(`:720`) | organic kind 를 먼저 등재 |
| `reinforce_ledger.R:740` | decision_id = kind_base_`%Y%m%dT%H%M%S` — 초 단위 | 같은 초 다중 결정 충돌. 수리가 선행 |
| `reinforce_ledger.R:884·930` | `DR_STATUS_ENUM = c("open","resolved")`. enum 밖 status 는 `dr_load` 파손 | 기계 기록은 status=resolved 만(evo 의 'enacted' 는 레지스터 전체를 읽을 수 없게 만든다) |
| `reinforce_ledger.R:1001·1024` | owner 대조는 "문자열 규약이지 인증이 아니다" | 기계 자기승인 봉쇄 장치를 신설(§3 G7) |
| `policy_state.R:33-34·46·64` | `pol_env()` 기본 unattended=0. `pol_gate_live(env=)`, `pol_transition(env=)` 가 인자를 받는다 | 유기체는 전역 env 를 건드리지 않고 **명시 인자**로 넘긴다 |
| `rf_promote.R:107·114-117` | 승격 = 전기간 등급 ∈ {A,B} ∧ PORT_t > 부모 | 승격 여부는 pi0(격자 live) 소관이다. 유기체 입력에 등급을 넣지 않는다 |
| `rf_weight_arms.R:40-41` / `rf_overlay_arms.R:47` / `rf_factor_arms.R:271-275` | 각각 denylist / active allowlist / lifecycle active 필터다. 비중 픽커 제외는 **`label`** 로 대조하는데 카탈로그 id 는 `catalog_id` 다(`qepm:CDaR_LP` 대 `CDaR_LP`, `weight_catalog.R:475-512`)[확인]. 대소문자만 다른 label 도 있다(`hrp`/`HRP`) | 정본 status 는 쓰지 않는다. 휴면 목록은 `catalog_id` 로 저장하고, 픽커 제외 1줄도 `catalog_id` 로 대조한다. 양성 대조를 붙인다 [헌R3] |
| `rf_overlay_adversary.R:168·184` | `adv_block_len` = Politis-White. `adv_circular_block_perm` = **비복원 순열**(다중집합 보존) | 순열은 플라시보 전용이다. SE 는 복원 추출 정상 블록 부트스트랩 |
| `essence_score.R:193·219-230` | OOS 분할 = 칸 활성 계열 길이의 비율 {0.55, 0.65, 0.75}. 절단점 k = floor(n·fr) | 칸마다 분할일이 다르다. 590/1,193칸의 0.55 IS 말일이 2016-11-21~28[심사 실측] → **전역 리터럴 τ 금지. 재도출 + 칸별 단언** |
| `constraint_defaults.json::diagnostics.oos_calendar_splits` | 2016-11-30 · 2019-02-11 · 2021-04-08(골든 5,336일 기준) | τ_D 의 **상한 포인터**로만 쓴다 |
| `reinforce_program.json` | blocks 7×5 · B4 칸 = `combo.use`(예: B4_21 = [B1,B2,B3,B5]) · `fixed_axes` 에 INV-7 + `base_weight 0.5` 동거 | 격자 파일은 기계 denylist. B4 절단은 `combo.use` 로 판정 |
| 설계 재료(B1 29건 · 블록 설계 79파일) | B1 재료 28/29건에 "앞선 논문들에서 이미 배운 것" 교차 entry 절이 있다[재집계]. 예: `RP_20260924_052517_7308_adapted_rulefast.materials.txt` L99~111 = entry 4212 의 arm 전기간 수치(B2_8 minvar PORT_t −0.042 등)[확인]. 재료 파일에서 전기간 IC 수치는 확인되지 않았다. 툴을 거친 열람은 R2 가 막는 통로라 칸별로 확인할 수 없다 | Q④ 는 교차 entry 노출로 한정한다. 노출은 파일별로 도출한다. P0-14 확장 [헌M4] |
| tick 레인 순서 | 충실구현 → overlay_propose → B1 설계 → B5 설계 → L2 → 러너(`reinforce_auto_tick.sh:59-89`) | 유기체 레인 = L2 뒤 · 러너 앞 1줄 |
| 결정 레지스터(78항목 · open 0) | RUNNER-RESTART-AFTER-P0-14(16:24) · PR-L1-A4-DISPOSITION(16:24) · D-E-B5-MATERIALS(17:16) · D-E-V6-CONDITIONAL-IC(17:16) 모두 resolved. 09-23 일괄 결정(D-A~D-M)에는 `recorded_by`·`evidence` 필드가 없고, note 에 "도훈 채팅 결정(AskUserQuestion…)"만 있다. 두 필드는 09-24 17:31 CALMAR-FREQ-DAILY 부터 있다[확인] | O1 은 shadow 전용 · Q④ 축소 · G7 ③ 증거 규칙에 레거시 대체 규칙 [헌M4·M9·완M4·M5] |
| `dr_open`/`dr_resolve`(`reinforce_ledger.R:959-1060`) | 잠금이 없다. 적재 → 수정 → 원자 쓰기 순서다. 중복 id 가 있으면 `dr_load` 가 stop 한다(`:934`). 운영 트리의 호출처는 `boot_lean.sh` 1곳이고 무인 레인 호출은 0 이다[확인] | 공용 claim 잠금 + CAS. 무인 레인 문맥에서 stop 해도 기존 동작은 깨지지 않는다 [헌M8·M9] |
| `rf_factor_arms.R::.rff_asof`(B08) | as-of 기본값 = 격자 `fixed_axes.start_date`, 즉 첫 시그널일 이전 워밍업 창이다. **성과(IC) 통계를 쓰되 보유 시작 전 창에서만** 쓴다. B7 `selection_asof` 도 같다[확인] | B08 은 '성과 비사용'이 아니다. τ_D 는 B08 보다 약한 as-of 다 → Q③ (d) 추가 [헌M2] |
| `rf_b5_design_lib.R:27·381` | `stagnation_window` 는 **새 arm 을 낸 라운드** 수다(단위가 주가 아니다). compose_only 라운드는 창에 들어가지 않는다[확인] | D-G 의 'compose_only 지속'은 별도 연속 라운드 키로 센다. yield 창 단위를 고친다 [완M7·헌M13] |
| `reinforce_auto_config.json::b5_design.note` | B5 설계 새 arm 은 probe → G1 적대 감사를 거친다[확인] | D-G 의 "G1 경유"는 이미 성립한다 → v1 의 'B5 설계 arm 쿼터 0' 삭제 [헌M1] |
| 선행 코드 부재 | `reinforcement/rf_prereg.R`(P2-01) · `06_Registry/rf_trial_log.jsonl` + design_source(P1-02) · `contracts/selection_accounting.R`(P1-03) · `contracts/tilt_attribution.R`(P2-02) 가 전부 없다. P0-08 표식 도출기는 운영 트리 밖 `/c/tmp/p0_08_apply/apply_p0_08_flags.R` 에만 있다[확인] | 선행 목록에 올리고 단계를 배정해 규모에 반영한다(§8) [완M6·완R1] |
| 09-18 리플레이 엔진 `04_Research/meta/axiom_replay/` | post_0904 19트리에서 π₀ 배치 재현 98.4% · pre_0904 는 53.2% 라 제외 · 조기 정지형의 최고 칸 발견률 58%(정체 시 정지)·42%(앞 두 블록만) · 공간/예산 비 중앙값 1.00 → "이득은 덜 하기에서만"(`out/wp2_report.md`)[확인] | 리플레이는 이 엔진을 어댑터로 재사용한다. 축소 정책의 사전확률에 싣는다 [완M2] |
| 훅 13종 · 무인 레인 | `reinforce_auto_config.json`·`decision_register.json` 쓰기를 막는 훅이 없다(`research_continuity_guard.sh` 는 config 를 읽기만 한다). 무인 LLM 레인은 `QVEST_UNATTENDED_LANE=1` 이다(`rf_llm_env.sh:111`)[확인] | auto_live·킬 해제는 도훈 결정 id 를 참조할 때만 인정한다 [헌M8] |
| pol_cfg(`policy_state.R:19-26`) | `weekly_activation_max` 1 · `tombstone_window_weeks` 8 · `heldout_win_min` 0.60 · `null_percentile_min` 0.95 · `discovery_drop_max` 0.10 · `unreachable_max` 0.20 · `best_loss_max` 0.05 · shadow 최소 주수 키 = `shadow_min_weeks`[확인] | 도출 파라미터의 원천(부록 D) |

---

## 1. 네 층 설계

### 1.0 공통 기층

**(a) 두 시계와 결정 함수 하나**
- 시장 시점 τ(데이터 날짜)와 연구 시점 r(원장 `closed_at`)을 구분한다.
- 모든 층의 결정은 순수 함수 `rfo_decide(layer, view, τ, cfg)` 하나가 낸다. 입력은 `view = rf_organic_view(r, τ)` 뿐이다.
- live 는 (r_now, τ_D) 로, 리플레이는 (r_k, τ₀) 로 부른다. 리플레이 전용 코드 경로는 없다. 선례는 `rf_runner_ctx(regime = injected)`(`rf_runner_gates.R:293-303`)다.
- 검사: 같은 (r, τ) 이면 live 결정과 리플레이 결정이 identical 이어야 한다.

**(b) τ_D · τ₀ — 재도출해 고정한다(리터럴 없음)**

```
τ_D = min( diagnostics.oos_calendar_splits[1],  min_{c ∈ 증거 풀(epoch 개시 시)} IS_end_0.55(c) )
IS_end_0.55(c) = essence 가 쓰는 바로 그 코드(.essence_active_series + k = floor(n·0.55))로 산출한 IS 마지막 날
τ₀  = [첫 활성일, τ_D] 구간에 같은 비율 0.55 를 적용한 절단일      (.ESSENCE_OOS_SPLITS$v2[1] 참조)
```

- epoch 개시 때 `state.epoch{tau_D, tau_0, derivation{upper_source, pool_md5, n_pool, argmin_cell}}` 로 고정한다.
- **칸별 fail-closed 단언**: 증거·결정에 들어가는 모든 칸 c 에 대해 τ_D ≤ IS_end_0.55(c) 를 확인한다. 위반 칸은 `asof_split_violation` 으로 제외하고 센다.
- 이 단언이 설계 3종 공통의 오류("등급 OOS 와 완전히 분리")를 고친다. [심사 실측]에 따르면 τ_D 는 2016-11-21 이하로 나올 것이다.
- τ_D 는 "기계가 서 있는 결정 시점"이다. 사람·등급·Judge·BOOK·전략 구현은 전기간을 그대로 쓴다.
- 다만 기계 입력에서 τ_D 이후를 빼는 이 구조는 **기능상 기계 입력에만 걸린 holdout** 이다. 근거가 look-ahead 가 아니라 "겨냥하면 retention 이 과적합 검정의 의미를 잃는다"는 holdout 논거이기 때문이다.
- 그래서 lockbox 폐지 조항("전기간 사용 · 반박 금지")의 **예외 요청**으로 §2.6 Q③ 에 그대로 올린다. 결정 전에는 이 제약이 걸린 결정이 전부 shadow 라서 운영 효과가 없다 [헌M3].
- **τ_D 도출 강건성** [완R6]
  - min 도출은 이상 칸 하나(짧은 계열·이른 종료)에 끌려간다. 그래서 epoch 개시 보고에 argmin 칸의 사유와 IS_end 하위 분포(하위 5칸)를 싣는다.
  - τ_D 가 사전등록 하한 아래로 나오면 fail-loud 로 멈춘다. 하한 = `oos_calendar_splits[1] − diagnostics.window_allowance_months`, 즉 2016-11-30 − 12개월이다. 멈추면 하한 아래 칸을 `asof_split_violation` 으로 제외한 재도출안을 사람에게 보인다.
  - "≤2016-11-21"과 "(τ₀, τ_D] ≈ 2011~16"은 O0b 재도출 전까지 전제로만 쓴다.

**(c) as-of 계약 — 신규 `02_Infrastructure/contracts/asof_window.R`**
- `aw_split_dates(bt_result)`: 칸의 비율 분할일 3개를 낸다(essence 부품을 그대로 호출하고 복제하지 않는다).
- `aw_subwindow(bt_result, start = NULL, end)`가 산출하는 m = {PT, SR, CAGR, MDD, Calmar, IR_IS, IR_OOS(창 안 0.55/0.65/0.75 분할), n}.
  - PT 는 `build_benchmark_compare` 의 `Portfolio_Alpha_t_NW_lag3` 와 **같은 함수**다.
  - 계약 ①: start=NULL ∧ end=원 종료일이면 authoritative essence 의 해당 필드와 identical.
  - 계약 ②: end 이후 수익을 섭동해도 m 이 비트 불변.
- P1-03 `sa_subwindow`(2024-12 절단판)는 이 계약을 부르는 얇은 래퍼로 둔다. `selection_accounting.R` 은 `asof_window.R` 을 source 한다. **역방향 의존은 금지**다. 유기체가 서류 모듈을 source 하지 않게 하는 방화벽의 전제다(§4).
- 산출 배치 `ops/rf_organic_asof_batch.R`
  - idle 전용이고 자기 claim 과 시간 상한을 둔다. tick 밖에서 돈다(심사3).
  - 형제 판 `bt_result.rds` 를 재채점만 하고 재시뮬은 하지 않는다. 결과는 **`06_Registry/organic/asof/<epoch>/<cell_key>.json`**(τ_D 창·τ₀ 창·(τ₀, τ_D] 창)에 쓴다.
  - 측정 산출 디렉터리(`remeasure_close_t1_*`)에는 쓰지 않는다. P0-05 의 원본 불변 디렉터리이고, 재귀 glob 사고 선례(`remeasure_from_holdings.R:41`)가 있다. 이렇게 하면 쓰기 허용목록도 `06_Registry/organic/**` 하나로 단일화된다 [헌R2].
  - 1,193칸 × 3창 규모다.

**(d) 원장 투영 어댑터 + 단일 접근자** [헌M6·완M3]
- `rf_organic_ledger_adapter.R::rfo_project(r)` 가 원장과 as-of 산출을 읽는 **유일한 파일**이다. G2 정적 봉쇄에서 면제되는 유일한 파일이고, 출력 열은 허용목록 `organic.view.columns` 로 제한한다.
  - 허용 열:
    - 식별·계보: 칸 키 · base_id · 뿌리 계보 · 부모 사슬 · 블록 · 레버 키 · design_source
    - 블록은 격자 코드 정본을 쓴다. `essence$block` 은 B4 에서 빠뜨린 축을 적으므로 쓰지 않는다.
    - 상태: regime 사실(`rf_candidate_facts`) · 표식 · 창 편차 · 짝 바닥 id · closed_at · `inherited_from` 유무(불리언) · terminal/`cell_no_treatment` 여부
    - as-of 지표(`06_Registry/organic/asof/<epoch>/`)
  - **전기간 essence 수치 · 등급 · retention · DSR · 적대검증 판정 열은 없다.** E4 가 쓰는 `inherited_from` 은 불리언으로만 투영한다.
  - 검사: 투영 열 집합이 허용목록과 같아야 한다(금지 열을 추가한 돌연변이는 red). 어댑터 출력 md5 는 결정론적이어야 한다.
- `rf_organic_view(r, τ)` 는 어댑터 출력만 받고, `closed_at < r` 인 칸만 돌려준다.
- view·model·policy·replay 파일에는 토큰 금지를 그대로 건다(§3 G2).
- τ₀ 도출에 쓰는 `.ESSENCE_OOS_SPLITS` 참조는 `contracts/asof_window.R` 안에만 둔다 [헌R14].

**(e) 증거 자격 E1~E8 — 전부 충족해야 한다**

| 코드 | 조건 | 원천 · 수리 내용 |
|---|---|---|
| E1 | 현행 규약 칸 | `rf_candidate_facts(a, .RCTX, "regime")` 통과. 문자열 대조 금지(심사3) |
| E2 | 표식 제외 — **전 블록** | `organic.evidence.exclude_flags` = {pit_c11, treatment_misspecified, selection_basis_full_sample_ic, selection_basis_full_sample_ic_inherited} + P0-14 계보 도출 표식. bayes 의 "Δ 에서 대부분 상쇄" 예외는 pit.md 금지 합리화라 폐기(심사1) |
| E3 | 설계 출처 층화 | `design_source` 는 **칸 단위**로 도출한다 [완R14]. 설계 파일 존재로 도출하면 entry 단위가 되어, 설계 검증에 실패해 규칙으로 폴백한 칸을 LLM 칸으로 잘못 분류한다. <br>원천: 설계 검증 기록(`b1_design_verify`·`rfbd_verify` 결정 kind)과 칸 spec 의 출처 필드. <br>범위: B1 설계(`.cache/rf_b1_design` 29) + 블록 설계(`.cache/rf_block_design` 79파일, B2·B3·B5) + B5 설계 레인. <br>값: rule_asof / rule_full_ic / llm_crossentry_exposed / llm_own_entry / llm_masked / grid / standing / carry_replay. <br>`llm_crossentry_exposed` 칸은 Q④ 결정 전까지 **층을 나눠 적합**하고, 결정에는 청정 층만 쓴다(`organic.evidence.design_stratum`) |
| E4 | 측정 완료 · 비상속 | `essence$inherited_from` 없음 · terminal 아님 · `cell_no_treatment` 아님 |
| E5 | 창 허용 | `window_deviation_months ≤ diagnostics.window_allowance_months`(D-C) |
| E6 | 동시 대조 | 칸과 짝 바닥이 같은 규약 ∧ 같은 데이터 지문. P0-07 지문 동치로 판정하고, mtime 등식은 금지(심사3). P0-07 배포 전에는 rebase 스탬프(시장 md5)로 대신한다 |
| E7 | as-of 뷰 존재 ∧ τ_D ≤ IS_end_0.55(c) | (b)·(c) |
| E8 | 블록 제외 | B5 는 as-of 적대검증(`adv_asof`, O4)이 생길 때까지 증거에서 뺀다. 현 T3 판정은 전기간 산출이다(심사1). B7 은 과거 칸이 오지정이라 증거 0 이다 |

- 블록의 유효 증거 수가 `organic.evidence.min_cells_block`(부록 D 의 검정력 규칙으로 도출) 미만이거나, 뿌리 계보 수가 `min_lineages_block` 미만이면 그 블록 결정은 **미결**이다. 조용히 실패하지 않고 로그와 주간 보고에 남긴다(K7 계열).

**(f) 효용 — D-F "게이트 축 = 제약 부족분 S" 의 as-of 판**

```
S_τ(c) = Σ_{j ∈ {PT, SR, CAGR, Calmar, R}}  max(0, θ_j^τ − m_j^τ(c)) / s_j
θ_j^τ  = tier_graduation 값(읽기 전용). PT 만 θ_PT^τ = θ_PT · sqrt(T_τ(c) / T_full(c))
         — NW-t 는 IR 이 고정일 때 √T 에 비례한다. ★내부 정규화 전용 proxy 이고 "판정 인용 금지(hurdle 급)" 라벨을 단다.
           π_S 가 live 가 되면 사실상 A-거리 정의를 바꾸는 셈이므로 A2-h 로 올린다 [헌R12]
m_R^τ(c) = median_s [ IR_OOS,s(c) / IR_IS,s(f(c)) ]     (고정 분모 retention: 분모 = 짝 바닥 f 의 창 안 IS 활성 IR)
         — 바닥 IS IR ≤ essence 의 retention 하한 규칙이면 NA → R 항 제외(계수)
u(c)   = S_τ(f(c)) − S_τ(c)        (부족분 감소 · 양수 = 개선)
```

- **목표 축 상한**: hinge 이므로 문턱을 넘긴 축은 0 이다. 초과분에는 보상이 없다(Goodhart 방지 · 기억 카드 "상한은 목표 축에").
- **고정 분모 retention**: 자기 IS 를 희석해 비율을 올리는 경로를 막는다(L-QPM-20260706 분모 게임). IS 활성 IR 은 보고에 병기한다.
- s_j(축 잡음 척도)는 (g) 에서 온다.

**(g) 잡음 척도 s_j · 칸 SE**
- 1순위는 P1-06 null-factor 희석 통제칸의 짝지은 차이(as-of 창)다. 2순위는 **복원 추출 정상 블록 부트스트랩**(Politis & Romano 1994)이다.
  - (칸, 바닥, 벤치) 세 계열을 공통 인덱스로 재표집해 S 를 통째로 다시 계산한다.
  - 블록 길이는 `adv_block_len(rule="auto")`(Politis-White 2004 + Patton-Politis-White 2009 정정)를 쓴다.
  - 두 값 중 **큰 쪽**을 쓴다.
- `adv_circular_block_perm` 은 쓰지 않는다. 순열은 CAGR·SR 을 보존해 SE 를 과소 추정한다(심사2).
- 위상쌍 B6_32/33 은 계통 효과라 SE 원천이 아니다[감사].

**(h) 짝 바닥과 레버 효과 추정 — Morris 모수 경험베이즈**

짝 바닥 f(c)를 정하는 순서:
1. `floor_code` 기록(09-17 이후 B5)
2. 승계 성분의 서명 복원 — 칸 spec 의 승계 성분마다, 그 성분을 자기 축 처치로 가진 같은 entry 측정 칸
- 양성 대조: `floor_code` 가 있는 칸에서 복원 바닥과 기록 바닥을 대조한다. 불일치는 전부 사유로 분류해야 하며, **미분류 불일치 0** 이 통과 조건이다. 수치 문턱 대신 전수 분류로 판정한다(부록 D) [헌M13].
- 복원 불가 칸은 제외하고 센다.
- 이 복원은 **짝 짓기에만** 쓴다. wf 의 AAC 처럼 필터로 쓰면 τ 이후 누출이 된다(심사2).

추정 — **공변량 창과 결과 창을 나눈다** [완M11]
```
블록 b 안:  u_i = a_ℓ(i) + γ_b · (S_{≤τ₀}(f_i) − S̄_b) + e_i
           u_i 는 (τ₀, τ_D] 창 값, 공변량은 ≤τ₀ 창 값
           — 같은 측정잡음이 양변에 들어가 γ̂ 이 부푸는 기계적 편향을 막는다
           OLS · 표준오차 = entry 군집 강건(같은 바닥을 공유하는 상관을 흡수) → â_ℓ, V_ℓ
           군집 수 < organic.model.min_clusters_cr 이면 wild cluster bootstrap(Cameron, Gelbach & Miller 2008)으로 SE 산출
EB 축소(Morris 1983):  ã_ℓ = μ̂_b + (1 − B_ℓ)(â_ℓ − μ̂_b),  B_ℓ = V_ℓ / (V_ℓ + τ̂_b²),  τ̂_b² = max(0, Var_ℓ(â_ℓ) − mean_ℓ V_ℓ)
                       sd_ℓ ≈ sqrt((1 − B_ℓ) V_ℓ)  (+ τ̂ 불확실성 Morris 보정항)
블록 효과:  α̂_b = 블록 안 u 평균,  se_b = 뿌리 계보 군집 강건
P(a_ℓ > δ) = Φ((ã_ℓ − δ)/sd_ℓ) ,  P̂_b = Φ((α̂_b − δ)/se_b) ,  δ = delta_sigma · (u 의 합동 잡음 SD)   — D-F "잡음 파생 여백"
```
- O0b 합성 세계 검사에 "γ 참값이 0 이면 γ̂ ≈ 0(95% 구간이 0 을 포함하는 비율 ≈ 0.95)"을 추가한다.
- live 결정도 같은 창으로 적합한다. 공변량은 ≤τ₀, 결과는 (τ₀, τ_D] 로, 모두 τ_D 이하다.

- γ_b 는 평균회귀를 교정한다. 나쁜 바닥일수록 개선이 쉬운 효과다. 레버 감사에서 "기준선에 따라 B1 부호가 뒤집힌" 기전이 이것이다.
- **사전 분포는 쓰지 않는다.** 모든 척도는 as-of 풀 자체에서 추정한다. 레버 감사의 전기간 분산을 초사전으로 쓰지 않는다(심사1).
- 완전 계층 Gibbs(bayes)는 v1 에 넣지 않는다. 켤레가 아니고(심사2), 규모 약 700줄에 비해 이득이 실증되지 않았다(심사3). O2 에서 보정 계기(I2)가 실패할 때만 대안으로 shadow 비교한다.
- 사후 요약 산출은 P3-01 레버 장부와 같은 저장소 `06_Registry/organic/lever_book/<epoch>.json` 하나에 둔다. 이 장부가 P3-01 의 as-of 뷰이고, 저장소를 둘로 만들지 않는다(AX-D2). `state.json` 에는 포인터와 해시(`posterior_ref{path, md5, fit_at, pool_md5}`)만 둔다 [헌R7].
- 적합은 기존 tick 레인의 idle 분기(`ops/rf_organic_fit.R`)에서 하고, 러너는 적합하지 않는다.

---

### 1.1 예산 층

**상태 변수**
- `plan[BID][b] = {n, cells_kept[], frozen, decided_at, policy@sha}`: entry × 블록 계획
- `P̂_b`: 블록 개선 확률
- entry 별 {used, 블록별 시도 코드 집합, 측정 블록 수, 승격 깊이}
- 신규 논문 소비: 승격 세대별 신규 논문 착수 수. D-G 의 "승격 세대당 신규 논문 ≥1"을 세대 단위 그대로 센다. v1 의 7일 비중 환산은 폐기한다 [헌R14·완M8].
- D-G 대조(shadow 전용): `dg_shadow{dead, since, g2_pass, compose_only_run}`. live 는 유기체 밖에서 한다(아래 '유기체 밖 사람 규칙').

**결정 규칙** (B1 은 절단 대상 밖 · B4 는 불변식 ③⑤ 로만 줄어든다)

```
n_cap(e,b) = max( blocks[b].n (격자),  이 entry 의 설계 칸 수(b) )                — 설계 칸을 자르지 않는다(심사3)
n(e,b)     = n_cap                                                     (정책이 live 가 아니거나 증거가 미결이면 = pi0)
           = max( n_min_b,  |시도 코드(e,b)|,  n_min_b + ⌊(n_cap − n_min_b) · P̂_b⌋ )     (live)
보존 순서  = 설계 칸 순서(설계 블록) 또는 격자 순서 — 결정론. 시도가 있는 코드는 항상 보존
```

- 비례식은 D-F 의 "soft 예산(다음 세대 ∝ P(Δ>0))"을 그대로 옮긴 것이다. v1 의 `p_ref`(비례 기준 0.5)는 근거 없는 판단값이라 폐지한다 [헌M13].
- **불변식 ①**: 시도(측정·pending·terminal)가 있는 코드는 절대 지우지 않는다. `resume_skip_unknown_cell`(`:833`) 정지 경로를 막는다.
- **불변식 ②**: 블록 b 의 계획은 그 블록의 첫 시도가 등록된 tick 의 계획으로 동결하고, 덮어쓰기를 거부한다(선례 `rf_record_block_order`).
- **불변식 ③**: B4 는 `combo.use` 에 n=0 이거나 diag 상태인 블록이 들어간 칸만 뺀다.
- **불변식 ④ (신규 · 정지 방지)** [완M1]
  - 절단 뒤 **빈 칸이 1개 이상 남으면 `length(cells) > used`** 여야 한다.
  - 위반하면 보존 순서대로 빈 칸을 더 살려 조건을 맞춘다. 그래도 맞출 수 없으면 절단을 취소(항등)하고 K9 를 낸다.
  - 빈 칸이 0 이 되도록 자르는 경우는 `rf_grid_consumed` 를 거쳐 정상 소진으로 가므로 허용한다.
- **불변식 ⑤ (신규)** [완R8]
  - B3·B5 가 동시에 축소돼도 B4 의 **전 승자 결합 칸**은 보존한다. 격자에서 `combo.use` 가 가장 넓은 칸이며, 현행 B4_21 = [B1,B2,B3,B5] 다.
  - 근거는 09-04 지시다(러너 `:366-370`: 결합이 못 돌면 그 entry 는 A 로 갈 길이 없다).
  - 이 칸이 참조하는 블록이 dormant(0칸)이면, 그 블록 승자 자리는 현행 누적 규칙대로 바닥이 채운다.
- **조기 소진(무익성)** — v1 은 shadow 전용
  - 조건: `P_cont(e) = 1 − Π_{b ∈ 남은 계획 블록}(1 − P̂_b) < p_stop` ∧ used ≥ n_min_entry ∧ 측정 블록 수 ≥ min_blocks
  - 효과: 남은 블록 가운데 **B1·B4 를 뺀** 블록을 n=0 으로 둔다. B4 는 불변식 ③⑤ 로만 줄어든다 [헌M11]. 그 결과 빈 칸이 0 이 되면 격자 소진 → `.exhaust_and_delegate("grid")` 로 넘어간다.
  - 판정 축은 S 다. PT 가 아니다(레버 감사 ④).
  - `p_stop` 은 리플레이 보정으로 정한다. 두 단 리플레이에서 "(τ₀, τ_D] 최고 칸을 잘랐을 비율 ≤ `pol_cfg.discovery_drop_max`"를 만족하는 가장 큰 값이다. 설계로 보정하라는 Saville et al. 2014 의 권고를 따른 것이다(부록 D).
  - ★09-18 실측에서 조기 정지형은 최고 칸을 42~58% 놓쳤다. 이 조건을 만족하는 p_stop 이 없을 수 있다. 없으면 조기 소진은 **철회**로 기록한다 [완M2].
- **승격 자식 soft 예산(D-F soft)**
  - 자식 entry 의 비-B1·비-B4 블록 n 에 `P̂_child` 를 곱한다(D-F 비례식).
  - 승격 **여부**는 pi0(`rf_promote_decide`) 소관이다. "승격하지 않음"은 선택 층 shadow 로만 기록한다.
  - ★승격이 B 모듈의 69% 를 만든다(09-18 실측). soft 예산과 B5 축소는 2계층 풀 공급을 줄인다. 그런데 B 등급은 전기간 파생값이라 기계 게이트에 넣을 수 없다. 그래서 외부 성적표 X6 와 동시 대조로 사람이 본다 [완R2].
- **B5 재설계 라운드와의 상호작용** [완R8]
  - `E$b5_redesign`·`cells_added` 로 붙은 칸은 새 라운드의 설계 칸이다.
  - 불변식 ② 의 동결은 **라운드 단위**로 건다. 재설계가 붙인 칸은 동결 뒤에 추가된 칸이라 절단 대상이 아니다. 계획을 재산출하지 않는다.
- **레인**
  - FIFO(P1-08)와 D-G 레인 순서(prereg > 신규 논문 > 승격 > 반사실)는 유기체 밖 사람 규칙이다(아래).
  - 유기체는 같은 순위 안에서 P_cont 로 정렬하는 것만 shadow 로 계산한다.
- **불변(기계 권한 밖)**: daily_cap · parallel_cells · worker_timeout_sec · cell_max_retry · `max_attempts`(원장·entry) · 격자 n · `promote_max_depth(_hard)`. 유기체는 **줄이기와 복원만** 한다.
- **`rf_budget_auto` 가 설계 칸·상주 칸을 MAXA 에 더하는 경로**(레버 감사 ④-3)
  - 유기체가 절단할 때 불변식 ④ 가 성립하면 격자 소진이 먼저 서므로, 이 경로가 정지를 만들지 않는다.
  - v1 은 이것을 "무해"라고만 적었다. 최종판은 근거를 **검사로** 둔다: 절단 뒤 `MAXA > length(cells)` 인 entry 픽스처에서 `grid_consumed → exhaust` 가 서는지 확인한다(K9 양성 대조) [완R12].
  - 가산 경로 자체를 막는 일은 D-G 이행 항목 소관이다(아래).

**유기체 밖 사람 규칙 — D-G·P1-08 이행 항목 (유기체가 소유하지 않는다)** [헌M1·완M5]

분리하는 이유는 두 가지다.
- RUNNER-RESTART-AFTER-P0-14 는 "현행 격자로 재개 · 유기적 강화는 설계 확정 뒤 shadow"로 결정됐다. 유기체 안에서 규칙을 live 로 켜면 이 결정과 충돌한다.
- 규칙을 유기체 모듈 안에 두고 G2 정적 봉쇄에서 면제하면, "as-of 정보만" 가드에 예외 구멍이 생긴다. D-E 의 면제 대상은 "사람이 문헌 근거로 고르는 것"뿐이고, 사람이 작성한 자동 규칙은 여기에 해당하지 않는다.

각 규칙은 플랜 항목으로 따로 배포·검사·롤백한다.

| 규칙 | 성과 소비 | 배포 조건 |
|---|---|---|
| P1-08 FIFO + D-G 레인 순서 + "승격 세대당 신규 논문 ≥1" | 아니오(대기열 순서) | D-G 로 이미 결정됨. 플랜 P1-08 배포 절차로 러너 재개와 함께 켤 수 있다 |
| overlay_propose 의 **G1 경유** | 아니오(입장 관문) | D-G 원문 "G1 경유 **또는** dead 동안 정지" 중 성과를 소비하지 않는 분기다. O0a 에서 현재 경유 여부를 확인하고, 경유하지 않으면 배선한다 |
| `rf_budget_auto` 의 B5 설계·상주 칸 가산 차단 + `b5_budget` 키 | 아니오 | D-G 이행 항목(레버 감사 ④-3) |
| B5 축소(상주 + `standing_plus`, pass 시 복원) · overlay_propose 'dead 동안 정지' | **예** — 입력이 프로그램 G2 pass 수(전기간 적대검증 판정)와 compose_only 지속이다 | **ORGANIC-DE Q②′ 결정 뒤.** D-E-B5-MATERIALS 는 교차 entry 의 "G2 수치"를 D-E 소재로 분류했다 |

- v1 의 "B5 설계 새 arm 쿼터 0(dead 동안)"은 **삭제**한다. D-G 가 정지를 요구한 것은 overlay_propose 이고, B5 설계 arm 은 이미 G1 을 거친다(`b5_design.note`)[확인] [헌M1].
- 'compose_only 지속'의 수치는 D-G 원문에 없다. `stagnation_window` 는 **arm 을 낸 라운드** 수라서 compose_only 지속을 셀 수 없다(`rf_b5_design_lib.R:27·381`). 그래서 별도 키 `b5_budget.compose_only_consecutive_rounds` 를 두고, 값은 도훈 확정 안건(A2-e)으로 올린다 [완M7].
- 유기체는 같은 규칙을 `dg_shadow` 로 계산해 "사람 규칙이 live 였다면 어땠을지"를 대조 기록만 한다.

**입력**: `rf_organic_view(r_now, τ_D)` · 원장 구조 필드(어댑터 경유) · 설계 파일 칸 수(`.cache/rf_b1_design`, `.cache/rf_block_design`) · 격자 · jlog `overlay_guard_h3/h4`(dg_shadow 전용).

**갱신 주기**
- 유기체 tick(러너 직전, 매 tick)은 활성 entry 의 **미진입 블록** 계획만 캐시 사후로 다시 계산한다.
- 진입한 블록은 동결한다. tick 은 먼저 동결 여부를 확인하고, 그다음 미진입 블록을 계산한다.
- 사후 재적합은 idle 분기에서 하루 1회, 그리고 epoch 이 바뀔 때 한다(트리거 §8.0).

**파라미터** (`reinforce_auto_config.json::organic.budget.*` — 사람 소유 · 기계는 읽기만 · 분류와 근거 = 부록 D)

| 키 | 초기값 | 분류 |
|---|---|---|
| `n_min_by_block` | B2 1 · B3 1(진단칸, 레버 감사 ④) · B6 = 격자 `phase_control` 이 지목한 칸 쌍 수(현행 B6_32·B6_33 → 2) · B7 = 사전등록값 · B5 = D-G 이행 항목 | B2 는 판단 → A2-c · 나머지는 도출 |
| `delta_sigma` | 1.0 | 판단 → A2-c(D-F 는 "짝지은 SE 배수"만 정했다) |
| `futility.p_stop` | 리플레이 보정(위) | 도출(pol_cfg) |
| `futility.min_blocks` | 2 | 판단 → A2-c |
| `futility.n_min_entry_source` | "blocks[B1].n + max(blocks[-B1].n)" | 도출(격자) |
| `soft_child.enabled` | false(shadow) | D-F |

**러너 개입 지점** (러너 본체는 바꾸지 않는다. 동시 수리로 줄 번호가 이동하므로 **함수·마커 기준**으로 적는다 [완R10])
- 원장 적재와 `.RCTX` 구성 직후(현 `reinforce_auto_parallel.R:144` 부근) 2줄: `source(".../rf_organic_apply.R", local=TRUE)` · `.OST <- rf_organic_ctx(ROOT, E, .RCTX, log = jlog)`. 상태를 읽고 신선도 키만 검사한다. **쓰기는 없다.**
- 상주 칸 삽입 블록 끝(현 `:436` 부근) 1줄: `cells <- rf_organic_cells(cells, E, .OST, log = jlog)`.
  - off·shadow 면 항등이다. shadow 는 "would_trim" 을 jlog 로만 남긴다.
  - live 면 `state.plan` 을 적용한다. 함수 안에서 불변식 ①③④⑤ 를 다시 단언하고, 위반이면 항등으로 돌리고 K9 를 낸다.
  - 적용한 절단은 jlog `organic_trim_applied{BID, removed}` 와 시행 로그에 남긴다. 롤백을 추적하기 위해서다(§3.3).
- 예산(`rf_budget_want`)·예산 소진·격자 소진 분기는 **수정하지 않는다.** 감소는 격자 소진으로 실현된다.
- 병합 절차: 동시 수리 배포 뒤 삽입점을 다시 읽고(마커 grep), 삽입한 줄을 지운 돌연변이 검사로 위치를 고정한다.
- `reinforce_auto_tick.sh` 에서 L2 레인과 러너 사이에 1줄: `[ -f rf_organic_tick.sh ] && bash rf_organic_tick.sh`.
  - 자기 claim(`rf_claim.R`)과 시간 상한을 둔다. 파일이 없거나 실패하면 즉시 종료한다.
  - 캐시가 낡으면 러너는 pi0 로 돈다(K7).
  - L2 드라이버가 러너 claim 을 쥐고 있는 동안에는 유기체 tick 이 **기다리지 않고 건너뛴다**(tick 순서 규약 §8.0) [완R11].

---

### 1.2 공간 층 (arm 생성·휴면)

**상태 변수**: `state.arms[id] = {block, status ∈ {pi0, organic_dormant, organic_probation, organic_retired}, since, reason, decision_id, probes, history[]}` · 생성 레인 쿼터 `state.quotas[lane]` · 레인 수율 y_ℓ.

**관리 범위(v1)**
- **B2 비중 arm 만** 관리한다.
- B5 는 as-of 적대검증(O4)이 생길 때까지 유기체 관리 밖이다. D-G 는 유기체 밖 이행 항목이다(§1.1).
- B1 팩터 수준은 D-E·P0-08 소관이라 범위 밖이다.
- B3·B6·B7 은 격자 고정 칸이라 구조 층 소관이다.
- 정본 status 가 active 가 아닌 arm(retired · suspended C11 · `pit_quarantine`)은 **관리 대상 자체가 아니다**. 부활도 없다.

**결정 규칙**
- **휴면**: 아래를 모두 만족하면 `organic_dormant` 다.
  - n_ℓ ≥ `n_min_arm` ∧ 계보 수 ≥ `r_min_arm`
  - P(a_ℓ > 0 | as-of 증거) < `dormant_p`
  - 뿌리 계보 군집 부트스트랩에서 음 부호가 `stable_share` 이상
  - 주간 변경 ≤ `max_changes_per_week`
- **부활 어휘 4종**(evo · 기억 카드 "닫힌 칸에는 되살리는 어휘")
  - 아래 ①~④ 중 하나라도 서면 `organic_probation` 이 된다.
  - probation 은 새 뿌리 entry 1개에서 픽커 제외를 풀어 탐침 `space.probe_cells` 칸을 허용한다. 값은 측정 최소 단위인 1칸이다(도출).
  - ① regime·epoch 변경
  - ② arm 코드·엔진 md5 변경(원인 수리)
  - ③ 재적합에서 P > `revive_p`(히스테리시스)
  - ④ `dormant_weeks` 경과
- **기계 퇴역**: dormant 가 `retire_weeks` 이상 이어지고, 탐침이 `space.retire_probe_failures`(판단 → A2-c)회 실패하면 `organic_retired` 로 둔다(자기 파일에서만).
  - `retire_weeks` = 2 × `dormant_weeks` = 16주. 부활 트리거 ④ 두 주기다. v1 의 26 은 산술 오류였다 [헌M13].
  - 정본 status 는 바뀌지 않고, 사람이 한 줄로 되돌릴 수 있다.
- **생성 쿼터 — 줄이기만 한다**: `q_ℓ ∈ [0, q_cap_ℓ]`(q_cap = 기존 사람 config)
  - `rf_overlay_propose`: 유기체 관리 밖이다(D-G 이행 항목 · §1.1). v1 의 'B5 설계 새 arm q=0' 은 삭제했다. B5 설계 arm 은 이미 G1 을 거치고, D-G 도 이를 요구하지 않는다 [헌M1].
  - `rf_weight_catalog_grow`: y_ℓ 은 생성 arm 가운데 G1 을 통과하고, 측정됐고, as-of a_ℓ > 0 인 비율이다.
    - y_ℓ = 0 이 **최근 `space.quota_yield_window_rounds` 생성 라운드** 동안 이어지면 q=0(shadow → live), 아니면 cap 이다.
    - 생성 라운드는 그 레인이 arm 을 낸 실행만 센다. `stagnation_window` 와 같은 단위이고, 같은 우회 차단 논리다.
    - v1 은 창을 '주'로 적어 단위가 틀렸다 [헌M13·완M7].
- 레버 감사가 지목한 해로운 arm(CDaR_LP·SchurDamping·minvar)은 **정답지가 아니다**(전기간 판정). as-of 규칙이 독립적으로 같은 결론에 도달하는지를 일치율로 보고만 한다.

**입력**: 증거표(E1~E8) · 사후 · `overlay_arm_ledger.jsonl`(생성 출처) · 카탈로그 3종(읽기만).

**갱신 주기**: 주 1회 배치다. 휴면 최소 체류는 `dormant_weeks` 다.

**파라미터** (`organic.space.*` — 분류와 근거 = 부록 D)

| 키 | 초기값 | 분류 |
|---|---|---|
| `managed_blocks` | ["B2"] | 설계 범위 |
| `n_min_arm` | 검정력 규칙: 최소 탐지 효과 `min_detectable_effect_sigma` 에서 n 도출(부록 D) | 도출. 단 MDE 는 판단 → A2-c |
| `r_min_arm` | 3 | 판단 → A2-c |
| `dormant_p` · `revive_p` | 0.05 · 0.15 | 관례 α · 판단(히스테리시스 폭) → A2-c |
| `stable_share` | 0.8 | 판단 → A2-c |
| `dormant_weeks` · `retire_weeks` | 8 · 2 × dormant_weeks(= 16) | 도출(`policy_state` tombstone_window_weeks 8 · 부활 트리거 ④ 두 주기) |
| `max_changes_per_week` | pol_cfg `weekly_activation_max`(= 1) | 도출 |
| `quota_yield_window_rounds` | `b5_design.guards.stagnation_window`(= 2, 단위 = 라운드) | 도출(단위 일치) |
| `probe_cells` · `retire_probe_failures` | 1 · 2 | 도출(측정 최소 단위) · 판단 → A2-c |

**개입 지점** — 정본 카탈로그·registry 에는 쓰지 않는다(심사 3종 공통)
- `rf_weight_arms.R` 의 `rf_pick_weight_arms` 에 휴면 제외를 넣는다. 1줄이고 **`catalog_id` 로 대조**한다: `A <- A[!(catalog_id %in% .dorm)]`, 여기서 `.dorm = rf_organic_dormant_ids(root, "B2")`.
  - 현행 `exclude` 는 `label` 로 대조한다. 여기에 카탈로그 id(`qepm:CDaR_LP`)를 넣으면 아무 효과가 없고 오류도 나지 않는다. 대소문자만 다른 label(`hrp`/`HRP`)도 있다 [헌R3].
  - 파일이 없거나 off 면 빈 벡터라서 결과가 비트 동일하다.
  - 양성 대조: 휴면 1개를 주입하면 픽커 산출에서 정확히 그 `catalog_id` 1개만 빠져야 한다. 대소문자 충돌 픽스처도 둔다.
- `rf_block_design.R` 의 `rfbd_catalog` 에도 같은 키로 같은 제외 1줄을 넣는다. 설계 레인이 휴면 arm 을 설계로 되살리지 못하게 한다.
- 설계 파일이 휴면보다 먼저 만들어졌다면 `rf_organic_cells` 가 해당 칸을 뺀다. 시도가 없는 칸만 빼고 불변식 ④ 를 지킨다. 이중 방어다.
- 레인 셸 `rf_weight_catalog_grow.sh` 가 `state.quotas` 를 읽는다. 값이 없으면 cap 을 쓴다.
- O4 에서 B5 를 편입할 때 `rf_overlay_arms.R` 에 같은 1줄을 넣는다.

---

### 1.3 선택 층 (블록 승자·바닥·carry·승격) — v1 은 shadow 전용

**상태 변수**: shadow 정책 집합 · 결정 기록 · 선택 인플레 계기.

**정책 가족** (사전등록 v1 — 사후 추가는 새 가족이며 새 N)

| 정책 | 규칙 | 역할 |
|---|---|---|
| π₀ (live) | `.metric(a, by)` — by 는 **격자 `blocks[].select_winner_by` 를 실제로 읽는다**(P1-05, 죽은 선언 해소). 값이 러너 리터럴과 같아 비트 동일[확인] | 현행 |
| π_asof | 같은 지표의 τ_D as-of 쌍둥이 | 선택 인플레 계측(현행이 as-of 였다면) |
| π_S | argmin as-of S. 칸 값은 EB 축소 | D-F 게이트 축 정합 |
| π_ladder | π_S + 사다리 띠: max − κ·σ 이내를 동률로 보고, 먼저 측정된 칸 → 작은 n 으로 깬다(Blum & Hardt 2015) | 잡음 증분 추격 억제 |
| π_R | 자격 후보 중 균등 무작위(시드 고정) | 음성 대조(Li SSRN 7190318) |

- carry·승격 shadow
  - `rf_carry_decide` 는 P(u_winner > 0) ≥ `carry_p` 로 판정한다.
  - 승격 shadow 는 P(u_child > δ) < `promote_p_min` 이면 "승격 안 함" 이다.
  - 둘 다 기록만 하고, 하드 규칙으로 쓰지 않는다(플랜 '하지 말 것' 5).
- B6·B7: `phase_control`·`success_criterion` 을 순수 술어로 두고 shadow 로 병기한다(P1-05).
- 승자 요약에는 Andrews-Kitagawa-McCloskey 조건부 구간을 병기한다(서술 교정 · 등급 불변 · O3).

**live 전환 제한 — 판정식이 존재하지 않는 결정은 기계 권한 밖이다**
- 격자 live 선택을 전기간에서 as-of 로 바꾸는 일은 리플레이로 판정할 수 없다. as-of 선택기는 as-of 채점에서 당연히 이기고, 전기간 argmax 에는 깨끗한 평가 창이 없다.
- 그래서 이 전환은 09-23 규율 (A)와 D-E 사이의 원칙 결정이다 → §2 Q①·Q⑤.
- ★격자 선택을 as-of 로 옮기는 것은 SEL-DISCIPLINE 이 **기각한 선택지 (B)**(선택만 anchored IS, 채점은 전기간)를 다시 올리는 일이다. 안건에 그렇게 명기한다 [헌R4].
- 결정 전까지 선택 층은 shadow 와 결정 기록뿐이다.

**입력**: 후보 자격 술어(`rf_candidates_keep`·`RF_ROLE_CHECKS`·`rf_adversary_ok` — **불변**) 통과 칸의 as-of 뷰.
- **결손 규칙**: 후보 중 as-of 뷰가 하나라도 없으면 그 결정의 shadow 는 `asof_view_missing` 로 기록한다. 한 argmax 에 두 창을 섞지 않는다.

**파라미터** (`organic.select.*` — 분류와 근거 = 부록 D)

| 키 | 초기값 | 분류 |
|---|---|---|
| `shadow_policies` | [π_asof, π_S, π_ladder, π_R] | 사전등록 가족 |
| `ladder_kappa` | = `budget.delta_sigma` | 도출. D-F 잡음 배수 하나로 통일해 별도 판단값을 두지 않는다 |
| `carry_p` | 0.8 | 플랜(PR-L2 성공 기준 P(Δ>0) ≥ 0.8) |
| `promote_p_min` | 0.2 | 판단 → A2-c |
| `report_winner_ci` | "akm_hybrid" | 문헌(Andrews et al. 2019) |
| `live_allowed` | false | 도출(결정 레지스터). ★코드 가드는 **조건부**다: "ORGANIC-DE 가 resolved 이고, 그 결정이 선택 층 live 를 허용하는가"를 확인한다. v1 의 영구 불가 가드는 선택 기준 자율 결정을 영구히 덮어버리므로 폐기한다 [헌R4] |

**러너 개입 지점** (O3 · pi0 비트 동일)
- `:683-684`: `v <- rf_select_value(cand, by, role = paste0("winner_", bid), pol = .OST$select)` — **순위 벡터**를 낸다. pi0 이면 `.metric` 과 identical.
- `:697`: `attr(out, "best_val") <- .metric(w, by)` — carry 게이트 척도(PORT_t)를 순위 값과 분리한다(심사3).
- `:774-776`·`:781`: 바닥에도 같은 분리를 적용한다(`.wbest_val <- .metric(.w0, "port_t")`).
- 결정 기록: `.winner_of`·바닥 직후 `rf_record_decision(kind = block_winner/floor, shadow = …)`(P1-05 배선).

---

### 1.4 구조 층 (블록 상태)

**상태 변수**: `state.structure{version, blocks[b] = {state ∈ {full, reduced, diag, dormant}, since, decision_id}}` · `state.entry_pin[BID] = structure_version` · `state.epoch.base_program_sha`.

**결정 규칙**
- 프로그램 수준 블록 상태는 모든 신규 entry 의 n_cap 상한으로 작용한다. 예산 층은 그 안에서 entry 별로 배분한다.
- **축소·진단화·휴면 조건**: n_eff,b ≥ `n_min_block_evidence` ∧ 계보 ≥ `r_min_block` ∧ P̂_b < `block_dormant_p` 가 `consecutive_windows` 연속.
  - 전이: full → reduced(n_min) → diag(B3 = 1칸) 또는 dormant(0칸). 한 번에 한 단계다.
- **B1·B4 는 휴면 불가다.** B1 은 선두, B4 는 결합(09-04 사고)이다.
  - B4 는 불변식 ③ 으로 휴면 블록 참조 칸만 빠진다. 단 전 승자 결합 칸은 불변식 ⑤ 로 보존한다.
- **B7 = 사전등록 전용 블록(prereg_only)**
  - 유기체는 B7 에 칸을 배분하지 않는다. 칸은 PR-L2 경로가 연다.
  - ★이 지정은 **G4 를 통과하기 전까지 pi0** 다. 즉 B08 로 수리된 현행 격자의 B7 칸은 일반 entry 에서 그대로 측정된다.
  - prereg_only 는 "유기체가 B7 을 줄이거나 늘리지 않는다"는 뜻이다. live 구조 변경이 아니다 [헌R9].
- **B5** 는 유기체 관리 밖이다(D-G 이행 항목 · Q②′). as-of 적대검증(O4)이 생긴 뒤 편입 여부를 다시 상정한다.
- **부활**: 1.2 의 부활 어휘 4종과 같다.
- **entry 는 개설 시 구조 판을 고정**하고 끝까지 간다. 롤백·변경은 새 entry 에만 효력이 있다.
- **(O4 선택) 템플릿 인스턴스화**
  - 사람이 구현·검사해 `06_Registry/block_templates.json` 에 등재하고, 사전등록 판정이 confirmed 인 템플릿만 쓴다. 예: PR-L1 cap_core, PR-L2 B7 as-of.
  - 템플릿은 **기존 블록 id 안의 칸**만 정의할 수 있다. 새 블록이나 새 축이 필요한 템플릿은 격자 편집(사람)의 몫이다. 그래서 아래 금지 목록과 충돌하지 않는다 [헌R9].
  - 칸을 늘리는 결정이라서 **canary** 로만 시작한다(§3.4).
- **금지**: 블록 순서(09-18 NO-GO) · 새 블록·축 · 블록 의존 변경 · G2 pass 0 동안 B5 확대 · `fixed_axes`·`graduation`·`execution` 편집 · 코드 생성.

**봉쇄**
- `reinforce_program.json` 은 **쓰지 않는다**(fixed_axes 동거).
- epoch 개시 때 기저 sha 와 `sha(fixed_axes)` 를 고정한다. 유기체 tick 과 `rf_organic_cells` 는 매번 `identical(PROG$fixed_axes, pinned)` 를 단언하고, 실패하면 K1 이다.
- 사람이 격자를 합법적으로 고치면 sha 가 바뀐다 → pi0 로 돌아가 **epoch 재개시**(config `organic.epoch.id` 증가 — 사람)를 기다린다.

**파라미터** (`organic.structure.*` — 분류와 근거 = 부록 D)

| 키 | 초기값 | 분류 |
|---|---|---|
| `block_dormant_p` | = `space.dormant_p` | 도출(관례 α 하나로 통일) |
| `n_min_block_evidence` | = `evidence.min_cells_block` | 도출(검정력 규칙 · 부록 D) |
| `r_min_block` | = `evidence.min_lineages_block` | 판단 → A2-c |
| `consecutive_windows` | 2(주) | 판단 → A2-c |
| `n_diag` | {B3: 1} | 감사 ④ |
| `never_dormant` · `prereg_only` | [B1, B4] · [B7](G4 전에는 pi0) | 09-04 지시 · PR-L2 |
| `max_live_changes_per_week` | pol_cfg `weekly_activation_max` | 도출 |

**개입 지점**: 1.1 의 `rf_organic_cells` 와 같다(추가 0줄).

---

### 1.5 C-트랙 — 워크포워드 합성 (유기체 밖 · 별도 사전등록 리서치 단위 · O4 진단)

wf 의 확약 층은 D-E 문언을 그대로 만족하는 유일한 A 객체다(정적 칸 명제, §2.1). 다만 두 가지 이유로 유기체 live 경로에서 떼어 낸다(심사2·3).

**치명 결함 수리**
- AAC 필터는 기록된 전기간 선택(k*_n)과 as-of 쌍둥이의 일치로 후보를 거른다. 이는 "조상의 우위가 τ 이후에도 지속된 계보"로 조건화하는 것이라 누출이다.
- 그래서 **허용 집합 A_k = H2-free ∧ H1clean ∧ 표식 청정 ∧ 현행 규약 ∧ 월간 집행**으로 둔다.
  - H2-free = 조상에 성과 선정 노드가 없는 칸(기저 실투형 B1_0 · 뿌리 as-of 규칙 칸).
  - H1clean = 설계 출처 ∈ {rule_asof, literature, llm_blinded(P1-09 as-of 재료 뒤)}.
- AAC 는 **A 서류의 진단 곡선**으로만 쓴다(P1-04).
- 섭동 검사는 **메타데이터 포함 섭동**이다. τ_k 이후 수익과 함께 기록된 선택·승격 여부를 재계산한 판으로 검사한다.

**구조상 2계층이다**
- 기저 전략들 사이의 τ_k as-of 선택은 전략 로테이션과 같은 구조다.
- 그래서 C-트랙은 `strategy-rotation` SKILL 의 리서치 1단위로 사전등록한다. 유기체는 as-of 뷰와 π_R 대조만 공급한다.

**MinBTL 재산출(심사2)**
- min_is = MinBTL(|A_k|, SR 목표)을 τ_k 마다 계산한다(Bailey et al. 2014).
- 예: |A_k|=50·SR 1 이면 약 5.2년, 300 이면 약 8.4년[계산]. 가용 이력이 부족한 τ_k 는 미결이다.

**측정**
- 이어 붙인 보유 → `rfh_*` 부품 → 하네스(close_t1·15bps·교체일 Δw 비용) → `build_bt_result` → audit → `essence_score(selection_type="sweep", n_trials = N_policy_family)`.
- 산출은 `stage_artifacts/wf_composite/<id>/` 에 쓴다. 계약 파일은 컨트롤러와 분리한다(심사1 내부 모순 수리).

**지위**
- A·Judge·BOOK 대상 여부는 안건 A4 다. 결정 전에는 보고만 한다.
- (ii) 이행의 비용·효과 사실표(bayes O4 이음 NAV 진단)를 겸한다.

**2계층 경계** [완R2]
- L2 원장(`reinforce_ledger_l2.json`)과 `rf_l2_auto` 는 유기체 범위 밖이다. 유기체는 둘 다 읽지도 쓰지도 않는다.
- 2계층은 FR-REMEASURE-PREREG 에 따라 정지 중이다(`l2_auto.enabled=false`, 입력 정화 뒤 사전등록 재측정까지). C-트랙도 그 뒤에 착수한다.
- C-트랙 측정의 Calmar 는 CALMAR-FREQ-DAILY 에 따라 **일간 bt_result** 로 산출한다. 월간 값은 진단으로 병기한다.
- FR 재측정의 전제인 "D-E 입장 경로 라벨 as-of 재산출"과 C-트랙 허용 집합(H2-free ∧ H1clean) 도출은 같은 계보 도출 함수(P0-14)를 공유한다.

---

## 2. ★D-E 정합 — 적응 층의 선정 통계는 C1/C14 에 걸리는가

### 2.1 무엇이 충돌하는가 · B08 선례 · 정적 칸 명제

- **D-E**(pit.md C1 · 09-23 확정): "평가 창 결과를 소비하는 자동 선정 규칙도 C1/C14 … 팩터·arm·슬리브를 전기간 IC·ic_bad·상관으로 고르면 시점 t 보유를 미래 통계로 정한 것. 선정 통계는 as-of 로만. 사람이 문헌 근거로 고르는 것은 해당 없음."
- **09-23 선택 규율 (A)**(SEL-DISCIPLINE): 격자 선택은 sweep 정직 표기 + 강건 선택 + 다중검정 서류로 하고, **전기간 데이터를 유지**한다. 기각된 (B) 는 "선택만 anchored IS(앞 55%), 채점은 전기간"이었다.
- **ORGANIC**(09-25): 선택 기준까지 기계가 정한다. 가드는 "as-of 정보만"이다.
- **이후 결정**
  - D-E-B5-MATERIALS: 교차 entry 수치는 D-E 소재다. 수치를 가리고 순위를 제거한다. 자기 entry 측정표는 유지한다.
  - D-E-V6-CONDITIONAL-IC: 전기간 조건부 IC 행렬로 선정하지 않는다. 새 규칙은 새 칸에만 적용하고, 과거 칸은 표식만 단다(재측정 금지).
- 현 러너의 자동 선정 5곳(승자·바닥·carry·승격 best·연장)은 전부 전기간 essence argmax 다[확인]. B2·B5 승자를 고르는 일은 곧 arm 선정이다.

**B08 선례 — v1 정정** [헌M2]
- v1 은 P0-08(B08)을 "성과를 쓰지 않는 선정"이라고 적었다. 틀렸다.
- B08 은 **성과 통계(IC)를 쓰되, 보유 시작일(`fixed_axes.start_date`) 이전 워밍업 창에서만** 계산한다(`rf_factor_arms.R::.rff_asof`)[확인].
- B7 `selection_asof` 도 같은 규칙이다: "셀 fixed_axes.start_date — 워밍업 창 1회 고정 = 정적 슬리브 불변식".
- B08 이 세운 기준은 이것이다: **정적 칸의 구성 결정은 보유 시작일 as-of 로 한다.**

**정적 칸 명제 (wf · 정정판)**
- 칸 c 의 보유 경로는 [2005-01-01, 끝]이다. c 의 구성이 다른 칸들의 **성과**로 골라졌고 그 통계가 τ 까지의 수익을 썼다면, t < τ 시점의 보유는 t 이후 통계로 정해진 것이다.
- ⇒ D-E 문언상 청정한 정적 칸의 형태는 둘뿐이다.
  - (a) **보유 시작일 이전 창의 통계로만** 고른 선정(B08)
  - (b) 시간에 따라 구성이 바뀌는 전략(워크포워드)
- 측정된 칸들의 성과는 2005 이후에만 있다. 그래서 (a) 기준으로는 측정 칸의 성과를 소비하는 **어떤 자동 결정도** 정적 칸의 구성을 청정하게 정할 수 없다.
- 따라서 τ_D(≈2016-11)로 arm 휴면·블록 축소를 하면, 2005~2016 성과로 2005 년부터의 보유 후보를 거르는 셈이 된다. **B08 기준으로 보면 τ_D 는 완화다.**
- v1 의 "D-E·P0-08 은 완화되지 않는다"는 사실이 아니다. 이 점을 안건 본문에 그대로 적는다.

### 2.2 선정 유형 분류

| 유형 | 정의 | 예 | 보유에 들어가나 | N 계상 |
|---|---|---|---|---|
| H1 | 칸 구성 **안에서** 데이터 통계로 고른다(측정 전 스크린) | B1 IC 픽커(22632 계보) · B7 ic_bad(구판) · pit.md V6 의 전기간 조건부 IC 행렬 우선(`.cache/conditional_ic_matrix.csv` — D-E-V6 로 개정 결정) · LLM 이 툴로 전기간 IC 를 읽고 고른 경우 | 예 | 아니오(숨은 시행) |
| H2 | 측정된 칸들 **사이에서** 성과로 골라 다음 칸에 심는다 | 블록 승자 · 누적 바닥 · carry · 승격 best | 예(자식 칸) | 예(계보 N) |
| H2-LLM | LLM 이 측정 칸들의 **전기간 성과 서술**을 재료로 다음 구성을 설계한다. 재료는 둘로 나뉜다: **자기 entry 측정표**(기결정 — 강화 루프 자체라 유지)와 **교차 entry 수치**(D-E-B5-MATERIALS — D-E 소재라 가림) | B1·B2·B3·B5 설계 레인 | 예 | 설계된 칸은 N 에 들어가지만, 설계 선택 자체는 들어가지 않는다 |
| R | **무엇을 잴지** 정한다 | 예산 절단 · 휴면 · 쿼터 · 조기 소진 · D-G B5 축소 | 아니오 | 간접(후보 집합을 바꿔 최종 선택 편향을 키운다) |
| C | 구성이 시간에 따라 바뀐다(τ_k 마다 ≤τ_k 정보로 선택) | C-트랙 합성 | 예 — ≤τ_k 정보만 | 정책 가족 N |

노출 규모:
- H2 조상 위에 선 칸: 1,030/1,238(83%)[심사 실측(wf)]
- H1 표식: 60 + 승계 501
- H2-LLM
  - 26 entry 의 표식 청정 칸 501[재집계]
  - B1 LLM 칸 가운데 표식 없는 칸 159/247[심사 실측]
  - 교차 entry 절이 있는 B1 재료 28/29 파일[재집계] — 칸 수는 P0-14 가 파일별 수치 포함 여부로 도출한다

### 2.3 해석 선택지

- **(i) 회계형**
  - C1 은 H1 만이다. H2·H2-LLM·R·유기체는 전기간 통계를 써도 되고, 대가는 N·DSR·PBO 로 치른다.
  - ORGANIC 의 "as-of" 는 연구 시점으로 읽는다.
- **(ii) 엄격 WF형**
  - 성과를 소비하는 모든 자동 선정(H1·H2·H2-LLM·R)이 C1 이다.
  - 기계 결정은 τ_k 워크포워드로만 한다. A 대상은 H2-free 칸과 C-트랙 합성뿐이다.
  - 격자 live 선택을 as-of 로 전환해야 하고, `selection_path_full_sample` 보류 코드를 켠다.
- **(iii) 경계형 — 권고**
  - H1 = C1: 현행을 유지한다. LLM 이 툴을 거쳐 전기간 IC 를 읽고 고른 경우도 포함한다.
  - H2(격자 live) = 09-23 (A) 의 다중검정 영역이다. A 서류에 AAC 진단 곡선, 선택 경로 라벨, retention 선택편향 표기를 싣는다.
  - H2-LLM: 자기 entry 분은 기결정(유지)이다. 교차 entry 수치에 노출된 과거 칸은 Q④ 로 다룬다.
  - **유기체(R + 선택 shadow)는 시장 시점 as-of τ_D(재도출·고정) + 연구 시점 as-of 로 제한한다.** 단 τ_D 는 B08 보다 약한 as-of 이고 기계 입력에만 걸린 holdout 이다. 두 점 모두 예외 요청으로 명시한다(Q③).
  - (iii) 의 논거:
    - R 결정은 보유를 구성하지 않고, 무엇을 잴지를 줄인다.
    - 최종 보유를 정하는 격자 선택(H2)은 이미 전기간 argmax 를 다중검정으로 허용받았다(09-23 A).
    - (iii) 은 그보다 **정보가 적은**(τ_D 이하) R 결정을 같은 회계 틀로 허용하는 해석이다.
  - 유기체는 격자 live 선택을 바꾸지 않는다. 바꾸려면 Q⑤ 의 별도 결정이 필요하다.
  - (ii) 로 가는 길은 C-트랙과 스위치 하나로 남긴다.
    - 스위치는 `a_eligibility_gate.json::holds.selection_path_full_sample` 이고, 기본 off 이며 도훈 소유다.
    - `RF_A_HOLD_CODES` 는 코드 집합 일치를 요구하므로, 코드 추가와 설정 추가는 한 커밋이어야 한다.
- **(iv) 경계형 + τ_latest**
  - (iii) 과 같되 유기체가 전기간(τ_latest)을 본다.
  - 비권고다. τ_latest 이후 데이터가 없어 섭동 검사가 발화할 수 없으므로 as-of 가드가 공허해진다. 또 유기체가 평가 창을 목적함수로 삼게 된다(Dwork et al. 2015 의 적응 재사용).
- **τ 선택지(Q③)는 해석과 따로 고른다**: (a) τ_D · (b) τ_latest · (c) τ_k 워크포워드 · **(d) start_date 워밍업 as-of — B08 정합** [헌M2]. (iii) 에 (d) 를 결합하면 성과를 소비하는 기계 결정은 0 이 된다. 이때 유기체는 회계·provenance·구조 사유 규칙·shadow 기록 층으로 축소된다.

### 2.4 일관성 표

| 항목 | (i) 회계형 | (ii) 엄격 WF형 | **(iii) + (a) τ_D (권고)** | (iii) + (d) B08 정합 | (iv) τ_latest |
|---|---|---|---|---|---|
| 격자 승자·바닥(전기간 argmax) | 합법 · 계상 | C1 → as-of 전환 필요 | 합법(09-23 A) + 서류 감사 | 같음 | 합법 |
| carry · 승격 | 합법 | C1 | 합법 + 감사 | 같음 | 합법 |
| 22632 표식(전기간 IC 승계) | C1. 단 argmax 는 계상인데 IC 는 C1 이라, 둘을 가르는 근거가 '계상 여부'뿐이다 | C1 | C1(IC 는 평가 창을 소비하는 측정 전 스크린) | C1 | C1 |
| 교차 entry 노출 LLM 과거 칸 | 합법 | C1 | Q④(권고: A 보류 · 재측정 금지) | 같음 | 합법 |
| 유기체 예산·휴면·구조 | 전기간 자유 | τ_k as-of | τ_D as-of(**예외 요청**) | 성과 소비 0 · 구조 사유만 | 전기간 → 가드 공허 |
| 유기체 선택 가치 | 전기간 가능 | as-of live | shadow 만 | shadow 만 | 전기간 가능 |
| B08 선례(start_date as-of) 대비 | 완화 | 일관 | **완화**(τ_D > start_date) | 일관 | 완화 |
| lockbox 폐지 조항 대비 | 충돌 없음 | 충돌 없음(순차 창 = 워크포워드) | 기계 입력 holdout → **예외 요청** | 충돌 없음 | 충돌 없음 |
| D-G B5 축소(전기간 G2 입력) | 합법 | C1 | Q②′(권고: 고정 사람 규칙 예외) | Q②′ | 합법 |
| 현 원장 A 가능 풀 | 현행(표식 칸 제외) | 0 에서 재시작(1,030칸 A 불가) | 현행(표식 칸 제외) + Q④ 노출분 보류 | 같음 | 현행 |
| OOS retention 의 뜻 | 유기체가 최적화하므로 검정력을 잃는다 | 정직(IS 정의가 바뀜) | 유기체에 대해서는 정직, 격자 argmax 는 계상 대상 | 정직 | 오염 |
| 필요 인프라 | 서류(P1-04) | 이음 NAV 계약 · 보류 코드 · τ_k 뷰 | `asof_window.R` · as-of 배치 | 회계·provenance 만 | 없음 |
| 유기체의 운영 가치 | 높음(대가 = 누출) | 중간 | 중간('미결'이 가장 흔함) | 낮음(회계·구조 규칙) | 높음(대가 = 가드 공허) |

### 2.5 Q 권고 — (iii) + τ_D, 두 예외를 명시해 요청

1. 09-23 (A) 와 ORGANIC 의 "as-of" 를 살리면서 D-E 를 가장 적게 완화하는, **운영 가능한** 해석이다.
   - 단 v1 의 "D-E·P0-08 은 완화되지 않는다"는 철회한다. τ_D 는 B08 보다 약한 as-of 다.
2. 완화의 크기는 제한적이다.
   - (가) R 결정은 보유를 구성하지 않고 측정을 줄인다.
   - (나) 입력은 τ_D 이하의 정보뿐이다.
   - (다) 최종 보유를 정하는 격자 선택은 이미 전기간 다중검정으로 허용돼 있다. R 결정이 추가로 쓰는 정보는 그 부분집합이다.
   - (라) 결정이 소비한 증거를 N_program 으로 계상한다.
3. 유기체가 나아지는지를 정직하게 잴 수 있다. τ_D 이후 성적(외부 성적표)은 유기체가 한 번도 입력으로 쓰지 않은 창이다.
4. (d)(B08 정합)는 헌법상 가장 깨끗하지만 유기체를 회계·구조 규칙 층으로 축소한다.
   - 도훈이 B08 기준을 R 결정에도 적용한다고 보면 (d) 가 맞다.
   - 이 설계는 (d) 로 결정돼도 O0a·O0b·O1 산출이 그대로 쓰이게 짰다(§8.3 분기).
5. (ii) 는 A 대상의 정의를 바꾼다. C-트랙 진단을 본 뒤 다시 상정한다.

**잔여 위반 — 명시 수용 대상** (숨기지 않는다)
- ① 격자 live argmax 의 전기간 선정은 D-E 의 넓은 문언에 걸릴 수 있다. (iii) 은 이것을 "완전히 명세된 PIT 전략들 사이의 성과 선정 = 다중검정"으로 분류한다. 도훈이 확인해야 한다.
- ② 유기체는 [2005, τ_D] 구간의 보유 후보를 τ_D 이하의 성과로 거른다. B08 기준으로 완화다(위 2). N_program 으로 계상한다.
- ③ 연구 시점의 지식 오염은 어느 선택지로도 없앨 수 없다.
  - Q·도훈·LLM 은 2017~20 년 EW−CW 역전을 이미 안다.
  - 그래서 "틸트 중립 선호"를 유기체의 사전이나 효용에 넣는 것을 금지한다.
  - 이 지식은 사람의 사전등록(PR-L1: 반증 시도 라벨 + 2024-12 절단판)으로만 다룬다.
- ④ 증거 모집단(바닥·승격 계보)은 전기간 결정(pi0)으로 만들어졌다. 유기체는 그 위에서 as-of 로 배운다. 이 조건화는 제거할 수 없다고 표기하고, H2-free 부분집합으로 민감도를 보고한다.

**lockbox 폐지 조항 — 예외 요청 (v1 의 부정 선언 철회)** [헌M3]
- pit.md 원문: "lockbox / Frozen Alpha 제도는 완전히 폐지 … 전 에이전트·전 단계가 가용 데이터 전기간을 사용 … 반박 금지".
- τ_D 가 하는 일:
  - 기계의 자동 결정 입력에서 τ_D 이후를 뺀다.
  - 그 창의 성적은 사람만 본다.
  - 근거는 "겨냥하면 OOS retention 이 과적합 검정의 의미를 잃는다"는 **holdout 논거**다. 기능상 기계 입력에만 걸린 holdout 이다.
- v1 은 "lockbox 가 아니다"라고 선언하고 "D-E 적용으로 본다"고 논증했다. 그 논증 자체가 반박 금지 조항에 대한 반박이라서 철회한다.
- 최종판은 **예외 요청**으로만 상정한다.
  - 범위는 유기체의 자동 결정 입력뿐이다.
  - 사람·등급·Judge·BOOK·전략 구현·격자 선택은 전기간을 그대로 쓴다.
- 도훈이 예외를 거부하면: (b) τ_latest 는 가드가 공허해지므로 비권고다. 실질적인 대안은 (c) τ_k 워크포워드 또는 (d) start_date 다.

### 2.6 결정 안건 문안 — `ORGANIC-DE` (owner dohoon · 하나로 통합 상정)

> **ORGANIC-DE — 자동 선정(격자·유기체·설계 레인·사람 자동 규칙)과 pit.md C1(D-E)의 경계**
>
> **배경**
> - D-E 와 09-23 선택 규율 (A)가 같은 날 확정됐지만, 둘 사이의 경계가 명문화되지 않았다.
> - REINFORCE-ORGANIC-AUTONOMY 로 기계가 예산·arm·선택 기준·구조를 정하게 됐다.
> - 정적 칸 명제(정정판): 성과로 고른 정적 칸이 청정하려면 보유 시작일 이전 통계만 써야 한다(B08 기준).
> - 이후 결정: D-E-B5-MATERIALS(교차 entry 수치 가림 · 자기 entry 유지) · D-E-V6-CONDITIONAL-IC(새 규칙은 새 칸에 · 과거 칸은 표식만) · RUNNER-RESTART-AFTER-P0-14(유기체는 shadow 로 붙인다).
> - PIT 해석은 기계 권한 밖이다.
>
> **질문**
> - **Q①** 측정된 칸 사이의 성과 선정(격자 승자·바닥·carry·승격 = H2)은 다중검정(09-23 A)인가, C1 인가?
> - **Q②** 측정을 멈추는 결정(arm 휴면·블록 축소·조기 소진 = R)은 문언의 "arm 선정"에 해당하는가? 해당한다면 as-of 만 허용하는가, 아니면 금지하는가?
> - **Q②′ 고정 사람 규칙의 예외** — D-G 의 B5 축소와 overlay_propose 'dead 동안 정지'는 입력이 프로그램 G2 pass 수(전기간 적대검증 판정)다. D-E 의 면제 대상은 "사람이 문헌 근거로 고르는 것"뿐이라 문언상 여기에 해당하지 않는다.
>   - (α) 예외 인정: 사전에 고정된 단일 사람 규칙이다. 정책 탐색이 없으므로 적응 재사용도 없다. 측정을 줄이는 방향이다. N_program 에 계상한다.
>   - (β) as-of 적대검증(adv_asof, O4) 뒤로 미룬다.
>   - (γ) 성과를 소비하지 않는 분기(overlay_propose G1 경유)만 이행한다.
> - **Q③** 기계 결정의 시장 τ 는 무엇으로 하는가?
>   - (a) τ_D 고정 — **B08 보다 약한 as-of 이고, 기계 입력에만 걸린 holdout 이다. lockbox 폐지 조항의 예외 요청이다.**
>   - (b) τ_latest
>   - (c) τ_k 워크포워드
>   - **(d) start_date 워밍업 as-of — B08 정합(성과 소비형 기계 결정 0)**
> - **Q④** 가림 이전 재료의 **교차 entry 수치**에 노출된 채 설계된 과거 칸은 어떻게 다루는가?
>   - (a) C1 — verdict `possible` 로 A 보류, 재측정 금지. D-E-V6 선례("새 규칙은 새 칸에, 과거 칸은 표식만")를 따른다.
>   - (b) H2 — 라벨 + 다중검정.
>   - 자기 entry 측정표 노출은 기결정(유지)이라 묻지 않는다.
>   - LLM 이 툴을 거쳐 전기간 IC 를 읽고 고른 경우는 이미 D-E 문언상 C1 이다(확인 요청).
> - **Q⑤** 격자 live 선택을 as-of 로 옮길지(선택 층 live), 그리고 (ii) 전환 스위치 `selection_path_full_sample` 의 일몰 조건은 무엇인가? ★이것은 SEL-DISCIPLINE 이 기각한 (B) 를 다시 올리는 일이다.
>
> **선택지**: 해석 (i) 회계형 / (ii) 엄격 WF형 / (iii) 경계형 / (iv) 경계형 + τ_latest. τ 는 Q③ 의 (a)~(d) 중에서 고른다.
>
> **Q 권고**: **(iii) + Q③ (a) τ_D — 두 예외(B08 대비 완화 · lockbox holdout)를 명시해 요청**
> - Q①: 다중검정 + 서류 감사.
> - Q②: τ_D as-of 로 한정해 허용한다(N_program 계상).
> - Q②′: (α) 예외 인정. 규칙이 하나로 고정돼 있어(정책 탐색 없음) Dwork 식 적응 재사용이 없고, 결정 방향이 측정 축소다. 유기체의 적응 정책 탐색과 구별되는 지점이 바로 여기다.
> - Q③: (a). 도훈이 B08 기준을 R 결정에도 적용한다면 (d).
> - Q④: (a). D-E-B5-MATERIALS 가 교차 entry 수치를 D-E 소재로 분류한 것과, D-E-V6 의 '과거 칸은 표식만' 선례에 일관된다.
> - Q⑤: 선택 층 live 는 C-트랙 첫 성적표 뒤에 다시 상정한다.
> - 재상정 시점: O2 첫 판정과 첫 A 후보 중 먼저 오는 때.
>
> **결정 전 기본값**
> - 유기체는 **live 0, shadow 만** 돈다(RUNNER-RESTART 와 같다).
> - 유기체 밖에서 배포할 수 있는 것은 D-G 의 성과 비소비 분기뿐이다: FIFO · 레인 순서 · 세대당 신규 논문 · overlay_propose G1 경유 · `rf_budget_auto` 가산 차단. B5 축소와 'dead 동안 정지'는 dg_shadow 로만 돈다.
> - 격자 live 선택은 pi0 다.
> - P0-14 는 H1 계보 도출 + 교차 entry 노출 도출(파일별) + 유기체 시행 로그 태그 판독으로 구현한다.
> - 교차 entry 노출이 도출된 칸에만 verdict `possible` 을 단다(A 보류 · fail-closed · 현재 A 가 0 이라 비용도 0). 표식 writer 는 P0-14 소관이고, 유기체가 아니다.
>
> **막는 것**: 유기체 O2 live · 선택 층 live · C-트랙 A 발행 · D-G B5 축소 live.

---

## 3. 가드 8종

### 3.1 가드 구현

| 가드 | 구현(파일·함수) | 검사 — 양성 대조 / 위반 주입 / 돌연변이 |
|---|---|---|
| **G1 시행 회계** | **정본**: `06_Registry/rf_trial_log.jsonl`(P1-02). **현재 없으므로 O0a 에서 선행 신설**하고, 생산자 7곳 배선까지 포함한다 [완M6]. writer 는 `reinforce_ledger.R::rf_trial_log_append`. <br>**kind**: organic_proposal · organic_prediction · organic_shadow · organic_live · organic_reject · organic_policy_transition · organic_kill · organic_rollback · organic_measure_tag. <br>**write-ahead**: 효과(state 쓰기)보다 먼저 쓴다. 필드 = policy@sha · layer · decision_id · view_md5 · τ_D · n_candidates · chosen · mode · counted_in{lineage, program, policy}. <br>**칸 태그**: 유기체 live 정책 아래 형성된 칸은 `organic_measure_tag{cell_key, policy@sha, decision_ids}` 로 태그한다. `vintage_flags` 에는 쓰지 않는다. flags 가 `*` 라서 A 가 자동 보류되기 때문이다. <br>★**A 관문 도달** [헌M5]: P0-14 계보 도출이 이 태그를 읽는다. `a_eligibility_gate.json` 에는 새 보류 코드 `organic_policy_selected` 를 둔다(기본 **비활성**, 도훈 소유). ORGANIC-DE 가 R 이나 선택을 C1 으로 판정하면 이 코드를 켠다. `RF_A_HOLD_CODES` 집합 일치 규칙 때문에 코드와 설정은 한 커밋으로 넣는다 | (+) state 효과 전부에 선행 레코드가 있다(조인 100%). <br>(−) 레코드 없는 효과를 주입하면 K2. <br>(돌연변이) write-ahead 순서를 뒤집으면 red. <br>(+) 태그된 합성 칸에서 보류 코드를 켜면 A 보류, 끄면 통과(비트 동일). <br>N 이중 도출은 K2 참조 |
| **G2 as-of 만** | 원장·as-of 산출을 읽는 파일은 `rf_organic_ledger_adapter.R` **하나뿐**이다. 유일한 면제 파일이며 열 허용목록을 따른다(§1.0 d) [헌M6·완M3]. <br>**정적 파싱**: view·model·policy·replay 파일에서 `getParseData` 의 SYMBOL·SYMBOL_FUNCTION_CALL·STR_CONST 토큰을 **정확 일치**로 대조한다. 부분문자열로 대조하면 `upgrade`·`tier_graduation` 에서 오탐이 난다(완M3). <br>**금지 토큰**: `essence`·`authoritative_remeasure`·`essence_grade`·`grade`·`adversary`·`verdict`·`oos_retention`·`dsr`·`selection_accounting`·`selection_dossier`·`rf_load`·원장 파일명·`.ESSENCE_OOS_SPLITS` | **bt_result 수준 섭동**(심사1·2): 격리 루트 픽스처에서 τ_D 이후 수익을 교란하고, 파생 필드(전기간 essence·등급·적대검증 판정·표식)를 파이프라인대로 전부 재계산한 원장 사본으로 유기체를 돌린다. 결정 md5 가 불변이어야 한다. <br>(+) 어댑터에 `essence$calmar` 열을 추가한 돌연변이는 열 허용목록 검사에서 red. 결정 파일이 판정을 읽는 돌연변이는 토큰 검사 red + 결정 변화. <br>(+) 우회 3종(문자열 결합 · `do.call` · `eval(parse())`) 양성 대조. <br>연구 시점 섭동(r 이후 레코드 교란)에도 결정이 불변이어야 한다. <br>야간 자가 실행 = K3(실행 주체 §3.2) |
| **G3 자동 사전등록** | **최소 writer 를 O0a 에 신설한다**: `reinforcement/rf_prereg.R::rf_prereg_write`(덮어쓰기 거부 · 원자 쓰기 · 스키마 검사). P2-01 이 아직 없어서 v1 의 "재사용"은 성립하지 않았다 [헌M7·완M6]. <br>**저장소**: 플랜 P2-01 과 같은 **`06_Registry/prereg/`** 하나. `layer: "organic"` 필드로 구분하고, 저장소를 둘로 나누지 않는다. <br>**내용**: 가설 · 층 · 규칙·파라미터 sha · 1차/2차 지표 · 두 단 창(τ₀, τ_D) · 검정력 3종(ratio·기대 t·검정력) · 09-18 리플레이 사전확률(해당 정책형의 discovery·unreachable 기술값) · 성공/실패 · 멈춤 · `hypothesis_index lookup` 첨부. <br>파라미터가 바뀌면 새 sha 다 | (+) 등록하면 shadow 에 진입한다. <br>(−) 같은 id 재기록 거부 · 사전등록 없는 정책의 shadow 진입 거부 · 검정력 ratio < `power_min_ratio` 인 정책은 '미결 전용'. <br>(돌연변이) 거부 분기를 지우면 red. <br>P2-01 을 본 배포할 때는 이 writer 를 확장한다(두 번째 writer 금지) |
| **G4 shadow→리플레이→live** | `axiom/replay/policy_state.R::pol_transition(state, st, cfg, env = list(rf_policy_off = …, unattended = .organic_auto_live_ok(cfg)))`. <br>`.organic_auto_live_ok` 는 두 조건이 모두 참일 때만 TRUE 다 [헌M8]: config `organic.auto_live = true`, 그리고 `organic.auto_live_decision_id` 가 도훈의 resolved 결정(G7 ③ 증거 규칙)을 가리킬 것. <br>전역 `QVEST_POLICY_UNATTENDED` 는 건드리지 않는다. <br>undo 문자열은 axiom 쪽 `promote.R::deactivate_policy` 대신 `rf_organic_rollback(policy@sha)` 를 가리키게 한다 [헌R6]. <br>**채점 = 09-18 리플레이 엔진 어댑터** `rf_organic_replay.R` [완M2]: 엔진 `04_Research/meta/axiom_replay/R/replay_engine.R` 을 source 만 한다. 세계는 close_t1 원장으로 재빌드하고, 점수 함수만 as-of (τ₀, τ_D] S 로 바꾼다 | 판정식은 §3.4. <br>(+) 개선을 심은 합성 정책은 live 에 도달한다. <br>(−) π_R 은 탈락한다. 레버 라벨 순열 플라시보에서는 효과가 사라져야 한다. <br>엔진 양성 대조를 재실행한다(post_0904 π₀ 재현 ≥ 사전등록 기준). <br>`test_policy_auto_live_rule.R` 회귀 |
| **G5 킬스위치** | **사람 스위치**: `organic.enabled` · `organic.layers.<층>.mode` · env `QVEST_RF_ORGANIC=off`. <br>**기계 자기 정지**: `state.killed{flag, code, at}`. 기계는 정지만 할 수 있다. <br>**해제 = 별도 토큰** `organic.kill.release{decision_id, at}`. decision_id 가 도훈의 resolved 결정(G7 ③ 증거 규칙)을 가리키고 `at` 이 킬 시각 뒤일 때만 tick 이 해제로 인정한다. <br>v1 의 `epoch.id` 증가 해제는 폐기한다. 해제할 때마다 τ_D 재도출과 N 재계상이 강제되기 때문이다 [완M8·헌M8] | K0~K9 조건마다 합성 열화 주입 픽스처 1개로 발화를 실증한다. <br>발화 뒤 러너 결정은 pi0 와 비트 동일이어야 한다(최근 tick 입력 재생). <br>(−) 기계 문맥에서 release 쓰기 → 거부. 증거 규칙을 통과하지 못하는 결정 id 를 참조 → 거부 |
| **G6 롤백** | `06_Registry/organic/actions.jsonl`(append-only · {decision_id, at, layer, target_pointer, before, after, policy@sha, trial_ref}). `rf_organic_rollback(decision_id \| policy@sha)` 가 state 포인터를 되돌린다. <br>★**러너가 실현한 효과는 state 롤백으로 되돌릴 수 없다**[헌M10]. 절단 → 격자 소진 → `rf_exhaust_entry` → 승격·다음 논문으로 이어지기 때문이다. <br>그래서 **사람 호출 writer `reinforce_ledger.R::rf_reopen_entry(base_id, reason, decision_id)`** 를 신설한다. <br>• 원장 claim 아래에서 entry 를 exhausted → active 로 되돌리고 `reopened{at, reason, decision_id}` 를 남긴다. <br>• 되살린 entry 는 롤백된 절단 이전의 계획으로 나머지 칸을 잰다. <br>• 이미 개시된 승격 자식과 다음 논문은 되돌리지 않는다(별개의 사실이다). <br>유기체는 이 함수를 부르지 않는다(원장 쓰기 금지). 롤백이 소진된 entry 에 걸리면 `reopen_required` 경보(`[무인]`)만 낸다 | (+) 적용 → 롤백 → `state.json` 대상 포인터의 md5 가 적용 전과 같다. <br>(+) 절단으로 소진된 합성 entry 에 `rf_reopen_entry` 를 호출하면 다음 tick 이 잘렸던 칸을 배치한다. 두 번 호출해도 결과가 같다(멱등). <br>(−) 원장·측정 칸을 건드리는 롤백 시도 → 거부. 유기체 문맥에서 `rf_reopen_entry` 호출 → stop |
| **G7 결정 레지스터 자동 기록** | 아래 §3.1.1 | 아래 |
| **G8 주간 보고** | `rf_organic_weekly.R` → `tg_agent_brief()`(단일 진입). 표제는 `[1계층·강화] 유기적 강화 주간 — <ISO 주차>`. qvest-telegram SKILL 의 5섹션 양식과 원칙 9(실측 수치 보고에는 차트 첨부)를 따른다 [헌R8·완R4]. <br>**트리거** [헌M12]: 기존 tick 의 idle 분기에서 두 조건이 모두 참일 때 1회 보낸다. <br>• 요일 = `organic.report.weekday_source`(주간 Cleaner 스윕 토 09:00 직후 첫 tick) <br>• 이번 ISO 주차에 아직 보내지 않음 <br>멱등 표식은 `06_Registry/organic/report_sent/<ISO주차>` 다 | 드라이런 `QVEST_TG_DRY_RUN=1` 에서 본문 ≤ `organic.report.max_chars`. <br>섹션을 빼는 돌연변이는 red. <br>발신기 formals 대조. `ok=FALSE` 도 실패로 읽는다. <br>같은 주 두 번째 tick 에서는 보내지 않는다(멱등) |

#### 3.1.1 G7 결정 레지스터 자동 기록 (재설계) [헌M9·M8·완M4]

**기록은 두 층이다**
- 상세: 기계의 모든 결정은 `06_Registry/organic/decisions.jsonl` 에 쓴다(append-only · `rfo_write` 경유).
- 레지스터: `decision_register.json` 에는 **전이 단위 포인터 행**만 쓴다.
  - scope 허용목록 {organic_policy_transition, organic_kill, organic_rollback, organic_structure_change} 에 해당하는 사건 1건당 1행이고, 본문은 jsonl 을 가리키는 포인터다.
  - 주당 상한 `organic.register.max_rows_per_week` = pol_cfg `weekly_activation_max` + K 발화·롤백 건수(사건 기반).
  - 상한을 넘는 분은 jsonl 에만 두고, 레지스터에는 "외 n건" 포인터 1행만 남긴다 [완R5].

**writer**: `reinforce_ledger.R::dr_record_machine(kind, summary, evidence_ptr, undo)` 를 신설한다.
- 레지스터 계약 주석(`:875`·`:916` "writer 는 dr_open/dr_resolve 뿐")을 세 번째 writer 가 있다는 내용으로 개정한다.
- 필드
  - owner = decided_by = `"machine:organic"` 리터럴
  - status = `"resolved"`(DR_STATUS_ENUM)
  - `dr_load` 가 요구하는 전 필드를 채운다: title · options=[] · recommendation · default_until_decided · blocks=[] · source · decision · decided_at · note · registered_at · recorded_by · evidence
  - 구분 필드 `record_class: "machine"`
- authority 대조: REINFORCE-ORGANIC-AUTONOMY 가 resolved 인지 확인한다. 금지 scope(tier_graduation · fixed_axes · pit · book · a_eligibility · D-* 참조)는 거부한다.

**id 네임스페이스**
- 형식: `M-ORG-<yyyymmddTHHMMSSmmm>-<seq>-<payload hash6>`.
- `dr_open` 은 `M-ORG-` 접두 id 를 거부한다.
- 쓰기 전에 중복을 검사한다. 중복 id 가 생기면 `dr_load` 가 stop 해서(`:934`) 부팅 Director 줄과 모든 `dr_*` 호출이 함께 죽기 때문이다.

**잠금 + CAS**
- `dr_open`·`dr_resolve`·`dr_record_machine` 세 writer 가 공용 claim 하나를 쥔다: `06_Registry/.decision_register.claim`. 구현은 원장 claim(`.rf_ledger_claim`)과 같은 패턴이다.
- 적재할 때 md5 를 기억했다가 쓰기 직전에 다시 대조한다. 달라졌으면 쓰지 않고 재시도한다.
- 지금은 잠금이 없어서, 무인 기계 쓰기와 세션 쓰기가 겹치면 도훈 결정 1건이 조용히 사라질 수 있다.

**기계 쓰기 전후 대조**: 쓰기 전후로 기존 항목 전부가 identical 하고 새 행 1개만 늘어야 한다. 아니면 되돌리고 K2 를 낸다.

**자기승인 봉쇄**
- ① `dr_open`/`dr_resolve` 는 `QVEST_ORGANIC_CTX=1` **또는 `QVEST_UNATTENDED_LANE=1`** 문맥에서 무조건 stop 한다.
  - 다른 무인 LLM 레인도 Rscript 로 결정을 resolve 할 수 있었기 때문이다.
  - 운영 트리의 호출처는 부팅 1곳뿐이라 기존 동작은 깨지지 않는다[확인] [헌M8].
- ② 유기체 파일에 `dr_open`/`dr_resolve`·`rf_reopen_entry` 토큰이 0 개여야 한다(정적 파싱).
- ③ **참조 결정 증거 규칙**: auto_live·킬 해제·live 게이트가 참조하는 도훈 결정은 다음을 모두 만족해야 한다.
  - owner = "dohoon" ∧ status resolved ∧ decided_by = "dohoon"
  - `recorded_by` 가 "machine:" 으로 시작하지 않는다
  - `evidence` 가 비어 있지 않다 — 또는 **레거시 대체**: `evidence` 필드가 레지스터에 처음 나타난 항목(현재 CALMAR-FREQ-DAILY, 09-24 17:31)의 `registered_at` 보다 먼저 등록된 결정이면 `note` 가 비어 있지 않으면 된다.
  - 09-23 일괄 결정(D-A~D-M)은 note "도훈 채팅 결정(AskUserQuestion…)"으로 통과한다. 소급 편집할 유인을 없앤다 [헌M9·완M4].

**한계 명시**
- owner 대조는 여전히 문자열 규약이다. 이 가드가 막는 것은 **기계와 무인 레인의** 자기승인이고, 악의적인 대화 세션은 막지 못한다.
- 필요하면 기존 `safety_guard.sh` 에 패턴을 추가한다: `decision_register.json` 직접 편집, `reinforce_auto_config.json` 의 `organic.auto_live`·`kill.release` 직접 편집을 차단한다. 새 훅은 등록하지 않고, 동시 수리 배포 뒤에 한다.

**검사**
- (+) live 전이 1건 → jsonl 1행 + 레지스터 포인터 1행. `dr_load` 가 성공하고, 부팅 Director 줄은 변하지 않는다(status resolved 라 대기 결정이 아니다).
- (−) 기계·무인 문맥에서 `dr_resolve(decided_by="dohoon")` → stop · scope=`tier_graduation` → 거부 · authority 가 open → 거부 · 중복 id 주입 → 쓰기 거부 · 두 프로세스 동시 쓰기 경합 시뮬레이션 → 유실 0.
- (돌연변이) 잠금이나 대조를 지우면 red.

### 3.2 킬스위치 발화 조건 (수치 = `organic.kill.*` · 실행 주체 명시 [헌M12])

| 코드 | 조건 | 실행 주체 · 원천 | 처분 |
|---|---|---|---|
| K0 수동 | config off · 층 mode=off · env `QVEST_RF_ORGANIC=off` | tick | 즉시 pi0 |
| K1 경계 | denylist 파일 md5 가 유기체 실행 전후에 바뀜 ∨ writer 가 거부함 ∨ `identical(fixed_axes)` 실패 ∨ 기저 sha 불일치 ∨ OneDrive 충돌 사본 탐지 | tick(유기체 실행 전후 스냅샷) | 전 층 off + **즉시 `[무인]` 경보** |
| K2 회계 | 선행 trial log 없는 효과 ∨ N 이중 도출 불일치 ∨ 로그 쓰기 실패 ∨ 레지스터 전후 대조 실패 | 효과 검사는 tick 이 한다. **N 대조는 유기체 밖 감사 스크립트** `ops/rf_organic_audit.R` 가 서류 쪽에서 독립으로 다시 센다(유기체는 서류를 읽을 수 없기 때문이다). 결과는 플래그 파일 `06_Registry/organic/flags/k2.json` 에 쓰고 tick 이 읽는다 | 전 층 off(fail-closed) + 즉시 경보 |
| K3 PIT 자가검사 | 섭동 자가검사 red | idle 분기에서 격리 루트(빈 `R_ENVIRON_USER` · 루트 리터럴)로 실행한다. 결과 파일 `06_Registry/organic/selftest/<date>.json{pass, organic_code_md5, at}` 만 쓰고 운영 상태는 건드리지 않는다(09-25 운영 오염 교훈). tick 은 **파일이 신선(`selftest_max_age` 이내)하고, md5 가 현재 유기체 코드 md5 와 같고, pass** 일 때만 통과로 본다. 아니면 K3 로 처리한다 | 전 층 off + 즉시 경보 |
| K4 전방 보정 | live 정책 예측의 e-과정이 1/`eprocess_alpha` 를 넘음(Ramdas et al. 2023 · Howard et al. 2021) | idle 분기(야간 적합) | 그 정책 강등 |
| K5 기아 | **승격 세대 1개가 신규 논문 착수 0 으로 끝남.** D-G 의 "세대당 ≥1"을 그대로 쓴다(7일 비중 환산 폐기) | tick(원장 구조 필드) | 예산 층 shadow |
| K6 진동 | 주간 live 변경 > `max_live_changes_per_week` ∨ 휴면 변경 > `space.max_changes_per_week` | tick | 해당 층을 `oscillation_pause` 동안 정지(= pol_cfg 주간 창 1개) |
| K7 낡음 | 신선도 키 불일치: epoch · current_axis · 활성 BID · posterior pool_md5 · state 나이 > `state_max_age`(= `stale_consecutive` × tick 주기) | tick | 그 tick 은 pi0 + jlog `organic_stale`. `stale_consecutive` 번 연속이면 층을 shadow 로 |
| K8 러너 건강 | live 변경 뒤, 유기체 live entry 의 tick 실패율이 **동시 대조 pi0 entry**(§3.4 ⑨)보다 높음. 단측 비율 검정(α = `kill.alpha`)에서 유의할 때 | idle 분기 · 원천 = jlog tick 이벤트(`halt_*`·`grid_consumed`·워커 실패) | 그 변경을 롤백. **대조 entry 가 없으면 K8 은 미무장이고 live 는 금지다**(미무장은 green 이 아니다) [헌M12·완M8] |
| K9 불변식 | 절단 entry 에서 `halt_no_free_cell`·`resume_skip_unknown_cell`·반복 `halt_no_jobs` 발생 ∨ 불변식 ①~⑤ 위반 탐지 | tick | 그 entry 의 계획을 롤백(소진 전이면 state 로, 소진 뒤면 `reopen_required` 경보) + 전 층 shadow + 즉시 경보 |

- 즉시 경보 대상은 K1·K2·K3·K9 와 롤백이다. `tg_agent_brief` 로 보내고 표제는 `[무인] 유기적 강화 — <K코드>` 다. 주간 보고를 기다리지 않는다 [헌R8·완R4].
- 외부 성적표(τ_D 이후) 수치로는 킬하지 않는다. 그러면 킬에서 살아남는 정책이 τ_D 이후 데이터로 선택된 셈이 된다(evo · 심사1·2).
- 킬이 발화하면 부분 복원하지 않는다. pi0 비트 동일로 돌아간다.

### 3.3 롤백 단위

- 1차 단위는 **decision_id** 다. 정책 판(policy@sha)을 롤백하면 그 판의 결정들을 연쇄로 롤백한다.
- entry 는 개설 때 고정한 구조 판으로 끝까지 가고, 진입한 블록의 계획은 동결이다. state 롤백은 미진입 블록과 새 entry 에만 효력이 있다.
- **소진까지 간 효과**
  - 절단이 그 entry 의 마지막 빈 칸을 닫아 소진을 일으켰는지는 jlog `organic_trim_applied` 와 `grid_consumed` 를 조인해 판별한다.
  - 해당 entry 는 `rf_reopen_entry`(사람 호출)로 되살린다.
  - 이것이 결정 문안의 필수 가드인 "롤백"이 가장 중요한 효과에까지 닿게 하는 경로다 [헌M10].
- 측정은 되돌리지 않는다. 그 정책 아래서 측정된 칸은 시행 로그 태그로 이후 집계에서 거를 수 있다.

### 3.4 shadow → 리플레이 → live 판정식 (정책 π 대 pi0)

```
live(π) ⇔ 아래 전부
 ① 사전등록(π@sha) 존재 ∧ 동결                                                  (G3)
 ② ORGANIC-DE resolved ∧ 그 결정이 π 의 유형(R·선택)을 허용 — 증거 규칙(G7 ③)
 ③ 두 단 as-of 리플레이(09-18 엔진 어댑터): π 는 ≤τ₀ 통계로 결정하고, 이득은 (τ₀, τ_D] 창 지표로만 잰다.
    τ_D 이후는 어떤 항에도 들어가지 않는다
    heldout_win ≥ 0.60 · null_pct ≥ 0.95 · discovery_drop ≤ 0.10 · unreachable ≤ 0.20 · best_loss ≤ 0.05
      (전부 pol_cfg 기본값 인용)
    절약 칸 > 0   (비열위 조건이 먼저 서므로 절약은 양이기만 하면 된다 — 부록 D)
    peek_blocked(G2) ∧ static_clean ∧ negative_control_ok(π_R 이 같은 게이트에서 탈락)
 ④ 검정력: 사전등록 ratio ≥ organic.gate.power_min_ratio (0.15 — 플랜 착수 관문). 미달 = '미결', live 불가
    ★(τ₀, τ_D] ≈ 2011~2016 에는 GFC 가 없다 → Calmar 계열 정책은 '미결'이 가장 흔하다고 사전등록한다(심사2)
 ⑤ shadow 주수 ≥ pol_cfg shadow_min_weeks ∧ 유익한 불일치 ≥ 3 ∧ newest_replay_win ∧ placebo_ok   (도훈 09-21 ① 값)
 ⑥ live_same_kind < 1 ∧ live_total < 2 ∧ activations_this_week < weekly_activation_max
 ⑦ .organic_auto_live_ok(cfg) — config auto_live ∧ 도훈 결정 id 참조(G4)
 ⑧ K1~K9 green(미무장 ≠ green) ∧ 경계·PIT 자가검사가 신선하고 green
 ⑨ 동시 대조 배정 사전등록 존재(아래)

demote(π) ⇔ pol_gate_demote(최신 5 판정 중 3 패) ∨ K4 ∨ K8
tombstone ⇔ 8주 안 2회 강등 (해제 = 도훈)
```

**축소 정책의 리플레이 가능성 — v1 주장 철회** [완M2]
- 절단이 블록 승자를 바꾸면 하류 칸(carry · B4 `combo.use`)이 달라진다. 그러면 반사실이 관측되지 않는다(unreachable).
- n_min 1~2/5 로 자르면 승자가 바뀌는 일이 흔하다. 그래서 `unreachable ≤ 0.20` 은 구조적으로 통과하기 어렵다.
- 09-18 실측(post_0904 19트리): 조기 정지형의 최고 칸 발견률은 58%·42% 였고, 공간/예산 비는 1.00 이었다. 결론은 "이득은 덜 하기에서만 나온다"였다.
- 그래서 이렇게 한다.
  - O2 착수 전에 후보 정책별 unreachable 과 discovery_drop 을 엔진으로 **기술 산출**해 사전등록 검정력 항목에 싣는다. 결정 수치가 아니라 사전확률이다.
  - π_trim 과 조기 소진류는 '철회' 또는 '미결'이 가장 흔할 것이라고 사전등록한다. 그렇게 나오면 벽이 아니라 사실로 적는다(AX-000).
  - π_dorm(B2 arm 휴면)은 하류 승자 교체가 B2 안에 머무는 경우가 많아 상대적으로 리플레이 가능성이 높다. 우선 판정 대상으로 둔다.
  - pre_0904 트리는 엔진이 재현하지 못하므로(53.2%) 리플레이 세계에서 뺀다. 세계는 close_t1 원장으로 재빌드한다.

**가산 정책**
- 칸을 늘리는 결정은 반사실이 없으므로 리플레이로 판정할 수 없다.
- canary 로 시작한다: `organic.canary_entries` 개 entry 에 `canary_weeks`(= pol_cfg `shadow_min_weeks`) 동안 적용하고, 내부 계기(I1·I3)가 비열위면 확대한다.

**⑨ 정책 수준 동시 대조** [완M10]
- live 정책이 있는 동안, 신규 entry(신규 논문·승격 자식)를 사전등록 시드로 **1:1 블록 무작위 배정**(블록 크기 2)한다. 한쪽은 pi0 로 유지한다.
  - 1:1 배정은 두 군의 분산이 같을 때 고정 총수 대비 검정력이 가장 크다.
- live 효과(I3 · 절약 칸 · K8 러너 건강)는 이 동시 대조와 비교한다. Lee & Wason 2020 이 지적한 비동시 대조 편향을 피하기 위해서다.
- 배정 자체는 N_meta 에 계상한다.
- 대가: 유기체의 효과가 신규 entry 의 절반에만 걸린다.

**2계층 풀 공급**
- 승격이 B 모듈의 69% 를 만든다. 그러나 B 등급은 전기간 파생값이라 이 판정식에 넣을 수 없다.
- 그래서 외부 성적표 X6 와 ⑨ 동시 대조로 사람이 판단하고, 사람이 중지하면 N_meta 로 센다 [완R2].

### 3.5 주간 보고 (`[1계층·강화] 유기적 강화 주간 — <ISO 주차>` · 5섹션 양식 + 차트)

**내부 절** (기계 결정과 같은 입력만 쓴다)
1. 상태: 층별 mode · live 정책@sha · killed 여부 · epoch(τ_D·τ₀·도출 근거·argmin 칸)
2. 결정 수(층별 제안/기각/shadow/live/강등)와 **러너 결정이 pi0 와 달라진 횟수**(디렉터 전철 감시)
3. 예산: would_trim·실제 회수 칸 수(원장 재도출값이다. 주장이 아니다) · 블록별 계획 대 격자 · 세대별 신규 논문 착수 · dg_shadow 대조
4. 공간: 휴면·부활·퇴역 목록과 사유 · 생성 레인 쿼터
5. 구조: 블록 상태 · epoch 고정 확인
6. 내부 계기 I1~I6 과 추세 · 킬 조건별 여유(현재값/문턱) · K8 무장 여부
7. N: N_cell · N_program · N_policy · N_meta
8. 경계 감사: denylist md5 불변 · 자가검사 신선도·결과 · 증거 풀 크기(청정/층화/미결 블록) · **기계 기록 건수**(레지스터 포인터 행 · jsonl 행 · 상한 초과분) [완R4·R5]

**외부 성적표 절** (사람 전용 · 별도 모듈 `rf_organic_scorecard.R` 산출 · 저장 `06_Registry/organic/scorecard/<ISO주차>.json` · 설계 레인 열람 차단 · 기계 결정 파일은 읽지 못한다 — 정적 검사) [헌R13]

9. X1 시장 시점 전이 ρ(u_τD, u_post): 유기체가 영향을 준 칸 대 pi0
10. X2 τ_D 이후 S(유기체 영향 계보 대 pi0) + IS 활성 IR + [시장·EW−CW·틸트·선별] 분해(P2-02 가 없으면 "미산출"로 표기)
11. X3 선택 인플레: pi0 승자와 as-of 쌍둥이 승자의 전기간 → τ_D 이후 감쇠 비교
12. X4 A 후보와 보류 코드
13. X5 계보 점유(22632 쏠림: B 104/225 · PT≥2.95 39/39[심사 실측(evo)])
14. **X6 B 모듈 생산률**(동시 대조군 대 유기체 live 군 · 승격 자식 수) [완R2]

**싣지 않는 것**: 내부 절에는 전기간 PT·Calmar 원수치를 싣지 않는다. 보고가 목적함수로 새는 것을 막기 위해서다.

---

## 4. 시행 회계

**층위**

| 수 | 정의 | 소비처 |
|---|---|---|
| N_cell | D-A = 계보 누적 측정 칸(상속 제외) + 기저 1 + 배치(`rf_selection_accounting` · gates:218-222) | DSR 게이트(**불변** · 기계 권한 밖) |
| N_program | 유기체 적합에 들어간 증거 칸 + **측정 중지 결정**(휴면·축소·조기 소진)의 근거 칸 | 서류 민감도 행(의무) · PBO 가족 |
| N_policy | 리플레이까지 간 정책 판 수(기각·shadow 탈락 포함, π_R 제외, 판마다 누적) | 서류 · 주간 보고 |
| N_meta | live 전이 수 + 동시 대조 배정 수 + 외부 성적표를 보고 사람(또는 Q 세션)이 발의하거나 중지한 정책 변경 수 [헌R13·완M10] | 서류("선택 규칙 자체가 선택됐다") |

**적응 결정이 N 에 들어가는 방식**
- 유기체가 배분해서 측정된 칸은 기존대로 N_cell 에 들어간다.
- 유기체가 **재지 않기로 한** 칸은 측정이 없으므로 N_cell 에 넣지 않는다. 대신 그 결정이 소비한 증거(N_program)가 선택 다중성이다. 풀링 사후는 계보 간 정보를 섞으므로 한 계보의 탐색이 프로그램 전체를 보고 이뤄진다. evo 의 "측정 전 선별 없음"은 휴면·반감과 모순이라 고쳤다(심사2).
- 정책 K 개 중 하나가 live 가 되는 것은 메타 선택이다(N_policy · N_meta).

**DSR·PBO 가 더 엄격해지는 효과**
- Bailey & López de Prado(2014)의 기대 최대 SR 인자 (1−γ)Φ⁻¹(1−1/N) + γΦ⁻¹(1−1/(Ne)) 는 N=170(최대 계보 규모)에서 2.71, N=1,200(프로그램)에서 3.31 이다(**+22%**, 식 대입 — 심사2 재계산 일치).
- 다만 최고 칸은 N=1,083 에서도 DSR 0.86 이다(플랜 D-A). DSR 은 구속하지 않을 가능성이 크다. 실제로 구속하는 것은 가족 단위 CSCV-PBO(Bailey et al. 2017)와 retention 감쇠귀무(D-B)다.
- 서류에는 N_cell 판(게이트)과 N_program 판(민감도)을 병기한다. 게이트 N 범위를 넓힐지는 안건 A3 다.

**예산과 A 후보 서류(P1-03/04)의 분리 — 한 방향 방화벽**
1. **자료**: 유기체는 as-of 뷰·구조 필드·시행 로그만 읽는다. 서류는 전기간 essence·시행 로그·부트스트랩·절단판을 읽는다.
2. **권한**: 유기체는 A 관문(`rf_a_eligibility`)·`a_eligibility_gate.json`·`grade_a_queue.json`·`judge_request_*`·서류를 읽지도 쓰지도 않는다. 서류는 유기체 provenance(`06_Registry/organic/*`·시행 로그)를 읽기만 한다.
3. **목적**: 효용 S_τ 에 DSR·PBO·등급·A 근접도가 없다. A 근접 계보에 "확인 측정"을 몰아주는 경로가 없다.
4. **정적·섭동 검사**
   - 유기체 파일이 `selection_accounting.R`·`selection_dossier.json` 을 source 하거나 읽으면 red 다.
   - 서류 값을 교란해도 유기체 결정은 불변이어야 한다.
   - 공용 계약 `asof_window.R` 의 의존 방향은 **`selection_accounting.R` → `asof_window.R`** 하나다. 서류가 계약을 source 하고, 유기체는 서류를 source 하지 않는다. v1 L691 에 역방향으로 적힌 서술을 정정한다 [헌R10].
5. **계산 자원**: 서류 계산은 idle 비동기 큐(P1-04), 유기체 적합·as-of 배치도 idle 이다. 서로 tick 예산을 잠식하지 않는다.
6. **서류 추가 항목**: 탐색 경로에 관여한 유기체 정책 id · 결정 시점 사후 요약 · N_program · N_policy · AAC 진단 곡선 · 선택 경로 라벨.
7. **A 관문 provenance** [헌M5]
   - 방화벽은 유기체 → 서류·관문 방향만 막는다.
   - 관문(P0-14 계보 도출)과 서류는 유기체 시행 로그를 **읽는다**. 유기체 태그가 판정 경로에 닿지 못하면 22632 와 같은 부류의 구멍이 생기기 때문이다(§3 G1).
8. **Judge 경로** [완R3]
   - Judge 는 유기체 state 를 직접 읽지 않는다. 서류(P1-04)를 거쳐서만 본다.
   - judge.md 6축 가운데 'selection 정직성'에 "유기체 결정 재현"을 추가하는 문서 개정을 권고한다: view_md5 와 policy@sha 로 재계산한 결과가 identical 한지, τ_D 단언이 성립하는지를 본다.
   - judge.md 편집은 도훈 승인이 필요한 문서 개정이다.

---

## 5. 헌법 경계 봉쇄 — 기계가 절대 바꾸지 못하는 것

| 층 | 장치 | 양방향 검사 |
|---|---|---|
| **단일 writer** | 파일은 `rf_organic_write.R::rfo_write(target, pointer, value, decision_id)` 만 쓴다. <br>state.json 은 임시 파일에 쓴 뒤 rename 하는 원자 쓰기로 쓴다. OneDrive 충돌 사본(`*-<PC명>*.json`)이 탐지되면 K1 이다 [완R11]. <br>경로 **allowlist**: <br>• `06_Registry/organic/**`(state · actions · decisions.jsonl · asof/ · lever_book/ · scorecard/ · selftest/ · flags/ · runs/ · report_sent/ · snapshots/) <br>• `06_Registry/prereg/`(layer=organic · `rf_prereg_write` 경유) <br>• `rf_trial_log.jsonl`(append · 기존 writer) <br>• `rf_decisions.jsonl`(`rf_record_decision`) <br>• `decision_register.json`(`dr_record_machine` 만 · 공용 claim) | (+) 허용 경로 쓰기 성공 + actions 1행. <br>(−) 금지 경로 쓰기를 주입하면 stop + K1. <br>(돌연변이) allowlist 검사를 뺀 판에서 검사 red |
| **denylist (md5 감시)** | `constraint_defaults.json` 전체 · `reinforce_program.json` 전체 · `a_eligibility_gate.json` · `pit_quarantine.json` · `06_Registry/book/**` · `05_Production/**` · `01_Literature/**` · `grade_a_queue.json` · `judge_request*` · 측정 원본 디렉터리 `remeasure_close_t1_*`[헌R2] · 정본 카탈로그 3종(`overlay_catalog.json` · `weight_catalog.json` · factor_registry **두 벌** — `.cache/factor_db/factor_registry.json` 과 git 추적 원본 `02_Infrastructure/factor_db/factor_registry.json`[헌R1]. lifecycle 은 팩터 DB 재빌드와 2계층도 소비한다) · `reinforce_auto_config.json`(사람 소유) · 원장 L1/L2(유기체는 원장을 쓰지 않는다) · `.claude/**` · 훅 · `02_Infrastructure/contracts/**`(as-of 계약 파일은 사람이 배포) | 유기체 실행마다 전후 md5 스냅샷을 찍는다. 불일치 = K1. 위반 주입 픽스처로 발화를 실증한다 |
| **정적 봉쇄** | 유기체 R 파일을 parse 해, 쓰기 호출(`writeLines`·`write`·`cat(file=)`·`saveRDS`·`fwrite`·`write_json`·`file.rename`·`file.copy`·`unlink`)이 `rfo_write`·as-of 배치 writer 밖에서 0 인지 확인한다. <br>`dr_open`/`dr_resolve`·`rf_reopen_entry`·`register_book_entry`·`promote_to_production` 토큰도 0 이어야 한다. <br>대조는 `getParseData` 토큰 **정확 일치**로 한다(부분문자열 대조 금지 [완M3]). <br>**소비자를 parse 해 formals·호출과 대조**한다(기억 카드 "서명은 계약이 아니다") | 우회 3종(문자열 결합 경로 · `do.call` · `eval(parse())`) 양성 대조. 셋 다 잡혀야 방어선으로 인정한다 |
| **스키마(deny-by-default)** | `06_Registry/organic/schema.json` = 허용 키 목록뿐: `plan` · `arms[].status∈{pi0,organic_dormant,organic_probation,organic_retired}` · `structure.blocks[].state` · `quotas` · `policies` · `killed` · `epoch` · `posterior_ref`(포인터·해시만 — 본문은 `lever_book/` [헌R7]) · `dg_shadow` · `kill_release_seen`. 고정 축 키(`n_max`·`universe`·`start_date`·`commission_bps`·`liq_adv20_min`·`long_only`·`weight_cap`·`base_weight`) · 문턱 키 · N 정의 · 보류 코드 · PIT 격리 키는 **존재하지 않는다** | 위반 주입 7종(fixed_axes 포인터 · tier_graduation · a_eligibility_gate · 카탈로그 status · n > n_cap · 격리 arm 부활 · 보호 파일 직접 쓰기) → 전부 stop + K1 |
| **값 제약** | n(e,b) ∈ [max(n_min_b, 시도 코드 수), n_cap(e,b)] · 쿼터 ∈ [0, q_cap] · 휴면 대상 ∈ 정본 active · 정책 ∈ 사전등록 가족. 유기체는 **줄이기와 복원만** 한다 | (−) n > n_cap · q > cap 주입 → 거부 |
| **전이표** | 정본 status 가 suspended(C11 — pg2_risk_overlay_v1)·retired·`pit_quarantine`·사람 tombstone 인 id 는 관리 대상이 아니다. 허용 전이 = {pi0 ↔ organic_dormant, organic_dormant → organic_probation → pi0, organic_dormant → organic_retired} | (−) pg2_risk_overlay_v1 부활 주입 → 거부. (돌연변이) 전이표 우회 → red |
| **고정 축 사후 재도출** | 기존 `rf_preflight_verify_axes` 가 모든 칸에서 고정 축을 재도출한다. 기계가 어떤 경로로 축을 어겨도 칸 단위에서 드러난다. 유기체는 epoch 고정 `sha(fixed_axes)` 와 `identical` 을 매 tick 단언한다 | 기저 파일 1바이트 변경 → K1 |
| **판정 경로 격리** | `rf_a_eligibility`·`essence_score.R`·`run_paper_replication.R`·`judge.md` 흐름은 `06_Registry/organic/*`(state · posterior · scorecard)를 읽지 않는다. **단 시행 로그의 `organic_measure_tag` 는 P0-14 계보 도출이 읽는다.** 판정 경로가 유기체 태그를 볼 수 있어야 하기 때문이다(provenance) [헌M5] | 정적: 세 파일에 "06_Registry/organic" 참조 0. <br>P0-14 도출 함수에 시행 로그 태그 판독이 있어야 한다. 양성 대조: 태그된 합성 칸이 도출 표식에 포함되는지 확인한다 |
| **LLM 권한** | 유기체는 LLM 을 부르지 않는다. 결정자가 아니고, 사전학습 기억은 C1~C15 밖이다(2504.14765). 설계 레인은 제안자로 남는다. <br>`arm_gen_read_guard` 의 MEASURE_RE 에 `06_Registry/organic/`(외부 성적표 `scorecard/` 포함)을 추가한다. **기존 훅 확장**이고, 동시 수리 배포 뒤에 한다 [헌R13] | 설계 레인 문맥에서 organic 상태나 성적표를 읽으면 block, 문맥 밖이면 pass |
| **검사 격리** | 모든 검사는 빈 `R_ENVIRON_USER` + 루트 리터럴 + 전후 스냅샷으로 돈다. `08_Tests` 글롭 금지(기억 카드 09-25 운영 오염 3건) | 스냅샷 불일치 = 검사 red |
| **사람 명령 경로** | 도훈용 명령은 `ops/rf_organic_cmd.R` 한 곳에서만 실행한다: 상태 조회 · 킬 해제 토큰 기록 · 롤백 · 휴면 해제 · `rf_reopen_entry`. 모두 `rfo_write` 나 원장 writer 를 거친다. 수동 JSON 편집은 스키마와 전후 md5 를 우회하므로 금지한다 [완R4] | (+) 명령 1건 → actions 1행. <br>(−) 기계·무인 문맥에서 명령 실행 → stop |

원칙: 위 장치는 모두 양성 대조(정상 통과) + 위반 주입(차단 발화) + 돌연변이(장치 제거판에서 검사 red)를 통과해야 방어선 목록에 오른다. 양성 대조 없는 계기는 방어선이 아니다.

---

## 6. 레버 감사 우선순위 1~9 · P0-14 · 플랜 항목과의 관계

### 6.1 레버 감사 우선순위

| # | 항목 | 관계 | 설명 |
|---|---|---|---|
| 1 | `tilt_attribution.R`(P2-02) | **선행조건(외부 성적표 X2)** · 현재 없음[확인] | 유기체 O0 와 독립으로 병행한다. 외부 성적표와 A 서류에 IS 활성 IR 과 [시장·EW−CW·틸트·선별] 분해를 병기한다. 없으면 X2 를 "미산출"로 보고한다(조용한 누락 금지). 유기체의 효용·사전에는 넣지 않는다 [완R12] |
| 2 | 쓰이지 않는 예산 회수 | **분할** | (a) D-G B5 축소: 유기체 밖 이행 항목이고, Q②′ 결정 뒤에 켠다 [헌M1]. <br>(b) B3 축소·diag + B3 를 참조하는 B4 칸 제거: 두 경로가 있다. **구조 사유 사람 규칙 안건 A5**(성과 비소비 — P0-12 k200 한정 × 09-05 유니버스 리셋 → 하류 소비자 없음), 또는 유기체 π_trim(성과 소비 · 증거가 부족해 '미결'이 가장 흔할 것) [완M12]. <br>(c) B2 해로운 arm 휴면: π_dorm(성과 소비형 → shadow → ORGANIC-DE → G4). 해로운 arm 목록은 정답지가 아니라 일치율 보고 대상이다. <br>(d) **B1 '7개 이상 팩터 적층' 퇴출**: 유기체 범위 밖이다(B1 절단 금지 09-04 · 팩터 수준은 P0-08 소관). B1 설계 레인 검증 규칙(`b1_design_verify`) 쪽 사람 안건 후보로 넘기고, 유기체는 as-of 일치율만 보고한다 [완R12] |
| 3 | 승격 통제칸(P1-06) | **선행조건 · 기결정** | D-F 로 결정된 '통제칸 상주'다. v1 §11 이 '선택 전제'로 적은 것을 정정한다 [완R12]. 잡음 척도 s_j 의 1순위 원천이다. 배포 전에는 부트스트랩만 쓴다 |
| 4 | PR-L2 B7 as-of | **독립** · 레인 최우선(D-G 레인 순서가 보장) | 유기체는 PR-L2 의 arm·예산·멈춤 조건을 건드리지 않는다 |
| 5 | PR-L1 cap_core | **독립** · 레인 최우선 | A4 칸은 PR-L1-A4-DISPOSITION 으로 삭제가 확정됐다(N 미계상). confirmed 가 되면 사람이 템플릿으로 등재하고 O4 에서 canary 로 인스턴스화한다 |
| 6 | D-F soft | **흡수(shadow)** | 승격 자식 soft 예산 · 잡음 파생 여백 δ |
| 7 | 선택 가치 함수 + 결정 기록(P1-05) | **흡수** | 선택 층 π 가족 · `select_winner_by` 실배선 · B6/B7 술어 · 결정 기록 배선. `rf_promote.R`·`rf_combination_launch.R` 편집을 포함한다(§8.4) |
| 8 | 설계 레인 학습 고리 | **부분 흡수** | design_source 칸 단위 도출. expect 채점(P3-03)은 별도 |
| 9 | 크래시 위험 선별 | 범위 밖 | L2 판정 뒤 사전등록 |

### 6.2 P0-14 와의 관계 (러너 재개 전 필수 · 유기체 O1 선행조건)

- 현재 표식 도출기는 운영 트리 밖 `/c/tmp/p0_08_apply/apply_p0_08_flags.R` 에만 있다[확인]. v1 의 "derive 가 없다"는 "운영 트리에 없다"로 정정한다 [완R1].
- **양성 대조**: 새 운영 함수는 현 원장의 B08 표식(직접 85칸 · 승계 포함 586칸)을 **비트 재현**해야 한다. 재현한 뒤 스크립트를 운영 트리로 옮긴다.
- **도출 규칙**
  - 플랜의 '승계 집합 ⊆ factors' 부분집합 규칙은 오탐을 낸다. 승계하지 않았는데 우연히 같은 팩터를 포함한 칸도 잡기 때문이다.
  - 관문 시점 도출은 **carry·부모 사슬 출처**(승계 성분 서명)로 하고, 부분집합 규칙은 교차 검사로만 쓴다 [완R1].
- **범위 권고**
  - ① H1: 전기간 IC 로 선정한 팩터 집합의 승계(현행)
  - ② 교차 entry 노출 LLM 설계 칸: 설계 재료 파일마다 교차 entry 절에 수치가 들어 있는지 도출한다(Q④ 기본값 = verdict `possible`)
  - ③ **유기체 시행 로그 `organic_measure_tag` 판독** → 보류 코드 `organic_policy_selected`(기본 비활성) [헌M5]
  - ④ D-E-V6 소비 코드(전기간 조건부 IC 행렬)로 선정된 칸이 있으면 같은 틀로 표식
- 유기체 증거 필터 E2·E3 도 이 도출 함수를 **같이** 쓴다. 두 소비자가 하나의 정본을 공유한다.
- P0-14 는 동시 진행 워크플로 소관이다. 이 설계는 요구사항만 넘긴다.

### 6.3 플랜 항목

| 항목 | 처분 |
|---|---|
| P0-07 빈티지 지문 | 선행(E6 동치 판정). B07 은 stage2 rebase 뒤 배포 예정이고, 그 전에는 rebase 스탬프로 대신한다 |
| P1-01 d_A·S | 흡수. as-of S_τ 가 유기체 효용이고, 전기간 판은 서류·보고용이다 |
| P1-02 시행 로그·설계 출처 | **O0a 에서 선행 신설**(현재 없음). 생산자 7곳 배선을 포함한다: 러너 결정 기록 · B1 설계 · 블록 설계 · B5 설계 · overlay_propose · weight_catalog_grow · 승격/결합 개시 [완M6] |
| P1-03 `sa_subwindow` | 유기체의 선행조건이 **아니다**(유기체는 `asof_window.R` 만 쓴다). P1-03 을 착수할 때 `asof_window.R` 을 source 하는 얇은 래퍼로 만든다(의존 방향 §4) |
| P1-04 서류 | 소비자. §4 의 항목을 추가한다 |
| P1-05 | 흡수(선택 층 · O3) |
| P1-06 | 선행 · 기결정(D-F) |
| P1-07 E2 | 유기체 층에 한해 G4 로 대체를 권고한다. H1 지표는 두 단 창으로 교체를 권고한다 → A2-b·d |
| P1-08 FIFO·priority | **유기체 밖 이행 항목**(D-G 결정 · 성과 비소비). 러너 재개와 함께 배포할 수 있다 |
| P1-09 설계 재료 | D-E-B5-MATERIALS 의 가림(B1 방식을 B5 로 확장)으로 **교차 entry 노출이 사라진 재료**가 `llm_masked` 라벨의 전제다. v1 의 "τ_D as-of 판 design basis" 조건은 가림 결정으로 대체한다 |
| P2-01 `rf_prereg.R` | **O0a 에서 최소 writer 를 선행 신설**한다(G3). P2-01 본 배포는 이 writer 를 확장한다 |
| P2-02 tilt_attribution | 독립 병행. 외부 성적표 X2 의 선행조건 |
| P2-03 floor v2 | 정합. F1(22632 B1_3)을 as-of 로 재선정한 새 칸으로 재정의한다 |
| P3-01 레버 장부 | 통합. `06_Registry/organic/lever_book/<epoch>.json` 이 장부의 as-of 뷰다. state 에는 포인터와 해시만 둔다 [헌R7]. PE-5 수용 게이트를 O0b 완료 판정에 재사용한다 |
| P3-02·04·06 | 독립. 유기체 상태는 기억층이 아니다(AX-D2 '4번째 기억층 금지' — state 는 제어 상태, actions 는 행동 로그) |

### 6.4 폐기·개정하는 플랜 조항

**유기체 권한 안에서 폐기**
1. P1-07 "live 는 도훈 confirm 후": 유기체 층에 한해 REINFORCE-ORGANIC-AUTONOMY 로 대체한다(G4). 다른 정책 종류에는 그대로 적용된다.
2. P3 보류 "policy_state 자동 live(도훈 재승인 후)": 유기체 층에 한해 G4 를 통과하면 해제한다. π_lever(Thompson) 보류는 **유지**한다. 이 설계는 Thompson 을 쓰지 않는다.
3. 플랜 '하지 말 것' 11 "probe 없이 자동 live 금지": **유지**한다. 유기체는 두 단 리플레이와 π_R 을 probe 로 거치므로 충돌하지 않는다.

**권고만 한다** (사람 소유 파일이거나 기결정을 재정의하는 일이라 안건 A2)
- `graduation.improvement_check`(죽은 선언) 삭제. `reinforce_program.json` 에는 `fixed_axes` 가 같이 있어서 세션이 편집하는 것도 도훈 결정이 필요하다 → A2-f [헌R14].
- D-G 레인의 **고정** 순서는 폐기하지 않는다(wf 안 철회 · 심사1). 유기체는 같은 순위 안에서만 정렬한다.

---

## 7. 메타 목표 — "유기체가 나아지고 있는가"

**원칙**: 컨트롤러가 최적화하는 값과 계기가 재는 값을 분리하고, 목표 축에 상한을 건다. 기계가 읽을 수 있는 계기는 τ_D 이하 또는 연구 시점 전방 양뿐이다.

**내부 계기(기계 가독 · 킬 입력 가능)**

| 코드 | 정의 | 역할 |
|---|---|---|
| I1 전방 예측 점수 | 측정 **전에** 기록한 예측(P̂_b·P(a_ℓ>δ)·P_cont)과 그 뒤 측정된 칸의 as-of 결과의 Brier·로그 점수, 기후값 대비 skill(Gneiting & Raftery 2007). e-과정 감시(K4) | 모형이 새 칸으로 일반화되는가 |
| I2 보정 | 80% 예측구간 포함률이 `calib_band` 안에 드는가. 띠 = 명목 0.8 에서 예측 n 개의 이항 95% 구간(Binomial(n, 0.8) 분위/n)이고, n 이 바뀌면 다시 계산한다. v1 의 [0.65, 0.92] 비대칭 리터럴은 폐기한다 [헌M13] | 과신 감시 |
| I3 효율 | as-of S 감소 1단위당 칸 수(pi0 리플레이 대비) — **S 는 hinge 라 문턱 위 초과분 0** | 예산 층 채점 |
| I4 처리량 | 주당 신규 기저 소비 · 신규 논문 비중 | 경로 ① |
| I5 결정 변경 수 | 러너 결정이 pi0 와 달라진 횟수 | 디렉터 전철(권고만 쌓이고 결정은 안 바뀜) 감시 |
| I6 청정 증거 증가율 | 주당 E1~E8 통과 칸 · 미결 블록 수 | 유기체가 배울 재료가 쌓이는가 |

**외부 성적표(사람 전용 · 되먹임 금지)**
- 항목은 X1~X6(§3.5)이다.
- 저장 위치는 `06_Registry/organic/scorecard/<ISO주차>.json` 이다. 별도 모듈 `rf_organic_scorecard.R` 이 산출하고, 설계 레인 열람 차단 대상이다 [헌R13].
- 기계 결정 파일은 이 값을 읽지 못한다(정적 검사). 킬스위치도 읽지 않는다.
- Q 세션이 성적표를 보고 발의한 정책 변경도 N_meta 로 센다.

**"나아졌다" 선언 조건**
- 기계가 스스로 선언할 수 있는 것은 내부 조건뿐이다: I1 skill 90% 하한 > 0 ∧ I2 가 띠 안 ∧ I3 비열위(pi0 대비) ∧ I4 가 K5 하한 위.
- 외부 성적표(X1 < 0 등)는 **사람이** 해석한다. 사람이 그것으로 정책을 중지하면 N_meta 에 계상한다.
- X1 < 0(as-of 개선이 τ_D 이후로 전이되지 않음)은 실패가 아니라 **사실 발견**으로 적는다. 대응은 사전등록 레버(L1)의 몫이다.
- 상한의 뜻: 어떤 축이 θ 에 도달하면 그 축의 추가 개선은 진전으로 세지 않는다. "PT 가 올라서 좋아 보이는" 착시는 정의상 진전이 아니다.

**실패 모드와 대응**

| # | 실패 모드 | 탐지 | 대응 |
|---|---|---|---|
| F1 | 평가 창 누출(사전·재료·보고·파생 필드 경유) | G2 bt_result 수준 섭동 · 정적 파싱 | 단일 접근자 · 사전 분포 없음 · 외부 성적표 분리 · 적대검증 판정 입력 금지 |
| F2 | τ_D 가 일부 칸의 등급 OOS 를 먹음 | 칸별 단언 | τ_D 재도출(최소 분할점) + 위반 칸 제외 |
| F3 | 절단 때문에 entry 가 영구 정지(시도 코드 소실 · used ≥ 칸 수) | K9 · `halt_*` jlog | 불변식 ①~⑤ · 초과 attempt entry 로 위반 주입 픽스처 [완M1] |
| F4 | 사후 과신 → 승자 저주 잔존 | I2 포함률 < 하한 | 복원 부트스트랩 SE · entry·계보 군집 강건 · K4 강등 |
| F5 | 비동시 대조·빈티지 드리프트(Lee & Wason 2020) | epoch 별 잔차 평균 | E1·E6 · epoch 변경 = 재적합 + 부활 트리거 |
| F6 | 청정 증거 부족 → 모든 결정 미결 | I6 · 미결 블록 수 | 정직 보고. 증거를 늘리려 표식을 풀지 않는다. P1-09·B08 뒤 새 칸이 쌓이며 해소 |
| F7 | 과도한 축소 → 검정력 저하 → 더 불확실 → 더 축소(악순환) | 증거 증가율 | n_min · 휴면 최소 증거 · 한 번에 한 단계 · 부활 탐침 쿼터 |
| F8 | 거짓 퇴출(한 국면에서만 나쁜 arm) | 부활 탐침 성적 | 휴면(삭제 아님) · 계보 수 · 부호 안정 · 부활 어휘 4종 |
| F9 | 신규 논문 기아 | K5 | D-G 하한 · 깊이 hard 6 불변 |
| F10 | N 과소 계상(풀링·측정 중지) | 서류 민감도 | N_program 병기 의무 · A3 |
| F11 | 경계 우회(간접 경로로 헌법 파일 변경) | K1 md5 · 정적 파싱 | 단일 writer · deny-by-default 스키마 · 사후 축 재도출 |
| F12 | 기계 자기승인(결정 레지스터 위조) | G7 검사 | `dr_record_machine` 전용 · 기계 문맥 `dr_*` stop · recorded_by 확인 |
| F13 | 무성 폴백(캐시 낡음·뷰 결손) | jlog `organic_stale`·`asof_view_missing` 계수 | K7 fail-loud · 주간 보고 항목 |
| F14 | 킬스위치 불발(죽은 계기) | 주입 드릴 | 조건별 합성 열화 양성 대조 · 야간 자가검사 |
| F15 | 무작위 정책과 구분 불가 | π_R 대조 | live 금지 · 사실로 보고(벽·한계로 적립 금지 · AX-000) |
| F16 | 롤백이 러너가 실현한 효과(소진·승격)에 닿지 않음 | `organic_trim_applied` + `grid_consumed` 조인 | `rf_reopen_entry`(사람 호출) · `reopen_required` 즉시 경보 [헌M10] |
| F17 | 레지스터 쓰기 경합으로 기록 유실, 또는 중복 id 로 `dr_load` 전면 정지 | 전후 identical 대조 · 중복 검사 | 공용 claim + CAS · `M-ORG-` 네임스페이스 [헌M9] |
| F18 | 판정 경로가 유기체 태그를 보지 못함(22632 부류 구멍) | P0-14 양성 대조 | 시행 로그 태그 판독 + 보류 코드 [헌M5] |
| F19 | 2계층 풀 공급 감소(승격 soft 예산 · B5 축소) | 외부 성적표 X6 · 동시 대조 | 사람 판단 · N_meta [완R2] |
| F20 | idle 이 오지 않아 적합·자가검사가 낡음(러너가 계속 바쁨) | K7·K3 신선도 | fail-closed 로 shadow 유지 · 주간 보고에 낡음 일수 표기 [완M9] |

---

## 8. 구현 단계 O0~O4

### 8.0 착수 순서 · 세션 상한 · 멈춤 조건 · 실행 트리거 [완M13·완M9·헌M12]

**존재의의와의 관계**
- 세션 기본값은 라운드 전진이다.
- 이 설계의 기대 A 증분은 +0.3~1.2%p(§0.3)이고, 비용은 17~25 세션이다.
- 인프라 작업으로서 이 설계가 확실히 정당화되는 부분은 "측정 신뢰 훼손" 쪽뿐이다: 회계·provenance(유기체 태그의 A 관문 도달), 결정 기록.

**착수 순서**
1. **P0-14**(동시 워크플로 소관)를 끝내고 러너를 재개한다. 현행 격자로 재개하며, 배포 완료 보고 뒤 Q 가 수행한다(RUNNER-RESTART).
2. **유기체 밖 이행 항목**(성과 비소비 · 작다)
   - P1-08 FIFO · 레인 순서 · 세대당 신규 논문
   - overlay_propose 의 G1 경유 여부 확인
   - `rf_budget_auto` 가산 차단 + `b5_budget` 키(값은 A2-e 결정 뒤)
3. **A 레버가 먼저다**: P2-02 tilt_attribution · PR-L2 B7 as-of · PR-L1 cap_core. 유기체 작업은 이들과 라운드가 쓰지 않는 세션에서만 한다.
4. ORGANIC-DE 를 상정한다(§2.6). 결정은 O0 와 나란히 기다린다. O0a·O0b·O1 은 어느 분기로 결정되든 쓰인다(§8.3).
5. 유기체 O0a → O0b → O1(shadow) → (결정 뒤) O2 → O3 → O4.

**세션 상한과 멈춤 조건** (플랜 멈춤 규칙 "인프라가 계획의 1.5배를 넘으면 재우선순위"를 단계별로 적용)

| 단계 | 계획 세션 | 상한(1.5배) | 상한에 닿으면 |
|---|---|---|---|
| O0a | 3~4 | 6 | 멈추고 도훈에게 보고한다. 남은 범위를 G1·G3·G7(회계·기록)만으로 줄일지 결정받는다 |
| O0b | 2~4 | 6 | EB 를 블록 평균 + 부트스트랩으로 단순화할지 결정받는다 |
| O1 | 3~4 | 6 | shadow 기록만 유지하고 계기 확장을 멈춘다 |
| O2 | 3~4 + 벽시계 ≥ 8주 | 6 | 일몰 판정(§8.3) |
| O3 | 2~3 | 4.5 | 결정 기록만 유지한다 |
| O4 | 4~6 | 9 | 재상정 |

**실행 트리거 — 새 스케줄 작업 0**
- 새 Task Scheduler 작업은 영속 설정 변경이라 도훈 승인이 필요하다(MSIX 카드: 스케줄러만 실디스크를 본다). 이 설계는 새 작업을 만들지 않는다.
- 모든 작업은 기존 `reinforce_auto_tick.sh` 레인 안에서 돈다.

| 작업 | 위치 | 조건 |
|---|---|---|
| 유기체 tick(판독·계획 계산) | L2 레인 뒤 · 러너 앞 1줄 | 매 tick · 자기 claim · 시간 상한 `organic.tick.max_sec`. L2 드라이버가 러너 claim 을 쥐고 있으면 건너뛴다 |
| as-of 배치 · 야간 적합 · K3 자가검사 · K2 감사 · 주간 보고 | tick 끝의 **idle 분기**(이번 tick 에 러너가 배치를 내지 않았을 때) | 작업마다 claim · 시간 상한 · 멱등 표식(`06_Registry/organic/runs/<job>/<date>`) · 하루 1회(주간 보고는 주 1회) |

- idle 이 며칠 동안 오지 않으면(러너가 계속 바쁘면) 적합과 자가검사가 낡는다. 그러면 K7·K3 가 fail-closed 로 층을 shadow 에 머물게 한다. 조용히 진행하지 않는다.
- 헤드리스 레인이 `QVEST_SKIP_AUTO_COMMIT` 이면 organic 산출이 git 에 남지 않는다. 보존은 `actions.jsonl`·`decisions.jsonl` append-only 와 주간 스냅샷으로 한다. 세션 auto-commit 이 이를 흡수하는지는 O1 에서 확인한다 [완R4].

### 8.1 단계 표

**공통 검사 규율**
- 모든 신규 계기·writer 에 양성 대조, 위반 주입, 돌연변이, 원장 재도출을 적용한다.
- 등급 불변 회귀: `test_grade_unification.R` B4~B6 + 골든 비트 동일.
- 검사 격리: 빈 `R_ENVIRON_USER` · 루트 리터럴 · 전후 스냅샷 · 글롭 금지(SUITES 명시 편입).
- 편집 순서: 동시 수리 워크플로가 배포된 **뒤** 병합한다. 삽입점은 줄 번호가 아니라 함수·마커로 다시 읽는다.

| 단계 | 산출 | 검사 | 완료 판정 | 규모 [판단 · v1 대비 2~3배 재추정] |
|---|---|---|---|---|
| **O0a 회계·기록·봉쇄 기질**(결정 0) | • P1-02 시행 로그 정본 + `rf_trial_log_append` + 생산자 7곳 배선 + 칸 단위 design_source 도출 <br>• `rf_prereg.R` 최소 writer(`06_Registry/prereg/`) <br>• `reinforce_ledger.R`: organic kinds · decision_id 수리(밀리초 + 순번 + 해시) · `dr_record_machine` · 공용 claim + CAS · `M-ORG-` 네임스페이스 · 기계/무인 문맥 `dr_*` stop · 증거 레거시 규칙 · `rf_reopen_entry` <br>• `rf_organic_write.R`·`rf_organic_guard.R`(writer · 스키마 · md5 · 전이표 · 원자 쓰기) <br>• `rf_organic_ledger_adapter.R`(열 허용목록) <br>• `ops/rf_organic_cmd.R`(사람 명령) <br>• config `organic.*`(enabled=false) · overlay_propose G1 경유 확인 | • 레지스터 경합 시뮬레이션에서 유실 0 · 중복 id 거부 · 09-23 결정의 레거시 증거 통과 · 무인 문맥 stop <br>• 경계 행렬(위반 7 · 돌연변이 3 · 우회 3) <br>• 어댑터 열 허용목록 돌연변이 red <br>• `rf_reopen_entry` 양성 대조 + 멱등 <br>• 시행 로그 조인 100% | 전 검사 green · 생산자 7곳의 기록을 원장 재도출로 확인 | R ~1,000줄 + 검사 ~800줄 · 3~4세션 |
| **O0b as-of·모형 기질**(결정 0) | • `contracts/asof_window.R`(사람 배포) · `ops/rf_organic_asof_batch.R`(1,193칸 × 3창 · idle) <br>• `rf_organic_view.R`(E1~E8 · 짝 바닥 · τ_D 도출과 강건성 보고) <br>• `rf_organic_model.R`(창을 분리한 EB · 군집 강건 · wild cluster · 복원 정상 블록 부트스트랩) <br>• 리플레이 어댑터 골격 + 09-18 엔진 양성 대조 재실행(close_t1 세계) <br>• 사람용 1회 보고: 블록별 '결정 가능 시점' 예측 · S_τ 축별 포화율 · as-of S 순위와 전기간 A-거리 순위의 관계(N_meta 계상) [완M12·완R7] <br>• 문헌 서지 대조(부록 B ○ 표시분) | • `asof_window`: 원 종료일에서 identical(골든 `20260921_100007_6876` close_t1 판 3.777/0.433) · 종료일 이후 섭동에 불변 · τ+1 을 읽는 가짜 통계는 red · 분할일이 essence 분할과 같음 <br>• 짝 바닥 미분류 불일치 0 <br>• EB 합성 세계: 우월 레버가 1위 · 순열 귀무 · 80% 포함률이 이항 띠 안 · **γ 참값 0 이면 γ̂≈0** · 결정론 해시 <br>• G2 bt_result 섭동 양방향 | 증거표를 원장에서 재도출해 해시 일치 · 첫 as-of 레버 표(보고 전용 · 청정/층화 병기) · 결정 가능 시점 표 | R ~1,200줄 + 검사 ~800줄 · 2~4세션 + 배치 1~2시간 |
| **O1 shadow 전용**(러너 3줄 · live 0) | • `ops/rf_organic_tick.{R,sh}` + idle 분기 작업 등록 <br>• `rf_organic_apply.R`(판독 전용) · 러너 삽입 3줄(마커 기준) <br>• `dg_shadow`(D-G 대조) <br>• 휴면 필터 1줄 × 2(`catalog_id` 대조 · 기본은 빈 벡터) <br>• 선택 층 결정 기록 중 shadow 부분 <br>• K2 감사 스크립트 · K3 자가검사 러너 · 주간 보고(드라이런 → 발송) · 즉시 경보 | • **pi0 비트 동일 회귀**: 최근 tick 입력을 재생해 off/shadow 에서 전수 identical <br>• 불변식 ①~⑤ 주입(초과 attempt entry · `:547`/`:833`/`halt_no_jobs` 재현 픽스처) <br>• `MAXA > length(cells)` 픽스처에서 grid_consumed → exhaust <br>• K0~K9 발화 드릴 · 롤백 드릴 · 러너 돌연변이(삽입 줄 삭제 → red) <br>• 휴면 필터 양성 대조(catalog_id · 대소문자 충돌) | • shadow 기록 ≥ pol_cfg `shadow_min_weeks`(4주) <br>• 그 기간 B2~B7 블록 진입이 블록당 1건 이상(없으면 기간 연장) <br>• K 무발화 · 절단 대상 entry 의 halt 0 <br>• 주간 보고 ≥ 2회 · 킬 드릴 1회 <br>• **would_trim 회수 추정량**을 보고한다. 정의: Σ_entry(계획 n_cap − shadow n), 원장 재도출 [완R13] | R ~800줄 + 검사 ~700줄 · 3~4세션 + 벽시계 4주 |
| **O2 리플레이 + 첫 성과 소비형 live**(ORGANIC-DE 결정 뒤) | • 리플레이 어댑터 완성(`rf_organic_polstats` · π_R · 플라시보) <br>• 후보 정책별 unreachable·discovery_drop 기술 산출 → 사전등록 <br>• 사전등록: π_dorm(B2 휴면, 우선) · π_trim · π_soft · 조기 소진 p_stop 보정 <br>• 동시 대조 배정 사전등록 | • 양성: 개선을 심은 정책이 통과 <br>• 음성: π_R 탈락 <br>• peek: τ_D 이후 교란에도 판정 불변 <br>• 게이트 항목을 뺀 돌연변이 red <br>• live 결정 = 리플레이 결정(항등) | 정책 1건 이상 판정. live·철회·'미결' 모두 완료로 친다. <br>**'미결' 뒤 처리** [완R13]: 청정 증거가 `min_cells_block` 에 닿는 예측 시점(O0b 표)에 한 번 다시 판정한다. 두 번째도 미결이면 그 정책은 철회로 닫고, 부활 어휘(증거가 두 배가 됨)로만 다시 상정한다 | R ~600줄 · 3~4세션 + 벽시계 ≥ 8주 |
| **O3 선택 층 계기** | • `rf_select_value`(순위 벡터 · pi0 비트 동일 · `select_winner_by` 판독) <br>• 러너 선택부(`.winner_of` · 바닥 · best_val 분리 — 마커 기준) <br>• 결정 기록 7종: 러너 + `rf_promote.R`(승격) + `rf_combination_launch.R`(결합 개시) [완R13] <br>• AKM 구간 · X3 | • 격자 사본의 `select_winner_by` 를 바꾸면 결과가 변함 <br>• pi0 가 과거 결정과 비트 동일 <br>• best_val/`.wbest_val` 가 PT 척도를 유지(14760 promo3 픽스처) <br>• 기록된 chosen = 다음 블록 SPEC 이 승계한 값 | 결정 기록 7종 · shadow 일치율 보고. live 는 Q⑤ 결정 뒤에만 | R ~500줄 · 2~3세션 |
| **O4 구조 + 확장** | 블록 상태 정책 · `adv_asof` · 템플릿 canary · C-트랙 사전등록(2계층 재개 뒤) · 8주 메타 재검토 | 구조 판 고정 · 롤백 비트 복원 · canary 확대 조건 · C-트랙 메타데이터 포함 섭동 | 구조 정책 판정 · C-트랙 첫 성적표 · A4 자료 | 4~6세션 |

**합계**: 17~25 세션 + 벽시계 12주 이상(O1 4주 + O2 8주). v1 의 "O0 2~3세션"은 비교 기준보다 작았다. `remeasure_from_holdings.R` 하나가 942줄이고, P0 는 워크플로를 여러 번 돌렸다.

### 8.2 신규 config 키

`reinforce_auto_config.json` 에 둔다. 사람 소유이고 기계는 읽기만 한다. 키마다 `_source` 를 병기하고, 값과 분류는 부록 D 에 있다.

```
organic.enabled                                   false
organic.auto_live                                 false
organic.auto_live_decision_id                     ""        (도훈 resolved 결정 id — G4)
organic.canary_entries · canary_weeks_source      1 · "policy_state.R::pol_cfg$shadow_min_weeks"
organic.layers.{budget,space,select,structure}.mode   "shadow"
organic.select.live_allowed                       false     (조건부 가드 — ORGANIC-DE 결정 참조)
organic.epoch.{id, tau_upper_source, tau0_ratio_source, tau_lower_rule}
      tau_upper_source  = "constraint_defaults.json::diagnostics.oos_calendar_splits[1]"
      tau0_ratio_source = "essence_score.R::.ESSENCE_OOS_SPLITS$v2[1]"   (asof_window.R 안에서만 참조)
      tau_lower_rule    = "oos_calendar_splits[1] − diagnostics.window_allowance_months"
organic.asof.{pt_threshold_scaling:"sqrt_T", retention_denominator:"floor_is_fixed", dir:"06_Registry/organic/asof"}
organic.view.columns[]                            (어댑터 열 허용목록)
organic.evidence.{exclude_flags[], design_stratum:"stratify", min_cells_block_rule, min_lineages_block,
                  pairing_order:["floor_code","sig_restore"], pairing_rule:"unclassified_mismatch_zero",
                  exclude_blocks:["B5","B7"]}
organic.noise.{source_order:["control_cells_P1-06","stationary_block_bootstrap"], bootstrap_B, block_rule:"auto"}
organic.model.{shrink:"morris_peb", cluster_lever:"entry", cluster_block:"lineage_root",
               covariate_window:"le_tau0", outcome_window:"tau0_tauD", min_clusters_cr}
organic.budget.{n_min_by_block, delta_sigma, futility.{p_stop_rule, min_blocks, n_min_entry_source}, soft_child.enabled}
organic.space.{managed_blocks, n_min_arm_rule, min_detectable_effect_sigma, r_min_arm, dormant_p, revive_p, stable_share,
               dormant_weeks, retire_weeks_rule:"2*dormant_weeks", max_changes_per_week_source,
               quota_yield_window_rounds_source, probe_cells, retire_probe_failures}
organic.structure.{block_dormant_p_source, n_min_block_evidence_source, r_min_block_source, consecutive_windows,
                   n_diag, never_dormant, prereg_only, max_live_changes_per_week_source}
organic.select.{shadow_policies, ladder_kappa_source:"budget.delta_sigma", carry_p, promote_p_min, report_winner_ci}
organic.gate.{power_min_ratio:0.15, alpha:0.05, power:0.8, bootstrap_B, random_policy_seeds, placebo_perms,
              pol_cfg:"policy_state.R 기본값 인용", concurrent_control:{ratio:"1:1", block_size:2, seed}}
organic.kill.{eprocess_alpha, alpha, calib_rule:"binom95_of_0.8", stale_consecutive, state_max_age_rule,
              selftest_max_age_rule, oscillation_pause_source, release:{decision_id, at}}
organic.register.max_rows_per_week_rule
organic.tick.max_sec
organic.report.{weekday_source:"weekly_cleaner_sweep 직후 첫 tick", max_chars:4096, header:"[1계층·강화] 유기적 강화 주간"}
b5_budget.{enabled, standing_plus:2, compose_only_consecutive_rounds:(A2-e), restore_on_g2_pass:true}
      — D-G 이행 항목이 소유한다(유기체 아님)
```

- 판단값은 부록 D 에서 "판단 → A2-c"로 분류하고 `_source` 에 적는다.
- 보정은 사전등록으로만 한다. 결과를 본 뒤에 바꾸면 새 epoch 이고 N 도 새로 센다.

### 8.3 ORGANIC-DE 결정별 분기 계획 · 일몰 [완R13]

| 결정 | O0a | O0b | O1 | O2~O4 |
|---|---|---|---|---|
| (iii) + (a) τ_D (권고) | 그대로 | 그대로 | 그대로 | 계획대로 |
| (iii) + (d) B08 정합 | 그대로 | as-of 배치와 모형은 사람용 진단·보고 전용 | shadow 기록 유지 | 성과 소비형 정책은 폐기. 구조 사유 규칙(A5 류)과 회계만 남긴다. O3 는 결정 기록만 |
| (ii) 엄격 WF | 그대로 | τ_k 뷰로 확장(배치 창 = τ_k 격자) | 그대로 | 리플레이는 τ_k 순차 · C-트랙이 주 경로 · `selection_path_full_sample` 보류 코드 활성 |
| (i) 회계형 / (iv) τ_latest | 그대로 | as-of 층은 진단용 | 그대로 | 가드 "as-of 정보만"이 공허해진다는 점을 결정 문안에 기록한다. live 는 허용하되 N_program·N_policy 계상을 강화한다. 외부 성적표 창이 사라진다는 점을 보고한다 |

**프로젝트 일몰**
- 조건: O2 착수 후 사전등록 판정 2주기(= 2 × pol_cfg `shadow_min_weeks`) 안에 (가) live 에 도달한 정책이 0 이고, (나) 모든 정책이 '미결'이거나 π_R 과 구분되지 않는다.
- 이 조건이 서면 유기체를 **회계·기록 층(O0a + O1 shadow 기록)으로 동결**하고 추가 개발을 멈춘다.
- 이것은 벽이 아니라 사실 기록이다(AX-000). 부활 어휘: 청정 증거가 두 배가 되거나 epoch 이 바뀌면 다시 상정한다.

### 8.4 파일

**신규**
- `02_Infrastructure/contracts/asof_window.R`
- `02_Infrastructure/reinforcement/`
  - `rf_prereg.R`(최소 writer)
  - `rf_organic_ledger_adapter.R` · `rf_organic_view.R` · `rf_organic_model.R` · `rf_organic_policy.R`
  - `rf_organic_apply.R` · `rf_organic_replay.R`(09-18 엔진 어댑터)
  - `rf_organic_write.R` · `rf_organic_guard.R` · `rf_organic_weekly.R`
  - `rf_organic_scorecard.R`(외부 성적표 — 유기체 결정 파일이 아니다)
- `02_Infrastructure/ops/`
  - `rf_organic_tick.R`·`.sh` · `rf_organic_asof_batch.R` · `rf_organic_fit.R`
  - `rf_organic_audit.R`(K2) · `rf_organic_selftest.R`(K3 · 격리 루트) · `rf_organic_cmd.R`(사람 명령)
- `06_Registry/organic/`: `state.json` · `actions.jsonl` · `decisions.jsonl` · `schema.json` · `asof/` · `lever_book/` · `scorecard/` · `selftest/` · `flags/` · `runs/` · `report_sent/` · `snapshots/`
- `06_Registry/prereg/`(P2-01 과 공용 · layer 필드)
- `06_Registry/rf_trial_log.jsonl`(P1-02 정본)
- 검사 `08_Tests/reinforcement/`
  - v1 목록: `test_asof_window.R` · `test_rf_organic_view.R` · `test_rf_organic_model.R` · `test_rf_organic_asof_perturb.R` · `test_rf_organic_boundary.R` · `test_rf_organic_invariants.R` · `test_rf_organic_pi0_identity.R` · `test_rf_organic_kill.R` · `test_rf_organic_rollback.R` · `test_rf_organic_gate.R` · `test_dr_record_machine.R`
  - 추가: `test_rf_prereg_min.R` · `test_dr_register_concurrency.R` · `test_rf_reopen_entry.R` · `test_rf_organic_adapter_columns.R` · `test_rf_organic_dormant_catalog_id.R` · `test_rf_organic_replay_adapter.R`
  - `08_Tests/hooks/run_all_hooks.sh` SUITES 에 명시 편입한다(글롭 금지)

**v1 대비 삭제**: `rf_organic_rules_human.R`. 사람 규칙은 유기체 밖 D-G/P1-08 이행 항목 파일로 옮긴다.

**수정 (국소 · 줄 번호 대신 함수·마커 기준 — 병합할 때 다시 읽는다)**

| 파일 | 변경 | 단계 |
|---|---|---|
| `ops/reinforce_auto_parallel.R` | 원장 적재·`.RCTX` 직후 2줄 · 상주 칸 삽입 끝 1줄 | O1 |
| 〃 | `.winner_of`(argmax·best_val 분리) · 바닥(`.wbest_val`) · 결정 기록 | O3 |
| `reinforcement/reinforce_ledger.R` | kinds · decision_id · `dr_record_machine` · 공용 claim + CAS · `M-ORG-` 거부 · 무인/기계 문맥 stop · 증거 레거시 규칙 · `rf_trial_log_append` · `rf_reopen_entry` · 레지스터 계약 주석 개정 | O0a |
| `ops/rf_weight_arms.R`(`rf_pick_weight_arms`) · `reinforcement/rf_block_design.R`(`rfbd_catalog`) | 휴면 제외 1줄씩(`catalog_id`) | O1 |
| `ops/rf_overlay_arms.R` | 휴면 제외 1줄 | O4 |
| `ops/rf_weight_catalog_grow.sh` | 쿼터 판독 | O1 |
| `ops/reinforce_auto_tick.sh` | L2 뒤·러너 앞 1줄 + idle 분기 | O1 |
| `reinforcement/rf_runner_gates.R` + `a_eligibility_gate.json` | P0-14 보류 코드 `organic_policy_selected`(비활성)를 한 커밋으로 · `rf_select_value`(O3) · (선택) `selection_path_full_sample` | P0-14·O3 |
| `reinforcement/rf_promote.R` · `rf_combination_launch.R` | 결정 기록 배선 | O3 |
| `hooks/arm_gen_read_guard.sh` | MEASURE_RE 에 `06_Registry/organic/`(scorecard 포함) | 동시 수리 배포 뒤 |
| `hooks/safety_guard.sh`(선택) | 레지스터 · auto_live · kill.release 직접 편집 차단 패턴 | 동시 수리 배포 뒤 |
| 문서 | qvest-telegram SKILL §5.6b 행(주간 보고 · `[무인]` 경보) · reinforce SKILL §0.3 포인터 · judge.md selection 정직성 축(유기체 재현 — 도훈 승인) · 부팅 `Rules:` 줄 → `Organic:` 줄 제안(층별 mode · killed · 마지막 live 변경 · 미결 블록 수) · CHANGELOG | O1 |

**유기체 밖 이행 항목 파일(D-G·P1-08 — 참고)**: `ops/reinforce_auto_next_paper.R`(FIFO) · `reinforcement/rf_runner_gates.R::rf_budget_auto`(B5 가산 차단) · `b5_budget` 키 · overlay_propose G1 경유 확인.

---

## 9. 하지 말 것

1. 유기체 입력(적합·결정·킬·재료·사전)에 τ_D 이후 수익이나 전기간 파생 필드(essence·등급·적대검증 판정·retention·DSR·서류)를 넣지 않는다. 레버 감사 Δ 표를 위치 사전이나 척도 사전으로 쓰지 않는다.
2. τ_D 를 전역 리터럴로 박지 않는다. 칸별 단언 없이 "등급 OOS 와 분리된다"고 주장하지 않는다.
3. τ_D holdout 을 기계 입력 밖으로 넓히지 않는다. 사람·등급·Judge·BOOK·전략 구현·격자 선택은 전기간을 쓴다. 도훈이 예외(ORGANIC-DE Q③)를 승인하기 전에는 τ_D 로 거른 결정을 live 로 쓰지 않는다. "lockbox 가 아니다"라는 어휘 논증으로 lockbox 폐지 조항을 우회하지 않는다 [헌M3].
4. 시도가 있는 코드를 절단하지 않는다. 빈 칸이 남는데 칸 수를 used 이하로 만들지 않는다(불변식 ④). 진입 블록의 계획을 덮어쓰지 않는다. B1 을 자르지 않는다. 조기 소진으로 B4 를 자르지 않고, B4 전 승자 결합 칸을 지우지 않는다(불변식 ⑤). 설계 칸 수 아래로 n_cap 을 잡지 않는다.
5. `max_attempts`·daily_cap·parallel_cells·격자 n 을 기계가 움직이지 않는다. 칸을 늘리는 결정은 canary 밖에서 하지 않는다. 블록 순서 최적화를 재투입하지 않는다(09-18 NO-GO). G2 pass 0 동안 B5 를 늘리지 않는다.
6. 정본 카탈로그 3종·factor_registry lifecycle·`reinforce_program.json`·`constraint_defaults.json`·`a_eligibility_gate.json`·`pit_quarantine.json`·원장·`reinforce_auto_config.json` 에 기계 쓰기 경로를 만들지 않는다. 휴면은 유기체 목록으로만 한다.
7. `vintage_flags` 에 유기체 태그를 쓰지 않는다(flags `*` 라 A 가 자동 보류된다). 태그는 시행 로그에만 쓴다.
8. 선택 층을 ORGANIC-DE 결정 전에 live 로 올리지 않는다. 한 argmax 에 두 창을 섞지 않는다. 순위 값을 carry 게이트 척도(best_val·`.wbest_val`)에 흘리지 않는다.
9. AAC 를 후보·증거·엘리트 필터로 쓰지 않는다(τ 이후 누출). 진단 곡선으로만 쓴다.
10. `adv_circular_block_perm` 을 SE 원천으로 쓰지 않는다. 위상쌍 B6_32/33 을 SE 원천으로 쓰지 않는다. 짝지은 하한 >0·P(Δ>0) 를 하드 승격·carry 규칙으로 쓰지 않는다(플랜 '하지 말 것' 5).
11. C1 표식 칸을 "Δ 에서 상쇄된다"는 이유로 증거에 남기지 않는다(합리화 = 위반).
12. 기계가 `dr_open`/`dr_resolve` 를 부르지 않는다. `dr_record_machine` 은 허용 scope 밖을 기록하지 않는다. status 에 enum 밖 값을 쓰지 않는다.
13. 외부 성적표 수치를 킬스위치·canary 확대·정책 선택 입력으로 되먹이지 않는다.
14. "EW−CW 틸트 중립 선호"를 유기체 효용·사전·생성 표적에 넣지 않는다. 그 지식은 τ 이후 관측이다 — 사람의 사전등록(PR-L1)으로만 다룬다.
15. 새 훅을 등록하지 않는다(`arm_gen_read_guard` 정규식 확장만, 동시 수리 뒤). 새 LLM 진입 함수를 만들지 않는다. 유기체가 LLM 을 부르지 않는다.
16. Q-Lead·python 으로 사후를 계산해 결정에 쓰지 않는다(AX-008). 양방향 검증 없는 가드를 방어선에 올리지 않는다.
17. 미결·휴면·퇴역·π_R 구분 불가를 '벽'이나 '한계'로 적립하지 않는다(AX-000). 사람이 붙인 tombstone·C11 suspended 를 기계가 되살리지 않는다.
18. 옛 규약(close_d_legacy)·rebase 전 수치를 증거에 섞지 않는다. B7·B1 폴백 과거 칸을 as-of 규칙으로 "재측정"하지 않는다(새 규칙 = 새 칸).
19. 러너 재개를 유기체 준비에 묶지 않는다. 유기체가 off 여도 러너는 돈다. 단 P0-14 는 러너 재개 전 필수다.
20. 사람 규칙이라는 이유로 성과 소비형 자동 규칙을 유기체 안에서 live 로 켜거나, G2 봉쇄에서 면제하지 않는다. D-G 의 성과 분기는 Q②′ 결정 뒤에 유기체 밖 항목으로만 배포한다 [헌M1].
21. 과거 LLM 설계 칸 501개를 일괄 보류하지 않는다. 교차 entry 노출이 파일별로 도출된 칸만 보류한다. 자기 entry 측정표 노출은 기결정(유지)이다 [헌M4].
22. 결정 레지스터에 잠금 없이 쓰지 않는다. 기계 id 를 `M-ORG-` 밖에서 만들지 않는다. 증거 규칙을 통과시키려고 09-23 일괄 결정을 소급 편집하지 않는다 [헌M9·완M4].
23. `epoch.id` 를 킬 해제 수단으로 쓰지 않는다. auto_live 와 킬 해제는 도훈 결정 id 참조 없이 인정하지 않는다 [헌M8·완M8].
24. 새 스케줄 작업을 만들지 않는다(기존 tick 의 idle 분기만 쓴다). 측정 원본 디렉터리(`remeasure_close_t1_*`)에 as-of 산출을 쓰지 않는다 [완M9·헌R2].
25. B 모듈 공급 수치와 외부 성적표를 기계 게이트 입력으로 쓰지 않는다. 사람이 판단하고 N_meta 로 센다 [완R2].
26. 판단값 파라미터를 결과를 본 뒤 바꾸지 않는다. 바꾸려면 사전등록과 새 epoch 을 거친다. 판단값이 09-03 근거 의무 해제 범위에 드는지는 A2-c 결정 전까지 "판단 → O2 보정" 라벨로만 쓴다 [헌M13].

---

## 10. 도훈 결정 안건 (최소화 — 기계 권한 밖이거나, 기결정의 문안이 모호한 것만)

| # | 안건 | 선택지 | Q 권고 | 결정 전 기본값 | 막는 것 |
|---|---|---|---|---|---|
| **A1** | **ORGANIC-DE** — §2.6 · Q① ② ②′ ③ ④ ⑤ | 해석 (i) / (ii) / (iii) / (iv) · τ = (a) τ_D / (b) τ_latest / (c) τ_k / (d) start_date | **(iii) + (a)** · 두 예외(B08 대비 완화 · lockbox 기계 입력 holdout)를 명시해 요청 · Q②′ (α) 고정 규칙 예외 · Q④ (a) 노출 칸만 A 보류, 재측정 금지 | 유기체 live 0 · D-G 성과 분기는 shadow · 격자 pi0 · 교차 entry 노출이 도출된 칸만 `possible` | O2 live · O3 live · C-트랙 A · D-G B5 축소 live |
| **A2** | **ORGANIC-SUPERSEDE** — ORGANIC 자율과 기결정·파라미터의 관계 | (a) D-G 레인 고정 순서: 유지 / 적응 대상 <br>(b) D-F "E2 통과 규칙만 live" + P1-07 E2: 유기체 G4 로 대체 / 별도 유지 <br>(c) **컨트롤러 파라미터 판단값**(부록 D 의 '판단 → A2-c' 14개)이 09-03 근거 의무 해제 범위에 드는가, 아니면 O2 보정·사전등록으로 확정하는가 <br>(d) P1-07 H1 지표: τ 이후 OOS 활성 IR 유지 / 두 단 창으로 교체 <br>(e) D-G 'compose_only 지속'의 수치(연속 라운드 수) <br>(f) `graduation.improvement_check`(죽은 선언) 삭제 <br>(g) **결정 문안 대비 축소를 인정할지** [헌R5]: 이 설계는 arm 생성 0, 줄이기·복원만, select live 조건부로 "완전 자율" 문안보다 좁다 <br>(h) S_τ 의 θ_PT·√T 환산을 π_S live 시 A-거리 정의로 쓸지 [헌R12] | (a) 유지 <br>(b) G4 로 대체(유기체 층 한정) <br>(c) 해제 범위 밖 — 판단값은 "판단 → O2 보정" 라벨과 사전등록으로만 확정 <br>(d) 두 단 교체 <br>(e) `stagnation_window` 와 같은 값(2 라운드)을 compose_only 연속 라운드에 적용 — 도훈 확정 <br>(f) 삭제 <br>(g) 축소 인정. arm 생성은 기존 설계 레인·입장 관문이 이미 하고 있다 <br>(h) 진단 전용(판정 인용 금지)으로 유지하고, π_S live 전에 재상정 | 권고안과 같은 보수판 · 판단값은 shadow 에서만 쓰인다 | O2 게이트 판정식 확정 · D-G B5 축소 배포 |
| **A3** | ORGANIC-N(D-A′) — 유기체 아래에서 DSR 게이트의 N | 계보 N 유지 / 계보 N + 적응 결정 대안 수 / 프로그램 N | **계보 N 유지**(D-A · D-A-N-TIMING) + 서류에 N_program·N_policy·N_meta 병기를 **의무화** | D-A | 없음(서류 항목만) |
| A4 | COMPOSITE-OBJECT — C-트랙 합성을 A·Judge·BOOK 대상으로 인정할지 | 예 / 아니오 / C-트랙 첫 성적표 뒤 | **첫 성적표 뒤 상정**(지금 결정할 사실이 없다. 2계층 재개도 FR-REMEASURE-PREREG 뒤다) | 보고만 | C-트랙 A 발행(O4) |
| **A5** | **B3-STRUCTURAL-TRIM**(신설 · 성과 비소비 사람 규칙) — B3 를 진단 1칸(diag)으로 줄이고, B3 를 참조하는 B4 칸을 뺀다(단 불변식 ⑤ 의 전 승자 결합 칸은 보존) [완M12] | 승인 / 기각 / 유기체 π_trim 판정에 맡김 | **승인**. 근거는 구조 사실만 쓴다: P0-12 유니버스 k200 한정 × 09-05 승격 carry 유니버스 리셋 → B3 승자의 하류 소비자가 없다[감사]. "B3 계보 PT·Calmar 양수 0/24" 같은 성과 수치는 근거에서 뺀다(넣으면 성과 소비가 된다). O0a 에서 구조 사실을 코드로 재확인한 뒤 상정한다 | 현행 격자 | 처리량 경로 ①(b) |

- 별건은 없다. v1 의 'PR-L1 A4'는 PR-L1-A4-DISPOSITION 으로 해결됐다(삭제 · N 미계상) [헌M4].
- 안건이 아닌 것(기계 권한 안): 정책 가족 구성 · 휴면·축소 판정(live 는 A1 뒤) · 쿼터 · 도출 파라미터.

---

## 11. 최소 경로 — 러너 재개와 함께 켤 수 있는 것

**전제 (러너 재개 전 필수 — RUNNER-RESTART-AFTER-P0-14 결정 내용)**
1. P0-14: 관문 시점 계보 기반 표식 도출(동시 워크플로 소관 · 요구사항은 §6.2).
2. 잔여 수리 배포: P0-13 충실구현 A 관문 · 설계 레인 전기간 IC 통로 · B08 상한 · B09 probe · safety_guard 여러 줄. 그리고 B07 배포.
3. 재개 실행(config `enabled=true`)은 배포 완료 보고 뒤 **Q 가 수행**한다. 이미 결정된 사항이다. v1 의 "도훈 재개 지시 대기"는 낡은 서술이다 [헌M4·완M5].

**러너 재개와 함께 켤 수 있는 것 — 유기체 밖**

| 켜는 것 | 상태 | 근거 |
|---|---|---|
| P1-08 FIFO · D-G 레인 순서 · 세대당 신규 논문 ≥1 | live(유기체 밖 이행 항목) | D-G · 성과 비소비 |
| overlay_propose G1 경유(확인·배선) · `rf_budget_auto` 가산 차단 | live(유기체 밖) | D-G · 레버 감사 ④-3 |
| D-G B5 축소 · 'dead 동안 정지' | **보류**(Q②′ 결정 뒤) | 헌M1 |
| B3 구조 축소 | 보류(A5 결정 뒤) | 완M12 |

**유기체 — 첫 단계(O0a) 착수 전제**
- ORGANIC-DE 는 O0a 착수의 전제가 **아니다.** O0a 는 결정을 내리지 않고, 어느 분기로 결정되든 쓰인다(§8.3).
- 필요한 것은 세 가지다.
  - ① 동시 수리 워크플로 배포 완료. `reinforce_ledger.R`·`rf_runner_gates.R` 편집 충돌을 피하기 위해서다.
  - ② 세션 배정이 §8.0 순서(라운드·A 레버 우선)와 충돌하지 않을 것.
  - ③ O0a 세션 상한 6 에 대한 도훈의 사전 동의.
- O1(shadow) 착수 전제: O0a·O0b 전 검사 green · P0-14 배포(유기체 태그 판독 경로) · 러너 재개 뒤 tick 이 안정적임을 확인.

**켜지 않는 것**: 유기체 live 전부 · 선택 층 live · 구조 변경 · 템플릿 · C-트랙 · D-G 성과 분기.

**O1 4주 뒤 기대 산출(사실만)**
- would_trim 회수 추정량(원장 재도출)
- 청정 증거 풀 크기와 블록별 결정 가능 시점
- dg_shadow 대조
- 주간 보고 2회 이상 · 킬 드릴 결과

이것이 A1·A2·A5 결정 자료가 된다.

---

## 부록 A. 3관점 심사 반영표 (v1 통합 시점 — 이력으로 유지 · 최종판의 변경은 부록 A2)

| 출처 | 결함·요구 | 반영 |
|---|---|---|
| 심사1·3 wf | G7 "기존 writer 가 owner 위조 거부" 거짓 | `dr_record_machine` 신설 · 기계 문맥 `dr_*` stop · 정적 토큰 0 · 결정 참조 시 recorded_by·evidence 확인 · 한계 명시(§3 G7) |
| 심사1·2·3 wf | 탐색 층 τ_latest → as-of 공허 · G2 섭동 발화 불가 | 유기체 전 층 τ_D(재도출·고정). (iv) 는 비권고 선택지로만 남김 |
| 심사1 wf | arm 휴면을 R 형(C1 아님)으로 분류 → D-E 문언 'arm' 과 충돌 | 휴면 통계 as-of τ_D · A1 Q② 로 명시 상정 |
| 심사1·2 wf | D-G 레인 고정 순서 '폐기' 단정 | 철회 — 상위 제약 유지 · A2(a) |
| 심사1 wf | `rf_wf_composite.R` 정적 금지 대상인데 essence 호출 · judge_request_WF 경로 allowlist 부재 | C-트랙을 유기체 밖(2계층 단위)으로 분리 · 계약 파일 분리 · judge_request 미생산(A4 전) |
| 심사1·evo | P0-14 "derive 재사용" 거짓 | 운영 함수 신설로 정정(§6.2) |
| 심사1 wf | 합성 보유 서술 부정확 | "구간 안 비중은 구간 안 시그널일에 칸 규칙으로 정해지고, PIT 는 칸 규칙이 PIT 이기 때문"으로 C-트랙 사양에 반영 |
| 심사2 wf **치명** | AAC 필터가 τ_k 이후 정보를 싣는다 · 섭동 검사가 못 본다 | AAC = 진단 곡선만 · C-트랙 허용 집합 = H2-free ∧ H1clean · 메타데이터 포함 섭동(§1.5) |
| 심사2 wf | MinBTL 을 N=4 로 오적용 | τ_k 별 \|A_k\| 로 재산출(§1.5) |
| 심사2 wf | S_b 부호 일치(m=4, 0.75)의 귀무 확률 0.31 | 폐기 — 시간 안정성은 두 단 리플레이 + 계보 군집 부트스트랩 부호 안정으로 대체 |
| 심사2 wf | EB 식에 Tweedie 표기 | Morris(1983) 모수 EB 로 정정 |
| 심사2 wf | decision_id 초 단위 충돌 | 밀리초 + 순번 + payload 해시(O0) |
| 심사3 wf **치명** | n_b ≤ 격자 n 이 설계 칸(B1 ≤15 · B5 ≤8) 절단 · 09-04 지시 위반 | n_cap = max(격자, 설계) · B1 절단 제외 · 결정론 보존 순서(§1.1) |
| 심사3 wf | rf_select_value 가 J 를 흘리면 carry 게이트 무성 퇴화 | 순위 벡터 전용 · best_val·`.wbest_val` = `.metric(·, by)`(§1.3) |
| 심사3 wf | 확약 층이 적응 층 live 경로를 무겁게 함 | C-트랙 분리 · 적응 층 live 에 필요한 안건 = A1 하나 |
| 심사3 wf | 셸 전역 `QVEST_POLICY_UNATTENDED=1` 설정 | `pol_transition(env = list(...))` 명시 인자 |
| 심사3 wf | 1,238칸 × τ 37 산출을 tick 안에서 | idle 배치(자기 claim · 시간 상한) · 창 3개로 축소 |
| 심사1 bayes | E2 가 C1 칸 561 을 타 블록 증거로 남김("대부분 상쇄") | 전 블록 제외(E2) |
| 심사1 bayes | 전기간 파생 필드(적대검증 판정·T3·등급 B 게이트)가 as-of 증거에 섞임 | B5 증거 제외(as-of 적대검증 전) · 등급·판정 입력 금지 · bt_result 수준 섭동으로 검사 |
| 심사1·2 bayes | K3·canary 가 τ 이후 창 소비 · "채점 전용 창" 모순 | 킬·canary 는 내부 계기만 · τ 이후는 사람 전용 외부 성적표 · 해당 어휘 삭제 |
| 심사1 bayes | lockbox 긴장 은폐 | §2.5 명시 · A1 Q③ |
| 심사1·2·3 공통 | 전역 τ=2016-11-30 이 590/1,193칸의 등급 OOS 를 먹음 | τ_D 재도출(최소 분할점) + 칸별 fail-closed 단언 |
| 심사1 bayes | 초사전 척도를 전기간 분산에서 | 사전 분포 없음 · 척도는 as-of 풀에서 추정 |
| 심사2 bayes | σ 원천이 순열 함수 → SE 과소 | 복원 정상 블록 부트스트랩(공통 인덱스 3계열) · `adv_block_len` 만 재사용 |
| 심사2 bayes | entry(바닥) 무작위효과 부재 | 레버 추정 = entry 군집 강건 · 블록 = 계보 군집 강건 |
| 심사2 bayes | Half-Normal Gibbs 는 켤레 아님 | Gibbs 폐기 → Morris EB(닫힌 식). 계층 모형은 I2 실패 시 O2 shadow 대안 |
| 심사2 bayes | arm 식별 67칸 → 135칸 | 정정(§0.2 ②) · n_min_arm 근거에 반영 |
| 심사2·3 bayes | trim 불변식 부재 | 불변식 ①②③ + K9 + 위반 주입 검사 |
| 심사2 bayes | P1-07 E2 재정의는 D-F 정의 변경 | A2(b) 로 상정 |
| 심사3 bayes **치명** | 절단으로 pending 코드 소실 → 영구 정지 | 불변식 ① · 절단은 `rf_organic_cells` 안에서 재단언 |
| 심사3 bayes **치명** | 감산을 `E$max_attempts` 에 써서 수동 채널 오염·핑퐁 | `max_attempts` 무접촉 — 격자 소진 경로 |
| 심사3 bayes **치명** | E1 키 문자 대조(전부 불일치) · E6 mtime 등식 | E1 = `rf_candidate_facts(..,"regime")` · E6 = P0-07 지문 동치 · 증거 하한 미달 = 미결(fail-loud) |
| 심사3 bayes | Thompson 배치마다 재추첨 | Thompson 미채택(결정론 비례 규칙 · 블록 진입 시 동결) |
| 심사3 bayes | as-of 뷰 산출이 워커 실패로 번짐 | 워커 밖 idle 배치 |
| 심사1·3 evo **치명** | status='enacted' → `dr_load` 파손 | status=resolved 만 |
| 심사1·2·3 evo **치명** | 정본 카탈로그·registry 에 기계 쓰기 | 쓰기 0 · 유기체 휴면 목록 + 픽커 제외 1줄 |
| 심사1·2 evo | `selection_asof` 라벨 = 거짓 청정 증명 | v1 은 라벨 미발행(격자 live = pi0). 향후 라벨은 관문 시점 계보 전체(선택 노드·H1clean·설계 출처)에서 도출 |
| 심사1 evo | OOS 분리 절대 주장 | 칸별 단언 |
| 심사1 evo | δ1 기술자에 τ 이후 지식 · 저틸트 편애 | MAP-Elites 틈새·기술자 미채택(v1). 재도입 시 사전표본·문헌 기술자 + `post_tau_informed` 라벨 |
| 심사1 evo | d_A 체비쇼프 = D-F(S) 이탈 | 효용 = as-of S(D-F 정합) |
| 심사2 evo | "측정 전 선별 없음"이 휴면·반감과 모순 | 측정 중지 결정의 근거 칸을 N_program 에 계상(§4) |
| 심사2 evo | 36 틈새 희소 → 틈새별 승자의 저주 | 틈새 미채택 |
| 심사2 evo | d_A PT 문턱 창 길이 보정 | θ_PT·√(T_τ/T) 적용(§1.0 f) |
| 심사2 evo | 가산 정책 canary · 주간 반복 UCB/LCB 순차 오류 | 가산 = canary · 반복 구간 검정 미사용 · 감시는 e-과정(언제든 유효) |
| 심사2 evo | (τ₀, τ*] 에 GFC 없음 → Calmar 정책 검정력 ≈0 | 검정력 관문 · 미결 최빈 사전등록(§3.4 ④) |
| 심사2 evo | 미확인 서지 9건 | O0 산출에 서지 대조 포함(부록 B 상태 표시) |
| 심사3 evo **치명** | shadow entry 를 원장에 씀 | shadow entry 미채택 — 새 arm 은 기존 생성 레인·입장 관문으로만, 유기체는 휴면·쿼터만 |
| 심사1 권고 | D-E 안건 통합 상정 | A1 하나(Q①~⑤) + A2 로 분리한 기결정 관계 |
| 심사2 권고 | π_R · e-과정 · Brier · 검정력 · live=리플레이 항등 · 선택 인플레 | 전부 반영(§1.3 · §3 · §7) |
| 심사3 권고 | 자동 live env 명시 인자 · 무거운 산출 idle | 반영 |
| **통합 추가 발견** | 설계 재료 29건에 앞 칸 전기간 PORT_t·MDD·Calmar 서술 → LLM 설계 칸 PIT 지위 미정 · 현 A 관문 미포착 | A1 Q④ · P0-14 범위 권고 · 결정 전 A 보류 |
| **통합 추가 발견** | `a_eligibility_gate` vintage_flag flags `*` | 유기체 태그를 `vintage_flags` 에 쓰지 않음(§3 G1) |

---

## 부록 A2. 비평 2종 반영표 (최종판)

### A2.1 수정 필수 26건

| 출처 | 결함 | 최종판 반영 위치 | 상태 |
|---|---|---|---|
| 헌M1 | π_DG·쿼터 0 을 live 로 두면 "as-of 정보만" 가드 위반 · RUNNER-RESTART 와 충돌 · B5 설계 쿼터는 D-G 초과 | §1.1 '유기체 밖 사람 규칙' · §1.2 쿼터 · §2.6 Q②′ · §11 · §9-20 | 반영 |
| 헌M2 | B08 을 '성과 비사용'으로 오기 · τ_D 는 B08 대비 완화 | §0.2⑤ · §2.1 · §2.3 Q③(d) · §2.4 · §2.5 · §8.3 | 반영 |
| 헌M3 | τ_D 는 기능상 holdout — 어휘로 lockbox 조항 우회 | §0.1 · §0.2① · §1.0(b) · §2.5 · §2.6 Q③ · §9-3 | 반영 |
| 헌M4 | Q④ 가 D-E-B5-MATERIALS 와 충돌 · 501칸 일괄 · 낡은 기술 3곳 | §0.2③ · §0.5 · §2.2 · §2.6 Q④ · §10(별건 삭제) · §11(재개 결정) · 부록 C(78건) | 반영 |
| 헌M5 | A 관문이 유기체 provenance 를 못 봄(22632 부류) | §3 G1 · §4-7 · §5 판정 경로 · §6.2③ · F18 | 반영 |
| 헌M6 | G2 정적 봉쇄 자기모순 | §1.0(d) 어댑터 1파일 면제 · §3 G2 | 반영 |
| 헌M7 | G3 writer 부재 · 저장소 이원화 | §3 G3 · §6.3 P2-01 · §8.1 O0a | 반영 |
| 헌M8 | 킬 해제·auto_live 가 표기로만 보호 · 무인 레인 `dr_resolve` 가능 | §3 G4·G5 · §3.1.1 ① · §5 사람 명령 경로 · §9-23 | 반영(safety_guard 확장은 선택 — 부록 E) |
| 헌M9 | G7 경합·id·계약·증거 규칙 결함 | §3.1.1 · F17 · §9-22 | 반영 |
| 헌M10 | 롤백이 러너 실현 효과(소진)를 못 되돌림 | §3 G6 `rf_reopen_entry` · §3.3 · F16 | 반영((a) 채택 · (b) 미채택 사유 부록 E) |
| 헌M11 | 조기 소진이 B4 를 자름 | §1.1 조기 소진 · 불변식 ⑤ · §9-4 | 반영 |
| 헌M12 | K2·K3·K8·G8 실행 주체·트리거 부재 | §3.2 표 '실행 주체' 열 · §3 G8 · §8.0 트리거 | 반영 |
| 헌M13 | 하드코딩(근거 없음·오류·리터럴·빈 키) | §1.1~§1.4 파라미터 표 · §7 I2 · §8.2 · 부록 D · A2-c | 반영 |
| 완M1 | used > 고유 코드 entry 에서 절단 뒤 `halt_no_jobs` 영구 정지 | §0.2④ · §0.5 · §1.1 불변식 ④ · F3 · O1 검사 | 반영 |
| 완M2 | "축소 정책 전부 리플레이 가능" 거짓 · 09-18 엔진 미인용 | §0.5 · §1.1 조기 소진 · §3 G4 · §3.4 | 반영 |
| 완M3 | G2 대 뷰 모순 · `grade` 부분일치 오탐 | §1.0(d) · §3 G2(정확 일치 토큰) | 반영 |
| 완M4 | G7③ 이 09-23 결정을 거부 · 레지스터 잠금 없음 | §3.1.1 레거시 증거 규칙 · 공용 claim + CAS | 반영 |
| 완M5 | 설계 전후 도훈 결정 4건과 어긋남 | §0.1 · §0.2⑤ · §1.1 · §2 · §10 · §11 | 반영 |
| 완M6 | 선행 코드 부재인데 단계·규모 없음 | §0.5 · §6.3 · §8.1 O0a | 반영 |
| 완M7 | D-G 창 단위 오류 | §0.5 · §1.1 · §1.2 · A2-e | 반영 |
| 완M8 | 문턱 없는 가드 · 킬 해제가 epoch 에 묶임 | §3.2 · §3 G5 · 부록 D | 반영 |
| 완M9 | 실행 트리거 미정 | §8.0(기존 tick idle 분기 · 새 스케줄 0) | 반영 |
| 완M10 | live 효과에 동시 대조 없음 | §3.4 ⑨ · K8 | 반영 |
| 완M11 | EB 공변량 기계적 편향 | §1.0(h) · O0b 검사 | 반영 |
| 완M12 | 레버 감사 #2 실현 경로 막힘 · +0.3~1.0%p 근거 없음 | §0.3 재추정 · §6.1 · A5 · O0b 결정 가능 시점 | 반영 |
| 완M13 | 규모 과소 · 우선순위 충돌 미처리 | §0.3 · §8.0 · §8.1 | 반영(재추정은 판단값 — 부록 E) |

### A2.2 권고 28건

| 출처 | 권고 | 반영 위치 | 상태 |
|---|---|---|---|
| 헌R1 | factor_registry git 추적 원본 denylist | §5 denylist | 반영 |
| 헌R2 | as-of 산출을 측정 원본 디렉터리에 쓰지 않기 | §1.0(c) · §5 · §9-24 | 반영 |
| 헌R3 | 휴면 제외 키 `catalog_id` | §0.5 · §1.2 | 반영 |
| 헌R4 | Q⑤ = SEL-DISCIPLINE (B) 재상정 · 조건부 가드 | §1.3 · §2.6 | 반영 |
| 헌R5 | 결정 문안 대비 축소 인정 질문 | A2-g · 아래 A2.3 | 반영 |
| 헌R6 | undo 문자열 | §3 G4 | 반영 |
| 헌R7 | posterior 저장소 단일화 | §1.0(h) · §6.3 P3-01 | 반영 |
| 헌R8 | 텔레그램 형식 | §3 G8 · §3.2 | 반영 |
| 헌R9 | 템플릿 대 금지 목록 · B7 prereg_only | §1.4 | 반영 |
| 헌R10 | L691 방향 | §4-4 | 반영 |
| 헌R11 | 잡음 척도 원천 불일치 | §0.2② | 반영(어느 σ 가 옳은지는 판정하지 않음 — 부록 E) |
| 헌R12 | θ_PT √T 라벨 · A2 | §1.0(f) · A2-h | 반영 |
| 헌R13 | 외부 성적표 경로 · N_meta | §3.5 · §4 · §5 · §7 | 반영 |
| 헌R14 | K5 환산 · improvement_check · τ₀ 위치 | §3.2 K5 · A2-f · §1.0(d) | 반영 |
| 완R1 | P0-14 양성 대조·도출 규칙 | §6.2 | 부분(스크립트 이관은 P0-14 소관 — 부록 E) |
| 완R2 | 2계층 경계 · B 공급 | §1.5 · §3.4 · X6 · F19 | 반영 |
| 완R3 | Judge 경계 · 6축 추가 | §4-8 | 부분(judge.md 개정은 권고만 — 부록 E) |
| 완R4 | 도훈 관측 경로 | §3.2 즉시 경보 · §5 사람 명령 · §3.5-8 · §8.0 · §8.4 | 부분(부팅 줄은 제안만 — 부록 E) |
| 완R5 | 레지스터 오염 방지 | §3.1.1 | 반영 |
| 완R6 | τ_D 도출 강건성 | §1.0(b) | 반영 |
| 완R7 | S_τ 포화 점검 | §8.1 O0b | 반영 |
| 완R8 | B5 재설계·B4 결합 | §1.1 불변식 ⑤ · B5 재설계 | 반영 |
| 완R9 | 4영역 추적표 | 아래 A2.3 | 반영 |
| 완R10 | 줄 번호 앵커 | §1.1 · §8.4 | 반영 |
| 완R11 | 동시성 | §1.1 tick 순서 · §5 원자 쓰기 · K1 | 반영 |
| 완R12 | 레버 감사 처분 누락 | §1.1 rf_budget_auto · §6.1 · §6.3 | 반영 |
| 완R13 | 완료 판정 구체화 · 분기 · 일몰 | §8.1 · §8.3 | 반영 |
| 완R14 | E3 폴백 오분류 | §1.0(e) | 반영 |

### A2.3 REINFORCE-ORGANIC-AUTONOMY 4영역 추적표 [완R9·헌R5]

| 영역 | 최종판 v1 상태 | 사유 | 활성 조건 |
|---|---|---|---|
| 예산 배분 | 계획 계산만 shadow · 줄이기와 복원만 | ORGANIC-DE 전 · RUNNER-RESTART | A1 결정 + O2 판정(G4) · 동시 대조 |
| arm 생성/퇴출 | 퇴출 = B2 휴면(shadow) · 생성 = 기존 설계 레인·입장 관문 담당(유기체는 쿼터 축소만) | 유기체가 arm 을 생성하면 LLM 이나 코드 생성이 결정자가 된다 — 설계 레인이 이미 생성자다 | 퇴출: A1 + G4 · 생성 확대: A2-g |
| 선택 기준 | shadow 정책 가족 + 결정 기록 | 판정식이 없는 결정이다 · SEL-DISCIPLINE (B) 를 다시 올리는 일이다 | Q⑤ 결정 |
| 블록 구조 | 상태 계산 shadow · 템플릿 canary 는 O4 | 증거 부족 · 가산 정책은 리플레이로 판정할 수 없다 | A1 + G4 · 템플릿은 confirmed + 사람 등재 |

---

## 부록 B. 문헌 (원문 링크 · 대조 상태)

대조 상태:
- ● = 설계 패널 세션에서 원문 제목·저자를 대조함(evo arXiv 8건 · bayes crossref 보고)
- ○ = 이번 통합 세션에서 대조하지 않음 → **O0 착수 전 대조**(심사2)

| 문헌 | 쓰임 | 링크 | 상태 |
|---|---|---|---|
| Morris (1983) Parametric Empirical Bayes Inference: Theory and Applications, JASA 78(381) | 레버 EB 축소 | https://doi.org/10.1080/01621459.1983.10477920 | ○ |
| Efron & Morris (1975) Data Analysis Using Stein's Estimator | 축소 | https://doi.org/10.1080/01621459.1975.10479864 | ● |
| Cameron & Miller (2015) A Practitioner's Guide to Cluster-Robust Inference, J. Human Resources 50(2) | 군집 강건 SE | https://doi.org/10.3368/jhr.50.2.317 | ○ |
| Politis & Romano (1994) The Stationary Bootstrap, JASA 89(428) | 복원 블록 부트스트랩 | https://doi.org/10.1080/01621459.1994.10476870 | ○ |
| Politis & White (2004) Automatic Block-Length Selection | 블록 길이 | https://doi.org/10.1081/ETC-120028836 | ● |
| Patton, Politis & White (2009) Correction to Automatic Block-Length Selection | 블록 길이 정정 | https://doi.org/10.1080/07474930802459016 | ○ |
| Saville, Connor, Ayers & Alvarez (2014) Bayesian predictive probabilities for interim monitoring | 무익성 조기 소진 | https://doi.org/10.1177/1740774514531352 | ● |
| Saville & Berry (2016) Efficiencies of platform clinical trials | arm 탈락 | https://doi.org/10.1177/1740774515626362 | ● |
| Lee & Wason (2020) Including non-concurrent control patients in platform trials | E6 동시 대조 | https://doi.org/10.1186/s12874-020-01043-6 | ● |
| Dwork, Feldman, Hardt, Pitassi, Reingold & Roth (2015) Generalization in Adaptive Data Analysis and Holdout Reuse | 적응 재사용 | https://arxiv.org/abs/1506.02629 | ● |
| Blum & Hardt (2015) The Ladder | 사다리 띠 | https://arxiv.org/abs/1502.04585 | ● |
| Bailey & López de Prado (2014) The Deflated Sharpe Ratio | N·DSR 인자 | https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2460551 | ○ |
| Bailey, Borwein, López de Prado & Zhu (2017) The Probability of Backtest Overfitting | CSCV-PBO | https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2326253 | ○ |
| Bailey, Borwein, López de Prado & Zhu (2014) Pseudo-Mathematics and Financial Charlatanism | MinBTL | https://www.ams.org/notices/201405/rnoti-p458.pdf | ○ |
| Hansen, Lunde & Nason (2011) The Model Confidence Set | C-트랙 교체 이력현상 | https://doi.org/10.3982/ECTA5771 | ○ |
| Gneiting & Raftery (2007) Strictly Proper Scoring Rules | I1 전방 채점 | https://doi.org/10.1198/016214506000001437 | ○ |
| Ramdas, Grünwald, Vovk & Shafer (2023) Game-theoretic statistics and safe anytime-valid inference | K4 e-과정 | https://arxiv.org/abs/2210.01948 | ○ |
| Howard, Ramdas, McAuliffe & Sekhon (2021) Time-uniform confidence sequences | K4 | https://arxiv.org/abs/1810.08240 | ○ |
| Andrews, Kitagawa & McCloskey (2019) Inference on Winners | 승자 구간 보고 | https://doi.org/10.3386/w25456 | ● |
| Manheim & Garrabrant (2018) Categorizing Variants of Goodhart's Law | 목표 축 상한 | https://arxiv.org/abs/1803.04585 | ● |
| Thall, Fox & Wathen (2015) Statistical controversies … adaptive randomization | 적응 배분 위험 | https://doi.org/10.1093/annonc/mdv238 | ● |
| Harvey & Liu (2020) False (and Missed) Discoveries in Financial Economics | 다중검정 | https://doi.org/10.1111/jofi.12951 | ● |
| McLean & Pontiff (2016) Does Academic Research Destroy Stock Return Predictability? | C-트랙 publication_asof 민감도 | https://doi.org/10.1111/jofi.12365 | ○ |
| 2026 스윕 카드 목록: AEAP 2609.00731 · Gençay 2608.27734 · Li SSRN 7190318 · Memorization Problem 2504.14765 | 프로세스 수준 PIT · 통계 보정 한계 · π_R · LLM 기억 | https://arxiv.org/abs/2609.00731 · https://arxiv.org/abs/2608.27734 · https://papers.ssrn.com/sol3/papers.cfm?abstract_id=7190318 · https://arxiv.org/abs/2504.14765 | ●(09-24 카드) |
| Cameron, Gelbach & Miller (2008) Bootstrap-Based Improvements for Inference with Clustered Errors, REStat 90(3) | 군집 수가 적을 때 wild cluster bootstrap | https://doi.org/10.1162/rest.90.3.414 | ○ |
| Davidson & MacKinnon (2000) Bootstrap Tests: How Many Bootstraps?, Econometric Reviews 19(1) | bootstrap_B · 무작위 정책 시드 · 플라시보 순열 수(α(B+1) 정수 규칙) | https://doi.org/10.1080/07474930008800459 | ○ |
| Campbell, Elbourne & Altman (2004) CONSORT statement: extension to cluster randomised trials, BMJ 328 | 설계효과 DE = 1 + (m̄−1)ρ — 군집 검정력 규칙 | https://doi.org/10.1136/bmj.328.7441.702 | ○ |

---

## 부록 C. 이 문서의 실측 (읽기 전용)

- 원장 L1: entry 64 · `current_axis = exec_v2_close_t1` · 전역 `max_attempts` 35 · port_t 유한 측정 칸 1,238 · 그중 close_t1 판 1,193(regime 문자열 전부 `close_t1_5562284e`)[재집계].
- close_t1 칸 중 C1 표식 531 · `treatment_misspecified` 25 제외 → 표식 청정 637.
  - 블록별: B1 188 · B2 126 · B3 101 · B4 83 · B5 113 · B6 25[재집계].
  - LLM B1 설계 파일이 있는 26 entry 에 501, 나머지에 136(B1 29 · B2 36 · B3 23 · B4 27 · B5 20)[재집계].
- 설계 재료 `.cache/rf_b1_design/*.materials.txt` 29건: 앞 칸 전기간 PORT_t·MDD·Calmar 서술 포함(예: 최신 파일 L102~112), 전기간 IC 수치 미포함[확인].
- `a_eligibility_gate.json::holds.vintage_flag` = active · flags `["*"]` · verdicts {consumed, consumed_absence, possible}[확인].
- 격자: 7블록 × n=5 · B4 칸 `combo.use`(B4_21 = [B1,B2,B3,B5]) · `select_winner_by` = B1 port_t · B2 port_t · B3 calmar · B6 calmar · B5 calmar · B7 calmar · B4 port_t · `fixed_axes` 키 = long_only · n_max · universe · start_date · commission_bps · liq_adv20_min · weight_cap · base_weight(+note)[확인].
- 결정 레지스터: **78 항목**(v1 작성 시 76 → 16:24 에 2건, 17:16 에 2건 추가) · open 0 · owner 전부 dohoon · D-A/D-E/D-F/D-G/D-I/REINFORCE-ORGANIC-AUTONOMY/RUNNER-RESTART-AFTER-P0-14/PR-L1-A4-DISPOSITION/D-E-B5-MATERIALS/D-E-V6-CONDITIONAL-IC resolved · `recorded_by`·`evidence` 필드는 CALMAR-FREQ-DAILY(09-24 17:31)부터 있다[확인].
- 코드 줄 번호: §0.5 표(전부 이번 세션 직접 판독).
- **최종판 추가 확인** (이번 개정 세션 · 읽기 전용)
  - B1 설계 재료 29건 중 28건에 "앞선 논문들에서 이미 배운 것" 교차 entry 절이 있다. 없는 1건은 `RP_20260904_112446_10544_combo_rulefast`. 예시 파일 L99~111 에 entry 4212 의 arm 전기간 수치가 있다[재집계·확인].
  - `attempts_used` > 고유 칸 코드 수인 entry: 이번 재집계 12/64(완결성 비평 10/64 — 칸 코드 필드 추출 차이). 전부 소진·파킹된 과거 entry 다[재집계].
  - `dr_open(`/`dr_resolve(` 호출처: 운영 트리 `02_Infrastructure` 에서는 `ops/boot_lean.sh` 1곳이다[확인].
  - B08 `.rff_asof` 기본값 = `fixed_axes.start_date` 워밍업 창 · B7 `selection_asof` 도 같다[확인].
  - `stagnation_window` = 새 arm 을 낸 라운드 수(`rf_b5_design_lib.R` H3)[확인].
  - `rf_pick_weight_arms` 의 제외 대조 키 = `label` · 카탈로그 id = `catalog_id`[확인].
  - pol_cfg 기본값: weekly_activation_max 1 · tombstone_window_weeks 8 · heldout_win_min 0.60 · null_percentile_min 0.95 · discovery_drop_max 0.10 · unreachable_max 0.20 · best_loss_max 0.05 · shadow 키 `shadow_min_weeks`[확인].
  - 09-18 리플레이 `wp2_report.md`: π₀ 재현 121/123 배치(98.4%) · 정체 시 정지 발견률 58% · 앞 두 블록만 42% · 공간/예산 비 1.00[확인].
  - config `promote_max_depth` 3 · `promote_max_depth_hard` 6 · `b5_design.guards` = {max_redesign_rounds 1, daily_arm_cap 6, stagnation_window 2, max_active_generated 40}[확인].
  - 선행 코드 부재: `rf_prereg.R` · `rf_trial_log.jsonl` · `selection_accounting.R` · `tilt_attribution.R` — 전부 없음. P0-08 도출기 = `/c/tmp/p0_08_apply/apply_p0_08_flags.R`[확인].

---

## 부록 D. 파라미터 전표 (분류: 도출 / 문헌 / 관례 / 판단 → A2-c) [헌M13·완M7·완M8]

- 분류 규칙
  - **도출**: 격자·pol_cfg·기존 config·결정 원문·코드에서 기계적으로 나온다.
  - **문헌**: 수치를 뒷받침하는 원문이 있다(부록 B).
  - **관례**: 통계 관례값이다(α 0.05 · 검정력 0.8).
  - **판단 → A2-c**: 근거가 Q 판단뿐이다. A2-c 결정 전에는 "판단 → O2 보정" 라벨을 달고 shadow 에서만 쓴다. 보정은 사전등록으로만 한다.
- 강화 레인의 근거 의무 해제(09-03)는 칸 축의 evidence 에 관한 것이다. 컨트롤러 파라미터까지 덮는지는 A2-c 로 묻는다.

| 키 | 값 | 분류 | 근거·도출식 |
|---|---|---|---|
| `budget.n_min_by_block.B2` | 1 | 판단 → A2-c | entry 당 비중 탐침 최소 1칸 |
| `budget.n_min_by_block.B3` | 1 | 도출(감사) | 레버 감사 ④: B3 는 유니버스 의존성의 유일한 진단원 |
| `budget.n_min_by_block.B6` | 2 | 도출(격자) | B6 `phase_control` 이 지목한 칸 쌍(B6_32·B6_33) |
| `budget.n_min_by_block.B7` | 사전등록값 | 도출 | PR-L2 사전등록 |
| `budget.delta_sigma` | 1.0 | 판단 → A2-c | D-F 는 "짝지은 SE 배수"만 정했고 배수 값은 없다 |
| `budget.futility.p_stop` | 리플레이 보정 | 도출 + 문헌 | discovery_drop ≤ pol_cfg 0.10 을 만족하는 최댓값 · Saville et al. 2014(설계 보정 권고) · 없으면 철회 |
| `budget.futility.min_blocks` | 2 | 판단 → A2-c | — |
| `budget.futility.n_min_entry` | blocks[B1].n + max(blocks[−B1].n) | 도출(격자) | — |
| ~~`budget.p_ref`~~ | 폐지 | — | D-F 비례식(n ∝ P̂)을 그대로 쓴다 |
| `evidence.min_cells_block` | ⌈DE · (z_{1−α} + z_{power})² / delta_sigma²⌉ | 도출 + 관례 | 단일 표본(짝 차이 u) 검정력 공식 · DE = 1 + (m̄−1)ρ(Campbell et al. 2004 · ρ 는 as-of 풀에서 추정) · α 0.05 · power 0.8(관례) |
| `evidence.min_lineages_block`(= `structure.r_min_block`) | 5 | 판단 → A2-c | 군집 수가 적을수록 wild cluster 가 필요하다는 방향만 문헌(Cameron & Miller 2015) |
| `model.min_clusters_cr` | 30 | 판단 → A2-c | Cameron & Miller 2015 의 '적은 군집' 논의 범위 안에서 판단 |
| `evidence.pairing_rule` | 미분류 불일치 0 | 도출 | 수치 문턱 대신 전수 분류(v1 의 0.99 폐기) |
| `noise.bootstrap_B` | 999 | 문헌 | Davidson & MacKinnon 2000(α(B+1) 정수) |
| `space.n_min_arm` | ⌈DE · 2(z_{1−α} + z_{power})² / MDE²⌉ | 도출 + 관례 | 두 표본 검정력 공식 · MDE = `min_detectable_effect_sigma` |
| `space.min_detectable_effect_sigma` | 1.0 | 판단 → A2-c | v1 "20칸이면 약 1σ 이상 큰 음의 arm 만 걸림"의 역산 |
| `space.r_min_arm` | 3 | 판단 → A2-c | — |
| `space.dormant_p` · `structure.block_dormant_p` | 0.05 | 관례(α) | — |
| `space.revive_p` | 0.15 | 판단 → A2-c | 히스테리시스 폭 · 방향은 Saville & Berry 2016 |
| `space.stable_share` | 0.8 | 판단 → A2-c | — |
| `space.dormant_weeks` | 8 | 도출 | pol_cfg `tombstone_window_weeks` 8 |
| `space.retire_weeks` | 16 | 도출 | 2 × dormant_weeks(부활 트리거 ④ 두 주기 — v1 의 26 은 오류) |
| `space.max_changes_per_week` · `structure.max_live_changes_per_week` | 1 | 도출 | pol_cfg `weekly_activation_max` |
| `space.quota_yield_window_rounds` | 2 라운드 | 도출 | `b5_design.guards.stagnation_window`(단위 = arm 을 낸 라운드) |
| `space.probe_cells` | 1 | 도출 | 측정 최소 단위 |
| `space.retire_probe_failures` | 2 | 판단 → A2-c | — |
| `structure.consecutive_windows` | 2(주) | 판단 → A2-c | — |
| `structure.n_diag.B3` | 1 | 도출(감사) | 레버 감사 ④ |
| `select.ladder_kappa` | = delta_sigma | 도출 | D-F 잡음 배수 하나로 통일 |
| `select.carry_p` | 0.8 | 플랜 | PR-L2 성공 기준 P(Δ>0) ≥ 0.8 |
| `select.promote_p_min` | 0.2 | 판단 → A2-c | — |
| `gate.power_min_ratio` | 0.15 | 플랜 | 플랜 착수 관문 |
| `gate.alpha` · `gate.power` | 0.05 · 0.8 | 관례 | — |
| pol_cfg 게이트 7종 | 0.60 · 0.95 · 0.10 · 0.20 · 0.05 · shadow_min_weeks · 유익 불일치 3 | 도출 | `policy_state.R` 기본값 · 도훈 09-21 ① |
| ~~`gate.min_cells_saved`~~ | "절약 > 0" | 도출 | 비열위 조건이 먼저 서므로 양이면 충분 |
| `gate.random_policy_seeds` · `gate.placebo_perms` | 999 · 999 | 문헌 | Davidson & MacKinnon 2000(null_pct 0.95 판정) |
| `gate.concurrent_control` | 1:1 · 블록 크기 2 | 관례 | 등분산 두 군에서 고정 총수 대비 검정력 최대 |
| `canary_entries` · `canary_weeks` | 1 · shadow_min_weeks | 도출 | 최소 단위 · pol_cfg |
| `kill.eprocess_alpha` · `kill.alpha` | 0.05 · 0.05 | 관례 | — |
| `kill.calib_band` | Binomial(n, 0.8) 95% 구간/n | 도출 | v1 의 [0.65, 0.92] 비대칭 리터럴 폐기 |
| `kill.stale_consecutive` | 3 | 판단 → A2-c | — |
| `kill.state_max_age` | stale_consecutive × tick 주기 | 도출 | 스케줄러의 tick 주기를 읽는다 |
| `kill.selftest_max_age` | stale_consecutive × 24h | 도출 | 자가검사는 하루 1회 |
| `kill.oscillation_pause` | 1주 | 도출 | pol_cfg 주간 회로차단기 창 |
| K5 기아 | 승격 세대당 신규 논문 ≥ 1 | 도출(D-G 원문) | 7일 비중 환산 폐기 |
| K8 러너 건강 | 동시 대조 대비 단측 비율 검정 α | 도출 | 고정 drop 문턱 없음 · 대조가 없으면 미무장 |
| `register.max_rows_per_week` | weekly_activation_max + K·롤백 사건 수 | 도출 | — |
| `tick.max_sec` | — | 판단 → A2-c | 운영값. O1 에서 tick 실측 분포로 보정한다 |
| `report.weekday` | 주간 Cleaner 스윕(토 09:00) 직후 첫 tick | 도출 | 기존 주간 주기에 맞춘다 |
| `report.max_chars` | 4096 | 도출 | 텔레그램 메시지 길이 한도 |
| `epoch.tau_lower` | oos_calendar_splits[1] − window_allowance_months | 도출 | `constraint_defaults.json::diagnostics` |
| `b5_budget.standing_plus` · `restore_on_g2_pass` | 2 · true | 도출(D-G 원문) | "상주+2칸, pass 시 복원" |
| `b5_budget.compose_only_consecutive_rounds` | — | **A2-e(도훈 확정)** | D-G 원문에 수치가 없다 |

- 판단 → A2-c 는 14개다: B2 n_min · delta_sigma · min_blocks · min_lineages_block · min_clusters_cr · MDE · r_min_arm · revive_p · stable_share · retire_probe_failures · consecutive_windows · promote_p_min · stale_consecutive · tick.max_sec.

---

## 부록 E. 반영하지 못했거나 부분 반영한 권고와 그 사유

| 출처 | 권고 | 처리 | 사유 |
|---|---|---|---|
| 헌M10 | 롤백 수단 선택지 (b) "유기체 절단이 entry 의 마지막 빈 칸을 닫는 원인이 되지 못하게 한다" | **미채택** · (a) `rf_reopen_entry` 채택 | (b) 를 쓰면 예산 회수 경로(격자 소진) 자체가 막혀 예산 층의 목적이 사라진다 |
| 헌M8 | `safety_guard.sh` 확장으로 레지스터·config 직접 편집 차단 | **선택 사항으로 둠** | 동시 수리 중인 파일이다. 봉쇄의 본체는 결정 id 참조 규칙과 무인 문맥 stop 이다. owner 문자열 규약의 한계(악의적 세션 미차단)는 남는다고 명시했다 |
| 헌M9 | 대안 중 "레지스터 공용 claim 잠금만" 단독 | **두 층으로 결합** | 잠금만으로는 기계 기록의 빈도가 레지스터의 도훈 대기 결정 용도를 흐린다. jsonl 상세 + 포인터 행 + 잠금을 함께 쓴다 |
| 헌R11 | 잡음 척도 σ 원천 불일치 해소 | **부분** | 어느 σ 가 옳은지는 이 세션이 판정하지 않는다(AX-008). O0b 가 as-of 풀에서 R 계약으로 산출하고, 계산 예시는 예시로만 표기했다 |
| 완R1 | 운영 트리 밖 `apply_p0_08_flags.R` 를 운영 트리로 이관 | **요구사항으로만 넘김** | P0-14 는 동시 진행 워크플로 소관이다. 이 설계는 양성 대조(586칸 비트 재현)와 도출 규칙(출처 기반)을 요구사항으로 넘긴다 |
| 완R3 | judge.md 6축에 '유기체 결정 재현' 추가 | **권고만** | `.claude/agents/judge.md` 는 도훈 승인 문서다. 읽기 전용 설계에서는 개정안만 적었다(§4-8) |
| 완R4 | 부팅 `Rules:` 줄을 `Organic:` 줄로 교체 | **제안만** | 부팅 스크립트는 하네스다. O1 문서 개정 목록에 제안으로 두고, 배포는 별도 승인이다 |
| 완R4 | headless `QVEST_SKIP_AUTO_COMMIT` 에서 organic 산출의 git 보존 | **O1 확인 항목** | 현 auto-commit 동작을 이 세션에서 실측하지 않았다. append-only + 주간 스냅샷으로 복원 가능성만 보장했다 |
| 완M13 | 현실 규모 2~3배 | **반영하되 판단값** | 재추정 근거가 비교 기준 두 개(`remeasure_from_holdings.R` 942줄 · P0 워크플로 반복)뿐이다. 세션 상한과 멈춤 조건으로 불확실성을 통제한다 |
| 완M2 | 기존 리플레이 엔진 재사용 | **반영 · 조건부** | 엔진이 `04_Research/meta`(리서치 디렉터리) 코드라 운영 의존이 생긴다. 어댑터는 source 만 하고, 엔진이 바뀌면 양성 대조를 재실행하는 것을 조건으로 둔다. 엔진을 운영 트리로 옮길지는 O2 에서 판단한다 |
| 완M12 | B3 축소를 사람 규칙 안건으로 | **A5 로 상정 · 사실 재확인 조건** | "P0-12 k200 한정 × 09-05 리셋 → 하류 소비자 없음"은 레버 감사[감사] 인용이다. O0a 에서 코드로 다시 확인한 뒤 상정한다. 성과 수치(양수 0/24)는 근거에서 뺐다 |
| 완R12 | B1 '7개 이상 팩터 적층' 퇴출 | **범위 밖 · 사람 안건 후보로만** | B1 절단 금지(09-04) · 팩터 수준 = P0-08. 레버 감사 근거가 전기간 판정이라 그 자체가 D-E 소재가 될 수 있다. as-of 재산출 전에는 상정하지 않는다 |
| 완R7 | as-of S 순위 대 전기간 A-거리 순위 관계 보고 | **반영 · 제한** | 사람용 1회 보고로만 쓰고 N_meta 로 센다. 이 관계를 기계 입력으로 쓰면 τ_D 이후 정보가 샌다 |
| 헌M1 | π_DG 를 유기체 밖으로 분리하거나 shadow 로 | **둘 다 채택** | live 는 유기체 밖 이행 항목(Q②′ 결정 뒤)으로, 유기체 안에서는 `dg_shadow` 대조 기록만 한다 |
