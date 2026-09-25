"""llm_single_entry_scan.py — 무인 LLM 단일 진입 정적 검사기 (P0-M1 · 2026-09-24)

무엇을: 저장소 코드 전수에서 claude CLI **헤드리스 호출**(`-p`/`--print`)을 찾아
  허용 지점(02_Infrastructure/ops/rf_llm_env.sh 의 함수 rf_llm_agent_run 본문) 밖의 호출을 보고한다.
왜: rf_llm_agent_run 만이 AutoMem 차단(CLAUDE_CODE_DISABLE_AUTO_MEMORY=1)과 무인 표식
  (QVEST_UNATTENDED_LANE=1)을 싣는다. 그 밖에서 뜨는 claude 는 기억을 주입받고 기억에 쓴다(D7-02).
  "12곳 목록" 같은 열거는 낡는다 — 전수 parse 로 재도출한다(critique M4).
어떻게(언어별 정적 parse — 문자열 속 언급·주석·헤레독 본문은 호출이 아니다):
  셸  : 따옴표·$( )·백틱·${ }·헤레독·줄 잇기를 따라가는 어휘 분석 → 단순 명령 단위로
        (대입 · timeout/env/nohup/exec/command/time/nice/xargs 래퍼를 건너뛴) 단어열에서
        'claude 실행 파일 참조' 뒤에 -p/--print 가 오면 호출. 래퍼 함수 인자 형태
        (`_run_claude "$CLAUDE_BIN" -p …`)도 같은 규칙으로 잡는다. eval · bash -c 문자열은 재귀 분석.
        claude 참조 = 이름이 claude(.exe/.cmd) · `${X:-claude}` · 이름이 …CLAUDE(_BIN|_CLI|_EXE|_CMD|_PATH) 인
        변수 · 같은 파일에서 claude 실행 파일을 값으로 받은 변수.
  R   : system2/processx/sys 호출의 명령 인자가 claude · system/shell/pipe 문자열 속 'claude -p' · 변수 경유.
  Py  : subprocess 목록 인자 첫 원소가 claude · os.system/popen·subprocess 문자열 속 'claude -p' · 변수 경유.
  PS1/BAT/CMD/JS : 주석 제거 후 claude(.exe) … -p/--print 패턴 · JS spawn/exec.
사용: python llm_single_entry_scan.py <root> [--overlay <dir>] [--paths p1 p2 …(root 기준 · 픽스처 검사용)]
  --overlay: 파일 목록은 root 에서, 같은 상대 경로 사본이 overlay 에 있으면 그 내용을 읽는다(스테이징 검증).
출력: 줄마다 'VIOLATION <path>:<line> <요약>' · 'ALLOWED …' · 끝에 요약 JSON. rc = 위반 수>0 이면 1.
"""
import io, json, os, re, subprocess, sys

ALLOW_FILE = '02_Infrastructure/ops/rf_llm_env.sh'
ALLOW_FUNC = 'rf_llm_agent_run'
EXCL_TOP = {'.git', '05_Production', '01_Literature', '08_Tests', '.venv_qvest_ml', 'node_modules', '.cache'}
EXCL_ANY = {'__pycache__', 'node_modules', 'worktrees'}
SH_EXT = ('.sh', '.bash')
R_EXT = ('.R', '.r')
PY_EXT = ('.py',)
PS_EXT = ('.ps1', '.psm1')
BAT_EXT = ('.bat', '.cmd')
JS_EXT = ('.js', '.mjs', '.cjs', '.ts')
ALL_EXT = SH_EXT + R_EXT + PY_EXT + PS_EXT + BAT_EXT + JS_EXT

PRINT_FLAGS = {'-p', '--print'}
WRAPPERS = {'timeout', 'env', 'nohup', 'exec', 'command', 'builtin', 'time', 'nice', 'stdbuf', 'setsid',
            'xargs', 'sudo', 'caffeinate', 'winpty'}
KEYWORDS = {'then', 'do', 'else', 'elif', 'if', 'while', 'until', '!', '{', '}', 'fi', 'done', 'esac'}
CLAUDE_VALUE_RE = re.compile(r'(^|[\s/\\"\'(=:\-])claude(\.exe|\.cmd)?(?=$|[\s"\')|;}&])')
CLAUDE_NAME_RE = re.compile(r'CLAUDE(_BIN|_CLI|_EXE|_CMD|_PATH)?$')
VAR_WORD_RE = re.compile(r'^\$\{?([A-Za-z_][A-Za-z0-9_]*)(?:[:\-=?+][^}]*)?\}?$')
ASSIGN_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)(\[[^\]]*\])?\+?=(.*)$', re.S)


# ════════════════════════════════════════════════════════════════════════════
# 셸 어휘 분석
# ════════════════════════════════════════════════════════════════════════════
class ShellLexer:
    def __init__(self, text, base_line=1):
        self.s = text; self.n = len(text); self.i = 0; self.line = base_line
        self.cmds = []            # (line, [words])
        self.subs = []            # (line, text) — $( ) / 백틱 / 헤레독 확장 본문 (재귀 대상)
        self.heredocs = []        # (delim, strip, quoted)

    def run(self):
        words = []; buf = []; has = False; cmd_line = self.line; skip_next = False
        s = self.s

        def end_word():
            nonlocal buf, has, skip_next
            if has:
                w = ''.join(buf)
                if skip_next:
                    skip_next = False
                else:
                    words.append(w)
            buf = []; has = False

        def end_cmd():
            nonlocal words, cmd_line
            end_word()
            if words:
                self.cmds.append((cmd_line, words))
            words = []; cmd_line = self.line

        while self.i < self.n:
            c = s[self.i]
            if c == '\\':
                if self.i + 1 < self.n and s[self.i + 1] == '\n':
                    self.i += 2; self.line += 1; continue
                if self.i + 1 < self.n and s[self.i + 1] == '\r' and self.i + 2 < self.n and s[self.i + 2] == '\n':
                    self.i += 3; self.line += 1; continue
                if self.i + 1 < self.n:
                    buf.append(s[self.i + 1]); has = True; self.i += 2; continue
                self.i += 1; continue
            if c == '\r':
                self.i += 1; continue
            if c == '\n':
                end_cmd(); self.i += 1; self.line += 1
                if self.heredocs:
                    self._read_heredocs()
                cmd_line = self.line
                continue
            if c in ' \t':
                end_word(); self.i += 1; continue
            if c == '#' and not has:
                while self.i < self.n and s[self.i] != '\n':
                    self.i += 1
                continue
            if c == "'":
                j = s.find("'", self.i + 1)
                if j < 0: j = self.n
                seg = s[self.i + 1:j]; self.line += seg.count('\n')
                buf.append(seg); has = True; self.i = j + 1; continue
            if c == '"':
                seg = self._read_dquote()
                buf.append(seg); has = True; continue
            if c == '`':
                j = self._find_backtick(self.i + 1)
                inner = s[self.i + 1:j]
                self.subs.append((self.line, inner)); self.line += inner.count('\n')
                buf.append('`' + inner + '`'); has = True; self.i = j + 1; continue
            if c == '$' and self.i + 1 < self.n:
                nx = s[self.i + 1]
                if nx == '(':
                    if self.i + 2 < self.n and s[self.i + 2] == '(':
                        j = self._match(self.i + 1, '(', ')')
                        seg = s[self.i:j + 1]; self.line += seg.count('\n')
                        buf.append(seg); has = True; self.i = j + 1; continue
                    j = self._match(self.i + 1, '(', ')')
                    inner = s[self.i + 2:j]
                    self.subs.append((self.line, inner)); self.line += inner.count('\n')
                    buf.append('$(' + inner + ')'); has = True; self.i = j + 1; continue
                if nx == '{':
                    j = self._match(self.i + 1, '{', '}')
                    seg = s[self.i:j + 1]; self.line += seg.count('\n')
                    buf.append(seg); has = True; self.i = j + 1; continue
                if nx == "'":   # $'...'
                    j = self.i + 2
                    while j < self.n and s[j] != "'":
                        j += 2 if s[j] == '\\' else 1
                    buf.append(s[self.i + 2:j]); has = True; self.i = j + 1; continue
            if c in ';&|()':
                # 함수 정의 name() — '(' ')' 는 단어를 끊기만
                end_cmd()
                if c == '(' and self.i + 1 < self.n and s[self.i + 1] == '(':
                    j = self._match(self.i, '(', ')')        # (( 산술 ))
                    self.line += s[self.i:j + 1].count('\n'); self.i = j + 1; continue
                self.i += 1
                while self.i < self.n and s[self.i] in ';&|':
                    self.i += 1
                continue
            if c in '<>':
                # fd 숫자(2>) 는 단어가 아니다
                if has and ''.join(buf).isdigit():
                    buf = []; has = False
                else:
                    end_word()
                if s.startswith('<<<', self.i):
                    self.i += 3; skip_next = True; continue
                if s.startswith('<<', self.i):
                    self.i += 2
                    strip = False
                    if self.i < self.n and s[self.i] == '-':
                        strip = True; self.i += 1
                    while self.i < self.n and s[self.i] in ' \t':
                        self.i += 1
                    j = self.i; quoted = False; d = []
                    while j < self.n and s[j] not in ' \t\r\n;&|<>)':
                        if s[j] in '\'"':
                            quoted = True
                        else:
                            d.append(s[j])
                        j += 1
                    self.heredocs.append((''.join(d).replace('\\', ''), strip, quoted or '\\' in s[self.i:j]))
                    self.i = j; continue
                self.i += 1
                while self.i < self.n and s[self.i] in '<>&|':
                    self.i += 1
                if self.i < self.n and s[self.i] == '-':   # >&-
                    self.i += 1
                skip_next = True
                continue
            buf.append(c); has = True; self.i += 1
        end_cmd()
        return self

    def _read_dquote(self):
        s = self.s; self.i += 1; out = []
        while self.i < self.n:
            c = s[self.i]
            if c == '\\' and self.i + 1 < self.n:
                nx = s[self.i + 1]
                if nx == '\n':
                    self.i += 2; self.line += 1; continue
                out.append(nx if nx in '"\\$`' else '\\' + nx); self.i += 2; continue
            if c == '"':
                self.i += 1; break
            if c == '`':
                j = self._find_backtick(self.i + 1)
                inner = s[self.i + 1:j]
                self.subs.append((self.line, inner))
                out.append('`' + inner + '`'); self.line += inner.count('\n'); self.i = j + 1; continue
            if c == '$' and self.i + 1 < self.n and s[self.i + 1] == '(':
                if self.i + 2 < self.n and s[self.i + 2] == '(':
                    j = self._match(self.i + 1, '(', ')')
                    out.append(s[self.i:j + 1]); self.line += s[self.i:j + 1].count('\n'); self.i = j + 1; continue
                j = self._match(self.i + 1, '(', ')')
                inner = s[self.i + 2:j]
                self.subs.append((self.line, inner))
                out.append('$(' + inner + ')'); self.line += inner.count('\n'); self.i = j + 1; continue
            if c == '$' and self.i + 1 < self.n and s[self.i + 1] == '{':
                j = self._match(self.i + 1, '{', '}')
                out.append(s[self.i:j + 1]); self.line += s[self.i:j + 1].count('\n'); self.i = j + 1; continue
            if c == '\n':
                self.line += 1
            out.append(c); self.i += 1
        return ''.join(out)

    def _find_backtick(self, j):
        s = self.s
        while j < self.n:
            if s[j] == '\\':
                j += 2; continue
            if s[j] == '`':
                return j
            j += 1
        return self.n

    def _match(self, j, op, cl):
        """s[j] == op → 짝이 되는 cl 위치(따옴표·중첩 인지)."""
        s = self.s; depth = 0
        while j < self.n:
            c = s[j]
            if c == '\\':
                j += 2; continue
            if c == "'" and op == '(':
                k = s.find("'", j + 1); j = (k if k >= 0 else self.n) + 1; continue
            if c == '"':
                k = j + 1
                while k < self.n and s[k] != '"':
                    k += 2 if s[k] == '\\' else 1
                j = k + 1; continue
            if c == op:
                depth += 1
            elif c == cl:
                depth -= 1
                if depth == 0:
                    return j
            j += 1
        return self.n - 1

    def _read_heredocs(self):
        s = self.s
        for delim, strip, quoted in self.heredocs:
            start_line = self.line; body = []
            while self.i < self.n:
                j = s.find('\n', self.i)
                if j < 0: j = self.n
                ln = s[self.i:j].rstrip('\r'); self.i = j + 1; self.line += 1
                cmp_ln = ln.lstrip('\t') if strip else ln
                if cmp_ln == delim:
                    break
                body.append(ln)
            if not quoted:
                txt = '\n'.join(body)
                for m in re.finditer(r'\$\(', txt):
                    sub = ShellLexer(txt[m.start():]); k = sub._match(1, '(', ')')
                    self.subs.append((start_line + txt[:m.start()].count('\n'), txt[m.start() + 2:m.start() + k]))
        self.heredocs = []


def _strip_q(w):
    return w.strip('"\'')


def _is_claude_word(w, cvars):
    w0 = _strip_q(w)
    base = re.split(r'[\\/]', w0)[-1]
    if base in ('claude', 'claude.exe', 'claude.cmd'):
        return True
    m = VAR_WORD_RE.match(w0)
    if m:
        name = m.group(1)
        if CLAUDE_NAME_RE.search(name) or name in cvars:
            return True
        if re.search(r':-[^}]*\bclaude(\.exe)?\b', w0):
            return True
    return False


def shell_calls(text, base_line=1, depth=0):
    """→ [(line, words)] 헤드리스 claude 호출로 판정된 단순 명령."""
    lx = ShellLexer(text, base_line).run()
    cvars = set()
    for _, ws in lx.cmds:              # 1차: claude 실행 파일을 값으로 받은 변수(local/export/declare 포함)
        q = 0
        if ws and ws[0] in ('local', 'export', 'declare', 'readonly', 'typeset'):
            q = 1
            while q < len(ws) and ws[q].startswith('-'):
                q += 1
        for w in ws[q:]:
            m = ASSIGN_RE.match(w)
            if not m:
                break
            if CLAUDE_VALUE_RE.search(m.group(3)):
                cvars.add(m.group(1))
    found = []
    for ln, ws in lx.cmds:
        k = 0
        while k < len(ws) and ASSIGN_RE.match(ws[k]):
            k += 1
        # 키워드·래퍼 건너뛰기 → 실제 명령어 자리(eval · bash -c 재귀 판정용)
        while k < len(ws):
            w = _strip_q(ws[k])
            if w in KEYWORDS:
                k += 1; continue
            if w in WRAPPERS:
                if w == 'command' and k + 1 < len(ws) and _strip_q(ws[k + 1]) in ('-v', '-V'):
                    k = len(ws); break
                k += 1
                while k < len(ws) and (_strip_q(ws[k]).startswith('-') or ASSIGN_RE.match(_strip_q(ws[k]))):
                    opt = _strip_q(ws[k]); k += 1
                    if (w, opt) in (('env', '-u'), ('env', '-C'), ('env', '-S'), ('timeout', '-s'),
                                    ('timeout', '-k'), ('nice', '-n'), ('xargs', '-I'), ('xargs', '-n'), ('xargs', '-P')):
                        k += 1
                if w == 'timeout' and k < len(ws):
                    k += 1                      # 지속 시간 인자
                continue
            break
        rest = ws[k:]
        if not rest:
            continue
        cw = _strip_q(rest[0])
        # eval / bash -c 문자열은 재귀 분석
        if depth < 3 and cw == 'eval':
            found += [(ln, x[1]) for x in shell_calls(' '.join(rest[1:]), ln, depth + 1)]
            continue
        if depth < 3 and re.split(r'[\\/]', cw)[-1] in ('bash', 'sh', 'zsh', 'dash', 'bash.exe', 'sh.exe'):
            for q in range(1, len(rest) - 1):
                if re.match(r'^-[a-z]*c[a-z]*$', _strip_q(rest[q])):
                    found += [(ln, x[1]) for x in shell_calls(rest[q + 1], ln, depth + 1)]
                    break
        # claude 참조 뒤에 -p/--print — 명령어 자리든 래퍼 함수 인자 자리든
        for q, w in enumerate(rest):
            if _is_claude_word(w, cvars) and any(_strip_q(x) in PRINT_FLAGS or _strip_q(x).startswith('--print=')
                                                 for x in rest[q + 1:]):
                found.append((ln, rest))
                break
    for ln, sub in lx.subs:
        if depth < 4:
            found += shell_calls(sub, ln, depth + 1)
    # 중복 제거(같은 줄·같은 단어열)
    seen = set(); out = []
    for ln, ws in found:
        key = (ln, tuple(ws))
        if key not in seen:
            seen.add(key); out.append((ln, ws))
    return out


def shell_func_ranges(text):
    rng = {}; lines = text.split('\n'); cur = None
    for i, l in enumerate(lines, 1):
        m = re.match(r'^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{?\s*$', l.rstrip('\r'))
        if m and cur is None:
            cur = (m.group(1), i); continue
        if cur and re.match(r'^\}\s*$', l.rstrip('\r')):
            rng.setdefault(cur[0], []).append((cur[1], i)); cur = None
    return rng


# ════════════════════════════════════════════════════════════════════════════
# R · Python · PS1/BAT · JS
# ════════════════════════════════════════════════════════════════════════════
def _strip_hash_comments(line):
    out = []; q = None; i = 0
    while i < len(line):
        c = line[i]
        if q:
            if c == '\\':
                out.append(line[i:i + 2]); i += 2; continue
            if c == q:
                q = None
        elif c in '"\'':
            q = c
        elif c == '#':
            break
        out.append(c); i += 1
    return ''.join(out)


STR_CLAUDE_P = re.compile(r'''["'](?:[^"'\n]*?[\s/\\])?claude(?:\.exe|\.cmd)?\s+[^"'\n]*?(?:-p|--print)\b''')


def _window(lines, i, k=6):
    return ' '.join(lines[i:i + k])


def r_calls(text):
    lines = [_strip_hash_comments(l) for l in text.split('\n')]
    cvars = set(); found = []
    for l in lines:
        m = re.search(r'''([A-Za-z_.][\w.]*)\s*(<-|=)\s*(Sys\.which\(\s*["']claude(\.exe)?["']\s*\)|["'](?:[^"'\n]*[\\/])?claude(\.exe|\.cmd)?["'])''', l)
        if m:
            cvars.add(m.group(1))
    for i, l in enumerate(lines):
        w = _window(lines, i)
        m = re.search(r'''\b(system2|processx::run|processx::process\$new|sys::exec_wait|sys::exec_internal|sys::exec_background)\s*\(\s*(?:command\s*=\s*)?(?:(["'](?:[^"'\n]*[\\/])?claude(?:\.exe|\.cmd)?["'])|([A-Za-z_.][\w.]*))''', l)
        if m:
            is_cl = bool(m.group(2)) or (m.group(3) in cvars)
            if is_cl and re.search(r'''["'](-p|--print)["']|["'][^"'\n]*\s(-p|--print)\b''', w):
                found.append((i + 1, l.strip()[:160])); continue
        if re.search(r'\b(system|shell|pipe|system2)\s*\(', l) and (STR_CLAUDE_P.search(w)):
            found.append((i + 1, l.strip()[:160]))
    return found


def py_calls(text):
    lines = [_strip_hash_comments(l) for l in text.split('\n')]
    cvars = set(); found = []
    for l in lines:
        m = re.search(r'''([A-Za-z_]\w*)\s*=\s*(shutil\.which\(\s*["']claude(\.exe)?["']\s*\)|r?["'](?:[^"'\n]*[\\/])?claude(\.exe|\.cmd)?["'])''', l)
        if m:
            cvars.add(m.group(1))
    for i, l in enumerate(lines):
        w = _window(lines, i)
        m = re.search(r'''subprocess\.(run|call|check_call|check_output|Popen)\(\s*\[\s*(r?f?["'](?:[^"'\n]*[\\/])?claude(?:\.exe|\.cmd)?["']|([A-Za-z_]\w*))''', l)
        if m and (m.group(3) is None or m.group(3) in cvars) and re.search(r'''["'](-p|--print)["']''', w):
            found.append((i + 1, l.strip()[:160])); continue
        if re.search(r'\b(os\.system|os\.popen|subprocess\.\w+)\s*\(', l) and STR_CLAUDE_P.search(w):
            found.append((i + 1, l.strip()[:160]))
    return found


def ps_bat_calls(text, kind):
    found = []
    for i, l in enumerate(text.split('\n')):
        s = l.strip()
        if kind == 'ps':
            s = _strip_hash_comments(s)
        else:
            if re.match(r'^(@?rem\b|::)', s, re.I):
                continue
        if re.search(r'''(^|[\s&|;(]|&\s*["'])(?:[^\s"']*[\\/])?claude(\.exe|\.cmd)?["']?\s+(?:[^|;&\n]*\s)?(-p|--print)\b''', s, re.I):
            found.append((i + 1, s[:160]))
    return found


def js_calls(text):
    found = []
    lines = text.split('\n')
    for i, l in enumerate(lines):
        s = re.sub(r'//.*$', '', l)
        w = _window(lines, i)
        if re.search(r'''\b(spawn|spawnSync|exec|execSync|execFile|execFileSync|fork)\s*\(\s*["'`](?:[^"'`\n]*[\\/])?claude(\.exe|\.cmd)?["'`\s]''', s) \
           and re.search(r'''(-p|--print)\b''', w):
            found.append((i + 1, s.strip()[:160]))
    return found


# ════════════════════════════════════════════════════════════════════════════
def list_files(root, only=None):
    if only:
        return [p.replace('\\', '/') for p in only]
    files = set()
    try:
        out = subprocess.run(['git', '-C', root, 'ls-files'], capture_output=True, text=True, encoding='utf-8', errors='replace').stdout
        for p in out.splitlines():
            files.add(p)
    except Exception:
        pass
    for top in ('02_Infrastructure', '.claude', 'qepm'):   # 미추적 새 레인도 잡는다(운영 코드 층)
        base = os.path.join(root, top)
        for dp, dns, fns in os.walk(base):
            dns[:] = [d for d in dns if d not in EXCL_ANY]
            for fn in fns:
                files.add(os.path.relpath(os.path.join(dp, fn), root).replace('\\', '/'))
    res = []
    for p in sorted(files):
        parts = p.split('/')
        if parts[0] in EXCL_TOP or any(x in EXCL_ANY for x in parts) or any(x.startswith('_archive') for x in parts):
            continue
        if parts[0] == '.claude' and len(parts) > 1 and parts[1] == 'worktrees':
            continue
        if p.endswith(ALL_EXT):
            res.append(p)
    return res


def scan(root, only=None, overlay=None):
    viol = []; allowed = []; nfiles = 0
    for rel in list_files(root, only):
        fp = os.path.join(root, rel)
        if overlay and os.path.isfile(os.path.join(overlay, rel)):
            fp = os.path.join(overlay, rel)      # 스테이징 검증: 같은 상대 경로의 사본이 있으면 그걸 읽는다
        try:
            text = io.open(fp, 'rb').read().decode('utf-8', 'replace')
        except Exception:
            continue
        if 'claude' not in text:
            nfiles += 1; continue
        nfiles += 1
        if rel.endswith(SH_EXT) or text.startswith('#!/bin/bash') or text.startswith('#!/usr/bin/env bash'):
            hits = [(ln, ' '.join(ws)[:160]) for ln, ws in shell_calls(text)]
            fr = shell_func_ranges(text) if rel == ALLOW_FILE else {}
            for ln, sn in hits:
                if rel == ALLOW_FILE and any(a <= ln <= b for a, b in fr.get(ALLOW_FUNC, [])):
                    allowed.append((rel, ln, sn))
                else:
                    viol.append((rel, ln, sn))
            continue
        if rel.endswith(R_EXT):
            hits = r_calls(text)
        elif rel.endswith(PY_EXT):
            hits = py_calls(text)
        elif rel.endswith(PS_EXT):
            hits = ps_bat_calls(text, 'ps')
        elif rel.endswith(BAT_EXT):
            hits = ps_bat_calls(text, 'bat')
        else:
            hits = js_calls(text)
        viol += [(rel, ln, sn) for ln, sn in hits]
    return viol, allowed, nfiles


def main():
    a = sys.argv[1:]
    root = a[0]; only = None; overlay = None
    if '--overlay' in a:
        overlay = a[a.index('--overlay') + 1]
        del a[a.index('--overlay'):a.index('--overlay') + 2]
    if '--paths' in a:
        only = a[a.index('--paths') + 1:]
    viol, allowed, nfiles = scan(root, only, overlay)
    for rel, ln, sn in allowed:
        print('ALLOWED   %s:%d  %s' % (rel, ln, sn))
    for rel, ln, sn in viol:
        print('VIOLATION %s:%d  %s' % (rel, ln, sn))
    print(json.dumps({'files_scanned': nfiles, 'allowed': len(allowed), 'violations': len(viol),
                      'violation_sites': ['%s:%d' % (r, l) for r, l, _ in viol]}, ensure_ascii=False))
    sys.exit(1 if viol else 0)


if __name__ == '__main__':
    main()
