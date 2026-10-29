import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 avec sel aléatoire. Format stocké :
/// `pbkdf2$sha256$<itérations>$<selHex>$<hashHex>`.
class PasswordHasher {
  const PasswordHasher._();

  static const defaultIterations = 120000;

  static String hash(String password,
      {int iterations = defaultIterations, List<int>? saltBytes}) {
    final salt = saltBytes ?? _randomBytes(16);
    final dk = _pbkdf2(utf8.encode(password), salt, iterations);
    return 'pbkdf2\$sha256\$$iterations\$${_hex(salt)}\$${_hex(dk)}';
  }

  static bool verify(String password, String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 5 || parts[0] != 'pbkdf2' || parts[1] != 'sha256') {
      return false;
    }
    final iterations = int.tryParse(parts[2]);
    if (iterations == null || iterations < 1) return false;
    final salt = _fromHex(parts[3]);
    final expected = _fromHex(parts[4]);
    if (salt == null || expected == null) return false;
    final actual = _pbkdf2(utf8.encode(password), salt, iterations);
    return _constantTimeEquals(actual, expected);
  }

  static bool needsRehash(String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 5) return true;
    return (int.tryParse(parts[2]) ?? 0) < defaultIterations;
  }

  /// Ancien schéma de l'application : sha256("sel:motdepasse") en hexadécimal.
  /// Conservé UNIQUEMENT pour permettre la connexion puis la migration
  /// automatique vers PBKDF2 (aucun compte existant n'est perdu).
  static bool verifyLegacy(String password, String salt, String storedHash) {
    final h = sha256.convert(utf8.encode('$salt:$password')).toString();
    return _constantTimeEquals(utf8.encode(h), utf8.encode(storedHash));
  }

  static List<int> _pbkdf2(List<int> password, List<int> salt, int iterations) {
    // dkLen = hLen = 32 : un seul bloc suffit (RFC 8018).
    final hmac = Hmac(sha256, password);
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t;
  }

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static List<int>? _fromHex(String s) {
    if (s.isEmpty || s.length.isOdd) return null;
    final out = <int>[];
    for (var i = 0; i < s.length; i += 2) {
      final v = int.tryParse(s.substring(i, i + 2), radix: 16);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
