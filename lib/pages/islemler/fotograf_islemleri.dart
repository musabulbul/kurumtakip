import 'dart:io'; // Android ve iOS için gerekli
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart'; // Resim seçmek için
import 'package:flutter/foundation.dart' show kIsWeb; // Platform kontrolü için
import 'package:kurum_takip/widgets/home_icon_button.dart';
import 'package:kurum_takip/services/photo_storage_service.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';
import '../../utils/institution_metadata_utils.dart';

UserController user = Get.find<UserController>();
InstitutionController kurum = Get.find<InstitutionController>();
var kurumkodu = user.data['kurumkodu'];

class Student {
  final String id;
  final String name;
  final String surname;
  final String classGroup;
  final String branch;
  final int schoolNumber;

  Student({
    required this.id,
    required this.name,
    required this.surname,
    required this.classGroup,
    required this.branch,
    required this.schoolNumber,
  });

  factory Student.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Student(
      id: doc.id,
      name: data['adi'] ?? '',
      surname: data['soyadi'] ?? '',
      classGroup: data['sinif'] ?? '',
      branch: data['sube'] ?? '',
      schoolNumber: int.tryParse(data["no"] ?? '0') ?? 0,
    );
  }
}

class StudentPage extends StatefulWidget {
  @override
  _StudentPageState createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  List<Student> students = [];
  List<Student> filteredStudents = [];
  String? selectedClass;
  String? selectedBranch;
  List<String> _classOptions = [];
  List<String> _branchOptions = [];
  Worker? _institutionWatcher;

  @override
  void initState() {
    super.initState();
    fetchStudents();
    _syncInstitutionMetadata();
    _institutionWatcher = ever(kurum.data, (_) => _syncInstitutionMetadata());
  }

  @override
  void dispose() {
    _institutionWatcher?.dispose();
    super.dispose();
  }

  Future<void> fetchStudents() async {
    final institutionId = (kurum.data['kurumkodu'] ?? kurumkodu).toString();
    var snapshot = await FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(institutionId)
        .collection('danisanlar')
        .get();

    List<Student> fetchedStudents =
        snapshot.docs.map((doc) => Student.fromFirestore(doc)).toList();
    setState(() {
      students = fetchedStudents;
      filteredStudents = fetchedStudents;
      sortStudents();
    });
  }

  void _syncInstitutionMetadata() {
    final classes = institutionClasses(kurum, includePlaceholder: false);
    final branches = institutionBranches(kurum, includePlaceholder: false);

    setState(() {
      _classOptions = classes.isNotEmpty ? classes : _classOptions;
      _branchOptions = branches.isNotEmpty ? branches : _branchOptions;

      if (selectedClass != null && !_classOptions.contains(selectedClass)) {
        selectedClass = null;
      }
      if (selectedBranch != null && !_branchOptions.contains(selectedBranch)) {
        selectedBranch = null;
      }
    });
  }

  void filterStudents() {
    setState(() {
      filteredStudents = students.where((student) {
        final classMatches =
            selectedClass == null || student.classGroup == selectedClass;
        final branchMatches =
            selectedBranch == null || student.branch == selectedBranch;
        return classMatches && branchMatches;
      }).toList();
      sortStudents();
    });
  }

  void sortStudents() {
    filteredStudents.sort((a, b) => a.schoolNumber.compareTo(b.schoolNumber));
  }

  Future<void> uploadPhoto(dynamic image, String studentId) async {
    final storageRef = PhotoStorageService.studentProfileRef(kurumkodu, studentId);

    if (kIsWeb) {
      // Web platformu için
      await storageRef.putBlob(image);
    } else {
      // Android ve iOS için
      File file = File(image.path);
      await storageRef.putFile(file);
    }

    setState(() {}); // Görüntüyü güncellemek için widget'ı yeniler
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Öğrenciler"),
        actions: const [HomeIconButton()],
      ),
      body: Column(
        children: [
          // Filtreleme Dropdown'ları
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              DropdownButton<String>(
                value: selectedClass,
                hint: Text("Sınıf Seçin"),
                items: _classOptions
                    .map((classItem) => DropdownMenuItem(
                          value: classItem,
                          child: Text(classItem),
                        ))
                    .toList(),
                onChanged: (newValue) {
                  setState(() {
                    selectedClass = newValue;
                    filterStudents();
                  });
                },
              ),
              DropdownButton<String>(
                value: selectedBranch,
                hint: Text("Şube Seçin"),
                items: _branchOptions
                    .map((branchItem) => DropdownMenuItem(
                          value: branchItem,
                          child: Text(branchItem),
                        ))
                    .toList(),
                onChanged: (newValue) {
                  setState(() {
                    selectedBranch = newValue;
                    filterStudents();
                  });
                },
              ),
            ],
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    MediaQuery.of(context).size.width > 600 ? 3 : 2,
                crossAxisSpacing: 8.0,
                mainAxisSpacing: 8.0,
              ),
              itemCount: filteredStudents.length,
              itemBuilder: (context, index) {
                final student = filteredStudents[index];
                return StudentCard(
                  student: student,
                  kurumkodu: kurumkodu,
                  onPhotoPick: (file) => uploadPhoto(file, student.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class StudentCard extends StatelessWidget {
  final Student student;
  final String kurumkodu;
  final Future<void> Function(dynamic) onPhotoPick;

  StudentCard(
      {required this.student, required this.kurumkodu, required this.onPhotoPick});

  Future<void> _pickPhoto(BuildContext context) async {
    if (kIsWeb) {
      // Web için henüz bir picker eklemedik
    } else {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        await onPhotoPick(File(pickedFile.path));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          FutureBuilder(
            future: PhotoStorageService.studentProfileRef(kurumkodu, student.id).getDownloadURL(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return CircularProgressIndicator();
              } else if (snapshot.hasError) {
                return Icon(Icons.error);
              } else {
                return Image.network(
                  snapshot.data as String,
                  height: 100,
                  fit: BoxFit.cover,
                );
              }
            },
          ),
          Text(student.name),
          Text(student.surname),
          Text('${student.classGroup} / ${student.branch}'),
          Text('No: ${student.schoolNumber}'),
          TextButton(
            onPressed: () => _pickPhoto(context),
            child: Text("Fotoğraf Yükle"),
          ),
        ],
      ),
    );
  }
}
