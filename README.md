# metaargs

Declarative command-line argument parsing for Dart. Build an immutable
command/option tree with a closure DSL, then parse, dispatch, and render help.

This is a self-educational project, written to explore Dart's type system,
function-type seams, and package design. It is not intended for production use.

## Example

```dart
import 'package:metaargs/metaargs.dart';

Future<int> main(List<String> argv) {
  final cli = buildMetaArgs(
    'greet',
    hint: 'A tiny example CLI',
    configure: (b) {
      b.cmd(
        'hello',
        hint: 'Print a greeting',
        options: (o) {
          o.option<String>('name', defaultsTo: 'world', hint: 'Who to greet');
        },
        run: (m, mc, args, options) {
          print('Hello, ${options.value(const OptionKey<String>('name'))}!');
        },
      );
    },
  );

  return ArgsRunner(cli).run(argv);
}
```

See `example/git_example.dart` for a larger, git-like CLI with groups,
required options, and multi-valued options.
