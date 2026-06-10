// A small example that mimics a handful of git subcommands using
// [ArgsRunner]. Try:
//
//   dart run example/git_example.dart --help
//   dart run example/git_example.dart status
//   dart run example/git_example.dart add src/main.dart lib/foo.dart
//   dart run example/git_example.dart commit -m "first cut"
//   dart run example/git_example.dart log --oneline -n 3
//   dart run example/git_example.dart remote add origin git@github.com:me/x
//   dart run example/git_example.dart remote list
//
// Handlers just print what they would do; nothing touches disk.

import 'dart:io';

import 'package:metaargs/metaargs.dart';

const verboseOptKey = OptionKey<bool>('verbose');
const messageOptKey = OptionKey<String>('message');
const onelineOptKey = OptionKey<bool>('oneline');
const countOptKey = OptionKey<int>('count');

const commitHelp = '''
This example does not inspect a real index or write to disk. It only checks
that a message was provided and prints the commit that would be created.
''';

const logHelp = '''
Use --oneline for compact output and -n/--count to control how many entries are
shown. The commits are generated sample data, not read from a repository.
''';

const remoteHelp = '''
The remote commands demonstrate nested command routing. They print the action
that would be performed without changing any Git configuration.
''';

const remoteAddHelp = '''
Pass the name first and the URL second, for example:
mygit remote add origin git@example.com:me/demo
''';

Future<int> main(List<String> argv) async {
  final meta = buildMetaArgs(
    'mygit',
    configure: (b) {
      b.globalFlag(
        verboseOptKey,
        abbr: 'v',
        defaultsTo: false,
        hint: 'Print extra information',
      );

      b.cmd('help', hint: 'Show this help message', run: help);

      b.cmd('status', hint: 'Show the working tree status', run: status);

      b.cmd('add', hint: 'Add file contents to the index', run: commandAdd);

      b.cmd(
        'commit',
        hint: 'Record changes to the repository',
        help: commitHelp,
        options: (o) {
          o.requiredOption<String>(
            messageOptKey,
            abbr: 'm',
            hint: 'Commit message',
          );
        },
        run: commandCommit,
      );

      b.cmd(
        'log',
        hint: 'Show commit logs',
        help: logHelp,
        options: (o) {
          o.flag(onelineOptKey, defaultsTo: false, hint: 'Condensed output');
          o.option<int>(
            countOptKey,
            abbr: 'n',
            defaultsTo: 5,
            hint: 'Number of entries to show',
          );
        },
        run: commandLog,
      );

      b.cmdGroup(
        'remote',
        hint: 'Manage set of tracked repositories',
        help: remoteHelp,
        subcommands: (g) {
          g.cmd(
            'add',
            hint: 'Add a remote named <name> for <url>',
            help: remoteAddHelp,
            run: commandRemoteAdd,
          );
          g.cmd('list', hint: 'List configured remotes', run: remoteList);
        },
      );
    },
    hint: 'A tiny git look-alike built on command_runner',
  );

  return ArgsRunner(meta).run(argv);
}

void status(
  MetaArgs m,
  MetaCmdLeaf mc,
  ParsedArgs args,
  ParsedOptions options,
) {
  if (_verbose(options)) stderr.writeln('[verbose] running status');
  stdout.writeln('On branch main');
  stdout.writeln('nothing to commit, working tree clean');
}

void commandAdd(
  MetaArgs m,
  MetaCmdLeaf mc,
  ParsedArgs args,
  ParsedOptions options,
) {
  if (args.values.isEmpty) {
    stderr.writeln('Nothing specified, nothing added.');
    return;
  }
  for (final f in args.values) {
    stdout.writeln('added $f');
  }
}

void commandCommit(
  MetaArgs m,
  MetaCmdLeaf mc,
  ParsedArgs args,
  ParsedOptions options,
) {
  final message = options.value(messageOptKey);
  if (message.isEmpty) {
    stderr.writeln('error: commit message must not be empty');
    throw StateError('empty commit message');
  }
  stdout.writeln('[main abc1234] $message');
}

void commandLog(
  MetaArgs m,
  MetaCmdLeaf mc,
  ParsedArgs args,
  ParsedOptions options,
) {
  final isOneline = options.value(onelineOptKey);
  final n = options.value(countOptKey);
  for (var i = 0; i < n; i++) {
    final sha = 'abc${1234 - i}';
    final subject = 'commit number ${n - i}';
    stdout.writeln(
      isOneline ? '$sha $subject' : 'commit $sha\n\n    $subject\n',
    );
  }
}

void commandRemoteAdd(
  MetaArgs m,
  MetaCmdLeaf mc,
  ParsedArgs args,
  ParsedOptions options,
) {
  if (args.length < 2) {
    stderr.writeln('usage: mygit remote add <name> <url>');
    throw StateError('remote add requires <name> <url>');
  }
  stdout.writeln('added remote ${args.values[0]} -> ${args.values[1]}');
}

bool _verbose(ParsedOptions opts) {
  return opts.value(verboseOptKey);
}

void remoteList(
  MetaArgs m,
  MetaCmdLeaf mc,
  ParsedArgs args,
  ParsedOptions options,
) {
  stdout.writeln('origin  git@example.com:me/demo (fetch)');
  stdout.writeln('origin  git@example.com:me/demo (push)');
}
