import 'dart:async';

import 'metaargs.dart';
import 'result.dart';

// Handler for a leaf command. May be sync (`void`) or async (`Future<void>`);
// the runner awaits the return. Throw to signal failure.
typedef Run =
    FutureOr<void> Function(
      MetaArgs m,
      MetaCmdLeaf mc,
      ParsedArgs args,
      ParsedOptions options,
    );

// Entry point: build an immutable [Meta] tree via a closure DSL.
// [name] is the program name (e.g. "mycli"); must be non-empty. [hint] is a
// one-line description, [help] is the long-form description.
// Throws [ArgumentError] on the first syntactic problem (bad name, duplicate
// name or abbr, etc.). Local checks fire eagerly at the offending builder
// call; cross-scope uniqueness is enforced once the tree is assembled.
MetaArgs buildMetaArgs(
  String name, {
  required void Function(MetaBuilder) configure,
  String hint = '',
  String help = '',
}) {
  _checkProgramName(name);
  final b = MetaBuilder._();
  configure(b);
  final m = MetaArgs(name, hint, help, b._globals, b._commands);
  _validateTree(m);
  return m;
}

// Builder for the program root: global options and top-level commands.
class MetaBuilder {
  final List<MetaOption> _globals = [];
  final List<MetaCmd> _commands = [];

  MetaBuilder._();

  void globalFlag(
    Object keyOrName, {
    String? abbr,
    String hint = '',
    String help = '',
    bool defaultsTo = false,
  }) {
    final name = _optionName<bool>(keyOrName);
    _checkFlagName(name);
    _checkAbbr(abbr);
    _globals.add(
      MetaOptionFlag(name, hint, help, _abbr(abbr), Some<bool>(defaultsTo)),
    );
  }

  void globalOption<T>(
    Object keyOrName, {
    T Function(String)? parse,
    String? abbr,
    String hint = '',
    String help = '',
    required T defaultsTo,
  }) {
    final name = _optionName<T>(keyOrName);
    _checkName(name);
    _checkAbbr(abbr);
    _globals.add(
      MetaOptionSingle<T>(
        name,
        hint,
        help,
        _abbr(abbr),
        parse ?? _defaultParse<T>(name),
        Some<T>(defaultsTo),
      ),
    );
  }

  void globalRequiredOption<T>(
    Object keyOrName, {
    T Function(String)? parse,
    String? abbr,
    String hint = '',
    String help = '',
  }) {
    final name = _optionName<T>(keyOrName);
    _checkName(name);
    _checkAbbr(abbr);
    _globals.add(
      MetaOptionSingle<T>(
        name,
        hint,
        help,
        _abbr(abbr),
        parse ?? _defaultParse<T>(name),
        None<T>(),
        true,
      ),
    );
  }

  void globalMulti<T>(
    Object keyOrName, {
    T Function(String)? parse,
    String? abbr,
    String hint = '',
    String help = '',
    List<T> defaultsTo = const [],
  }) {
    final name = _optionName<List<T>>(keyOrName);
    _checkName(name);
    _checkAbbr(abbr);
    _globals.add(
      MetaOptionMulti<T>(
        name,
        hint,
        help,
        _abbr(abbr),
        parse ?? _defaultParse<T>(name),
        Some<List<T>>(defaultsTo),
      ),
    );
  }

  void cmd(
    String name, {
    String hint = '',
    String help = '',
    void Function(OptionsBuilder)? options,
    required Run run,
  }) {
    _checkName(name);
    _commands.add(_makeLeaf(name, hint, help, options, run));
  }

  void cmdGroup(
    String name, {
    String hint = '',
    String help = '',
    required void Function(GroupBuilder) subcommands,
  }) {
    _checkName(name);
    _commands.add(_makeGroup(name, hint, help, subcommands));
  }
}

// Builder for the subcommands of a [MetaCmdGroup].
class GroupBuilder {
  final List<MetaCmd> _commands = [];

  GroupBuilder._();

  void cmd(
    String name, {
    String hint = '',
    String help = '',
    void Function(OptionsBuilder)? options,
    required Run run,
  }) {
    _checkName(name);
    _commands.add(_makeLeaf(name, hint, help, options, run));
  }

  void group(
    String name, {
    String hint = '',
    String help = '',
    required void Function(GroupBuilder) subcommands,
  }) {
    _checkName(name);
    _commands.add(_makeGroup(name, hint, help, subcommands));
  }
}

// Builder for the options of a [MetaCmdLeaf].
class OptionsBuilder {
  final List<MetaOption> _options = [];

  OptionsBuilder._();

  void flag(
    Object keyOrName, {
    String? abbr,
    String hint = '',
    String help = '',
    bool defaultsTo = false,
  }) {
    final name = _optionName<bool>(keyOrName);
    _checkFlagName(name);
    _checkAbbr(abbr);
    _options.add(
      MetaOptionFlag(name, hint, help, _abbr(abbr), Some<bool>(defaultsTo)),
    );
  }

  void option<T>(
    Object keyOrName, {
    T Function(String)? parse,
    String? abbr,
    String hint = '',
    String help = '',
    required T defaultsTo,
  }) {
    final name = _optionName<T>(keyOrName);
    _checkName(name);
    _checkAbbr(abbr);
    _options.add(
      MetaOptionSingle<T>(
        name,
        hint,
        help,
        _abbr(abbr),
        parse ?? _defaultParse<T>(name),
        Some<T>(defaultsTo),
      ),
    );
  }

  void requiredOption<T>(
    Object keyOrName, {
    T Function(String)? parse,
    String? abbr,
    String hint = '',
    String help = '',
  }) {
    final name = _optionName<T>(keyOrName);
    _checkName(name);
    _checkAbbr(abbr);
    _options.add(
      MetaOptionSingle<T>(
        name,
        hint,
        help,
        _abbr(abbr),
        parse ?? _defaultParse<T>(name),
        None<T>(),
        true,
      ),
    );
  }

  void multi<T>(
    Object keyOrName, {
    T Function(String)? parse,
    String? abbr,
    String hint = '',
    String help = '',
    List<T> defaultsTo = const [],
  }) {
    final name = _optionName<List<T>>(keyOrName);
    _checkName(name);
    _checkAbbr(abbr);
    _options.add(
      MetaOptionMulti<T>(
        name,
        hint,
        help,
        _abbr(abbr),
        parse ?? _defaultParse<T>(name),
        Some<List<T>>(defaultsTo),
      ),
    );
  }
}

// Built-in string-to-T converters for the most common option value types.
String parseString(String s) => s;
int parseInt(String s) => int.parse(s);
double parseDouble(String s) => double.parse(s);
bool parseBool(String s) {
  switch (s.toLowerCase()) {
    case 'true':
      return true;
    case 'false':
      return false;
  }
  throw FormatException('Expected true or false, got "$s"');
}

// Pick a default converter based on the static type [T]. Used by `option`,
// `globalOption`, `multi`, and `globalMulti` when the caller omits `parse:`.
// For any [T] outside the built-in set the caller must pass `parse:`
// explicitly; otherwise we throw at build time with a pointer to the field.
T Function(String) _defaultParse<T>(String optionName) {
  if (T == String) return (s) => s as T;
  if (T == int) return (s) => int.parse(s) as T;
  if (T == double) return (s) => double.parse(s) as T;
  if (T == bool) return (s) => parseBool(s) as T;
  throw ArgumentError.value(
    T,
    'T',
    'No built-in parser for $T on option "$optionName"; '
        'pass parse: <your converter>',
  );
}

Option<String> _abbr(String? abbr) =>
    abbr == null ? None<String>() : Some<String>(abbr);

String _optionName<T>(Object keyOrName) {
  if (keyOrName is String) return keyOrName;
  if (keyOrName is OptionKey<T>) return keyOrName.name;
  if (keyOrName is OptionKey) {
    throw ArgumentError.value(
      keyOrName.name,
      'keyOrName',
      'Option key has the wrong value type',
    );
  }
  throw ArgumentError.value(
    keyOrName,
    'keyOrName',
    'Expected a String or OptionKey<$T>',
  );
}

// kebab-case: lowercase letters and digits, segments joined by single dashes.
final _nameRe = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _abbrRe = RegExp(r'^[a-zA-Z0-9]$');

void _checkName(String name) {
  if (!_nameRe.hasMatch(name)) {
    throw ArgumentError.value(
      name,
      'name',
      'Name must be kebab-case: ${_nameRe.pattern}',
    );
  }
}

void _checkFlagName(String name) {
  _checkName(name);
  if (name.startsWith('no-')) {
    throw ArgumentError.value(
      name,
      'name',
      'Flag name must not start with "no-"',
    );
  }
}

void _checkAbbr(String? abbr) {
  if (abbr == null) return;
  if (!_abbrRe.hasMatch(abbr)) {
    throw ArgumentError.value(
      abbr,
      'abbr',
      'Abbreviation must be a single alphanumeric character',
    );
  }
}

// Program name is looser than command/option names: any non-empty string
// without whitespace is accepted (real binary names sometimes contain dots).
void _checkProgramName(String name) {
  if (name.isEmpty || RegExp(r'\s').hasMatch(name)) {
    throw ArgumentError.value(
      name,
      'name',
      'Program name must be non-empty and contain no whitespace',
    );
  }
}

// Cross-scope uniqueness pass. Runs once after the closure DSL completes.
// - Option long names are unique within each scope (globals; each leaf).
// - Abbreviations are unique within each scope.
// - Subcommand names are unique among siblings.
// - No top-level command shares the program name.
void _validateTree(MetaArgs m) {
  _checkOptionScope(m.globalOptions, 'global option');
  for (final c in m.commands) {
    if (c.name == m.name) {
      throw ArgumentError.value(
        c.name,
        'name',
        'Top-level command name collides with program name',
      );
    }
  }
  _checkCommands(m.commands, parentPath: '');
}

void _checkOptionScope(Iterable<MetaOption> opts, String label) {
  final names = <String>{};
  final abbrs = <String>{};
  for (final o in opts) {
    if (!names.add(o.name)) {
      throw ArgumentError.value(o.name, 'name', 'Duplicate $label name');
    }
    final a = o.abbr;
    if (a is Some<String>) {
      if (!abbrs.add(a.v)) {
        throw ArgumentError.value(a.v, 'abbr', 'Duplicate $label abbr');
      }
    }
  }
}

void _checkCommands(Iterable<MetaCmd> cmds, {required String parentPath}) {
  final names = <String>{};
  for (final c in cmds) {
    if (!names.add(c.name)) {
      throw ArgumentError.value(
        c.name,
        'name',
        'Duplicate subcommand name${parentPath.isEmpty ? '' : ' under "$parentPath"'}',
      );
    }
    final path = parentPath.isEmpty ? c.name : '$parentPath $c.name';
    switch (c) {
      case MetaCmdLeaf():
        _checkOptionScope(c.options, 'option in "$path"');
      case MetaCmdGroup():
        _checkCommands(c.subcommands, parentPath: path);
    }
  }
}

MetaCmdLeaf _makeLeaf(
  String name,
  String hint,
  String help,
  void Function(OptionsBuilder)? options,
  Run run,
) {
  final ob = OptionsBuilder._();
  if (options != null) options(ob);
  return MetaCmdLeaf(name, hint, help, ob._options, run);
}

MetaCmdGroup _makeGroup(
  String name,
  String hint,
  String help,
  void Function(GroupBuilder) subcommands,
) {
  final gb = GroupBuilder._();
  subcommands(gb);
  return MetaCmdGroup(name, hint, help, gb._commands);
}
