# P1R03 사전등록 초안 격리 교차 점검 v3(좁은 변경분 · v3 → v4)

- 점검자: 격리 교차 점검(서브에이전트)이다. 초안 세션과도, 점검 v1 · v2 와도 맥락을 공유하지 않았다. 측정 결과는 없다(`results/` 는 빈 폴더). 기술 점검만 했고, 판단 · 철학 정렬은 감독 몫이다. 점검 시각은 2026-11-13 00:05~00:21 이고 HEAD 는 시작과 끝 모두 `83086746a` 다.
- 점검 종류: **좁은 변경분 점검(v3 → v4)**. 기준은 점검 v2 §3(필수 N-1 · 권고 R-5′ · R-6′ · N-2 · N-3 · N-4 · 선택 S-6 · S-7)과 그 '고치는 법'이다. 차이는 `git diff HEAD -- <판 폴더>` 로 봤다(HEAD = 초안 v3).
- 대상(md5 앞 8자리)
  - `prereg_draft.json`: draft_version 4 · **8df67731**
  - `prereg_draft.md` 99297ded · `round_spec.json` 169d23fc(= `spec_md5`) · `DESIGN.md` a6e1ff18
  - `drafts.json` 08d930bb: v4 항목의 md5 · md5_md 가 위 둘과 같다 · review = null
  - `tools/p1r03_dawn_measure.sh` 81dbfd96 · `tools/p1r03_milestone.R` e3fa0274
  - 카드 사본 6a2a1d21: `06_Registry/behavior_card.json` 과 같다
  - `specs/` 15: md5 15/15 · mtime 22:52 그대로
  - v3 기준본 = `git show HEAD:` 사본(사양 5836ff67 · 초안 f6307548 — 점검 v2 기록과 같다)
- **판정: ok** — N-1 이 해소됐고 새 필수는 없다. 규칙 · 선택 · 칸 · 핀 · 시험 · 카드 설정 · τ_D 는 v3 와 같다.
  - 권고 R-6″ 하나는 등록 전에 고칠 만하다. 다만 고치면 사양 md5 가 바뀌어 초안 v5 와 그 한 줄의 변경분 점검이 다시 필요하다. 그대로 등록하면 이 리뷰가 정정 기록으로 남는다. 어느 쪽을 골라도 판정은 바뀌지 않는다.
- **건수: 필수 0 · 권고 1 · 선택 4**(새 지적만 셌다. v2 의 미해소 선택은 §1 표에 이월로만 둔다).

## 0. 정보 경계 선언

- 연 것
  - 판 폴더: diff 전문 · 사양과 초안의 v3 · v4 블록 대조(파이썬 객체 비교) · 셸 전문 · 이정표 R 전문 · DESIGN §1 · §6~8 · md 의 노출 · 결론 범위 절. 점검 v2 는 기준본이라 전문을 읽었다.
  - 감독 리뷰(소수점 값은 가렸다): `20261112_2218_T1.md` 1-9행 · 절 제목 · 'deprecation_reason' 개수 / `20261112_2249_T3.md` 5-7 · 53행 / `20261112_2317_T1.md` 112-118행.
  - 판단 원장: R-20261112-001 · 002 · 004 의 id · at · role · trigger · file · round 만.
  - 팩터 등록부(파이썬 · 개수만)
    - `direction_economic_evidence` 는 있는지 · 비었는지만 셌다. **내용은 한 번도 출력하지 않았다.**
    - `direction_economic_basis` 는 정책의 열거값 4종 중 무엇인지만 셌다.
    - 구성원 25개는 data_source · direction · stored_sign · definition(소수점 가림)을 봤다.
    - HEAD 와 작업 트리의 차이는 항목 id 와 바뀐 키 이름만 봤다.
    - dedup · reason · evidence · history · research_stage 류 필드 내용은 출력하지 않았다.
  - 엔진 사양: `FC_FAM_*` 14개 + `FC_TOTAL_EW` 의 `core.members`(id · s_reg)와 `direction` 키. `FC_FAM_value/engine.R` 는 grep 만 했다.
  - 코드 · 문서(읽기)
    - 방향 계열: `DIRECTION_POLICY.md:11-15` · `apply_direction_basis.py` 1-40(docstring)
    - 설계: 설계 README `:361`
    - 코어 · 운영: `rf_base_cache.R`(grep) · `round.sh`(40-60 · 76-135) · `driver.R` · `register.R`(96-106) · `factor_combinable.R`(grep)
    - 시드: `p1s02_seed_watch.sh`(grep · 55-128)
  - 상태
    - 시드 상태 줄 1줄(00:03 'W 대기(P1S02_E2_C0) — 시각 창 밖(3분)').
    - `.cache/rf_base_signal` 은 개수만 셌다(86 · 11-12 22:00 뒤 생긴 것 0).
    - 예약 작업 두 개의 State 를 읽었다(Qvest_DailyRefresh Running · Qvest_MorningBrief Ready).
- 안 연 것: `results/**`(빈 폴더 ls 만) · `stage_artifacts/**` · `authoritative_remeasure.json` · 텔레그램 기록 · `.cache/scheduler_logs/*replication*` · 레인 로그 · 2023 이후 성과 수치 · 등급.
- 우연 열람: 없다. `apply_direction_basis.py` 머리의 '실측' 한 줄은 2000-06~2002-06(τ_D 이전) 순위 상관이고, 값은 가린 채 읽었다.
- 실행한 것
  - Git Bash 읽기 명령 · md5sum · git diff/show/status · `bash -n`(셸 · 통과).
  - 스크래치 폴더 파이썬(-I · 표준 라이브러리 · 개수 셈과 대조).
  - grep 패턴 시험: 스크래치에 만든 상태 문자열 6줄에 대고 돌렸다.
  - PowerShell `Get-ScheduledTask`(읽기).
  - **R · 시험 · `round.sh` · 셸 본체는 하나도 돌리지 않았다.**
- 쓴 것: 이 파일 1개(스크래치 임시 파일 제외).

## 1. v2 지적별 처리

| v2 지적 | 처리 | 근거(파일:행) |
|---|---|---|
| **N-1** 노출 두 리뷰 섞임(필수) | **해소** | round_spec.json:150 · :151(md:56 · :57)이 v2 고치는 법의 두 문장과 바이트 동일하다. 원문과도 맞는다: R-001 = `20261112_2218_T1.md:5`(dedup.reason · 전기간 승인 게이트 통계 · 값 미전재 · 'E3 · N2 에만' — 그 절은 :74 · :101 에 있다 · 이 파일에 'deprecation_reason' 0건) · R-002 = `20261112_2249_T3.md:6`(deprecation_reason 2건 · 소수점 가림 · 행 수만). 원장도 맞다(R-001 = T1 · P1S02 · 2218_T1.md · R-002 = T3 · 2249_T3.md). `changes_after_superfan`(:181)은 'C-033 노출 4줄'이다 ✓(괄호 문구는 → S-9). DESIGN §7(DESIGN.md:47)도 9줄이다 ✓ |
| **R-5′** 쌍 두 줄 겹침 · 3쌍 누락 | **해소** | 결론 범위가 한 줄(:160 · md:67)이 됐다: 같은 자료원 9 · 다른 자료원 3 · 기계 규칙 1(D46↔R15) · 가족 안 2쌍 · AC01 메모 보존 — v2 표 · 고치는 법과 같다. 옛 두 줄(v3 [3] · [13])은 지워졌다. 사양 · 초안 · md · DESIGN 에서 '같은 정의' · '8쌍' · '1~5쌍' 은 0건이다. 재도출: 9쌍 전부 같은 data_source · 서로 다른 가족(v2 는 6쌍만 확인했다) · 다른 자료원 3묶음 · 가족 안 2쌍(quality)이 등록부 · own_spec 과 맞다. 정의 × stored_sign × s_reg 로 부호를 다시 본 것(같은 자료원 5쌍 · XF_DU03↔Q13 · T14↔D53↔L41)은 모두 같은 부호라 '이중(삼중) 가중'이 맞다 |
| **R-6′** 방향 출처 노출 | **부분** | 새 줄이 생겼다(:154 · md:60). 334(14 엔진 합 = 합집합 · 겹침 0) · 143 · 371 · 169 는 재도출과 일치한다(HEAD 등록부는 370 · 169 — 차이는 비구성원 1개). 그러나 '191 은 등록부 원래 값'은 틀렸다 → 권고 R-6″ |
| **N-2** DESIGN 셈 단위 · 줄 수 | **해소** | DESIGN.md:9 = 원천(토탈 제외 · 저위험 4가족 = 1)으로, 사양 :169 · :172 와 뜻이 같다(셈법을 풀어 쓴 판이라 글자까지 같지는 않다). DESIGN.md:47 = 9줄이고, 목록 9개 = 사양 exposures 9줄이다 |
| **N-3** 뷰 바뀐 뒤 재측정 | **해소** | DESIGN.md:53 · 이정표 R:17 에 'results 칸 파일 15 + 측정 시작 뒤 생긴 `.cache/rf_base_signal`'이 적혔다. 서술도 맞다: 캐시 키 ①~⑦ · AUX = consensus 뿐이고 factor_combinable 은 0건이다(rf_base_cache.R:15-46). 절차대로 하면 다시 잰다: `m()` 은 ok json 이 없으면 칸 폴더 · 지문 파일을 지우고 다시 재고(round.sh:99-104), 병합은 verdict.json 을 덮어 쓴다(driver.R:87). 첫 측정은 깨끗하다(22:00 뒤 생긴 캐시 0) |
| **N-4** 시드 E3 follow 대기 | **해소**(대가 → S-10) | 셸:38 의 패턴이 실제 상태 문구와 맞는다: 시드 :79 'M 측정 중 — <code>' · :94 'W(follow) E2 직후 — …' · :123 'W 대기(<code>) — <사유>'. 패턴 시험에서 E2 대기 · 끝 줄은 통과하고, E2 측정 · E3 follow · E3 대기 줄은 막았다. :96 'W 측정 창 · 레인 측정 0 대기 — P1S02_E3_RX0' 은 막지 않는다. 이 줄은 보통 대기 진입 때 잠깐 나오는데, 보통 대기의 E3 는 낮 창 밖에서 서지 못하므로 겹침이 없다 |
| v2 §3 S-6 시행 집합 생략(p4.R:1380-1381) | 미해소(선택) | 결론 범위 :163 그대로다. v4 의 'S-6 실효 시작'은 v1 S-6(v2 §2 표 이월)이다 → S-8 |
| v2 §3 S-7 C-021 (3) · C-022 (c) 실행자 | 미해소(선택) | 사양 · DESIGN grep 0. v4 의 'S-7(사양 밖)'은 v1 S-7 이다 → S-8 |
| (v1 S-6 · v2 §2 이월) 가족별 실효 시작 | 해소 | 결론 범위 :173 · md:80. 선택 규칙이 `none` 이라 '칸 사이 비교는 겹치는 창'과 부딪히는 규칙이 없다 |
| (v1 S-7 · v2 §2 이월) 체인 확인 열린 실패 | 해소 | 셸:25-26 — 빈 판독을 실행 중으로 본다(닫힘). 예약 작업 두 이름은 실재한다(읽기) → 이름이 틀려 영구 대기할 일은 없다. 판독 실패가 '밤 체인 실행 중'으로 적히는 것은 → S-11 |
| v2 §3 S-1~S-5 | 범위 밖 · 그대로 | 이정표 R:23(summary 문자열 조건) · 셸:32 · :53 · 결론 범위 :171 · pins.basis · changes_after_review[0] 모두 그대로다 |

- 바뀌지 않아야 할 블록(파이썬 객체 대조)
  - 사양: schema · purpose · hypothesis · cells · rules · selection · tests · pins · behavior_card_cfg · tau_d 가 v3 와 같다.
  - 초안: core · rules_resolved · sentences · pins · cells · behavior_card_cfg 가 v3 와 같다.
  - 바뀐 것은 사양의 exposures(7 → 9) · conclusion_scope(17 → 17: 2줄 빠지고 2줄 들어옴) · changes_after_review(1 → 2) · changes_after_superfan(1줄 교체)뿐이다. 초안은 draft_version · drafted_at · spec_md5 · spec 만 바뀌었다.
  - 초안에 든 spec = 사양 파일이다. md 의 노출 9 · 결론 범위 17 줄은 사양 문장 그대로다.
- 핀은 표본이 아니라 전수로 다시 쟀다
  - `pins.files` 76/76 · `pins.core.files` 20/20 · 칸 사양 15/15 가 디스크 md5 와 같다. 매니페스트 md5(4d00113a)는 기록값이 그대로라는 것만 봤고 다시 계산하지 않았다.
  - 핀에 적힌 패키지 5개 · R 문자열(4.6.2)은 v2 기록과 같다. 설치본 DESCRIPTION 은 다시 보지 않았다.
  - 바뀐 판 폴더 파일(사양 · DESIGN · 셸 · 이정표 R)은 핀에 없다. 등록부 · custom_factors 도 핀 밖이다(v3 와 같다).
- 등록 조건에 닿는 것
  - ① 이 점검 = ok → `reviewed` 를 표시한다. R-6″ 를 고치면 v5 를 다시 점검한다.
  - ② 사양 md5 = spec_md5 다.
  - ⑦ 미커밋: round_spec.json · DESIGN.md · tools/ 두 파일. `rc_uncommitted` 는 prereg_draft* · drafts.json · results 만 뺀다(register.R:103) → 커밋 뒤 등록한다.

## 2. 새 지적

### 권고

**R-6″. 노출 :154 의 '191 은 등록부 원래 값이다'가 재도출되지 않는다 — 7개는 Q 의 코드 · 정의 판정이다(R-6′ 의 남은 몫)**

- 재도출: 근거 종류는 `direction_economic_basis`(DIRECTION_POLICY.md:13)로 셌다.

| 구성원 334 | 근거 필드 있음 | 근거 필드 없음 |
|---|---|---|
| literature | 77 | — |
| literature_mixed_defensive_tiebreak | 66 | — |
| code_and_definition | — | **7** |
| registry_original | — | **184** |
| 합 | 143 | 191 |

- `code_and_definition` 의 뜻은 '코드 주석 · 정의로 Q 판정'(DIRECTION_POLICY.md:13)이다. '문헌 검토 전 — 등재자가 쓴 값'인 registry_original 과 다르다.
  - 7개 = AC09_NNI · AC14_Discretionary_Accruals · AC17_Accrual_Reversal · AC25_Accrual_Size_Interaction(accrual) · Q27_CapEx_to_Rev · Q28_Cash_Conversion · XF_PR04_NetInterestMargin(quality).
  - 등록부의 code_and_definition 7개는 모두 구성원이다.
  - 등록부 전체는 169 + 7 + 195 = 371 이다. README :361 의 '169 · 195'와 맞고, 7 은 README 가 세지 않은 몫이다.
- 왜 필수가 아닌가
  - τ_D 접촉을 덜 적은 것이 아니다. 근거가 기록된 7개를 '확인하지 않은 원래 값'에 넣어서, 미확인 집합을 7 크게 적었다(보수 쪽 오류).
  - 그래도 방향을 정한 주체(Q 판정 대 등재자)가 틀렸고, Q 는 시험 창을 본 상태다(노출 :146).
  - 규칙 · 핀 · 칸에는 닿지 않는다.
- 고치는 법: :154 의 둘째 문장을 아래로 바꾼다.
  - "구성원 334 = 방향 근거 필드(direction_economic_evidence) 있음 143(literature 77 · literature_mixed_defensive_tiebreak 66) · code_and_definition 7(코드 주석 · 정의로 Q 판정 — AC09 · AC14 · AC17 · AC25 · Q27 · Q28 · XF_PR04) · registry_original 184(문헌 검토 전 등재자 값) — 등록부 전체 371 = 169 · 7 · 195(README §9 는 169 · 195)."
  - 셋째 문장의 '원래 값이'는 'registry_original 이'로 바꾼다.
- 비용: 사양 md5 가 바뀌므로 초안 v5 와 이 한 줄의 변경분 점검이 필요하다. S-8 · S-9 의 표기도 같이 넣으면 한 번에 끝난다. 안 고치고 등록하면 등록 뒤에는 사양을 바꿀 수 없으므로, 이 리뷰가 정정 기록이 된다.

### 선택

- **S-8. 'S-6 · S-7' 표기가 v1 과 v2 에서 다른 항목을 가리킨다.**
  - 사양 :177 과 결론 범위 :173 의 '(격리 점검 v2 S-6)'은 v1 S-6(가족별 실효 시작 — v2 §2 표의 미해소 이월)이다. v2 §3 S-6 은 시행 회계 문장의 생략(같은 기저를 쓴 다른 사슬의 시행 · p4.R:1380-1381)이고, :163 에 그대로 남아 있다.
  - 'S-7(사양 밖)'도 v1 S-7(running 열린 실패)이다. v2 §3 S-7(철학 C-021 (3) · C-022 (c) 의 '누가 · 언제')은 사양 · DESIGN 어디에도 없다.
  - 고치는 법
    - 다음 사양 변경 때 표기를 'v1 S-6 · v1 S-7(v2 §2 이월)'로 바꾼다.
    - v2 §3 S-7 은 DESIGN §8 판정 해석 단계에 한 줄 넣는다(md5 무관).
    - v2 §3 S-6 은 사양 변경이라, R-6″ 와 함께 고치는 것이 아니면 미뤄도 된다.
- **S-9. :181 'C-033 노출 4줄(T1 두 리뷰의 열람 · Q 의 레인 로그 열람)' — 4줄인데 괄호에는 출처가 셋(T1 R-001 · T1 R-004 · Q)만 있다.**
  - 넷째 줄은 T3 R-002(:151)다.
  - C-033(20261112_2317_T1.md:116)이 요구한 것은 R-001 · R-004 두 줄이다. T3 줄은 C-011(20261112_2249_T3.md:53) 계열이고, Q 줄은 초안이 스스로 넣었다.
  - 기록 정확성만의 문제다. 고친다면 '(T1 두 리뷰 · T3 한 리뷰 · Q 의 레인 로그 열람 — C-033 몫은 R-001 · R-004)'.
- **S-10. N-4 의 대가가 v2 추정('드물다')보다 크다(셸 · md5 무관).**
  - 'W 대기(P1S02_E3_RX0) — 시각 창 밖'은 보통 대기에서만 나온다. follow 는 시각 창을 보지 않는다(시드 :109).
  - 보통 대기의 E3 는 낮 창 08:20~11:45(:34)에만 선다. 그래서 P1R03 창(04:30~06:00 · 18:00~22:00)과 겹칠 수 없다.
  - 그런데 이 줄이 밤새 10분마다 다시 쓰여서(:123), 셸:38 이 P1R03 의 저녁 · 새벽 창을 막는다.
  - E3 가 보통 대기로 떨어지는 길은 두 가지다: 코어 건너뜀 뒤(:78 `mode=normal`), 그리고 follow 중 지문이 바뀔 때(:103-105 — 00:03 밤 체인이 자료를 바꾸면 그렇게 된다).
  - 그러면 P1R03 은 E3 가 다음 낮 창에서 끝날 때까지 서지 못한다. 40시간 상한(셸:21 · :32)이 먼저 차면 조용히 끝난다(v2 S-2). 다만 06:00 이정표가 사유를 싣는다(:52-54).
  - 11-13 새벽은 해당하지 않는다(지금 시드 = E2 대기).
  - 고치는 법: `grep -E "M 측정 중|W\(follow\)|W 대기\(P1S02_E3_RX0\)" "$SEED_ST" 2>/dev/null | grep -qv "시각 창 밖"`.
- **S-11. 문구가 낡았다(md5 무관).**
  - DESIGN §8 시작 조건(DESIGN.md:51 '판 2 시드 측정 중 아님')과 셸 머리(:6 '측정 중(M) 아님')가 N-4 로 넓힌 조건(E3 follow · E3 대기)을 적지 않았다.
  - S-7 닫힘은 판독 실패도 '밤 체인 실행 중'으로 적는다(셸:35-36). 그러면 06:00 이정표의 '마지막 사유'가 오해를 부를 수 있다. `running()` 이 빈 판독에 다른 종료 코드를 주게 하고, 사유를 '체인 상태 판독 실패'로 나누면 된다.

## 3. 못 본 것

- R 실행: `rc_pins_mismatches` · `rc_prereg_md` · 시험 · `fce_verify` 를 돌리지 않았다. 핀은 파이썬 md5 로 전수 대조했다. 실제 실행 R 판(PATH 의 Rscript)은 확인하지 않았다.
- 정렬 뒤 신호의 정의 문장 대조는 같은 자료원 5쌍 + 다른 자료원 2묶음만 했다.
  - D46↔R15 · Q06↔GR03 · Q20↔IN04 · D45↔R07 은 이름 · direction · stored_sign 이 같은지만 봤다.
  - XF_LL05↔Q31 은 direction · stored_sign 만 봤다.
- 등록부가 측정 때 직접 읽히는지(핀 밖)
  - 결합용 뷰가 빌드 때 등록부 방향으로 정렬한다(factor_combinable.R:8 · :188)는 것만 봤다.
  - 작업 트리 등록부는 HEAD 와 비구성원 1개(RP_1603_00751) 추가만 다르다. 구성원 334 의 항목은 하나도 바뀌지 않았다(direction · stored_sign · 근거 종류 포함).
- code_and_definition 7개를 Q 가 언제 판정했는지는 보지 않았다. direction_history 에 reason · evidence 필드가 있어 열지 않았다.
- 시드 E3 가 실제로 보통 대기로 떨어질 확률(레인 GPU 슬롯 · 자료 갱신 일정)은 보지 않았다.
- 셸을 띄우는 환경과 발송(QVEST_TG_DRY_RUN · PATH)은 보지 않았다. 이정표 R 은 눈으로만 읽었다(R 문법 실행 검사 없음).
- 판단 · 철학 정렬은 감독 몫이다.
