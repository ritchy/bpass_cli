


A password manager command-line application.

in pubspec.yaml, add this:
executables:
  bpass: password_cli

install it this way:

dart pub global activate --source path .

 with an entrypoint in `bin/`, library code
in `lib/`, and example unit test in `test/`.

dart run bin/password_cli.dart list
dart compile exe bin/password_cli.dart -o bin/bpass

## clipboard uses system commands like:

pbcopy < file.name


## Commands

sync -- Google Sync

list -- list all entries, filtered by arguments

delete -- delete if search criterior returns a single match

update -- udpates if search criterior returns a single match

search -- searches all entries with provide string

hint -- provides hints with accounts returned in search
