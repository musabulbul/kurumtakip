import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SmsProvidersPage extends StatefulWidget {
  const SmsProvidersPage({super.key});

  @override
  State<SmsProvidersPage> createState() => _SmsProvidersPageState();
}

class _SmsProvidersPageState extends State<SmsProvidersPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  String? _errorMessage;
  final List<Map<String, dynamic>> _providers = [];

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final snapshot = await _firestore.collection('sms_providers').get();
      final items = snapshot.docs.map((doc) {
        final data = doc.data();
        final send = data['send'] as Map<String, dynamic>? ?? {};
        final oneToMany = send['oneToMany'] as Map<String, dynamic>? ?? {};
        final manyToMany = send['manyToMany'] as Map<String, dynamic>? ?? {};
        return {
          'docId': doc.id,
          'name': data['name'] ?? doc.id,
          'baseUrl': data['baseUrl'] ?? '',
          'paramMap': data['paramMap'],
          'extraParams': data['extraParams'],
          'oneToManyPath': oneToMany['path'] ?? '',
          'manyToManyPath': manyToMany['path'] ?? '',
          'contentType': oneToMany['contentType'] ?? manyToMany['contentType'] ?? '',
        };
      }).toList();

      items.sort((a, b) =>
          (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));

      setState(() {
        _providers
          ..clear()
          ..addAll(items);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'SMS sağlayıcıları yüklenirken hata oluştu: $e';
      });
    }
  }

  Future<void> _openProviderDialog({Map<String, dynamic>? provider}) async {
    final bool isEdit = provider != null;
    final formKey = GlobalKey<FormState>();
    final paramMap = _asStringMap(provider?['paramMap']);
    final legacyExtraParams = _asStringMap(provider?['extraParams']);

    final TextEditingController providerIdController =
        TextEditingController(text: provider?['docId'] ?? '');
    final TextEditingController nameController =
        TextEditingController(text: provider?['name'] ?? '');
    final TextEditingController baseUrlController =
        TextEditingController(text: provider?['baseUrl'] ?? '');
    final TextEditingController oneToManyController =
        TextEditingController(text: provider?['oneToManyPath'] ?? '');
    final TextEditingController manyToManyController =
        TextEditingController(text: provider?['manyToManyPath'] ?? '');
    final TextEditingController contentTypeController =
        TextEditingController(text: provider?['contentType'] ?? 'application/json');
    final TextEditingController messageParamController =
        TextEditingController(text: _mapValue(paramMap, 'message'));
    final TextEditingController receiversParamController =
        TextEditingController(text: _mapValue(paramMap, 'receivers'));
    final TextEditingController messagesParamController =
        TextEditingController(text: _mapValue(paramMap, 'messages'));
    final TextEditingController receiverParamController =
        TextEditingController(text: _mapValue(paramMap, 'receiver'));
    final TextEditingController usernameParamController =
        TextEditingController(text: _mapValue(paramMap, 'username'));
    final TextEditingController passwordParamController =
        TextEditingController(text: _mapValue(paramMap, 'password'));
    final TextEditingController apiKeyParamController =
        TextEditingController(text: _mapValue(paramMap, 'apiKey'));
    final TextEditingController senderParamController =
        TextEditingController(text: _mapValue(paramMap, 'sender'));
    final TextEditingController sendDateParamController =
        TextEditingController(text: _mapValue(paramMap, 'sendDate'));
    final TextEditingController expireDateParamController =
        TextEditingController(text: _mapValue(paramMap, 'expireDate'));
    final TextEditingController messageTypeParamController = TextEditingController(
      text: _mapValue(
        paramMap,
        'messageType',
        fallback: _findLegacyTemplateKey(legacyExtraParams, '{{tur}}'),
      ),
    );
    final TextEditingController messageContentTypeParamController =
        TextEditingController(
      text: _mapValue(
        paramMap,
        'messageContentType',
        fallback: _findLegacyTemplateKey(
          legacyExtraParams,
          '{{messageContentType}}',
        ),
      ),
    );

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(isEdit ? 'SMS Sağlayıcı Güncelle' : 'Yeni SMS Sağlayıcı'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField(
                    label: 'Provider ID',
                    controller: providerIdController,
                    readOnly: isEdit,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Provider ID zorunludur';
                      }
                      return null;
                    },
                  ),
                  _buildTextField(
                    label: 'Firma Adı',
                    controller: nameController,
                  ),
                  _buildTextField(
                    label: 'Base URL',
                    controller: baseUrlController,
                    hintText: 'Örn: https://.../api_json',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Base URL zorunludur';
                      }
                      return null;
                    },
                  ),
                  _buildTextField(
                    label: 'Send 1-N Path',
                    controller: oneToManyController,
                    hintText: '/v1/Sms/Send_1_N',
                  ),
                  _buildTextField(
                    label: 'Send N-N Path',
                    controller: manyToManyController,
                    hintText: '/v1/Sms/Send_N_N',
                  ),
                  _buildTextField(
                    label: 'Content Type',
                    controller: contentTypeController,
                    hintText: 'application/json',
                  ),
                  _buildTextField(
                    label: 'Mesaj Alanı',
                    controller: messageParamController,
                    hintText: 'Örn: message / msg',
                  ),
                  _buildTextField(
                    label: 'Alıcı Listesi Alanı',
                    controller: receiversParamController,
                    hintText: 'Örn: receivers / phones',
                  ),
                  _buildTextField(
                    label: 'Kişisel Mesaj Listesi Alanı',
                    controller: messagesParamController,
                    hintText: 'Örn: messages / phones',
                  ),
                  _buildTextField(
                    label: 'Kişisel Alıcı Alanı',
                    controller: receiverParamController,
                    hintText: 'Örn: receiver / phone',
                  ),
                  _buildTextField(
                    label: 'Kullanıcı Parametresi',
                    controller: usernameParamController,
                    hintText: 'Örn: username / api_id',
                  ),
                  _buildTextField(
                    label: 'Şifre Parametresi',
                    controller: passwordParamController,
                    hintText: 'Örn: password',
                  ),
                  _buildTextField(
                    label: 'API Key Parametresi',
                    controller: apiKeyParamController,
                    hintText: 'Örn: api_key',
                  ),
                  _buildTextField(
                    label: 'Gönderici Parametresi',
                    controller: senderParamController,
                    hintText: 'Örn: sender / title',
                  ),
                  _buildTextField(
                    label: 'Gönderim Zamanı Parametresi',
                    controller: sendDateParamController,
                    hintText: 'Örn: send_time',
                  ),
                  _buildTextField(
                    label: 'Bitiş Zamanı Parametresi',
                    controller: expireDateParamController,
                    hintText: 'Örn: expire_time',
                  ),
                  _buildTextField(
                    label: 'Mesaj Türü Parametresi',
                    controller: messageTypeParamController,
                    hintText: 'Örn: message_type',
                  ),
                  _buildTextField(
                    label: 'Mesaj İçerik Türü Parametresi',
                    controller: messageContentTypeParamController,
                    hintText: 'Örn: message_content_type',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) {
                  return;
                }

                final resolvedParamMap = <String, dynamic>{};
                _putIfNotEmpty(resolvedParamMap, 'message', messageParamController.text);
                _putIfNotEmpty(resolvedParamMap, 'receivers', receiversParamController.text);
                _putIfNotEmpty(resolvedParamMap, 'messages', messagesParamController.text);
                _putIfNotEmpty(resolvedParamMap, 'receiver', receiverParamController.text);
                _putIfNotEmpty(resolvedParamMap, 'username', usernameParamController.text);
                _putIfNotEmpty(resolvedParamMap, 'password', passwordParamController.text);
                _putIfNotEmpty(resolvedParamMap, 'apiKey', apiKeyParamController.text);
                _putIfNotEmpty(resolvedParamMap, 'sender', senderParamController.text);
                _putIfNotEmpty(resolvedParamMap, 'sendDate', sendDateParamController.text);
                _putIfNotEmpty(resolvedParamMap, 'expireDate', expireDateParamController.text);
                _putIfNotEmpty(resolvedParamMap, 'messageType', messageTypeParamController.text);
                _putIfNotEmpty(
                  resolvedParamMap,
                  'messageContentType',
                  messageContentTypeParamController.text,
                );

                final payload = {
                  'name': nameController.text.trim().isEmpty
                      ? providerIdController.text.trim()
                      : nameController.text.trim(),
                  'baseUrl': baseUrlController.text.trim(),
                  if (resolvedParamMap.isNotEmpty) 'paramMap': resolvedParamMap,
                  'extraParams': FieldValue.delete(),
                  'send': {
                    'oneToMany': {
                      'path': oneToManyController.text.trim(),
                      'method': 'POST',
                      'contentType': contentTypeController.text.trim().isEmpty
                          ? 'application/json'
                          : contentTypeController.text.trim(),
                    },
                    'manyToMany': {
                      'path': manyToManyController.text.trim(),
                      'method': 'POST',
                      'contentType': contentTypeController.text.trim().isEmpty
                          ? 'application/json'
                          : contentTypeController.text.trim(),
                    },
                  },
                };

                final docId = providerIdController.text.trim();
                try {
                  await _firestore
                      .collection('sms_providers')
                      .doc(docId)
                      .set(payload, SetOptions(merge: true));

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isEdit
                              ? 'SMS sağlayıcı güncellendi.'
                              : 'SMS sağlayıcı oluşturuldu.',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Kaydedilirken hata oluştu: $e')),
                    );
                  }
                } finally {
                  await _loadProviders();
                }
              },
              child: Text(isEdit ? 'Güncelle' : 'Kaydet'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteProvider(Map<String, dynamic> provider) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('SMS Sağlayıcıyı Sil'),
          content: Text(
            '${provider['name']} sağlayıcısını silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    try {
      await _firestore
          .collection('sms_providers')
          .doc(provider['docId'] as String)
          .delete();
      await _loadProviders();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silinirken hata oluştu: $e')),
        );
      }
    }
  }

  Future<void> _upsertIlkSmsProvider() async {
    final payload = {
      'name': 'Ilk SMS (VatanSMS)',
      'baseUrl': 'https://api.vatansms.net',
      'paramMap': {
        'username': 'api_id',
        'apiKey': 'api_key',
        'sender': 'sender',
        'receivers': 'phones',
        'messages': 'phones',
        'receiver': 'phone',
        'message': 'message',
        'sendDate': 'send_time',
        'messageType': 'message_type',
        'messageContentType': 'message_content_type',
      },
      'extraParams': FieldValue.delete(),
      'send': {
        'oneToMany': {
          'path': '/api/v1/NtoN',
          'method': 'POST',
          'contentType': 'application/json',
        },
        'manyToMany': {
          'path': '/api/v1/NtoN',
          'method': 'POST',
          'contentType': 'application/json',
        },
      },
    };

    try {
      await _firestore
          .collection('sms_providers')
          .doc('ilksms_vatansms')
          .set(payload, SetOptions(merge: true));
      await _loadProviders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ilk SMS sağlayıcısı eklendi/güncellendi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ilk SMS eklenirken hata oluştu: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Sağlayıcılar'),
        actions: [
          IconButton(
            tooltip: 'Ilk SMS Ekle',
            onPressed: _upsertIlkSmsProvider,
            icon: const Icon(Icons.cloud_download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openProviderDialog(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : _providers.isEmpty
                  ? const Center(child: Text('Kayıtlı SMS sağlayıcı yok.'))
                  : ListView.builder(
                      itemCount: _providers.length,
                      itemBuilder: (context, index) {
                        final provider = _providers[index];
                        return ListTile(
                          title: Text(provider['name'] ?? provider['docId']),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((provider['baseUrl'] ?? '').toString().isNotEmpty)
                                Text('Base URL: ${provider['baseUrl']}'),
                              if ((provider['oneToManyPath'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text('Send 1-N: ${provider['oneToManyPath']}'),
                              if ((provider['manyToManyPath'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text('Send N-N: ${provider['manyToManyPath']}'),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<int>(
                            onSelected: (value) {
                              if (value == 0) {
                                _openProviderDialog(provider: provider);
                              } else if (value == 1) {
                                _deleteProvider(provider);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 0,
                                child: Text('Düzenle'),
                              ),
                              const PopupMenuItem(
                                value: 1,
                                child: Text('Sil'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool readOnly = false,
    bool obscureText = false,
    String? hintText,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        obscureText: obscureText,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          border: const OutlineInputBorder(),
        ),
        validator: validator,
      ),
    );
  }

  Map<String, String> _asStringMap(dynamic value) {
    if (value is! Map) {
      return {};
    }
    final mapped = <String, String>{};
    value.forEach((key, val) {
      if (key == null || val == null) {
        return;
      }
      final cleanKey = key.toString().trim();
      if (cleanKey.isEmpty) {
        return;
      }
      mapped[cleanKey] = val.toString().trim();
    });
    return mapped;
  }

  String _mapValue(
    Map<String, String> source,
    String key, {
    String fallback = '',
  }) {
    return source[key] ?? fallback;
  }

  String _findLegacyTemplateKey(
    Map<String, String> source,
    String templateValue,
  ) {
    for (final entry in source.entries) {
      if (entry.value.trim() == templateValue) {
        return entry.key;
      }
    }
    return '';
  }

  void _putIfNotEmpty(Map<String, dynamic> map, String key, String value) {
    final clean = value.trim();
    if (clean.isEmpty) {
      return;
    }
    map[key] = clean;
  }
}
