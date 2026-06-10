import 'dart:async';
import 'dart:io';

import 'metaargs.dart';
import 'metaargs_help.dart';
import 'metaargs_impl.dart';
import 'result.dart';

// Exit codes follow the BSD sysexits(3) convention used by most CLIs:
// - 0  : success
// - 1  : the command handler threw
// - 64 : usage error (parse failure)
const int _exitOk = 0;
const int _exitFailure = 1;
const int _exitUsage = 64;

// Output sink used by the runner to emit lines to stdout/stderr; injected so
// tests can capture output without touching the real process streams.
typedef _WriteLn = void Function(String line);

// Run a [Meta] tree against an argv vector.
//
// Resolves the leaf via [DefaultArgsParser.parse], invokes its handler (sync or
// async), and translates the outcome into a process exit code. On parse
// errors a short message is written to [err] followed by help text. On
// handler exceptions the exception is written to [err]; the stack trace is
// discarded by default (callers wanting traces should catch inside the
// handler).
class ArgsRunner {
  final MetaArgs meta;
  final _WriteLn _err;

  ArgsRunner(this.meta, {void Function(String)? err}) : _err = err ?? _stderrLn;

  Future<int> run(List<String> argv) async {
    final r = DefaultArgsParser().parse(meta, argv);
    switch (r) {
      case Ok<Cmd, ParseError>(:final v):
        try {
          await v.leaf.run(meta, v.leaf, v.args, v.options);
          return _exitOk;
        } catch (e) {
          _err('Error: $e');
          return _exitFailure;
        }
      case Err<Cmd, ParseError>(:final e):
        _err(_formatParseError(e));
        _err('');
        _err(formatHelp(meta, _pathFromArgv(argv)));
        return _exitUsage;
    }
  }

  // Walk argv as a command path until the first non-command-looking token
  // (anything starting with `-`, or any token after a leaf is reached).
  // Used to anchor help output near where the parse failed.
  ParsedArgs _pathFromArgv(List<String> argv) {
    final path = <String>[];
    Iterable<MetaCmd> current = meta.commands;
    for (final tok in argv) {
      if (tok.startsWith('-')) break;
      MetaCmd? found;
      for (final c in current) {
        if (c.name == tok) {
          found = c;
          break;
        }
      }
      if (found == null) break;
      path.add(tok);
      if (found is MetaCmdGroup) {
        current = found.subcommands;
      } else {
        break;
      }
    }
    return ParsedArgs(path);
  }
}

String _formatParseError(ParseError e) => switch (e) {
  UnknownCommand(:final name) => 'Unknown command: $name',
  UnknownOption(:final name) => 'Unknown option: $name',
  MissingOptionValue(:final name) => 'Missing value for option: $name',
  MissingRequiredOption(:final name) => 'Missing required option: $name',
  InvalidOptionValue(:final name, :final raw) =>
    'Invalid value for option $name: "$raw"',
  SubcommandRequired(:final groupName, :final available) =>
    groupName.isEmpty
        ? 'A command is required. Available: ${available.join(', ')}'
        : 'Subcommand required for "$groupName". '
              'Available: ${available.join(', ')}',
};

void _stderrLn(String s) => stderr.writeln(s);
