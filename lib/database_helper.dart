
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static const _databaseName = 'MyDatabase.db';
  static const _databaseVersion = 2;

  // Guest roster table
  static const table = 'my_table';
  static const columnId = '_id';
  static const columnName = 'name';
  static const columnAge = 'age';

  // Card Catalogue tables
  static const foldersTable = 'folders';
  static const cardsTable = 'cards';

  late Database _db;

  // Open the database, enable foreign key support
  Future<void> init() async {
    final documentsDirectory =
        await getApplicationDocumentsDirectory();

    final databasePath =
        join(documentsDirectory.path, _databaseName);

    _db = await openDatabase(
      databasePath,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // when the database is first created
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $table (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL,
        $columnAge INTEGER NOT NULL
      )
    ''');

    await _createCatalogueTables(db);
  }

  // Upgrade without removing guest records
  Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createCatalogueTables(db);
    }
  }

  Future<void> _createCatalogueTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $foldersTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $cardsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        suit TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        image_ref TEXT,
        folder_id INTEGER NOT NULL,
        FOREIGN KEY (folder_id)
          REFERENCES $foldersTable(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cards_folder_id
      ON $cardsTable(folder_id)
    ''');
  }

  // guest roster crud
  Future<int> insert(Map<String, dynamic> row) async {
    return _db.insert(table, row);
  }

  Future<List<Map<String, dynamic>>> queryAllRows() async {
    return _db.query(
      table,
      orderBy: '$columnId ASC',
    );
  }

  Future<int> queryRowCount() async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) FROM $table',
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> update(Map<String, dynamic> row) async {
    final id = row[columnId] as int;

    return _db.update(
      table,
      row,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  Future<int> delete(int id) async {
    return _db.delete(
      table,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  // folder operations
  Future<List<Folder>> getFoldersWithCounts() async {
    final rows = await _db.rawQuery('''
      SELECT
        f.id,
        f.name,
        f.created_at,
        COUNT(c.id) AS card_count
      FROM $foldersTable AS f
      LEFT JOIN $cardsTable AS c
        ON c.folder_id = f.id
      GROUP BY f.id, f.name, f.created_at
      ORDER BY f.name COLLATE NOCASE ASC
    ''');

    return rows
        .map((row) => Folder.fromMap(row))
        .toList();
  }

  Future<int> insertFolder(String name) async {
    final cleanedName = name.trim();

    if (cleanedName.isEmpty) {
      throw ArgumentError('Folder name cannot be empty.');
    }

    return _db.insert(
      foldersTable,
      {
        'name': cleanedName,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  // The foreign key ON DELETE CASCADE handles cards
  Future<int> deleteFolder(int id) async {
    return _db.delete(
      foldersTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // card operations
  // Get every card belonging to a specific folder.
  Future<List<CardRecord>> getCards(int folderId) async {
    final rows = await _db.query(
      cardsTable,
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );

    return rows
        .map((row) => CardRecord.fromMap(row))
        .toList();
  }

  Future<int> insertCard({
    required String title,
    required String suit,
    String notes = '',
    String? imageRef,
    required int folderId,
  }) async {
    final card = CardRecord(
      title: title,
      suit: suit,
      notes: notes,
      imageRef: imageRef,
      folderId: folderId,
    );

    _validateCard(card);

    return _db.insert(
      cardsTable,
      card.toMap(),
    );
  }

  Future<int> updateCard({
    required int id,
    required String title,
    required String suit,
    String notes = '',
    String? imageRef,
    required int folderId,
  }) async {
    final card = CardRecord(
      id: id,
      title: title,
      suit: suit,
      notes: notes,
      imageRef: imageRef,
      folderId: folderId,
    );

    _validateCard(card);

    return _db.update(
      cardsTable,
      card.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCard(int id) async {
    return _db.delete(
      cardsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  void _validateCard(CardRecord card) {
    if (card.title.trim().isEmpty) {
      throw ArgumentError('Card title cannot be empty.');
    }

    const allowedSuits = {
      'Hearts',
      'Diamonds',
      'Clubs',
      'Spades',
      'Other',
    };

    if (!allowedSuits.contains(card.suit)) {
      throw ArgumentError('Invalid card suit.');
    }

    if (card.folderId <= 0) {
      throw ArgumentError('A valid folder is required.');
    }
  }

  // database
  Future<int> getSchemaVersion() async {
    final result = await _db.rawQuery('PRAGMA user_version');

    return result.first.values.first as int;
  }

  Future<int> getForeignKeysEnabled() async {
    final result =
        await _db.rawQuery('PRAGMA foreign_keys');

    return result.first.values.first as int;
  }

  Future<List<Map<String, Object?>>> getCardForeignKeys() async {
    return _db.rawQuery(
      'PRAGMA foreign_key_list($cardsTable)',
    );
  }

  Future<List<Map<String, Object?>>> getCardIndexes() async {
    return _db.rawQuery(
      'PRAGMA index_list($cardsTable)',
    );
  }

  Future<List<Map<String, Object?>>> getGuestDiagnostics() async {
    return _db.rawQuery('''
      SELECT $columnId, $columnName, $columnAge
      FROM $table
      ORDER BY $columnId ASC
    ''');
  }

  // Close the database when its no longer needed
  Future<void> close() async {
    if (_db.isOpen) {
      await _db.close();
    }
  }
}

// folder model
class Folder {
  final int id;
  final String name;
  final String createdAt;
  final int cardCount;

  const Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.cardCount = 0,
  });

  factory Folder.fromMap(Map<String, Object?> map) {
    return Folder(
      id: map['id'] as int,
      name: map['name'] as String,
      createdAt: map['created_at'] as String,
      cardCount: (map['card_count'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt,
    };
  }
}

// card model
class CardRecord {
  final int? id;
  final String title;
  final String suit;
  final String notes;
  final String? imageRef;
  final int folderId;

  const CardRecord({
    this.id,
    required this.title,
    required this.suit,
    this.notes = '',
    this.imageRef,
    required this.folderId,
  });

  factory CardRecord.fromMap(Map<String, Object?> map) {
    return CardRecord(
      id: map['id'] as int,
      title: map['title'] as String,
      suit: map['suit'] as String,
      notes: (map['notes'] as String?) ?? '',
      imageRef: map['image_ref'] as String?,
      folderId: map['folder_id'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'title': title.trim(),
      'suit': suit,
      'notes': notes.trim(),
      'image_ref': imageRef,
      'folder_id': folderId,
    };
  }
}
