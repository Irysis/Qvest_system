## P1S03 판정 일치 기록(DESIGN §8 · 철학 N2 · 판단 C-056 · 변경분 점검 v4 S-3) — T1 판정을 읽기 전에 T0 15 만 본다.
##   ① 같은 자료 판(판 표식 마지막 줄 D2-XF-FILL-RESTORE-20261114 뒤): P1S03 T0 판정 ↔ P1R04 기준 칸 R0 판정(기대 15/15)
##   ② 앞 자료 판(D2 정정 전): P1S03 T0 판정 ↔ P1R03 원 칸 C0 판정 — 양방향(통과 → 통과 · 미달 → 미달)
##   참고 열: 이음매 세션 D2 재측정(인용 폴더 P1R03_factor_family_composites/remeasure_d2_20261114/results — 이 도구는 열지 않는다 ·
##           이음매 세션 통지 11-14 23:4x 의 IS 판정 문장 '원 칸과 IS 판정 15/15 같음 · 바뀐 엔진 없음'을 그대로 옮긴다).
##   입력 = 보는 창 파일만(standing_visible.json · P1R04 evaluation_visible.json · P1R03 evaluation_visible.json). 시험 창 값 없음.
##   출력 = results/t0_agreement.json + 표준 출력 요약. 실행(저장소 루트): python 04_Research/programs/P1_RETURN/P1S03_own_spec_qualification/tools/p1s03_t0_agreement.py
import json, datetime, sys
RD = '04_Research/programs/P1_RETURN/P1S03_own_spec_qualification'
rd = lambda p: json.load(open(p, encoding='utf-8'))
S = rd(RD + '/results/standing_visible.json')
R4 = {r['engine']: r for r in rd('04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/results/evaluation_visible.json')['table'] if r['code'].endswith('_R0')}
R3 = {r['engine']: r for r in rd('04_Research/programs/P1_RETURN/P1R03_factor_family_composites/results/evaluation_visible.json')['table']}
AB = {'accrual': 'FACCR', 'consensus': 'FCONS', 'crowding': 'FCROW', 'defense': 'FDEFE', 'growth': 'FGROW', 'investor_flow': 'FINVE', 'leverage': 'FLEVE',
      'liquidity': 'FLIQU', 'momentum': 'FMOME', 'quality': 'FQUAL', 'regime': 'FREGI', 'risk': 'FRISK', 'technical': 'FTECH', 'value': 'FVALU'}
import re
def t0_key(it):
    e = str(it.get('engine') or '')
    if e in R4: return e                                   # 시드(FVALU)
    e = re.sub(r'_[0-9a-f]{6}$', '', e)                    # 상설 항목 이름 = <엔진 폴더>_<엔진 md5 앞 6>(standing_visible.json)
    if e == 'FC_TOTAL_EW': return 'TOTAL'
    if e.startswith('FC_FAM_') and not e.endswith('_ICW'): return AB.get(e[len('FC_FAM_'):])
    return None                                            # T1(_ICW) · 그 밖 = 이 기록 밖(읽지 않는다)
rows, pend = [], []
for it in S['items']:
    k = t0_key(it)
    if k is None: continue
    if it.get('status') != 'evaluated' or it.get('qualify') is None: pend.append((it['code'], it.get('status'))); continue
    a, b, c = bool(it['qualify']), bool(R4[k]['qualify']), bool(R3[k]['qualify'])
    rows.append({'engine': k, 'p1s03_code': it['code'], 'p1s03_qualify': a, 'p1r04_r0_qualify': b, 'p1r03_c0_qualify': c,
                 'same_as_p1r04_r0': a == b, 'same_as_p1r03_c0': a == c,
                 't_alpha_vis': {'p1s03': it.get('t_alpha_vis'), 'p1r04_r0': R4[k].get('t_alpha_vis'), 'p1r03_c0': R3[k].get('t_alpha_vis')},
                 'uc_vis': {'p1s03': it.get('uc_vis'), 'p1r04_r0': R4[k].get('uc_vis'), 'p1r03_c0': R3[k].get('uc_vis')},
                 'abs_diff_vs_p1r04_r0': max(abs(float(it[x]) - float(R4[k][x])) for x in ('t_alpha_vis', 'uc_vis', 'beta_vis'))})
n = len(rows); s4 = sum(r['same_as_p1r04_r0'] for r in rows); s3 = sum(r['same_as_p1r03_c0'] for r in rows)
diff3 = [r['engine'] for r in rows if not r['same_as_p1r03_c0']]; diff4 = [r['engine'] for r in rows if not r['same_as_p1r04_r0']]
out = {'schema': 'p1s03_t0_agreement_v1', 'written_at': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
       'audience': '보는 창(τ_D 이전) 값만 — 시험 창 값 없음 · T1(_ICW) 항목은 읽지 않았다',
       'rule': 'DESIGN §8 판정 일치 기록 — P1S03 T0 판정 ↔ P1R04 R0(같은 자료 판 · 기대 15/15) · ↔ P1R03 C0(앞 자료 판 · 양방향)',
       'n_t0_judged': n, 'pending': pend, 'same_as_p1r04_r0': s4, 'same_as_p1r03_c0': s3, 'differs_from_p1r04_r0': diff4, 'differs_from_p1r03_c0': diff3,
       'max_abs_diff_vs_p1r04_r0': max([r['abs_diff_vs_p1r04_r0'] for r in rows], default=None),
       'reference_column_d2_remeasure': '이음매 세션 통지(11-14 23:4x): P1R03 D2 재측정 IS 자격 8/15 그대로 · 바뀐 엔진 없음 · 원 칸과 IS 판정 15/15 같음 — 인용 폴더 P1R03_factor_family_composites/remeasure_d2_20261114/results(이 도구는 열지 않았다)',
       'rows': rows}
json.dump(out, open(RD + '/results/t0_agreement.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('[t0_agreement] T0 판정 %d · P1R04 R0 와 같음 %d · P1R03 C0 와 같음 %d · 대기 %d · R0 대비 최대 차 %s · R0 와 다름 %s · C0 와 다름 %s' %
      (n, s4, s3, len(pend), out['max_abs_diff_vs_p1r04_r0'], diff4 or '-', diff3 or '-'))
sys.exit(0 if n == 15 and not pend else 3)
