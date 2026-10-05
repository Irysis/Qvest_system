#!/usr/bin/env python
"""rf_clean_lane.py — 무인 충실구현 레인 **청정 모드** 도우미 (결정 FA-CLEAN-BASE-PATH · 도훈 2026-09-26 12:24)

결정문: "(나) 기존 레인 강화 — 노출 범위 full 유지 · 무인 충실구현 레인에 성과 열람 차단·피드백 성과 제거·훅 성과 문맥 제외·
         출처 기록 → 1505.00328 재구현이 첫 F_A 후보. 규칙 파일(pit.md 사고 수치 등) 주입은 알려진 경계로 문서화."
호출자 = rf_replication_auto.sh (셸에 판단 로직을 두지 않는다 — 파이썬 한 곳 · 검사 = 08_Tests/ops/test_rf_clean_lane.sh)

  mode            요청·설정에서 레인 모드 해석 → 셸 대입문(LANE_MODE=clean|normal|halt …) · 첫 해석을 요청 파일에 lane_mode 로 남긴다
                  (같은 요청의 재시도·검증기 단독 재실행이 같은 작업 디렉터리를 보게). 규칙 순서는 cmd_mode 머리 주석.
  sanitize        재구현 피드백(측정 실패 사유 · 충실도 감사 지적)에서 성과 수치·측정 산출물 참조를 뺀다(충실도 사유만) — stdin → stdout ·
                  가린 뒤 사후 검사 정규식(clean_base_rule.config.json)을 다시 걸어 남으면 그 줄을 뺀다(fail-closed) · 통계 JSON
  prompt-section  청정 모드 프롬프트 절(열람 범위 = 가드 설정 read_allow 에서 생성 — 사본 없음)
  prov-pre        출처 기록(작업 디렉터리 lane_provenance.json) — 실행 전: 모드·가드/훅/설정 sha256·CLI 도구 목록·프롬프트 sha256·
                  피드백 가림 통계·자동 주입 규칙 파일 지문(알려진 경계)
  prov-post       출처 기록 — 실행 후: rc · 폴백 · engine/FIDELITY sha256·mtime

★자기 신고로 쓰지 않는다: 이 기록은 사후 검사(rf_clean_base.R)가 **전사·산출물에서 재도출한 값과 대조**하는 대상이다
  (프롬프트 sha256 = 전사 첫 레코드 content 의 sha256 · 엔진 sha256 = 현재 engine.R · 가드 작동 = 전사 hook_success stdout).
쓰기: 요청 파일(lane_mode 3필드 · 원자적) · 작업 디렉터리 lane_provenance.json · --stats 로 준 파일. 그 밖 무쓰기.
"""
import hashlib, io, json, os, re, shlex, sys, time

MODES = ('clean', 'normal')


def _now():
    return time.strftime('%Y-%m-%dT%H:%M:%S%z')


def _rd_json(p):
    try:
        return json.loads(io.open(p, 'rb').read().decode('utf-8'))
    except Exception:
        return None


def _sha_bytes(b):
    return hashlib.sha256(b).hexdigest() if b is not None else None


def _sha_file(p):
    try:
        return _sha_bytes(open(p, 'rb').read())
    except Exception:
        return None


def _md5_file(p):
    # md5 병기 — 원장·표식 키트(mark_automem_exposure.R .md5f)·CLEAN 핀(.rfc_md5)이 엔진을 md5 로 부른다(대조 편의 · 판정은 sha256)
    try:
        return hashlib.md5(open(p, 'rb').read()).hexdigest()
    except Exception:
        return None


def _atomic_json(p, obj):
    d = os.path.dirname(os.path.abspath(p))
    os.makedirs(d, exist_ok=True)
    tmp = '%s.tmp%d_%d' % (p, os.getpid(), time.perf_counter_ns())
    with io.open(tmp, 'wb') as fh:
        fh.write(json.dumps(obj, ensure_ascii=False, indent=1).encode('utf-8'))
    os.replace(tmp, p)


def _args(argv):
    out, k = {}, None
    for a in argv:
        if a.startswith('--'):
            k = a[2:]
            out[k] = ''
        elif k is not None:
            out[k] = a
            k = None
    return out


def _sq(v):
    return shlex.quote(str(v))


# ── 모드 해석 ────────────────────────────────────────────────────────────────
def _support(root, lane):
    """청정 모드 전제 — 설정·가드·훅이 청정 표식을 아는가. 반환 = 사유 목록(빈 목록 = 충족)."""
    why = []
    if not isinstance(lane, dict):
        return ['lane_config_unreadable']
    for k in ('rule_config', 'guard', 'guard_policy', 'inject_hook', 'guard_support_marker', 'inject_support_marker',
              'wdir_prefix', 'provenance_file', 'feedback_sanitize', 'disallowed_tools_clean'):
        if not lane.get(k):
            why.append('lane_config_missing:%s' % k)
    if why:
        return why
    rc = _rd_json(os.path.join(root, lane['rule_config']))
    try:
        [re.compile(x) for x in rc['exposure']['prompt']['measured_ref_regex']]
        [re.compile(x) for x in rc['exposure']['transcript']['auto_memory']['metric_regex']]
    except Exception:
        why.append('rule_config_unreadable')
    pol = _rd_json(os.path.join(root, lane['guard_policy']))
    try:
        cl = pol['clean_lane']
        re.compile(cl['target_regex'])
        if not cl['read_allow'] or not cl['wdir_env']:
            raise ValueError
    except Exception:
        why.append('guard_policy_no_clean_lane')
    for k, mk in (('guard', 'guard_support_marker'), ('inject_hook', 'inject_support_marker')):
        try:
            if lane[mk] not in io.open(os.path.join(root, lane[k]), encoding='utf-8', errors='replace').read():
                why.append('%s_without_clean_support' % k)
        except Exception:
            why.append('%s_unreadable' % k)
    try:
        for rx in (lane['feedback_sanitize'].get('drop_line_regex') or []) + (lane['feedback_sanitize'].get('mask_regex') or []):
            re.compile(rx)
    except Exception:
        why.append('sanitize_rules_invalid')
    return why


def cmd_mode(a):
    """규칙 순서(먼저 걸리는 것이 이긴다):
       ① 결합 요청 → normal(combo_forced — 설계 재료가 교차 entry 실측이다)
       ② 요청에 lane_mode 가 이미 있다 → 그대로(persisted — 같은 요청의 재시도·검증기 단독 재실행이 같은 작업 디렉터리를 본다)
       ③ 요청 clean_mode:false → normal(request_off)
       ④ 요청 clean_mode:true → clean(request) — 전제 미충족이면 halt(요청 보존 · 조용히 비청정으로 돌지 않는다)
       ⑤ 배포 전부터 진행 중이던 요청(실패·감사 지적·재시도 흔적이 있는데 lane_mode 없음) → normal(legacy_in_flight — 옛 작업 디렉터리의 앞 판·피드백과 짝이 맞게)
       ⑥ 설정 default_mode → clean|normal(config_default) — clean 인데 전제 미충족이면 normal(config_default_degraded · 사유 기록)
       ⑦ 설정 판독 불능 → normal(lane_config_absent) — ④는 halt"""
    req_p, root = a.get('req', ''), a.get('root', '')
    lane_p = a.get('lane-cfg', '')
    combo = a.get('combo', '0') == '1'
    R = _rd_json(req_p) or {}
    lane = _rd_json(lane_p)
    prefix = (lane or {}).get('wdir_prefix') or 'RP_AUTO_CLEAN_'
    ask = R.get('clean_mode', None)
    persisted = R.get('lane_mode') if R.get('lane_mode') in MODES else None
    legacy = persisted is None and any([R.get('audit_feedback'), int(R.get('audit_retries') or 0) > 0, R.get('failure'),
                                        int(R.get('auto_retries') or 0) > 0, R.get('revived_from')])
    mode, src, why = 'normal', '', ''
    if combo:
        mode, src = ((lane or {}).get('combo_mode') or 'normal'), 'combo_forced'
        if mode not in MODES:
            mode = 'normal'
    elif persisted:
        mode, src = persisted, 'persisted'
    elif ask is False:
        mode, src = 'normal', 'request_off'
    elif ask is True:
        miss = _support(root, lane)
        mode, src, why = ('halt', 'request', ';'.join(miss)) if miss else ('clean', 'request', '')
    elif legacy:
        mode, src = 'normal', 'legacy_in_flight'
    elif isinstance(lane, dict):
        dm = lane.get('default_mode')
        if dm not in MODES:
            mode, src, why = 'normal', 'config_default_invalid', str(dm)
        elif dm == 'clean':
            miss = _support(root, lane)
            mode, src, why = ('normal', 'config_default_degraded', ';'.join(miss)) if miss else ('clean', 'config_default', '')
        else:
            mode, src = 'normal', 'config_default'
    else:
        mode, src, why = 'normal', 'lane_config_absent', lane_p
    if mode == 'clean' and combo:                      # 이중 안전 — 결합은 청정이 아니다
        mode, src = 'normal', 'combo_forced'
    if mode in MODES and not persisted and R:
        R['lane_mode'] = mode
        R['lane_mode_source'] = src
        R['lane_mode_at'] = _now()
        if why:
            R['lane_mode_why'] = why
        try:
            _atomic_json(req_p, R)
        except Exception as e:
            why = (why + ';' if why else '') + 'persist_failed:%s' % type(e).__name__
    print('LANE_MODE=%s' % _sq(mode))
    print('LANE_MODE_SOURCE=%s' % _sq(src))
    print('LANE_MODE_WHY=%s' % _sq(why))
    print('LANE_WDIR_PREFIX=%s' % _sq(prefix))
    return 0


# ── 피드백 가림 ──────────────────────────────────────────────────────────────
def _rules(a):
    lane = _rd_json(a.get('lane-cfg', ''))
    root = a.get('root', '')
    rc_p = a.get('rule-cfg') or os.path.join(root, (lane or {}).get('rule_config') or '')
    rc = _rd_json(rc_p)
    fs = (lane or {})['feedback_sanitize']
    drop = [re.compile(x) for x in fs['drop_line_regex']]
    mask = [re.compile(x) for x in fs['mask_regex']]
    for m in mask:
        if 'v' not in m.groupindex:
            raise ValueError('mask_regex 에 (?P<v>…) 그룹이 없다: ' + m.pattern)
    post = [re.compile(x) for x in rc['exposure']['prompt']['measured_ref_regex']] + \
           [re.compile(x) for x in rc['exposure']['transcript']['auto_memory']['metric_regex']]
    fp = hashlib.sha256(json.dumps([fs, [p.pattern for p in post]], ensure_ascii=False, sort_keys=True).encode('utf-8')).hexdigest()
    return dict(drop=drop, mask=mask, post=post, token=str(fs['mask']), ph=str(fs['drop_placeholder']), fp=fp)


def sanitize_text(text, R):
    st = dict(lines_in=0, lines_out=0, masked=0, dropped_ref=0, dropped_residual=0)
    out = []
    for ln in text.split('\n'):
        st['lines_in'] += 1
        if any(r.search(ln) for r in R['drop']):
            st['dropped_ref'] += 1
            out.append(R['ph'])
            continue
        for r in R['mask']:
            def _sub(m):
                st['masked'] += 1
                s, e = m.span('v')
                g0s = m.start()
                return m.group(0)[:s - g0s] + R['token'] + m.group(0)[e - g0s:]
            ln = r.sub(_sub, ln)
        if any(r.search(ln) for r in R['post']):
            st['dropped_residual'] += 1
            out.append(R['ph'])
            continue
        out.append(ln)
    st['lines_out'] = len(out)
    return '\n'.join(out), st


def cmd_sanitize(a):
    raw = sys.stdin.buffer.read().decode('utf-8', 'replace')
    try:
        R = _rules(a)
    except Exception as e:
        sys.stderr.write('[rf_clean_lane] sanitize 규칙 판독 불능(fail-closed): %s\n' % e)
        return 3
    txt, st = sanitize_text(raw, R)
    st.update(kind=a.get('kind', ''), rules_sha256=R['fp'], in_sha256=_sha_bytes(raw.encode('utf-8')),
              out_sha256=_sha_bytes(txt.encode('utf-8')), at=_now())
    if a.get('stats'):
        _atomic_json(a['stats'], st)
    sys.stdout.buffer.write(txt.encode('utf-8'))
    return 0


# ── 프롬프트 절 ──────────────────────────────────────────────────────────────
def cmd_prompt_section(a):
    pol = _rd_json(a.get('policy', ''))
    lane = _rd_json(a.get('lane-cfg', '')) or {}
    try:
        items = pol['clean_lane']['read_allow']
    except Exception:
        sys.stderr.write('[rf_clean_lane] 가드 설정 clean_lane.read_allow 판독 불능\n')
        return 3
    L = ['## 청정 모드 — 열람 범위 (결정 FA-CLEAN-BASE-PATH)',
         '이 실행은 **성과를 보지 않고 논문만으로** 구현하는 청정 레인이다. 읽기(Read·Grep)는 아래 허용 목록과 작업 디렉터리로',
         '제한되고 그 밖은 훅이 막는다(원장·산출물·다른 전략 엔진·교훈·기억 — 그 안의 수치는 이 구현의 입력이 아니다).',
         '- 작업 디렉터리: `%s` (네 산출물만 있다)' % a.get('wdir', '')]
    for it in items:
        L.append('- `%s` — %s' % (it.get('path'), it.get('why')))
    L += ['Glob(이름 열거)은 저장소 안에서 열려 있지만 내용은 위 목록 밖에서 열리지 않는다 — 막히면 경로를 바꾸지 말고 이 목록 안에서 찾아라.',
          '논문 원문은 WebFetch 로 읽어라. 셸·Agent·Skill 도구는 이 실행에 없다.']
    wf = lane.get('web_forbidden') or []
    if wf:
        L.append('★이 저장소의 웹 사본(%s)을 열지 마라 — 원격 사본도 같은 원장·산출물이다.' % ' · '.join(wf))
    sys.stdout.buffer.write(('\n'.join(L) + '\n').encode('utf-8'))
    return 0


# ── 출처 기록 ────────────────────────────────────────────────────────────────
def _rel(p, root):
    p = (p or '').replace('\\', '/')
    r = (root or '').replace('\\', '/').rstrip('/')
    return p[len(r) + 1:] if r and p.lower().startswith(r.lower() + '/') else p


def _instr_files(root):
    # CLI 가 cwd(저장소 루트)에서 자동 주입하는 프로젝트 규칙 파일(알려진 경계) — 실제 주입 목록은 사후 검사가 전사에서 재도출해 대조한다
    out = []
    for rel in ['CLAUDE.md'] + sorted('.claude/rules/' + f for f in (os.listdir(os.path.join(root, '.claude', 'rules'))
                                                                     if os.path.isdir(os.path.join(root, '.claude', 'rules')) else [])
                                         if f.endswith('.md')):
        p = os.path.join(root, rel)
        if os.path.isfile(p):
            out.append(dict(path=rel, sha256=_sha_file(p), bytes=os.path.getsize(p)))
    return out


def cmd_prov_pre(a):
    root, wdir = a.get('root', ''), a.get('wdir', '')
    lane = _rd_json(a.get('lane-cfg', '')) or {}
    pf = a.get('prompt', '')
    fb = {}
    for k in ('failure', 'audit'):
        sp = os.path.join(wdir, '.clean_fb_%s.json' % k)
        if os.path.isfile(sp):
            fb[k] = _rd_json(sp)
    R = _rd_json(a.get('req', '')) or {}
    pol_p = os.path.join(root, lane.get('guard_policy') or '')
    pol = _rd_json(pol_p) or {}
    cl = pol.get('clean_lane')
    mode = a.get('mode', '')
    instr = _instr_files(root)
    guard_sha = _sha_file(os.path.join(root, lane.get('guard') or ''))
    cl_sha = _sha_bytes(json.dumps(cl, ensure_ascii=False, sort_keys=True).encode('utf-8')) if cl else None
    inj_sha = _sha_file(os.path.join(root, lane.get('inject_hook') or ''))
    lane_sha = _sha_file(a.get('lane-cfg', ''))
    rule_sha = _sha_file(os.path.join(root, lane.get('rule_config') or ''))
    # 주입 문맥 지문 — 이 실행에 들어가는 문맥 원천 전부(프롬프트 · 자동 주입 규칙 파일 · 가드·설정·주입 훅 · 레인/규칙 설정)의 sha256 을
    #   정해진 순서로 묶은 sha256 1개. 표식 키트·사후 검사가 "같은 조건의 실행인가" 를 한 값으로 대조한다(구성 목록은 아래 필드에 그대로 있다).
    fp_src = dict(prompt=_sha_file(pf), instruction_files=[[f['path'], f['sha256']] for f in instr], guard=guard_sha,
                  guard_policy_clean_lane=cl_sha, inject_hook=inj_sha, lane_config=lane_sha, rule_config=rule_sha, mode=mode)
    fingerprint = _sha_bytes(json.dumps(fp_src, ensure_ascii=False, sort_keys=True).encode('utf-8'))
    doc = dict(
        schema=lane.get('provenance_schema') or 'lane_provenance_v1',
        decision=lane.get('decision') or 'FA-CLEAN-BASE-PATH',
        mode=mode, clean=(mode == 'clean'), mode_source=a.get('mode-source', ''), mode_why=a.get('mode-why', ''),
        paper_key=(R.get('paper') or {}).get('paper_key') or '', paper_url=(R.get('paper') or {}).get('url') or '',
        wdir=_rel(wdir, root), engine_rel=_rel(os.path.join(wdir, 'engine.R').replace('\\', '/'), root),
        pre=dict(
            at=_now(),
            injected_context_fingerprint=fingerprint, injected_context_sources=fp_src,
            prompt=dict(file=os.path.basename(pf), sha256=_sha_file(pf), md5=_md5_file(pf), bytes=(os.path.getsize(pf) if os.path.isfile(pf) else None)),
            feedback=dict(failure=fb.get('failure'), audit=fb.get('audit'),
                          audit_source_mode=R.get('audit_feedback_mode') if R.get('audit_feedback') else None,
                          audit_source_dir=R.get('audit_feedback_src') if R.get('audit_feedback') else None),
            guard=dict(applied=(mode == 'clean'),
                       env={'QVEST_CLEAN_LANE': '1', 'QVEST_CLEAN_WDIR': wdir.replace('\\', '/')} if mode == 'clean' else {},
                       hook_sha256=guard_sha, policy_sha256=_sha_file(pol_p), policy_clean_lane_sha256=cl_sha,
                       inject_hook_sha256=inj_sha, lane_config_sha256=lane_sha, rule_config_sha256=rule_sha),
            cli=dict(allowed_tools=a.get('allowed', ''), disallowed_tools=a.get('disallowed', ''),
                     model=a.get('model', ''), effort=a.get('effort', ''), fallback_model=a.get('fallback-model', ''),
                     auto_memory_disabled=True),
            known_boundary=dict(instruction_files=instr, notes=lane.get('known_boundary') or [])),
        post=None)
    _atomic_json(os.path.join(wdir, lane.get('provenance_file') or 'lane_provenance.json'), doc)
    print('prov_pre ok')
    return 0


def cmd_prov_post(a):
    wdir = a.get('wdir', '')
    lane = _rd_json(a.get('lane-cfg', '')) or {}
    p = os.path.join(wdir, lane.get('provenance_file') or 'lane_provenance.json')
    doc = _rd_json(p)
    if not isinstance(doc, dict):
        sys.stderr.write('[rf_clean_lane] prov-post: 실행 전 기록 부재 — %s\n' % p)
        return 3
    eng = os.path.join(wdir, 'engine.R')
    fid = os.path.join(wdir, 'FIDELITY.json')
    doc['post'] = dict(at=_now(), rc=a.get('rc', ''), fell_back=a.get('fell-back', ''),
                       used_model=a.get('used-model', ''), used_effort=a.get('used-effort', ''),
                       engine_sha256=_sha_file(eng), engine_md5=_md5_file(eng),
                       engine_mtime_utc=(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(os.path.getmtime(eng))) if os.path.isfile(eng) else None),
                       fidelity_sha256=_sha_file(fid), fidelity_md5=_md5_file(fid),
                       abort=os.path.isfile(os.path.join(wdir, 'ABORT.txt')))
    _atomic_json(p, doc)
    print('prov_post ok')
    return 0


def main(argv):
    if not argv:
        print(__doc__)
        return 64
    cmd, a = argv[0], _args(argv[1:])
    fn = {'mode': cmd_mode, 'sanitize': cmd_sanitize, 'prompt-section': cmd_prompt_section,
          'prov-pre': cmd_prov_pre, 'prov-post': cmd_prov_post}.get(cmd)
    if fn is None:
        print(__doc__)
        return 64
    return fn(a)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
