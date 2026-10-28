#!/usr/bin/env python3
"""The words on screen, counted (plan-wizard.md 2.1). A lint, not proof.

  strings.py [--root DIR] [--allow FILE] [--removed FILE] [--bash FILE]... [FILE]...

Prints one JSON object on stdout; dev/strings.sh reads it. With no FILE the
scanned files are the notch's own (those that exist); with FILEs only those.

The rule (plan-settings.md): a string on screen is one sentence of at most
MAX_WORDS words, a tip at most TIP_MAX characters with no full stop, a bash
title or finish message at most TITLE_MAX characters as well.

Prose is a double-quoted literal of two words or more with none of $ = { } \\.
Literals joined by `+`, or the pieces of a template, are judged as one string
(any other operand is one word); the branches of ?: and || are separate. An
unjoined prose literal that starts lowercase, or one that starts with a space,
is a fragment: a sentence split across bindings, which the count cannot see.
"""
import json, os, re, sys

MAX_WORDS = 7
TIP_MAX = 60
TITLE_MAX = 44

SCANNED = [
    "Bar.qml", "NotchSettings.qml", "NotchSetup.qml", "SetupService.qml", "NotchUpdate.qml",
    "plugins/NotchPlugins.qml", "plugins/NotchPluginsNotice.qml", "plugins/PluginsModel.js",
    "platform.js", "keys.js",
    # From the day they exist.
    "NotchWizard.qml", "wizard.js", "settings-tips.js", "NotchTip.qml", "NotchConfigTransfer.qml",
]
TIP_FILES = {"settings-tips.js"}   # one tip per literal: the character rule, not the word rule
RATCHETED = [f for f in SCANNED if f.endswith(".qml")]
BASH_SCRIPT = "bin/notch-setup"


def tokens(src):
    """(kind, text, line) with kind str | tpl | op | id; comments gone, single quotes skipped."""
    out, i, n, line = [], 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n": line += 1; i += 1
        elif c in " \t\r": i += 1
        elif src.startswith("//", i):
            while i < n and src[i] != "\n": i += 1
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2); j = n if j < 0 else j + 2
            line += src.count("\n", i, j); i = j
        elif c in "\"'":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            out.append(("str" if c == '"' else "sq", src[i + 1:j], line))
            i = j + 1
        elif c == "`":
            j, depth = i + 1, 0
            while j < n and (src[j] != "`" or depth):
                if src.startswith("${", j): depth += 1
                elif src[j] == "}" and depth: depth -= 1
                j += 2 if src[j] == "\\" else 1
            body = src[i + 1:j]
            out.append(("tpl", re.sub(r"\$\{[^}]*\}", "x", body), line))
            line += body.count("\n"); i = j + 1
        elif src.startswith("||", i) or src.startswith("&&", i) or src.startswith("??", i):
            out.append(("op", src[i:i + 2], line)); i += 2
        elif c.isalnum() or c in "_$.":
            j = i
            while j < n and (src[j].isalnum() or src[j] in "_$."): j += 1
            out.append(("id", src[i:j], line)); i = j
        else:
            out.append(("op", c, line)); i += 1
    return out


def operand(toks, i):
    """The end of one non-string term of a `+` chain starting at i, or i if there is none."""
    if i >= len(toks) or toks[i][0] != "id": return i
    j = i + 1
    while j < len(toks) and toks[j][0] == "op" and toks[j][1] in "([":
        close, depth, k = ")" if toks[j][1] == "(" else "]", 0, j
        while k < len(toks):
            if toks[k][0] == "op" and toks[k][1] in "([": depth += 1
            elif toks[k][0] == "op" and toks[k][1] in ")]": depth -= 1
            k += 1
            if depth == 0: break
        j = k
    return j


def drop_console(toks):
    """console.warn(...) and its kin print to a log, not a screen."""
    out, i = [], 0
    while i < len(toks):
        if toks[i][0] == "id" and toks[i][1].startswith("console."):
            end = operand(toks, i)
            i = max(end, i + 1)
        else:
            out.append(toks[i]); i += 1
    return out


def literals(src):
    """[(text, line, joined, kind, pieces)]: each judged string of the source."""
    toks, out, used = drop_console(tokens(src)), [], set()
    for i in range(len(toks)):
        parts, texts, j = [], [], i
        while True:
            if j < len(toks) and toks[j][0] in ("str", "tpl"):
                parts.append(j); texts.append(toks[j][1]); j += 1
            elif operand(toks, j) > j:
                texts.append("x"); j = operand(toks, j)
            else:
                break
            if j < len(toks) and toks[j][:2] == ("op", "+"): j += 1
            else: break
        if not parts or any(p in used for p in parts): continue
        used.update(parts)
        out.append(("".join(texts), toks[parts[0]][2], len(texts) > 1, toks[parts[0]][0], [toks[p][1] for p in parts]))
    return out


def is_prose(text, joined, kind):
    if kind == "tpl" or joined: return len(text.split()) >= 2
    return len(text.split()) >= 2 and not re.search(r"[$={}\\]", text)


def sentences(text):
    return 1 + len(re.findall(r"[.!?]\s+\S", text.strip()))


def over(text, limit_chars=None):
    words = len(text.split())
    why = []
    if words > MAX_WORDS: why.append(f"{words} words")
    if sentences(text) > 1: why.append("two sentences")
    if limit_chars and len(text) > limit_chars: why.append(f"{len(text)} characters")
    return why


def scan_qml(path, rel, allow):
    src = open(path, encoding="utf-8").read()
    found, hit = [], set()
    for text, line, joined, kind, pieces in literals(src):
        fragment = not joined and kind == "str" and text.startswith(" ") and re.search(r"[A-Za-z]", text)
        if not is_prose(text, joined, kind) and not fragment: continue
        why = []
        if rel in TIP_FILES:
            if len(text) > TIP_MAX: why.append(f"{len(text)} characters")
            if text.rstrip().endswith("."): why.append("a full stop")
        else:
            why = over(text)
        if not joined and kind == "str" and (fragment or text[:1].islower()): why.append("a fragment")
        if (rel, text) in allow:
            hit.add((rel, text)); why = []
        if why: found.append({"file": rel, "line": line, "text": text, "why": why, "pieces": pieces})
    return found, hit


def expand(s):
    """A bash string with its expansions as one word each: $name, ${..}, $(..)."""
    out, i = [], 0
    while i < len(s):
        if s.startswith("$(", i):
            depth, j = 0, i + 1
            while j < len(s):
                depth += s[j] == "("; depth -= s[j] == ")"
                j += 1
                if depth == 0: break
            out.append("xxxxxxxx"); i = j
        elif s[i] == "$":
            m = re.match(r"\$(\{[^}]*\}|\w+)", s[i:])
            out.append("xxxxxxxx"); i += len(m.group(0)) if m else 1
        elif s[i] == "\\" and i + 1 < len(s): out.append(s[i + 1]); i += 2
        else: out.append(s[i]); i += 1
    return "".join(out)


def quoted(s, i):
    """The raw text of the double-quoted word at s[i:], or None."""
    if i >= len(s) or s[i] != '"': return None
    j, depth = i + 1, 0
    while j < len(s):
        if s.startswith("$(", j): depth += 1
        elif s[j] == ")" and depth: depth -= 1
        elif s[j] == "\\": j += 1
        elif s[j] == '"' and not depth: return s[i + 1:j]
        j += 1
    return None


def scan_bash(path, rel):
    """Point titles (point <id> <severity> "<title>") and finish messages (finish <phase> <code> "<message>")."""
    found, seen = [], []
    for n, line in enumerate(open(path, encoding="utf-8").read().splitlines(), 1):
        if line.lstrip().startswith("#"): continue
        for m in re.finditer(r"(?:^|[\s{(;&|])(point|finish)\s+(\S+)\s+(\S+)\s+(?=\")", line):
            raw = quoted(line, m.end())
            if raw is None: continue
            text = expand(raw)
            if not text.strip(): continue
            seen.append((m.group(1), text))
            why = over(text, TITLE_MAX)
            if why: found.append({"file": rel, "line": n, "text": raw, "why": why, "kind": m.group(1), "pieces": [raw]})
    return found, seen


def load_allow(path):
    allow = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            if not line.strip() or line.startswith("#"): continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2: allow[(parts[0], parts[1])] = parts[2] if len(parts) > 2 else ""
    return allow


def main(argv):
    args, root, allow_file, removed, bash, files = list(argv), None, None, None, [], []
    while args:
        a = args.pop(0)
        if a == "--root": root = args.pop(0)
        elif a == "--allow": allow_file = args.pop(0)
        elif a == "--removed": removed = args.pop(0)
        elif a == "--bash": bash.append(args.pop(0))
        else: files.append(a)
    root = os.path.abspath(root or os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    allow = load_allow(allow_file) if allow_file else {}
    explicit = bool(files or bash)
    names = files or ([] if bash else [f for f in SCANNED if os.path.exists(os.path.join(root, f))])
    if not explicit and os.path.exists(os.path.join(root, BASH_SCRIPT)): bash = [BASH_SCRIPT]
    offenders, hit, wraps, captions = [], set(), 0, 0
    for rel in names:
        found, h = scan_qml(os.path.join(root, rel), rel, allow)
        offenders += found; hit |= h
        if rel in RATCHETED:
            src = re.sub(r"//[^\n]*", "", open(os.path.join(root, rel), encoding="utf-8").read())
            wraps += len(re.findall(r"\bwrapMode:", src)); captions += len(re.findall(r"Style\.font\.caption", src))
    bash_found, titles = [], 0
    for rel in bash:
        f, seen = scan_bash(os.path.join(root, rel), rel)
        bash_found += f; titles += len(seen)
    # An allowed literal that is gone is stale; in a default run so is one whose file is no longer scanned.
    stale = [f"{k[0]}\t{k[1]}" for k in allow if k not in hit and (not explicit or k[0] in names)]
    old = []
    if removed:
        olds = [l.strip() for l in open(removed, encoding="utf-8") if l.strip() and not l.startswith("#")]
        skip = {os.path.realpath(removed), os.path.realpath(os.path.join(root, "dev/strings.sh"))}
        for top in ("dev", "bin", "README.md"):
            base = os.path.join(root, top)
            walk = [(root, [], [top])] if os.path.isfile(base) else os.walk(base)
            for d, dirs, fs in walk:
                dirs[:] = [x for x in dirs if x not in ("local", "__pycache__")]
                for f in fs:
                    path = os.path.join(d, f)
                    if os.path.realpath(path) in skip or f.endswith((".png", ".qsb", ".pyc")): continue
                    try: text = open(path, encoding="utf-8").read()
                    except (UnicodeDecodeError, OSError): continue
                    old += [{"file": os.path.relpath(path, root), "text": o} for o in olds if o in text]
    print(json.dumps({"offenders": offenders, "bash": bash_found, "stale": stale, "wraps": wraps,
                      "captions": captions, "old": old, "titles": titles, "scanned": names}))


if __name__ == "__main__":
    main(sys.argv[1:])
