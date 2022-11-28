import 'package:logging/logging.dart';
import 'google_api.dart';
import 'dart:io';
import 'dart:convert';
import 'console.dart';

class Accounts {
  File? file;

  List<AccountItem> accounts = [];
  List<AccountItem> deletedAccounts = [];
  List<String> tags = ['bank', 'travel', 'finance', 'work', 'shopping'];
  final log = Logger('Accounts');

  int getNumberOfTags() {
    return tags.length;
  }

  void addAccount(AccountItem item) {
    //print("accounts adding account $item");
    if (item.status != AccountItem.DELETED) {
      accounts.add(item);
    } else {
      deletedAccounts.add(item);
    }
  }

  List<AccountItem> getFilteredList(String searchTerm) {
    return accounts
        .where((entry) => (entry.name
                .toLowerCase()
                .contains(searchTerm.toLowerCase()) ||
            entry.username.toLowerCase().contains(searchTerm.toLowerCase())))
        .toList();
  }

  List<AccountItem> filterAccountsByTag(String tagSearch) {
    //print("filtering accounts by tag: $tagSearch");
    String lowerCaseTagSearch = tagSearch.toLowerCase();
    if (tagSearch == "no tags") {
      return accounts;
    } else {
      return accounts
          .where((entry) => entry.tags.contains(lowerCaseTagSearch))
          .toList();
    }
  }

  List<AccountItem> getFilteredListByAccountName(String searchTerm) {
    return accounts
        .where((entry) =>
            (entry.name.toLowerCase().contains(searchTerm.toLowerCase())))
        .toList();
  }

  List<AccountItem> getFilteredListByEmail(String emailSearch) {
    return accounts
        .where((entry) =>
            (entry.email.toLowerCase().contains(emailSearch.toLowerCase())))
        .toList();
  }

  List<AccountItem> getFilteredListByUsername(String userSearch) {
    return accounts
        .where((entry) =>
            (entry.username.toLowerCase().contains(userSearch.toLowerCase())))
        .toList();
  }

  List<AccountItem> getFilteredListByTags(List<String> tagSearch) {
    print("searching for tags $tagSearch");
    return accounts
        .where((entry) => hasIntersect(entry.tags, tagSearch))
        .toList();
  }

  bool hasIntersect(List listOne, List listTwo) {
    return listOne.toSet().intersection(listTwo.toSet()).isNotEmpty;
  }

  //this is used by command line application
  List<AccountItem> getFilteredAccounts(String searchTerm) {
    return accounts
        .where((entry) =>
            entry.name.toLowerCase().contains(searchTerm.toLowerCase()))
        .toList();
  }

  List<String> getTags() {
    //print("getTags: $tags");
    if (tags.isEmpty) {
      return ["empty"];
    } else {
      return tags.toSet().toList();
    }
  }

  void addTag(List<String> newTags) {
    for (String tagValue in newTags) {
      String lowerCase = tagValue.toLowerCase();
      if (!tags.contains(lowerCase)) {
        tags.add(lowerCase);
      }
    }
  }

  void setTags(int accountId, List<String> tags) {}

  int getNumberOfAccounts() {
    return accounts.length;
  }

  List<AccountItem> getAccountListCopy() {
    List<AccountItem> toReturn = [];
    toReturn.addAll(accounts);
    return toReturn;
  }

  void removeEmptyAccounts() {
    List<AccountItem> toRemove = [];
    for (AccountItem account in accounts) {
      if (account.isEmpty()) {
        toRemove.add(account);
        //} else {
        //print("not removing $account");
      }
    }
    for (AccountItem account in toRemove) {
      //print("removing empty ..");
      accounts.remove(account);
    }
  }

  void handleRemovedAccount(AccountItem account) {
    //account.status = AccountItem.DELETED;
    log.info("moving account from active list to deleted list $account");
    deletedAccounts.add(account);
    int index = -1;
    for (int i = 0; i < accounts.length; ++i) {
      if (accounts[i].id == account.id) {
        index = i;
        break;
      }
    }
    if (index > -1) {
      accounts.removeAt(index);
    }
  }

  void markAccountAsDeleted(AccountItem account) {
    account.lastUpdated = DateTime.now();
    account.status = AccountItem.DELETED;
  }

  Future<void> loadFileAsync(File file) async {
    loadFile(file);
  }

  void loadFile(File file) {
    this.file = file;
    log.info("loading from file: ${file.path}");
    //var id = DateTime.now().millisecondsSinceEpoch;
    //accounts.add(
    //    AccountItem("", id, "", "", "", "", "", "", "", [], newAccount: true));
    //title_rows.add("");
    //file.openRead();
    String contents = file.readAsStringSync();
    if (contents.isEmpty || contents.trim().isEmpty) {
      //Console.normal(message)
      updateAccountFiles(null);
    } else {
      var jsonResponse = jsonDecode(contents);
      for (var entry in jsonResponse) {
        AccountItem item = getAccountItemFromJsonEntry(entry);
        addAccount(item);
        //accounts.add(item);
        //add any new tags to global tag list
        for (String tagValue in item.tags) {
          if (!tags.contains(tagValue)) {
            tags.add(tagValue);
          }
        }
      }
    }
    log.info("You currently have ${accounts.length} accounts");
  }

  AccountItem getAccountItemFromJsonEntry(var entry) {
    var name = entry['name'];
    var lastUpdated = DateTime.parse(entry['last_updated']);
    var id = entry['id'];
    var username = entry['username'];
    var email = entry['email'];
    var password = entry['password'];
    var accountNumber = entry['account_number'];
    var url = entry['url'];
    var hint = entry['hint'];
    var notes = entry['notes'];
    var status = AccountItem.ACTIVE;
    if (entry['status'] != null) {
      status = entry['status'];
    }
    List<String>? accountTags =
        (entry["tags"] as List).map((e) => e as String).toList();
    return AccountItem(name, id, username, password, hint, email, accountNumber,
        url, notes, accountTags,
        lastUpdated: lastUpdated, status: status);
  }

  Future<bool> reconcileAccountsFromFile(
      File file, GoogleService googleService) async {
    //removeEmptyDisplayAccounts();
    bool somethingChanged = false;
    List<AccountItem> fileAccounts = loadAccountsFromFile(file);
    //print("loaded ${fileAccounts.length} accounts from provide file");

    //First, walk through accounts in Drive version and compare against local
    for (AccountItem itemFromFile in fileAccounts) {
      //print("checking $itemFromFile");
      //skip over empty items from incoming file
      if (itemFromFile.isEmpty()) {
        //print("google trying to sneak in an empty item");

        continue;
      }
      //print("searching for $item ...");
      AccountItem? currentItem = findAccountItemById(itemFromFile.id);
      if ((currentItem != null) &&
          (itemFromFile.lastUpdated != null) &&
          (currentItem.lastUpdated != null)) {
        //log.info("evaluating item $currentItem");
        int? f = currentItem.lastUpdated?.millisecondsSinceEpoch;
        int? g = itemFromFile.lastUpdated?.millisecondsSinceEpoch;
        if (f != null && g != null && g > f) {
          //take google value
          log.fine("replacing $currentItem with $itemFromFile from Drive");
          if (itemFromFile.status == AccountItem.ACTIVE) {
            replaceAccountItem(currentItem, itemFromFile);
          } else {
            handleRemovedAccount(itemFromFile);
          }
          somethingChanged = true;
        } else {
          log.finer(
              "we have the latest account entry, not taking version in Drive ${currentItem.name}");
        }
      } else if (currentItem == null) {
        //didn't find item in local accounts, make sure it's not in the deleted accounts
        currentItem = findDeletedAccountItemById(itemFromFile.id);
        if (currentItem == null) {
          //dont have this account entry, so add new account from file
          //print("found a new item we don't have locally ${itemFromFile.name}");
          if (!itemFromFile.isEmpty()) {
            log.fine("adding google item $itemFromFile");
            addAccount(itemFromFile);
          } else {
            //print("we have some empty accounts to remove...");
          }
          somethingChanged = true;
        } else {
          //item was deleted
          //log.info("$currentItem was deleted, let's compare");
          if ((itemFromFile.lastUpdated != null) &&
              (currentItem.lastUpdated != null)) {
            //log.info("evaluating item $currentItem");
            int? f = currentItem.lastUpdated?.millisecondsSinceEpoch;
            int? g = itemFromFile.lastUpdated?.millisecondsSinceEpoch;
            if (f != null && g != null && g > f) {
              //take google value
              //log.info("replacing $currentItem with $itemFromFile");
              replaceDeletedAccountItem(currentItem, itemFromFile);
              somethingChanged = true;
            } else {
              log.finer(
                  "we have the latest account entry in deleted items, not taking version in Drive ${currentItem.name}");
            }
          }
          somethingChanged = true;
        }
      }
    }

    //now walk through all accounts in local file and compare in Drive version
    for (AccountItem localAccountItem in accounts) {
      //print("local account item $localAccountItem");
      bool found = false;
      if (localAccountItem.isEmpty()) {
        //print("empty $localAccountItem");
        continue;
      }
      //first, try to find this item in google version
      for (AccountItem itemFromFile in fileAccounts) {
        if (localAccountItem.id == itemFromFile.id) {
          found = true;
          break;
        }
      }
      if (found) {
        //print("found $localAccountItem");
        continue;
      } else {
        //print("found some local additions $localAccountItem ...");
        somethingChanged = true;
        break;
      }
    }

    if (somethingChanged) {
      log.info("We found some changes with Google Drive sync, applying ...");
      await updateAccountFiles(googleService);
    } else {
      log.info("Nothing new in Google Drive file");
    }

    return somethingChanged;
  }

  void updateAccountItem(AccountItem newAccountItem) {
    for (int i = 0; i < accounts.length; ++i) {
      AccountItem item = accounts[i];
      if (item.id == newAccountItem.id) {
        log.info("updating $item to $newAccountItem");
        newAccountItem.lastUpdated = DateTime.now();
        accounts[i] = newAccountItem;
        break;
      }
    }
  }

  AccountItem? findAccountItemById(int accountId) {
    for (AccountItem account in accounts) {
      if (account.id == accountId) {
        return account;
      }
    }
    return null;
  }

  AccountItem? findDeletedAccountItemById(int accountId) {
    for (AccountItem account in deletedAccounts) {
      if (account.id == accountId) {
        return account;
      }
    }
    return null;
  }

  AccountItem? findAccountItemByName(String name) {
    for (AccountItem account in accounts) {
      if (account.name == name) {
        return account;
      }
    }
    return null;
  }

  void replaceAccountItem(AccountItem toReplace, AccountItem newItem) {
    int itemIndex = accounts.indexOf(toReplace);
    if (itemIndex >= 0) {
      log.info("replacing $toReplace with $newItem");
      accounts[itemIndex] = newItem;
    }
  }

  void addWelcomeAccount() {
    var id = DateTime.now().millisecondsSinceEpoch;
    accounts.add(AccountItem(
        "Welcome",
        id,
        "welcomeuser",
        "",
        "hint: welcome",
        "welcome@email.com",
        "",
        "",
        "You can edit this acccount or delete completely",
        [],
        lastUpdated: DateTime.now(),
        newAccount: true));
  }

  void replaceDeletedAccountItem(AccountItem toReplace, AccountItem newItem) {
    int itemIndex = accounts.indexOf(toReplace);
    if (itemIndex >= 0) {
      log.info("replacing $toReplace with $newItem");
      accounts[itemIndex] = newItem;
    }
  }

  List<AccountItem> loadAccountsFromFile(File file) {
    List<AccountItem> fileAccounts = [];
    log.info("loading accounts from file ${file.path} ...");
    //File toLoad = File("${file.path}s");
    String contents = file.readAsStringSync();
    //print("loaded file ${file.lengthSync()} .. contents\n:${contents}:");
    if (contents.isEmpty) {
      print("Unable to load any file content");
    } else {
      var jsonResponse = jsonDecode(contents);
      for (var entry in jsonResponse) {
        fileAccounts.add(getAccountItemFromJsonEntry(entry));
      }
    }
    //print("loaded ${fileAccounts.length} accounts");
    return fileAccounts;
  }

  Future<void> updateAccountFiles(GoogleService? googleService) async {
    removeEmptyAccounts();
    if (accounts.isEmpty) {
      addWelcomeAccount();
    }
    Console.normal("saving ${accounts.length} accounts");
    List combinedAccounts = [];
    combinedAccounts.addAll(accounts);
    combinedAccounts.addAll(deletedAccounts);
    if (file == null) {
      log.warning("account file hasn't been loaded");
      //print('file is null?');
    } else {
      var sink = file?.openWrite();
      JsonEncoder encoder = const JsonEncoder.withIndent('  ');
      String prettyprint = encoder.convert(combinedAccounts);
      //print("saving $prettyprint");
      sink?.write(prettyprint);
      // Close the IOSink to free system resources.
      await sink?.close();
      if (googleService != null) {
        //print("Calling google.updateAccountFile()");
        await googleService.updateAccountFileInDrive(prettyprint);
      } else {
        Console.normal(
            "Google service isn't initialized, did you get logged in successfully?");
      }
    }
  }
}

class AccountItem {
  String name;
  DateTime? lastUpdated;
  String status; // = "active" or "deleted"
  int id;
  String username;
  String password;
  String accountNumber;
  String url;
  String email;
  String hint;
  String notes;
  List<String> tags;
  static const String ACTIVE = "active";
  static const String DELETED = "deleted";
  bool newAccount;

  AccountItem(this.name, this.id, this.username, this.password, this.hint,
      this.email, this.accountNumber, this.url, this.notes, this.tags,
      {this.lastUpdated, this.status = "active", this.newAccount = false});

  @override
  String toString() {
    return "name: $name, username: $username, hint: $hint, email: $email, account number: $accountNumber, status $status, url: $url, new: $newAccount, tags: $tags";
  }

  Map<String, dynamic> toJson() {
    lastUpdated ??= DateTime.now();
    final Map<String, dynamic> data = Map<String, dynamic>();
    data['name'] = name;
    data['last_updated'] = lastUpdated.toString();
    data['status'] = status;
    data['id'] = id;
    data['username'] = username;
    data['password'] = password;
    data['account_number'] = accountNumber;
    data['url'] = url;
    data['email'] = email;
    data['hint'] = hint;
    data['notes'] = notes;
    data['tags'] = tags;
    return data;
  }

  void setTags(List<String> t) {
    tags = t;
  }

  //status, lastupdated and id don't factor into 'empty' status
  bool isEmpty() {
    return ((name == "") &&
        (username == "") &&
        (password == "") &&
        (accountNumber == "") &&
        (url == "") &&
        (email == "") &&
        (hint == "") &&
        (notes == "") &&
        (tags.isEmpty));
  }

  bool isEqual(AccountItem item) {
    return ((name == item.name) &&
        (username == item.username) &&
        (password == item.password) &&
        (accountNumber == item.accountNumber) &&
        (url == item.url) &&
        (email == item.email) &&
        (hint == item.hint) &&
        (notes == item.notes) &&
        (tags == item.tags));
  }
}
