import 'dart:math';

import 'package:group_trip/data/firestore_schema.dart';

abstract class IdGenerator {
  String next({int length = 20});

  String inviteCode({int length = FirestoreSchema.inviteCodeMinLength});
}

class RandomIdGenerator implements IdGenerator {
  RandomIdGenerator([Random? random]) : _random = random ?? Random.secure();

  final Random _random;
  static const _idAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  @override
  String next({int length = 20}) => _pick(_idAlphabet, length);

  @override
  String inviteCode({int length = FirestoreSchema.inviteCodeMinLength}) =>
      _pick(_codeAlphabet, length);

  String _pick(String alphabet, int length) {
    return List.generate(
      length,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }
}

class SequentialIdGenerator implements IdGenerator {
  int _n = 0;

  @override
  String next({int length = 20}) {
    _n += 1;
    return 'id$_n';
  }

  @override
  String inviteCode({int length = FirestoreSchema.inviteCodeMinLength}) {
    _n += 1;
    return 'CODE${_n.toString().padLeft(2, '0')}';
  }
}
