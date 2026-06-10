import "metaargs.dart";
import "result.dart";

// Default text width when no explicit width is provided.
const int _defaultWidth = 80;

// MetaCmdLeaf.run-shaped entry point. Walks args as a command path.
void help(MetaArgs m, MetaCmdLeaf mc, ParsedArgs args, ParsedOptions options) {
  print(formatHelp(m, args));
}

// Pure, testable entry point. Returns the full help text.
// Walks [args] as a command path through groups; extra tokens past a leaf
// are treated as the leaf's positional args (leaf help is still rendered).
String formatHelp(MetaArgs m, ParsedArgs args, {int width = _defaultWidth}) {
  final tokens = args.values;
  if (tokens.isEmpty) return _formatProgramHelp(m, width: width);

  Iterable<MetaCmd> current = m.commands;
  final chain = <MetaCmd>[];
  for (final tok in tokens) {
    MetaCmd? found;
    for (final c in current) {
      if (c.name == tok) {
        found = c;
        break;
      }
    }
    if (found == null) {
      return 'Unknown command: ${tokens.join(' ')}\n\n'
          '${_formatProgramHelp(m, width: width)}';
    }
    chain.add(found);
    if (found is MetaCmdGroup) {
      current = found.subcommands;
    } else {
      break; // leaf reached; remaining tokens are positional args
    }
  }

  final last = chain.last;
  return switch (last) {
    MetaCmdLeaf() => _formatLeafHelp(m, chain, last, width: width),
    MetaCmdGroup() => _formatGroupHelp(m, chain, last, width: width),
  };
}

String _formatProgramHelp(MetaArgs m, {int width = _defaultWidth}) {
  final b = StringBuffer();
  _writeBanner(b, m.name, m.hint);
  _writeBlock(b, m.help, width);
  _writeUsage(b, _programUsage(m));
  if (m.commands.isNotEmpty) {
    b.writeln();
    b.writeln('Commands:');
    _writeCommandList(b, m.commands);
  }
  if (m.globalOptions.isNotEmpty) {
    b.writeln();
    b.writeln('Global options:');
    _writeOptions(b, m.globalOptions);
  }
  return b.toString().trimRight();
}

String _formatLeafHelp(
  MetaArgs m,
  List<MetaCmd> chain,
  MetaCmdLeaf mc, {
  int width = _defaultWidth,
}) {
  final b = StringBuffer();
  final path = _chainPath(m, chain);
  _writeBanner(b, path, mc.hint);
  _writeBlock(b, mc.help, width);
  _writeUsage(b, _leafUsage(m, path, mc));
  if (mc.options.isNotEmpty) {
    b.writeln();
    b.writeln('Options:');
    _writeOptions(b, mc.options);
  }
  if (m.globalOptions.isNotEmpty) {
    b.writeln();
    b.writeln('Global options:');
    _writeOptions(b, m.globalOptions);
  }
  return b.toString().trimRight();
}

String _formatGroupHelp(
  MetaArgs m,
  List<MetaCmd> chain,
  MetaCmdGroup mc, {
  int width = _defaultWidth,
}) {
  final b = StringBuffer();
  final path = _chainPath(m, chain);
  _writeBanner(b, path, mc.hint);
  _writeBlock(b, mc.help, width);
  _writeUsage(b, _groupUsage(m, path));
  if (mc.subcommands.isNotEmpty) {
    b.writeln();
    b.writeln('Subcommands:');
    _writeCommandList(b, mc.subcommands);
  }
  if (m.globalOptions.isNotEmpty) {
    b.writeln();
    b.writeln('Global options:');
    _writeOptions(b, m.globalOptions);
  }
  return b.toString().trimRight();
}

// Internals

// Render `<name>` or `<name> - <hint>` followed by a blank line.
void _writeBanner(StringBuffer b, String name, String hint) {
  b.writeln(hint.isEmpty ? name : '$name - $hint');
  b.writeln();
}

// Write a wrapped block of help text followed by a blank line.
// No-op when the text is empty.
void _writeBlock(StringBuffer b, String text, int width) {
  if (text.isEmpty) return;
  b.writeln(_wrap(text, width));
  b.writeln();
}

void _writeUsage(StringBuffer b, String line) {
  b.writeln('Usage: $line');
}

// Full command path including the program name, e.g. "mycli db migrate".
String _chainPath(MetaArgs m, List<MetaCmd> chain) =>
    '${m.name} ${chain.map((c) => c.name).join(' ')}';

String _programUsage(MetaArgs m) {
  final p = StringBuffer(m.name);
  if (m.globalOptions.isNotEmpty) p.write(' [<global options>]');
  if (m.commands.isNotEmpty) p.write(' <command>');
  p.write(' [<args>]');
  return p.toString();
}

String _groupUsage(MetaArgs m, String path) {
  final p = StringBuffer(_usagePath(m, path));
  p.write(' <subcommand>');
  return p.toString();
}

String _leafUsage(MetaArgs m, String path, MetaCmdLeaf mc) {
  final p = StringBuffer(_usagePath(m, path));
  if (mc.options.isNotEmpty) p.write(' [<options>]');
  p.write(' [<args>]');
  return p.toString();
}

String _usagePath(MetaArgs m, String path) {
  if (m.globalOptions.isEmpty) return path;
  return '${m.name} [<global options>]${path.substring(m.name.length)}';
}

int _maxLen(Iterable<String> ss) =>
    ss.fold(0, (m, s) => s.length > m ? s.length : m);

void _writeCommandList(StringBuffer b, Iterable<MetaCmd> cs) {
  final w = _maxLen(cs.map((c) => c.name));
  for (final c in cs) {
    b.writeln('  ${c.name.padRight(w)}  ${c.hint}');
  }
}

void _writeOptions(StringBuffer b, Iterable<MetaOption> opts) {
  final lefts = opts.map(_optionLeft).toList(growable: false);
  final w = _maxLen(lefts);
  var i = 0;
  for (final o in opts) {
    b.writeln('  ${lefts[i].padRight(w)}  ${_optionRight(o)}');
    i++;
  }
}

String _optionLeft(MetaOption o) => switch (o) {
  MetaOptionFlag() => '--${o.name}',
  MetaOptionSingle() => '--${o.name}=<value>',
  MetaOptionMulti() => '--${o.name}=<value>...',
};

String _optionRight(MetaOption o) {
  final def = _defaultStr(o);
  return def.isEmpty ? o.hint : '${o.hint}   [default: $def]';
}

String _defaultStr(MetaOption o) => switch (o) {
  MetaOptionFlag(:final defaultValue) => _someStr(defaultValue),
  MetaOptionSingle(:final defaultValue) => _someStr(defaultValue),
  MetaOptionMulti(:final defaultValue) => _someStr(defaultValue),
};

String _someStr<T>(Option<T> o) => switch (o) {
  None<T>() => '',
  Some<T>(:final v) => v.toString(),
};

// Word-wrap [text] to [width] columns; preserves existing newlines.
String _wrap(String text, int width) {
  if (width <= 0) return text;
  return text.split('\n').map((l) => _wrapLine(l, width)).join('\n');
}

String _wrapLine(String line, int width) {
  if (line.length <= width) return line;
  final words = line.split(' ');
  final b = StringBuffer();
  var col = 0;
  for (final w in words) {
    if (w.isEmpty) continue;
    if (col == 0) {
      b.write(w);
      col = w.length;
    } else if (col + 1 + w.length <= width) {
      b.write(' ');
      b.write(w);
      col += 1 + w.length;
    } else {
      b.write('\n');
      b.write(w);
      col = w.length;
    }
  }
  return b.toString();
}
