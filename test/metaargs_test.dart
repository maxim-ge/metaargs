import 'package:metaargs/src/metaargs.dart';
import 'package:metaargs/src/metaargs_builder.dart';
import 'package:metaargs/src/metaargs_impl.dart';
import 'package:metaargs/src/result.dart';
import 'package:test/test.dart';

void _noop(
  MetaArgs m,
  MetaCmdLeaf mc,
  ParsedArgs args,
  ParsedOptions options,
) {}

MetaArgs _treeForRouting() => buildMetaArgs(
  'cli',
  configure: (b) {
    b.globalFlag('verbose', abbr: 'v');
    b.globalFlag('quiet', abbr: 'q');
    b.globalOption<int>('jobs', abbr: 'j', parse: parseInt, defaultsTo: 4);
    b.cmd('build', run: _noop);
    b.cmdGroup(
      'db',
      subcommands: (g) {
        g.cmd(
          'migrate',
          run: _noop,
          options: (o) {
            o.flag('dry', abbr: 'd');
            o.option<String>(
              'engine',
              abbr: 'e',
              parse: parseString,
              defaultsTo: 'pg',
            );
            o.multi<String>('tag', abbr: 't', parse: parseString);
          },
        );
      },
    );
  },
);

Cmd _ok(Result<Cmd, ParseError> r) {
  expect(r, isA<Ok<Cmd, ParseError>>());
  return (r as Ok<Cmd, ParseError>).v;
}

ParseError _err(Result<Cmd, ParseError> r) {
  expect(r, isA<Err<Cmd, ParseError>>());
  return (r as Err<Cmd, ParseError>).e;
}

void main() {
  final p = DefaultArgsParser();

  group('routing', () {
    test('resolves a top-level leaf', () {
      final c = _ok(p.parse(_treeForRouting(), ['build']));
      expect(c.leaf.name, 'build');
      expect(c.args.values, isEmpty);
    });

    test('resolves a nested leaf through a group', () {
      final c = _ok(p.parse(_treeForRouting(), ['db', 'migrate']));
      expect(c.leaf.name, 'migrate');
    });

    test('unknown top-level command -> UnknownCommand', () {
      final e = _err(p.parse(_treeForRouting(), ['nope']));
      expect(e, isA<UnknownCommand>());
      expect((e as UnknownCommand).name, 'nope');
    });

    test('group with no further token -> SubcommandRequired', () {
      final e = _err(p.parse(_treeForRouting(), ['db']));
      expect(e, isA<SubcommandRequired>());
      final sr = e as SubcommandRequired;
      expect(sr.groupName, 'db');
      expect(sr.available, ['migrate']);
    });

    test('no command at all -> SubcommandRequired at top', () {
      final e = _err(p.parse(_treeForRouting(), const []));
      expect(e, isA<SubcommandRequired>());
      expect((e as SubcommandRequired).groupName, '');
    });
  });

  group('long options', () {
    test('global flag set before subcommand', () {
      final c = _ok(p.parse(_treeForRouting(), ['--verbose', 'build']));
      final m = _treeForRouting();
      final flag = m.globalOptions.whereType<MetaOptionFlag>().first;
      expect(c.options.value(flag), isTrue);
    });

    test('global option --name=value', () {
      final c = _ok(p.parse(_treeForRouting(), ['--jobs=8', 'build']));
      final jobs = _treeForRouting().globalOptions
          .whereType<MetaOptionSingle<int>>()
          .first;
      expect(c.options.value(jobs), 8);
    });

    test('global option --name value (next token)', () {
      final c = _ok(p.parse(_treeForRouting(), ['--jobs', '8', 'build']));
      final jobs = _treeForRouting().globalOptions
          .whereType<MetaOptionSingle<int>>()
          .first;
      expect(c.options.value(jobs), 8);
    });

    test('leaf option after subcommand', () {
      final c = _ok(
        p.parse(_treeForRouting(), ['db', 'migrate', '--engine=mysql']),
      );
      expect(c.leaf.name, 'migrate');
    });

    test('global option not allowed after subcommand', () {
      final e = _err(p.parse(_treeForRouting(), ['build', '--jobs=8']));
      expect(e, isA<UnknownOption>());
      expect((e as UnknownOption).name, 'jobs');
    });

    test('leaf option not allowed before subcommand', () {
      final e = _err(p.parse(_treeForRouting(), ['--dry', 'db', 'migrate']));
      expect(e, isA<UnknownOption>());
    });

    test('missing value -> MissingOptionValue', () {
      final e = _err(p.parse(_treeForRouting(), ['--jobs']));
      expect(e, isA<MissingOptionValue>());
      expect((e as MissingOptionValue).name, 'jobs');
    });

    test('invalid value -> InvalidOptionValue', () {
      final e = _err(p.parse(_treeForRouting(), ['--jobs=abc', 'build']));
      expect(e, isA<InvalidOptionValue>());
      expect((e as InvalidOptionValue).name, 'jobs');
    });

    test('unknown long option -> UnknownOption', () {
      final e = _err(p.parse(_treeForRouting(), ['--bogus', 'build']));
      expect(e, isA<UnknownOption>());
      expect((e as UnknownOption).name, 'bogus');
    });
  });

  group('multi (repeated)', () {
    test('accumulates repeated occurrences', () {
      final c = _ok(
        p.parse(_treeForRouting(), ['db', 'migrate', '--tag=a', '--tag', 'b']),
      );
      final tag = (c.leaf.options.whereType<MetaOptionMulti<String>>()).first;
      expect(c.options.value(tag), ['a', 'b']);
    });
  });

  group('positional args + --', () {
    test('positional args collected after the leaf', () {
      final c = _ok(
        p.parse(_treeForRouting(), ['build', 'file1.dart', 'file2.dart']),
      );
      expect(c.args.values, ['file1.dart', 'file2.dart']);
    });

    test('options and positional args may interleave after the leaf', () {
      final c = _ok(
        p.parse(_treeForRouting(), [
          'db',
          'migrate',
          'a.sql',
          '--dry',
          'b.sql',
        ]),
      );
      expect(c.args.values, ['a.sql', 'b.sql']);
      final dry = c.leaf.options.whereType<MetaOptionFlag>().first;
      expect(c.options.value(dry), isTrue);
    });

    test('-- switches to positional-only, even option-like tokens', () {
      final c = _ok(
        p.parse(_treeForRouting(), ['build', '--', '--jobs=8', 'x']),
      );
      expect(c.args.values, ['--jobs=8', 'x']);
    });

    test('-- before subcommand still routes correctly', () {
      // Lenient: a `--` before any subcommand turns everything positional,
      // so there is no leaf -> SubcommandRequired.
      final e = _err(p.parse(_treeForRouting(), ['--', 'build']));
      expect(e, isA<SubcommandRequired>());
    });
  });

  group('defaults', () {
    test('global default injected when not specified', () {
      final c = _ok(p.parse(_treeForRouting(), ['build']));
      final jobs = _treeForRouting().globalOptions
          .whereType<MetaOptionSingle<int>>()
          .first;
      expect(c.options.value(jobs), 4);
    });

    test('global default can be queried by option key', () {
      const jobsKey = OptionKey<int>('jobs');
      final c = _ok(p.parse(_treeForRouting(), ['build']));
      expect(c.options.value(jobsKey), 4);
    });

    test('value returns effective value including defaults', () {
      const jobsKey = OptionKey<int>('jobs');
      final defaulted = _ok(p.parse(_treeForRouting(), ['build']));
      final specified = _ok(p.parse(_treeForRouting(), ['--jobs=8', 'build']));

      expect(defaulted.options.value(jobsKey), 4);
      expect(specified.options.value(jobsKey), 8);
    });

    test('value throws when the key has no effective value', () {
      const missingKey = OptionKey<String>('missing');
      final c = _ok(p.parse(_treeForRouting(), ['build']));

      expect(() => c.options.value(missingKey), throwsStateError);
    });

    test('missing required option -> MissingRequiredOption', () {
      final m = buildMetaArgs(
        'cli',
        configure: (b) {
          b.cmd(
            'commit',
            run: _noop,
            options: (o) {
              o.requiredOption<String>('message', abbr: 'm');
            },
          );
        },
      );

      final e = _err(p.parse(m, ['commit']));
      expect(e, isA<MissingRequiredOption>());
      expect((e as MissingRequiredOption).name, 'message');
    });

    test('leaf default injected when not specified', () {
      final c = _ok(p.parse(_treeForRouting(), ['db', 'migrate']));
      final engine = c.leaf.options.whereType<MetaOptionSingle<String>>().first;
      expect(c.options.value(engine), 'pg');
    });

    test('isSpecified ignores injected defaults', () {
      const jobsKey = OptionKey<int>('jobs');
      const engineKey = OptionKey<String>('engine');
      final build = _ok(p.parse(_treeForRouting(), ['build']));
      final migrate = _ok(p.parse(_treeForRouting(), ['db', 'migrate']));

      expect(build.options.isSpecified(jobsKey), isFalse);
      expect(migrate.options.isSpecified(engineKey), isFalse);
    });

    test('isSpecified is true for explicit long options', () {
      const jobsKey = OptionKey<int>('jobs');
      const dryKey = OptionKey<bool>('dry');
      const tagKey = OptionKey<List<String>>('tag');
      final build = _ok(p.parse(_treeForRouting(), ['--jobs=8', 'build']));
      final migrate = _ok(
        p.parse(_treeForRouting(), ['db', 'migrate', '--dry', '--tag=a,b']),
      );

      expect(build.options.isSpecified(jobsKey), isTrue);
      expect(migrate.options.isSpecified(dryKey), isTrue);
      expect(migrate.options.isSpecified(tagKey), isTrue);
    });

    test('flag defaults to false when not specified', () {
      final c = _ok(p.parse(_treeForRouting(), ['db', 'migrate']));
      final dry = c.leaf.options.whereType<MetaOptionFlag>().first;
      expect(c.options.value(dry), isFalse);
      expect(c.options.isSpecified(dry), isFalse);
    });

    test('multi defaults to empty list when not specified', () {
      const tagKey = OptionKey<List<String>>('tag');
      final c = _ok(p.parse(_treeForRouting(), ['db', 'migrate']));

      expect(c.options.value(tagKey), isEmpty);
      expect(c.options.isSpecified(tagKey), isFalse);
    });
  });

  group('short options', () {
    MetaOptionFlag flag(MetaArgs m, String name) => m.globalOptions
        .whereType<MetaOptionFlag>()
        .firstWhere((o) => o.name == name);
    MetaOptionSingle<int> jobs(MetaArgs m) =>
        m.globalOptions.whereType<MetaOptionSingle<int>>().first;

    test('single short flag', () {
      final m = _treeForRouting();
      final c = _ok(p.parse(m, ['-v', 'build']));
      expect(c.options.value(flag(m, 'verbose')), isTrue);
    });

    test('bundled flags', () {
      final m = _treeForRouting();
      final c = _ok(p.parse(m, ['-vq', 'build']));
      expect(c.options.value(flag(m, 'verbose')), isTrue);
      expect(c.options.value(flag(m, 'quiet')), isTrue);
    });

    test('attached value: -j4', () {
      final m = _treeForRouting();
      final c = _ok(p.parse(m, ['-j4', 'build']));
      expect(c.options.value(jobs(m)), 4);
    });

    test('next-token value: -j 8', () {
      final m = _treeForRouting();
      final c = _ok(p.parse(m, ['-j', '8', 'build']));
      expect(c.options.value(jobs(m)), 8);
    });

    test('bundle + attached value: -vqj4', () {
      final m = _treeForRouting();
      final c = _ok(p.parse(m, ['-vqj4', 'build']));
      expect(c.options.value(flag(m, 'verbose')), isTrue);
      expect(c.options.value(flag(m, 'quiet')), isTrue);
      expect(c.options.value(jobs(m)), 4);
    });

    test('bundle + next-token value: -vqj 8', () {
      final m = _treeForRouting();
      final c = _ok(p.parse(m, ['-vqj', '8', 'build']));
      expect(c.options.value(flag(m, 'verbose')), isTrue);
      expect(c.options.value(jobs(m)), 8);
    });

    test('short leaf option after subcommand', () {
      final c = _ok(p.parse(_treeForRouting(), ['db', 'migrate', '-emysql']));
      final engine = c.leaf.options.whereType<MetaOptionSingle<String>>().first;
      expect(c.options.value(engine), 'mysql');
    });

    test('short multi via repeated -t', () {
      final c = _ok(
        p.parse(_treeForRouting(), ['db', 'migrate', '-ta', '-t', 'b']),
      );
      final tag = c.leaf.options.whereType<MetaOptionMulti<String>>().first;
      expect(c.options.value(tag), ['a', 'b']);
    });

    test('global short not allowed after subcommand', () {
      final e = _err(p.parse(_treeForRouting(), ['build', '-v']));
      expect(e, isA<UnknownOption>());
      expect((e as UnknownOption).name, 'v');
    });

    test('unknown short letter -> UnknownOption with the letter', () {
      final e = _err(p.parse(_treeForRouting(), ['-x', 'build']));
      expect(e, isA<UnknownOption>());
      expect((e as UnknownOption).name, 'x');
    });

    test('missing value at end of bundle -> MissingOptionValue', () {
      final e = _err(p.parse(_treeForRouting(), ['-j']));
      expect(e, isA<MissingOptionValue>());
      expect((e as MissingOptionValue).name, 'j');
    });

    test('invalid attached value -> InvalidOptionValue with the letter', () {
      final e = _err(p.parse(_treeForRouting(), ['-jabc', 'build']));
      expect(e, isA<InvalidOptionValue>());
      expect((e as InvalidOptionValue).name, 'j');
    });

    test('bare "-" treated as positional after a leaf', () {
      final c = _ok(p.parse(_treeForRouting(), ['build', '-']));
      expect(c.args.values, ['-']);
    });
  });

  group('flag negation and boolean values', () {
    MetaOptionFlag flag(MetaArgs m, String name) => m.globalOptions
        .whereType<MetaOptionFlag>()
        .firstWhere((o) => o.name == name);

    test('--no-<flag> sets the flag to false', () {
      final m = _treeForRouting();
      final c = _ok(p.parse(m, ['--no-verbose', 'build']));
      expect(c.options.value(flag(m, 'verbose')), isFalse);
    });

    test('--flag=true sets true', () {
      final m = _treeForRouting();
      final c = _ok(p.parse(m, ['--verbose=true', 'build']));
      expect(c.options.value(flag(m, 'verbose')), isTrue);
    });

    test('--flag=false sets false', () {
      final m = _treeForRouting();
      final c = _ok(p.parse(m, ['--verbose=false', 'build']));
      expect(c.options.value(flag(m, 'verbose')), isFalse);
    });

    test('--flag=TRUE is case-insensitive', () {
      final m = _treeForRouting();
      final c = _ok(p.parse(m, ['--verbose=TRUE', 'build']));
      expect(c.options.value(flag(m, 'verbose')), isTrue);
    });

    test('--flag=yes -> InvalidOptionValue', () {
      final e = _err(p.parse(_treeForRouting(), ['--verbose=yes', 'build']));
      expect(e, isA<InvalidOptionValue>());
      expect((e as InvalidOptionValue).name, 'verbose');
      expect(e.raw, 'yes');
    });

    test('--no-flag=true -> InvalidOptionValue (mixing forms)', () {
      final e = _err(
        p.parse(_treeForRouting(), ['--no-verbose=true', 'build']),
      );
      expect(e, isA<InvalidOptionValue>());
      expect((e as InvalidOptionValue).name, 'no-verbose');
    });

    test('--no-<non-flag> -> UnknownOption with full name', () {
      // `jobs` is a Single<int>, not a flag - negation does not apply.
      final e = _err(p.parse(_treeForRouting(), ['--no-jobs', 'build']));
      expect(e, isA<UnknownOption>());
      expect((e as UnknownOption).name, 'no-jobs');
    });
  });

  group('multi comma-split', () {
    test('long inline value: --tag=a,b,c', () {
      final c = _ok(
        p.parse(_treeForRouting(), ['db', 'migrate', '--tag=a,b,c']),
      );
      final tag = c.leaf.options.whereType<MetaOptionMulti<String>>().first;
      expect(c.options.value(tag), ['a', 'b', 'c']);
    });

    test('long next-token value: --tag a,b', () {
      final c = _ok(
        p.parse(_treeForRouting(), ['db', 'migrate', '--tag', 'a,b']),
      );
      final tag = c.leaf.options.whereType<MetaOptionMulti<String>>().first;
      expect(c.options.value(tag), ['a', 'b']);
    });

    test('short attached value: -ta,b', () {
      final c = _ok(p.parse(_treeForRouting(), ['db', 'migrate', '-ta,b']));
      final tag = c.leaf.options.whereType<MetaOptionMulti<String>>().first;
      expect(c.options.value(tag), ['a', 'b']);
    });

    test('repeated + comma-split combined are additive', () {
      final c = _ok(
        p.parse(_treeForRouting(), [
          'db',
          'migrate',
          '--tag=a,b',
          '--tag',
          'c',
        ]),
      );
      final tag = c.leaf.options.whereType<MetaOptionMulti<String>>().first;
      expect(c.options.value(tag), ['a', 'b', 'c']);
    });

    test('empty parts pass through to parse (parseString keeps "")', () {
      final c = _ok(
        p.parse(_treeForRouting(), ['db', 'migrate', '--tag=a,,b']),
      );
      final tag = c.leaf.options.whereType<MetaOptionMulti<String>>().first;
      expect(c.options.value(tag), ['a', '', 'b']);
    });
  });

  group('edge cases', () {
    test('--flag= (empty inline) on a flag -> InvalidOptionValue', () {
      final e = _err(p.parse(_treeForRouting(), ['--verbose=']));
      expect(e, isA<InvalidOptionValue>());
      expect((e as InvalidOptionValue).name, 'verbose');
      expect(e.raw, '');
    });

    test('--opt= (empty inline) on a string option keeps empty string', () {
      final c = _ok(p.parse(_treeForRouting(), ['db', 'migrate', '--engine=']));
      final engine = c.leaf.options.whereType<MetaOptionSingle<String>>().first;
      expect(c.options.value(engine), '');
    });

    test('--opt= (empty inline) on an int option -> InvalidOptionValue', () {
      final e = _err(p.parse(_treeForRouting(), ['--jobs=']));
      expect(e, isA<InvalidOptionValue>());
      expect((e as InvalidOptionValue).name, 'jobs');
      expect(e.raw, '');
    });

    test('--=value (empty name) -> UnknownOption with empty name', () {
      final e = _err(p.parse(_treeForRouting(), ['--=value']));
      expect(e, isA<UnknownOption>());
      expect((e as UnknownOption).name, '');
    });

    test('bare "-" before a leaf -> UnknownCommand("-")', () {
      final e = _err(p.parse(_treeForRouting(), ['-']));
      expect(e, isA<UnknownCommand>());
      expect((e as UnknownCommand).name, '-');
    });
  });
}
