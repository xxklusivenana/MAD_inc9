import 'package:flutter/material.dart';
import 'database_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final helper = DatabaseHelper();

  try {
    await helper.init();
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

    return;
  }

  runApp(
    DirectoryApp(helper: helper),
  );
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
    );
  }
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
    if (_busy) return;

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
    final age = int.tryParse(
      _ageController.text.trim(),
    );

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
            _feedback =
                'Guest ID $_editingId was not found.';
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
          _feedback =
              'Guest saved with ID $id.';
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
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Guest?'),
          content: Text(
            'Are you sure you want to delete '
            'guest ID $id ($name)?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteGuest(id);
    } else if (confirmed == false && mounted) {
      setState(() {
        _feedback =
            'Deletion cancelled. No changes were made.';
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
          _feedback =
              'Guest ID $id deleted successfully.';
        });
      } else {
        setState(() {
          _feedback =
              'Guest ID $id was not found.';
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
                    color: Theme.of(context)
                        .colorScheme
                        .error,
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
                if (value == null ||
                    value.trim().isEmpty) {
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
                final age = int.tryParse(
                  value?.trim() ?? '',
                );

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
                    onPressed:
                        _busy ? null : _saveGuest,
                    icon: Icon(
                      _isEditing
                          ? Icons.save
                          : Icons.person_add,
                    ),
                    label: Text(
                      _isEditing
                          ? 'Save'
                          : 'Add Guest',
                    ),
                  ),
                ),

                if (_isEditing) ...[
                  const SizedBox(width: 8),

                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _busy ? null : _cancelEdit,
                      child: const Text(
                        'Cancel Edit',
                      ),
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
            onPressed:
                _busy ? null : _loadGuests,
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
            style: TextStyle(
              fontSize: 18,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _guests.length,
      itemBuilder: (context, index) {
        final guest = _guests[index];

        final id =
            guest[DatabaseHelper.columnId] as int;

        final name =
            guest[DatabaseHelper.columnName] as String;

        final age =
            guest[DatabaseHelper.columnAge] as int;

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text('$id'),
            ),

            title: Text(name),

            subtitle: Text(
              'ID: $id   •   Age: $age',
            ),

            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit guest',
                  onPressed: _busy
                      ? null
                      : () => _editGuest(guest),
                  icon: const Icon(Icons.edit),
                ),

                IconButton(
                  tooltip: 'Delete guest',
                  onPressed: _busy
                      ? null
                      : () => _confirmDelete(
                            guest,
                          ),
                  icon: const Icon(
                    Icons.delete,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}