import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_database.dart';
import 'recoverable_store_file.dart';

final class LocalStore {
  LocalStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? (() => getApplicationSupportDirectory());

  LocalStore.withDatabase(
    AppDatabase database, {
    Future<Directory> Function()? directoryProvider,
  }) : _database = database,
       _directoryProvider =
           directoryProvider ?? (() => getApplicationSupportDirectory());

  final Future<Directory> Function() _directoryProvider;
  AppDatabase? _database;

  AppDatabase get database {
    return _database ??= AppDatabase(
      LazyDatabase(() async {
        return NativeDatabase.createInBackground(await file);
      }),
    );
  }

  Future<File> get file async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, 'lume.sqlite'));
  }

  Future<File> get legacyJsonFile async {
    final directory = await _directoryProvider();
    return File(p.join(directory.path, 'lume-state.json'));
  }

  Future<AppSnapshot> load() async {
    await _migrateLegacyJsonIfNeeded();

    if (!await database.hasAnyUserData()) {
      final seeded = AppSnapshot.seeded(DateTime.now().toUtc());
      await save(seeded);
      return seeded;
    }

    return database.loadSnapshot();
  }

  Future<void> save(AppSnapshot snapshot) async {
    await database.replaceSnapshot(snapshot);
  }

  Future<void> close() async {
    await database.close();
  }

  Future<void> _migrateLegacyJsonIfNeeded() async {
    if (await database.hasAnyUserData()) {
      return;
    }

    final legacy = await legacyJsonFile;
    if (!await legacy.exists()) {
      return;
    }

    try {
      final raw = await legacy.readAsString();
      if (raw.trim().isEmpty) {
        await preserveInvalidStoreFile(legacy);
        return;
      }
      final json = jsonDecode(raw) as Map<String, Object?>;
      await save(AppSnapshot.fromJson(json));
    } on Object catch (error) {
      if (!isRecoverableStoreFormatError(error)) {
        rethrow;
      }
      await preserveInvalidStoreFile(legacy);
    }
  }
}
