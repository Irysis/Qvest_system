# 충실도 감사 지적 유형 전수 분류 — 기계 사전검사(pre-audit) 설계 근거

작성 2026-10-05 · 대상 = 무인 충실구현 레인(`rf_replication_auto.sh`)의 적대적 충실도 감사 산출 전부 · 산출 = `findings.csv`(지적 1건 = 1행) + 이 문서
읽기 전용 작업이다 — 원장·설정·레인 스크립트·요청 파일·`RP_AUTO_CLEAN_2508_18592/` 는 읽기만 했다. R 은 실행하지 않았고 집계는 파이썬이다.

---

## 0. 결론

1. **원 지적 197항목 → 중복 제거 134건**(+확인 문장 3건 별도) · 감사 패스 39개(감사 실행 42회) · 논문 키 21개 중 19개에서 지적.
2. **최다 유형은 '방어·위생 코드 미신고'(GUARD 26건)** 이고, 침묵 스킵(SKIP 7건)을 합친 '구현자 추가물 미신고' 계열이 33건(25%)이다. 그다음은 신호·추정 식 치환(FORMULA 19) · 하네스·러너 층 효과(HARNESS 12) · 포트폴리오 구성(PORT 11) · 데이터 정의(DATA 11) · 논문 서술 오류(DECL_PAPER 11) 순이다.
3. **선언 문구 자체의 사실 오류가 넓게 퍼져 있다** — 1차 유형으로 25건, 2차 유형까지 넣으면 134건 중 59건이 FIDELITY 문장(논문 서술·자기 코드 서술·근거 진술)이 틀렸다는 지적을 포함한다.
4. **비용 '편도/왕복' 해석 지적은 0건**이다. 비용 축 지적 9건은 전부 러너·하네스 규약(8)과 논문 서술 과장(1)으로 귀속된다.
5. **기계 검출**: misdeclared 축에서 나온 지적 106건 = H 35 · M 40 · L 31. misdeclared 패스 28개 중 **12개는 misdeclared 축 지적이 전부 H/M**(5개는 전부 H)이었다 — 결정론 사전검사로 감사 전에 막을 수 있었던 상한이다. 나머지 16개는 논문 판독이 필요한 L 지적(식 치환·논문 구성·논문 서술)을 하나 이상 품는다.
6. **2패스 구조는 사실이고, 2차 패스가 잘 수렴하지 않는다**: 레인 1차 감사 19건 중 15건 misdeclared → 재구현 → 2차 감사 15건 중 10건이 또 misdeclared(→ `implementation_suspect` 꼬리표로 소비). 2차 misdeclared 10건 중 3건(0806.2606 · 1403.8125 · 2006.04639)은 **하네스 층 효과 또는 프롬프트 지시만으로** 기각됐다 — 재구현자가 논문을 더 잘 읽어서는 피할 수 없던 기각이다.
7. **프롬프트가 직접 유발하는 지시가 있다**: `유동성 하한 adv20 ≥ 2e8` 줄(SOT `paper_faithful` 과 충돌 — 감사된 엔진 39개 중 24개가 2e8 하한을 코드에 보유, 감사 판정은 엇갈림), `faithful 이면 changed 는 유니버스만` + `기간 2005-01-01~` 조합, `Z_Score_Aligned 만 소비` 강제(변환 사슬 공시 없음), 이식 경로의 `25종·월간·EW`. §6.

---

## 1. 데이터와 방법

### 1.1 입력과 과거 패스 복원
- 작업 트리의 `fidelity_audit.json`·`fidelity_axis_*.json` 은 **최신 패스만** 남는다. 과거 패스는 **git 이력(자동 커밋 54개)에서 blob 단위로 복원**했다(`git log --all` → `git rev-parse <commit>:<path>` → 중복 blob 제거, 513개 판). 청정 레인 1차 감사는 `.clean_audit_src/r1/` 에서 읽었다.
- `combo:1403.8125+2301.09173+2404.08129` 1차 병합본은 git 에 없어서 **같은 시각의 축 파일 6개(git)로 재구성**했다(항목 수 4/3 이 저널 `fidelity_audit_verdict` 기록과 일치).
- `06_Registry/replication_request.json` 의 `audit_feedback`(이력 포함)은 병합본과 같은 문장의 사본이라 대조용으로만 썼다. 현재 요청의 2508.18592 1차 지적 14항목 = `.clean_audit_src/r1` 과 동일.
- 패스 순서·판정·재구현 여부는 저널 `.cache/reinforce_auto_log.jsonl` 의 `fidelity_audit_verdict`·`fidelity_reimplement_requested`·`start` 이벤트로 맞췄다.
- 감사 대상이 된 엔진·FIDELITY 판은 패스별로 git blob 을 특정했다(부록 A). 1차 엔진 = `engine.rejected1.R`.

### 1.2 패스 정의 · 중복 제거 · 제외
- **패스 = 구현 1판**(엔진 1개). 같은 구현을 여러 번 감사한 경우는 한 패스로 묶었다: 2002.06975 1차(동시 실행 사고로 같은 엔진을 3회 감사 — §4.5), 2302.10175 1차(단일 감사 + 사후 팬아웃 감사). 1403.8125 1차는 채움 필터 수리 뒤 재병합본(8/2)을 정본으로 썼다(첫 병합 1/1 은 같은 축 파일의 과잉 필터 결과).
- **중복 제거**: 같은 패스 안에서 여러 축(또는 같은 패스의 여러 감사 실행)이 같은 사실을 지적하면 1건으로 묶고 축 목록·원 항목 ID 를 남겼다(`axes`·`member_item_ids`). 194개 실질 항목이 134건으로 줄었다 — 40건이 2개 이상 항목의 병합이고 그중 16건은 2개 이상 축의 병합이다.
- **확인 문장 3건**(지적 배열에 실린 '일치함/불일치 없음' 서술 — F033·F055·F100)은 `NONFINDING` 으로 표시하고 집계에서 뺐다. 25자 게이트를 넘는 긴 확인 문장이라 병합기 채움 필터를 통과했다.
- **제외**: 09-05 `unverifiable` 3건(감사 미실행을 판정으로 읽던 구멍 — 지적 0), 09-04 오전 감사 레인 시험(프로브 `RP_PROBE_1505_flip`·픽스처), **2508.18592 2차 감사(진행 중)**.

### 1.3 분류 원칙과 한계
- 각 지적에 1차 유형 1개 + 2차 유형(선택) + 꼬리표(`prompt`·`prompt_related`·`harness_fixed`·`pit`·`contested`)를 붙였다. 1차 유형 = **감사자가 기각 사유로 세운 핵심 사실**. 같은 지적이 '코드 차이'이면서 'FIDELITY 문장 오류'이면 코드 차이를 1차로, 문장 오류를 2차로 두었다(그래서 DECL_SELF 는 1차 7건 · 2차 24건).
- 분류는 감사 문장을 읽은 1인 판정이다. 지적의 타당성을 원문 대조로 재판정하지는 않았다 — 지적은 감사자의 주장이고, 감사 판정 자체가 흔들린다(§4.5).
- 지적 수는 감사자의 서술 입도에 좌우된다(2404.08129 사후 감사 22항목 → 15건).

---

## 2. 패스 현황 — 2패스 구조

| 구분 | 건 | misdeclared | adapted/faithful |
|---|---:|---:|---:|
| 레인 1차 감사(요청 단위) | 19 | 15 | 4 |
| 사후 감사(1차 · 2006.04639 · 2404.08129 · 2302.10175) | 3 | 3 | 0 |
| 2차 감사(재구현 후 · 논문당 최종) | 15 | 10 | 5 |

- 1차 misdeclared 17건(레인 15 + 재구현을 부른 사후 2) 중 15건이 2차 감사까지 갔다. 미완 2건: 2508.18592(2차 진행 중) · combo(2007.08115+2301.09173) 요청 B(재구현 4회 모두 측정 오류 → skiplist).
- 1707.05552 는 2차 구현이 둘이다(p2a = 검증기가 rc 127 로 죽어 판정이 소비되지 않은 adapted 판 · p2b = 같은 피드백으로 다시 돈 misdeclared 판). 표는 p2b 를 최종으로 셌다.
- 지적이 1건 이상인 패스 33개 중 28개가 misdeclared 다(기저율 85%). 아래 표의 '패스 misdeclared 비율'은 이 기저율과 비교해 읽어야 한다.

---

## 3. 유형 분류 (B)

| 계열 | 유형 | 정의 · 판별 기준 |
|---|---|---|
| A 구현자 추가물 미신고 | **GUARD** 방어·위생 코드 | 논문에 없는데 구현자가 넣은 값 절단(clip·winsorize)·커버리지/최소 N/최소 관측 문턱·결측 대치(0·중앙값·LOCF)·수치 가드(분모·바닥·절댓값 상한)·행 필터(가격>0·중복·부분월·결산월)·최적화 상수·결측 규약 — 신고 누락 |
| | **SKIP** 침묵 스킵·미발행 | `next`·`return(NULL)`·행 필터로 그 달 FACTORS/PORTFOLIO 를 내지 않음 → 하네스가 **직전 책을 이월 보유**. 무계수 스킵·침묵 폴백 포함 |
| B 논문 대비 구현 차이 | **WINDOW** 롤링 창 | 창 종점(t vs t−1)·길이·첫 창·거래일 vs 잔존 행 수 |
| | **PERIOD** 표본기간·워밍업 | 2005-01~ vs 논문 기간 · 워밍업 상수 재사용 · walk-forward → 단일 경로 |
| | **FDB** 팩터 DB 매핑 | 등록부 팩터 정의 ≠ 논문 정의(skip-month · half-life · DUPC 중복 · `Z_Score_Aligned` 의 1/99 clip) |
| | **PREPROC** 논문 전처리 누락 | 논문이 명시한 중성화(업종·시총 잔차화)·업종중위수 결측대체 단계가 없음 |
| | **FORMULA** 식·절차 치환 | 신호·회계 식·부호·초기값·최적화기·피처 구성·추정 단위가 논문 식과 다름 |
| | **DATA** 데이터 정의·대리변수 | 수정주가 레벨/이음매 · 배당 미포함 · 수익 구간(일중 vs 종가-종가) · 초과수익 · 산업분류(FF49 → Sector_Lv2) · 조정주식수 |
| | **TIMING** 시점·지연 규약 | 회계 가용일 비균일(휴장·3월 lag) · 산출 빈도(월말 vs 일별) |
| | **PORT** 포트폴리오 구성 | 분위·롱숏·종목수·비중·breadth·노출 스칼라(s*)·kill-switch · 실현 보유가 논문/선언과 다름 |
| | **UNIV** 유니버스·유동성 | LIQ 2e8 '지시 축' 표기 · KQ150 멤버십 시작(2010) 미공시 · 학습 유니버스 한정 |
| | **POOL** 분할 단위 통합 | 논문의 독립 단위(거래소별 정렬 · 종목별 모델)를 단일 풀로 합침 |
| | **COST** 비용 해석 | 편도/왕복 등 엔진측 비용 가정 — **0건** |
| C 선언 문구 오류 | **DECL_PAPER** 논문 서술 오류 | 'NOT STATED/논문 미명시' 오기 · paper_original_form 오류 · 인용 절단 · '원문 판독 불가' 오선언 |
| | **DECL_SELF** 자기 코드·산출 서술 오류 | 선언 수치·날짜·범위·빈도 ≠ 산출물 · 선언한 폴백·성질 ≠ 코드 |
| | **DECL_WHY** 근거·영향 진술 오류 | 신고된 변경에 붙은 '무영향·흡수·불변·결정됨' 근거가 거짓 |
| D 인프라 층 | **HARNESS** 하네스·러너 규약 효과 | 유니버스 재적용(inner join)·재정규화 유무·월간 재EW·체결가 규약·비용모형·paper_basis 라벨 — 엔진이 아니라 측정 층이 만든 효과의 미공시·오서술 |

---

## 4. 유형별 표 (C)

### 4.1 메인 표

'패스 misdeclared' = 그 유형 지적이 1건 이상 있었던 패스 중 판정 misdeclared 비율(기저율 28/33 = 85%). 'mis 축' = 그 지적을 낸 축의 판정이 misdeclared 인 건수(= 기각에 직접 기여한 지적).

| 유형 | 건수 | mis 축 | 논문 | 패스 | 패스 misdeclared | 기계 검출 | 대표 예 |
|---|---:|---:|---:|---:|---|---|---|
| GUARD | 26 | 22 | 9 | 11 | 10/11 (91%) | M24 · L2 | F007 1403.8125 p1 형성창 일별 로그수익 ±log(3) 절단(`.DCAP`) · F058 2302.10175 연율변동성<1% 종목 포지션 0 강제(`.SD_FLOOR`) |
| FORMULA | 19 | 11 | 10 | 11 | 10/11 (91%) | L19 | F028 2002.06975 No.27 accruals 부호 반전 · F061 2404.08129 초기값 SVD → 순위 기반 |
| HARNESS | 12 | 10 | 7 | 8 | 6/8 (75%) | H12 | F012 1403.8125 p2 보유 중 유니버스 재적용(러너 `.apply_universe`)으로 바스켓 중도 탈락 · F084 2511.12129 체결가 = 시그널일 종가(`close_d_legacy`), 선언은 '논문 거래일과 일치' |
| PORT | 11 | 10 | 6 | 8 | 8/8 | H4 · L7 | F064 2404.08129 §5.7 5분위 롱숏 → top-25 롱온리 · F094 2511.12490 노출 스칼라 s* 미적용 |
| DATA | 11 | 7 | 7 | 10 | 7/10 (70%) | H5 · M4 · L2 | F021 1707.05552 p2b 순위변수가 이음매 미보정 Close · F079 2511.12129 EPS 분모 = Size/Close(사후 조정 주식수) |
| DECL_PAPER | 11 (+2차 10) | 9 | 9 | 9 | 9/9 | H2 · M2 · L7 | F026 2002.06975 'No.19~33 식 없음' 선언 — 논문은 15개 식 인쇄 · F065 2404.08129 paper_original_form '포트폴리오·롱숏·SR 없음' 허위 |
| SKIP | 7 | 7 | 6 | 7 | 7/7 | H7 | F102 2511.12490 p2 활성 부족 월 미발행 → 59/260 월말 직전 책 이월 · F105 combo(2007+2301) `next` 10지점 → 252개월 중 156개월만 리밸, 선언은 'monthly' |
| DECL_SELF | 7 (+2차 24) | 7 | 4 | 5 | 5/5 | H4 · M3 | F114 combo3 p1 '전원 결측이면 EW' 폴백 선언 — 코드엔 없음 · F082 2511.12129 실현 보유 15~43종 vs '25종 초과 구조적' 선언 |
| DECL_WHY | 7 (+2차 3) | 3 | 4 | 6 | 5/6 (83%) | L7 | F075 2404.08129 rf 생략 근거 '절편·φ 흡수·순위 무영향' 불성립 · F104 2511.12490 p2 백분위 규약 '결과 영향 없음' 산술 불성립 |
| WINDOW | 5 | 3 | 5 | 5 | 3/5 (60%) | M5 | F131 2508.18592 EWM min-max·엔트로피 창 종점이 t(논문 t−1) · F093 2511.12490 trailing 창이 거래일이 아니라 잔존 행 수 |
| FDB | 4 | 4 | 2 | 2 | 2/2 | H2 · M2 | F032 2003.02515 특성 = `Z_Score_Aligned`(1/99 clip) — 논문은 원값 순위 · F135 2508.18592 M11/M29 bit-identical(DUPC-033) 이중 계상 |
| UNIV | 4 | 4 | 4 | 4 | 4/4 | H3 · L1 | F016 1707.05552 LIQ 2e8 을 '지시 축'으로 표기 · F081 2511.12129 KQ150 멤버십 2010 시작 미공시 |
| PERIOD | 3 (+2차 2) | 3 | 3 | 3 | 3/3 | H1 · M2 | F010 1403.8125 표본 2005-01~ (논문 2003–2012) 미신고 · F098 2511.12490 3창 walk-forward → 전기간 단일 경로 |
| TIMING | 3 | 2 | 3 | 3 | 3/3 | L3 | F050 2202.05702 3/31 휴장 해 Q1 회계 2분기 스킵 · F027 2002.06975 월말 1회 산출 규정 → 일별 재계산 |
| PREPROC | 2 | 2 | 1 | 1 | 1/1 | M2 | F132 2508.18592 업종·시총 잔차화 누락 · F136 같은 패스 업종중위수 결측대체 누락 → complete.cases 탈락 |
| POOL | 2 | 2 | 2 | 2 | 2/2 | M2 | F127 1505.00328 청정 1차 거래소별 독립 정렬을 단일 횡단면으로(6항목 병합) · F049 2202.05702 종목별 local 모델 → pooled |
| COST | 0 | – | – | – | – | – | 비용 축 지적 9건은 HARNESS 8 · DECL_PAPER 1 로 귀속 |

계열 합계: A(GUARD+SKIP) 33건(mis 축 29) · B(창~분할) 64건(48) · C(선언 문구) 25건(19, 2차 포함 59건 관여) · D(HARNESS) 12건(10).

### 4.2 GUARD 하위 유형 (26건)

| 하위 | 건 | 예 |
|---|---:|---|
| 커버리지·최소 N·최소 관측 문턱 | 7 | `.COV=0.80`(F008) · `.NMIN=30`(F009) · 완전성 95%(F056) · `.LEAF_MO_L=6`(F107) · 월당 관측 ≥1(F110) |
| 행 필터·중복·부분월(데이터 위생) | 5 | `Close>0`(F070) · `(Ticker,Date)` 중복 제거(F071) · 부분월(F073) · 결산월 행 삭제(F086) · 월말 내부결합 탈락(F124) |
| 결측 대치(0·중앙값·LOCF) | 4 | InterestExp NA→0(F022) · `lm.fit` 비유한 계수→0(F067) · SVD 입력 결측 0(F109) · β 중앙값 대치+`ties='first'`(F113) |
| 값 절단(clip·winsorize) | 3 | ±log(3)(F007) · 표적 ±5SD(F004, 신고됨) · winsorize 범위(F053) |
| 수치 가드(분모·바닥·절댓값 상한) | 3 | `.SD_FLOOR` 영점화(F058) · 절댓값>1e6→0·seed·LOCF 묶음(F059) · 분모 0 가드(F068) |
| 최적화 상수·구간 | 2 | `optimize` 구간 하한 step/10(F074) · HFL 정지 상수 7종(F121) |
| 결측 규약·정규화 선택 | 2 | 코호트 결측 시 nc 재스케일(F011) · 예측 평균 t 집합(F076) |

### 4.3 기각에 기여한 축

misdeclared 축에서 나온 지적의 축 분포(병합 건은 축마다 셈): undeclared 55 · signal 27 · portfolio 20 · universe 9 · cost 6 · 단일 감사 4 · timing 2. 코드에서 출발하는 undeclared 축이 기각의 최대 공급원이다 — 기계 스캔이 대신할 수 있는 바로 그 방향이다.

### 4.4 2차 패스는 무엇으로 기각됐나 (misdeclared 10건)

| 원인 | 패스 · 지적 |
|---|---|
| 하네스 층 효과만 | 1403.8125 p2 (F012~F015 — 유니버스 재적용·월간 재EW·paper_basis 15bps·L-code 비교) · 0806.2606 p2 (F006 — 1차 감사가 '재정규화 경로 없음'을 지적하자 2차 선언이 '재정규화 없음'을 단언, 2차 감사는 무데이터 종목 재정규화를 지적) |
| 프롬프트 LIQ 줄만 | 2006.04639 p2 (F039 — 유일한 지적) |
| 1차 지적과 반대 독법 | 2011.05381 p2 (F044·F045 — 1차는 'N=100 이 보유 종목수'로 기각, 재구현이 100종 고정하자 2차는 '논문 자산수는 시변'으로 기각) |
| 1차 수정 불완전 | 2511.12490 p2 (F103 — kill-switch 트리거 4종 중 2종만) |
| 1차에 없던 새 사실 | 1707.05552 p2b(F021) · 2003.02515 p2(F034) · 2202.05702 p2(F050·F051) · combo4 p2(F112) · combo3 p2(F118~F126) · 2511.12490 p2(F102) |

- 재구현이 FIDELITY 를 키운다: 1차→2차 FIDELITY 문자 수 중앙 **×1.53**(14쌍). 2차 misdeclared 축 지적 24건 중 14건(58%)이 선언 문구 오류를 포함한다(1차 82건 중 35건, 43%). 선언이 길어지면 틀릴 문장도 늘어난다.

### 4.5 감사 판정의 흔들림 (같은 입력 · 다른 판정)

- **2002.06975 1차**: 같은 엔진(`f50628ef`, 856행)·같은 FIDELITY(`19d63e0f`)를 09-13 동시 실행 사고로 팬아웃 감사 3회가 돌았다 — 2회 misdeclared(**같은 7항목**), 1회 adapted(0항목; 같은 No.26 ROIC 차이를 '선언됨'으로 판정). 재현되는 지적(7항목)과 재현되지 않는 판정이 공존한다.
- **2302.10175**: 같은 엔진에 단일 감사(adapted — MACD 응답함수 φ 생략을 '원문 F.2 대로 올바름'으로 명시)와 팬아웃 감사(misdeclared — 같은 φ 생략을 지적, F060 `contested`).
- **LIQ 2e8**: 감사된 엔진 39개 중 24개가 2e8 하한을 코드에 둔다. 지적한 감사는 2건(1707.05552 p1 · 2006.04639 p2, 둘 다 '지시 축' 표기 문제)이고, 2404.08129 1차 universe 축은 같은 필터를 '허용된 유니버스 교체 범위(실투형 고정 축)'로 받아들였다. SOT 가 둘이라 감사도 둘로 갈린다.

---

## 5. 기계 검출 가능성 (D)

### 5.1 유형별 등급과 규칙

등급: **H** = 정규식·AST·산출물 대조로 확정 · **M** = 후보를 뽑아 FIDELITY 신고와 대조(오탐 있음) · **L** = 논문 판독 필요. 건별 등급은 `findings.csv` 의 `machine_check`·`check_rule`.

| 유형 | 등급 | 규칙 | 검출 방식(요지) |
|---|---|---|---|
| GUARD | **M** (구조화 신고 도입 시 H) | R1 | 엔진 스캔 → 방어 코드 후보 목록 → 상수 이름·값이 FIDELITY 에 없으면 미신고 후보 |
| SKIP | **H** | R2 | 산출 시그널 날짜 vs 월 격자 공백 → 신고된 스킵 정책 없으면 실패 |
| WINDOW | **M** | R3 + R1 | `shift(x, 0:(n-1))` 류 당월 포함 창 · 행 필터 뒤 `shift/froll` → 후보 |
| PERIOD | H(고정 축 기간) · M(워밍업·평가 프로토콜) | R6 · R1 · R9 | 기간 축 정적 공시 · 상수 재사용 · 원문 'walk-forward' |
| FDB | H(DUPC·`Z_Score_Aligned` 사슬) · M(정의 차이) | R4 | 등록부 `dedup.cluster` 충돌 · 소비 시 변환 사슬 자동 공시 · `definition` 의 skip/half-life 토큰 |
| PREPROC | **M** | R9 | 원문 키워드(neutraliz·industry dumm·residual·imput·median·MAD) ↔ FIDELITY |
| FORMULA | **L** | – | 식 대조는 원문 판독 필요 |
| DATA | H(산업분류·배당 공시) · M(수정주가 레벨·Close 비율·초과수익) · L(수익 구간) | R8 | 엔진 토큰(`Sector_Lv2`·`1/Close`·`Size/Close`·`Close/shift(Close)`) |
| TIMING | **L** | – | 회계 가용일 × 휴장 상호작용 · 산출 빈도 |
| PORT | H(선언 vs 실현 보유·비중·노출) · L(논문 구성) | R7 | 산출물(`04_holdings.csv`·`10_audit.csv`) 대조 |
| UNIV | H(LIQ 표기 · KQ150 2010) · L(학습 유니버스) | R6 | 충실구현 엔진의 `2e8`/`adv20` · 측정 시작 < 2010-02 |
| POOL | **M** | R9 | 원문 'independently·separately·each stock·local' ↔ FIDELITY |
| HARNESS | **H** | R5 | 러너 설정에서 공시 블록 자동 생성(구현자 서술 금지) |
| DECL_PAPER | H('판독 불가') · M(NOT STATED·인용 절단) · L(원형 서술) | R10 · R11 | URL 실측 · 인용 축자 대조 · 주제어 원문 검색 |
| DECL_SELF | H(수치·날짜) · M(폴백·성질) | R7 | 구조화 `engine_contract` vs 산출물 · 선언 폴백 분기 grep |
| DECL_WHY | **L** | – | '무영향·흡수' 주장 목록화는 가능하나 검증은 판독 |

### 5.2 규칙 카탈로그 (각 1~2줄)

- **R1 방어 코드 재고(GUARD·창 길이·워밍업)** — engine.R 에서 ①최상위 상수 `^\s*\.?[A-Z][A-Z0-9_]*\s*<-\s*(숫자|log\(|exp\()` ②절단 `pmin\(|pmax\(|winsor|clip|quantile\([^)]*(0\.01|0\.99)` ③대치 `\[!is\.finite\(.*\)\]\s*<-` · `\[!\w+\]\s*<-` · `fifelse\(is\.finite\(` · `nafill|na\.locf|fcoalesce` · `<-\s*median\(` ④개수 문턱 `(sum|length|nrow|uniqueN|rowSums)\(…\)\s*[<>]=?\s*\d` · `\[\w*N\w*\s*>=\s*\d+L?\]` ⑤`(Close|Size)\s*>\s*0` · `duplicated` · `max\(Date\).*by=` ⑥`set\.seed` · `optimi[sz]e\(|interval\s*=|maxit|tol` 를 뽑는다. 각 후보의 상수 이름·리터럴이 FIDELITY 에 없으면 미신고 후보. ★자유 서술 FIDELITY 에선 오탐이 많다(§5.3) → FIDELITY 에 `declared_constants[{name,value,line,source: paper|guard|convention}]` 표를 의무화하고 **R1 후보 ⊆ 표** 를 관문으로 걸면 H.
- **R2 미발행 월(SKIP)** — 측정 산출물에서 시그널 월 집합(`04_holdings.csv` 리밸일 또는 FACTORS 날짜)을 첫~끝 월 격자와 대조, 공백이 있으면 FIDELITY 의 구조화 `skip_policy`(carry/flat + 사유) 없이는 실패. 코드 보조: 루프 안 `next`/`return(NULL)` 마다 계수기(`n_skip`) 짝이 없으면 후보.
- **R3 창 종점(WINDOW)** — `shift\([^)]*\b0\s*:` (lag 0 포함 창), `froll(sum|mean)\(` 뒤 `shift(…,1)` 없음, `[is.finite(Close) & Close > 0]` 행 필터 뒤 `shift(Close, k)` → '당월 포함·행 수 창' 후보. 신고와 대조.
- **R4 팩터 DB 등록부(FDB)** — 엔진이 참조한 팩터명(`\b[A-Z]{1,3}\d{2}_\w+`)을 `02_Infrastructure/factor_db/factor_registry.json` 에 조회: ①둘 이상이 같은 `dedup.cluster`(예 DUPC-033: M11_ST_Reversal ↔ M29_Mom_5d) 이거나 `deprecated_for_selection` alias 면 **실패(H)** ②`Z_Score_Aligned` 를 소비하면 변환 사슬(유니버스 1/99 clip → z → ±3 clip → `ic_sign` → sd=1 · 업종/시총 중성화 없음 · `Raw_Value/Rank_Pct/Z_Sector` 미적재 — `factor_db_builder.R`·`factor_db_connector.R:304,650`)을 **자동 공시(H)** ③각 팩터 `definition` 을 표로 붙이고 'skip'·'EWMA/half-life'·창 일수 토큰이 FIDELITY 매핑 서술에 없으면 후보(M). 등록부 `definition` 에 'skip' 이 든 팩터 5개, half-life/EWMA 3개, `dedup` 블록 133개(alias `deprecated_for_selection` 11개).
- **R5 하네스 공시(HARNESS)** — 러너 설정·`portfolio_spec` 으로 고정 문단을 생성해 감사 전 FIDELITY 에 붙인다: 시그널일 멤버십 재적용(inner join, 탈락분 미재분배) · PORTFOLIO = 리밸마다 목표비중 재매매(보유 중 드리프트 없음) · 월간 집행 · 체결 규약(`close_d_legacy`/`close_t1`/`open_t1` 해석값) · 비용 = Σ|Δw_target|×수수료(`weight_delta_approx`) · paper_basis = `commission_paper` 또는 0. 구현자의 하네스 서술은 금지(F002·F006·F084 가 그 서술의 오류).
  - ★**정정(Q-Lead 코드 검증 2026-10-05)**: '보유 중 드리프트 없음' 은 **틀렸다** — `replication_harness.R` 은 보유창 안을 `Return.portfolio(…, rebalance_on = NA)`(buy-and-hold)로 굴려 비중이 드리프트하고, 다음 신호일 집행 때 목표비중으로 되돌린다. '월간 집행' 도 하네스 규약이 아니라 **엔진이 신호를 낸 날마다** 리밸이다(신호 없는 달 = 직전 보유 이월). '탈락분 미재분배' 는 맞다(다리 총노출 GL = 결합 뒤 Σ|w|). 배선된 공시 블록(검증 문장만) = `06_Registry/rf_preaudit.json::harness` · 생성기 `rf_preaudit.py --harness-block` — 체결 규약은 `constraint_defaults.json::execution.exec_price` 에서 그때 읽는다.
- **R6 고정 축 정적 공시(PERIOD·UNIV)** — 항상 붙인다: 기간 2005-01-01~ vs 논문 표본 · KQ150 플래그는 2010-01-29 부터(이전 K200 단독). 충실구현 엔진에 `2e8|adv20` 이 있으면 논문에 유동성 필터가 없는 한 **실패**('지시 축' 표기 금지).
- **R7 선언 vs 산출물(DECL_SELF·PORT)** — FIDELITY 에 구조화 `engine_contract{n_holdings_range, first_exec_month, rebalance, long_gross, short_gross, net, max_weight, weighting}` 를 의무화하고 `04_holdings.csv`·`10_audit.csv`(holdings_cap 행)·`00_manifest.json`(start_date) 과 대조 — 불일치면 실패 또는 실측값으로 덮어쓰기. 성질 서술(예 '전원 결측이면 EW')은 해당 분기 존재를 grep(M).
- **R8 데이터 정의(DATA)** — `Sector_Lv2|Sector_Lv1` 사용 → 'WI26 중분류' 자동 공시(H) · `Close` 비율 수익 → '현금배당 미포함·수출본 이음매' 자동 공시(H) · `1\s*/\s*Close` · `Size\s*/\s*Close` · 가격 레벨 순위 → '소급 재작성 수정주가 레벨'(M, 시점오염 위험) · `Close/shift(Close)` 로 수익을 다시 만들면 이음매 가드(`Ret`) 우회 후보(M).
- **R9 원문 키워드 체크리스트(PREPROC·POOL·PERIOD)** — 원문 전문(arxiv html 또는 PDF 텍스트)에서 {neutraliz, industry dumm, residual, imput, industry median, MAD, winsor, independently, separately, each stock, local learning, excess return, dividend, walk-forward, kill-switch, response function, gradient norm, quintile, decile, long … short, transaction cost, commission} 을 결정론으로 찾고, 히트마다 FIDELITY 의 kept/changed 대응 문장이 없으면 후보.
- **R10 원문 경로·인용(DECL_PAPER)** — 'HTML 없음·판독 불가' 주장이 있으면 `arxiv.org/html/<id>v1` 과 `r.jina.ai/https://arxiv.org/pdf/<id>` 를 실제로 받아 판독되면 실패(H). FIDELITY 의 인용문은 원문에서 축자 검색하고, 원문 문장이 인용 끝에서 이어지면 절단 후보(M — 예 'and recurrence'·'which is calculated as follows').
- **R11 NOT STATED 검증(DECL_PAPER)** — FIDELITY 의 'NOT STATED/미명시/silent' 각 항목의 주제어를 원문에서 'defin·calculated·as follows·=' 근처로 검색, 히트하면 후보(M — 예 'definitions of factors No.19-33').

### 5.3 실측 검증 (R1~R4 · 감사가 지목한 엔진 행을 규칙이 맞히는가)

- 패스별로 **감사 당시 엔진**(git blob)에 R1~R4 정규식을 돌려, 지적 본문이 인용한 `engine.R:<행>` ±1 행에 같은 계열 규칙이 걸리는지 쟀다(`scanner_cited_line_hit` 열).
  - GUARD: 행을 인용한 25건 중 **23건 적중**(미적중 F011 코호트 정규화 · F076 예측 평균 집합 — 둘 다 L 로 분류).
  - SKIP: 코드 규칙 7건 중 6건 적중. 미적중 1건(F102)은 `next` 가 아니라 행 필터로 월이 사라진 경우라 R2(산출물 격자)가 맡는다.
  - WINDOW 5/5(창 길이는 R1 상수, 창 종점·행 수 창은 R3) · FDB 행 인용 3/3 · UNIV LIQ 2/2.
- **오탐 부담(R1 을 자유 서술 FIDELITY 에 그대로 걸 때)**: 감사된 엔진 33개(FIDELITY 판을 특정할 수 있는 것) 기준 최상위 상수 중앙 30개(7~59), 그중 FIDELITY 에 이름·값이 안 나오는 상수 중앙 18개, `next` 중앙 6개(최대 14). 신고 누락으로 지적된 상수는 이름이 실제로 FIDELITY 에 없었다(`.DCAP`·`.COV`·`.NMIN`·`.SD_FLOOR`·`.BIG` 와 HFL 정지 상수 7종 `.GD_*`·`.CD_*`·`.ROOT_TOL` — `.LEAF_MO_L` 만 값 6 이 우연히 등장), 신고된 상수는 있었다(`.Y_CLIP`·`.TMIN_I`·`.EPS`·`.K`). 즉 신호는 있으나 후보 18개를 사람이 거르게 할 수는 없다 → **구조화 상수표 + 완전성 관문**이 맞다.
- R5~R11 은 설계안이다(이번에 실측 검증하지 않았다).

### 5.4 사전검사로 막을 수 있었던 범위 (상한)

- misdeclared 축 지적 106건: **H 35 · M 40 · L 31** (H/M 71%).
- misdeclared 패스 28개 중 misdeclared 축 지적이 **전부 H** = 5개(0806.2606 p1·p2 · 1403.8125 p2 · 2003.02515 p1 · 2006.04639 p2), **전부 H/M** = 12개(위 5 + 1707.05552 p2b · 1806.01743 p1 · 2508.18592 p1 · 2511.12129 p1 · combo4 p1 · combo3 p1 · combo(2007+2301) B).
- 상한인 이유: 사전검사가 그 지적들을 감사 전에 신고·수정시키고, 감사가 다른 것을 새로 찾지 않는다는 가정이다. L 지적(FORMULA 11 · PORT 6 · DECL_PAPER 6 · DECL_WHY 3 · TIMING 2 · 기타 3)이 남은 16개 패스는 여전히 감사가 필요하다.
- 권장 순서: ①정적 공시 자동 부착(R5·R6·R4②·R8 H) → ②엔진 스캔 + 구조화 신고 완전성 관문(R1·R2 코드·R3·R4①) → ③측정 후 산출물 대조(R2 격자·R7) → ④원문 키워드·인용·NOT STATED 검사(R9~R11) → ⑤LLM 6축 감사. ①은 구현자에게 묻지 않고 기계가 쓴다 — HARNESS 12건과 2차 패스 기각 3건이 이 층에서 사라진다.

---

## 6. 프롬프트가 유발하는 지시 (E)

근거 = `02_Infrastructure/ops/rf_replication_auto.sh` PROMPT(작업 트리 판 행 번호). 같은 문장이 10-05 의 `RP_AUTO_CLEAN_2508_18592/prompt.txt` 24·31·64·65·67행에도 그대로 있다.

1. **449행 `유동성 하한 adv20 ≥ 2e8 은 t-1 로 적용.`** — SOT `.claude/rules/lean-loop.md` 축 2층 표의 충실구현 행은 '유동성 필터 = 논문 우선(`paper_faithful`)', `CLAUDE.md` 는 LIQ 2e8 을 실투형(강화부터) 축으로 둔다. 결과: 감사된 엔진 39개 중 24개가 2e8 하한을 코드에 둔다. 구현자는 이를 '지시 축'으로 적고(F016 1707.05552 p1 · F039 2006.04639 p2 — 둘 다 misdeclared 축), 2006.04639 2차 패스는 **이 지적 하나로** misdeclared 였다. 반면 2404.08129 1차 universe 축은 같은 필터를 허용 범위로 받아들였다(§4.5). 이 충돌은 09-07 메모리 카드에 이미 기록됐는데 10-05 프롬프트에도 남아 있다.
2. **416행 `faithful 이면 changed 는 유니버스만 K200 합집합 KQ150 이다.` + 450행 `기간 2005-01-01~.`(축으로 지시)** — faithful 라벨 구현은 changed 를 유니버스(와 LIQ)로만 쓴다. 1403.8125 1차 FIDELITY.changed 가 정확히 '유니버스만 … + adv20(t-1)≥2e8 유동성 하한' 이었고, 같은 패스에서 기간 차이(F010, `prompt`)와 방어 상수 3종(F007~F009)이 미신고로 걸렸다. 신고 체크리스트(424~441행)는 이 문장과 반대 방향을 지시한다 — 두 지시가 한 프롬프트 안에서 충돌한다.
3. **452행 `팩터 DB 는 load_month_factors() 경유(C15), Z_Score_Aligned 만 소비(C13).`** — 경로를 강제하면서 그 변수의 변환(유니버스 1/99 clip · ±3 clip · IC 부호 정렬 · 재표준화 · 중성화 없음)을 공시하라는 말이 없다. F032(2003.02515 1차 — 논문은 원값 순위, misdeclared 의 유일한 지적) · F132(2508.18592 — 논문의 업종·시총 중성화가 `Z_Score_Aligned` 에 없음)가 여기서 나온다(`prompt_related`). 이 경로로는 원값 순위·중성화를 만들 수 없다는 사실 자체가 구현자에게 전달되지 않는다.
4. **409행 `이식은 *기전*을 옮기는 것이고, 파라미터는 **우리 고정 축**(25종·월간·EW)을 쓴다.`** — 충실구현 단계의 고정 축은 '논문 그대로'인데, adapted 경로로 가면 실투형 축(25종·EW)을 쓰라고 한다. 2404.08129 는 '논문에 포트폴리오가 없다'(사실 아님 — F065)는 전제로 이식 경로에 들어가 §5.7 5분위 롱숏을 top-25 롱온리 EW 로 바꿨다(F064, `prompt_related`).
5. **신고 체크리스트(424~441행 · 처음 나타난 커밋 = 2026-09-04 19:47 자동 커밋 `e9f7bce99`)의 빈칸** — 체크리스트 도입 뒤에도 GUARD 지적은 계속 나왔다(도입 후 31개 패스 중 6개에서 misdeclared 축 GUARD 15건 · 도입 전 8개 중 3개에서 7건). 그리고 목록에 없는 범주가 지금 기각을 만든다: 미발행 월·스킵 정책(SKIP 7건, 전부 misdeclared 축) · 팩터 DB 정의 차이(FDB 4) · 'NOT STATED' 주장 검증(DECL_PAPER 11 + 2차 10) · 하네스 동작(HARNESS 12).
6. **하네스 동작에 대한 서술이 프롬프트에 없다** — 그런데 체크리스트는 '전부 적어라'를 요구한다. 구현자는 하네스를 추측해 쓰고 틀리거나(F002 '재정규화한다' → F006 '재정규화 없다', 둘 다 틀림 · F084 '논문 거래일과 일치') 빠뜨린다(F012~F015). R5 자동 공시로 대체해야 할 영역이다.
7. (관찰) **재구현 절의 `지적이 부당하다고 판단하면 … changed 에 원문 근거로 적어라`** — 반박과 해명이 FIDELITY 를 키우고(중앙 ×1.53), 2차 패스의 기각은 선언 문구 오류 비중이 더 높다(58% vs 43%). 지시 자체의 결함이라기보다 '서술로 방어하는' 유인의 비용이다.

---

## 7. 부수 관찰 — 시점오염 성격의 지적 3건 (`pit` 꼬리표)

감사는 충실도 지적으로 냈지만 서술상 의사결정 시점 이후 정보가 개입한다: F079(2511.12129 EPS 분모 Size/Close = 이후 액면분할 조정계수 포함 — 2차에서 EPS 제거로 해소) · F092(2511.12490 value = 1/수정주가, 소급 재작성 계열 — 2차 감사에 언급 없음) · F137(2508.18592 피처 집합을 전체 패널 가용성으로 확정 — 재구현 진행 중). 앞의 둘은 R8 이 결정론으로 잡는다. Judge 는 A 등급 후에만 돌므로 이런 지적은 등급 무관하게 사전검사 층에서 잡는 편이 낫다.

---

## 부록 A. 감사 실행(R00~R41) ↔ 원천

`member_item_ids` 의 `Rnn-Uk`/`Rnn-Sk` = 실행 Rnn 의 `undeclared_changes[k]`/`signal_mismatch[k]`(1부터). git 원천은 `04_Research/strategies/` 아래 경로@blob.

| 실행 | run | 판정 | 방식 | U/S | 원천 |
|---|---|---|---|---|---|
| R00 | 0806.2606 p1 | misdeclared | fanout | 2/3 | RP_AUTO_0806_2606/fidelity_audit.json@8e1f643f |
| R01 | 0806.2606 p2 | misdeclared | fanout | 2/0 | …@a7dae593 |
| R02 | 1403.8125 p1 | misdeclared | fanout | 8/2 | RP_AUTO_1403_8125/fidelity_audit.json@368054f8 |
| R03 | 1403.8125 p2 | misdeclared | fanout | 7/0 | …@b001040f |
| R04 | 1505.00328 p1 (단일) | faithful | single | 0/0 | RP_AUTO_1505_00328/fidelity_audit.json@63454779 |
| R05 | 1707.05552 p1 | misdeclared | fanout | 4/1 | RP_AUTO_1707_05552/fidelity_audit.json@a933fbda |
| R06 | 1707.05552 p2a | adapted | fanout | 0/1 | …@c7815fdb |
| R07 | 1707.05552 p2b | misdeclared | fanout | 2/2 | …@9f6098bc |
| R08 | 1806.01743 p1 | misdeclared | fanout | 1/0 | RP_AUTO_1806_01743/fidelity_audit.json@156e43df |
| R09 | 1806.01743 p2 | adapted | fanout | 0/0 | …@f4fa93cf |
| R10 | 2001.04185 p1 | adapted | fanout | 0/3 | RP_AUTO_2001_04185/fidelity_audit.json@0ebb0bda |
| R11 | 2002.06975 p1 실행 a | misdeclared | fanout | 3/4 | RP_AUTO_2002_06975/fidelity_audit.json@ae9f31f4 |
| R12 | 2002.06975 p1 실행 b | misdeclared | fanout | 3/4 | …@7608c30a |
| R13 | 2002.06975 p1 실행 c | adapted | fanout | 0/0 | …@031d7745 |
| R14 | 2002.06975 p2 | adapted | fanout | 0/0 | …@c542c812 |
| R15 | 2003.02515 p1 | misdeclared | fanout | 2/3 | RP_AUTO_2003_02515/fidelity_audit.json@f14d60d5 |
| R16 | 2003.02515 p2 | misdeclared | fanout | 1/0 | …@df237b3f |
| R17 | 2006.04639 p1 (사후) | misdeclared | fanout | 2/3 | RP_AUTO_2006_04639/fidelity_audit.json@4431f7ab |
| R18 | 2006.04639 p2 | misdeclared | fanout | 1/0 | …@00057605 |
| R19 | 2011.05381 p1 | misdeclared | fanout | 2/3 | RP_AUTO_2011_05381/fidelity_audit.json@4f3e0336 |
| R20 | 2011.05381 p2 | misdeclared | fanout | 3/1 | …@cb1fb69b |
| R21 | 2202.05702 p1 | misdeclared | fanout | 2/2 | RP_AUTO_2202_05702/fidelity_audit.json@a53fd66c |
| R22 | 2202.05702 p2 | misdeclared | fanout | 1/1 | …@55c32040 |
| R23 | 2302.10175 p1 (단일) | adapted | single | 3/1 | RP_AUTO_2302_10175/fidelity_audit.json@da62cb77 |
| R24 | 2302.10175 p1 (사후 팬아웃) | misdeclared | fanout | 4/2 | …@d01aca5a |
| R25 | 2404.08129 p1 (사후) | misdeclared | fanout | 16/6 | RP_AUTO_2404_08129/fidelity_audit.json@1c1f043d |
| R26 | 2404.08129 p2 | adapted | fanout | 3/1 | …@e472a062 |
| R27 | 2511.12129 p1 | misdeclared | fanout | 9/2 | RP_AUTO_2511_12129/fidelity_audit.json@fdfd2470 |
| R28 | 2511.12129 p2 | adapted | fanout | 0/4 | …@3f4ccd61 |
| R29 | 2511.12490 p1 | misdeclared | fanout | 9/3 | RP_AUTO_2511_12490/fidelity_audit.json@36004b86 |
| R30 | 2511.12490 p2 | misdeclared | fanout | 2/1 | …@d109a972 |
| R31 | combo:2007.08115+2301.09173 요청 A | adapted | single | 0/0 | RP_AUTO_COMBO_combo_2007_08115_2301_09/fidelity_audit.json@c61ee806 |
| R32 | combo:2007.08115+2301.09173 요청 B | misdeclared | single | 2/2 | …@d5bd07ce |
| R33 | combo:1403.8125+2007.08115+2301.09173+2404.08129 p1 | misdeclared | fanout | 4/0 | RP_AUTO_COMBO_combo_1403_8125_2007_081/fidelity_audit.json@15b11b88 |
| R34 | 같은 combo p2 | misdeclared | fanout | 2/1 | …@90ce62eb |
| R35 | combo:1403.8125+2301.09173+2404.08129 p1 | misdeclared | fanout(축 재구성) | 4/3 | RP_AUTO_COMBO_combo_1403_8125_2301_091/fidelity_axis_*.json (2026-09-10 12:20~12:32 커밋판) |
| R36 | 같은 combo p2 | misdeclared | fanout | 9/0 | …/fidelity_audit.json@14deb151 |
| R37 | combo:1403.8125+2007.08115+2011.05381+2301.09173+2404.08129 p1 | adapted | fanout | 0/0 | RP_AUTO_COMBO_combo_1403_8125_2007_081/fidelity_audit.json@0bc488ee |
| R38 | combo:1403.8125+2002.06975+2007.08115+2011.05381+2301.09173+2404.08129 p1 | adapted | fanout | 0/0 | RP_AUTO_COMBO_combo_1403_8125_2002_069/fidelity_audit.json@19ba6b91 |
| R39 | 1505.00328 청정 p1 | misdeclared | fanout | 8/1 | RP_AUTO_CLEAN_1505_00328/.clean_audit_src/r1/fidelity_audit.json |
| R40 | 1505.00328 청정 p2 | adapted | fanout | 2/0 | RP_AUTO_CLEAN_1505_00328/fidelity_audit.json |
| R41 | 2508.18592 청정 p1 | misdeclared | fanout | 9/5 | RP_AUTO_CLEAN_2508_18592/.clean_audit_src/r1/fidelity_audit.json |

`RP_AUTO_COMBO_combo_1403_8125_2007_081` 디렉터리는 slug 절단(24자) 때문에 서로 다른 결합 셋(3·4·5편)이 같은 작업 디렉터리를 썼다 — 패스 귀속은 저널의 `start` 이벤트 paper 키로 했다.

## 부록 B. findings.csv 열

`finding_id` · `paper_key` · `pass`(p1/p2/p2a/p2b/p1A/p1B/p1_clean/p2_clean) · `pass_verdict`(그 구현의 정본 감사 판정) · `audit_runs`(병합된 감사 실행) · `axes` · `axis_verdicts`(축=축판정) · `from_misdeclared_axis`(1 = misdeclared 축에서 나옴) · `list_kind`(undeclared/mismatch) · `n_merged_items` · `member_item_ids`(부록 A) · `type_primary` · `type_secondary` · `flags` · `title`(요지 1줄) · `machine_check`(H/M/L) · `check_rule`(§5.2) · `scanner_cited_line_hit`(§5.3 검증 결과: 적중 규칙 / miss / no_cited_line) · `text_head200`(첫 원 항목 앞 200자).
