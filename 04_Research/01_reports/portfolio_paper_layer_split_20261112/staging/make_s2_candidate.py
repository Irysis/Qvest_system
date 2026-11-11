# -*- coding: utf-8 -*-
"""판 2 구축 S2 — 시드 엔진 RP_AUTO_2002_06975/engine.R 의 스케줄 수리 후보판(운영 파일은 건드리지 않는다).
사용: python -X utf8 make_s2_candidate.py <저장소 루트> <후보판을 둘 폴더>
- 치환 대상이 정확히 한 곳인지 단정 · 줄끝 보존 · 원본 md5 가 기대값과 다르면 멈춤.
무엇을 고치나:
  ① 갱신 격자 앵커 이전의 월말을 스케줄에서 뺀다(시작일이 앵커보다 앞이면 max(integer(0)) = -Inf 로 멈추던 것)
  ② 달 인덱스 k 를 달력 월 기준으로(2005-01 = 1) — 시작일이 달라져도 같은 달의 시드가 같다
기본 시작(2005-01-01)에서는 스케줄이 비트 동일해야 한다(sched_test.R 가 실제 달력으로 확인)."""
import hashlib, os, sys

ROOT, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
REL = '04_Research/strategies/RP_AUTO_2002_06975/'
EXPECT = {'engine.R': '6b6a8e1a144b4b316c28628b0de7f95d'}

def load(name):
    raw = open(os.path.join(ROOT, REL, name), 'rb').read()
    md5 = hashlib.md5(raw).hexdigest()
    if name in EXPECT and md5 != EXPECT[name]:
        raise SystemExit('원본 md5 불일치 %s: %s' % (name, md5))
    nl = '\r\n' if b'\r\n' in raw else '\n'
    return raw.decode('utf-8').replace('\r\n', '\n'), nl, md5

def save(name, text, nl):
    b = text.replace('\n', nl).encode('utf-8')
    open(os.path.join(OUT, name), 'wb').write(b)
    return hashlib.md5(b).hexdigest()

def once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        raise SystemExit('치환 대상이 %d곳이다(1곳이어야 한다): %s' % (n, what))
    return text.replace(old, new, 1)

# ── engine.R ─────────────────────────────────────────────────────────────────
t, nl, m0 = load('engine.R')

a = '.SEED_BASE <- 20020697L                              # ★changed(6) 시드 = 논문 번호(임의 상수) + 월 인덱스\n'
t = once(t, a, a +
         '.K_REF_MI  <- 2005L * 12L + 1L                       # ★changed(17) 월 인덱스 k 의 기준 달 = 2005-01(k = 1) — 시작일이 달라져도 같은 달은 같은 시드\n',
         '.SEED_BASE 상수')

a = '# 6. 스케줄 — 월말 시그널 · 5영업일 갱신 격자 · 학습창 [u−1004, u−5]  ★changed(3)(5)\n'
t = once(t, a, '# 6. 스케줄 — 월말 시그널 · 5영업일 갱신 격자 · 학습창 [u−1004, u−5]  ★changed(3)(5)(17)\n', '6절 제목')

a = ('.grid5 <- .CAL[di >= .anchor_i & ((di - .anchor_i) %% .UPD_EVERY) == 0L, di]\n'
     '.SCH <- .me[, {\n')
t = once(t, a,
         '.grid5 <- .CAL[di >= .anchor_i & ((di - .anchor_i) %% .UPD_EVERY) == 0L, di]\n'
         '## ★changed(17) (2026-11-11) 갱신 격자 앵커 이전의 월말 = 갱신점이 없다 → 스케줄 밖. 시작일이 앵커보다 앞이면(측정 축 시작 2000-01-01 을 받을 때)\n'
         '##   종전에는 아래 max(integer(0)) 이 -Inf 가 되어 묶음 사이 형 불일치로 멈췄다. 기본 시작(2005-01-01)에서는 해당 달이 없다(결과 불변).\n'
         '.n_pre_anchor <- .me[di < .anchor_i, .N]\n'
         '.me <- .me[di >= .anchor_i]\n'
         '.SCH <- .me[, {\n', '스케줄 조립 머리')

a = '.SCH[, k := seq_len(.N)]\n'
t = once(t, a,
         '## ★changed(17) 월 인덱스 k = 달력 월 기준(2005-01 = 1 · 그 앞 달은 0 이하). 순번(seq_len)이면 시작일이 달라질 때 같은 달의 시드가 밀려\n'
         '##   같은 입력을 다른 시드로 다시 학습한다. 달력 기준이면 겹치는 달의 시드 · 예측 캐시 키가 시작일과 무관하게 같다.\n'
         '.SCH[, k := MI - .K_REF_MI + 1L]\n', 'k 순번')

a = ('cat(sprintf("%s 스케줄 %d개월(%s ~ %s · 학습창 미달로 제외 %d) · 갱신 격자 앵커 %s · 첫 달: 갱신 %s · 학습집합 %s ~ %s\\n",\n'
     '            .TAG, nrow(.SCH), as.character(min(.SCH$Date)), as.character(max(.SCH$Date)), .n_sched_all - nrow(.SCH),\n')
t = once(t, a,
         'cat(sprintf("%s 스케줄 %d개월(%s ~ %s · 학습창 미달로 제외 %d · 앵커 전 제외 %d) · 갱신 격자 앵커 %s · 첫 달: 갱신 %s · 학습집합 %s ~ %s\\n",\n'
         '            .TAG, nrow(.SCH), as.character(min(.SCH$Date)), as.character(max(.SCH$Date)), .n_sched_all - nrow(.SCH), .n_pre_anchor,\n',
         '스케줄 로그')
m1 = save('engine.R', t, nl)
print('engine.R %s -> %s (줄끝 %s)' % (m0, m1, 'CRLF' if nl == '\r\n' else 'LF'))

# ── FIDELITY.json — 변경 신고 (17) · 창 · 산출 행 서술 · 개정 기록(서식 보존: 원문 치환만) ─────────────
f, fnl, f0 = load('FIDELITY.json')
C17 = ('(17) [스케줄 — 측정 시작일 전달 · 2026-11-11 개정(상설 자격 판 2 구축 S2 · 감사 밖 수리)] '
       'ⓐ 시작일: 엔진은 러너가 넘기는 측정 시작일(.RP_START_DATE)을 쓰고 없으면 2005-01-01 이다(10-13 측정 축 전환 패치 — '
       '04_Research/01_reports/l1_prescription_redesign_20261013/mc1_integration/engine_start_patch_manifest.json). 11-11 부터 셀 경로(rf_cell_engine.R)도 같은 값을 넘긴다. '
       'ⓑ 갱신 격자 앵커(2001-01-01 이후 첫 거래일) 이전의 월말은 갱신점이 없어 스케줄에서 뺀다 — 종전에는 시작일이 앵커보다 앞이면 스케줄 조립에서 멈췄다(max(integer(0)) = -Inf · 묶음 사이 형 불일치). '
       '기본 시작에서는 해당 달이 없어 스케줄이 비트 동일하다(실제 달력 대조 262개월). '
       'ⓒ 학습창이 격자(2000-06-01~) 안에 서지 않는 달(smin_i < 1)은 종전대로 뺀다 → 축 시작 2000-01-01 을 받으면 첫 시그널 = 2004-07 월말(268개월 · 앞당겨진 달 6 · 앵커 전 제외 7). '
       'ⓓ 월 인덱스 k = 달력 월 기준(2005-01 = 1 · 그 앞 달은 0 이하): 순번이면 시작일이 달라질 때 같은 달의 시드(20020697 + k)가 밀려 같은 입력을 다른 시드로 다시 학습한다 — '
       '달력 기준이면 2005-01 이후 달의 학습창 · 시드 · 예측 캐시 키가 시작일과 무관하게 같다(대조 확인). '
       '격자 시작 · 앵커 · 학습창 길이 · 모델 · 특성 · 조립은 손대지 않았다. 파이썬 합성 양성 대조의 시드는 스케줄 첫 달의 시드 + 7 이라 시작일을 받으면 달라진다(문턱 0.8 불변).')
f = once(f, '— 러너 규약)."\n  ],', '— 러너 규약).",\n    "' + C17 + '"\n  ],', 'changed 마지막 항목')
f = once(f, '첫 시그널 2005-01 월말(고정 축)',
         '첫 시그널 = 측정 시작일 이후 학습창이 격자 안에 서는 첫 월말(시작일 미전달 = 2005-01 월말 · 축 시작 2000-01-01 전달 = 2004-07 월말 — changed(17))', '창·워밍업 첫 시그널')
f = once(f, '"rows": "2005-01 이후 완결 달력월의 마지막 거래일 1행 집합',
         '"rows": "측정 시작일(.RP_START_DATE · 없으면 2005-01-01) 이후 학습창이 서는 완결 달력월의 마지막 거래일 1행 집합(changed(17))', 'engine_contract.rows')
f = once(f, '줄로 확인할 것."\n  },\n',
         '줄로 확인할 것.",\n'
         '    "patch_20261111": "상설 자격 판 2(P1S02) 구축 S2 — 스케줄 수리(changed(17): 앵커 전 달 제외 · 월 인덱스 달력 기준). 감사(3판 · 2026-09-13) 뒤의 수리이고 감사 대상 축의 서술은 바꾸지 않았다. '
         '검증 = 6절만 떼어 실제 거래일 달력으로 구판과 대조(기본 시작 262개월 비트 동일 · 2000-01-01 에서 구판 멈춤 재현 · 후보판 268개월 · 겹치는 262개월 창 · 번호 · 시드 동일 · PIT 창 불변식). '
         '엔진 md5 ' + m0 + ' → ' + m1 + '. 기록 = 04_Research/01_reports/portfolio_paper_layer_split_20261112/BUILD_EDITION2.md S2."\n'
         '  },\n', 'revision 끝')
f1 = save('FIDELITY.json', f, fnl)
import json
json.loads(f)   # 구문 확인
print('FIDELITY.json %s -> %s' % (f0, f1))
