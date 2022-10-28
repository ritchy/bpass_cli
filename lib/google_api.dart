import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:logging/logging.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import 'package:_discoveryapis_commons/_discoveryapis_commons.dart' as commons;
import 'encryption_handler.dart';
import 'client.dart';

//import 'package:password_manager/platform_details.dart';

class GoogleService {
  drive.DriveApi? driveApi;
  drive.File? driveFile;
  bool loggedIn = false;
  GoogleSettings googleSettings = GoogleSettings();
  ClientAccessRequests? clientAccessRequests;
  AccountFileEncryptionHandler? cryptoHandler;
  String? appDirPath;
  final log = Logger('GoogleService');

  GoogleService(this.appDirPath) {
    log.finer("creating new google service..");
  }
  void initCryptoHandler() {
    log.fine("init crypt $appDirPath and ${googleSettings.keyAsBase64}");
    String? key = googleSettings.keyAsBase64;
    if (key == null || key.isEmpty) {
      cryptoHandler = AccountFileEncryptionHandler(appDirPath!);
    } else {
      cryptoHandler =
          AccountFileEncryptionHandler(appDirPath!, keyAsBase64: key);
    }
  }

  var scopes = ['email', 'https://www.googleapis.com/auth/drive.file'];
  final _clientId = ClientId(CLIENT_IDENTIFIER, CLIENT_SECRET);

  void autoGoogleLogin() async {
    //processingGoogleFile = true;

    //if (PlatformDetails().isDesktop) {
    //} else if (PlatformDetails().isMobile) {}
    if (googleSettings.authClientSettings == null) {
      GoogleSettings? settings = await loadSettings();
      if (settings != null) {
        googleSettings = settings;
      }
    }

    AuthClientSettings? authClientSettings = googleSettings.authClientSettings;
    //print('loaded settings $authClientSettings');
    AutoRefreshingAuthClient? authClient;
    if (authClientSettings != null) {
      try {
        authClient = await refreshGoogleAuth(authClientSettings);
        if (authClient != null) {
          loggedIn = true;
          String data = authClient.credentials.accessToken.data;
          String type = authClient.credentials.accessToken.type;
          String expiry = authClient.credentials.accessToken.expiry.toString();
          String refreshToken = authClient.credentials.refreshToken!;
          authClientSettings =
              AuthClientSettings(data, type, expiry, refreshToken);
          googleSettings.authClientSettings = authClientSettings;
          updateGoogleSettings(googleSettings);
        }
      } catch (e) {
        print("Unable to refresh google login.");
      }
    } else {
      print("no previous google account info, waiting for manual attempt.");
      return;
    }
  }

  Future<bool> handleGoogleDriveLogin(PromptHandler promptHandler) async {
    log.finest("handleGoogleDriveLogin()");
    if (googleSettings.authClientSettings == null) {
      GoogleSettings? settings = await loadSettings();
      if (settings != null) {
        googleSettings = settings;
      }
    }
    AuthClientSettings? authClientSettings = googleSettings.authClientSettings;

    log.fine('loaded settings $authClientSettings');
    AutoRefreshingAuthClient? authClient;

    if ((authClientSettings != null) &&
        (authClientSettings.refreshToken != null)) {
      try {
        authClient = await refreshGoogleAuth(authClientSettings);
      } catch (e) {
        authClient = await obtainAuthClient(promptHandler);
      }
    } else {
      print("need to obtain authorization from user");
      authClient = await obtainAuthClient(promptHandler);
    }
    if (authClient != null) {
      loggedIn = true;
      String data = authClient.credentials.accessToken.data;
      String type = authClient.credentials.accessToken.type;
      String expiry = authClient.credentials.accessToken.expiry.toString();
      String refreshToken = authClient.credentials.refreshToken!;
      authClientSettings = AuthClientSettings(data, type, expiry, refreshToken);
      googleSettings.authClientSettings = authClientSettings;
      updateGoogleSettings(googleSettings);
      //print(
      //    "auth credentials access token\n type: ${authClient.credentials.accessToken.type}\nexpiry: ${authClient.credentials.accessToken.expiry} refresh token? ${authClient.credentials.refreshToken}  ");
      //print("Auth settings: $authClientSettings");
      driveApi = drive.DriveApi(authClient);
    }
    return true;
  }

  void fakeGoogleLogin() async {
    //processingGoogleFile = true;
    print("Faking login ...");
    await Future.delayed(Duration(seconds: 2));
    loggedIn = true;
    //processingGoogleFile = false;
    print("logged in .. notifying...");
  }

  Future<AutoRefreshingAuthClient?> refreshGoogleAuth(
      authClientSettings) async {
    //create the access token (even if it's expired)
    DateTime? expireDate = DateTime.tryParse(authClientSettings.expiry);
    if (expireDate != null) {
      AccessToken accessToken = AccessToken(
          authClientSettings.type, authClientSettings.data, expireDate);
      //use the refresh token here. Refresh tokens do not expire (for the most part).
      AccessCredentials creds = await refreshCredentials(
          _clientId,
          AccessCredentials(
              accessToken, authClientSettings.refreshToken, scopes),
          http.Client());

      http.Client c = http.Client();
      //create the AutoRefreshingAuthClient using previous
      //credentials
      return autoRefreshingClient(_clientId, creds, c);
    }
    return null;
  }

  Future<drive.File> createDriveFolder(drive.DriveApi driveApi) async {
    var createFolder = await driveApi.files.create(
      drive.File()
        ..name = 'ByteStream'
        //..parents = ['1f4tjhpBJwF5t6FpYvufTljk8Gapbwajc'] // Optional if you want to create subfolder
        ..mimeType =
            'application/vnd.google-apps.folder', // this defines its folder
    );
    return createFolder;
  }

  void googleLogout() {
    driveApi = null;
    loggedIn = false;
  }

  Future<File?> downloadAccountFile() async {
    log.fine("downloadAccountFile $driveFile and $driveApi ...");
    if (!await accountsFileExistInDrive()) {
      log.warning(
          "account file does not exist in google Drive, not downloading");
      return null;
    }
    if (driveFile == null) {
      if (driveApi != null) {
        String? folderId = await _getFolderId(driveApi!);
        if (folderId != null) {
          driveFile = await _getDriveFileInstance(
              driveApi!, googleSettings.googleAccountsFileName, folderId);
        } else {
          log.warning("Drive folder id is null? unable to find it?");
        }
      } else {
        log.warning("Drive api is null?  not logged in?");
      }
    }
    //this should be encrytped, need to unencrypt and save
    String? encryptedContent = await _getFileContent(driveFile?.id);
    //log.info("got encrypted content? $encryptedContent");
    String? unEncryptedContent;
    if (cryptoHandler == null) {
      initCryptoHandler();
    }
    if (encryptedContent != null) {
      unEncryptedContent =
          await cryptoHandler?.decryptStringContent(encryptedContent);
    } else {
      log.warning(
          "unable to get content from accounts file in Google Drive, cryptohandler null? $cryptoHandler");
    }
    //log.info("got unencrypted content? $unEncryptedContent");
    String? jsonDocument =
        "$appDirPath${Platform.pathSeparator}${googleSettings.googleAccountsFileName}";
    //print("downloading to $jsonDocument");
    File file = File(jsonDocument);
    if (!file.existsSync()) {
      file.createSync();
    }
    if (unEncryptedContent != null && unEncryptedContent.isNotEmpty) {
      log.fine(
          "saving unencrypted accounts file from Drive here: $jsonDocument");
      await file.writeAsString(unEncryptedContent, flush: true);
    } else {
      log.warning(
          "not saving unencrypted accounts file from Drive $jsonDocument");
    }
    return file;
  }

  Future<bool> accountsFileExistInDrive() async {
    // Check if the folder exists. If it doesn't exist, create it and return the ID.
    final folderId = await _getFolderId(driveApi!);
    if (folderId == null) {
      //await showMessage(context, "Failure", "Error");
      log.warning("Unable to get bytestream folder");
      return false;
    }
    try {
      final found = await driveApi?.files.list(
        q: "parents in '$folderId' and name = '${googleSettings.googleAccountsFileName}'",
        $fields: "files(id, name)",
      );
      final files = found?.files;
      if (files == null || files.isEmpty) {
        return false;
      } else {
        return true;
      }
    } catch (e) {
      log.warning("exception occurred searching for client access file $e");
    }
    log.warning(
        "shouldn't see this log message, we're not sure if file exist or not!");
    return false;
  }

  Future<void> updateAccountFileInDrive(String unEncryptedContent) async {
    //log.info("gapi:updateAccountFile(): encrypting $unEncryptedContent");
    String? encryptedContent =
        await encryptAccountFileContentsAsBase64(unEncryptedContent);
    if (encryptedContent == null) {
      print(
          "Unable to save encrypted file on google drive, no content to save");
      return;
    }

    print("Updating google drive file with latest version ...");
    if (driveApi == null) {
      print("Not logged in! Can't update google drive");
      return;
    }
    try {
      // Check if the folder exists. If it doesn't exist, create it and return the ID.
      final folderId = await _getFolderId(driveApi!);
      if (folderId == null) {
        //await showMessage(context, "Failure", "Error");
        log.warning("Unable to get bytestream folder");
        return;
      }

      if (await accountsFileExistInDrive()) {
        driveFile ??= await _getDriveFileInstance(
            driveApi!, googleSettings.googleAccountsFileName, folderId);
        //print("account file exist? $driveFile");

        // Create data here instead of loading a file
        //final contents = "['bytestream':'bytestream-update-refresh-token']";
        final Stream<List<int>> mediaStream =
            Future.value(encryptedContent.codeUnits)
                .asStream()
                .asBroadcastStream();
        var media = drive.Media(mediaStream, encryptedContent.length);

        if (driveFile != null) {
          drive.File fileToUpdate = drive.File();
          //fileToUpdate.id = driveFile.id;
          String? oldId = driveFile?.id;
          fileToUpdate.name = driveFile?.name;
          fileToUpdate.parents = driveFile?.parents;

          // Upload
          driveFile = await driveApi?.files
              .update(fileToUpdate, oldId!, uploadMedia: media);
          //print("response: $driveFile");
        } else {
          //cannot update the file
          log.severe(
              "Unable to update google drive file, API reference is null");
        }
      } else {
        await createDriveFile(
            googleSettings.googleAccountsFileName, encryptedContent, folderId);
      }
    } catch (e) {
      log.severe("problem updating google drive $e");
    } finally {}
  }

  Future<String?> encryptAccountFileContentsAsBase64(String content) async {
    //print("encryptAccountFileContentsAsBase64()");
    if (googleSettings.keyAsBase64 == null) {
      googleSettings.keyAsBase64 = generateBase64AesKey();
      updateGoogleSettings(googleSettings);
    } else {
      //print("got key from settings file ${googleSettings.keyAsBase64}");
    }
    if (googleSettings.keyAsBase64 != null) {
      if (cryptoHandler == null) {
        initCryptoHandler();
      }
      return cryptoHandler?.encryptAcccountFileContent(content);
    } else {
      log.severe(
          "Unable to encrypt google file, one of these is null, app dir path: $appDirPath or our key: ${googleSettings.keyAsBase64}, so not saving");
    }
    return null;
  }

  Future<void> updateEncryptedAccountFile(String contents) async {
    //print("updateEncryptedAccountFile()");
    if (googleSettings.keyAsBase64 == null) {
      googleSettings.keyAsBase64 = generateBase64AesKey();
      updateGoogleSettings(googleSettings);
    }

    //var keyString = "iKb+U5suLwCVlB9Qy2wRjFJB5mjPFWaJSfdcUgyxcdE=";
    if ((appDirPath != null) && (googleSettings.keyAsBase64 != null)) {
      AccountFileEncryptionHandler cryptoHandler = AccountFileEncryptionHandler(
          appDirPath!,
          keyAsBase64: googleSettings.keyAsBase64!);
      cryptoHandler.encryptAccountFileContents(contents);
      //print("encrypted file, now see if we can unencrypt:");
      //print(await cryptoHandler.unEncryptAccountFileContents());
    } else {
      log.severe(
          "Unable to encrypt google file, one of these is null, app dir path: $appDirPath or our key: ${googleSettings.keyAsBase64}, so not saving");
    }
  }

  Future<File?> downloadClientAccessFile() async {
    drive.File? clientAccesFile;
    if (driveApi != null) {
      String? folderId = await _getFolderId(driveApi!);
      if (folderId != null) {
        clientAccesFile = await _getDriveFileInstance(
            driveApi!, googleSettings.accessAccountsFileName, folderId);
      } else {
        log.warning("Drive folder id is null? unable to find it?");
      }
    } else {
      log.warning("Drive api is null?  not logged in?");
    }
    if (clientAccesFile == null) {
      log.info(
          "There is no existing client access file, ${googleSettings.accessAccountsFileName}, in Google Drive");
      return null;
    } else {
      String? fileContents = await _getFileContent(clientAccesFile.id);
      String? jsonDocumentFilePath =
          "$appDirPath${Platform.pathSeparator}${googleSettings.accessAccountsFileName}";
      //print("downloading to $jsonDocumentFilePath");
      File file = File(jsonDocumentFilePath);
      if (!file.existsSync()) {
        file.createSync();
      }
      if (fileContents != null && fileContents.isNotEmpty) {
        await file.writeAsString(fileContents, flush: true);
      }
      return file;
    }
  }

  Future<File?> saveAccessRequestFileLocally(
      ClientAccessRequests clientAccessRequests) async {
    File? file = await openClientAccessFile(true);
    if (file == null) {
      log.severe("Cannot load access request file");
    }
    var sink = file?.openWrite();
    String prettyprint = generateAccessRequestsJson(clientAccessRequests);
    sink?.write(prettyprint);
    // Close the IOSink to free system resources.
    await sink?.close();
    return file;
  }

  String generateAccessRequestsJson(ClientAccessRequests clientAccessRequests) {
    JsonEncoder encoder = const JsonEncoder.withIndent('  ');
    clientAccessRequests.lastUpdated = DateTime.now();
    return encoder.convert(clientAccessRequests);
  }

  Future<File?> openClientAccessFile(bool createIfMissing) async {
    if (appDirPath == null) {
      return null;
    }

    String? jsonDocument =
        "$appDirPath${Platform.pathSeparator}${googleSettings.accessAccountsFileName}";
    File file = File(jsonDocument);
    if (!file.existsSync()) {
      if (createIfMissing) {
        generateNewClientAccessFile();
        return file;
      } else {
        return null;
      }
    } else {
      return file;
    }
  }

  Future<bool> clientAccessFileExistInDrive() async {
    // Check if the folder exists. If it doesn't exist, create it and return the ID.
    if (driveApi == null) {
      Exception("Don't have API references, cannot check for file in Drive");
    }
    final folderId = await _getFolderId(driveApi);
    if (folderId == null) {
      //await showMessage(context, "Failure", "Error");
      log.warning("Unable to get bytestream folder");
      return false;
    }
    try {
      final found = await driveApi?.files.list(
        q: "parents in '$folderId' and name = '${googleSettings.accessAccountsFileName}'",
        $fields: "files(id, name)",
      );
      final files = found?.files;
      if (files == null || files.isEmpty) {
        return false;
      } else {
        return true;
      }
    } catch (e) {
      log.warning("exception occurred searching for client access file $e");
    }
    //driveFile ??= await _getDriveFileInstance(
    //    driveApi!, googleSettings.accessAccountsFileName, folderId);
    //log.finer("client access file exist? $driveFile");
    //return (driveFile != null);
    log.warning(
        "shouldn't see this log message, we're not sure if file exist or not!");
    return false;
  }

  Future<File?> generateNewClientAccessFile() async {
    clientAccessRequests = ClientAccessRequests();
    ClientAccess clientAccess = ClientAccess();
    clientAccess.accessStatus = ClientAccess.GRANTED;
    clientAccessRequests?.addAccessRequest(clientAccess);
    await updateClientAccessFileInDrive(clientAccessRequests!);
    googleSettings.clientAccessId = clientAccess.clientId;
    updateGoogleSettings(googleSettings);
    return await saveAccessRequestFileLocally(clientAccessRequests!);
  }

  Future<void> generateNewClientAccessRequest() async {
    if (clientAccessRequests == null) {
      await loadClientAccessRequests();
    }
    if (this.cryptoHandler == null) {
      initCryptoHandler();
    }
    final cryptoHandler = this.cryptoHandler;
    if (cryptoHandler != null && !cryptoHandler.exchangePemFilesExist()) {
      await cryptoHandler.generateExchangePemFiles();
    }
    String? publicKey = await cryptoHandler?.loadPublicKeyAsString();

    publicKey ??= "";

    ClientAccess clientAccess = ClientAccess();
    clientAccess.accessStatus = ClientAccess.REQUESTED;
    clientAccess.publicKey = publicKey;
    clientAccessRequests?.addAccessRequest(clientAccess);
    //await updateClientAccessFileInDrive(clientAccessRequests!);
    googleSettings.clientAccessId = clientAccess.clientId;
    updateGoogleSettings(googleSettings);
    await saveAccessRequestFileLocally(clientAccessRequests!);
  }

  Future<void> grantAccessRequest(String clientId) async {
    log.finest("Google API granting access to client $clientId ...");
    //log.info("logged in? $loggedIn");
    bool somethingChanged = false;
    bool removeClientRequest = false;
    clientAccessRequests ??= await loadClientAccessRequests();
    if (this.cryptoHandler == null) {
      initCryptoHandler();
    }
    final cryptoHandler = this.cryptoHandler;
    final requests = clientAccessRequests?.clientAccessRequests;
    if (requests != null) {
      for (ClientAccess cr in requests) {
        if (cr.clientId == clientId) {
          final key = googleSettings.keyAsBase64;
          final publicKey = cr.publicKey;
          if (key != null && publicKey != null) {
            if (publicKey.isEmpty) {
              log.warning(
                  "public key wasn't provided, cannot grant access to client $clientId, removing request..");
              removeClientRequest = true;
              somethingChanged = true;
              break;
            } else {
              cr.encryptedAccessKey =
                  await cryptoHandler?.encryptAccessKey(key, publicKey);
              cr.accessStatus = ClientAccess.GRANTED;
              somethingChanged = true;
              //print("encrypted key $key to ${cr.encryptedAccessKey}");
            }
          }
        }
      }
    }
    if (somethingChanged) {
      if (removeClientRequest) {
        log.fine("Removing access request in google drive...");
        removeAccessRequestById(clientId);
      } else {
        log.fine("Access updated, updating google drive...");
        await updateClientAccessRequests();
      }
    }
  }

  Future<void> updateClientRequest(ClientAccess accessRequest) async {
    log.info("updating access requests...");
    var requests = clientAccessRequests?.clientAccessRequests;
    if (requests != null) {
      for (int i = 0; i < requests.length; ++i) {
        ClientAccess ca = requests[i];
        if (ca == accessRequest) {
          if (accessRequest.clientId == null) {
            clientAccessRequests?.clientAccessRequests.remove(ca);
          } else {
            requests[i] = accessRequest;
          }
          await updateClientAccessRequests();
          break;
        }
      }
    }
  }

  Future<ClientAccess?> findExistingRequest() async {
    ClientAccess? toReturn;
    String? myClientId = googleSettings.clientAccessId;
    myClientId ??= "";
    if (myClientId.isNotEmpty) {
      ClientAccessRequests requests = await loadClientAccessRequests();
      for (ClientAccess access in requests.clientAccessRequests) {
        if (access.clientId == myClientId) {
          if (access.accessStatus == ClientAccess.REQUESTED) {}
          //print("we have outstanding request");
          toReturn = access;
          break;
        }
      }
    }
    return toReturn;
  }

  Future<void> removeOutstandingRequests() async {
    ClientAccess? toDelete;
    String? myClientId = googleSettings.clientAccessId;
    myClientId ??= "";
    if (myClientId.isNotEmpty) {
      ClientAccessRequests requests = await loadClientAccessRequests();
      for (ClientAccess access in requests.clientAccessRequests) {
        if (access.clientId == myClientId) {
          toDelete = access;
          //print("we have outstanding request");
          break;
        }
      }
      if (toDelete != null) {
        requests.clientAccessRequests.remove(toDelete);
      }
    }
  }

  Future<void> decryptAndSaveKey(String enryptedKey) async {
    try {
      //print("decryptAndSaveKey() decrypting $enryptedKey");
      if (cryptoHandler == null) {
        initCryptoHandler();
      }
      String? decryptedKey = await cryptoHandler?.decryptAccessKey(enryptedKey);
      if (decryptedKey != null && decryptedKey.isNotEmpty) {
        googleSettings.keyAsBase64 = decryptedKey;
        log.info("updating $googleSettings");
        await updateGoogleSettings(googleSettings);
      }
      //print("decrypted key $decryptedKey");
    } catch (e) {
      print("problem decrypting provided key $e");
    }
  }

  Future<void> removeAccessRequest(ClientAccess clientAccess) async {
    log.info("removing access request...");
    clientAccessRequests?.clientAccessRequests.remove(clientAccess);
    await updateClientAccessRequests();
  }

  Future<void> removeAccessRequestById(String clientId) async {
    log.info("removing access request...");
    var requests = clientAccessRequests?.clientAccessRequests;
    if (requests != null) {
      for (int i = 0; i < requests.length; ++i) {
        ClientAccess ca = requests[i];
        if (ca.clientId == clientId) {
          requests.remove(ca);
          await updateClientAccessRequests();
          break;
        }
      }
    }
  }

  Future<void> updateClientAccessRequests() async {
    final ClientAccessRequests? toSave = clientAccessRequests;
    if (toSave != null) {
      await saveAccessRequestFileLocally(toSave);
      await updateClientAccessFileInDrive(toSave);
    }
  }

  Future<void> updateClientAccessFileInDrive(
      ClientAccessRequests clientAccessRequests) async {
    String content = generateAccessRequestsJson(clientAccessRequests);
    log.finest("gapi:updateClientAccessFileInDrive()");
    log.info(
        "Updating google drive file with latest client access version ...");
    //print("content $content");
    if (driveApi == null) {
      log.warning("Not logged in! Can't update google drive");
      return;
    }
    try {
      // Check if the folder exists. If it doesn't exist, create it and return the ID.
      final folderId = await _getFolderId(driveApi!);
      if (folderId == null) {
        //await showMessage(context, "Failure", "Error");
        log.warning("Unable to get bytestream folder");
        return;
      }
      if (await clientAccessFileExistInDrive()) {
        drive.File? accessDriveFile = await _getDriveFileInstance(
            driveApi!, googleSettings.accessAccountsFileName, folderId);
        log.fine(
            "client access file, ${googleSettings.accessAccountsFileName} exist? $accessDriveFile");

        // Create data here instead of loading a file
        //final contents = "['bytestream':'bytestream-update-refresh-token']";
        final Stream<List<int>> mediaStream =
            Future.value(content.codeUnits).asStream().asBroadcastStream();
        var media = drive.Media(mediaStream, content.length);

        if (accessDriveFile != null) {
          drive.File fileToUpdate = drive.File();
          //fileToUpdate.id = driveFile.id;
          String? oldId = accessDriveFile.id;
          fileToUpdate.name = accessDriveFile.name;
          fileToUpdate.parents = accessDriveFile.parents;

          // Upload
          accessDriveFile = await driveApi?.files
              .update(fileToUpdate, oldId!, uploadMedia: media);
          //print("response: $accessDriveFile");
          log.info("updated ${fileToUpdate.name} in google Drive");
        } else {
          //cannot update the file
          log.severe(
              "Unable to update google drive client access, API reference is null");
        }
      } else {
        await createDriveFile(
            googleSettings.accessAccountsFileName, content, folderId);
      }
    } catch (e) {
      log.severe("problem updating google drive with client access updates $e");
    } finally {}
  }

  //Future<void> grantAccess(String clientId) async {}

  Future<ClientAccessRequests> loadClientAccessRequests() async {
    log.info("Downloading access requests from Drive ...");
    if (await clientAccessFileExistInDrive()) {
      File? clientAccessFile = await downloadClientAccessFile();
      if (clientAccessFile != null) {
        String contents = clientAccessFile.readAsStringSync();
        try {
          //print("parsing contents: $contents");
          clientAccessRequests = ClientAccessRequests();
          var jsonResponse = jsonDecode(contents);
          var clients = jsonResponse['clients'];
          for (var client in clients) {
            var accessStatus = client['access_status'];
            var lastUpdated = client['last_updated'];
            var clientId = client['client_id'];
            var clientName = client['client_name'];
            var publicKey = client['public_key'];
            var accessKey = client['encrypted_access_key'];
            if (accessStatus == ClientAccess.REQUESTED) {
              log.info(
                  "Got a request for Drive access $clientName id=$clientId");
            }
            ClientAccess clientAccess = ClientAccess(
                accessStatus: accessStatus,
                lastUpdated: DateTime.parse(lastUpdated),
                clientId: clientId,
                clientName: clientName,
                publicKey: publicKey,
                encryptedAccessKey: accessKey);
            clientAccessRequests?.addAccessRequest(clientAccess);
            //print("access status $accessStatus");
          }
        } catch (e) {
          log.severe("unable to parse client access file: $e");
        }
      } else {
        log.warning("Problem downloading access file from Drive");
      }
    } else {
      await generateNewClientAccessFile();
    }
    return clientAccessRequests ?? ClientAccessRequests();
  }

  Future<String>? _getFileContent(String? id) {
    if (id == null) {
      log.warning("not retriving file contents from Drive, file id is null");
      return null;
    } else {
      return driveApi?.files
          .get(id, downloadOptions: commons.DownloadOptions.fullMedia)
          .then((response) {
        if (response is! commons.Media) throw Exception("invalid response");
        return response.stream.toList().then((lists) {
          return String.fromCharCodes(lists.expand((list) => list));
        });
      });
    }
  }

//Normal Drive folder, not hidden appfolder
  Future<String?> _getFolderId(drive.DriveApi? driveApi) async {
    if (driveApi == null) {
      return null;
    }
    const mimeType = "application/vnd.google-apps.folder";
    String folderName = "ByteStream";

    try {
      final found = await driveApi.files.list(
        q: "mimeType = '$mimeType' and name = '$folderName'",
        $fields: "files(id, name)",
      );
      final files = found.files;
      if (files == null) {
        //await showMessage(context, "Sign-in first", "Error");
        print("not logged in");
        return null;
      }

      // The folder already exists
      if (files.isNotEmpty) {
        return files.first.id;
      }

      // Create a folder
      var folder = drive.File();
      folder.name = folderName;
      folder.mimeType = mimeType;
      final folderCreation = await driveApi.files.create(folder);
      log.info("Folder ID: ${folderCreation.id}");

      return folderCreation.id;
    } catch (e) {
      log.severe("got exceptions $e");
      return null;
    }
  }

  //hidden app folder on google drive
  void _getAppDrive(drive.DriveApi driveApi) {
    // Set up File info
    var driveFile = drive.File();
    final timestamp = DateFormat("yyyy-MM-dd-hhmmss").format(DateTime.now());
    driveFile.name = "technical-feeder-$timestamp.txt";
    driveFile.modifiedTime = DateTime.now().toUtc();
    driveFile.parents = ["appDataFolder"];
  }

  //Normal Drive folder, not hidden appfolder
  Future<drive.File?> _getDriveFileInstance(
      drive.DriveApi driveApi, String fileName, String parentFolderId) async {
    //String fileName = "accounts.json";
    drive.File? driveFile;
    try {
      final found = await driveApi.files.list(
        q: "name = '$fileName'",
        $fields: "files(id, name)",
      );
      final files = found.files;
      if (files == null) {
        //await showMessage(context, "Sign-in first", "Error");
        print("not logged in");
        return null;
      }

      if (files.isNotEmpty) {
        //print("parents: ${files.first.parents}");
        //print("found ${files.length} files ..");
        driveFile = files.first;
      } //else {
      //log.info("drive file, $fileName, doesn't exist, creating");
      //const contents = "[]";
      //driveFile = await createAccountsDriveFile(contents, parentFolderId);
      //}
    } catch (e) {
      log.severe("got exceptions $e");
      return null;
    }
    return driveFile;
  }

  Future<drive.File?> createDriveFile(
      String fileName, String contents, String parentFolderId) async {
    final Stream<List<int>> mediaStream =
        Future.value(contents.codeUnits).asStream().asBroadcastStream();
    var media = drive.Media(mediaStream, contents.length);

    //create the file
    // Set up File info
    drive.File? driveFile = drive.File();
    //const timestamp =
    //    DateFormat("yyyy-MM-dd-hhmmss").format(DateTime.now());
    driveFile.name = fileName;
    driveFile.modifiedTime = DateTime.now().toUtc();

    // parent folder
    driveFile.parents = [parentFolderId];

    // Upload
    driveFile = await driveApi?.files.create(driveFile, uploadMedia: media);
    return driveFile;
    //print("response: $driveFile");
    //return response;
  }

// Use the oauth2 authentication code flow functionality to obtain
// credentials. [prompt] is used for directing the user to a URI.
  Future<AccessCredentials> obtainCredentials(
      PromptHandler promptHandler) async {
    final client = http.Client();

    try {
      return await obtainAccessCredentialsViaUserConsent(
        ClientId(
            '240721822501-4g0qvd039md5dncd8pdosk9co59d84h0.apps.googleusercontent.com',
            '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'),
        ['email', 'https://www.googleapis.com/auth/drive.file'],
        client,
        promptHandler.handlePrompt,
        //(String url) => promptHandler.handlePrompt(url),
      );
    } finally {
      client.close();
    }
  }

  Future<void> obtainFakeAuthClient(Function prompt) async {
    prompt("Url is cool");
  }

// Use the oauth2 code grant server flow functionality to
// get an authenticated and auto refreshing client.
  Future<AutoRefreshingAuthClient> obtainAuthClient(
          PromptHandler promptHandler) async =>
      await clientViaUserConsent(
        ClientId(
            '240721822501-4g0qvd039md5dncd8pdosk9co59d84h0.apps.googleusercontent.com',
            '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'),
        ['email', 'https://www.googleapis.com/auth/drive.file'],
        promptHandler.handlePrompt,
        //(String url) => promptHandler.handlePrompt(url),
      );

  void _prompt2(String url) async {
    //canLaunchUrl().then((bool result) {});
    print("Here's the URL to grant access:");
    print('  => $url');
    var result = await Process.run('open', [url]);
    print('');
  }

  //Future<void> loadSettingsAsync() async {
  //  loadSettings();
  //}

  Future<GoogleSettings?> loadSettings() async {
    File? file = await getSettingsFile();
    log.info("loading settings from file ... ${file?.path}");
    if (file != null) {
      String? contents = file.readAsStringSync();
      if (contents != null) {
        try {
          var jsonResponse = jsonDecode(contents);
          //for (var entry in jsonResponse) {
          var authClient = jsonResponse['auth_client'];
          var lastUpdatedString = authClient['last_updated'];
          var data = authClient['data'];
          var type = authClient['type'];
          var expiry = authClient['expiry'];
          var refreshToken = authClient['refresh_token'];
          var keyAsBase64 = jsonResponse['key_base64'];
          var clientAccessId = jsonResponse['client_access_id'];
          return GoogleSettings(
              authClientSettings:
                  AuthClientSettings(data, type, expiry, refreshToken),
              keyAsBase64: keyAsBase64,
              clientAccessId: clientAccessId);
          //}
        } catch (e) {
          print("unable to read settings file $e");
        }
      } else {
        print("Settings file empty");
      }
    }
    return null;
  }

  Future<void> updateGoogleSettings(GoogleSettings googleSettings) async {
    File? file = await getSettingsFile();
    if (file == null) {
      log.warning("Cannot load settings file");
      return;
    }
    if (googleSettings.keyAsBase64 == null ||
        googleSettings.keyAsBase64!.isEmpty) {}
    var sink = file.openWrite();
    JsonEncoder encoder = const JsonEncoder.withIndent('  ');
    String prettyprint = encoder.convert(googleSettings);
    sink.write(prettyprint);
    // Close the IOSink to free system resources.
    await sink.close();
  }

  Future<File?> getSettingsFile() async {
    //Directory appDocDir = await getApplicationDocumentsDirectory();
    //String appDocPath = appDocDir.path;
    //print("getting settings file from $appDirPath");
    if (appDirPath == null) {
      return null;
    }

    String jsonDocument =
        "$appDirPath${Platform.pathSeparator}${googleSettings.googleSettingsFileName}";
    //print("file path: $jsonDocument");
    File file = File(jsonDocument);
    if (!file.existsSync()) {
      stdout.writeln("Settings file does not exist, creating ...");
      file.createSync();
      var sink = file.openWrite();
      sink.write('{"date-created" : "${DateTime.now()}"}\n');
      // Close the IOSink to free system resources.
      await sink.close();
      return file;
    } else {
      return file;
    }
  }
}

class GoogleSettings {
  AuthClientSettings? authClientSettings;
  String? keyAsBase64;
  String? clientAccessId;
  String googleAccountsFileName =
      "bpass-encrypted.json"; //"google-accounts.json";
  String accessAccountsFileName = "access.json";
  String googleSettingsFileName = "google-settings.json";
  GoogleSettings(
      {this.authClientSettings, this.keyAsBase64, this.clientAccessId});
  @override
  String toString() {
    return "authClientSettings: $authClientSettings, keyAsBase64: $keyAsBase64";
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> settings = Map<String, dynamic>();
    //settings['accounts_filename'] = googleAccountsFileName;
    settings['key_base64'] = keyAsBase64;
    settings['auth_client'] = authClientSettings;
    settings['client_access_id'] = clientAccessId;
    return settings;
  }
}

class AuthClientSettings {
  String? data, type, expiry, refreshToken;
  DateTime lastUpdated = DateTime.now();

  AuthClientSettings(this.data, this.type, this.expiry, this.refreshToken);

  @override
  String toString() {
    return "data: $data, type: $type expiry: $expiry refreshToken: $refreshToken lastUpdated: $lastUpdated";
  }

  Map<String, dynamic> toJson() {
    //print("converting $this");
    lastUpdated = DateTime.now();
    final Map<String, dynamic> settings = Map<String, dynamic>();
    settings['last_updated'] = lastUpdated.toString();
    settings['data'] = data;
    settings['type'] = type;
    settings['expiry'] = expiry;
    settings['refresh_token'] = refreshToken;
    return settings;
  }
}

class PromptHandler {
  void handlePrompt(String url) async {
    print('Please go to the following URL and grant access:');
    print('  => $url');
    print('');
  }
}

class AccountFileEncryptionHandler {
  String appDirPath;
  String? keyAsBase64;
  String exchangePublicPemFileName = "bpass-exchange-public.pem";
  String exchangePrivatePemFileName = "bpass-exchange-private.pem";
  String encryptedAccountFileName = "encrypted-accounts-json";

  AccountFileEncryptionHandler(this.appDirPath, {this.keyAsBase64});

  String getFilePath(String fileName) {
    return "$appDirPath${Platform.pathSeparator}$fileName";
  }

  bool exchangePemFilesExist() {
    File publicFile = File(getFilePath(exchangePublicPemFileName));
    File privateFile = File(getFilePath(exchangePrivatePemFileName));
    return (publicFile.existsSync() && privateFile.existsSync());
  }

  Future<void> generateExchangePemFiles() async {
    generateRSAPemFiles(getFilePath(exchangePublicPemFileName),
        getFilePath(exchangePrivatePemFileName));
  }

  Future<String> loadPublicKeyAsString() async {
    File publicFile = File(getFilePath(exchangePublicPemFileName));
    if (publicFile.existsSync()) {
      return await publicFile.readAsString();
    } else {
      return "";
    }
  }

  Future<String> loadPrivateKeyAsString() async {
    //print("loadPrivateKeyAsString()");
    File privatePemFile = File(getFilePath(exchangePrivatePemFileName));
    if (privatePemFile.existsSync()) {
      //print("returning contents from ${privatePemFile.path}");
      try {
        //privatePemFile.readAsBytesSync();
        //print('read bytes');
        String contents = privatePemFile.readAsStringSync();
        //print("got contents $contents");
        return contents;
      } catch (e) {
        log.severe("problem reading file $e");
      }
    }
    log.warning("unable to load private key");
    return "";
  }

  Future<String> encryptAccessKey(String keyAsBase64, String publicKey) async {
    return await encryptWithProvidedKey(keyAsBase64, publicKey);
  }

  Future<String> decryptAccessKey(String keyAsBase64) async {
    //print("decryptAccessKey()");
    String privateKeyString = await loadPrivateKeyAsString();
    //print("decryptAccessKey() $privateKeyString");
    return await decryptWithProvidedKey(keyAsBase64, privateKeyString);
  }

  Future<void> encryptAccountFileContents(String unEncryptedContent) async {
    if (keyAsBase64 != null) {
      encryptAndSaveContent(keyAsBase64!, unEncryptedContent,
          getFilePath(encryptedAccountFileName));
    } else {
      log.severe("Cannot encrypt account file because provided key is null");
    }
  }

  Future<String> encryptAcccountFileContent(String unEncryptedContent) async {
    //print(
    //    "encryptAcccountFileContent(): about to encrypt this: $unEncryptedContent");
    if (keyAsBase64 != null) {
      return await encryptStringContentAsBase64(
          keyAsBase64!, unEncryptedContent);
    } else {
      log.severe("Cannot encrypt account file because provided key is null");
      return "";
    }
  }

  Future<String> decryptAccountFileContents() async {
    if (keyAsBase64 != null) {
      return loadAndUnencryptContent(
          keyAsBase64!, getFilePath(encryptedAccountFileName));
    } else {
      log.severe(
          "Cannot un-encrypt account file contents because provided key is null");
      return "[]";
    }
  }

  Future<String> decryptStringContent(String encryptedContentAsBase64) async {
    //log.finer("CryptoHandler(): unEncryptStringContent()");
    String? key = keyAsBase64;
    if (key != null && key.isNotEmpty) {
      return await unEncryptStringContentFromBase64(
          key, encryptedContentAsBase64);
    } else {
      log.severe("Cannot un-encrypt this string because provided key is null");
      return "[]";
    }
  }
}

class ClientAccessRequests {
  var clientAccessRequests = [];
  DateTime lastUpdated = DateTime.now();

  ClientAccess generateAccessRequest(String clientId) {
    ClientAccess clientAccess = ClientAccess(clientId: clientId);
    clientAccess.accessStatus = ClientAccess.REQUESTED;
    return clientAccess;
  }

  void addAccessRequest(ClientAccess clientAccess) {
    //first, remove any existing client with the same id
    var toRemove = [];
    for (ClientAccess c in clientAccessRequests) {
      if (c.clientId == clientAccess.clientId) {
        toRemove.add(c);
      }
    }
    clientAccessRequests.removeWhere((e) => toRemove.contains(e));
    clientAccessRequests.add(clientAccess);
  }

  ClientAccess? findById(String clientAccessId) {
    for (ClientAccess clientAccess in clientAccessRequests) {
      if (clientAccess.clientId == clientAccessId) {
        return clientAccess;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    //print("converting $this");
    lastUpdated = DateTime.now();
    final Map<String, dynamic> results = Map<String, dynamic>();
    results['last_updated'] = lastUpdated.toString();
    results['clients'] = clientAccessRequests;
    return results;
  }
}

/**
 *  access_status: "requested/granted/denied"
 */
class ClientAccess {
  String? clientId;
  String? clientName;
  DateTime? lastUpdated;
  String? publicKey;
  String? accessStatus;
  String? encryptedAccessKey;
  static const String GRANTED = "granted";
  static const String REQUESTED = "requested";
  static const String DENIED = "denied";

  ClientAccess(
      {this.clientId,
      this.clientName,
      this.lastUpdated,
      this.publicKey,
      this.accessStatus,
      this.encryptedAccessKey}) {
    clientId ??= DateTime.now().millisecondsSinceEpoch.toString();
  }

  Map<String, dynamic> toJson() {
    //print("converting $this");
    clientId ??= DateTime.now().millisecondsSinceEpoch.toString();
    clientName ??= Platform.operatingSystem;
    lastUpdated ??= DateTime.now();
    publicKey ??= "";
    encryptedAccessKey ??= "";
    final Map<String, dynamic> clients = Map<String, dynamic>();
    clients['last_updated'] = lastUpdated.toString();
    clients['client_id'] = clientId;
    clients['client_name'] = clientName;
    clients['public_key'] = publicKey;
    clients['encrypted_access_key'] = encryptedAccessKey;
    clients['access_status'] = accessStatus;
    return clients;
  }
}
