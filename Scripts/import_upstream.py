"""Import redistributable resources from the pinned Android source."""
import ast
import json
import re
import shutil
import sqlite3
import sys
import unicodedata
from pathlib import Path

source = Path(sys.argv[1])
root = Path(__file__).resolve().parents[1]
resources = root / 'KeyboardData'
resources.mkdir(exist_ok=True)
android = source / 'app/src/main'
kotlin = android / 'java/com/expressive/keyboard'
assets = android / 'assets'

def arguments(source):
    tokens = re.finditer(r'"(?:\\.|[^"\\])*"|\(|\)|,|//[^\n]*|/\*[\s\S]*?\*/|[^"(),/]+|/', source)
    level, part = 0, ''
    for t in tokens:
        s = t.group()
        if s.startswith(('//', '/*')):
            continue
        if s == '(':
            level += 1
        if s == ')':
            level -= 1
        if level == 0 and s == ',':
            if part.strip():
                yield part.strip()
            part = ''
        else:
            part += s
    if part.strip():
        yield part.strip()

constants = {}
def value(s):
    if s.startswith('listOf('):
        return [value(x) for x in arguments(s[7:-1])]
    if s in constants:
        return constants[s]
    if s.startswith('Composer.'):
        return s.split('.')[1].lower()
    if s in ('null', 'true', 'false'):
        return json.loads(s)
    try:
        return ast.literal_eval(s)
    except (ValueError, SyntaxError):
        if '+' in s:
            return ''.join(value(x.strip()) for x in s.split('+'))
        raise ValueError(s)

def row(s):
    return s.split() if ' ' in s else list(s)

def layout(id, label, space, title, locale, rows, accents='', shift='', dict=None, hasCase=True,
           composer='none', autoCorrect=True, rtl=False):
    return {'id': id, 'label': label, 'space': space, 'title': title, 'locale': locale,
            'rows': [row(r) for r in rows], 'accents': {a[0]: list(a[1:]) for a in accents.split()},
            'shift': {a[0]: a[1:] for a in shift.split()}, 'dictionary': dict,
            'hasCase': hasCase, 'composer': composer, 'autoCorrect': autoCorrect, 'rtl': rtl}

def indic(id, label, space, title, locale, offset, dictionary):
    def convert(s):
        tokens = [''.join(chr(ord(c) + offset) if 0x900 <= ord(c) <= 0x97f else c for c in t) for t in s.split()]
        return ' '.join(t for t in tokens if all(unicodedata.category(c) != 'Cn' for c in t))
    return layout(id, label, space, title, locale, [convert(r) for r in constants['INSCRIPT_ROWS']],
                  shift=convert(constants['INSCRIPT_SHIFT']), dict=dictionary, hasCase=False)

def parse(s):
    if s in constants:
        return constants[s]
    name, call = s.split('(', 1)
    args, kwargs = [], {}
    for arg in arguments(call[:-1]):
        kw = re.match(r'^(\w+)\s*=\s*([\s\S]*)$', arg)
        if kw:
            kwargs[kw[1]] = value(kw[2])
        else:
            args.append(value(arg))
    if name == 'L':
        kwargs.setdefault('dict', args[0])
        return layout(*args, **kwargs)
    assert name == 'indic', name
    return indic(*args, **kwargs)

prefix, listing = (kotlin / 'Languages.kt').read_text().split('val builtIn: List<KeyboardLanguage> = listOf(', 1)
definition = '    ' + prefix[prefix.index('private val QWERTY ='):]
pattern = r'(?m)^    (?:private )?(?:const )?val (\w+) = ((?:listOf|L)\([\s\S]*?\)(?=\n|$)|"[^"\n]*")'
for match in re.finditer(pattern, definition):
    name, expression = match.groups()
    constants[name] = parse(expression) if expression.startswith('L(') else value(expression)
layouts = [parse(item) for item in arguments(listing.split('\n    )', 1)[0])]
assert len(layouts) >= 90 and len({l['id'] for l in layouts}) == len(layouts)
(resources / 'layouts.json').write_text(json.dumps(layouts, ensure_ascii=False, indent=2))
for name in ('emoji', 'plugins'):
    shutil.copytree(assets / name, resources / name, dirs_exist_ok=True)
shutil.copyfile(source / 'LICENSE', root / 'LICENSE')
shutil.copyfile(source / 'PLUGINS.md', root / 'PLUGINS-Android.md')

db = resources / 'lexicon.sqlite3'
db.unlink(missing_ok=True)
with sqlite3.connect(db) as conn:
    conn.executescript('''
    CREATE TABLE entries (lang TEXT, input TEXT, output TEXT, rank INTEGER, PRIMARY KEY(lang,input,output)) WITHOUT ROWID;
    CREATE TABLE glide (lang TEXT, path TEXT, word TEXT, rank INTEGER, PRIMARY KEY(lang,path,word)) WITHOUT ROWID;
    CREATE TABLE typo (lang TEXT, input TEXT, output TEXT, PRIMARY KEY(lang,input)) WITHOUT ROWID;
    CREATE TABLE context (lang TEXT, input TEXT, output TEXT, rank INTEGER, PRIMARY KEY(lang,input,output)) WITHOUT ROWID;
    ''')
    for name in ('en', 'ru', 'am'):
        files = [assets / 'dict' / (name + suffix + '.txt') for suffix in ('', '_more', '_names')]
        words = dict.fromkeys(line.strip().split()[0].lower() for file in files if file.exists()
                              for line in file.read_text().splitlines() if line.strip() and not line.startswith('#'))
        conn.executemany('INSERT OR IGNORE INTO entries VALUES (?,?,?,?)',
                         ((name, w, w, i) for i, w in enumerate(words)))
        conn.executemany('INSERT OR IGNORE INTO glide VALUES (?,?,?,?)',
                         ((name, re.sub(r'(.)\1+', r'\1', w), w, i) for i, w in enumerate(words) if len(w) >= 2 and w.isalpha()))
        file = assets / 'dict' / (name + '_typos.txt')
        if file.exists():
            conn.executemany('INSERT OR IGNORE INTO typo VALUES (?,?,?)',
                             ((name, *s[:2]) for line in file.read_text().splitlines()
                              if not line.startswith('#') and len(s := line.split()) >= 2))
        for suffix in ('_bi', '_tri'):
            file = assets / 'dict' / (name + suffix + '.txt')
            if not file.exists():
                continue
            rows = []
            for line in file.read_text().splitlines():
                fields = line.split()
                width = 1 if suffix == '_bi' else 2
                for token in fields[width:]:
                    word, _, rank = token.rpartition('/')
                    if word and rank.isdigit():
                        rows.append((name, ' '.join(fields[:width]), word, int(rank)))
            conn.executemany('INSERT OR IGNORE INTO context VALUES (?,?,?,?)', rows)
    for name in ('zh_cn', 'zh_tw'):
        conn.executemany('INSERT OR IGNORE INTO entries VALUES (?,?,?,?)',
                         ((name, reading, word, i) for i, line in enumerate((assets/'zh'/f'{name}.txt').read_text().splitlines())
                          if len(fields := line.split('\t')) >= 2 for word, reading in [fields[:2]]))
    conn.executemany('INSERT OR IGNORE INTO entries VALUES (?,?,?,?)',
                     (('ja', fields[0], word, index) for line in (assets/'ja'/'ja_kanji.txt').read_text().splitlines()
                      if len(fields := line.split('\t')) >= 3 for index, word in enumerate(fields[2:])))
    conn.execute('PRAGMA optimize')
print(f'{len(layouts)} layouts, {db.stat().st_size:,} bytes of dictionaries')
