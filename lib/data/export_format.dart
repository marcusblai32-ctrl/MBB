import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Format d'échange MBB (JSON). Les PDF ne servent pas à restaurer les données.
const mbbExportFormat = 'mbb-export';
const mbbExportVersion = 1;

String canonicalJson(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonicalJson(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(canonicalJson).join(',')}]';
  return jsonEncode(v);
}

String checksumOf(Object? data) =>
    sha256.convert(utf8.encode(canonicalJson(data))).toString();

Map<String, Object?> buildEnvelope({
  required String bureau,
  required Map<String, Object?> data,
  required DateTime generatedAt,
  required String appVersion,
}) =>
    {
      'format': mbbExportFormat,
      'version': mbbExportVersion,
      'bureau': bureau,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'appVersion': appVersion,
      'checksum': checksumOf(data),
      'data': data,
    };

class EnvelopeCheck {
  EnvelopeCheck(this.errors, this.data);
  final List<String> errors;
  final Map<String, Object?>? data;
  bool get ok => errors.isEmpty;
}

/// Validation stricte d'une enveloppe : structure, version, bureau attendu,
/// somme de contrôle. Ne lève jamais d'exception sur un contenu malformé.
EnvelopeCheck validateEnvelope(String raw, {required String expectedBureau}) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return EnvelopeCheck(['Le fichier n’est pas un JSON valide.'], null);
  }
  if (decoded is! Map) {
    return EnvelopeCheck(['Structure racine invalide.'], null);
  }
  final errors = <String>[];
  if (decoded['format'] != mbbExportFormat) {
    errors.add('Format de fichier inconnu.');
  }
  final version = decoded['version'];
  if (version is! int) {
    errors.add('Version du format absente.');
  } else if (version > mbbExportVersion) {
    errors.add('Version $version plus récente que celle prise en charge ($mbbExportVersion).');
  } else if (version < 1) {
    errors.add('Version $version invalide.');
  }
  if (decoded['bureau'] != expectedBureau) {
    errors.add('Ce fichier provient d’un autre bureau (${decoded['bureau']}).');
  }
  final data = decoded['data'];
  if (data is! Map) {
    errors.add('Section « data » absente ou invalide.');
  } else if (decoded['checksum'] != checksumOf(data)) {
    errors.add('Somme de contrôle incorrecte : fichier modifié ou corrompu.');
  }
  return EnvelopeCheck(
      errors, errors.isEmpty ? Map<String, Object?>.from(data as Map) : null);
}

/// Écriture financière échangée.
class ExchangeTx {
  ExchangeTx({
    required this.uid,
    required this.reference,
    required this.kind,
    required this.category,
    required this.dateIso,
    required this.description,
    required this.amountCents,
    required this.voided,
  });
  final String uid, reference, kind, category, dateIso, description;
  final int amountCents;
  final bool voided;

  Map<String, Object?> toJson() => {
        'uid': uid,
        'reference': reference,
        'kind': kind,
        'category': category,
        'date': dateIso,
        'description': description,
        'amountCents': amountCents,
        'voided': voided,
      };

  bool sameContentAs(ExchangeTx o) =>
      kind == o.kind &&
      category == o.category &&
      dateIso == o.dateIso &&
      description == o.description &&
      amountCents == o.amountCents &&
      voided == o.voided;

  /// Retourne null et remplit [problems] si l'entrée est invalide.
  static ExchangeTx? tryFrom(Object? raw, int index, List<String> problems) {
    if (raw is! Map) {
      problems.add('Ligne ${index + 1} : objet attendu.');
      return null;
    }
    String? s(String k) => raw[k] is String && (raw[k] as String).trim().isNotEmpty
        ? (raw[k] as String)
        : null;
    final uid = s('uid'), ref = s('reference'), cat = s('category');
    final date = s('date');
    final kind = raw['kind'];
    final cents = raw['amountCents'];
    final bad = <String>[
      if (uid == null) 'uid',
      if (ref == null) 'reference',
      if (cat == null) 'category',
      if (kind != 'recette' && kind != 'depense') 'kind',
      if (cents is! int || cents <= 0) 'amountCents',
      if (date == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) || DateTime.tryParse(date) == null) 'date',
      if (raw['voided'] is! bool) 'voided',
    ];
    if (bad.isNotEmpty) {
      problems.add('Ligne ${index + 1} : champ(s) invalide(s) ${bad.join(', ')}.');
      return null;
    }
    return ExchangeTx(
      uid: uid!,
      reference: ref!,
      kind: kind as String,
      category: cat!,
      dateIso: date!,
      description: raw['description'] is String ? raw['description'] as String : '',
      amountCents: cents as int,
      voided: raw['voided'] as bool,
    );
  }
}

class ImportPlan {
  final toAdd = <ExchangeTx>[];
  final identicalDuplicates = <ExchangeTx>[];
  final conflicts = <String>[]; // même uid avec contenu différent, ou référence réutilisée
  final invalid = <String>[];
  bool get hasBlockingIssues => conflicts.isNotEmpty || invalid.isNotEmpty;

  String summary() =>
      '${toAdd.length} à ajouter, ${identicalDuplicates.length} déjà présentes, '
      '${conflicts.length} conflit(s), ${invalid.length} ligne(s) invalide(s).';
}

/// Prépare une importation SANS rien écrire : l'utilisateur confirme ensuite.
/// Aucune donnée existante n'est jamais supprimée ni écrasée.
ImportPlan planImport(List<Object?> incoming, List<ExchangeTx> existing) {
  final plan = ImportPlan();
  final byUid = {for (final e in existing) e.uid: e};
  final byRef = {for (final e in existing) e.reference: e};
  final seen = <String>{};
  final seenRefs = <String, String>{};
  for (var i = 0; i < incoming.length; i++) {
    final tx = ExchangeTx.tryFrom(incoming[i], i, plan.invalid);
    if (tx == null) continue;
    if (!seen.add(tx.uid)) {
      plan.conflicts.add('${tx.reference} : uid présent deux fois dans le fichier.');
      continue;
    }
    final known = byUid[tx.uid];
    if (known != null) {
      if (known.sameContentAs(tx)) {
        plan.identicalDuplicates.add(tx);
      } else {
        plan.conflicts.add('${tx.reference} : existe déjà avec un contenu différent.');
      }
      continue;
    }
    final refOwner = byRef[tx.reference];
    final fileOwner = seenRefs[tx.reference];
    if ((refOwner != null && refOwner.uid != tx.uid) ||
        (fileOwner != null && fileOwner != tx.uid)) {
      plan.conflicts.add('${tx.reference} : référence déjà utilisée par une autre opération.');
      continue;
    }
    seenRefs[tx.reference] = tx.uid;
    plan.toAdd.add(tx);
  }
  return plan;
}
