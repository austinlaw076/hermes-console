import '../models/agent_profile.dart';
import '../models/bot_visual_identity.dart';
import '../models/profile_pet.dart';
import 'profile_pet_visual_adapter.dart';
import 'tui_gateway_client.dart';

typedef ReadProfilePet = Future<ProfilePetInfo> Function(String profile);
typedef SelectProfilePet = Future<bool> Function(String profile, String slug);
typedef DisableProfilePet = Future<bool> Function(String profile);
typedef MaterializeSelectedProfilePet =
    Future<ProfilePetVisual> Function(String profile, ProfilePetInfo info);

enum BotIdentityMutationStatus { applied, rolledBack, uncertain }

final class BotIdentityMutationResult {
  final BotIdentityMutationStatus status;
  final Object? failure;
  final Object? rollbackFailure;

  const BotIdentityMutationResult._(
    this.status, {
    this.failure,
    this.rollbackFailure,
  });

  const BotIdentityMutationResult.applied()
    : this._(BotIdentityMutationStatus.applied);

  const BotIdentityMutationResult.rolledBack(Object failure)
    : this._(BotIdentityMutationStatus.rolledBack, failure: failure);

  const BotIdentityMutationResult.uncertain(
    Object failure,
    Object rollbackFailure,
  ) : this._(
        BotIdentityMutationStatus.uncertain,
        failure: failure,
        rollbackFailure: rollbackFailure,
      );
}

/// Applies the three server-side stores that make up one Bot Mode identity.
///
/// Hermes deliberately keeps pet selection, the lightweight avatar raster,
/// and `ui_meta['hermes-bots']` in separate RPCs. This coordinator gives the
/// editor one result and compensates every store if a later write fails.
final class BotIdentityMutationService {
  final HermesDesktopProfileAssetsGateway assets;
  final ReadProfilePet readPet;
  final SelectProfilePet selectPet;
  final DisableProfilePet disablePet;
  final MaterializeSelectedProfilePet materializeSelectedPet;

  const BotIdentityMutationService({
    required this.assets,
    required this.readPet,
    required this.selectPet,
    required this.disablePet,
    required this.materializeSelectedPet,
  });

  Future<BotIdentityMutationResult> apply({
    required AgentProfile profile,
    required BotVisualIdentity target,
    String? title,
    required ProfilePetInfo previousPet,
    required AgentProfileAvatar? previousAvatar,
  }) async {
    final profileName = profile.name.trim();
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(profileName)) {
      throw ArgumentError.value(profile.name, 'profile', 'Invalid profile');
    }
    if (profile.hasAvatar && previousAvatar == null) {
      throw StateError('Cannot snapshot the current profile avatar');
    }

    final previousIdentity = _previousIdentity(profile, previousAvatar);

    try {
      AgentProfileAvatar? targetAvatar;
      if (target case PetSpriteIdentity(:final slug)) {
        final selected = await _selectAndVerify(profileName, slug);
        final visual = await materializeSelectedPet(profileName, selected);
        if (!visual.companion.isRemote ||
            !visual.companion.isValid ||
            visual.companion.slug != slug) {
          throw StateError('Selected pet visual does not match pet.info');
        }
        targetAvatar = AgentProfileAvatar.fromDataUri(
          visual.avatar.toDataUri(),
        );
      } else {
        await _disableAndVerify(profileName);
        targetAvatar = target is ProfileImageIdentity ? target.avatar : null;
      }

      if (targetAvatar != null && !_sameAvatar(targetAvatar, previousAvatar)) {
        await assets.setProfileAvatar(
          profile: profileName,
          dataUri: targetAvatar.toDataUri(),
        );
      } else if (targetAvatar == null && previousAvatar != null) {
        await assets.clearProfileAvatar(profileName);
      }

      await assets.saveProfileBotMeta(
        profile: profileName,
        title: title,
        identity: target,
      );
      return const BotIdentityMutationResult.applied();
    } catch (failure) {
      try {
        // The failing RPC may have reached Hermes before its response was
        // lost, so compensation restores all three stores, not only calls
        // that returned successfully. Asset -> metadata -> pet is deliberate.
        if (previousAvatar != null) {
          await assets.setProfileAvatar(
            profile: profileName,
            dataUri: previousAvatar.toDataUri(),
          );
        } else {
          await assets.clearProfileAvatar(profileName);
        }
        await assets.saveProfileBotMeta(
          profile: profileName,
          title: title == null ? null : (profile.botTitle ?? ''),
          identity: previousIdentity,
        );
        await _restorePet(profileName, previousPet);
        return BotIdentityMutationResult.rolledBack(failure);
      } catch (rollbackFailure) {
        return BotIdentityMutationResult.uncertain(failure, rollbackFailure);
      }
    }
  }

  BotVisualIdentity _previousIdentity(
    AgentProfile profile,
    AgentProfileAvatar? previousAvatar,
  ) {
    final resolved = BotVisualIdentity.resolve(
      profile,
      ProfilePetInfo.disabled,
      previousAvatar,
    );
    if (resolved != null) return resolved;
    return BotVisualIdentityState.rehydrate(
      profileName: profile.name,
      botMeta: profile.botModeUiMeta,
      hasAvatar: previousAvatar != null,
    ).identity;
  }

  Future<ProfilePetInfo> _selectAndVerify(String profile, String slug) async {
    if (!await selectPet(profile, slug)) {
      throw StateError('Hermes rejected pet selection');
    }
    final current = await readPet(profile);
    if (!current.enabled || current.slug != slug) {
      throw StateError('Hermes did not activate the selected pet');
    }
    return current;
  }

  Future<void> _disableAndVerify(String profile) async {
    if (!await disablePet(profile)) {
      throw StateError('Hermes rejected pet disable');
    }
    final current = await readPet(profile);
    if (current.enabled) {
      throw StateError('Hermes kept a pet active');
    }
  }

  Future<void> _restorePet(String profile, ProfilePetInfo previous) async {
    if (previous.enabled && previous.slug.isNotEmpty) {
      await _selectAndVerify(profile, previous.slug);
    } else {
      await _disableAndVerify(profile);
    }
  }
}

bool _sameAvatar(AgentProfileAvatar left, AgentProfileAvatar? right) {
  if (right == null ||
      left.mimeType != right.mimeType ||
      left.bytes.length != right.bytes.length) {
    return false;
  }
  for (var index = 0; index < left.bytes.length; index++) {
    if (left.bytes[index] != right.bytes[index]) return false;
  }
  return true;
}
