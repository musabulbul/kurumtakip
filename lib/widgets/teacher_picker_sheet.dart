import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TeacherSelectionResult {
  const TeacherSelectionResult({
    required this.teacherId,
    required this.teacherName,
    this.branch = '',
    this.phone = '',
  });

  final String teacherId;
  final String teacherName;
  final String branch;
  final String phone;
}

Future<TeacherSelectionResult?> showTeacherPickerSheet({
  required BuildContext context,
  required String institutionId,
}) {
  return showModalBottomSheet<TeacherSelectionResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => TeacherPickerSheet(institutionId: institutionId),
  );
}

class TeacherPickerSheet extends StatefulWidget {
  const TeacherPickerSheet({super.key, required this.institutionId});

  final String institutionId;

  @override
  State<TeacherPickerSheet> createState() => _TeacherPickerSheetState();
}

class _TeacherPickerSheetState extends State<TeacherPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _TeacherOption? _selectedTeacher;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleQueryChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    setState(() {
      _query = _searchController.text.trim().toLowerCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: viewInsets.bottom) +
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('kurumlar')
                      .doc(widget.institutionId)
                      .collection('ogretmenler')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Öğretmen listesi yüklenemedi: ${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? const [];
                    if (docs.isEmpty) {
                      return _buildEmptyPlaceholder(context);
                    }

                    final teachers = docs.map((doc) {
                      final data = doc.data();
                      final firstName = (data['adi'] ?? '').toString().trim();
                      final lastName = (data['soyadi'] ?? '').toString().trim();
                      final branch = (data['alani'] ?? '').toString().trim();
                      final phone = (data['telefon'] ?? '').toString().trim();
                      return _TeacherOption(
                        id: doc.id,
                        firstName: firstName,
                        lastName: lastName,
                        branch: branch,
                        phone: phone,
                      );
                    }).toList();

                    final filtered = _filterTeachers(teachers);
                    if (filtered.isEmpty) {
                      return _buildNoMatchPlaceholder(context);
                    }

                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final teacher = filtered[index];
                        final subtitleParts = <String>[
                          if (teacher.branch.isNotEmpty) teacher.branch,
                          if (teacher.phone.isNotEmpty) teacher.phone,
                        ];
                        final subtitle =
                            subtitleParts.isEmpty ? null : subtitleParts.join(' • ');
                        return RadioListTile<String>(
                          value: teacher.id,
                          groupValue: _selectedTeacher?.id,
                          onChanged: (_) => _selectTeacher(teacher),
                          title: Text(
                            teacher.fullName.isEmpty
                                ? 'İsimsiz Öğretmen'
                                : teacher.fullName,
                          ),
                          subtitle: subtitle != null ? Text(subtitle) : null,
                          selected: _selectedTeacher?.id == teacher.id,
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Vazgeç'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _handleConfirm,
                      icon: const Icon(Icons.check),
                      label: const Text('Onayla'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        labelText: 'Öğretmen ara',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                onPressed: _searchController.clear,
                icon: const Icon(Icons.clear),
              )
            : null,
      ),
    );
  }

  List<_TeacherOption> _filterTeachers(List<_TeacherOption> teachers) {
    if (_query.isEmpty) {
      return teachers;
    }
    return teachers.where((teacher) {
      final normalized = _query;
      final fullName = teacher.fullName.toLowerCase();
      final branch = teacher.branch.toLowerCase();
      final phone = teacher.phone.toLowerCase();
      return fullName.contains(normalized) ||
          branch.contains(normalized) ||
          phone.contains(normalized);
    }).toList(growable: false);
  }

  Widget _buildEmptyPlaceholder(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text(
            'Kayıtlı öğretmen bulunamadı.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoMatchPlaceholder(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text(
            'Arama kriterlerine uygun öğretmen bulunamadı.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _selectTeacher(_TeacherOption teacher) {
    setState(() {
      _selectedTeacher = teacher;
    });
  }

  void _handleConfirm() {
    final messenger = ScaffoldMessenger.of(context);
    final selected = _selectedTeacher;
    if (selected == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Lütfen bir öğretmen seçin.')),
      );
      return;
    }

    Navigator.of(context).pop(
      TeacherSelectionResult(
        teacherId: selected.id,
        teacherName: selected.fullName.isEmpty
            ? 'İsimsiz Öğretmen'
            : selected.fullName,
        branch: selected.branch,
        phone: selected.phone,
      ),
    );
  }
}

class _TeacherOption {
  _TeacherOption({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.branch,
    required this.phone,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String branch;
  final String phone;

  String get fullName {
    final parts = <String>[
      firstName,
      lastName,
    ].where((part) => part.trim().isNotEmpty).toList();

    if (parts.isEmpty) {
      return '';
    }

    return parts.join(' ').trim();
  }
}
