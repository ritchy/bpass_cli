import 'package:args/command_runner.dart';
import 'package:password_cli/accounts.dart';
import 'package:tabler/tabler.dart';
import 'package:password_cli/google_api.dart';
import 'package:logging/logging.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'console.dart';

final log = Logger('command');

class AddCommand extends BaseCommand {
  Accounts? accounts;
  AddCommand(this.accounts) : super(accounts);

  @override
  final name = 'add';

  @override
  final description = """Adds a new account entry to your account file
-----------

Example:
   dpass add BankName -e myemail@bank.com -u bankuser -H 'same as other bank' -tags 'bank, finance'

""";

  @override
  void run() async {
    Console.normal("Adding account entry");
    log.info("REST: ${argResults?.rest}");
    String? accountName = argResults?.rest[0];
    if (accountName == null) {
      throw Exception();
    }
    AccountItem? existingAccount = accounts?.findAccountItemByName(accountName);
    if (existingAccount == null) {
      accounts?.addAccount(getAccountItem(accountName, argResults?.arguments));
      await accounts?.updateAccountFiles(null);
    } else {
      Console.normal("Account with the name $accountName already exist!");
      //Console.normal(existingAccount);
    }
  }
}

class UpdateCommand extends BaseCommand {
  Accounts? accounts;
  UpdateCommand(this.accounts) : super(accounts);

  @override
  final name = 'update';

  @override
  final description = """Update an account entry in your account file
-----------

Narrows down to a single account based on provided account name and will confirm
before any delete.

""";
  //findAccountItemByName
  @override
  void run() async {
    var args = argResults?.arguments;
    String? toSearch = argResults?.rest[0];
    if (toSearch == null) {
      throw new Exception();
    }
    AccountItem? account = getSingleAccount(toSearch);
    if (account == null) {
      //print ("Unable to find single account by searching for $toSearch, try new search phrase.");
      List<AccountItem>? items =
          accounts?.getFilteredListByAccountName(toSearch);
      if (items == null) {
        Console.normal(
            "Unable to find account by searching for $toSearch, try new search phrase.");
      } else if (items.length > 1) {
        Console.normal(
            "Multiple matches coming back when searching $toSearch, try to narrow with new search.");
        printAccountItems(items);
      } else {
        account = items[0];
      }
    }
    if (account != null) {
      bool updateProvided = false;
      Console.normal("updating account $account");
      if (containsArgument(args, "user", "-u")) {
        var username = getArgumentValue(args, "user", "-u");
        account.username = username;
        updateProvided = true;
      }
      if (containsArgument(args, "email", "-e")) {
        var email = getArgumentValue(args, "email", "-e");
        account.email = email;
        updateProvided = true;
      }
      if (containsArgument(args, "pass", "-p")) {
        var password = getArgumentValue(args, "pass", "-p");
        account.password = password;
        updateProvided = true;
      }
      if (containsArgument(args, "--hint", "-H")) {
        var hint = getArgumentValue(args, "--hint", "-H");
        account.hint = hint;
        updateProvided = true;
      }
      if (containsArgument(args, "tags", "-t")) {
        var tags = getTagsArgumentValue(args, "tags", "-t");
        account.tags = tags;
        updateProvided = true;
      }
      if (containsArgument(args, "--notes", "-n")) {
        var notes = getArgumentValue(args, "--notes", "-n");
        account.notes = notes;
        updateProvided = true;
      }
      if (containsArgument(args, "--url", "----")) {
        var url = getArgumentValue(args, "--url", "----");
        account.url = url;
        updateProvided = true;
        Console.normal("got url $url");
      }

      if (updateProvided) {
        account.lastUpdated = DateTime.now();
        await accounts?.updateAccountFiles(null);
        List<AccountItem>? searchResults =
            accounts?.getFilteredListByAccountName(toSearch);
        printAccountItems(searchResults);

        //accounts?.replaceAccountItem()
        //accounts?.addAccount(getAccountItem(accountName, argResults?.arguments));
        //accounts?.saveUpdates();

      } else {
        Console.normal("Need to provide something to update!\n\nSee Usage:\n");
        throw Exception();
      }
    }
  }
}

class DeleteCommand extends BaseCommand {
  DeleteCommand(accounts) : super(accounts);

  @override
  final name = 'delete';

  @override
  final description = """Deletes an entry in your account file
-----------

Narrows down to a single account based on provided account name and will confirm
before any delete.

EXAMPLE: bpass delete MyBank
Are you sure you want to delete MyBank? y/n > y

""";

  @override
  void run() async {
    //Console.normal("Deleting account entry");
    String? toSearch = argResults?.rest[0];
    if (toSearch == null) {
      throw Exception();
    }
    AccountItem? account = getSingleAccount(toSearch);
    if (account == null) {
      //print ("Unable to find single account by searching for $toSearch, try new search phrase.");
      List<AccountItem>? items =
          accounts?.getFilteredListByAccountName(toSearch);
      if ((items == null) || (items.isEmpty)) {
        Console.normal(
            "Unable to find account by searching for $toSearch, try new search phrase.");
      } else if (items.length > 1) {
        Console.normal(
            "Multiple matches coming back when searching $toSearch, try to narrow with new search.");
        printAccountItems(items);
      } else {
        account = items[0];
      }
    }
    if (account != null) {
      //print ("found $account");
      printAccountItems([account]);
      bool answeredYes = Console.prompt(
          "Are you sure you want to delete ${account.name}? y/n > ");
      if (answeredYes) {
        Console.normal("Deleting $toSearch ...");
        accounts?.markAccountAsDeleted(account);
        await accounts?.updateAccountFiles(null);
      } else {
        Console.normal("Not Deleting..");
      }
    }
  }
}

class GoogleSyncCommand extends BaseCommand {
  Accounts? accounts;
  String? appDirPath;

  GoogleSyncCommand(this.accounts, this.appDirPath) : super(accounts);

  GoogleService? googleService;

  @override
  final name = 'sync';

  @override
  final description = """Syncs your account file with Google Drive
-----------

If you've never logged in before, you should see your browser pop up to associate
with a Google account.  Once completed, your account file will be stored in 
Google Drive for automatic syncing with other devices.

""";

  @override
  void run() async {
    try {
      Console.normal("Syncing with Google Drive ...");
      googleService = GoogleService(appDirPath);
      await googleService?.handleGoogleDriveLogin(CommandLineGooglePrompt());
      //print ("logged in, now reconcile file from drive");
      await reconcileGoogleAccountFile();
    } catch (e, stacktrace) {
      Console.normal("Something went wrong $e $stacktrace");
    }
    //exit(0);
  }

  Future<void> reconcileGoogleAccountFile() async {
    //check to see if the accounts file exist
    bool? fileExistsInDrive = await googleService?.accountsFileExistInDrive();
    if (fileExistsInDrive == null) {
      Console.normal("There was a problem with the google service");
    } else if (fileExistsInDrive) {
      String? key = googleService?.googleSettings.keyAsBase64;
      if (key != null && key.isNotEmpty) {
        //we have a file in Drive and an encryption key, good to go
        log.info("Got key, downloading file from Google Drive ... ");
        File? toReconcile = await googleService?.downloadAccountFile();
        //print ("downloaded file ${toReconcile.path}, now reconciling ...");
        if (accounts == null) {
          Console.normal(
              "Have not loaded accounts locally, unable to perform sync");
        } else {
          await accounts?.reconcileAccountsFromFile(
              toReconcile!, googleService!);
          Console.normal("Checking for access requests ...");
          await refreshAccessRequestList();
          Console.normal("Completed sync");
        }
      } else {
        //looks like we need to make a request for access
        //let's make sure we haven't already done that
        ClientAccess? outstandingRequest =
            await googleService?.findExistingRequest();
        //Console.normal("outstanding request $outstandingRequest");
        //outstandingRequest ??= null;
        if (outstandingRequest != null) {
          if (outstandingRequest.accessStatus == ClientAccess.REQUESTED) {
            Console.normal(
                "You have an outstanding request for access to existing accounts in Drive, run sync again when request has been granted.");
          } else if (outstandingRequest.accessStatus == ClientAccess.DENIED) {
            Console.normal(
                "You sent a request that was denied, run sync again if you want to send another request");
            await googleService?.removeOutstandingRequests();
            await googleService?.updateClientAccessRequests();
          } else if (outstandingRequest.accessStatus == ClientAccess.GRANTED) {
            Console.normal("Request granted .. ");
            final encryptedKey = outstandingRequest.encryptedAccessKey;
            if (encryptedKey != null) {
              //Console.normal("decrypting key...");
              await googleService?.decryptAndSaveKey(encryptedKey);
            } else {
              Console.normal("no key??");
            }
          }
        } else {
          Console.normal("-------> Request Access?");
          bool answeredYes = Console.prompt(
              "This appears to be your first sync and there's an existing file in Google Drive, would you like to request access? y/n > ");
          Console.normal("");
          if (answeredYes) {
            await googleService?.generateNewClientAccessRequest();
            await googleService?.updateClientAccessRequests();
            Console.normal(
                "sent access request, run sync again when request has been granted ...");
          } else {
            Console.normal("Not syncing ..");
          }
        }
      }
    } else {
      //no file in Drive, so we are the first one to sync, no need to reconcile, but we need to set up encryption
      String? key = googleService?.googleSettings.keyAsBase64;
      if (key != null && key.isNotEmpty) {
        //looks like we already set up encryption key, so just synd
        accounts?.updateAccountFiles(googleService);
      } else {
        Console.normal(
            "This appears to be your first sync, generating encryption keys ...");
      }
    }
  }

  Future<void> grantAccessRequest(ClientAccess accessRequest) async {
    log.finer("controller grantAccessRequest()");
    final GoogleService? gs = googleService;
    if (gs == null || !gs.loggedIn) {
      Console.warning(
          "Trying to update access in Drive file, but not logged in");
    } else {
      String? clientId = accessRequest.clientId;
      if (clientId != null) {
        Console.normal("granting access to $clientId ...");
        await gs.grantAccessRequest(clientId);
      } else {
        Console.normal(
            "This access request isn't valid, missing required client id, removing");
        await gs.removeAccessRequest(accessRequest);
      }
    }
  }

  Future<void> denyAccessRequest(ClientAccess accessRequest) async {
    final GoogleService? gs = googleService;
    if (gs == null || !gs.loggedIn) {
      Console.normal(
          "Trying to sync deny response with Drive file, but not logged in");
    } else {
      accessRequest.accessStatus = ClientAccess.DENIED;
      await gs.updateClientRequest(accessRequest);
    }
  }

  Future<void> updateOutstandingRequest(ClientAccess accessRequest) async {
    if (googleService != null) {
      if (googleService!.loggedIn) {
        Console.normal("Trying to sync with Drive file, but not logged in");
      } else {
        await googleService?.updateClientRequest(accessRequest);
      }
    }
  }

  Future<void> refreshAccessRequestList() async {
    //var outstandingRequests = [];
    ClientAccessRequests? clientAccessRequests =
        await loadOutstandingAccessRequests();
    log.info("reviewing access requests...");
    var requests = clientAccessRequests?.clientAccessRequests;
    var toProcess = [];
    if (requests != null) {
      for (ClientAccess ca in requests) {
        if (ca.accessStatus == ClientAccess.REQUESTED) {
          toProcess.add(ca);
        }
      }
      for (ClientAccess ca in toProcess) {
        log.info("Found request ${ca.clientName}");
        bool answeredYes = Console.prompt(
            'You got access request from ${ca.clientName}, would you like to approve? y/n > ');
        Console.normal("");
        if (answeredYes) {
          Console.normal("Granting access ...");
          await grantAccessRequest(ca);
        } else {
          Console.normal("Denying access..");
          await denyAccessRequest(ca);
        }
      }
    }
  }

  Future<ClientAccessRequests?> loadOutstandingAccessRequests() async {
    final GoogleService? gs = googleService;
    if (gs == null) {
      log.warning("Trying to sync with Drive file, but not logged in");
    } else {
      if (!await gs.clientAccessFileExistInDrive()) {
        Console.normal("Access file does not exist in drive, creating ...");
        await gs.generateNewClientAccessFile();
      }
      return await gs.loadClientAccessRequests();
    }
    return null;
  }
}

class CommandLineGooglePrompt extends PromptHandler {
  @override
  void handlePrompt(String url) async {
    //canLaunchUrl().then((bool result) {});
    Console.normal("Here's the URL to grant access:");
    Console.normal('  => $url');
    var result = await Process.run('open', [url]);
    Console.normal('');
  }
}

class SearchCommand extends BaseCommand {
  Accounts? accounts;
  SearchCommand(this.accounts) : super(accounts);

  @override
  final name = 'search';

  @override
  final description = """Searches for an entry in your account file
--------
  'bpass search etrade' -- will return search results of accounts with 'etrade' in their name.
  'bpass search -email bpass@email.com' -- will return all accounts you've associated this email.

  """;

  @override
  void run() {
    Console.normal("Searching ${argResults?.rest[0]} ...");
    //print ("rest ${argResults?.rest}");
    String? toSearch = argResults?.rest[0];
    if (toSearch == null) {
      toSearch = "";
    }
    List<AccountItem>? items = accounts?.getFilteredList(toSearch);
    printAccountItems(items);
    //for (AccountItem? item in items!) {
    //  print ("Item $item");
    // }
  }
}

class PasswordCommand extends BaseCommand {
  Accounts? accounts;
  PasswordCommand(this.accounts) : super(accounts);

  @override
  final name = 'pass';

  @override
  final description =
      """Prints the password and hint for the provided account name
---------
Narrows down to a single account based on provided account name and will provide
a bigger list with broader search results. Prints out the password and hint for 
the provided account name.

""";

  @override
  void run() {
    Console.normal("Searching ${argResults?.rest[0]} ...");
    //print ("rest ${argResults?.rest}");
    String? toSearch = argResults?.rest[0];
    if (toSearch == null) {
      toSearch = "";
    }
    AccountItem? account = accounts?.findAccountItemByName(toSearch);
    if (account != null) {
      var passText =
          account.password.isEmpty ? "<empty password>" : account.password;
      var hintText =
          account.hint.isEmpty ? "-hint <empty hint>" : "-hint ${account.hint}";
      Console.normal("$passText $hintText");
    } else {
      List<AccountItem>? items =
          accounts?.getFilteredListByAccountName(toSearch);
      if (items == null || items.isEmpty) {
        Console.normal("No account found matching $toSearch");
      } else if (items.length > 1) {
        Console.normal(
            "==========>> multiple accounts matching $toSearch, which one?  <<============");
        printAccountItems(items);
      } else {
        var passText =
            items[0].password.isEmpty ? "<empty password>" : items[0].password;
        var hintText =
            items[0].hint.isEmpty ? "<empty hint>" : "-hint ${items[0].hint}";
        Console.normal("$passText $hintText");
      }
    }
  }
}

class HintCommand extends BaseCommand {
  Accounts? accounts;
  HintCommand(this.accounts) : super(accounts);

  @override
  final name = 'hint';

  @override
  final description =
      """Returns the password hint(s) for the provided account name search
---------
You provide enough of an account name to narrow down and this returns 
the password hint for the provided account name.  Otherwise, you see a bigger
listing of search results that include the hint.


  """;

  @override
  void run() {
    Console.normal("Searching ${argResults?.rest[0]} ...");
    String? toSearch = argResults?.rest[0];
    if (toSearch == null) {
      toSearch = "";
    }
    AccountItem? account = accounts?.findAccountItemByName(toSearch);
    if (account != null) {
      Console.normal(account.hint.isEmpty ? "<empty hint>" : account.hint);
    } else {
      List<AccountItem>? items =
          accounts?.getFilteredListByAccountName(toSearch);
      if (items == null || items.isEmpty) {
        Console.normal("No account found matching $toSearch");
      } else if (items.length > 1) {
        Console.normal(
            "==========>> multiple accounts matching $toSearch, which one?  <<============");
        printAccountItems(items);
      } else {
        Console.normal(items[0].hint.isEmpty ? "<empty hint>" : items[0].hint);
      }
    }
  }
}

class ListCommand extends BaseCommand {
  Accounts? accounts;
  ListCommand(this.accounts) : super(accounts);

  @override
  final name = 'list';

  @override
  final description =
      """Lists entries from your account file based on filter like email or tags
---------

  You provide a search or argument like email 'list -e some@email.com' and this
  will print out all accounts associated with that email.  All entries will be listed
  with no arguement provided.

  """;

  @override
  void run() {
    var args = argResults?.arguments;
    log.info("running list command with args $args");
    if (containsArgument(args, "user", "-u")) {
      var username = getArgumentValue(args, "user", "-u");
      List<AccountItem>? items = accounts?.getFilteredListByUsername(username);
      printAccountItems(items);
    } else if (containsArgument(args, "email", "-e")) {
      var email = getArgumentValue(args, "email", "-e");
      List<AccountItem>? items = accounts?.getFilteredListByEmail(email);
      printAccountItems(items);
    } else if (containsArgument(args, "tags", "-t")) {
      List<String> tags = getTagsArgumentValue(args, "tags", "-t");
      //getArgumentValue(args, "tags", "-t").toLowerCase().split(",");
      List<AccountItem>? items = accounts?.getFilteredListByTags(tags);
      printAccountItems(items);
    } else {
      List<AccountItem>? items = accounts?.accounts;
      printAccountItems(items);
    }
  }
}

class CsvCommand extends BaseCommand {
  Accounts? accounts;
  CsvCommand(this.accounts) : super(accounts);

  @override
  final name = 'csv';

  @override
  final description = """Dumps all or filtered account entries in CSV format
---------

  You provide a search or argument like email 'csv -e some@email.com' and this
  will print out all accounts associated with that email in CSV format. All entries
  will be listed with no arguement provided.

  """;

  @override
  void run() {
    var args = argResults?.arguments;
    log.info("running list command with args $args");
    if (containsArgument(args, "user", "-u")) {
      var username = getArgumentValue(args, "user", "-u");
      List<AccountItem>? items = accounts?.getFilteredListByUsername(username);
      printAsCsv(items);
    } else if (containsArgument(args, "email", "-e")) {
      var email = getArgumentValue(args, "email", "-e");
      List<AccountItem>? items = accounts?.getFilteredListByEmail(email);
      printAsCsv(items);
    } else if (containsArgument(args, "tags", "-t")) {
      List<String> tags = getTagsArgumentValue(args, "tags", "-t");
      //List<String> tags =
      //    getArgumentValue(args, "tags", "-t").toLowerCase().split(",");
      List<AccountItem>? items = accounts?.getFilteredListByTags(tags);
      printAsCsv(items);
    } else {
      List<AccountItem>? items = accounts?.accounts;
      printAsCsv(items);
    }
  }

  void printAsCsv(List<AccountItem>? items) {
    //Console.normal("Found ${items?.length} account(s)");
    var header = [
      'Account',
      'User',
      'Hint',
      'Email',
      'Acct Number',
      'Notes',
      'Tags'
    ];
    List<List<dynamic>> data = [];
    data.add(header);
    for (AccountItem? item in items!) {
      List<String> rowData = [];
      var name = (item == null || item.name.isEmpty) ? "" : item.name;
      rowData.add(name);
      var username =
          (item == null || item.username.isEmpty) ? "" : item.username;
      rowData.add(username);
      var hint = (item == null || item.hint.isEmpty) ? "" : item.hint;
      rowData.add(hint);
      var email = (item == null || item.email.isEmpty) ? "" : item.email;
      rowData.add(email);
      var accountNumber = (item == null || item.accountNumber.isEmpty)
          ? ""
          : item.accountNumber;
      rowData.add(accountNumber);
      var notes = (item == null || item.notes.isEmpty) ? "" : item.notes;
      rowData.add(wrapText(notes, 25));
      List<String> tags = (item == null || item.tags.isEmpty) ? [] : item.tags;
      String tagString = tags.join(', ');
      rowData.add(tagString);
      data.add(rowData);
    }
    String csv = const ListToCsvConverter().convert(data);
    Console.normal(csv);
  }
}

abstract class BaseCommand extends Command {
  Accounts? accounts;
  BaseCommand(this.accounts);

  AccountItem getAccountItem(String name, List<String>? args) {
    //AccountItem accountItem = AccountItem();
    int id = DateTime.now().millisecondsSinceEpoch;
    String username = "";
    String password = "";
    String accountNumber = "";
    String url = "";
    String email = "";
    String hint = "";
    String notes = "";
    List<String> tags = [];

    //Console.normal(args);
    if (containsArgument(args, "--user", "-u")) {
      username = getArgumentValue(args, "user", "-u");
      //Console.normal("got user $username");
    }
    if (containsArgument(args, "--email", "-e")) {
      email = getArgumentValue(args, "email", "-e");
    }
    if (containsArgument(args, "--pass", "-p")) {
      password = getArgumentValue(args, "pass", "-p");
    }
    if (containsArgument(args, "--account", "-a")) {
      accountNumber = getArgumentValue(args, "account", "-a");
    }
    if (containsArgument(args, "--hint", "-H")) {
      hint = getArgumentValue(args, "--hint", "-H");
    }
    if (containsArgument(args, "--tags", "-t")) {
      tags = getTagsArgumentValue(args, "tags", "-t");
    }
    if (containsArgument(args, "--notes", "-n")) {
      notes = getArgumentValue(args, "--notes", "-n");
    }
    if (containsArgument(args, "--url", "----")) {
      url = getArgumentValue(args, "--url", "----");
      //Console.normal("got url $url");
    }
    DateTime lastUpdated = DateTime.now();
    return AccountItem(name, id, username, password, hint, email, accountNumber,
        url, notes, tags,
        lastUpdated: lastUpdated);
  }

  bool containsArgument(List<String>? args, String full, String abbr) {
    if (args != null) {
      return (args.contains(full) || args.contains(abbr));
    } else {
      return false;
    }
  }

  String getArgumentValue(List<String>? args, String full, String abbr) {
    if (args == null || args.length < 2) {
      return "";
    } else {
      for (int i = 0; i < args.length; ++i) {
        if ((args[i] == full) || (args[i] == abbr)) {
          return args[i + 1].trim();
        }
      }
    }
    return "";
  }

  List<String> getTagsArgumentValue(
      List<String>? args, String full, String abbr) {
    //Console.normal("get tags");
    List<String> toReturn = [];
    if (args == null || args.length < 2) {
      return toReturn;
    } else {
      for (int i = 0; i < args.length; ++i) {
        if ((args[i] == full) || (args[i] == abbr)) {
          //Console.normal("returning '${findAllTags(args, i + 1)}'");
          String toSplit = findAllTags(args, i + 1);
          List<String> toProcess = toSplit.toLowerCase().split(",");
          for (int i = 0; i < toProcess.length; ++i) {
            //Console.normal(
            //    "trimming each one $i: '${toProcess[i]}' = '${toProcess[i].trim()}'");
            toProcess[i] = toProcess[i].trim();
          }
          toReturn = toProcess;
        }
      }
    }
    return toReturn;
  }

  String findAllTags(List<String> args, int startingIndex) {
    if (startingIndex >= args.length) {
      return "";
    }
    String tags = "";
    for (int i = startingIndex; i < args.length; ++i) {
      if (isNotArgument(args[i])) {
        String tag = args[i].trim();
        //Console.normal("adding '$tag'");
        tags = tags + tag;
      } else {
        break;
      }
    }
    return tags;
  }

  bool isNotArgument(String arg) {
    bool notArgument = true;
    if ([
      "-u",
      "--user",
      "-e",
      "--email",
      "-p",
      "--pass",
      "-a",
      "--account",
      "-h",
      "-H",
      "--hint",
      "-t",
      "--tags",
      "-n",
      "--notes",
      "--url"
    ].any((item) => arg == item)) {
      notArgument = false;
    }
    return notArgument;
  }

  bool returnsSingleAccount(String toSearch) {
    AccountItem? account = accounts?.findAccountItemByName(toSearch);
    if (account != null) {
      return true;
    } else {
      List<AccountItem>? items =
          accounts?.getFilteredListByAccountName(toSearch);
      if (items == null || items.isEmpty) {
        return false;
      } else if (items.length > 1) {
        return false;
      } else {
        return true;
      }
    }
  }

  AccountItem? getSingleAccount(String toSearch) {
    AccountItem? account = accounts?.findAccountItemByName(toSearch);
    if (account != null) {
      //print ("getsingle account, found it!");
      return account;
    } else {
      List<AccountItem>? items =
          accounts?.getFilteredListByAccountName(toSearch);
      if (items == null || items.isEmpty) {
        return null;
      } else if (items.length > 1) {
        return null;
      } else {
        return items[0];
      }
    }
  }

  void printAccountItems(List<AccountItem>? items) {
    Console.normal("Found ${items?.length} account(s)");
    List<List<dynamic>> data = [];
    int i = 1;
    for (AccountItem? item in items!) {
      List<String> rowData = [];
      var name = (item == null || item.name.isEmpty) ? "" : item.name;
      rowData.add(name);
      var username =
          (item == null || item.username.isEmpty) ? "" : item.username;
      rowData.add(username);
      var hint = (item == null || item.hint.isEmpty) ? "" : item.hint;
      rowData.add(hint);
      var email = (item == null || item.email.isEmpty) ? "" : item.email;
      rowData.add(email);
      var accountNumber = (item == null || item.accountNumber.isEmpty)
          ? ""
          : item.accountNumber;
      rowData.add(accountNumber);
      var notes = (item == null || item.notes.isEmpty) ? "" : item.notes;
      rowData.add(wrapText(notes, 25));
      List<String> tags = (item == null || item.tags.isEmpty) ? [] : item.tags;
      String tagString = tags.join(', ');
      rowData.add(tagString);
      data.add(rowData);
      i = i + 1;
      if (i % 5 == 0) {
        data.add([
          "---------",
          "---------",
          "---------",
          "---------",
          "---------",
          "---------",
          "---------"
        ]);
      }
    }
    var header = [
      'Account',
      'User',
      'Hint',
      'Email',
      'Acct Number',
      'Notes',
      'Tags'
    ];
    printResults(header, data);
  }

  String wrapText(String inputText, int wrapLength) {
    List<String> separatedWords = inputText.split(' ');
    StringBuffer intermidiateText = StringBuffer();
    StringBuffer outputText = StringBuffer();

    for (String word in separatedWords) {
      if ((intermidiateText.length + word.length) >= wrapLength) {
        intermidiateText.write('\n');
        outputText.write(intermidiateText);
        intermidiateText.clear();
        intermidiateText.write('$word ');
      } else {
        intermidiateText.write('$word ');
      }
    }

    outputText.write(intermidiateText); //Write any remaining word at the end
    intermidiateText.clear();
    return outputText.toString().trim();
  }

  void printResults(List<String> header, List<List<dynamic>> data) {
    //final TablerStyle _style;
    //var data = [
    //  ['1', '2', '3']
    //];
    var toPrint = Tabler(
      data: data,
      header: header,
      style: TablerStyle(
        verticalChar: '!',
        horizontalChar: '=',
        junctionChar: '#',
        padding: 2,
        align: TableTextAlign.right,
      ),
    );
    print(toPrint);
  }
}
