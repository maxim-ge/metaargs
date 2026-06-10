/// A small library for declaring a CLI command tree, parsing argv against it,
/// and running the resolved command's handler.
///
/// Typical use: build a [MetaArgs] tree with [buildMetaArgs], then drive it
/// with [ArgsRunner].
library;

// Model and contracts.
export 'src/metaargs.dart'
    show
        MetaArgs,
        MetaCmd,
        MetaCmdLeaf,
        MetaCmdGroup,
        MetaOption,
        MetaOptionFlag,
        MetaOptionSingle,
        MetaOptionMulti,
        OptionKey,
        ParsedArgs,
        ParsedOptions,
        Run,
        ParseError,
        UnknownCommand,
        UnknownOption,
        MissingOptionValue,
        MissingRequiredOption,
        InvalidOptionValue,
        SubcommandRequired;

// Option type referenced by the option model above. `ParseError` is surfaced
// by `MetaOptionMulti.appendParsed`; the parser itself is not part of the API.
export 'src/result.dart' show Option, Some, None;

// Builder DSL.
export 'src/metaargs_builder.dart'
    show
        buildMetaArgs,
        MetaBuilder,
        GroupBuilder,
        OptionsBuilder,
        parseString,
        parseInt,
        parseDouble,
        parseBool;

// Runner.
export 'src/metaargs_runner.dart' show ArgsRunner;

// Help rendering.
export 'src/metaargs_help.dart' show help, formatHelp;
