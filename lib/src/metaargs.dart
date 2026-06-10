import 'dart:async';
import 'dart:collection';

import "result.dart";

/*
## A minimal viable grammar (suggested baseline)

```text
args        = { globalOpt } , { commandToken , { localOpt | posArg | "--" posArgs } }
globalOpt   = "--" name [ "=" value ]
            | "--" "no-" name        (for flags)
localOpt    = same as globalOpt but resolved against leaf options
posArg      = any token after "--", or any non-"--" token after the leaf
```
*/

abstract interface class ArgsParser {
  Result<Cmd, ParseError> parse(MetaArgs m, List<String> args);
}

// ## ParseError

sealed class ParseError {}

final class UnknownCommand extends ParseError {
  final String name;
  UnknownCommand(this.name);
}

final class UnknownOption extends ParseError {
  final String name;
  UnknownOption(this.name);
}

final class MissingOptionValue extends ParseError {
  final String name;
  MissingOptionValue(this.name);
}

final class MissingRequiredOption extends ParseError {
  final String name;
  MissingRequiredOption(this.name);
}

final class InvalidOptionValue extends ParseError {
  final String name;
  final String raw;
  InvalidOptionValue(this.name, this.raw);
}

final class SubcommandRequired extends ParseError {
  final String groupName;
  final List<String> available;
  SubcommandRequired(this.groupName, this.available);
}

// ## Cmd

final class Cmd {
  // Resolved leaf command.
  final MetaCmdLeaf leaf;
  // Real options
  final ParsedOptions options;
  // Positional arguments left after options are consumed
  final ParsedArgs args;

  Cmd(this.leaf, this.options, this.args);
}

final class MetaArgs extends _MetaItem {
  final Iterable<MetaOption> globalOptions;

  // Top-level commands; may include both leaves and groups.
  final Iterable<MetaCmd> commands;

  MetaArgs(
    super.name,
    super.hint,
    super.help,
    this.globalOptions,
    this.commands,
  );
}

// Each meta item has name, hint, and help
class _MetaItem {
  final String name;
  // One-line description of the item
  final String hint;
  // Longer description of the item
  final String help;
  _MetaItem(this.name, this.hint, this.help);
}

// ## MetaCmd

sealed class MetaCmd extends _MetaItem {
  MetaCmd(super.name, super.hint, super.help);
}

final class MetaCmdLeaf extends MetaCmd {
  final Iterable<MetaOption> options;
  // Invoked by the runner when this leaf is the resolved command. Return
  // `void` for sync work or `Future<void>` for async; the runner awaits it.
  // Throw to signal failure - the runner translates exceptions into a
  // non-zero exit code.
  final FutureOr<void> Function(
    MetaArgs m,
    MetaCmdLeaf mc,
    ParsedArgs args,
    ParsedOptions options,
  )
  run;
  MetaCmdLeaf(super.name, super.hint, super.help, this.options, this.run);
}

final class MetaCmdGroup extends MetaCmd {
  final Iterable<MetaCmd> subcommands;
  MetaCmdGroup(super.name, super.hint, super.help, this.subcommands);
}

// ## ParsedOptions

class OptionKey<T> {
  final String name;
  const OptionKey(this.name);
}

final class ParsedOptions {
  final Map<String, Object> _options;
  final Set<String> _specifiedNames;

  T value<T>(OptionKey<T> key) {
    var v = _options[key.name];
    if (v == null) {
      throw StateError('No value for option: ${key.name}');
    }
    return v as T;
  }

  bool isSpecified<T>(OptionKey<T> key) => _specifiedNames.contains(key.name);

  ParsedOptions(this._options, [Set<String> specifiedNames = const <String>{}])
    : _specifiedNames = Set.unmodifiable(specifiedNames);
}

// ## ParsedArgs

final class ParsedArgs {
  final List<String> _values;

  int get length => _values.length;
  UnmodifiableListView<String> get values => UnmodifiableListView(_values);

  ParsedArgs(this._values);
}

// ## MetaOption

sealed class MetaOption<T> extends _MetaItem implements OptionKey<T> {
  final Option<String> abbr;
  MetaOption(super.name, super.hint, super.help, this.abbr);
}

final class MetaOptionFlag extends MetaOption<bool> {
  final Option<bool> defaultValue;
  MetaOptionFlag(
    super.name,
    super.hint,
    super.help,
    super.abbr,
    this.defaultValue,
  );
}

final class MetaOptionSingle<T> extends MetaOption<T> {
  final T Function(String) parse;
  final Option<T> defaultValue;
  final bool isRequired;
  MetaOptionSingle(
    super.name,
    super.hint,
    super.help,
    super.abbr,
    this.parse,
    this.defaultValue, [
    this.isRequired = false,
  ]);
}

final class MetaOptionMulti<T> extends MetaOption<List<T>> {
  final T Function(String) parse;
  final Option<List<T>> defaultValue;
  MetaOptionMulti(
    super.name,
    super.hint,
    super.help,
    super.abbr,
    this.parse,
    this.defaultValue,
  );

  // Parse [raw] and append it to the list stored under [name] in [values],
  // creating a typed List<T> on first insert. Returns an error if parsing
  // throws. Instance method so T is preserved at runtime.
  ParseError? appendParsed(Map<String, Object> values, String raw) {
    final T v;
    try {
      v = parse(raw);
    } catch (_) {
      return InvalidOptionValue(name, raw);
    }
    final existing = values[name];
    if (existing == null) {
      values[name] = <T>[v];
    } else {
      (existing as List<T>).add(v);
    }
    return null;
  }
}
