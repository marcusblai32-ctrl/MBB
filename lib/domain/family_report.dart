class FamilyMemberLine {
  const FamilyMemberLine(this.name, this.churchRole, this.phone, this.status);
  final String name, churchRole, phone, status;
}

class FamilyBlock {
  FamilyBlock(this.id, this.name, this.address);
  final int id;
  final String name, address;
  final List<FamilyMemberLine> members = [];
}

class FamilyReport {
  FamilyReport(this.families, this.unassigned, this.totalMembers);
  final List<FamilyBlock> families;
  final List<FamilyMemberLine> unassigned; // membres sans famille
  final int totalMembers; // tous les membres enregistrés
  int get totalFamilies => families.length;
  int get membersInFamilies => totalMembers - unassigned.length;
}

/// Rapport des familles : toutes les familles, tous les membres de chacune,
/// et les totaux. Calculé uniquement à partir des données enregistrées.
class FamilyReportBuilder {
  const FamilyReportBuilder._();

  static FamilyReport build(List<Map<String, Object?>> families, List<Map<String, Object?>> members) {
    final blocks = <int, FamilyBlock>{
      for (final f in families) f['id'] as int: FamilyBlock(f['id'] as int, '${f['name']}', '${f['address'] ?? ''}')
    };
    final unassigned = <FamilyMemberLine>[];
    for (final m in members) {
      final line = FamilyMemberLine('${m['first_name']} ${m['last_name']}'.trim(),
          '${m['church_role'] ?? ''}', '${m['phone'] ?? ''}', '${m['status'] ?? ''}');
      final fid = m['family_id'];
      if (fid is int && blocks.containsKey(fid)) {
        blocks[fid]!.members.add(line);
      } else {
        unassigned.add(line);
      }
    }
    int byName(FamilyMemberLine a, FamilyMemberLine b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    for (final b in blocks.values) {
      b.members.sort(byName);
    }
    unassigned.sort(byName);
    final list = blocks.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return FamilyReport(list, unassigned, members.length);
  }
}
