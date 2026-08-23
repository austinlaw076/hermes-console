import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../companion/data/companion_repository.dart';
import '../companion/models/companion.dart';
import '../companion/models/companion_animation_state.dart';
import '../models/agent_profile.dart';
import '../models/profile_pet.dart';

/// Mascota oficial ya validada para las dos representaciones de Bot Mode:
/// el atlas animado de la preview y el frame ligero del avatar del roster.
final class ProfilePetVisual {
  final Companion companion;
  final AgentProfileAvatar avatar;

  const ProfilePetVisual({required this.companion, required this.avatar});
}

/// Frontera inyectable para materializar una revisión oficial de `pet.info`.
///
/// No selecciona mascotas ni hace red: consume exclusivamente el payload
/// revisionado que el llamador obtuvo del Gateway.
abstract interface class ProfilePetVisualMaterializer {
  Future<ProfilePetVisual> materialize(
    ProfilePetInfo info, {
    required String connectionId,
    required String profileId,
  });
}

/// Adapta el contrato Companion existente a la identidad visual de un bot.
/// Reutiliza su validación/caché y recorta el frame 0 de la fila `idle`; no
/// crea un segundo formato de sprites ni interpreta SVG o contenido remoto.
final class ProfilePetVisualAdapter implements ProfilePetVisualMaterializer {
  final CompanionRepository _repository;

  ProfilePetVisualAdapter({CompanionRepository? repository})
    : _repository =
          repository ??
          CompanionRepository(importedRootProvider: _companionRoot);

  static Future<Directory> _companionRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/companions');
  }

  @override
  Future<ProfilePetVisual> materialize(
    ProfilePetInfo info, {
    required String connectionId,
    required String profileId,
  }) async {
    final companion = await _repository.materializeProfilePet(
      info,
      connectionId: connectionId,
      profileId: profileId,
    );
    final avatar = await _idleFrameAvatar(companion);
    return ProfilePetVisual(companion: companion, avatar: avatar);
  }

  Future<AgentProfileAvatar> _idleFrameAvatar(Companion companion) async {
    if (!companion.isRemote || !companion.isValid || !companion.isFileBacked) {
      throw const FormatException('Pet companion is not a validated remote');
    }
    final idle = companion.rowFor(CompanionAnimationState.idle);
    if (idle == null || idle.row < 0 || idle.row >= companion.rows) {
      throw const FormatException('Pet companion has no valid idle row');
    }

    final bytes = await File(companion.spritesheetAsset).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    ui.Image? source;
    ui.Image? frame;
    ui.Picture? picture;
    try {
      source = (await codec.getNextFrame()).image;
      final frameWidth = companion.frameWidth;
      final frameHeight = companion.frameHeight;
      final sourceLeft = 0.0;
      final sourceTop = (idle.row * frameHeight).toDouble();
      if (frameWidth <= 0 ||
          frameHeight <= 0 ||
          sourceLeft + frameWidth > source.width ||
          sourceTop + frameHeight > source.height) {
        throw const FormatException('Pet idle frame is outside the atlas');
      }

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(
          sourceLeft,
          sourceTop,
          frameWidth.toDouble(),
          frameHeight.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, frameWidth.toDouble(), frameHeight.toDouble()),
        ui.Paint(),
      );
      picture = recorder.endRecording();
      frame = await picture.toImage(frameWidth, frameHeight);
      final png = await frame.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw const FormatException('Pet idle frame could not be encoded');
      }
      final dataUri =
          'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}';
      // Reaplica los límites/MIME/magic bytes de todo avatar entrante/saliente.
      return AgentProfileAvatar.fromDataUri(dataUri);
    } finally {
      picture?.dispose();
      frame?.dispose();
      source?.dispose();
      codec.dispose();
    }
  }
}
