/// Normalizes Turkish text for search comparison.
/// Collapses all i-variants (İ, I, ı, i) to 'i' and all other Turkish chars
/// to their ASCII equivalents so search is case- and diacritic-insensitive.
String normalizeTr(String input) {
  return input
      .trim()
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')   // Latin capital I → i (same bucket as dotted İ)
      .replaceAll('ı', 'i')   // Turkish dotless lowercase i → i
      .replaceAll('Ğ', 'g')
      .replaceAll('ğ', 'g')
      .replaceAll('Ü', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('Ş', 's')
      .replaceAll('ş', 's')
      .replaceAll('Ö', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('Ç', 'c')
      .replaceAll('ç', 'c')
      .toLowerCase();
}

String toUpperCaseTr(String input) {
  return input
      .trim()
      .replaceAll('i', 'İ')
      .replaceAll('ı', 'I')
      .replaceAll('ğ', 'Ğ')
      .replaceAll('ü', 'Ü')
      .replaceAll('ş', 'Ş')
      .replaceAll('ö', 'Ö')
      .replaceAll('ç', 'Ç')
      .toUpperCase();
}

/// Title-cases a name with proper Turkish uppercase rules.
/// "ahmet ali" → "Ahmet Ali", "ışık" → "Işık", "işlem" → "İşlem"
String toTitleCaseTr(String input) {
  return input
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((word) {
        final first = word[0];
        final String upper;
        switch (first) {
          case 'i':
            upper = 'İ'; // dotted i → dotted capital İ
          case 'ı':
            upper = 'I'; // dotless i → dotless capital I
          case 'ğ':
            upper = 'Ğ';
          case 'ü':
            upper = 'Ü';
          case 'ş':
            upper = 'Ş';
          case 'ö':
            upper = 'Ö';
          case 'ç':
            upper = 'Ç';
          default:
            upper = first.toUpperCase();
        }
        // Lowercase the rest with Turkish-aware mapping (İ→i, I→ı, then standard lower)
        final rest = word
            .substring(1)
            .replaceAll('İ', 'i')
            .replaceAll('I', 'ı')
            .toLowerCase();
        return upper + rest;
      })
      .join(' ');
}
