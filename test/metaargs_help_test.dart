import 'package:metaargs/src/metaargs.dart';
import 'package:metaargs/src/metaargs_builder.dart' show parseInt;
import 'package:metaargs/src/metaargs_help.dart';
import 'package:metaargs/src/result.dart';
import 'package:test/test.dart';

void _noop(
  MetaArgs m,
  MetaCmdLeaf mc,
  ParsedArgs args,
  ParsedOptions options,
) {}

MetaCmdLeaf _leaf(
  String name,
  String hint, [
  String help = '',
  Iterable<MetaOption> options = const <MetaOption>[],
]) => MetaCmdLeaf(name, hint, help, options, _noop);

MetaArgs _meta(Iterable<MetaOption> globals, Iterable<MetaCmd> commands) =>
    MetaArgs('cli', '', '', globals, commands);

void main() {
  group('formatHelp - no target', () {
    test('lists commands with hints', () {
      final m = _meta(const <MetaOption>[], [
        _leaf('build', 'Build the project'),
        _leaf('test', 'Run tests'),
      ]);
      final out = formatHelp(m, ParsedArgs(const []));
      expect(out, contains('Commands:'));
      expect(out, contains('build'));
      expect(out, contains('Build the project'));
      expect(out, contains('test'));
      expect(out, contains('Run tests'));
    });

    test('lists global options when present', () {
      final m = _meta([
        MetaOptionFlag(
          'verbose',
          'Be verbose',
          '',
          None<String>(),
          None<bool>(),
        ),
      ], const <MetaCmd>[]);
      final out = formatHelp(m, ParsedArgs(const []));
      expect(out, contains('Global options:'));
      expect(out, contains('--verbose'));
      expect(out, contains('Be verbose'));
    });

    test('renders program banner with name and hint', () {
      final m = MetaArgs('mycli', 'A friendly CLI', '', const <MetaOption>[], [
        _leaf('build', 'Build'),
      ]);
      final out = formatHelp(m, ParsedArgs(const []));
      expect(out, startsWith('mycli - A friendly CLI'));
    });

    test('program banner omits hint when empty', () {
      final m = _meta(const <MetaOption>[], [_leaf('build', 'Build')]);
      final out = formatHelp(m, ParsedArgs(const []));
      expect(out, startsWith('cli\n'));
      expect(out, isNot(contains('cli -')));
    });

    test('program-level help text is rendered after the banner', () {
      final m = MetaArgs(
        'mycli',
        'h',
        'Longer description goes here.',
        const <MetaOption>[],
        [_leaf('build', 'Build')],
      );
      final out = formatHelp(m, ParsedArgs(const []));
      expect(out, contains('Longer description goes here.'));
    });

    test('program-level usage line is rendered', () {
      final m = _meta(const <MetaOption>[], [_leaf('build', 'Build')]);
      final out = formatHelp(m, ParsedArgs(const []));
      expect(out, contains('Usage: cli <command> [<args>]'));
    });
  });

  group('formatHelp - known leaf target', () {
    test('header includes program name, command path, and hint', () {
      final mc = _leaf('build', 'Build the project');
      final m = _meta(const <MetaOption>[], [mc]);
      final out = formatHelp(m, ParsedArgs(const ['build']));
      expect(out, startsWith('cli build - Build the project'));
    });

    test('header omits " - <hint>" when hint is empty', () {
      final mc = _leaf('build', '');
      final m = _meta(const <MetaOption>[], [mc]);
      final out = formatHelp(m, ParsedArgs(const ['build']));
      expect(out, startsWith('cli build\n'));
      expect(out, isNot(contains('cli build -')));
    });

    test('usage line includes program name and command', () {
      final mc = _leaf('build', 'Build');
      final m = _meta(const <MetaOption>[], [mc]);
      final out = formatHelp(m, ParsedArgs(const ['build']));
      expect(out, contains('Usage: cli build'));
    });

    test('usage line shows [<options>] only when leaf has options', () {
      final withOpts = _leaf('serve', 'Serve', '', [
        MetaOptionFlag('quiet', 'Be quiet', '', None<String>(), None<bool>()),
      ]);
      final withoutOpts = _leaf('build', 'Build');
      final m = _meta(const <MetaOption>[], [withOpts, withoutOpts]);
      final outWith = formatHelp(m, ParsedArgs(const ['serve']));
      final outWithout = formatHelp(m, ParsedArgs(const ['build']));
      expect(outWith, contains('Usage: cli serve [<options>] [<args>]'));
      expect(outWithout, contains('Usage: cli build [<args>]'));
    });

    test('usage line shows [<global options>] only when globals exist', () {
      final mc = _leaf('build', 'Build');
      final withGlobals = MetaArgs(
        'cli',
        '',
        '',
        [
          MetaOptionFlag(
            'verbose',
            'Verbose',
            '',
            None<String>(),
            None<bool>(),
          ),
        ],
        [mc],
      );
      final out = formatHelp(withGlobals, ParsedArgs(const ['build']));
      expect(out, contains('Usage: cli [<global options>] build [<args>]'));
    });

    test('renders default value when Some', () {
      final mc = _leaf('serve', 'Serve', '', [
        MetaOptionSingle<int>(
          'port',
          'Port',
          '',
          None<String>(),
          parseInt,
          Some<int>(8080),
        ),
      ]);
      final m = _meta(const <MetaOption>[], [mc]);
      final out = formatHelp(m, ParsedArgs(const ['serve']));
      expect(out, contains('--port=<value>'));
      expect(out, contains('Port'));
      expect(out, contains('[default: 8080]'));
    });

    test('omits default value when None', () {
      final mc = _leaf('serve', 'Serve', '', [
        MetaOptionSingle<int>(
          'port',
          'Port',
          '',
          None<String>(),
          parseInt,
          None<int>(),
        ),
      ]);
      final m = _meta(const <MetaOption>[], [mc]);
      final out = formatHelp(m, ParsedArgs(const ['serve']));
      expect(out, isNot(contains('[default:')));
    });

    test('word-wraps long help text to provided width', () {
      final longHelp =
          'Lorem ipsum dolor sit amet consectetur adipiscing elit sed do';
      final mc = _leaf('x', 'h', longHelp);
      final m = _meta(const <MetaOption>[], [mc]);
      final out = formatHelp(m, ParsedArgs(const ['x']), width: 20);
      // Lines belonging to the wrapped help block (after header + blank).
      final lines = out.split('\n');
      expect(lines[0], 'cli x - h');
      expect(lines[1], '');
      for (var i = 2; i < lines.length; i++) {
        if (lines[i].isEmpty) break;
        expect(
          lines[i].length,
          lessThanOrEqualTo(20),
          reason: 'line exceeds width: "${lines[i]}"',
        );
      }
    });

    test('extra tokens past a leaf still render the leaf', () {
      final mc = _leaf('build', 'Build');
      final m = _meta(const <MetaOption>[], [mc]);
      final out = formatHelp(m, ParsedArgs(const ['build', 'extra']));
      expect(out, startsWith('cli build - Build'));
    });
  });

  group('formatHelp - group target', () {
    test('renders subcommands of a group', () {
      final db = MetaCmdGroup('db', 'Database tools', '', [
        _leaf('migrate', 'Apply migrations'),
        _leaf('seed', 'Seed data'),
      ]);
      final m = _meta(const <MetaOption>[], [db]);
      final out = formatHelp(m, ParsedArgs(const ['db']));
      expect(out, startsWith('cli db - Database tools'));
      expect(out, contains('Usage: cli db <subcommand>'));
      expect(out, contains('Subcommands:'));
      expect(out, contains('migrate'));
      expect(out, contains('Apply migrations'));
      expect(out, contains('seed'));
    });

    test('usage line places global options before command path', () {
      final db = MetaCmdGroup('db', 'Database tools', '', [
        _leaf('migrate', 'Apply migrations'),
      ]);
      final m = MetaArgs(
        'cli',
        '',
        '',
        [
          MetaOptionFlag(
            'verbose',
            'Verbose',
            '',
            None<String>(),
            None<bool>(),
          ),
        ],
        [db],
      );
      final out = formatHelp(m, ParsedArgs(const ['db']));
      expect(out, contains('Usage: cli [<global options>] db <subcommand>'));
    });

    test('walks nested path to a leaf', () {
      final db = MetaCmdGroup('db', 'Database tools', '', [
        _leaf('migrate', 'Apply migrations'),
      ]);
      final m = _meta(const <MetaOption>[], [db]);
      final out = formatHelp(m, ParsedArgs(const ['db', 'migrate']));
      expect(out, startsWith('cli db migrate - Apply migrations'));
      expect(out, contains('Usage: cli db migrate'));
    });
  });

  group('formatHelp - unknown target', () {
    test('top-level unknown -> error line and program help', () {
      final m = _meta(const <MetaOption>[], [_leaf('build', 'Build')]);
      final out = formatHelp(m, ParsedArgs(const ['nope']));
      expect(out, startsWith('Unknown command: nope'));
      expect(out, contains('Commands:'));
      expect(out, contains('build'));
    });

    test('nested unknown -> full path in error line', () {
      final db = MetaCmdGroup('db', 'Database tools', '', [
        _leaf('migrate', 'Apply migrations'),
      ]);
      final m = _meta(const <MetaOption>[], [db]);
      final out = formatHelp(m, ParsedArgs(const ['db', 'nope']));
      expect(out, startsWith('Unknown command: db nope'));
      expect(out, contains('Commands:'));
    });
  });
}
