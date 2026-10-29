import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/permissions.dart';
import '../database/app_database.dart';
import 'export_format.dart';

const _appVersion = '1.0.0';

class FinanceExportResult {
  FinanceExportResult(this.json, this.exported, this.skipped);
  final String json;
  final int exported;
  final int skipped; // lignes à montant nul ou négatif, non exportables
}

class FinanceImportPreview {
  FinanceImportPreview.invalid(this.fileErrors) : plan = null;
  FinanceImportPreview.ready(this.plan) : fileErrors = const [];
  final List<String> fileErrors;
  final ImportPlan? plan;
  bool get fileOk => plan != null;
}

/// Échange des écritures financières entre appareils. Réservé au bureau
/// Comptabilité : les droits sont vérifiés ici.
class FinanceExchange {
  const FinanceExchange._();

  static Future<List<ExchangeTx>> _existing() async {
    final rows = await AppDatabase.instance.query('transactions');
    final out = <ExchangeTx>[];
    for (final r in rows) {
      final cents = ((r['amount'] as num) * 100).round();
      final uid = '${r['uid']}';
      if (cents <= 0 || uid.isEmpty) continue;
      out.add(ExchangeTx(
        uid: uid,
        reference: '${r['reference']}',
        kind: r['kind'] == 'Recette' ? 'recette' : 'depense',
        category: '${r['category']}',
        dateIso: '${r['transaction_date']}',
        description: '${r['description']}',
        amountCents: cents,
        voided: false,
      ));
    }
    return out;
  }

  static Future<FinanceExportResult> export(Principal actor) async {
    AccessPolicy.require(actor, Permission.financeExport);
    final all = await AppDatabase.instance.query('transactions');
    final list = await _existing();
    final env = buildEnvelope(
      bureau: Bureau.comptabilite.folder,
      generatedAt: DateTime.now(),
      appVersion: _appVersion,
      data: {'transactions': [for (final t in list) t.toJson()]},
    );
    await AppDatabase.instance.log('EXPORT_FINANCE', '${list.length} opérations', username: actor.username);
    return FinanceExportResult(jsonEncode(env), list.length, all.length - list.length);
  }

  /// Analyse un fichier SANS rien écrire.
  static Future<FinanceImportPreview> preview(Principal actor, String raw) async {
    AccessPolicy.require(actor, Permission.financeImport);
    final check = validateEnvelope(raw, expectedBureau: Bureau.comptabilite.folder);
    if (!check.ok) return FinanceImportPreview.invalid(check.errors);
    final txs = check.data!['transactions'];
    if (txs is! List) {
      return FinanceImportPreview.invalid(['Liste « transactions » absente.']);
    }
    return FinanceImportPreview.ready(planImport(txs, await _existing()));
  }

  /// Applique uniquement les écritures nouvelles (jamais d'écrasement ni de
  /// suppression), en une seule transaction SQL, après copie de sécurité.
  static Future<int> apply(Principal actor, ImportPlan plan) async {
    AccessPolicy.require(actor, Permission.financeImport);
    if (AppDatabase.readOnly) throw ReadOnlyDeviceException();
    final supported = plan.toAdd.where((t) => !t.voided).toList();
    if (supported.isEmpty) return 0;
    final dir = await getApplicationSupportDirectory();
    final safetyDir = Directory(p.join(dir.path, 'sauvegardes_auto'));
    await safetyDir.create(recursive: true);
    final src = File(p.join(dir.path, 'mbb_database.db'));
    if (await src.exists()) {
      await src.copy(p.join(safetyDir.path, 'avant_import_${DateTime.now().millisecondsSinceEpoch}.db'));
    }
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final t in supported) {
        await txn.insert('transactions', {
          'uid': t.uid,
          'reference': t.reference,
          'kind': t.kind == 'recette' ? 'Recette' : 'Dépense',
          'category': t.category,
          'amount': t.amountCents / 100.0,
          'transaction_date': t.dateIso,
          'description': t.description,
          'payment_method': '',
          'created_at': now,
        });
      }
    });
    await AppDatabase.instance.log('IMPORT_FINANCE', '${supported.length} opérations ajoutées', username: actor.username);
    return supported.length;
  }
}
