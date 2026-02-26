import 'package:flutter/material.dart';

class GizlilikPolitikasiPage extends StatelessWidget {
  const GizlilikPolitikasiPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gizlilik Politikasi'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'Son guncelleme: 18 Subat 2026',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 12),
          Text(
            'Mebs Kurum Takip, kurum ici operasyonlarin yonetimi icin kullanilir. '
            'Uygulama; kullanici hesap bilgileri, danisan kayitlari, randevu/islem '
            'bilgileri, telefon numaralari ve fotograf gibi verileri sadece hizmetin '
            'sunulmasi amaciyla isler.',
          ),
          SizedBox(height: 12),
          Text(
            'Veriler, kimlik dogrulama, veritabani ve dosya depolama gibi teknik '
            'hizmetlerin saglanmasi icin Firebase altyapisinda saklanabilir. '
            'SMS gonderim sureclerinde telefon numarasi ve mesaj icerigi, '
            'entegrasyon servisleri uzerinden islenebilir.',
          ),
          SizedBox(height: 12),
          Text(
            'Kamera ve galeri erisimi sadece fotograf secme/cekme islemleri icin '
            'kullanilir. Bu izinler disinda cihaziniza ait gereksiz bir veriye '
            'erisilmez.',
          ),
          SizedBox(height: 12),
          Text(
            'Kisisel veriler, ilgili mevzuat ve isleme amacinin gerektirdigi sure '
            'boyunca saklanir; sure sonunda silinir, yok edilir veya anonimlestirilir.',
          ),
          SizedBox(height: 12),
          Text(
            'KVKK kapsamindaki basvuru, duzeltme ve silme talepleriniz icin kurum '
            'yoneticiniz veya veri sorumlusu ile iletisime gecebilirsiniz.',
          ),
        ],
      ),
    );
  }
}
