# -*- coding: utf-8 -*-
"""직접 포트폴리오 엔진 분류표 생성 — 4분법(도훈 결정 PAPER-CONTRIBUTION-LAYER-TAXONOMY-20261111).

입력: data/engine_static.json(코드 구조) · data/engine_counts_merged.json(신호일당 종목 개수) + 아래 FACTS(부품별 판독).
FACTS 의 근거 = 엔진 코드(비중 대입 줄 · 최적화 · 추정 호출) + FIDELITY.json 신고(kept · paper_original_form · paper_steps · portfolio_spec)
               + 인계 기록의 라우터 프로그램. 성과 수치(등급 · PORT_t · 수익 · 위기 방어)는 읽지 않았다.
표기: P = 논문 기여(논문이 정의한 고유 방법) · S = 표준(교과서 · 기존 카탈로그와 같음) · X = 외생(논문이 주어진 것으로 둠 · 엔진이 대체) · - = 없음
"""
import json, os, csv, sys

HERE = os.path.dirname(os.path.abspath(__file__)); REP = os.path.dirname(HERE)
st = {r['dir']: r for r in json.load(open(os.path.join(REP, 'data', 'engine_static.json'), encoding='utf-8')) if r.get('has_engine')}
cnt = json.load(open(os.path.join(REP, 'data', 'engine_counts_merged.json'), encoding='utf-8'))
# 판 1 상설 입구 건식 스캔(쓰기 없음 · 성과 수치 안 읽음) — data/p1s01_scan_dryrun.json
scan = {r['dir']: r for r in json.load(open(os.path.join(REP, 'data', 'p1s01_scan_dryrun.json'), encoding='utf-8'))['rows']}
REASON_KO = {'no_handoff': '인계 기록 없음', 'not_routed': '수익 프로그램 인계 아님', 'audit_not_passed': '감사 미통과', 'implementation_suspect': '구현 의심',
             'dynamic_sign': '동적 부호', 'combination': '결합', 'long_leg_absent': '롱 레그 없음', 'no_engine': '엔진 없음'}

def entry_cell(d):
    r = scan.get(d)
    if not r: return '판독 없음'
    if r.get('status') in ('known', 'new') and not (r.get('reasons') or ''): return '**통과**'
    return '제외 — ' + ' · '.join(REASON_KO.get(x, x) for x in str(r.get('reasons') or '').split(';') if x)

# dir · 논문 키 · 짧은 제목 · ①기대수익 예측 · ②위험 예측 · ③구성 규칙 · ④노출 규칙 · 주 기여 · 목적지 · 구 3분류 · 비중 줄 · 비고 · MC3 손 판독(없으면 자동)
F = [
 ("RP_AUTO_0806_2606", "0806.2606", "신경망 순위 예측(ANN)", ("P", "ANN 분기 순위 예측"), ("-", ""), ("S", "누적 데실 EW · 분기 보유 트랜치 3개 평균"), ("-", ""),
  "기대수익 예측", "상설 자격 판", "B", "460", "", None),
 ("RP_AUTO_1403_8125", "1403.8125", "낙폭 · 회복 기반 모멘텀 순위", ("P", "MDD · 회복 · 누적(CM) 순위"), ("-", ""), ("S", "데실 EW · 6개월 중첩 코호트(1/K)"), ("-", ""),
  "기대수익 예측", "상설 자격 판(점수 출력 추가)", "B", "239", "L1 기록의 최신 산출은 강화 칸(top_n_long)이라 엔진 원 출력 개수는 미확인", "미확인 — 구조상 넓음(데실 × 6 코호트)"),
 ("RP_AUTO_1505_00328", "1505.00328", "반전(통합 패널)", ("P", "과거 J개월 수익 반전 순위"), ("-", ""), ("S", "데실 EW"), ("-", ""),
  "기대수익 예측", "상설 자격 판", "B", "209-210", "", None),
 ("RP_AUTO_1707_05552", "1707.05552", "횡단면 반전(CSCON)", ("P", "직전 J개월 평균수익 순위"), ("-", ""), ("S", "데실 EW · 1개월 스킵"), ("-", ""),
  "기대수익 예측", "상설 자격 판", "B", "151", "", None),
 ("RP_AUTO_2001_04185", "2001.04185", "팩터 크라우딩(가설적 투자자)", ("S", "12-1 모멘텀 순위(표준 팩터)"), ("-", ""), ("P", "신호 EMA 감속 포지션(식 1) — 전 종목 신호 비례"), ("-", ""),
  "구성 규칙(거래 감속)", "리밸 블록 재료(카탈로그 보류)", "A", "188", "논문 본체는 크라우딩 진단 · 감속 규칙은 직전 포지션 상태가 필요해 ctx 로 계산 불가", None),
 ("RP_AUTO_2002_06975", "2002.06975", "DNN 횡단면 예측", ("P", "DNN 5일 수익 순위 예측"), ("-", ""), ("S", "5분위 EW"), ("-", ""),
  "기대수익 예측", "상설 자격 판(P1S01 시드)", "B", "754", "", None),
 ("RP_AUTO_2003_02515", "2003.02515", "시변 신경망(온라인 조기중단)", ("P", "NN 앙상블 다음 달 수익 예측"), ("-", ""), ("S", "십분위 EW"), ("-", ""),
  "기대수익 예측", "상설 자격 판", "B", "713", "", None),
 ("RP_AUTO_2006_04639", "2006.04639", "동적 네트워크 위험 요인", ("P", "연결성 요인 로딩 β 순위"), ("-", ""), ("S", "5분위 시총가중"), ("-", ""),
  "기대수익 예측", "상설 자격 판(점수 출력 추가)", "B", "430-432", "", None),
 ("RP_AUTO_2011_05381", "2011.05381", "디리클레 정책 강화학습", ("P", "정책 점수 x'θ(REINFORCE)"), ("-", ""), ("S", "softmax(점수) — lean:softmax_tilt 와 같은 꼴 · 풀 = 무작위 100종"), ("-", ""),
  "한 모형 → 내부 점수", "상설 자격 판(점수 패널 = x'θ)", "C", "394-407", "다특성 정책 가중 자체는 ctx 에 특성 패널이 없어 카탈로그 보류", None),
 ("RP_AUTO_2202_05702", "2202.05702", "재무 기반 ML(종목별 RF)", ("P", "종목별 RF 예측 상대수익"), ("-", ""), ("S", "상위 1/3 EW · 분기"), ("-", ""),
  "기대수익 예측", "상설 자격 판", "B", "561", "", None),
 ("RP_AUTO_2302_10175", "2302.10175", "시공간 모멘텀(신경망 포지션)", ("P", "NN 포지션 X∈[−1,1]"), ("-", ""), ("S", "역변동성 스케일(1/N · σ_tgt/σ_i)"), ("S", "포트폴리오 변동성 표적 15%"),
  "한 모형 → 내부 점수", "결합형 후보(고정 패널 46종 — 점수로도 폭 부족)", "C", "516", "패널이 고정이라 전 종목으로 넓히면 논문 그대로가 아님", "never_met 유력(구 축 개수 · 고정 패널)"),
 ("RP_AUTO_2404_08129", "2404.08129", "단일 비선형 팩터", ("P", "모형 예측수익"), ("-", ""), ("S", "5분위 EW · 반년 형성"), ("-", ""),
  "기대수익 예측", "상설 자격 판(점수 출력 추가)", "B", "381", "", None),
 ("RP_AUTO_2505_16336", "2505.16336", "무형투자 팩터", ("P", "INTAN 특성(산업-연도 회귀 잔차)"), ("-", ""), ("S", "2×3 정렬 · 코너 EW"), ("-", ""),
  "기대수익 예측", "상설 자격 판(점수 출력 추가)", "B", "404", "", None),
 ("RP_AUTO_2505_20608", "2505.20608", "참조 의존(CGO) 이중정렬", ("P", "CGO × 위험 대리 순위"), ("-", ""), ("S", "5×5 시총가중"), ("-", ""),
  "기대수익 예측", "상설 자격 판", "B", "405", "", None),
 ("RP_AUTO_2511_12129", "2511.12129", "ML 종목 추천 + 최소분산", ("P", "섹터별 ML 예측(MSE 최소 모형)"), ("S", "1년 일간 표본 공분산"), ("S", "섹터별 상위 20% · 최소분산(5% 상한)"), ("-", ""),
  "기대수익 예측", "상설 자격 판", "B", "622-629", "최소분산 = 기존 lean:minvar", None),
 ("RP_AUTO_2511_12490", "2511.12490", "드리프트 국면 게이트 팩터", ("P", "EDGE 점수 × 종목별 상승일 비율 게이트"), ("-", ""), ("S", "z 부호 버킷 · 사이드 정규화"), ("S", "노출 스칼라(목표 변동성)"),
  "기대수익 예측", "상설 자격 판(점수 출력 추가)", "B", "372", "게이트 때문에 활성 종목이 적다", "never_met 유력(구 축 개수 · 새 축 미확인)"),
 ("RP_AUTO_2608_24703", "2608.24703", "리드-래그 군집 타이밍", ("P", "군집 내 리드-래그 점수(리더 선정)"), ("-", ""), ("S", "리더 바스켓 EW"), ("P", "리더 EWMA 부호로 롱/숏 전환"),
  "노출 규칙(+ 리더 점수)", "방어 프로그램 재료", "노출형", "270", "롱 레그 없는 신호일 109 — 인계되면 long_leg_absent 대상", "폭은 통과 유력(구 축 개수 · 최대 87) — 단 롱 레그 없는 신호일 109"),
 ("RP_AUTO_2608_27076", "2608.27076", "교차 국면 앙상블(XGBoost+TabNet)", ("P", "확률 순위 앙상블"), ("-", ""), ("S", "상위 6 롱/숏 EW"), ("-", ""),
  "기대수익 예측", "상설 자격 판", "B", "588-589", "", None),
 ("RP_AUTO_CLEAN_1109_3488", "1109.3488", "다목적 진화 제약 구성(MOEA)", ("X", "다요인 점수(논문 입력 · 엔진 대체)"), ("-", ""), ("P", "NSGA-II → SPEA2 다목적 제약 구성(턴오버 · 보유 한도 · 종목 수 · 스타일)"), ("-", ""),
  "구성 규칙", "비중 카탈로그 보류(직전 비중 · 확률 탐색)", "A", "817", "기존 qepm:Genetic(진화 가족 · 탐침 실패)과 가족이 겹친다", "개수 자료 없음(레인 산출 없음)"),
 ("RP_AUTO_CLEAN_1505_00328", "1505.00328", "반전(거래소 분리)", ("P", "과거 J개월 수익 반전 순위"), ("-", ""), ("S", "데실 EW"), ("-", ""),
  "기대수익 예측", "상설 자격 판(점수 출력 추가)", "B", "147-148", "", None),
 ("RP_AUTO_CLEAN_1610_01338", "1610.01338", "저가주 단일 요인 정렬", ("P", "저가 구간 한정 + 요인 정렬"), ("-", ""), ("S", "하위 50% EW · 연 1회"), ("-", ""),
  "기대수익 예측", "상설 자격 판", "B", "175", "", None),
 ("RP_AUTO_CLEAN_1801_01777", "1801.01777", "딥러닝 횡단면 예측", ("P", "DNN 다음 달 수익 순위 예측"), ("-", ""), ("S", "5분위 EW"), ("-", ""),
  "기대수익 예측", "상설 자격 판(점수 출력 추가)", "B", "540", "", None),
 ("RP_AUTO_CLEAN_1810_08384", "1810.08384", "포트폴리오 구성이 성과를 만든다", ("S", "모멘텀 순위(표준)"), ("P", "상관행렬 상위 k 고유모드 정제 공분산"), ("P", "마코위츠 x ∝ C⁻¹p"), ("-", ""),
  "위험 예측 + 구성 규칙", "이미 등재(paper:EigenCleanMarkowitz)", "A", "197", "", None),
 ("RP_AUTO_CLEAN_1908_01112", "1908.01112", "중기 예측(Mid-ARMA + HMM)", ("P", "예측 누적수익 Chat"), ("P", "예측 경로 로그수익의 공분산(식 28)"), ("S", "시장상관 상위 50 + Chat 문턱 · 롱온리 최대 샤프"), ("-", ""),
  "기대수익 예측", "상설 자격 판(점수 = Chat 출력 추가)", "C", "438-457", "최대 샤프 = 기존 qepm:MVO 계열 · 예측 경로 공분산은 엔진 안에서만 계산 가능", None),
 ("RP_AUTO_CLEAN_2202_10721", "2202.10721", "왜도 위험 패리티", ("-", "종목 선정 없음(고정 슬리브)"), ("P", "2성분 가우스 혼합(점프 국면) · 정상 국면 공분산 필터"), ("P", "혼합분포 99% ES 위험 예산"), ("-", ""),
  "구성 규칙 + 위험 예측", "비중 카탈로그 새 후보", "A", "487-492", "", None),
 ("RP_AUTO_CLEAN_2210_12462", "2210.12462", "딥 멀티팩터(계층 중성화)", ("P", "딥팩터(ICIR 최대화)"), ("-", ""), ("S", "상위 10% EW"), ("-", ""),
  "기대수익 예측", "상설 자격 판(점수 출력 추가)", "B", "395", "상위 10% 라 유니버스가 넓어지면 보유도 늘어난다", "미확정(구 축 20~35 · 새 축 미측정)"),
 ("RP_AUTO_CLEAN_2305_16364", "2305.16364", "엔드투엔드 액티브(E2EAI)", ("P", "심층팩터 · attention 점수"), ("-", ""), ("P", "2단 softmax 자동 선정 · 비중(학습 정책)"), ("-", ""),
  "한 모형 → 내부 점수", "상설 자격 판(softmax 전 점수 출력 추가) · 없으면 결합형", "C", "581", "", "never_met 유력(구 축 개수 · 엔진이 25종 이하로 낸다)"),
 ("RP_AUTO_CLEAN_2411_08864", "2411.08864", "등방 상관 모형", ("X", "α(논문이 주어진 것으로 둠)"), ("P", "등방 상관 Σ · ρ 추정기(실효 자유도 N*)"), ("S", "폐형 평균-분산 해"), ("-", ""),
  "위험 예측", "공분산 추정기 축 새 후보", "A", "144", "", None),
 ("RP_AUTO_CLEAN_2412_12350", "2412.12350", "다요인 시장중립(Lasso)", ("P", "Lasso 기대수익 순위"), ("-", ""), ("S", "상위 40/하위 40 · 최소분산 베타중립(세 구성 중 하나)"), ("-", ""),
  "기대수익 예측", "상설 자격 판(점수 출력 추가)", "B", "259-333", "", None),
 ("RP_AUTO_CLEAN_2601_04602", "2601.04602", "상관 예측(THGNN) 통계적 차익", ("P", "군집 내 역추세 신호 + ML 필터"), ("P", "10일 선행 쌍별 상관 예측 → 군집"), ("S", "군집 내 롱숏 바스켓"), ("-", ""),
  "한 모형(예측 + 위험 예측)", "결합형(논문 구성 그대로만)", "C", "(조립 함수)", "롱 레그 없는 신호일 152 — 인계되면 long_leg_absent 대상 · 상관 예측은 추정기 축 후보지만 torch 모델이라 보류", "판독 불가(롱 레그 없는 신호일 152)"),
 ("RP_AUTO_CLEAN_2601_10732", "2601.10732", "국면 의존 팩터 선행(Granger)", ("-", "종목 예측 없음"), ("-", ""), ("S", "FF 2×3 스프레드 구성"), ("P", "위기 국면 게이트 + HML 선행 부호 · 비위기 무포지션"),
  "노출 규칙", "방어 프로그램 재료(미분류 보류 중)", "노출형", "353-356", "논문 스스로 수익 없음 · 위험 관리 정보라고 결론", "타이밍형 — 표준 구성 대상 아님"),
 ("RP_AUTO_CLEAN_2604_16773", "2604.16773", "위상 위험 패리티(TRP)", ("X", "부호 신호 s(논문 입력)"), ("S", "표본 상관 → 상관거리"), ("P", "최소 신장 나무 경로곱 위상 인자"), ("-", ""),
  "구성 규칙", "비중 카탈로그 새 후보", "A", "321", "", None),
 ("RP_AUTO_COMBO_combo_1403_8125_2301_091", "combo", "결합 엔진(1403.8125 + 2301.09173 + 2404.08129)", ("P", "결합 신호"), ("-", ""), ("S", "롱온리 ≤ 25"), ("-", ""),
  "결합", "범위 밖(상설 입구 combination)", "-", "493-500", "", "대상 아님(결합)"),
]

COUNT_UNRELIABLE = {'RP_AUTO_1403_8125', 'RP_AUTO_COMBO_combo_1403_8125_2301_091'}

def q(v):
    return "–" if not v else "%s/%s/%s" % tuple(str(int(x)) if float(x) == int(x) else str(x) for x in v)

def count_cell(c):
    """신호일당 종목 수 — 출처 우선순위: 기저 캐시(셀 엔진이 읽는 패널) > 레인 보유(새 축) > 레인 · L1 보유(구 축)"""
    if c.get('cache'):
        k = c['cache']
        return "캐시 %s (신호일 %d · 월말 %d)" % (q(k['names']), k['nD'], k['n_me']), 'cache', k
    if c.get('lane'):
        l = c['lane']; ax = '새 축' if str(l.get('axis', '')).startswith('all_hyg') else '구 축'
        return "레인 보유 %s (%s · 신호일 %d)" % (q(l['names']), ax, l['nD']), 'lane_' + ('new' if ax == '새 축' else 'old'), l
    if c.get('l1'):
        o = c['l1']
        return "레인 보유 %s (구 축 · 신호일 %d)" % (q(o['names']), o['nD']), 'l1_old', o
    return "자료 없음", 'none', None

def mc3_auto(out, src, k):
    if out != 'PORTFOLIO':
        if src == 'cache':
            return "점수 패널 사용 — 통과(월말 신호일 %d 중 폭 ≥ 50 인 날 %d)" % (k['n_me'], k['n_me_ge50'])
        return "점수 패널 사용 — 폭 미확인(패널 = 적격 전 종목)"
    if src == 'cache':
        if k['n_me'] == 0 or (k['me'][2] is not None and k['me'][2] < 50):
            return "never_met 확정적(월말 신호일 %d · 그날 최대 폭 %s < 50)" % (k['n_me'], str(k['me'][2]))
        return "통과(월말 신호일 %d 중 폭 ≥ 50 인 날 %d) — 단 비중을 점수로 읽는다" % (k['n_me'], k['n_me_ge50'])
    if src in ('lane_new', 'lane_old', 'l1_old'):
        mx = k['names'][2]
        tag = '새 축' if src == 'lane_new' else '구 축 개수'
        return ("never_met 유력(%s · 최대 %s < 50)" % (tag, mx)) if mx < 50 else ("통과 유력(%s · 최대 %s) — 단 비중을 점수로 읽는다" % (tag, mx))
    return "개수 자료 없음"

# 주 기여 층(1개) · 부 기여(다른 논문 기여 층) · 한 모형이 다 하는가 · 내부 종목별 값(점수로 내보낼 수 있는가)
#   주 기여 = 논문 기여(P) 층이 여럿일 때 논문의 중심(FIDELITY kept 의 '기전' 서술 · 논문 표제) 하나. 결정문 경계 3: 한 모형이 다 하면 내부 값을 점수로 내보내 예측으로 잰다.
ER, RK, CN, EX = "기대수익 예측", "위험 예측", "구성 규칙", "노출 규칙"
X = {
 "RP_AUTO_0806_2606": (ER, [], False, "있음 — 이미 점수로 낸다(ANN 예측)"),
 "RP_AUTO_1403_8125": (ER, [], False, "있음 — 출력 추가(순위 지표 C−MDD)"),
 "RP_AUTO_1505_00328": (ER, [], False, "있음 — 이미 낸다(−과거 수익)"),
 "RP_AUTO_1707_05552": (ER, [], False, "있음 — 이미 낸다"),
 "RP_AUTO_2001_04185": (CN, [], False, "있음 — 이미 낸다(감속 포지션 · 원 신호는 표준 모멘텀 순위라 예측 기여 아님)"),
 "RP_AUTO_2002_06975": (ER, [], False, "있음 — 이미 낸다(DNN 예측)"),
 "RP_AUTO_2003_02515": (ER, [], False, "있음 — 이미 낸다(앙상블 예측)"),
 "RP_AUTO_2006_04639": (ER, [], False, "있음 — 출력 추가(요인 로딩 β)"),
 "RP_AUTO_2011_05381": (ER, [], True, "있음 — 이미 낸다(정책 점수 x'θ · 적격 전 종목)"),
 "RP_AUTO_2202_05702": (ER, [], False, "있음 — 이미 낸다(예측 상대수익)"),
 "RP_AUTO_2302_10175": (ER, [], True, "있음 — 출력 추가(포지션 값 X) · 단 고정 패널 46종이라 폭이 모자란다"),
 "RP_AUTO_2404_08129": (ER, [], False, "있음 — 출력 추가(모형 예측수익)"),
 "RP_AUTO_2505_16336": (ER, [], False, "있음 — 출력 추가(INTAN 특성)"),
 "RP_AUTO_2505_20608": (ER, [], False, "있음 — 이미 낸다"),
 "RP_AUTO_2511_12129": (ER, [], False, "있음 — 이미 낸다(ML 예측)"),
 "RP_AUTO_2511_12490": (ER, [], False, "있음 — 출력 추가(EDGE 점수)"),
 "RP_AUTO_2608_24703": (EX, [ER], False, "노출 신호는 시장 단위 값(종목별 아님) · 리더 점수는 종목별(출력 추가 가능)"),
 "RP_AUTO_2608_27076": (ER, [], False, "있음 — 이미 낸다(확률 순위)"),
 "RP_AUTO_CLEAN_1109_3488": (CN, [], False, "없음 — 점수는 외생 입력"),
 "RP_AUTO_CLEAN_1505_00328": (ER, [], False, "있음 — 출력 추가(−과거 수익)"),
 "RP_AUTO_CLEAN_1610_01338": (ER, [], False, "있음 — 이미 낸다"),
 "RP_AUTO_CLEAN_1801_01777": (ER, [], False, "있음 — 출력 추가(DNN 예측점수)"),
 "RP_AUTO_CLEAN_1810_08384": (CN, [RK], False, "없음 — 신호는 표준 모멘텀 순위"),
 "RP_AUTO_CLEAN_1908_01112": (ER, [RK], False, "있음 — 출력 추가(예측 누적수익 Chat)"),
 "RP_AUTO_CLEAN_2202_10721": (CN, [RK], False, "없음 — 종목별 값 없음(슬리브 사이 배분)"),
 "RP_AUTO_CLEAN_2210_12462": (ER, [], False, "있음 — 출력 추가(딥팩터 점수)"),
 "RP_AUTO_CLEAN_2305_16364": (ER, [CN], True, "있음 — 출력 추가(softmax 전 점수 — 순전파 안)"),
 "RP_AUTO_CLEAN_2411_08864": (RK, [], False, "없음 — α 는 외생 입력"),
 "RP_AUTO_CLEAN_2412_12350": (ER, [], False, "있음 — 출력 추가(Lasso 기대수익)"),
 "RP_AUTO_CLEAN_2601_04602": (RK, [ER], True, "쌍별 예측 상관은 있다(추정기 축 값 · torch) · 종목별 신호는 군집 상대값이라 다른 구성에 못 꽂는다"),
 "RP_AUTO_CLEAN_2601_10732": (EX, [], False, "없음 — 시장 단위 국면 상태뿐"),
 "RP_AUTO_CLEAN_2604_16773": (CN, [], False, "없음 — 부호 신호는 외생 입력"),
 "RP_AUTO_COMBO_combo_1403_8125_2301_091": ("결합", [], False, "대상 아님"),
}

rows = []
for (d, key, title, er, rk, cn, ex, main, dest, old3, wline, note, mc3_hand) in F:
    s = st[d]; c = cnt[d]
    lp, ls, one_model, internal = X[d]
    cell, src, k = count_cell(c)
    if d in COUNT_UNRELIABLE:                      # L1 기록의 최신 산출이 엔진 원 출력이 아니라 강화 칸(top_n_long)인 엔진 — 개수로 쓰지 않는다
        cell, src, k = "자료 없음(남은 산출 = 강화 칸)", 'none', None
    out = s['outputs'].replace('FACTORS+PORTFOLIO', 'PORTFOLIO+FACTORS')
    mc3 = mc3_hand or mc3_auto(s['outputs'], src, k)
    rows.append(dict(engine_dir=d, paper=key, title=title, outputs=out, declared_construction=c.get('cons'), router_program=c.get('prog'),
                     layer_primary=lp, layer_secondary=ls, one_model=one_model, internal_value=internal,
                     expected_return=er[0], expected_return_what=er[1], risk=rk[0], risk_what=rk[1], construction=cn[0], construction_what=cn[1],
                     exposure=ex[0], exposure_what=ex[1], main_contribution=main, destination=dest, old_3class=old3, weight_line=wline,
                     count_source=src, counts=cell, mc3_standard_construction=mc3, p1s01_entry_dryrun=entry_cell(d), note=note))

json.dump(rows, open(os.path.join(REP, 'classification.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
with open(os.path.join(REP, 'classification.csv'), 'w', encoding='utf-8-sig', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader()
    w.writerows([dict(r, layer_secondary=' · '.join(r['layer_secondary'])) for r in rows])

SYM = {'P': '●', 'S': '○', 'X': '외생', '-': '–'}
def short(r): return r['engine_dir'].replace('RP_AUTO_', '')
def cell(sym, what): return SYM[sym] + ((" " + what) if what else "")

# 표 1 — 분류(유형 열 = 주 기여 층 1개 + 부 기여 · 내부 종목별 값)
t1 = ["**표 1 — 분류**", "",
      "| # | 엔진 디렉터리 | 논문 | 산출 | 주 기여 층 | 부 기여 | 한 모형 | 내부 종목별 값(점수로 내보낼 수 있나) | 가는 곳 | 구 3분류 |",
      "|---|---|---|---|---|---|---|---|---|---|"]
for i, r in enumerate(rows, 1):
    t1.append("| %d | `%s` | %s %s | %s | **%s** | %s | %s | %s | %s | %s |" % (
        i, short(r), r['paper'], r['title'], r['outputs'], r['layer_primary'], ' · '.join(r['layer_secondary']) or '–',
        '예' if r['one_model'] else '–', r['internal_value'], r['destination'], r['old_3class']))

# 표 2 — 단계별 근거(추정 단계 = 종목별 데이터로 종목별 값을 만든다 / 규칙 단계 = 값을 받아 비중을 낸다)
t2 = ["**표 2 — 단계별 근거**(비중 줄 = `engine.R` 의 Weight 대입 줄)", "",
      "| # | 엔진 디렉터리 | 추정 단계 ① 기대수익 | 추정 단계 ② 위험 | 규칙 단계 ③ 구성(자르기 · 비중) | 규칙 단계 ④ 노출 | 비중 줄 |",
      "|---|---|---|---|---|---|---|"]
for i, r in enumerate(rows, 1):
    t2.append("| %d | `%s` | %s | %s | %s | %s | %s |" % (
        i, short(r), cell(r['expected_return'], r['expected_return_what']), cell(r['risk'], r['risk_what']),
        cell(r['construction'], r['construction_what']), cell(r['exposure'], r['exposure_what']), r['weight_line']))

# 표 3 — 신호일당 종목 수 · 실효 시작 규칙 · 지금 입구
t3 = ["**표 3 — 신호일당 종목 수와 입구**", "",
      "| # | 엔진 디렉터리 | 신호일당 종목 수(최소/중앙/최대) | 표준 구성에 올리면 실효 시작 규칙은 | 지금 상설 입구(판 1 건식 스캔) |",
      "|---|---|---|---|---|"]
for i, r in enumerate(rows, 1):
    t3.append("| %d | `%s` | %s | %s | %s |" % (i, short(r), r['counts'], r['mc3_standard_construction'], r['p1s01_entry_dryrun']))
open(os.path.join(REP, 'classification_table.md'), 'w', encoding='utf-8').write("\n".join(t1 + [""] + t2 + [""] + t3) + "\n")

from collections import Counter
print('rows', len(rows))
print('outputs', Counter(r['outputs'] for r in rows))
print('layer_primary', Counter(r['layer_primary'] for r in rows))
print('one_model', [short(r) for r in rows if r['one_model']])
print('secondary', [(short(r), r['layer_secondary']) for r in rows if r['layer_secondary']])
print('internal', Counter(r['internal_value'].split(' — ')[0] for r in rows))
print('need_score_output', [short(r) for r in rows if '출력 추가' in r['internal_value'] and r['layer_primary'] == ER])
print('old3', Counter(r['old_3class'] for r in rows))
po = [r for r in rows if r['outputs'] == 'PORTFOLIO']
print('PORTFOLIO-only', len(po))
for r in po: print('  ', r['engine_dir'][8:], '|', r['counts'], '|', r['mc3_standard_construction'])
