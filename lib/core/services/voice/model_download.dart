/// Señal esperada cuando el usuario cancela una descarga de modelo.
/// Se distingue de un fallo de red para no mostrar un error engañoso.
class ModelDownloadCancelled implements Exception {
  const ModelDownloadCancelled();

  @override
  String toString() => 'Model download cancelled';
}
