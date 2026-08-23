import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/agent_profile.dart';
import 'package:hermes_android/core/models/bot_visual_identity.dart';
import 'package:hermes_android/core/models/profile_pet.dart';
import 'package:hermes_android/core/companion/models/companion.dart';
import 'package:hermes_android/core/companion/models/companion_animation_state.dart';
import 'package:hermes_android/core/services/bot_identity_mutation_service.dart';
import 'package:hermes_android/core/services/profile_pet_visual_adapter.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';

const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Companion _remoteCompanion(String slug) => Companion(
  slug: slug,
  name: slug,
  author: 'Hermes',
  license: 'test',
  spritesheetAsset: '/tmp/$slug.png',
  frameWidth: 1,
  frameHeight: 1,
  cols: 1,
  rows: 1,
  fps: 8,
  states: const {
    CompanionAnimationState.idle: RowSpec(row: 0, frameCount: 1, loop: true),
  },
  origin: CompanionOrigin.remote,
);

class _Assets implements HermesDesktopProfileAssetsGateway {
  final calls = <String>[];
  final titles = <String?>[];
  bool failMeta = false;
  bool failRestore = false;
  AgentProfileAvatar? avatar;

  @override
  Future<AgentProfileAvatar?> profileAvatar(String profileName) async => avatar;

  @override
  Future<void> saveProfileBotMeta({
    required String profile,
    String? title,
    String? shape,
    String? colorHex,
    bool? hidden,
    bool? pinned,
    BotVisualIdentity? identity,
  }) async {
    calls.add('meta:${identity.runtimeType}');
    titles.add(title);
    if (failMeta) {
      failMeta = false;
      throw const TuiGatewayRpcError('profiles.configure', 'failed');
    }
    if (failRestore) {
      throw const TuiGatewayRpcError('profiles.configure', 'restore failed');
    }
  }

  @override
  Future<void> setProfileAvatar({
    required String profile,
    required String dataUri,
  }) async {
    AgentProfileAvatar.fromDataUri(dataUri);
    calls.add('asset:set');
  }

  @override
  Future<void> clearProfileAvatar(String profile) async {
    calls.add('asset:clear');
  }
}

void main() {
  late _Assets assets;
  late List<String> petCalls;
  late ProfilePetInfo pet;
  late BotIdentityMutationService service;

  setUp(() {
    assets = _Assets();
    petCalls = [];
    pet = ProfilePetInfo.disabled;
    service = BotIdentityMutationService(
      assets: assets,
      readPet: (_) async => pet,
      selectPet: (_, slug) async {
        petCalls.add('select:$slug');
        pet = ProfilePetInfo(enabled: true, slug: slug);
        return true;
      },
      disablePet: (_) async {
        petCalls.add('disable');
        pet = ProfilePetInfo.disabled;
        return true;
      },
      materializeSelectedPet: (_, info) async {
        petCalls.add('materialize:${info.slug}');
        return ProfilePetVisual(
          companion: _remoteCompanion(info.slug),
          avatar: AgentProfileAvatar.fromDataUri(_png),
        );
      },
    );
  });

  test(
    'photo disables pet, writes raster, then publishes photo metadata',
    () async {
      pet = const ProfilePetInfo(enabled: true, slug: 'old');
      final avatar = AgentProfileAvatar.fromDataUri(_png);

      final result = await service.apply(
        profile: const AgentProfile(name: 'nimbus'),
        target: ProfileImageIdentity(avatar: avatar, legacy: false),
        previousPet: pet,
        previousAvatar: null,
      );

      expect(result.status, BotIdentityMutationStatus.applied);
      expect(petCalls, ['disable']);
      expect(assets.calls, ['asset:set', 'meta:ProfileImageIdentity']);
    },
  );

  test(
    'using an existing photo does not rewrite the unchanged asset',
    () async {
      final avatar = AgentProfileAvatar.fromDataUri(_png);

      final result = await service.apply(
        profile: const AgentProfile(name: 'nimbus', hasAvatar: true),
        target: ProfileImageIdentity(avatar: avatar, legacy: false),
        previousPet: const ProfilePetInfo(enabled: true, slug: 'old'),
        previousAvatar: avatar,
      );

      expect(result.status, BotIdentityMutationStatus.applied);
      expect(petCalls, ['disable']);
      expect(assets.calls, ['meta:ProfileImageIdentity']);
    },
  );

  test('refuses mutation when an existing avatar cannot be snapshotted', () {
    expect(
      () => service.apply(
        profile: const AgentProfile(name: 'nimbus', hasAvatar: true),
        target: ClassicFaceIdentity(shape: 'cloud', colorHex: '#38bdf8'),
        previousPet: ProfilePetInfo.disabled,
        previousAvatar: null,
      ),
      throwsStateError,
    );
    expect(petCalls, isEmpty);
    expect(assets.calls, isEmpty);
  });

  test(
    'face disables pet and clears raster before publishing shape metadata',
    () async {
      final result = await service.apply(
        profile: const AgentProfile(name: 'nimbus', hasAvatar: true),
        target: ClassicFaceIdentity(shape: 'cloud', colorHex: '#38bdf8'),
        previousPet: const ProfilePetInfo(enabled: true, slug: 'old'),
        previousAvatar: AgentProfileAvatar.fromDataUri(_png),
      );

      expect(result.status, BotIdentityMutationStatus.applied);
      expect(petCalls, ['disable']);
      expect(assets.calls, ['asset:clear', 'meta:ClassicFaceIdentity']);
    },
  );

  test('pet verifies selection before writing its lightweight frame', () async {
    final result = await service.apply(
      profile: const AgentProfile(name: 'nimbus'),
      target: const PetSpriteIdentity(slug: 'zoro', revision: 'rev-1'),
      previousPet: ProfilePetInfo.disabled,
      previousAvatar: null,
    );

    expect(result.status, BotIdentityMutationStatus.applied);
    expect(petCalls, ['select:zoro', 'materialize:zoro']);
    expect(assets.calls, ['asset:set', 'meta:PetSpriteIdentity']);
  });

  test(
    'pet materialization failure restores prior selection before publish',
    () async {
      pet = const ProfilePetInfo(enabled: true, slug: 'old');
      service = BotIdentityMutationService(
        assets: assets,
        readPet: (_) async => pet,
        selectPet: (_, slug) async {
          petCalls.add('select:$slug');
          pet = ProfilePetInfo(enabled: true, slug: slug);
          return true;
        },
        disablePet: (_) async {
          petCalls.add('disable');
          pet = ProfilePetInfo.disabled;
          return true;
        },
        materializeSelectedPet: (_, _) async =>
            throw const FormatException('invalid remote atlas'),
      );

      final result = await service.apply(
        profile: const AgentProfile(
          name: 'nimbus',
          botModeUiMeta: {
            'shape': 'cloud',
            'color': '#38bdf8',
            'imageKind': 'shape',
            'custom': true,
          },
        ),
        target: const PetSpriteIdentity(slug: 'zoro'),
        previousPet: pet,
        previousAvatar: null,
      );

      expect(result.status, BotIdentityMutationStatus.rolledBack);
      expect(petCalls, ['select:zoro', 'select:old']);
      expect(assets.calls, ['asset:clear', 'meta:ClassicFaceIdentity']);
    },
  );

  test(
    'partial failure compensates in reverse and never reports success',
    () async {
      assets.failMeta = true;
      final previousAvatar = AgentProfileAvatar.fromDataUri(_png);
      final result = await service.apply(
        profile: const AgentProfile(
          name: 'nimbus',
          hasAvatar: true,
          botModeUiMeta: {
            'title': 'Nimbus anterior',
            'shape': 'cloud',
            'color': '#38bdf8',
            'imageKind': 'photo',
          },
        ),
        target: ClassicFaceIdentity(shape: 'hexagon', colorHex: '#f97316'),
        title: 'Nimbus nuevo',
        previousPet: const ProfilePetInfo(enabled: true, slug: 'old'),
        previousAvatar: previousAvatar,
      );

      expect(result.status, BotIdentityMutationStatus.rolledBack);
      expect(petCalls, ['disable', 'select:old']);
      expect(assets.calls, [
        'asset:clear',
        'meta:ClassicFaceIdentity',
        'asset:set',
        'meta:ProfileImageIdentity',
      ]);
      expect(assets.titles, ['Nimbus nuevo', 'Nimbus anterior']);
    },
  );

  test('failed compensation exposes uncertain state', () async {
    assets
      ..failMeta = true
      ..failRestore = true;
    final result = await service.apply(
      profile: const AgentProfile(name: 'nimbus'),
      target: ClassicFaceIdentity(shape: 'cloud', colorHex: '#38bdf8'),
      previousPet: ProfilePetInfo.disabled,
      previousAvatar: null,
    );

    expect(result.status, BotIdentityMutationStatus.uncertain);
  });
}
