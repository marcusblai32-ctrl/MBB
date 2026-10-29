import '../core/money.dart';
import '../core/periods.dart';

enum EntryKind { recette, depense }

class LedgerEntry {
  const LedgerEntry({
    required this.uid,
    required this.reference,
    required this.kind,
    required this.category,
    required this.dateIso,
    required this.description,
    required this.amount,
    this.voided = false,
    this.voidReason = '',
  });
  final String uid, reference, category, dateIso, description, voidReason;
  final EntryKind kind;
  final Money amount; // toujours positif ; le sens est donné par `kind`
  final bool voided;
}

class CategoryTotal {
  const CategoryTotal(this.category, this.total, this.count);
  final String category;
  final Money total;
  final int count;
}

class LedgerReport {
  const LedgerReport({
    required this.period,
    required this.opening,
    required this.income,
    required this.expenses,
    required this.closing,
    required this.incomeEntries,
    required this.expenseEntries,
    required this.voidedEntries,
    required this.incomeByCategory,
    required this.expenseByCategory,
  });
  final ReportPeriod period;
  final Money opening, income, expenses, closing;
  final List<LedgerEntry> incomeEntries, expenseEntries, voidedEntries;
  final List<CategoryTotal> incomeByCategory, expenseByCategory;
  bool get isEmpty => incomeEntries.isEmpty && expenseEntries.isEmpty;
  Money get net => income - expenses;
}

/// Calcul comptable pur (sans interface ni base de données) : seule source
/// des totaux utilisés par les écrans, le PDF et l'Excel.
class LedgerCalculator {
  const LedgerCalculator._();

  static int _cmp(LedgerEntry a, LedgerEntry b) {
    final d = a.dateIso.compareTo(b.dateIso);
    return d != 0 ? d : a.reference.compareTo(b.reference);
  }

  static List<CategoryTotal> _byCategory(List<LedgerEntry> list) {
    final totals = <String, int>{};
    final counts = <String, int>{};
    for (final e in list) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount.cents;
      counts[e.category] = (counts[e.category] ?? 0) + 1;
    }
    final out = [
      for (final k in totals.keys) CategoryTotal(k, Money(totals[k]!), counts[k]!)
    ]..sort((a, b) {
        final c = b.total.cents.compareTo(a.total.cents);
        return c != 0 ? c : a.category.compareTo(b.category);
      });
    return out;
  }

  /// [all] : toutes les écritures du bureau (annulées incluses).
  /// [initialBalance] : solde de départ saisi à la mise en service.
  static LedgerReport build(List<LedgerEntry> all, ReportPeriod period,
      {Money initialBalance = Money.zero}) {
    var opening = initialBalance;
    final inPeriod = <LedgerEntry>[];
    final voided = <LedgerEntry>[];
    for (final e in all) {
      final before = e.dateIso.compareTo(period.startIso) < 0;
      if (e.voided) {
        if (period.contains(e.dateIso)) voided.add(e);
        continue;
      }
      if (before) {
        opening += e.kind == EntryKind.recette ? e.amount : -e.amount;
      } else if (period.contains(e.dateIso)) {
        inPeriod.add(e);
      }
    }
    final inc = inPeriod.where((e) => e.kind == EntryKind.recette).toList()..sort(_cmp);
    final exp = inPeriod.where((e) => e.kind == EntryKind.depense).toList()..sort(_cmp);
    voided.sort(_cmp);
    final income = Money(inc.fold(0, (s, e) => s + e.amount.cents));
    final expenses = Money(exp.fold(0, (s, e) => s + e.amount.cents));
    return LedgerReport(
      period: period,
      opening: opening,
      income: income,
      expenses: expenses,
      closing: opening + income - expenses,
      incomeEntries: inc,
      expenseEntries: exp,
      voidedEntries: voided,
      incomeByCategory: _byCategory(inc),
      expenseByCategory: _byCategory(exp),
    );
  }
}
