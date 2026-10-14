import 'package:flutter/material.dart';
import 'database_helper.dart';

// part 1
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final helper = DatabaseHelper();

  try {
    await helper.init();
    runApp(DirectoryApp(helper: helper));
  } catch (error, stackTrace) {
    debugPrint(
      'Database initialization failed: $error\n$stackTrace',
    );

    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Could not open local storage. '
              'Restart the app and check the logs.',
            ),
          ),
        ),
      ),
    );
  }
}

class DirectoryApp extends StatelessWidget {
  const DirectoryApp({
    super.key,
    required this.helper,
  });

  final DatabaseHelper helper;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fall Festival Roster',
      home: RosterScreen(helper: helper),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
        ),
        useMaterial3: true,
      ),
    );
  }
}

// top nav
void openCatalogue(BuildContext context, DatabaseHelper helper) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CatalogueScreen(helper: helper),
    ),
  );
}

void openFolders(BuildContext context, DatabaseHelper helper) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FoldersScreen(helper: helper),
    ),
  );
}

void openCards(BuildContext context, DatabaseHelper helper) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CardsScreen(helper: helper),
    ),
  );
}

List<Widget> navigationButtons(
  BuildContext context,
  DatabaseHelper helper,
) {
  return [
    IconButton(
      tooltip: 'Catalogue',
      icon: const Icon(Icons.dashboard_outlined),
      onPressed: () => openCatalogue(context, helper),
    ),
    IconButton(
      tooltip: 'Folders',
      icon: const Icon(Icons.folder_outlined),
      onPressed: () => openFolders(context, helper),
    ),
    IconButton(
      tooltip: 'Cards',
      icon: const Icon(Icons.style_outlined),
      onPressed: () => openCards(context, helper),
    ),
  ];
}

class RosterScreen extends StatefulWidget {
  const RosterScreen({
    super.key,
    required this.helper,
  });

  final DatabaseHelper helper;

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _ageController = TextEditingController();

  List<Map<String, dynamic>> _guests = [];

  int _count = 0;
  int? _editingId;

  bool _loading = true;
  bool _busy = false;

  String? _errorMessage;
  String _feedback = '';

  bool get _isEditing => _editingId != null;

  @override
  void initState() {
    super.initState();
    _loadGuests();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _loadGuests() async {
    if (!mounted || _busy) return;

    setState(() {
      _busy = true;
      _loading = true;
      _errorMessage = null;
    });

    try {
      final guests = await widget.helper.queryAllRows();
      final count = await widget.helper.queryRowCount();

      if (!mounted) return;

      setState(() {
        _guests = guests;
        _count = count;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Database read failed: $error\n$stackTrace',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage =
            'Could not load the roster. Tap Refresh to try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _saveGuest() async {
    if (_busy) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _nameController.text.trim();
    final age = int.tryParse(_ageController.text.trim());

    if (age == null || age < 0 || age > 130) {
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      if (_isEditing) {
        final updated = await widget.helper.update({
          DatabaseHelper.columnId: _editingId,
          DatabaseHelper.columnName: name,
          DatabaseHelper.columnAge: age,
        });

        if (!mounted) return;

        if (updated == 1) {
          setState(() {
            _feedback =
                'Guest ID $_editingId updated successfully.';
          });

          _clearForm();
        } else {
          setState(() {
            _feedback = 'Guest ID $_editingId was not found.';
          });
        }
      } else {
        // Add a new guest.
        final id = await widget.helper.insert({
          DatabaseHelper.columnName: name,
          DatabaseHelper.columnAge: age,
        });

        if (!mounted) return;

        setState(() {
          _feedback = 'Guest saved with ID $id.';
        });

        _clearForm();
      }

      // Reload the list after the database operation
      final guests = await widget.helper.queryAllRows();
      final count = await widget.helper.queryRowCount();

      if (!mounted) return;

      setState(() {
        _guests = guests;
        _count = count;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Database write failed: $error\n$stackTrace',
      );

      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Could not save the guest. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _editGuest(Map<String, dynamic> guest) {
    if (_busy) return;

    final id = guest[DatabaseHelper.columnId] as int;
    final name = guest[DatabaseHelper.columnName] as String;
    final age = guest[DatabaseHelper.columnAge] as int;

    setState(() {
      _editingId = id;
      _nameController.text = name;
      _ageController.text = age.toString();
      _feedback = 'Editing guest ID $id.';
      _errorMessage = null;
    });
  }

  void _cancelEdit() { // without changing database
    if (_busy) return;

    _clearForm();

    setState(() {
      _feedback = 'Edit cancelled. No changes were saved.';
    });
  }

  void _clearForm() {
    _editingId = null;
    _nameController.clear();
    _ageController.clear();
  }

  Future<void> _confirmDelete(
    Map<String, dynamic> guest,
  ) async {
    if (_busy) return;

    final id = guest[DatabaseHelper.columnId] as int;
    final name = guest[DatabaseHelper.columnName] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Guest?'),
          content: Text(
            'Are you sure you want to delete '
            'guest ID $id ($name)?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (confirmed == true) {
      await _deleteGuest(id);
    } else if (confirmed == false) {
      setState(() {
        _feedback = 'Deletion cancelled. No changes were made.';
      });
    }
  }

  Future<void> _deleteGuest(int id) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final deleted = await widget.helper.delete(id);

      if (!mounted) return;

      if (deleted == 1) {
        if (_editingId == id) {
          _clearForm();
        }

        setState(() {
          _feedback = 'Guest ID $id deleted successfully.';
        });
      } else {
        setState(() {
          _feedback = 'Guest ID $id was not found.';
        });
      }

      // Reload the list after deletion
      final guests = await widget.helper.queryAllRows();
      final count = await widget.helper.queryRowCount();

      if (!mounted) return;

      setState(() {
        _guests = guests;
        _count = count;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Database delete failed: $error\n$stackTrace',
      );

      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Could not delete the guest. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fall Festival Roster'),
        actions: navigationButtons(context, widget.helper),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildForm(),
            _buildRosterHeader(),
            if (_feedback.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_feedback),
                ),
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            Expanded(
              child: _buildGuestList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _nameController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Guest Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a guest name.';
                }

                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ageController,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Age',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final age = int.tryParse(value?.trim() ?? '');

                if (age == null) {
                  return 'Age must be a whole number.';
                }

                if (age < 0 || age > 130) {
                  return 'Age must be between 0 and 130.';
                }

                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _saveGuest,
                    icon: Icon(
                      _isEditing ? Icons.save : Icons.person_add,
                    ),
                    label: Text(
                      _isEditing ? 'Save' : 'Add Guest',
                    ),
                  ),
                ),
                if (_isEditing) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _cancelEdit,
                      child: const Text('Cancel Edit'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRosterHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      child: Row(
        children: [
          Text(
            'Record Count: $_count',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _busy ? null : _loadGuests,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_guests.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No festival guests yet.\n'
            'Add your first guest to the roster!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _guests.length,
      itemBuilder: (context, index) {
        final guest = _guests[index];

        final id = guest[DatabaseHelper.columnId] as int;
        final name = guest[DatabaseHelper.columnName] as String;
        final age = guest[DatabaseHelper.columnAge] as int;

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text('$id'),
            ),
            title: Text(name),
            subtitle: Text('ID: $id   •   Age: $age'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit guest',
                  onPressed: _busy ? null : () => _editGuest(guest),
                  icon: const Icon(Icons.edit),
                ),
                IconButton(
                  tooltip: 'Delete guest',
                  onPressed: _busy
                      ? null
                      : () => _confirmDelete(guest),
                  icon: const Icon(Icons.delete),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Part 2
class CatalogueScreen extends StatelessWidget {
  const CatalogueScreen({super.key, required this.helper});

  final DatabaseHelper helper;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Card Catalogue'),
        actions: navigationButtons(context, helper),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.collections_bookmark, size: 72),
          const SizedBox(height: 12),
          Text(
            'Your Card Catalogue',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Organize your cards into folders. Open a folder to '
            'add cards, edit their details, or remove cards.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _DashboardTile(
            icon: Icons.folder_open,
            title: 'Folders',
            subtitle: 'Create and manage card folders',
            onTap: () => openFolders(context, helper),
          ),
          _DashboardTile(
            icon: Icons.style,
            title: 'Cards',
            subtitle: 'Browse the cards stored in your folders',
            onTap: () => openCards(context, helper),
          ),
          _DashboardTile(
            icon: Icons.people_alt_outlined,
            title: 'Fall Festival Roster',
            subtitle: 'Return to the guest list',
            onTap: () => Navigator.popUntil(
              context,
              (route) => route.isFirst,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  const _DashboardTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// folder screen
class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key, required this.helper});

  final DatabaseHelper helper;

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  List<Folder> _folders = [];
  bool _loading = true;
  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    if (!mounted || _busy) return;

    setState(() {
      _busy = true;
      _loading = true;
      _errorMessage = null;
    });

    try {
      final folders = await widget.helper.getFoldersWithCounts();

      if (!mounted) return;

      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load folders: $error\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = 'Could not load folders. Please refresh.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _addFolder() async {
    if (_busy) return;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _FolderNameDialog(),
    );

    if (!mounted || name == null) return;

    if (name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a folder name.'),
        ),
      );
      return;
    }

    if (_busy) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      await widget.helper.insertFolder(name.trim());

      final folders = await widget.helper.getFoldersWithCounts();

      if (!mounted) return;

      setState(() {
        _folders = folders;
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Folder "${name.trim()}" created.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not create folder: $error\n$stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not create folder. Check that its name is unique.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Folder?'),
        content: Text(
          'Delete "${folder.name}" and all cards inside it? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true || _busy) return;

    setState(() {
      _busy = true;
    });

    try {
      await widget.helper.deleteFolder(folder.id);
      final folders = await widget.helper.getFoldersWithCounts();

      if (!mounted) return;

      setState(() {
        _folders = folders;
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${folder.name}" deleted.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not delete folder: $error\n$stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete the folder.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openFolder(Folder folder) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderCardsScreen(
          helper: widget.helper,
          folder: folder,
        ),
      ),
    );

    if (mounted) {
      await _loadFolders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Folders'),
        actions: [
          ...navigationButtons(context, widget.helper),
          IconButton(
            tooltip: 'Refresh folders',
            onPressed: _busy ? null : _loadFolders,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addFolder,
        icon: const Icon(Icons.create_new_folder),
        label: const Text('Add Folder'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_errorMessage!),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _busy ? null : _loadFolders,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _folders.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No folders yet.\n'
                          'Tap "Add Folder" to create your first folder.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                        left: 12,
                        right: 12,
                        top: 12,
                        bottom: 90,
                      ),
                      itemCount: _folders.length,
                      itemBuilder: (context, index) {
                        final folder = _folders[index];

                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.folder),
                            ),
                            title: Text(folder.name),
                            subtitle: Text(
                              '${folder.cardCount} '
                              '${folder.cardCount == 1 ? 'card' : 'cards'}',
                            ),
                            onTap: _busy
                                ? null
                                : () => _openFolder(folder),
                            trailing: PopupMenuButton<String>(
                              enabled: !_busy,
                              onSelected: (value) {
                                if (value == 'open') {
                                  _openFolder(folder);
                                } else if (value == 'delete') {
                                  _deleteFolder(folder);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'open',
                                  child: Text('Open folder'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete folder'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog();

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a folder name.'),
        ),
      );
      return;
    }

    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Folder'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Folder name',
          hintText: 'Example: Favorite Cards',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

// card screen
class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key, required this.helper});

  final DatabaseHelper helper;

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  List<Folder> _folders = [];
  List<CardRecord> _cards = [];

  int? _selectedFolderId;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final folders = await widget.helper.getFoldersWithCounts();

      if (!mounted) return;

      final selectedId = folders.any(
        (folder) => folder.id == _selectedFolderId,
      )
          ? _selectedFolderId
          : folders.isNotEmpty
              ? folders.first.id
              : null;

      setState(() {
        _folders = folders;
        _selectedFolderId = selectedId;
      });

      await _loadCards();
    } catch (error, stackTrace) {
      debugPrint('Could not load folders: $error\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = 'Could not load your folders.';
      });
    }
  }

  Future<void> _loadCards() async {
    if (_selectedFolderId == null) {
      if (!mounted) return;

      setState(() {
        _cards = [];
        _loading = false;
      });
      return;
    }

    try {
      final cards = await widget.helper.getCards(_selectedFolderId!);

      if (!mounted) return;

      setState(() {
        _cards = cards;
        _loading = false;
        _errorMessage = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load cards: $error\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = 'Could not load cards.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cards'),
        actions: navigationButtons(context, widget.helper),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_errorMessage!),
                      FilledButton(
                        onPressed: _loadFolders,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _folders.isEmpty
                  ? const Center(
                      child: Text(
                        'No folders yet.\nCreate a folder first.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: DropdownButtonFormField<int>(
                            initialValue: _selectedFolderId,
                            decoration: const InputDecoration(
                              labelText: 'Choose a folder',
                              border: OutlineInputBorder(),
                            ),
                            items: _folders.map((folder) {
                              return DropdownMenuItem<int>(
                                value: folder.id,
                                child: Text(folder.name),
                              );
                            }).toList(),
                            onChanged: (id) async {
                              setState(() {
                                _selectedFolderId = id;
                                _loading = true;
                              });
                              await _loadCards();
                            },
                          ),
                        ),
                        Expanded(
                          child: _cards.isEmpty
                              ? const Center(
                                  child: Text(
                                    'This folder has no cards yet.',
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _cards.length,
                                  itemBuilder: (context, index) {
                                    final card = _cards[index];

                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      child: ListTile(
                                        leading: CardArtwork(
                                          suit: card.suit,
                                          imageRef: card.imageRef,
                                        ),
                                        title: Text(card.title),
                                        subtitle: Text(
                                          'Card ID: ${card.id ?? 'Unknown'}\n'
                                          'Suit: ${card.suit}'
                                          '${card.notes.isEmpty ? '' : '\nNotes: ${card.notes}'}',
                                        ),
                                        isThreeLine: card.notes.isNotEmpty,
                                        onTap: () async {
                                          final folder = _folders.firstWhere(
                                            (f) => f.id == card.folderId,
                                          );

                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => FolderCardsScreen(
                                                helper: widget.helper,
                                                folder: folder,
                                              ),
                                            ),
                                          );

                                          if (mounted) {
                                            await _loadFolders();
                                          }
                                        },
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
    );
  }
}

// folder card screen
class FolderCardsScreen extends StatefulWidget {
  const FolderCardsScreen({
    super.key,
    required this.helper,
    required this.folder,
  });

  final DatabaseHelper helper;
  final Folder folder;

  @override
  State<FolderCardsScreen> createState() => _FolderCardsScreenState();
}

class _FolderCardsScreenState extends State<FolderCardsScreen> {
  List<CardRecord> _cards = [];
  bool _loading = true;
  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final cards = await widget.helper.getCards(widget.folder.id);

      if (!mounted) return;

      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load cards: $error\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = 'Could not load cards. Please refresh.';
      });
    }
  }

  Future<void> _showCardForm({CardRecord? card}) async {
    if (_busy) return;

    final result = await showDialog<CardFormResult>(
      context: context,
      builder: (_) => CardFormDialog(card: card),
    );

    if (result == null || !mounted || _busy) return;

    setState(() => _busy = true);

    try {
      if (card == null) {
        await widget.helper.insertCard(
          title: result.title,
          suit: result.suit,
          notes: result.notes,
          imageRef: result.imageRef,
          folderId: widget.folder.id,
        );
      } else {
        if (card.id == null) {
          throw StateError('Cannot edit a card without an ID.');
        }

        await widget.helper.updateCard(
          id: card.id!,
          title: result.title,
          suit: result.suit,
          notes: result.notes,
          imageRef: result.imageRef,
          folderId: widget.folder.id,
        );
      }

      await _loadCards();
    } catch (error, stackTrace) {
      debugPrint('Could not save card: $error\n$stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save card. Check the title and folder.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCard(CardRecord card) async {
    if (_busy || card.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Card?'),
        content: Text('Delete "${card.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true || _busy) return;

    setState(() => _busy = true);

    try {
      await widget.helper.deleteCard(card.id!);
      await _loadCards();
    } catch (error, stackTrace) {
      debugPrint('Could not delete card: $error\n$stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete card.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folder.name),
        actions: navigationButtons(context, widget.helper),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _showCardForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Card'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_errorMessage!),
                      FilledButton(
                        onPressed: _loadCards,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _cards.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No cards in this folder yet.\n'
                          'Tap "Add Card" to add your first card.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                        left: 12,
                        right: 12,
                        top: 12,
                        bottom: 90,
                      ),
                      itemCount: _cards.length,
                      itemBuilder: (context, index) {
                        final card = _cards[index];

                        return Card(
                          child: ListTile(
                            leading: CardArtwork(
                              suit: card.suit,
                              imageRef: card.imageRef,
                            ),
                            title: Text(card.title),
                            subtitle: Text(
                              'Card ID: ${card.id ?? 'Unknown'}\n'
                              'Suit: ${card.suit}'
                              '${card.notes.isEmpty ? '' : '\nNotes: ${card.notes}'}',
                            ),
                            isThreeLine: card.notes.isNotEmpty,
                            trailing: PopupMenuButton<String>(
                              enabled: !_busy,
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showCardForm(card: card);
                                } else if (value == 'delete') {
                                  _deleteCard(card);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit card'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete card'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

// card form
class CardFormResult {
  const CardFormResult({
    required this.title,
    required this.suit,
    required this.notes,
    required this.imageRef,
  });

  final String title;
  final String suit;
  final String notes;
  final String? imageRef;
}

class CardFormDialog extends StatefulWidget {
  const CardFormDialog({super.key, this.card});

  final CardRecord? card;

  @override
  State<CardFormDialog> createState() => _CardFormDialogState();
}

class _CardFormDialogState extends State<CardFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _imageController;

  static const List<String> _suits = [
    'Hearts',
    'Diamonds',
    'Clubs',
    'Spades',
    'Other',
  ];

  late String _suit;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.card?.title ?? '',
    );

    _notesController = TextEditingController(
      text: widget.card?.notes ?? '',
    );

    _imageController = TextEditingController(
      text: widget.card?.imageRef ?? '',
    );

    final existingSuit = widget.card?.suit ?? 'Hearts';
    _suit = _suits.contains(existingSuit) ? existingSuit : 'Other';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final image = _imageController.text.trim();

    Navigator.pop(
      context,
      CardFormResult(
        title: _titleController.text.trim(),
        suit: _suit,
        notes: _notesController.text.trim(),
        imageRef: image.isEmpty ? null : image,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.card == null ? 'Add Card' : 'Edit Card'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Card title',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a card title.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _suit,
                decoration: const InputDecoration(
                  labelText: 'Suit',
                  border: OutlineInputBorder(),
                ),
                items: _suits.map((suit) {
                  return DropdownMenuItem(
                    value: suit,
                    child: Text(suit),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _suit = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _imageController,
                decoration: const InputDecoration(
                  labelText: 'Image URL (optional)',
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Leave the image field blank to use the suit symbol.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// fallback
class CardArtwork extends StatelessWidget {
  const CardArtwork({
    super.key,
    required this.suit,
    this.imageRef,
  });

  final String suit;
  final String? imageRef;

  IconData get _suitIcon {
    switch (suit) {
      case 'Hearts':
        return Icons.favorite;
      case 'Diamonds':
        return Icons.diamond;
      case 'Clubs':
        return Icons.filter_vintage;
      case 'Spades':
        return Icons.spa;
      default:
        return Icons.style;
    }
  }

  Color get _suitColor {
    if (suit == 'Hearts' || suit == 'Diamonds') {
      return Colors.red;
    }
    return Colors.black87;
  }

  @override
  Widget build(BuildContext context) {
    final reference = imageRef?.trim() ?? '';

    if (reference.startsWith('https://') ||
        reference.startsWith('http://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          reference,
          width: 48,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _fallback();
          },
        ),
      );
    }

    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: 48,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _suitIcon,
        color: _suitColor,
        size: 30,
      ),
    );
  }
}