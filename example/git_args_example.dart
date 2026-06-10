// A small example that mimics a handful of git subcommands using the standard
// `package:args` [CommandRunner]. It is equivalent to git_example.dart. Try:
//
//   dart run example/git_args_example.dart --help
//   dart run example/git_args_example.dart status
//   dart run example/git_args_example.dart add src/main.dart lib/foo.dart
//   dart run example/git_args_example.dart commit -m "first cut"
//   dart run example/git_args_example.dart log --oneline -n 3
//   dart run example/git_args_example.dart remote add origin git@github.com:me/x
//   dart run example/git_args_example.dart remote list
//
// Handlers just print what they would do; nothing touches disk.

import 'dart:io';

import 'package:args/command_runner.dart';

const commitHelp = '''
This example does not inspect a real index or write to disk. It only checks
that a message was provided and prints the commit that would be created.''';

const logHelp = '''
Use --oneline for compact output and -n/--count to control how many entries are
shown. The commits are generated sample data, not read from a repository.''';

const remoteHelp = '''
The remote commands demonstrate nested command routing. They print the action
that would be performed without changing any Git configuration.''';

const remoteAddHelp = '''
Pass the name first and the URL second, for example:
mygit remote add origin git@example.com:me/demo''';

Future<int> main(List<String> argv) async {
  final runner =
      CommandRunner<int>('mygit', 'A tiny git look-alike built on package:args')
        ..argParser.addFlag(
          'verbose',
          abbr: 'v',
          defaultsTo: false,
          negatable: false,
          help: 'Print extra information',
        )
        ..addCommand(StatusCommand())
        ..addCommand(AddCommand())
        ..addCommand(CommitCommand())
        ..addCommand(LogCommand())
        ..addCommand(RemoteCommand());

  try {
    return await runner.run(argv) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64;
  }
}

bool _verbose(Command c) => c.globalResults?.flag('verbose') ?? false;

class StatusCommand extends Command<int> {
  @override
  final name = 'status';
  @override
  final description = 'Show the working tree status';

  @override
  int run() {
    if (_verbose(this)) stderr.writeln('[verbose] running status');
    stdout.writeln('On branch main');
    stdout.writeln('nothing to commit, working tree clean');
    return 0;
  }
}

class AddCommand extends Command<int> {
  @override
  final name = 'add';
  @override
  final description = 'Add file contents to the index';

  @override
  int run() {
    final files = argResults!.rest;
    if (files.isEmpty) {
      stderr.writeln('Nothing specified, nothing added.');
      return 0;
    }
    for (final f in files) {
      stdout.writeln('added $f');
    }
    return 0;
  }
}

class CommitCommand extends Command<int> {
  @override
  final name = 'commit';
  @override
  final description = 'Record changes to the repository';
  @override
  String get usageFooter => '\n$commitHelp';

  CommitCommand() {
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'Commit message',
      mandatory: true,
    );
  }

  @override
  int run() {
    if (!argResults!.wasParsed('message')) {
      throw UsageException('Missing required option: message', usage);
    }
    final message = argResults!.option('message')!;
    if (message.isEmpty) {
      stderr.writeln('error: commit message must not be empty');
      throw UsageException('empty commit message', usage);
    }
    stdout.writeln('[main abc1234] $message');
    return 0;
  }
}

class LogCommand extends Command<int> {
  @override
  final name = 'log';
  @override
  final description = 'Show commit logs';
  @override
  String get usageFooter => '\n$logHelp';

  LogCommand() {
    argParser
      ..addFlag(
        'oneline',
        defaultsTo: false,
        negatable: false,
        help: 'Condensed output',
      )
      ..addOption(
        'count',
        abbr: 'n',
        defaultsTo: '5',
        help: 'Number of entries to show',
      );
  }

  @override
  int run() {
    final isOneline = argResults!.flag('oneline');
    final n = int.parse(argResults!.option('count')!);
    for (var i = 0; i < n; i++) {
      final sha = 'abc${1234 - i}';
      final subject = 'commit number ${n - i}';
      stdout.writeln(
        isOneline ? '$sha $subject' : 'commit $sha\n\n    $subject\n',
      );
    }
    return 0;
  }
}

class RemoteCommand extends Command<int> {
  @override
  final name = 'remote';
  @override
  final description = 'Manage set of tracked repositories';
  @override
  String get usageFooter => '\n$remoteHelp';

  RemoteCommand() {
    addSubcommand(RemoteAddCommand());
    addSubcommand(RemoteListCommand());
  }
}

class RemoteAddCommand extends Command<int> {
  @override
  final name = 'add';
  @override
  final description = 'Add a remote named <name> for <url>';
  @override
  String get usageFooter => '\n$remoteAddHelp';

  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      stderr.writeln('usage: mygit remote add <name> <url>');
      throw UsageException('remote add requires <name> <url>', usage);
    }
    stdout.writeln('added remote ${rest[0]} -> ${rest[1]}');
    return 0;
  }
}

class RemoteListCommand extends Command<int> {
  @override
  final name = 'list';
  @override
  final description = 'List configured remotes';

  @override
  int run() {
    stdout.writeln('origin  git@example.com:me/demo (fetch)');
    stdout.writeln('origin  git@example.com:me/demo (push)');
    return 0;
  }
}
