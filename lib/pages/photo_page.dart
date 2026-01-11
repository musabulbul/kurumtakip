import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_html/html.dart' as html;
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive.dart'; // Zip sıkıştırma için eklendi

import 'package:kurum_takip/controllers/institution_controller.dart';
import 'package:kurum_takip/controllers/user_controller.dart';
import 'package:kurum_takip/utils/institution_metadata_utils.dart';
import 'package:kurum_takip/utils/image_utils.dart';
import 'package:kurum_takip/utils/student_utils.dart';
import 'package:kurum_takip/widgets/home_icon_button.dart';

import 'danisan_profil.dart';

enum _PhotoMenuAction { bulkUpload, download }

class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key});

  @override
  _AraState createState() => _AraState();
}

class _AraState extends State<PhotoPage> {
  UserController user = Get.find<UserController>();
  InstitutionController kurum = Get.find<InstitutionController>();
  final TextEditingController _aramaController = TextEditingController();
  final RxList<Map<String, dynamic>> _aramaSonucu =
      <Map<String, dynamic>>[].obs;
  final RxBool _hasRequestedResults = false.obs;

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<String> notUploadedPhotos = [];

  List<Map<String, dynamic>> ogrenciler = [];

  var genel = "", sinif = "", sube = "";

  String dropDown1Value = "SINIF";
  String dropDown2Value = "ŞUBE";

  List<String> _classFilterOptions = const ['SINIF'];
  List<String> _branchFilterOptions = const ['ŞUBE'];
  Worker? _institutionWatcher;

  List<Map<String, dynamic>> filtre({
    genel = "",
    sinif = "",
    sube = "",
    no = "",
  }) {
    return ogrenciler.where((e) {
      bool matchesGenel = genel.isEmpty ||
          e["adi"].toString().toUpperCase().contains(genel.toUpperCase()) ||
          e["soyadi"].toString().toUpperCase().contains(genel.toUpperCase()) ||
          e["no"].toString().toUpperCase().contains(genel.toUpperCase());
      bool matchesSinif = sinif.isEmpty ||
          e["sinif"].toString().toUpperCase().contains(sinif.toUpperCase());
      bool matchesSube = sube.isEmpty ||
          e["sube"].toString().toUpperCase().contains(sube.toUpperCase());
      return matchesGenel && matchesSinif && matchesSube;
    }).toList();
  }

  void ara() {
    final aramaSonucu = filtre(
      genel: genel,
      sinif: sinif,
      sube: sube,
    );
    aramaSonucu.sort((a, b) {
      int? aValue =
          a["no"] is int ? a["no"] : int.tryParse(a["no"].toString());
      int? bValue =
          b["no"] is int ? b["no"] : int.tryParse(b["no"].toString());

      if (aValue == null && bValue == null) return 0;
      if (aValue == null) return -1;
      if (bValue == null) return 1;

      return aValue.compareTo(bValue);
    });

    _hasRequestedResults.value = true;
    _aramaSonucu.value = aramaSonucu;
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _studentsSubscription;

  void _listenToFirestoreChanges() {
    final studentsRef = FirebaseFirestore.instance
        .collection("kurumlar")
        .doc(kurum.data["kurumkodu"])
        .collection("danisanlar");

    _studentsSubscription = studentsRef.snapshots().listen((snapshot) {
      final fetchedStudents = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data["id"] = doc.id;

        final rawNo = data["no"];
        if (rawNo is! int) {
          data["no"] = int.tryParse(rawNo?.toString() ?? "0") ?? 0;
        }

        return data;
      }).toList();

      fetchedStudents
          .sort((a, b) => (a["no"] ?? 0).compareTo(b["no"] ?? 0));

      setState(() {
        ogrenciler = fetchedStudents;
      });
    });
  }

  // Resim URL'lerini önbelleğe almak için harita
  Map<String, String> _imageUrlCache = {};

  void _syncInstitutionMetadata() {
    if (!mounted) return;
    final classes = institutionClasses(kurum, includePlaceholder: true);
    final branches = institutionBranches(kurum, includePlaceholder: true);

    setState(() {
      if (classes.isNotEmpty) {
        _classFilterOptions = classes;
        if (!_classFilterOptions.contains(dropDown1Value)) {
          dropDown1Value = _classFilterOptions.first;
          sinif = dropDown1Value == 'SINIF' ? '' : dropDown1Value;
        }
      }
      if (branches.isNotEmpty) {
        _branchFilterOptions = branches;
        if (!_branchFilterOptions.contains(dropDown2Value)) {
          dropDown2Value = _branchFilterOptions.first;
          sube = dropDown2Value == 'ŞUBE' ? '' : dropDown2Value;
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _listenToFirestoreChanges();
    _syncInstitutionMetadata();
    _institutionWatcher = ever(kurum.data, (_) => _syncInstitutionMetadata());
  }

  @override
  void dispose() {
    _studentsSubscription?.cancel();
    _aramaController.dispose();
    _institutionWatcher?.dispose();
    super.dispose();
  }

  bool get _isManager =>
      (user.data['rol'] ?? '').toString().toUpperCase() == 'YÖNETİCİ';

  PopupMenuButton<_PhotoMenuAction> _buildOverflowMenu() {
    return PopupMenuButton<_PhotoMenuAction>(
      tooltip: 'Fotoğraf işlemleri',
      onSelected: (selection) async {
        FocusScope.of(context).unfocus();
        switch (selection) {
          case _PhotoMenuAction.bulkUpload:
            await pickAndUploadImages();
            break;
          case _PhotoMenuAction.download:
            await downloadAllPhotos();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_PhotoMenuAction>(
          value: _PhotoMenuAction.bulkUpload,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.cloud_upload_outlined, size: 20),
              SizedBox(width: 12),
              Text('Toplu Fotoğraf Yükle'),
            ],
          ),
        ),
        PopupMenuItem<_PhotoMenuAction>(
          value: _PhotoMenuAction.download,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.download_rounded, size: 20),
              SizedBox(width: 12),
              Text('Fotoğrafları İndir'),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final gradientTop = colorScheme.primaryContainer.withOpacity(
      theme.brightness == Brightness.dark ? 0.18 : 0.28,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Fotoğraf İşlemleri"),
        actions: [
          if (_isManager) _buildOverflowMenu(),
          const HomeIconButton(),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              gradientTop,
              colorScheme.background,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: _buildFilterSection(theme),
              ),
              Expanded(
                child: Obx(() {
                  if (!_hasRequestedResults.value) {
                    return _buildInitialState();
                  }
                  if (_aramaSonucu.isEmpty) {
                    return _buildEmptyResults();
                  }
                  return sonuclariGetir();
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final fieldWidth = isWide ? 260.0 : constraints.maxWidth;

        return Material(
          elevation: 4,
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          shadowColor: theme.shadowColor.withOpacity(0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fotoğraf araması',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _aramaController,
                  builder: (context, value, _) {
                    return TextField(
                      controller: _aramaController,
                      textInputAction: TextInputAction.search,
                      onChanged: (girilenDeger) {
                        genel = girilenDeger.isNotEmpty ? girilenDeger : "";
                        _aramaSonucu.clear();
                        _hasRequestedResults.value = false;
                      },
                      decoration: InputDecoration(
                        hintText: 'Danışan ara...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: value.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _aramaController.clear();
                                  setState(() {
                                    dropDown1Value = "SINIF";
                                    dropDown2Value = "ŞUBE";

                                    genel = "";
                                    sinif = "";
                                    sube = "";
                                  });
                                  _aramaSonucu.value = [];
                                  _hasRequestedResults.value = false;
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: colorScheme.surfaceVariant.withOpacity(
                          theme.brightness == Brightness.dark ? 0.25 : 0.35,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: fieldWidth,
                      child: _buildDropdownField(
                        theme: theme,
                        label: 'Sınıf',
                        value: dropDown1Value,
                        options: _classFilterOptions,
                        onChanged: (girilenDeger) {
                          setState(() {
                            dropDown1Value = girilenDeger;
                            sinif = girilenDeger != 'SINIF' ? girilenDeger : '';
                          });
                          _aramaSonucu.clear();
                          _hasRequestedResults.value = false;
                        },
                      ),
                    ),
                    SizedBox(
                      width: fieldWidth,
                      child: _buildDropdownField(
                        theme: theme,
                        label: 'Şube',
                        value: dropDown2Value,
                        options: _branchFilterOptions,
                        onChanged: (girilenDeger) {
                          setState(() {
                            dropDown2Value = girilenDeger;
                            sube = girilenDeger != 'ŞUBE' ? girilenDeger : '';
                          });
                          _aramaSonucu.clear();
                          _hasRequestedResults.value = false;
                        },
                      ),
                    ),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          ara();
                        },
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text("Göster"),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDropdownField({
    required ThemeData theme,
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    final safeValue = options.contains(value) ? value : options.first;
    return DropdownButtonFormField<String>(
      value: safeValue,
      icon: const Icon(Icons.expand_more_rounded),
      borderRadius: BorderRadius.circular(16),
      items: options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option,
              child: Text(option),
            ),
          )
          .toList(),
      onChanged: (selected) {
        if (selected == null) {
          return;
        }
        onChanged(selected);
      },
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: theme.colorScheme.surfaceVariant.withOpacity(
          theme.brightness == Brightness.dark ? 0.25 : 0.2,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildInitialState() {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 72,
                color: theme.colorScheme.primary.withOpacity(0.35),
              ),
              const SizedBox(height: 16),
              Text(
                'Fotoğraf görmek için filtreleri doldurup Göster’e basın',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sınıf/şube seçip arama yapın ya da öğrencinin adını yazarak aramayı başlatın.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  int _calculateCrossAxisCount(double width) {
    if (width >= 1100) return 4;
    if (width >= 800) return 3;
    return 2;
  }

  Widget _buildEmptyResults() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: theme.colorScheme.primary.withOpacity(0.35),
          ),
          const SizedBox(height: 12),
          Text(
            'Filtrenize uygun fotoğraf bulunamadı.',
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget sonuclariGetir() {
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = _calculateCrossAxisCount(width);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 18.0,
        mainAxisSpacing: 18.0,
        childAspectRatio: 0.72,
      ),
      itemCount: _aramaSonucu.length,
      itemBuilder: (context, index) {
        final ogrenci = _aramaSonucu[index];
        final id = resolveStudentId(ogrenci);
        final fallbackIds = <String>[];
        final tckn = (ogrenci['tckn'] ?? '').toString().trim();
        if (tckn.isNotEmpty && !fallbackIds.contains(tckn)) {
          fallbackIds.add(tckn);
        }

        final name = '${ogrenci["adi"] ?? ''} ${ogrenci["soyadi"] ?? ''}'.trim();
        final sinifValue = (ogrenci["sinif"] ?? '').toString();
        final subeValue = (ogrenci["sube"] ?? '').toString();
        final numberValue = (ogrenci["no"] ?? '').toString();
        final classInfo = [
          if (sinifValue.isNotEmpty) sinifValue,
          if (subeValue.isNotEmpty) subeValue,
        ].join('/');
        final subtitleParts = [
          if (classInfo.isNotEmpty) classInfo,
          if (numberValue.isNotEmpty) numberValue,
        ];
        final subtitle = subtitleParts.join(' · ');

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => DanisanProfil(id: id)),
              );
            },
            onLongPress: () => resimsil(id),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImage(id, fallbackIds: fallbackIds),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _buildPhotoActionButton(
                        icon: Icons.camera_alt_outlined,
                        tooltip: 'Kameradan çek',
                        onPressed: () => _updateStudentPhoto(id, ImageSource.camera),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _buildPhotoActionButton(
                        icon: Icons.file_upload_outlined,
                        tooltip: 'Galeriden yükle',
                        onPressed: () => _updateStudentPhoto(id, ImageSource.gallery),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.6),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name.isEmpty ? 'İsimsiz Danışan' : name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ) ??
                                  const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withOpacity(0.85),
                                  fontWeight: FontWeight.w500,
                                ) ??
                                    TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.85),
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhotoActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surface.withOpacity(0.95),
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.14),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(
              icon,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateStudentPhoto(String studentId, ImageSource source) async {
    final picker = ImagePicker();
    try {
      final pickedImage = await picker.pickImage(
        source: source,
        maxWidth: 480,
        maxHeight: 640,
      );

      if (pickedImage == null) {
        return;
      }

      final imageBytes = await pickedImage.readAsBytes();
      final optimizedBytes = optimizeImageBytes(imageBytes, maxDimension: 1080, quality: 72);

      await FirebaseStorage.instance
          .ref('${kurum.data["kurumkodu"]}/danisanlar/$studentId.jpg')
          .putData(
            optimizedBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _imageUrlCache.remove(studentId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera
                ? 'Yeni fotoğraf kaydedildi.'
                : 'Fotoğraf güncellendi.',
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (kDebugMode) {
        print(error);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotoğraf yüklenemedi. Lütfen tekrar deneyin.'),
        ),
      );
    } catch (error) {
      if (kDebugMode) {
        print(error);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotoğraf yüklenemedi. Lütfen tekrar deneyin.'),
        ),
      );
    }
  }

  Widget _buildImagePlaceholder() {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceVariant.withOpacity(
        theme.brightness == Brightness.dark ? 0.3 : 0.2,
      ),
      child: Center(
        child: Icon(
          Icons.person_outline,
          size: 52,
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
    );
  }

  // Resim görüntüleme widget'ı
  Widget _buildImage(String id, {List<String> fallbackIds = const []}) {
    if (_imageUrlCache.containsKey(id)) {
      return Image.network(
        _imageUrlCache[id]!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          final progress = loadingProgress.expectedTotalBytes != null
              ? loadingProgress.cumulativeBytesLoaded /
                  loadingProgress.expectedTotalBytes!
              : null;
          return Stack(
            fit: StackFit.expand,
            children: [
              _buildImagePlaceholder(),
              Center(
                child: CircularProgressIndicator(value: progress),
              ),
            ],
          );
        },
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
      );
    } else {
      return FutureBuilder<String?>(
        future: getFirstImageUrlById(id, fallbackIds: fallbackIds),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Stack(
              fit: StackFit.expand,
              children: [
                _buildImagePlaceholder(),
                const Center(child: CircularProgressIndicator()),
              ],
            );
          } else if (snapshot.hasError || snapshot.data == null) {
            return _buildImagePlaceholder();
          } else {
            _imageUrlCache[id] = snapshot.data!;
            return Image.network(
              snapshot.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
            );
          }
        },
      );
    }
  }

  Future<void> pickAndUploadImages() async {
    if (!_isManager) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu işlem için yetkiniz yok.')),
        );
      }
      return;
    }

    final studentSnapshot = await _firestore
        .collection('kurumlar')
        .doc(kurum.data["kurumkodu"])
        .collection("danisanlar")
        .get();
    final studentLookup = <String, String>{};
    for (final doc in studentSnapshot.docs) {
      final data = doc.data();
      final docId = doc.id;
      studentLookup[docId] = docId;
      final rawTckn = (data['tckn'] ?? '').toString().trim();
      if (rawTckn.isNotEmpty) {
        studentLookup[rawTckn] = docId;
      }
    }
    final studentIds = studentLookup.keys.where((value) => value.trim().isNotEmpty).toSet();

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );

    if (result != null) {
      notUploadedPhotos.clear();
      int uploadedCount = 0;

      for (var file in result.files) {
        if (file.bytes != null) {
          String fileNameWithoutExtension = file.name.split('.').first;

          if (studentIds.contains(fileNameWithoutExtension)) {
            if (file.bytes == null) {
              continue;
            }
            final optimizedBytes = optimizeImageBytes(file.bytes!, maxDimension: 1080, quality: 72);

            try {
              final ref = _storage
                  .ref('${kurum.data["kurumkodu"]}/danisanlar/$fileNameWithoutExtension.jpg');
              await ref.putData(
                optimizedBytes,
                SettableMetadata(contentType: 'image/jpeg'),
              );
              print('Uploaded: ${file.name}');
              uploadedCount++;
              if (mounted) {
                final cacheKey = studentLookup[fileNameWithoutExtension] ?? fileNameWithoutExtension;
                setState(() {
                  _imageUrlCache.remove(cacheKey);
                  _imageUrlCache.remove(fileNameWithoutExtension);
                });
              }
            } catch (e) {
              print('Error uploading ${file.name}: $e');
            }
          } else {
            notUploadedPhotos.add(file.name);
          }
        }
      }

      if (notUploadedPhotos.isNotEmpty) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Başarısız Yükleme'),
              content: Text(
                  'Aşağıda adı verilen fotoğraflar kayıtlı T.C. Kimlik Numaralarıyla eşleşmediği için yüklenememiştir. Fotoğraf adı öğrenci T.C. Kimlik numarasıyla aynı olamalıdır.:\n\n${notUploadedPhotos.join('\n')}'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      }

      if (uploadedCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$uploadedCount fotoğraf güncellendi.')),
        );
      }
    }
  }

  Future<String?> getFirstImageUrlById(String id, {List<String> fallbackIds = const []}) async {
    try {
      final kurumkodu = kurum.data["kurumkodu"];
      final storageRef = FirebaseStorage.instance.ref('$kurumkodu/danisanlar');
      final candidates = <String>{
        id.trim(),
        ...fallbackIds.map((e) => e.trim()),
      }.where((element) => element.isNotEmpty).toList();

      const extensions = ['jpg', 'jpeg', 'png', 'JPG', 'JPEG', 'PNG'];

      for (final candidate in candidates) {
        for (final ext in extensions) {
          try {
            final url = await storageRef.child('$candidate.$ext').getDownloadURL();
            return url;
          } on FirebaseException catch (error) {
            if (error.code == 'object-not-found') {
              continue;
            }
            rethrow;
          }
        }
      }

      print("No file found with the given ID.");
      return null;
    } catch (e) {
      print("Error fetching download URL: $e");
      return null;
    }
  }

  resimsil(String studentId) {
    if (studentId.trim().isEmpty) {
      return;
    }
    Future.delayed(Duration.zero, () {
      showDialog(
          context: context,
          builder: (context) => AlertDialog(
                title: Text("RESİM SİL"),
                content: Text("Silmek istediğinizden emin misiniz?"),
                actions: [
                  TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: Text("İPTAL")),
                  TextButton(
                      onPressed: () {
                        try {
                          FirebaseStorage.instance
                              .ref('${kurum.data["kurumkodu"]}/danisanlar/$studentId.jpg')
                              .delete();
                        } catch (e) {
                          print(e);
                        }
                        Navigator.pop(context);
                      },
                      child: Text("SİL"))
                ],
              ));
    });
  }

  Future<void> downloadAllPhotos() async {
    if (!_isManager) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu işlem için yetkiniz yok.')),
      );
      return;
    }

    if (!_hasRequestedResults.value || _aramaSonucu.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Önce filtreyi uygulayıp fotoğrafları gösterin.')),
        );
      }
      return;
    }

    if (kIsWeb) {
      await _downloadAllPhotosWeb();
      return;
    }

    if (Platform.isIOS) {
      await _downloadAllPhotosIOS();
    } else if (Platform.isAndroid) {
      await _downloadAllPhotosAndroid();
    } else {
      await _downloadAllPhotosDesktop();
    }
  }

  Future<void> _downloadAllPhotosAndroid() async {
    if (!await _requestStoragePermission()) {
      return;
    }

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) {
      print("Klasör seçimi iptal edildi.");
      return;
    }

    final downloadFolder = Directory(selectedDirectory);
    if (!await downloadFolder.exists()) {
      await downloadFolder.create(recursive: true);
    }

    final photos = await _collectStudentPhotos();
    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İndirilecek fotoğraf bulunamadı.')),
      );
      return;
    }

    for (final photo in photos) {
      final file = File(path.join(downloadFolder.path, photo.fileName));
      await file.writeAsBytes(photo.bytes, flush: true);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fotoğraflar ${downloadFolder.path} klasörüne kaydedildi.')),
    );
  }

  Future<void> _downloadAllPhotosDesktop() async {
    final photos = await _collectStudentPhotos();
    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İndirilecek fotoğraf bulunamadı.')),
      );
      return;
    }

    final downloadsDirectory = await getDownloadsDirectory();
    final baseDirectory = downloadsDirectory ?? await getApplicationDocumentsDirectory();
    final folderName = 'ogrenci_fotograflari_${DateTime.now().millisecondsSinceEpoch}';
    final targetDirectory = Directory(path.join(baseDirectory.path, folderName));
    await targetDirectory.create(recursive: true);

    for (final photo in photos) {
      final file = File(path.join(targetDirectory.path, photo.fileName));
      await file.writeAsBytes(photo.bytes, flush: true);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fotoğraflar ${targetDirectory.path} klasörüne kaydedildi.')),
    );
  }

  Future<void> _downloadAllPhotosIOS() async {
    final photos = await _collectStudentPhotos();
    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İndirilecek fotoğraf bulunamadı.')),
      );
      return;
    }

    final archive = Archive();
    for (final photo in photos) {
      archive.addFile(ArchiveFile(photo.fileName, photo.bytes.length, photo.bytes));
    }

    final directory = await getTemporaryDirectory();
    final zipPath = path.join(directory.path, 'ogrenci_fotograflari.zip');
    final zipFile = File(zipPath);
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes != null) {
      await zipFile.writeAsBytes(zipBytes, flush: true);
      await Share.shareXFiles([XFile(zipPath)], text: 'Danışan fotoğrafları');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fotoğraflar paylaşım menüsüne gönderildi.')),
    );
  }

  Future<List<_StudentPhoto>> _collectStudentPhotos() async {
    final List<_StudentPhoto> photos = [];

    for (var ogrenci in _aramaSonucu) {
      final map = Map<String, dynamic>.from(ogrenci);
      final studentId = resolveStudentId(map);
      if (studentId.isEmpty) {
        continue;
      }
      final studentName = (map["adi"] ?? '').toString();
      final studentSurname = (map["soyadi"] ?? '').toString();
      final studentNo = (map["no"] ?? '').toString();

      try {
        final fallbackIds = <String>[];
        final tckn = (map['tckn'] ?? '').toString().trim();
        if (tckn.isNotEmpty && tckn != studentId) {
          fallbackIds.add(tckn);
        }

        String? downloadUrl = await getFirstImageUrlById(
          studentId,
          fallbackIds: fallbackIds,
        );

        if (downloadUrl != null) {
          final bytes = await _downloadPhotoBytes(downloadUrl);
          if (bytes == null) {
            print('Fotoğraf indirilemedi: $studentId');
            continue;
          }

          String fileName = _buildPhotoFileName(
            number: studentNo,
            name: studentName,
            surname: studentSurname,
          );
          photos.add(_StudentPhoto(fileName, bytes));
        } else {
          print('Fotoğraf bulunamadı: $studentId');
        }
      } catch (e) {
        print('Hata oluştu: $e');
      }
    }

    return photos;
  }

  String _buildPhotoFileName({
    required String number,
    required String name,
    required String surname,
  }) {
    String sanitize(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return '';
      }
      final withoutInvalidChars = trimmed
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return withoutInvalidChars;
    }

    final parts = <String>[
      sanitize(number),
      sanitize(name),
      sanitize(surname),
    ].where((element) => element.isNotEmpty).toList();

    if (parts.isEmpty) {
      parts.add('ogrenci');
    }

    final fileName = parts.join('_');
    return '$fileName.jpg';
  }

  Future<Uint8List?> _downloadPhotoBytes(String url) async {
    try {
      if (kIsWeb) {
        final response = await html.HttpRequest.request(
          url,
          responseType: 'arraybuffer',
        );
        final data = response.response;
        if (data is ByteBuffer) {
          return Uint8List.view(data);
        }
        if (data is Uint8List) {
          return data;
        }
        return null;
      } else {
        final httpClient = HttpClient();
        final request = await httpClient.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          httpClient.close(force: true);
          return null;
        }
        final bytes = await consolidateHttpClientResponseBytes(response);
        httpClient.close(force: true);
        return bytes;
      }
    } catch (error) {
      print('Fotoğraf indirilemedi: $error');
      return null;
    }
  }

  Future<void> _downloadAllPhotosWeb() async {
    final archive = Archive();

    for (final photo in await _collectStudentPhotos()) {
      archive.addFile(ArchiveFile(photo.fileName, photo.bytes.length, photo.bytes));
    }

    final zipBytes = ZipEncoder().encode(archive);
    final blob = html.Blob([zipBytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download = 'ogrenci_fotograflari.zip';
    html.document.body!.children.add(anchor);
    anchor.click();
    html.document.body!.children.remove(anchor);
    html.Url.revokeObjectUrl(url);
    print("Tüm Fotoğraflar indirildi");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tüm fotoğraflar indirildi!')),
    );
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) {
          print("Depolama izni reddedildi.");
          return false;
        }
      }
    }
    return true;
  }
}

class _StudentPhoto {
  _StudentPhoto(this.fileName, this.bytes);

  final String fileName;
  final Uint8List bytes;
}
