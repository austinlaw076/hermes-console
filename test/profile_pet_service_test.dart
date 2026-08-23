import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/profile_pet.dart';
import 'package:hermes_android/core/services/profile_pet_service.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';

class _RecordingPetGateway implements HermesDesktopPetGateway {
  final StreamController<TuiGatewayEvent> _events =
      StreamController<TuiGatewayEvent>.broadcast();

  final List<({String profile, String? knownRevision})> infoCalls = [];
  final List<({String profile, String slug})> selectCalls = [];
  final List<String> disableCalls = [];

  @override
  Stream<TuiGatewayEvent> get events => _events.stream;

  void emitChanged() {
    _events.add(
      const TuiGatewayEvent(
        type: 'pet.changed',
        sessionId: '',
        payload: {'enabled': true, 'slug': 'zoro'},
      ),
    );
  }

  Future<void> close() => _events.close();

  @override
  Future<ProfilePetInfo> profilePetInfo({
    String profile = '',
    String? knownRevision,
  }) async {
    infoCalls.add((profile: profile, knownRevision: knownRevision));
    return const ProfilePetInfo(enabled: true, slug: 'zoro');
  }

  @override
  Future<ProfilePetGallery> profilePetGallery({
    String profile = '',
    bool localOnly = false,
  }) async => const ProfilePetGallery(enabled: true, active: 'zoro', pets: []);

  @override
  Future<String?> profilePetThumb({
    String profile = '',
    required String slug,
    String url = '',
  }) async => null;

  @override
  Future<ProfilePetSelection> profilePetSelect({
    String profile = '',
    required String slug,
  }) async {
    selectCalls.add((profile: profile, slug: slug));
    return ProfilePetSelection(slug: slug);
  }

  @override
  Future<bool> profilePetDisable({String profile = ''}) async {
    disableCalls.add(profile);
    return true;
  }
}

void main() {
  test(
    'read-only permite pet.info y pet.changed pero bloquea select y disable',
    () async {
      final gateway = _RecordingPetGateway();
      addTearDown(gateway.close);
      final service = ProfilePetService(gateway, allowWrites: false);

      final changed = service.petChanged.first;
      gateway.emitChanged();
      await changed;

      final info = await service.activePet(
        profile: 'alpha',
        knownRevision: 'sha256:r1',
      );
      expect(info?.slug, 'zoro');
      expect(gateway.infoCalls, [
        (profile: 'alpha', knownRevision: 'sha256:r1'),
      ]);

      expect(await service.selectPet(profile: 'alpha', slug: 'zoro'), isFalse);
      expect(await service.disablePet(profile: 'alpha'), isFalse);
      expect(gateway.selectCalls, isEmpty);
      expect(gateway.disableCalls, isEmpty);
    },
  );
}
