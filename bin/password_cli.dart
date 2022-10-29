import 'package:args/command_runner.dart';
import 'package:password_cli/command.dart';
import 'package:password_cli/accounts.dart';
import 'package:logging/logging.dart';
import 'dart:io';

const help = "help";
const lineNumber = 'line-number';
const hint = "hint";
const userName = "user";
const password = "pass";
const accountNumber = "account";
const email = "email";
const tags = "tags";
const url = "url";
const notes = "notes";
const verbose = "verbose";
const logOption = "log";

/***
 * 
 */
void main(List<String> arguments) async {
  final log = Logger('password_cli');
  await initLogger();
  exitCode = 0; // presume success
  Accounts? accounts = await loadAccountsFromFile();
  final runner = CommandRunner(
    "bpass",
    """

Command Line Account Manager
----------------------------
""",
  )..addCommand(AddCommand(accounts));
  runner.addCommand(UpdateCommand(accounts));
  runner.addCommand(DeleteCommand(accounts));
  runner.addCommand(ListCommand(accounts));
  runner.addCommand(SearchCommand(accounts));
  runner.addCommand(PasswordCommand(accounts));
  runner.addCommand(HintCommand(accounts));
  runner.addCommand(GoogleSyncCommand(accounts, getAppDirPath()));
  runner.addCommand(CsvCommand(accounts));
  runner.argParser.addOption(password, abbr: "p", help: "account password");
  runner.argParser.addOption(userName, abbr: "u", help: "user name");
  runner.argParser.addOption(email, abbr: "e", help: "account email");
  runner.argParser.addOption(hint, abbr: "H", help: "password hint");
  runner.argParser.addOption(accountNumber, abbr: "a", help: "account number");
  runner.argParser.addOption(notes, abbr: "n", help: "account notes");
  runner.argParser.addOption(url, help: "account url");
  runner.argParser.addOption(tags,
      abbr: "t",
      help:
          "account tags for categorization and grouping, separated by commas");
  runner.argParser.addOption(logOption,
      abbr: "l", help: "increase logging output: verbose, info or warning");
  runner.argParser.addFlag(verbose, abbr: "v", help: "verbose output");

  try {
    await runner.run(arguments);
  } catch (e) {
    print(runner.usage);
  }
  exit(0);
}

Future<Accounts> loadAccountsFromFile() async {
  String jsonDocument =
      "${getAppDirPath()}${Platform.pathSeparator}accounts.json";
  //Platform.operatingSystem;
  //print("loading accounts from file: $jsonDocument");
  File file = File(jsonDocument);
  if (!file.existsSync()) {
    file.createSync();
    var sink = file.openWrite();
    sink.write('[]\n');
    // Close the IOSink to free system resources.
    await sink.close();
  }
  Accounts accounts = Accounts();
  accounts.loadFile(file);
  return accounts;
}

String getAppDirPath() {
  String? os = Platform.operatingSystem;
  String? home = "";
  Map<String, String> envVars = Platform.environment;
  if (Platform.isMacOS) {
    home = envVars['HOME'];
  } else if (Platform.isLinux) {
    home = envVars['HOME'];
  } else if (Platform.isWindows) {
    home = envVars['UserProfile'];
  }
  //stdout.writeln("home: $home");
  Directory appDir = Directory("$home${Platform.pathSeparator}.bpass");
  appDir.create();
  return "$home${Platform.pathSeparator}.bpass";
}

Future<void> initLogger() async {
  /***
  String path = getAppDirPath();
  File logFile = File("$path${Platform.pathSeparator}bpass.log");
  if (!logFile.existsSync()) {
    logFile.createSync();
  }
  ***/
  Logger.root.level = Level.OFF;
  //Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) async {
    stdout.writeln('${record.level.name}: ${record.time}: ${record.message}');
    /****
    File logFile = File("$path${Platform.pathSeparator}bpass.log");
    await logFile.writeAsString(
        '${record.level.name}: ${record.time}: ${record.message}',
        mode: FileMode.append,
        flush: true);
        ***/
  });
}
