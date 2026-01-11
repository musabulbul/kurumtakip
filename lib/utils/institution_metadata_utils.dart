import 'dart:collection';

import '../controllers/institution_controller.dart';

const List<String> _defaultBranches = [
  'ŞUBE',
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'R',
  'S',
  'T',
  'U',
  'V',
  'Y',
  'Z',
];

const Map<String, List<String>> _defaultClassesByType = {
  'ANADOLU': ['SINIF', '9', '10', '11', '12'],
  'İHL': ['SINIF', '9', '10', '11', '12'],
  'ORTHAOKUL': ['SINIF', '5', '6', '7', '8'],
  'ORTAOKUL': ['SINIF', '5', '6', '7', '8'],
  'İLKOKUL': ['SINIF', '1', '2', '3', '4'],
  'SOSYAL': ['SINIF', '9', '10', '11', '12'],
  'MESLEK': ['SINIF', '9', '10', '11', '12'],
};

List<String> buildClassList(Map<String, dynamic> institutionData, {bool includePlaceholder = true}) {
  final raw = institutionData['siniflar'];
  final placeholder = includePlaceholder ? 'SINIF' : null;
  final classes = SplayTreeSet<String>();

  if (raw is Iterable) {
    for (final entry in raw) {
      final value = entry?.toString().trim();
      if (value != null && value.isNotEmpty) {
        classes.add(value);
      }
    }
  }

  if (classes.isEmpty) {
    final map = institutionData['sinifSubeHaritasi'];
    if (map is Map) {
      for (final entry in map.entries) {
        final key = entry.key?.toString().trim();
        if (key != null && key.isNotEmpty) {
          classes.add(key);
        }
      }
    } else {
      final combos = institutionData['sinifSubeler'];
      if (combos is Iterable) {
        for (final entry in combos) {
          final value = entry?.toString().trim().toUpperCase();
          if (value == null || value.isEmpty) continue;
          final match = RegExp(r'^(HAZIRLIK|HAZ\\.?|\\d{1,2})').firstMatch(value);
          if (match != null) {
            final normalized = match.group(0)!;
            classes.add(normalized.startsWith('HAZ') ? 'HAZ.' : normalized);
          }
        }
      }
    }
  }

  if (classes.isEmpty) {
    final type = (institutionData['kurumturu'] ?? '').toString().trim().toUpperCase();
    final defaults = _defaultClassesByType[type] ??
        (_defaultClassesByType['ANADOLU'] ??
            (includePlaceholder
                ? ['SINIF', '9', '10', '11', '12']
                : ['9', '10', '11', '12']));
    if (includePlaceholder) {
      return defaults;
    }
    return defaults.where((element) => element != 'SINIF').toList();
  }

  final list = classes.toList();
  if (includePlaceholder && (list.isEmpty || list.first != 'SINIF')) {
    list.insert(0, 'SINIF');
  }
  return list;
}

List<String> buildBranchList(Map<String, dynamic> institutionData, {bool includePlaceholder = true}) {
  final raw = institutionData['subeler'];
  final branches = SplayTreeSet<String>();
  if (raw is Iterable) {
    for (final entry in raw) {
      final value = entry?.toString().trim().toUpperCase();
      if (value != null && value.isNotEmpty) {
        branches.add(value);
      }
    }
  }

  if (branches.isEmpty) {
    final map = institutionData['sinifSubeHaritasi'];
    if (map is Map) {
      for (final entry in map.entries) {
        final value = entry.value;
        if (value is Iterable) {
          for (final branch in value) {
            final normalized = branch?.toString().trim().toUpperCase();
            if (normalized != null && normalized.isNotEmpty) {
              branches.add(normalized);
            }
          }
        }
      }
    } else {
      final combos = institutionData['sinifSubeler'];
      if (combos is Iterable) {
        for (final entry in combos) {
          final value = entry?.toString().trim().toUpperCase();
          if (value == null || value.isEmpty) continue;
          final match = RegExp(r'(HAZIRLIK|HAZ\.?|\d{1,2})([A-ZÇĞİÖŞÜ]{1,2})').firstMatch(value);
          if (match != null && match.groupCount >= 2) {
            branches.add(match.group(2)!);
          } else {
            final branchOnly = RegExp(r'([A-ZÇĞİÖŞÜ]{1,2})$').firstMatch(value);
            if (branchOnly != null) {
              branches.add(branchOnly.group(1)!);
            }
          }
        }
      }
    }
  }

  if (branches.isEmpty) {
    if (includePlaceholder) {
      return _defaultBranches;
    }
    return _defaultBranches.where((element) => element != 'ŞUBE').toList();
  }

  final list = branches.toList();
  if (includePlaceholder) {
    list.insert(0, 'ŞUBE');
  }
  return list;
}

Map<String, List<String>> buildClassBranchMap(Map<String, dynamic> institutionData) {
  final raw = institutionData['sinifSubeHaritasi'];
  final Map<String, List<String>> result = {};
  if (raw is Map) {
    raw.forEach((key, value) {
      if (key == null) return;
      final sinif = key.toString().trim();
      if (sinif.isEmpty) return;
      final branches = SplayTreeSet<String>();
      if (value is Iterable) {
        for (final entry in value) {
          final v = entry?.toString().trim().toUpperCase();
          if (v != null && v.isNotEmpty) {
            branches.add(v);
          }
        }
      }
      if (branches.isNotEmpty) {
        result[sinif] = branches.toList();
      }
    });
  }
  return result;
}

List<String> institutionClasses(InstitutionController controller, {bool includePlaceholder = true}) {
  return buildClassList(
    Map<String, dynamic>.from(controller.data),
    includePlaceholder: includePlaceholder,
  );
}

List<String> institutionBranches(InstitutionController controller, {bool includePlaceholder = true}) {
  return buildBranchList(
    Map<String, dynamic>.from(controller.data),
    includePlaceholder: includePlaceholder,
  );
}

Map<String, List<String>> institutionClassBranchMap(InstitutionController controller) {
  return buildClassBranchMap(Map<String, dynamic>.from(controller.data));
}

List<String> buildClassSectionList(Map<String, dynamic> institutionData, {bool includePlaceholder = false}) {
  final combos = SplayTreeSet<String>();

  final map = buildClassBranchMap(institutionData);
  if (map.isNotEmpty) {
    map.forEach((sinif, subeler) {
      if (subeler.isEmpty) {
        combos.add(sinif);
      } else {
        for (final sube in subeler) {
          combos.add('$sinif$sube');
        }
      }
    });
  } else {
    final raw = institutionData['sinifSubeler'];
    if (raw is Iterable) {
      for (final entry in raw) {
        final value = entry?.toString().trim().toUpperCase();
        if (value != null && value.isNotEmpty) {
          combos.add(value);
        }
      }
    }
  }

  if (combos.isEmpty) {
    return includePlaceholder ? ['SINIF/ŞUBE'] : <String>[];
  }

  final list = combos.toList();
  if (includePlaceholder) {
    list.insert(0, 'SINIF/ŞUBE');
  }
  return list;
}

List<String> institutionClassSections(InstitutionController controller, {bool includePlaceholder = false}) {
  return buildClassSectionList(
    Map<String, dynamic>.from(controller.data),
    includePlaceholder: includePlaceholder,
  );
}
