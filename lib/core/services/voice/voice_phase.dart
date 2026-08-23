/// Fases compartidas por la superficie visual de conversación. El motor local
/// y el legado pueden mapear sus estados internos a este vocabulario sin
/// importarse entre sí.
enum VoicePhase {
  idle,
  listening,
  transcribing,
  thinking,
  speaking,
  toolCall,
  waitingPermission,
}
