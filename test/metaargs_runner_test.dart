import 'package:metaargs/src/metaargs.dart';
import 'package:metaargs/src/metaargs_builder.dart';
import 'package:metaargs/src/metaargs_runner.dart';
import 'package:test/test.dart';

void main() {
  group('ArgsRunner', () {
    test('returns 0 when the handler completes', () async {
      var called = false;
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.cmd(
            'build',
            run: (m, mc, args, opts) {
              called = true;
            },
          );
        },
      );
      final r = ArgsRunner(m, err: (_) {});
      expect(await r.run(['build']), 0);
      expect(called, isTrue);
    });

    test('awaits async handlers', () async {
      var called = false;
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.cmd(
            'build',
            run: (m, mc, args, opts) async {
              await Future<void>.delayed(Duration.zero);
              called = true;
            },
          );
        },
      );
      final r = ArgsRunner(m, err: (_) {});
      expect(await r.run(['build']), 0);
      expect(called, isTrue);
    });

    test('returns 1 when the handler throws', () async {
      final errLines = <String>[];
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.cmd(
            'build',
            run: (m, mc, args, opts) {
              throw StateError('boom');
            },
          );
        },
      );
      final r = ArgsRunner(m, err: errLines.add);
      expect(await r.run(['build']), 1);
      expect(errLines.first, contains('boom'));
    });

    test('returns 64 on UnknownCommand and prints help', () async {
      final errLines = <String>[];
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.cmd('build', run: (m, mc, args, opts) {});
        },
      );
      final r = ArgsRunner(m, err: errLines.add);
      expect(await r.run(['nope']), 64);
      final joined = errLines.join('\n');
      expect(joined, contains('Unknown command: nope'));
      expect(joined, contains('Usage: cli'));
    });

    test('returns 64 on MissingOptionValue', () async {
      final errLines = <String>[];
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.cmd(
            'build',
            run: (m, mc, args, opts) {},
            options: (o) {
              o.requiredOption<String>('out', parse: parseString);
            },
          );
        },
      );
      final r = ArgsRunner(m, err: errLines.add);
      expect(await r.run(['build', '--out']), 64);
      expect(errLines.join('\n'), contains('Missing value for option: out'));
    });

    test('returns 64 on SubcommandRequired and prints program help', () async {
      final errLines = <String>[];
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.cmd('build', run: (m, mc, args, opts) {});
          b.cmd('test', run: (m, mc, args, opts) {});
        },
      );
      final r = ArgsRunner(m, err: errLines.add);
      expect(await r.run(const []), 64);
      final joined = errLines.join('\n');
      expect(joined, contains('A command is required'));
      expect(joined, contains('Commands:'));
    });

    test(
      'help is anchored at the failing path (group with no subcommand)',
      () async {
        final errLines = <String>[];
        final m = buildMetaArgs(
          'cli',
          configure: (b) {
            b.cmdGroup(
              'db',
              subcommands: (g) {
                g.cmd('migrate', run: (m, mc, args, opts) {});
              },
            );
          },
        );
        final r = ArgsRunner(m, err: errLines.add);
        expect(await r.run(['db']), 64);
        final joined = errLines.join('\n');
        expect(joined, contains('Subcommand required for "db"'));
        expect(joined, contains('cli db'));
      },
    );

    test('passes parsed args and options to the handler', () async {
      var seenArgs = const <String>[];
      var seenJobs = -1;
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.cmd(
            'build',
            run: (m, mc, args, opts) {
              seenArgs = args.values;
              final jobs = mc.options
                  .whereType<MetaOptionSingle<int>>()
                  .firstWhere((o) => o.name == 'jobs');
              seenJobs = opts.value(jobs);
            },
            options: (o) {
              o.option<int>('jobs', parse: parseInt, defaultsTo: 1);
            },
          );
        },
      );
      final r = ArgsRunner(m, err: (_) {});
      expect(await r.run(['build', '--jobs=4', 'src', 'lib']), 0);
      expect(seenArgs, ['src', 'lib']);
      expect(seenJobs, 4);
    });
  });
}
