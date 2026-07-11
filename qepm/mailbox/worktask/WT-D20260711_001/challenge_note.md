# Self-Adversarial Challenge — WT-D20260711_001 (H-d disclosure TEXT content LLM pilot)

**Charter §8 No Silent Override.** finalize 직전 자체 적대검증 (v8.2 Opus 4.8 native, 외부 Codex 없음).
Pre-reg SHA256 `beba7a3c…` / Scores SHA256 `d7b05e81…` (blind, returns 미접근 상태에서 채점 동결).

## Concerns raised (≥3) + classification

### C1 [ACCEPT] IC→PORT_t 전이 벽 — 이 파일럿은 자본-등급 알파가 아니다
본 파일럿이 측정한 것 = **점수와 forward 12M 초과수익의 횡단 rank 상관(Spearman)**. 시스템의 반복
교훈(measurement-graduation §3, 16/16 admission FAIL)은 rank-IC/상관이 top-N long-only 실현
portfolio-alpha t로 전이되지 않는 경우가 구조적 다수라는 것. complexity ρ=-0.316(perm p=0.035)은
**screening-tier 신호 whisper이지 PORT_t 2.95 통과를 함의하지 않는다.** 파일럿은 월간 리밸 포트폴리오가
아니고 canonical_screen_bt를 돌리지 않았으므로 (사전등록대로) canonical_port_t 미진입.
→ **처리**: alpha_package.canonical_port_t_nw_lag3 = null + 사유 기록. 어떤 게이트 주장도 금지(사전등록 상한
준수). 확장 설계에 canonical_screen_bt 월간 패널 의무 명시.

### C2 [PARTIAL] 채점자 = 나 자신(주관적 complexity) — 기전 모호성
complexity 1-5는 in-context 주관 판정. "악재 난독화"(Li 2008 가설)를 잡은 것인지, 아니면 내 complexity
평가가 표-덤핑/자회사 나열/법률체 = 특정 disclosure 유형/품질을 프록시한 것인지 파일럿으로 분리 불가.
**근거 강화**: (a) complexity는 Size와 무상관(cor=+0.046) → 단순 size 프록시 아님. (b) LARGE/MID/SMALL
3개 tier 전부 음(-0.475/-0.180/-0.242) → tier 아티팩트 아님. (c) 3개 vintage bin 전부 음 → 시대 아티팩트
아님. 그러나 (d) 주관 채점의 기전 귀속은 미해결.
→ **처리**: 확장 시 **객관적 가독성 지표(평균 문장길이·Fog 등가·표밀도·명사화율)로 complexity 대체**를
1급 배선. 학술 근거: Li (2008) "Annual report readability, current earnings, and earnings persistence" JAE.
주관 LLM 채점은 tone/uncertainty(lexicon-hard)에만 보조 사용.

### C3 [ACCEPT] 다중검정 — complexity p=0.035는 미보정
1차 축 4개 검정 중 최소값. Bonferroni×4 → p≈0.14 (미유의). 사전등록이 **파일럿은 multiple-testing
graduation gate 부적용**(directional triage)을 명시했으므로 verdict 카테고리(PROMISING_SCALE_UP)는 불변
이나, **강도는 "confirmed"가 아니라 "promising(weak-tier)"**. 확장은 Bonferroni-보정 α에서 검정력을
설계해야 함(아래 검정력 계산).
→ **처리**: verdict = PROMISING_SCALE_UP로 유지하되 라벨에 weak-tier + screening-tier 명기.

### C4 [REBUTTAL] tone 가설 부호가 반대로 나왔다 — 합리화 아님, 정직 기각
사전등록 tone 가설 = POSITIVE. 실측 ρ(excess)=-0.232, ρ(total)=-0.293(총수익 90%CI excl 0),
perm p=0.128. **가설 부호 기각**(경영진 낙관 과잉 → 낮은 후행수익, overoptimism-reversal). 이는
self-rationalization("미미/관행"으로 뭉개기)이 아니라 사전공약 부호가 틀렸음을 그대로 보고하는 것.
근거: Loughran-McDonald(2011) 낙관 lexicon의 시장별 부호 불안정성 + KR 소형·성장주 hype 반전.
정량 3축: (i) ρ 부호 일관(excess/total 둘 다 음) (ii) drop-max 후 강화(-0.259) (iii) perm p=0.128(약).
→ **처리**: tone = 2차 lead. 확장 시 **부호를 뒤집어(낙관↑ = 악재)** 재검정. 단독 verdict 근거 아님.

### C5 [ACCEPT] 발췌 품질 — 3/45(6.7%)가 거버넌스 boilerplate 오추출
D005/D055/D059가 MD&A 본문 대신 이사회/감사 표를 추출(anchor가 오작동). low_content 3건 제외 시
complexity **강화**(-0.316→-0.358, CI[-0.559,-0.144]) → 결론 방향 불변(오히려 노이즈 제거).
→ **처리**: 확장 시 섹션 anchor 보강(제목 계층 파싱 + '개요/재무상태 및 영업실적' 이중 확인).

### C6 [ACCEPT] 블라인드 준수 자가점검
채점(scores.csv, SHA256 d7b05e81)은 04_analysis.R(수익 최초 접근)보다 **먼저** 동결. 채점 시 로드한
파일 = excerpts.json(텍스트만). 수익/Size는 채점 후 병합. rubric·표본추첨 hash(beba7a3c)는 선택·채점
전 동결. → 위반 없음.

## Self-rationalization auto-detection
"미미/관행/실무적/보수적이면 OK/대부분 동일" 사용 여부 자가검색 → **미사용**. tone 부호 반전을 뭉개지 않고
명시 기각(C4). complexity를 과대주장하지 않고 screening-tier로 강등(C1, C3).

## Q-Lead escalate trigger 점검
HIGH severity ≥5? → 아니오(파일럿, 자본 미영향). AX axiom hard FAIL ≥3? → 아니오. PIT C1(lockbox/
lookahead) 위반? → 아니오(forward window = rcept 익월부터 12M, 사전등록 clean PIT). **escalate 불요.**

## AX-008 Verification Triangulation (3-source 2/3)
- self-adversarial(본 노트): PASS(방법론 결함 6건 분류·보완, verdict 방향 유지)
- Forge: N/A(파일럿, forge 미호출 — 자본 게이트 미진입이 사전등록 상한)
- Architect: N/A
→ 2/3 미충족이나 **파일럿은 admission 대상 아님**(canonical/forge 미진입이 설계). self-adversarial 단독으로
directional triage 결론에 충분. 확장(자본 후보화) 시 AX-008 full 적용 의무.
