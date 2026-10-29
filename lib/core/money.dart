/// Montant monétaire stocké en entier (centimes) : aucune erreur d'arrondi
/// binaire, contrairement à `double`.
class Money implements Comparable<Money> {
  const Money(this.cents);
  static const zero = Money(0);

  final int cents;

  Money operator +(Money o) => Money(cents + o.cents);
  Money operator -(Money o) => Money(cents - o.cents);
  Money operator -() => Money(-cents);
  bool get isNegative => cents < 0;
  bool get isZero => cents == 0;

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);
  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;
  @override
  int get hashCode => cents.hashCode;

  /// Lit une saisie utilisateur : « 1 250,50 », « 1250.5 », « 300 ».
  /// Séparateur décimal « , » ou « . » (2 décimales maximum). Les espaces
  /// servent de séparateurs de milliers. Retourne null si invalide.
  static Money? tryParse(String input) {
    var s = input.replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
    if (s.isEmpty) return null;
    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    }
    final m = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(s);
    if (m == null) return null;
    final whole = int.tryParse(m.group(1)!);
    if (whole == null || whole > 900000000000) return null;
    final frac = (m.group(2) ?? '').padRight(2, '0');
    final value = whole * 100 + int.parse(frac.isEmpty ? '0' : frac);
    return Money(negative ? -value : value);
  }

  /// Format français : « 1 250,50 » (sans devise).
  String format() {
    final abs = cents.abs();
    final whole = (abs ~/ 100).toString();
    final frac = (abs % 100).toString().padLeft(2, '0');
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(' ');
      buf.write(whole[i]);
    }
    return '${cents < 0 ? '-' : ''}$buf,$frac';
  }

  String formatWith(String currency) => '${format()} $currency';

  @override
  String toString() => format();
}
