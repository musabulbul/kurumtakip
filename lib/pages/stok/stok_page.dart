import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/institution_controller.dart';
import '../../controllers/user_controller.dart';
import '../../widgets/home_icon_button.dart';
import '../../utils/text_utils.dart';
import '../../utils/permission_utils.dart';

class StokPage extends StatefulWidget {
  const StokPage({super.key});

  @override
  State<StokPage> createState() => _StokPageState();
}

class _StokPageState extends State<StokPage> {
  final InstitutionController _institution = Get.find<InstitutionController>();
  final UserController _user = Get.find<UserController>();

  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _productPriceController = TextEditingController();
  final TextEditingController _stockQuantityController = TextEditingController();
  final TextEditingController _stockNoteController = TextEditingController();
  final TextEditingController _productSearchController = TextEditingController();
  final TextEditingController _stockListSearchController =
      TextEditingController();

  static const List<String> _units = ['Adet', 'Lt.', 'Ml.', 'Paket', 'Gr.'];
  String _selectedUnit = _units.first;

  String? _selectedProductId;
  String? _selectedProductName;
  String? _selectedProductUnit;

  bool _isSavingProduct = false;
  bool _isSavingStock = false;
  bool _isProductFormExpanded = true;

  _StockSortType _stockSortType = _StockSortType.alphabetical;

  @override
  void dispose() {
    _productNameController.dispose();
    _productPriceController.dispose();
    _stockQuantityController.dispose();
    _stockNoteController.dispose();
    _productSearchController.dispose();
    _stockListSearchController.dispose();
    super.dispose();
  }

  String _currentInstitutionId() {
    return (_institution.data['kurumkodu'] ?? '').toString().trim();
  }

  CollectionReference<Map<String, dynamic>> _productsRef(String kurumkodu) {
    return FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(kurumkodu)
        .collection('stokUrunler');
  }

  CollectionReference<Map<String, dynamic>> _stockMovementRef(String kurumkodu) {
    return FirebaseFirestore.instance
        .collection('kurumlar')
        .doc(kurumkodu)
        .collection('stokHareketleri');
  }

  double? _parseDecimal(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  Future<void> _saveProduct() async {
    if (_isSavingProduct) {
      return;
    }
    final kurumkodu = _currentInstitutionId();
    if (kurumkodu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
      );
      return;
    }
    final name = _productNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ürün adı girin.')),
      );
      return;
    }
    final price = _parseDecimal(_productPriceController.text);
    if (price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir satış fiyatı girin.')),
      );
      return;
    }

    setState(() {
      _isSavingProduct = true;
    });

    try {
      await _productsRef(kurumkodu).add({
        'ad': toUpperCaseTr(name),
        'birim': _selectedUnit,
        'fiyat': price,
        'stok': 0.0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _productNameController.clear();
      _productPriceController.clear();
      setState(() {
        _selectedUnit = _units.first;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ürün kaydedildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ürün kaydedilemedi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingProduct = false;
        });
      }
    }
  }

  Future<void> _saveStockEntry() async {
    if (_isSavingStock) {
      return;
    }
    final kurumkodu = _currentInstitutionId();
    if (kurumkodu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
      );
      return;
    }
    if (_selectedProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stok girişi için ürün seçin.')),
      );
      return;
    }
    final quantity = _parseDecimal(_stockQuantityController.text);
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir miktar girin.')),
      );
      return;
    }

    setState(() {
      _isSavingStock = true;
    });

    final productId = _selectedProductId!;
    final productName = _selectedProductName ?? '';
    final productUnit = _selectedProductUnit ?? '';
    final note = _stockNoteController.text.trim();
    final createdByName = [
      (_user.data['adi'] ?? '').toString().trim(),
      (_user.data['soyadi'] ?? '').toString().trim(),
    ].where((part) => part.isNotEmpty).join(' ');
    final createdById =
        (_user.data['email'] ?? _user.data['uid'] ?? '').toString();

    try {
      final productRef = _productsRef(kurumkodu).doc(productId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(productRef);
        if (!snapshot.exists) {
          throw 'Ürün bulunamadı.';
        }
        transaction.update(productRef, {
          'stok': FieldValue.increment(quantity),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      await _stockMovementRef(kurumkodu).add({
        'urunId': productId,
        'urunAdi': productName,
        'birim': productUnit,
        'miktar': quantity,
        'tip': 'giris',
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
        'createdById': createdById,
        'createdByName': createdByName,
      });
      if (!mounted) return;
      _stockQuantityController.clear();
      _stockNoteController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stok girişi işlendi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stok girişi yapılamadı: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingStock = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stok'),
          actions: const [HomeIconButton()],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Satış'),
              Tab(text: 'Tüketim'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildSalesTab(),
            _buildConsumptionPlaceholder(),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(
          icon: Icons.inventory_2_outlined,
          title: 'Ürün Tanımı',
          subtitle: 'Satılacak ürünleri tanımlayın.',
        ),
        const SizedBox(height: 8),
        _buildProductFormCard(),
        const SizedBox(height: 20),
        _buildSectionHeader(
          icon: Icons.add_business_outlined,
          title: 'Stok Girişi',
          subtitle: 'Mevcut ürünlere stok ekleyin.',
        ),
        const SizedBox(height: 8),
        _buildStockEntryCard(),
        const SizedBox(height: 20),
        _buildSectionHeader(
          icon: Icons.list_alt_outlined,
          title: 'Mevcut Stok',
          subtitle: 'Tüm ürünleri ve stok durumunu görüntüleyin.',
        ),
        const SizedBox(height: 8),
        _buildStockListCard(),
      ],
    );
  }

  Widget _buildConsumptionPlaceholder() {
    return Center(
      child: Text(
        'Tüketim bölümü yakında.',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductFormCard() {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: _isProductFormExpanded,
        onExpansionChanged: (value) {
          setState(() {
            _isProductFormExpanded = value;
          });
        },
        title: const Text(
          'Yeni ürün ekle',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            controller: _productNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Ürün adı',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedUnit,
            items: _units
                .map(
                  (unit) => DropdownMenuItem(
                    value: unit,
                    child: Text(unit),
                  ),
                )
                .toList(),
            onChanged: _isSavingProduct
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedUnit = value;
                    });
                  },
            decoration: const InputDecoration(
              labelText: 'Satış birimi',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _productPriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Satış fiyatı',
              suffixText: 'TL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSavingProduct ? null : _saveProduct,
              icon: _isSavingProduct
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_isSavingProduct ? 'Kaydediliyor' : 'Ürün Kaydet'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockEntryCard() {
    final kurumkodu = _currentInstitutionId();
    if (kurumkodu.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Kurum bilgisi bulunamadı.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _productsRef(kurumkodu).orderBy('ad').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Ürünler yüklenemedi.');
            }
            if (!snapshot.hasData) {
              return const LinearProgressIndicator(minHeight: 2);
            }
            final docs = snapshot.data!.docs;
            final products = docs
                .map(
                  (doc) => _StockProduct.fromSnapshot(doc),
                )
                .toList();
            if (products.isEmpty) {
              return const Text('Önce ürün tanımı yapmalısınız.');
            }
            if (_selectedProductId == null ||
                !products.any((p) => p.id == _selectedProductId)) {
              final first = products.first;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _selectedProductId = first.id;
                  _selectedProductName = first.name;
                  _selectedProductUnit = first.unit;
                });
              });
            }
            final query = normalizeTr(_productSearchController.text);
            final filteredProducts = query.isEmpty
                ? products
                : products
                    .where(
                      (product) => normalizeTr(product.name).contains(query),
                    )
                    .toList();
            if (filteredProducts.isNotEmpty &&
                !filteredProducts.any((p) => p.id == _selectedProductId)) {
              final firstMatch = filteredProducts.first;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _selectedProductId = firstMatch.id;
                  _selectedProductName = firstMatch.name;
                  _selectedProductUnit = firstMatch.unit;
                });
              });
            }
            final selectedProduct = (filteredProducts.isNotEmpty
                    ? filteredProducts
                    : products)
                .firstWhere(
              (product) => product.id == _selectedProductId,
              orElse: () => (filteredProducts.isNotEmpty
                  ? filteredProducts.first
                  : products.first),
            );
            final selectedUnit = _selectedProductUnit ?? selectedProduct.unit;

            return Column(
              children: [
                TextField(
                  controller: _productSearchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Ürün ara',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _productSearchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _productSearchController.clear();
                              setState(() {});
                            },
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedProduct.id,
                  items: (filteredProducts.isNotEmpty
                          ? filteredProducts
                          : products)
                      .map(
                        (product) => DropdownMenuItem(
                          value: product.id,
                          child: Text(product.label),
                        ),
                      )
                      .toList(),
                  onChanged: _isSavingStock
                      ? null
                      : (value) {
                          final sourceList = filteredProducts.isNotEmpty
                              ? filteredProducts
                              : products;
                          final selected =
                              sourceList.firstWhere((p) => p.id == value);
                          setState(() {
                            _selectedProductId = selected.id;
                            _selectedProductName = selected.name;
                            _selectedProductUnit = selected.unit;
                          });
                        },
                  decoration: const InputDecoration(
                    labelText: 'Ürün',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (filteredProducts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Eşleşen ürün bulunamadı.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _stockQuantityController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Miktar',
                    suffixText: selectedUnit,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _stockNoteController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Not (opsiyonel)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSavingStock ? null : _saveStockEntry,
                    icon: _isSavingStock
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_circle_outline),
                    label:
                        Text(_isSavingStock ? 'Kaydediliyor' : 'Stok Girişi Yap'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStockListCard() {
    final kurumkodu = _currentInstitutionId();
    if (kurumkodu.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Kurum bilgisi bulunamadı.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _productsRef(kurumkodu).orderBy('ad').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Stok listesi yüklenemedi.'),
              );
            }
            if (!snapshot.hasData) {
              return const LinearProgressIndicator(minHeight: 2);
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Henüz ürün bulunmuyor.'),
              );
            }
            final products = docs
                .map((doc) => _StockProduct.fromSnapshot(doc))
                .toList();
            final searchQuery = normalizeTr(_stockListSearchController.text);
            final filteredProducts = searchQuery.isEmpty
                ? products
                : products
                    .where(
                      (product) => normalizeTr(product.name).contains(searchQuery),
                    )
                    .toList();
            final sortedProducts = _sortProducts(
              filteredProducts,
              _stockSortType,
            );
            return ListView.separated(
              itemCount: sortedProducts.length + 1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    children: [
                      TextField(
                        controller: _stockListSearchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          labelText: 'Ürün ara',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _stockListSearchController.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _stockListSearchController.clear();
                                    setState(() {});
                                  },
                                ),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<_StockSortType>(
                        value: _stockSortType,
                        items: _StockSortType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(_stockSortLabel(type)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _stockSortType = value;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Sıralama',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (sortedProducts.isEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Eşleşen ürün bulunamadı.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                    ],
                  );
                }
                final product = sortedProducts[index - 1];
                final priceLabel = product.price != null
                    ? '${product.price!.toStringAsFixed(2)} TL'
                    : '-';
                final stockLabel = product.stock != null
                    ? '${product.stock!.toStringAsFixed(2)} ${product.unit}'
                    : '-';
                final isManager = isManagerUser(_user.data);
                return ListTile(
                  title: Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('Birim: ${product.unit}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            stockLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            priceLabel,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                      PopupMenuButton<_StockMenuAction>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (action) async {
                          switch (action) {
                            case _StockMenuAction.updatePrice:
                              await _showUpdatePriceDialog(product);
                              break;
                            case _StockMenuAction.adjustStock:
                              await _showAdjustStockDialog(product);
                              break;
                            case _StockMenuAction.sell:
                              await _showStockSaleDialog(product);
                              break;
                            case _StockMenuAction.movements:
                              await _showStockMovements(product);
                              break;
                            case _StockMenuAction.delete:
                              if (!isManager) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Bu işlem için yetkiniz yok.'),
                                    ),
                                  );
                                }
                                return;
                              }
                              await _confirmDeleteProduct(product);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: _StockMenuAction.updatePrice,
                            child: Text('Satış fiyatı güncelle'),
                          ),
                          const PopupMenuItem(
                            value: _StockMenuAction.adjustStock,
                            child: Text('Stok düzeltme'),
                          ),
                          const PopupMenuItem(
                            value: _StockMenuAction.sell,
                            child: Text('Satış'),
                          ),
                          const PopupMenuItem(
                            value: _StockMenuAction.movements,
                            child: Text('Stok hareketleri'),
                          ),
                          if (isManager)
                            const PopupMenuItem(
                              value: _StockMenuAction.delete,
                              child: Text('Ürünü sil'),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _showUpdatePriceDialog(_StockProduct product) async {
    final controller = TextEditingController(
      text: product.price != null ? product.price!.toStringAsFixed(2) : '',
    );
    bool isSaving = false;

    final kurumkodu = _currentInstitutionId();
    if (kurumkodu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Satış fiyatını güncelle'),
              content: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Yeni fiyat',
                  suffixText: 'TL',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final price = _parseDecimal(controller.text);
                          if (price == null || price < 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Geçerli bir fiyat girin.'),
                              ),
                            );
                            return;
                          }
                          setDialogState(() {
                            isSaving = true;
                          });
                          try {
                            await _productsRef(kurumkodu)
                                .doc(product.id)
                                .update({
                              'fiyat': price,
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Fiyat güncellenemedi: $e'),
                                ),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isSaving = false;
                              });
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  List<_StockProduct> _sortProducts(
    List<_StockProduct> products,
    _StockSortType sortType,
  ) {
    final sorted = [...products];
    switch (sortType) {
      case _StockSortType.alphabetical:
        sorted.sort((a, b) => a.name.compareTo(b.name));
        break;
      case _StockSortType.stockAsc:
        sorted.sort((a, b) => (a.stock ?? 0).compareTo(b.stock ?? 0));
        break;
      case _StockSortType.stockDesc:
        sorted.sort((a, b) => (b.stock ?? 0).compareTo(a.stock ?? 0));
        break;
    }
    return sorted;
  }

  String _stockSortLabel(_StockSortType type) {
    switch (type) {
      case _StockSortType.alphabetical:
        return 'A-Z';
      case _StockSortType.stockAsc:
        return 'Stok azdan çoğa';
      case _StockSortType.stockDesc:
        return 'Stok çoktan aza';
    }
  }

  Future<void> _showAdjustStockDialog(_StockProduct product) async {
    final controller = TextEditingController(
      text: product.stock != null ? product.stock!.toStringAsFixed(2) : '',
    );
    bool isSaving = false;
    final kurumkodu = _currentInstitutionId();
    if (kurumkodu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Stok düzeltme'),
              content: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Yeni stok miktarı',
                  suffixText: product.unit,
                  border: const OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final newValue = _parseDecimal(controller.text);
                          if (newValue == null || newValue < 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Geçerli bir miktar girin.'),
                              ),
                            );
                            return;
                          }
                          setDialogState(() {
                            isSaving = true;
                          });
                          try {
                            final productRef =
                                _productsRef(kurumkodu).doc(product.id);
                            await productRef.update({
                              'stok': newValue,
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                            await _stockMovementRef(kurumkodu).add({
                              'urunId': product.id,
                              'urunAdi': product.name,
                              'birim': product.unit,
                              'miktar': newValue,
                              'tip': 'duzeltme',
                              'oncekiStok': product.stock ?? 0,
                              'createdAt': FieldValue.serverTimestamp(),
                              'createdById': (_user.data['email'] ??
                                      _user.data['uid'] ??
                                      '')
                                  .toString(),
                              'createdByName': [
                                (_user.data['adi'] ?? '').toString().trim(),
                                (_user.data['soyadi'] ?? '').toString().trim(),
                              ].where((part) => part.isNotEmpty).join(' '),
                            });
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Stok düzeltilemedi: $e'),
                                ),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isSaving = false;
                              });
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _showStockSaleDialog(_StockProduct product) async {
    final qtyController = TextEditingController();
    final noteController = TextEditingController();
    bool isSaving = false;
    final kurumkodu = _currentInstitutionId();
    if (kurumkodu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ürün satışı'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Miktar',
                      suffixText: product.unit,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Not (opsiyonel)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final qty = _parseDecimal(qtyController.text);
                          if (qty == null || qty <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Geçerli bir miktar girin.'),
                              ),
                            );
                            return;
                          }
                          if ((product.stock ?? 0) < qty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Stok yetersiz.'),
                              ),
                            );
                            return;
                          }
                          setDialogState(() {
                            isSaving = true;
                          });
                          try {
                            final productRef =
                                _productsRef(kurumkodu).doc(product.id);
                            await FirebaseFirestore.instance.runTransaction(
                              (transaction) async {
                                final snapshot = await transaction.get(productRef);
                                final currentStock =
                                    _readDouble(snapshot.data()?['stok']) ?? 0;
                                if (currentStock < qty) {
                                  throw 'Stok yetersiz.';
                                }
                                transaction.update(productRef, {
                                  'stok': FieldValue.increment(-qty),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                });
                              },
                            );
                            await _stockMovementRef(kurumkodu).add({
                              'urunId': product.id,
                              'urunAdi': product.name,
                              'birim': product.unit,
                              'miktar': qty,
                              'tip': 'satis',
                              'note': noteController.text.trim(),
                              'createdAt': FieldValue.serverTimestamp(),
                              'createdById': (_user.data['email'] ??
                                      _user.data['uid'] ??
                                      '')
                                  .toString(),
                              'createdByName': [
                                (_user.data['adi'] ?? '').toString().trim(),
                                (_user.data['soyadi'] ?? '').toString().trim(),
                              ].where((part) => part.isNotEmpty).join(' '),
                            });
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Satış yapılamadı: $e')),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isSaving = false;
                              });
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    qtyController.dispose();
    noteController.dispose();
  }

  Future<void> _showStockMovements(_StockProduct product) async {
    final kurumkodu = _currentInstitutionId();
    if (kurumkodu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Stok hareketleri'),
          content: SizedBox(
            width: 420,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stockMovementRef(kurumkodu)
                  .where('urunId', isEqualTo: product.id)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Hareketler yüklenemedi.');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Text('Henüz hareket bulunmuyor.');
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final qty = _readDouble(data['miktar']) ?? 0;
                    final type = (data['tip'] ?? '').toString();
                    final note = (data['note'] ?? '').toString().trim();
                    final createdAt = data['createdAt'] is Timestamp
                        ? (data['createdAt'] as Timestamp).toDate()
                        : null;
                    final label = _movementLabel(type);
                    final dateLabel = createdAt == null
                        ? '-'
                        : '${createdAt.day.toString().padLeft(2, '0')}.'
                            '${createdAt.month.toString().padLeft(2, '0')}.'
                            '${createdAt.year}';
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withOpacity(0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$label • ${qty.toStringAsFixed(2)} ${product.unit}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text('Tarih: $dateLabel'),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Not: $note'),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
  }

  String _movementLabel(String type) {
    switch (type) {
      case 'giris':
        return 'Stok girişi';
      case 'satis':
        return 'Satış';
      case 'duzeltme':
        return 'Stok düzeltme';
      default:
        return 'Hareket';
    }
  }

  Future<void> _confirmDeleteProduct(_StockProduct product) async {
    final kurumkodu = _currentInstitutionId();
    if (kurumkodu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kurum bilgisi bulunamadı.')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ürün silinsin mi?'),
        content: const Text('Bu ürün kalıcı olarak silinecektir.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    try {
      await _productsRef(kurumkodu).doc(product.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ürün silindi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ürün silinemedi: $e')),
        );
      }
    }
  }
}

enum _StockMenuAction {
  updatePrice,
  adjustStock,
  sell,
  movements,
  delete,
}

enum _StockSortType {
  alphabetical,
  stockAsc,
  stockDesc,
}

class _StockProduct {
  const _StockProduct({
    required this.id,
    required this.name,
    required this.unit,
    required this.price,
    required this.stock,
  });

  final String id;
  final String name;
  final String unit;
  final double? price;
  final double? stock;

  String get label => '$name • $unit';

  factory _StockProduct.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    return _StockProduct(
      id: snapshot.id,
      name: (data['ad'] ?? '').toString().trim(),
      unit: (data['birim'] ?? '').toString().trim(),
      price: _readDouble(data['fiyat']),
      stock: _readDouble(data['stok']),
    );
  }
}

double? _readDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final parsed = double.tryParse(value.toString());
  return parsed;
}
