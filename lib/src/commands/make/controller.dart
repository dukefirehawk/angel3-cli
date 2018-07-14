import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';
import 'package:io/ansi.dart';
import 'package:prompts/prompts.dart' as prompts;
import 'package:recase/recase.dart';
import '../../util.dart';
import 'maker.dart';

class ControllerCommand extends Command {
  @override
  String get name => 'controller';

  @override
  String get description => 'Generates a controller class.';

  ControllerCommand() {
    argParser
      ..addFlag('websocket',
          abbr: 'w',
          help:
              'Generates a WebSocketController, instead of an HTTP controller.',
          negatable: false)
      ..addOption('name',
          abbr: 'n', help: 'Specifies a name for the model class.')
      ..addOption('output-dir',
          help: 'Specifies a directory to create the controller class in.',
          defaultsTo: 'lib/src/controllers');
  }

  @override
  run() async {
    var pubspec = await loadPubspec();
    String name;
    if (argResults.wasParsed('name')) name = argResults['name'] as String;

    if (name?.isNotEmpty != true) {
      name = prompts.get('Name of controller class');
    }

    List<MakerDependency> deps = [
      const MakerDependency('angel_framework', '^1.0.0')
    ];

    // ${pubspec.name}.src.models.${rc.snakeCase}

    var rc = new ReCase(name);
    var controllerLib = new Library((controllerLib) {
      if (argResults['websocket'] as bool) {
        deps.add(const MakerDependency('angel_websocket', '^1.0.0'));
        controllerLib.directives
            .add(new Directive.import('package:angel_websocket/server.dart'));
      } else {
        controllerLib.directives.add(new Directive.import(
            'package:angel_framework/angel_framework.dart'));
      }

      controllerLib.body.add(new Class((clazz) {
        clazz
          ..name = '${rc.pascalCase}Controller'
          ..extend = refer(argResults['websocket'] as bool
              ? 'WebSocketController'
              : 'Controller');

        if (argResults['websocket'] as bool) {
          clazz.methods.add(new Method((meth) {
            meth
              ..name = 'hello'
              ..returns = refer('void')
              ..annotations.add(refer('ExposeWs')
                  .constInstance([literal('get_${rc.snakeCase}')]))
              ..requiredParameters.add(new Parameter((b) => b
                ..name = 'socket'
                ..type = refer('WebSocketContext')))
              ..body = new Block((block) {
                block.addExpression(refer('socket').property('send').call([
                  literal('got_${rc.snakeCase}'),
                  literalMap({'message': literal('Hello, world!')}),
                ]));
              });
          }));
        } else {
          clazz
            ..annotations.add(
                refer('Expose').constInstance([literal('/${rc.snakeCase}')]))
            ..methods.add(new Method((meth) {
              meth
                ..name = 'hello'
                ..returns = refer('String')
                ..body = literal('Hello, world').returned.statement
                ..annotations.add(refer('Expose').constInstance([
                  literal('/'),
                ]));
            }));
        }
      }));
    });

    var outputDir = new Directory.fromUri(
        Directory.current.uri.resolve(argResults['output-dir'] as String));
    var controllerFile =
        new File.fromUri(outputDir.uri.resolve('${rc.snakeCase}.dart'));
    if (!await controllerFile.exists())
      await controllerFile.create(recursive: true);
    await controllerFile.writeAsString(new DartFormatter()
        .format(controllerLib.accept(new DartEmitter()).toString()));

    print(green.wrap(
        '$checkmark Created controller file "${controllerFile.absolute.path}"'));

    if (deps.isNotEmpty) await depend(deps);
  }
}