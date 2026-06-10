import 'package:metaargs/src/metaargs.dart';
import 'package:metaargs/src/metaargs_builder.dart';
import 'package:metaargs/src/metaargs_help.dart';
import 'package:metaargs/src/result.dart';
import 'package:test/test.dart';

void _noop(
  MetaArgs m,
  MetaCmdLeaf mc,
  ParsedArgs args,
  ParsedOptions options,
) {}

void main() {
  group('buildMeta', () {
    test('builds empty tree', () {
      final m = buildMetaArgs('cli', configure: (_) {});
      expect(m.globalOptions, isEmpty);
      expect(m.commands, isEmpty);
    });

    test('adds global options of all kinds', () {
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.globalFlag('verbose', hint: 'Be verbose');
          b.globalOption<int>(
            'jobs',
            parse: parseInt,
            hint: 'Parallel jobs',
            defaultsTo: 4,
          );
          b.globalMulti<String>(
            'tag',
            parse: parseString,
            hint: 'Tag to apply',
          );
        },
      );
      final globals = m.globalOptions.toList();
      expect(globals, hasLength(3));

      final verbose = globals[0] as MetaOptionFlag;
      expect(verbose.name, 'verbose');
      expect(verbose.hint, 'Be verbose');
      expect(verbose.defaultValue, isA<Some<bool>>());
      expect((verbose.defaultValue as Some<bool>).v, isFalse);

      final jobs = globals[1] as MetaOptionSingle<int>;
      expect(jobs.name, 'jobs');
      expect(jobs.hint, 'Parallel jobs');
      expect(jobs.defaultValue, isA<Some<int>>());
      expect((jobs.defaultValue as Some<int>).v, 4);

      final tag = globals[2] as MetaOptionMulti<String>;
      expect(tag.name, 'tag');
      expect(tag.hint, 'Tag to apply');
      expect(tag.defaultValue, isA<Some<List<String>>>());
      expect((tag.defaultValue as Some<List<String>>).v, isEmpty);

      expect(verbose.abbr, isA<None<String>>());
      expect(jobs.abbr, isA<None<String>>());
      expect(tag.abbr, isA<None<String>>());
    });

    test('adds options from option keys', () {
      const verboseKey = OptionKey<bool>('verbose');
      const jobsKey = OptionKey<int>('jobs');
      const tagKey = OptionKey<List<String>>('tag');

      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.globalFlag(verboseKey, abbr: 'v');
          b.cmd(
            'build',
            run: _noop,
            options: (o) {
              o.option<int>(jobsKey, defaultsTo: 4);
              o.multi<String>(tagKey, parse: parseString);
            },
          );
        },
      );

      expect(m.globalOptions.single.name, 'verbose');
      final leaf = m.commands.single as MetaCmdLeaf;
      final opts = leaf.options.toList();
      expect(opts[0].name, 'jobs');
      expect(opts[1].name, 'tag');
    });

    test('threads abbr through globals and leaf options', () {
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.globalFlag('verbose', abbr: 'v');
          b.cmd(
            'build',
            run: _noop,
            options: (o) {
              o.flag('quiet', abbr: 'q');
              o.option<int>('jobs', parse: parseInt, abbr: 'j', defaultsTo: 4);
              o.multi<String>('tag', parse: parseString, abbr: 't');
            },
          );
        },
      );

      final verbose = m.globalOptions.first as MetaOptionFlag;
      expect(verbose.abbr, isA<Some<String>>());
      expect((verbose.abbr as Some<String>).v, 'v');

      final leaf = m.commands.first as MetaCmdLeaf;
      final opts = leaf.options.toList();
      expect((opts[0].abbr as Some<String>).v, 'q');
      expect((opts[1].abbr as Some<String>).v, 'j');
      expect((opts[2].abbr as Some<String>).v, 't');
    });

    test('builds a leaf with options', () {
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.cmd(
            'build',
            hint: 'Build',
            run: _noop,
            options: (o) {
              o.flag('quiet', hint: 'Suppress output');
              o.option<int>(
                'jobs',
                parse: parseInt,
                hint: 'Parallel jobs',
                defaultsTo: 4,
              );
            },
          );
        },
      );
      final cmds = m.commands.toList();
      expect(cmds, hasLength(1));
      final leaf = cmds[0] as MetaCmdLeaf;
      expect(leaf.name, 'build');
      expect(leaf.hint, 'Build');
      final opts = leaf.options.toList();
      expect(opts, hasLength(2));

      final quiet = opts[0] as MetaOptionFlag;
      expect(quiet.name, 'quiet');
      expect(quiet.hint, 'Suppress output');

      final jobs = opts[1] as MetaOptionSingle<int>;
      expect(jobs.name, 'jobs');
      expect(jobs.hint, 'Parallel jobs');
    });

    test('builds nested groups', () {
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.cmdGroup(
            'db',
            hint: 'DB tools',
            subcommands: (g) {
              g.cmd('migrate', hint: 'Apply migrations', run: _noop);
              g.group(
                'shards',
                hint: 'Shard ops',
                subcommands: (g2) {
                  g2.cmd('list', hint: 'List shards', run: _noop);
                },
              );
            },
          );
        },
      );
      final cmds = m.commands.toList();
      expect(cmds, hasLength(1));
      final db = cmds[0] as MetaCmdGroup;
      expect(db.name, 'db');
      expect(db.hint, 'DB tools');
      final subs = db.subcommands.toList();
      expect(subs, hasLength(2));

      final migrate = subs[0] as MetaCmdLeaf;
      expect(migrate.name, 'migrate');
      expect(migrate.hint, 'Apply migrations');

      final shards = subs[1] as MetaCmdGroup;
      expect(shards.name, 'shards');
      expect(shards.hint, 'Shard ops');
      final shardSubs = shards.subcommands.toList();
      expect(shardSubs, hasLength(1));
      final list = shardSubs[0] as MetaCmdLeaf;
      expect(list.name, 'list');
      expect(list.hint, 'List shards');
    });

    test('DSL-built tree formats the same as long-form', () {
      final dsl = buildMetaArgs(
        'cli',
        configure: (b) {
          b.globalFlag('verbose', hint: 'Be verbose');
          b.cmd(
            'build',
            hint: 'Build',
            run: _noop,
            options: (o) {
              o.option<int>(
                'jobs',
                parse: parseInt,
                hint: 'Parallel jobs',
                defaultsTo: 4,
              );
            },
          );
          b.cmdGroup(
            'db',
            hint: 'DB tools',
            subcommands: (g) {
              g.cmd('migrate', hint: 'Apply migrations', run: _noop);
            },
          );
        },
      );

      final longForm = MetaArgs(
        'cli',
        '',
        '',
        [
          MetaOptionFlag(
            'verbose',
            'Be verbose',
            '',
            None<String>(),
            Some<bool>(false),
          ),
        ],
        [
          MetaCmdLeaf('build', 'Build', '', [
            MetaOptionSingle<int>(
              'jobs',
              'Parallel jobs',
              '',
              None<String>(),
              parseInt,
              Some<int>(4),
            ),
          ], _noop),
          MetaCmdGroup('db', 'DB tools', '', [
            MetaCmdLeaf('migrate', 'Apply migrations', '', const [], _noop),
          ]),
        ],
      );

      expect(
        formatHelp(dsl, ParsedArgs(const [])),
        formatHelp(longForm, ParsedArgs(const [])),
      );
      expect(
        formatHelp(dsl, ParsedArgs(const ['build'])),
        formatHelp(longForm, ParsedArgs(const ['build'])),
      );
      expect(
        formatHelp(dsl, ParsedArgs(const ['db', 'migrate'])),
        formatHelp(longForm, ParsedArgs(const ['db', 'migrate'])),
      );
    });
  });

  group('builder validation - names', () {
    test('flag name starting with "no-" is rejected', () {
      expect(
        () =>
            buildMetaArgs('cli', configure: (b) => b.globalFlag('no-verbose')),
        throwsArgumentError,
      );
    });

    test('non-flag option may start with "no-"', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) => b.globalOption<String>(
            'no-cache',
            parse: parseString,
            defaultsTo: '',
          ),
        ),
        returnsNormally,
      );
    });

    test('uppercase name is rejected', () {
      expect(
        () => buildMetaArgs('cli', configure: (b) => b.globalFlag('Verbose')),
        throwsArgumentError,
      );
    });

    test('leading dash is rejected', () {
      expect(
        () => buildMetaArgs('cli', configure: (b) => b.globalFlag('-verbose')),
        throwsArgumentError,
      );
    });

    test('trailing dash is rejected', () {
      expect(
        () => buildMetaArgs('cli', configure: (b) => b.globalFlag('verbose-')),
        throwsArgumentError,
      );
    });

    test('double dash inside name is rejected', () {
      expect(
        () => buildMetaArgs('cli', configure: (b) => b.globalFlag('ver--bose')),
        throwsArgumentError,
      );
    });

    test('empty name is rejected', () {
      expect(
        () => buildMetaArgs('cli', configure: (b) => b.globalFlag('')),
        throwsArgumentError,
      );
    });

    test('command name follows the same rule', () {
      expect(
        () =>
            buildMetaArgs('cli', configure: (b) => b.cmd('Build', run: _noop)),
        throwsArgumentError,
      );
    });
  });

  group('builder validation - abbreviations', () {
    test('two-character abbr is rejected', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) => b.globalFlag('verbose', abbr: 'vv'),
        ),
        throwsArgumentError,
      );
    });

    test('non-alphanumeric abbr is rejected', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) => b.globalFlag('verbose', abbr: '-'),
        ),
        throwsArgumentError,
      );
    });

    test('uppercase single-letter abbr is allowed', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) => b.globalFlag('verbose', abbr: 'V'),
        ),
        returnsNormally,
      );
    });
  });

  group('builder validation - uniqueness', () {
    test('duplicate global option names are rejected', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) {
            b.globalFlag('verbose');
            b.globalOption<int>('verbose', parse: parseInt, defaultsTo: 0);
          },
        ),
        throwsArgumentError,
      );
    });

    test('duplicate global abbrs are rejected', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) {
            b.globalFlag('verbose', abbr: 'v');
            b.globalFlag('version', abbr: 'v');
          },
        ),
        throwsArgumentError,
      );
    });

    test('duplicate leaf option names are rejected', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) => b.cmd(
            'build',
            run: _noop,
            options: (o) {
              o.flag('quiet');
              o.option<int>('quiet', parse: parseInt, defaultsTo: 0);
            },
          ),
        ),
        throwsArgumentError,
      );
    });

    test('duplicate leaf option abbrs are rejected', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) => b.cmd(
            'build',
            run: _noop,
            options: (o) {
              o.flag('quiet', abbr: 'q');
              o.option<int>('jobs', parse: parseInt, abbr: 'q', defaultsTo: 0);
            },
          ),
        ),
        throwsArgumentError,
      );
    });

    test('same option name in different scopes is allowed', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) {
            b.globalFlag('verbose');
            b.cmd(
              'build',
              run: _noop,
              options: (o) {
                o.flag('verbose');
              },
            );
          },
        ),
        returnsNormally,
      );
    });

    test('duplicate top-level command names are rejected', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) {
            b.cmd('build', run: _noop);
            b.cmd('build', run: _noop);
          },
        ),
        throwsArgumentError,
      );
    });

    test('duplicate sibling subcommand names are rejected', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) => b.cmdGroup(
            'db',
            subcommands: (g) {
              g.cmd('migrate', run: _noop);
              g.cmd('migrate', run: _noop);
            },
          ),
        ),
        throwsArgumentError,
      );
    });

    test('same subcommand name under different groups is allowed', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) {
            b.cmdGroup('db', subcommands: (g) => g.cmd('list', run: _noop));
            b.cmdGroup('jobs', subcommands: (g) => g.cmd('list', run: _noop));
          },
        ),
        returnsNormally,
      );
    });

    test('top-level command colliding with program name is rejected', () {
      expect(
        () => buildMetaArgs('cli', configure: (b) => b.cmd('cli', run: _noop)),
        throwsArgumentError,
      );
    });

    test('top-level group colliding with program name is rejected', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) =>
              b.cmdGroup('cli', subcommands: (g) => g.cmd('list', run: _noop)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('builder validation - program name', () {
    test('empty program name is rejected', () {
      expect(() => buildMetaArgs('', configure: (_) {}), throwsArgumentError);
    });

    test('program name with whitespace is rejected', () {
      expect(
        () => buildMetaArgs('my cli', configure: (_) {}),
        throwsArgumentError,
      );
    });

    test('program name with dot is allowed', () {
      expect(() => buildMetaArgs('my.cli', configure: (_) {}), returnsNormally);
    });
  });

  group('default parsers', () {
    test('option<int> without parse: parses ints', () {
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.globalOption<int>('jobs', defaultsTo: 1);
        },
      );
      final jobs = m.globalOptions.first as MetaOptionSingle<int>;
      expect(jobs.parse('42'), 42);
    });

    test('option<double> without parse: parses doubles', () {
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.globalOption<double>('ratio', defaultsTo: 0);
        },
      );
      final ratio = m.globalOptions.first as MetaOptionSingle<double>;
      expect(ratio.parse('1.5'), 1.5);
    });

    test('option<String> without parse: is identity', () {
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.globalOption<String>('out', defaultsTo: '');
        },
      );
      final out = m.globalOptions.first as MetaOptionSingle<String>;
      expect(out.parse('hello'), 'hello');
    });

    test('option<bool> without parse: accepts true/false case-insensitive', () {
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.globalOption<bool>('on', defaultsTo: false);
        },
      );
      final on = m.globalOptions.first as MetaOptionSingle<bool>;
      expect(on.parse('true'), isTrue);
      expect(on.parse('FALSE'), isFalse);
      expect(() => on.parse('yes'), throwsFormatException);
    });

    test('multi<int> without parse: parses ints', () {
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.globalMulti<int>('port');
        },
      );
      final port = m.globalOptions.first as MetaOptionMulti<int>;
      expect(port.parse('80'), 80);
    });

    test('leaf option<int> without parse: parses ints', () {
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.cmd(
            'run',
            run: _noop,
            options: (o) {
              o.option<int>('count', defaultsTo: 0);
            },
          );
        },
      );
      final leaf = m.commands.first as MetaCmdLeaf;
      final count = leaf.options.first as MetaOptionSingle<int>;
      expect(count.parse('7'), 7);
    });

    test('unsupported T without parse: throws ArgumentError at build', () {
      expect(
        () => buildMetaArgs(
          'cli',
          configure: (b) {
            b.globalOption<DateTime>('when', defaultsTo: DateTime(0));
          },
        ),
        throwsArgumentError,
      );
    });
  });
}
