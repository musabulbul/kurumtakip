import 'package:flutter/material.dart';

typedef SendResultsCallback = Future<void> Function(
  BuildContext context, {
  required bool parent1,
  required bool parent2,
  required bool student,
});

Future<bool?> showSendResultsSheet({
  required BuildContext context,
  required int selectedCount,
  required SendResultsCallback onSend,
  String? description,
  String actionLabel = 'SMS Gönder',
  IconData actionIcon = Icons.sms,
  bool singleSelection = false,
  String? parent1Info,
  String? parent2Info,
  String? studentInfo,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _SendResultsSheet(
      selectedCount: selectedCount,
      onSend: onSend,
      description: description,
      actionLabel: actionLabel,
      actionIcon: actionIcon,
      singleSelection: singleSelection,
      parent1Info: parent1Info,
      parent2Info: parent2Info,
      studentInfo: studentInfo,
    ),
  );
}

class _SendResultsSheet extends StatefulWidget {
  const _SendResultsSheet({
    required this.selectedCount,
    required this.onSend,
    required this.actionLabel,
    required this.actionIcon,
    this.description,
    this.singleSelection = false,
    this.parent1Info,
    this.parent2Info,
    this.studentInfo,
  });

  final int selectedCount;
  final SendResultsCallback onSend;
  final String? description;
  final String actionLabel;
  final IconData actionIcon;
  final bool singleSelection;
  final String? parent1Info;
  final String? parent2Info;
  final String? studentInfo;

  @override
  State<_SendResultsSheet> createState() => _SendResultsSheetState();
}

class _SendResultsSheetState extends State<_SendResultsSheet> {
  bool _parent1 = true;
  bool _parent2 = false;
  bool _student = false;
  bool _isSending = false;
  String? _selectedRecipient;

  @override
  void initState() {
    super.initState();
    if (widget.singleSelection) {
      if (widget.parent1Info != null) {
        _selectedRecipient = 'parent1';
        _parent1 = true;
        _parent2 = false;
        _student = false;
      } else if (widget.parent2Info != null) {
        _selectedRecipient = 'parent2';
        _parent1 = false;
        _parent2 = true;
        _student = false;
      } else if (widget.studentInfo != null) {
        _selectedRecipient = 'student';
        _parent1 = false;
        _parent2 = false;
        _student = true;
      } else {
        _selectedRecipient = null;
        _parent1 = false;
        _parent2 = false;
        _student = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.description ??
                (widget.selectedCount == 1
                    ? 'Seçili sınav sonucu SMS ile gönderilecek.'
                    : '${widget.selectedCount} öğrencinin sonuçları SMS ile gönderilecek.'),
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (widget.singleSelection)
            ..._buildRadioOptions()
          else ...[
            CheckboxListTile(
              dense: true,
              value: _parent1,
              onChanged: (value) => setState(() => _parent1 = value ?? false),
              title: const Text('1. Veli'),
              subtitle:
                  widget.parent1Info == null ? null : Text(widget.parent1Info!),
            ),
            CheckboxListTile(
              dense: true,
              value: _parent2,
              onChanged: (value) => setState(() => _parent2 = value ?? false),
              title: const Text('2. Veli'),
              subtitle:
                  widget.parent2Info == null ? null : Text(widget.parent2Info!),
            ),
            CheckboxListTile(
              dense: true,
              value: _student,
              onChanged: (value) => setState(() => _student = value ?? false),
              title: const Text('Öğrenci'),
              subtitle:
                  widget.studentInfo == null ? null : Text(widget.studentInfo!),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isSending
                ? null
                : () async {
                    if (widget.singleSelection) {
                      if (_selectedRecipient == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Lütfen bir alıcı seçiniz.')),
                        );
                        return;
                      }
                      setState(() => _isSending = true);
                      try {
                        await widget.onSend(
                          context,
                          parent1: _selectedRecipient == 'parent1',
                          parent2: _selectedRecipient == 'parent2',
                          student: _selectedRecipient == 'student',
                        );
                      } finally {
                        if (mounted) setState(() => _isSending = false);
                      }
                      return;
                    }

                    if (!_parent1 && !_parent2 && !_student) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('En az bir alıcı seçiniz.')),
                      );
                      return;
                    }
                    setState(() => _isSending = true);
                    try {
                      await widget.onSend(
                        context,
                        parent1: _parent1,
                        parent2: _parent2,
                        student: _student,
                      );
                    } finally {
                      if (mounted) setState(() => _isSending = false);
                    }
                  },
            icon: _isSending
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(widget.actionIcon),
            label: Text(widget.actionLabel),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRadioOptions() {
    Widget? subtitle(String? info) => info == null ? const Text('Telefon bulunamadı') : Text(info);

    final hasParent1 = widget.parent1Info != null;
    final hasParent2 = widget.parent2Info != null;
    final hasStudent = widget.studentInfo != null;

    return [
      RadioListTile<String>(
        dense: true,
        value: 'parent1',
        groupValue: _selectedRecipient,
        onChanged: hasParent1
            ? (value) => setState(() {
                  _selectedRecipient = value;
                  _parent1 = value == 'parent1';
                  _parent2 = value == 'parent2';
                  _student = value == 'student';
                })
            : null,
        title: const Text('1. Veli'),
        subtitle: subtitle(widget.parent1Info),
      ),
      RadioListTile<String>(
        dense: true,
        value: 'parent2',
        groupValue: _selectedRecipient,
        onChanged: hasParent2
            ? (value) => setState(() {
                  _selectedRecipient = value;
                  _parent1 = value == 'parent1';
                  _parent2 = value == 'parent2';
                  _student = value == 'student';
                })
            : null,
        title: const Text('2. Veli'),
        subtitle: subtitle(widget.parent2Info),
      ),
      RadioListTile<String>(
        dense: true,
        value: 'student',
        groupValue: _selectedRecipient,
        onChanged: hasStudent
            ? (value) => setState(() {
                  _selectedRecipient = value;
                  _parent1 = value == 'parent1';
                  _parent2 = value == 'parent2';
                  _student = value == 'student';
                })
            : null,
        title: const Text('Öğrenci'),
        subtitle: subtitle(widget.studentInfo),
      ),
    ];
  }
}
