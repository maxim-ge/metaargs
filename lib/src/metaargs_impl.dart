import 'metaargs.dart';
import 'result.dart';

// Default parser.
// - Long forms: `--name`, `--name=value`, `--name value`.
// - Short forms: `-x`, bundled flags `-vqx`, attached value `-j4`,
//   bundle+value `-vqj4`, next-token value `-j 4` / `-vqj 4`.
// - Globals before subcommand only; leaf options after the leaf.
// - Lenient `--`: anywhere, switches to positional-only mode.
// - Multi: repeated occurrences accumulate; values are comma-split.
// - Flags accept `--no-<flag>` and `--flag=true|false` (case-insensitive).
//   Direct name lookup wins over `--no-` negation.
class DefaultArgsParser implements ArgsParser {
  @override
  Result<Cmd, ParseError> parse(MetaArgs m, List<String> args) {
    final s = _State(m);
    for (var i = 0; i < args.length; i++) {
      final tok = args[i];

      if (s.positionalOnly) {
        s.posArgs.add(tok);
        continue;
      }
      if (tok == '--') {
        s.positionalOnly = true;
        continue;
      }
      if (tok.startsWith('--')) {
        final err = _handleLong(s, args, i, tok);
        if (err != null) return Err(err);
        if (s.consumedNext) {
          i++;
          s.consumedNext = false;
        }
        continue;
      }
      if (tok.startsWith('-') && tok.length > 1) {
        final err = _handleShort(s, args, i, tok);
        if (err != null) return Err(err);
        if (s.consumedNext) {
          i++;
          s.consumedNext = false;
        }
        continue;
      }

      // Bare word
      if (s.leaf == null) {
        MetaCmd? found;
        for (final c in s.currentCommands) {
          if (c.name == tok) {
            found = c;
            break;
          }
        }
        if (found == null) return Err(UnknownCommand(tok));
        s.chain.add(found);
        if (found is MetaCmdGroup) {
          s.currentCommands = found.subcommands;
        } else {
          s.leaf = found as MetaCmdLeaf;
        }
      } else {
        s.posArgs.add(tok);
      }
    }

    if (s.leaf == null) {
      final names = s.currentCommands.map((c) => c.name).toList();
      final groupName = s.chain.isEmpty
          ? ''
          : (s.chain.last as MetaCmdGroup).name;
      return Err(SubcommandRequired(groupName, names));
    }

    final defaultsErr = _mergeDefaults(s);
    if (defaultsErr != null) return Err(defaultsErr);
    return Ok(
      Cmd(
        s.leaf!,
        ParsedOptions(s.values, s.specifiedNames),
        ParsedArgs(s.posArgs),
      ),
    );
  }
}

class _State {
  final MetaArgs m;
  Iterable<MetaCmd> currentCommands;
  final List<MetaCmd> chain = [];
  MetaCmdLeaf? leaf;
  final Map<String, Object> values = {};
  final Set<String> specifiedNames = {};
  final List<String> posArgs = [];
  bool positionalOnly = false;
  bool consumedNext = false;

  _State(this.m) : currentCommands = m.commands;

  // Lookup a long option name in the current scope (rule 5a):
  // - Before the leaf: only globals.
  // - After the leaf: only leaf options.
  MetaOption? lookupLong(String name) {
    final source = leaf == null ? m.globalOptions : leaf!.options;
    for (final o in source) {
      if (o.name == name) return o;
    }
    return null;
  }

  // Lookup an option by its single-letter abbreviation in the current scope.
  MetaOption? lookupShort(String c) {
    final source = leaf == null ? m.globalOptions : leaf!.options;
    for (final o in source) {
      final a = o.abbr;
      if (a is Some<String> && a.v == c) return o;
    }
    return null;
  }
}

ParseError? _handleLong(_State s, List<String> args, int i, String tok) {
  final raw = tok.substring(2);
  final eq = raw.indexOf('=');
  final name = eq >= 0 ? raw.substring(0, eq) : raw;
  final inlineValue = eq >= 0 ? raw.substring(eq + 1) : null;

  var opt = s.lookupLong(name);
  var negated = false;
  // `--no-<flag>` negation: only if the full name doesn't resolve and the
  // suffix names a flag in the current scope.
  if (opt == null && name.startsWith('no-')) {
    final cand = s.lookupLong(name.substring(3));
    if (cand is MetaOptionFlag) {
      opt = cand;
      negated = true;
    }
  }
  if (opt == null) return UnknownOption(name);

  switch (opt) {
    case MetaOptionFlag():
      if (negated) {
        if (inlineValue != null) return InvalidOptionValue(name, inlineValue);
        s.values[opt.name] = false;
        s.specifiedNames.add(opt.name);
        return null;
      }
      if (inlineValue != null) {
        final b = _parseBool(inlineValue);
        if (b == null) return InvalidOptionValue(name, inlineValue);
        s.values[opt.name] = b;
        s.specifiedNames.add(opt.name);
        return null;
      }
      s.values[opt.name] = true;
      s.specifiedNames.add(opt.name);
      return null;
    case MetaOptionSingle():
      final (value, err) = _readValue(args, i, name, inlineValue, s);
      if (err != null) return err;
      try {
        s.values[opt.name] = opt.parse(value!) as Object;
        s.specifiedNames.add(opt.name);
      } catch (_) {
        return InvalidOptionValue(name, value!);
      }
      return null;
    case MetaOptionMulti():
      final (value, err) = _readValue(args, i, name, inlineValue, s);
      if (err != null) return err;
      return _appendMultiCsv(opt, s, value!);
  }
}

// Handle a short-option token like `-v`, `-vqx`, `-j4`, or `-vqj4`.
// Iterates characters in the bundle; the first value-taking option consumes
// the rest of the bundle as its inline value (or the next token if empty).
ParseError? _handleShort(_State s, List<String> args, int i, String tok) {
  final body = tok.substring(1);
  for (var j = 0; j < body.length; j++) {
    final c = body[j];
    final opt = s.lookupShort(c);
    if (opt == null) return UnknownOption(c);
    switch (opt) {
      case MetaOptionFlag():
        s.values[opt.name] = true;
        s.specifiedNames.add(opt.name);
      case MetaOptionSingle():
        final rest = body.substring(j + 1);
        final inline = rest.isEmpty ? null : rest;
        final (value, err) = _readValue(args, i, c, inline, s);
        if (err != null) return err;
        try {
          s.values[opt.name] = opt.parse(value!) as Object;
          s.specifiedNames.add(opt.name);
        } catch (_) {
          return InvalidOptionValue(c, value!);
        }
        return null;
      case MetaOptionMulti():
        final rest = body.substring(j + 1);
        final inline = rest.isEmpty ? null : rest;
        final (value, err) = _readValue(args, i, c, inline, s);
        if (err != null) return err;
        return _appendMultiCsv(opt, s, value!);
    }
  }
  return null;
}

// Comma-split a raw multi-option value and append each part. Empty parts are
// passed to the converter unchanged (`parse('')` decides the outcome).
ParseError? _appendMultiCsv(MetaOptionMulti opt, _State s, String value) {
  for (final part in value.split(',')) {
    final err = opt.appendParsed(s.values, part);
    if (err != null) return err;
  }
  s.specifiedNames.add(opt.name);
  return null;
}

// Case-insensitive boolean for `--flag=true|false`. Returns null on mismatch.
bool? _parseBool(String s) {
  switch (s.toLowerCase()) {
    case 'true':
      return true;
    case 'false':
      return false;
  }
  return null;
}

(String?, ParseError?) _readValue(
  List<String> args,
  int i,
  String name,
  String? inlineValue,
  _State s,
) {
  if (inlineValue != null) return (inlineValue, null);
  if (i + 1 >= args.length) return (null, MissingOptionValue(name));
  s.consumedNext = true;
  return (args[i + 1], null);
}

ParseError? _mergeDefaults(_State s) {
  ParseError? apply(Iterable<MetaOption> opts) {
    for (final o in opts) {
      if (s.values.containsKey(o.name)) continue;
      switch (o) {
        case MetaOptionFlag(:final defaultValue):
          if (defaultValue is Some<bool>) s.values[o.name] = defaultValue.v;
        case MetaOptionSingle(:final defaultValue, :final isRequired):
          if (defaultValue is Some) {
            s.values[o.name] = defaultValue.v as Object;
          } else if (isRequired) {
            return MissingRequiredOption(o.name);
          }
        case MetaOptionMulti(:final defaultValue):
          if (defaultValue is Some<List>) {
            s.values[o.name] = defaultValue.v;
          }
      }
    }
    return null;
  }

  final globalErr = apply(s.m.globalOptions);
  if (globalErr != null) return globalErr;
  return apply(s.leaf!.options);
}
